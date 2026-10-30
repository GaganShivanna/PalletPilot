# PalletPilot Backend API Audit (for iOS)

Date: 2026-10-28. Sources: `docs/FRONTEND_HANDOFF.md`, `docs/openapi.json`,
`backend/app/routes/*`, `backend/app/schemas/*`, `backend/app/services/*`,
`backend/tests/test_phase2.py`, `backend/tests/test_jobs.py`.
Verification: 12/12 collectible unit tests pass in this session
(`test_providers.py` + `test_persistence.py`); `test_jobs.py`/`test_phase2.py`
do not collect here because `backend/.venv` lacks `cv2` (see §6).

## 1. Architecture summary

FastAPI service (`backend/app/main.py`, `create_app`), no auth. Routers:
`health`, `jobs`, `pallets`, `items`. SQLite metadata (`meta.db` via
`app/services/persistence.py`) + files on disk under `DATA_DIR`.
Single background worker (`JobQueue`) runs `run_pipeline` off the event loop:
upload → frame sampling (OpenCV, 2–5 fps clamp) → provider segmentation →
identification (transient retry) → photos with per-item frame fallback →
fixture pricing → deterministic listing drafts → item persistence.
`AI_PROVIDER` defaults to `mock`; real adapters raise `ProviderUnavailable`.
All mock output is labeled (`provider="mock"`, `needs_review=true`,
`price_source="mock_fixture"`/`"none"`, `Demo draft: …` marker).

## 2. Documented-vs-implemented comparison

| # | Claim (document source) | Code reality | Verdict |
|---|---|---|---|
| 1 | `POST/GET /pallets` (`docs/REPO_MAP.md` Features + Layout) | `backend/app/routes/pallets.py` has `POST ""` only; `openapi.json` paths confirm `/pallets` supports `post` only. **No list-pallets endpoint exists.** | REPO_MAP WRONG; handoff (which omits it) is correct |
| 2 | `GET /jobs`, `GET /jobs/{id}`, file serving (handoff) | `routes/jobs.py:62,67,72` implement all three; openapi confirms | MATCH |
| 3 | `POST /jobs → 202`, multipart `video` + optional `pallet_id` (handoff) | `routes/jobs.py:26-59`: `video: UploadFile`, `pallet_id: str \| None = Form(None)`; tests assert 202 | MATCH |
| 4 | Upload errors `415` bad extension, `413` over `MAX_UPLOAD_MB`, `404` unknown pallet, `409` pallet-has-job (handoff) | `routes/jobs.py:30-40,52-54` raise exactly these; `ALLOWED_VIDEO_EXTENSIONS = {.mp4,.mov,.m4v,.avi,.webm,.mkv}`; `test_jobs.py` asserts 415 + traversal-404 | MATCH |
| 5 | `POST /pallets → 201`, optional `job_id` claims items; `404` unknown job, `409` already-linked (handoff) | `routes/pallets.py:57-77` + `claim_job_items`; `test_phase2.py` asserts claim, 409, 404 | MATCH |
| 6 | `GET /pallets/{id} → PalletSummary` with estimates (handoff) | `routes/pallets.py:80-85` returns `summarize(...)`; `PalletSummary` has `estimated_revenue/estimated_fees/projected_profit/fee_rate/unpriced_item_count/estimates` | MATCH |
| 7 | `GET /pallets/{id}/items → Item[]` stable id order (handoff) | `routes/pallets.py:88-92`; `items_for_pallet … ORDER BY id` | MATCH |
| 8 | `PATCH /items/{id}` edits 7 fields; explicit-null clears price; `422` on negative price / bad condition; `404` unknown (handoff) | `routes/items.py:25-31` (provided-fields-only via `model_fields_set`); `schemas/items.py` validators; `test_phase2.py::test_patch_validation_and_404s` | MATCH |
| 9 | `GET /items/{id}` round-trip read (handoff) | `routes/items.py:20-22` | MATCH |
| 10 | `GET /pallets/{id}/export → text/csv`, 10 columns, `image_url` singular, formula-guard, empty-not-zero prices (handoff) | `routes/pallets.py:95-104`; `services/exports.py: COLUMNS` lists exactly `item_id,title,description,category,brand,condition,suggested_price,currency,image_url,review_status`; `test_phase2.py` asserts header row + `'=…` escaping | MATCH |
| 11 | Job status flow `queued → sampling_frames → segmenting → identifying → generating_photos → generating_listings → completed/failed` (handoff) | `schemas/jobs.py: JobStatus` (same 8 values, same order); `pipeline.py:62-101` transitions in that order | MATCH |
| 12 | Pallet `status: empty \| processing \| ready \| failed` (handoff) | Derived in `routes/pallets.py:27-37` from job link + job status, not stored | MATCH |
| 13 | Item ids look like `<job_id>:item_0`, `:` URL-safe (handoff) | `pipeline.py:85` `f"{job_id}:{product.item_id}"`; tests interpolate raw into paths | MATCH (client must NOT percent-encode `:`) |
| 14 | Suggested poll: every 1 s, 60 s cap (handoff) | Advisory only; no server contract. `GET /jobs` has no filters/pagination | MATCH (client-side policy) |
| 15 | Base URL `http://127.0.0.1:8000`, no auth, CORS allow-list incl. localhost (handoff) | `config.py: cors_origins`; no auth middleware anywhere; run cmd in `backend/AGENTS.md` | MATCH |

## 3. Discrepancies and corrections

- **D1 (doc bug, load-bearing): `docs/REPO_MAP.md` claims `GET /pallets`. It does not exist** — in code, in `openapi.json`, or in tests. iOS must not implement a pallet-list network call; see `INTEGRATION_GAPS.md`.
- **D2 (staleness risk): `Job.listings` is a completion-time snapshot** (`pipeline.py:99`, `jobs.py: listings_json`). Later `PATCH /items/{id}` updates the items table only, so `GET /jobs/{id}.listings` goes stale after any edit. iOS must treat pallet-items endpoints as current truth, job listings as history.
- **D3 (trailing slash): canonical paths have NO trailing slash** (`@router.post("")` + prefix; tests call `/jobs`, `/pallets`). iOS must not append `/` — FastAPI may 307-redirect and drop POST bodies.
- **D4 (status codes): `openapi.json` is the tiebreaker** where prose is vague: `POST /pallets → 201`, `POST /jobs → 202`, `PATCH /items → 200`, CSV `→ 200`. Error bodies are `{"detail": "<msg>"}` (FastAPI default), except `422` which is the standard validation envelope.

## 4. Verified endpoint inventory (11 routes, code-grounded)

`GET /health`; `POST /jobs`; `GET /jobs`; `GET /jobs/{job_id}`;
`GET /jobs/{job_id}/files/{file_path}`; `POST /pallets`;
`GET /pallets/{pallet_id}`; `GET /pallets/{pallet_id}/items`;
`GET /pallets/{pallet_id}/export`; `GET /items/{item_id}`;
`PATCH /items/{item_id}`. Full contracts in `API_CONTRACTS.md`.

## 5. Serialization facts (verified in schemas)

- Dates: ISO 8601 `date-time` with UTC offset + microseconds (SQLite stores `datetime.now(UTC).isoformat()`; Pydantic emits the same shape). Client needs fractional-seconds ISO8601 parsing.
- Money: `float` dollars, `currency` default `"USD"`; `suggested_price` nullable — null means unknown, never 0.
- Ids: pallets/jobs are `uuid4().hex` (32 hex chars, no dashes); items are `<jobhex>:item_<N>`.
- Media: `image_urls` / `original_image_url` are **relative** paths (`/jobs/<id>/files/...`); client prefixes the base URL. `price_source`: `mock_fixture | none`; `price_type`: `asking | unknown`; `condition ∈ {new, like_new, good, fair, poor, parts, unknown}`.
- `Pallet.status` and `item_count`/`priced_item_count` are server-derived; never sent by the client.

## 6. Test-evidence note

This session: `12 passed` (`test_providers`, `test_persistence`). `test_jobs.py`
and `test_phase2.py` fail at **collection** here (`ModuleNotFoundError: cv2` —
`backend/.venv` lacks `opencv-python-headless`). The 25/25 claim in
`docs/CURRENT_STATUS.md` is therefore **not independently corroborated in this
session**; endpoint behavior above is grounded in route/schema/service source
and `openapi.json`, not in a green test run. Recommend one unsandboxed run of
`cd backend && .venv/bin/python -m pytest -q` with full deps before iOS
integration testing.

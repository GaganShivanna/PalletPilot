# PalletPilot API Contracts (verified, for iOS)

Base URL (local): `http://127.0.0.1:8000`. Auth: none. No versioning prefix.
All JSON uses ISO 8601 date-time strings (UTC, fractional seconds) and float
dollars (`currency: "USD"`). Error bodies: `{"detail": "<message>"}` except
`422` (FastAPI validation envelope). Canonical paths have **no trailing slash**.
Media URLs in payloads are **relative** — prefix with the base URL.
Sources: `backend/app/routes/*`, `backend/app/schemas/*`, `docs/openapi.json`,
`backend/tests/test_phase2.py`. No endpoint below is assumed: each maps to a
route function listed in Related files.

## Endpoint index

| # | Method | Path | Purpose | Req content type | Codes |
|---|---|---|---|---|---|
| 1 | GET | `/health` | Liveness | — | 200 |
| 2 | POST | `/pallets` | Create pallet, optionally claim a job's items | `application/json` | 201, 404, 409, 422 |
| 3 | POST | `/jobs` | Upload video, enqueue analysis | `multipart/form-data` | 202, 404, 409, 413, 415, 422 |
| 4 | GET | `/jobs` | List jobs, newest first | — | 200 |
| 5 | GET | `/jobs/{job_id}` | Job detail / poll processing status | — | 200, 404 |
| 6 | GET | `/jobs/{job_id}/files/{file_path}` | Serve frame/photo bytes | — | 200, 404 |
| 7 | GET | `/pallets/{pallet_id}` | Pallet detail + financial estimates | — | 200, 404 |
| 8 | GET | `/pallets/{pallet_id}/items` | Pallet inventory, stable id order | — | 200, 404 |
| 9 | GET | `/items/{item_id}` | Single item (edit-form round-trip) | — | 200, 404 |
| 10 | PATCH | `/items/{item_id}` | Edit listing fields | `application/json` | 200, 404, 422 |
| 11 | GET | `/pallets/{pallet_id}/export` | CSV download of listings | — | 200, 404 |

No query parameters exist on any endpoint. No pagination. No DELETE/PUT anywhere.

## 1. `GET /health` → 200

Purpose: liveness probe. Related: `backend/app/routes/health.py`.
No auth, no parameters.

```json
{ "status": "ok" }
```

## 2. `POST /pallets` → 201 (`Pallet`)

Purpose: create a pallet. Optional `job_id` links an existing unlinked job and
claims its already-processed items (no reprocessing).
Related: `backend/app/routes/pallets.py:57`, `backend/app/schemas/pallets.py`,
`backend/app/services/persistence.py` (`insert_pallet`, `claim_job_items`).

Request `application/json` (`PalletCreate`; all fields optional):

```json
{ "name": "Bin 12", "purchase_cost": 20.0, "additional_costs": 5.0, "job_id": null }
```

Response `Pallet` (status/counts/dates are server-derived):

```json
{
  "id": "9f3c1a2b3c4d5e6f7a8b9c0d1e2f3a4b",
  "name": "Bin 12",
  "purchase_cost": 20.0,
  "additional_costs": 5.0,
  "job_id": null,
  "status": "empty",
  "item_count": 0,
  "priced_item_count": 0,
  "created_at": "2026-10-28T12:00:00.123456+00:00",
  "updated_at": "2026-10-28T12:00:00.123456+00:00"
}
```

Errors: `404` unknown `job_id`; `409` job already linked to a pallet;
`422` negative costs. See `test_phase2.py::test_pallet_claims_completed_job_without_reprocessing`.

## 3. `POST /jobs` → 202 (`JobCreated`)

Purpose: upload a video and enqueue the analysis pipeline.
Related: `backend/app/routes/jobs.py:26`, `backend/app/services/jobs.py`,
`backend/app/config.py` (`max_upload_mb`, default 500).

Request `multipart/form-data` (`video` part required, `pallet_id` form field optional):

```bash
curl -X POST http://127.0.0.1:8000/jobs \
  -F video=@unboxing.mp4 -F pallet_id=9f3c1a2b3c4d5e6f7a8b9c0d1e2f3a4b
```

Response:

```json
{ "id": "abc123def4567890abc123def4567890", "status": "queued" }
```

Errors: `415` extension not in `{.mp4,.mov,.m4v,.avi,.webm,.mkv}`;
`413` body exceeds `MAX_UPLOAD_MB`; `404` unknown pallet; `409` pallet already
has a job. Missing `video` part → `422`.

## 4. `GET /jobs` → 200 (`Job[]`)

Purpose: list jobs, newest first (`ORDER BY created_at DESC`). Related:
`backend/app/routes/jobs.py:62`. Element shape = §5. No parameters.

## 5. `GET /jobs/{job_id}` → 200 (`Job`)

Purpose: poll processing until `status` is `completed` or `failed` (server
advice: every 1 s, 60 s cap — client-side policy, not a contract).
Related: `backend/app/routes/jobs.py:67`, `backend/app/schemas/jobs.py`,
`backend/app/services/pipeline.py`.

`status` enum: `queued | sampling_frames | segmenting | identifying |
generating_photos | generating_listings | completed | failed`.

Completed job (from `test_phase2.py::test_end_to_end_mock_workflow` — 2 s clip
at `sample_fps=3` yields `frame_count: 6`, 3 listings):

```json
{
  "id": "abc123def4567890abc123def4567890",
  "status": "completed",
  "created_at": "2026-10-28T12:00:00.123456+00:00",
  "updated_at": "2026-10-28T12:00:05.123456+00:00",
  "video_filename": "video.mp4",
  "frame_count": 6,
  "listings": [
    {
      "item_id": "abc123def4567890abc123def4567890:item_0",
      "title": "Acme Cordless Drill",
      "description": "Acme Cordless Drill (Power Tools). Brand: Acme. Observed condition: good. Functionality untested; sold as pictured. Demo draft: attributes are mocked fixture data — verify before posting.",
      "category": "Power Tools",
      "brand": "Acme",
      "condition": "good",
      "price": { "amount": 45.0, "currency": "USD" },
      "image_urls": ["/jobs/abc123def4567890abc123def4567890/files/photos/item_0_0.jpg"],
      "confidence": 0.85,
      "needs_review": true,
      "review_reasons": ["mock identification: not verified against imagery"]
    }
  ],
  "error": null
}
```

Failed job: same shape with `"status": "failed"`, `"error": "Could not open video: video.mp4"`.
Unknown id: `404 {"detail": "Job not found"}`.
**Caution:** `listings` is a completion-time snapshot; after any item edit it is
stale (see `BACKEND_API_AUDIT.md` D2). Current per-item truth lives in §8.

## 6. `GET /jobs/{job_id}/files/{file_path}` → 200 (binary)

Purpose: serve frame/photo bytes under the job dir (`image_urls`,
`original_image_url` resolve here). Related: `backend/app/routes/jobs.py:72`.
Content type varies (JPEG). Path traversal or missing file → `404`.

## 7. `GET /pallets/{pallet_id}` → 200 (`PalletSummary`)

Purpose: pallet detail + projected financials. **All money is an estimate**
(`estimates: true`); unpriced items are excluded from revenue and counted in
`unpriced_item_count`, never $0. Related: `backend/app/routes/pallets.py:80`,
`backend/app/services/financials.py`, `backend/app/schemas/pallets.py`.

```json
{
  "pallet": {
    "id": "9f3c1a2b3c4d5e6f7a8b9c0d1e2f3a4b",
    "name": "Demo pallet",
    "purchase_cost": 20.0,
    "additional_costs": 5.0,
    "job_id": "abc123def4567890abc123def4567890",
    "status": "ready",
    "item_count": 3,
    "priced_item_count": 2,
    "created_at": "2026-10-28T12:00:00.123456+00:00",
    "updated_at": "2026-10-28T12:00:05.123456+00:00"
  },
  "estimated_revenue": 77.5,
  "estimated_fees": 10.07,
  "projected_profit": 42.43,
  "fee_rate": 0.13,
  "unpriced_item_count": 1,
  "estimates": true
}
```

(`77.5 = 45.0 + 32.5` mock fixtures; fees `round(77.5 × 0.13, 2)`;
profit `round(revenue − fees − purchase − additional, 2)` — `financials.py`.)
`status` is derived: `empty` (no job) | `processing` | `ready` | `failed`.
Unknown pallet: `404`. Verified in `test_end_to_end_mock_workflow` asserts.

## 8. `GET /pallets/{pallet_id}/items` → 200 (`Item[]`)

Purpose: pallet inventory in stable id order. Related:
`backend/app/routes/pallets.py:88`, `backend/app/schemas/items.py`.

```json
[
  {
    "id": "abc123def4567890abc123def4567890:item_0",
    "pallet_id": "9f3c1a2b3c4d5e6f7a8b9c0d1e2f3a4b",
    "job_id": "abc123def4567890abc123def4567890",
    "track_id": "track_00003",
    "title": "Acme Cordless Drill",
    "description": "Acme Cordless Drill (Power Tools). … Demo draft: …",
    "category": "Power Tools",
    "brand": "Acme",
    "condition": "good",
    "suggested_price": 45.0,
    "currency": "USD",
    "price_source": "mock_fixture",
    "price_confidence": 0.4,
    "price_type": "asking",
    "original_image_url": "/jobs/abc123def4567890abc123def4567890/files/frames/frame_00003.jpg",
    "image_urls": ["/jobs/abc123def4567890abc123def4567890/files/photos/item_0_0.jpg"],
    "confidence": 0.85,
    "needs_review": true,
    "review_reasons": ["mock identification: not verified against imagery"],
    "provider": "mock",
    "created_at": "2026-10-28T12:00:05.123456+00:00",
    "updated_at": "2026-10-28T12:00:05.123456+00:00"
  },
  {
    "id": "abc123def4567890abc123def4567890:item_2",
    "title": "Unidentified sealed box",
    "brand": null,
    "category": "Uncategorized",
    "condition": "unknown",
    "suggested_price": null,
    "price_source": "none",
    "price_confidence": null,
    "price_type": "unknown",
    "confidence": 0.1,
    "needs_review": true,
    "provider": "mock"
  }
]
```

Field notes: `brand`, `suggested_price`, `price_confidence`,
`original_image_url` are nullable; `description` defaults `""`;
`condition` defaults `"unknown"`; fixed vocabularies —
`condition ∈ {new, like_new, good, fair, poor, parts, unknown}`,
`price_source ∈ {mock_fixture, none}`, `price_type ∈ {asking, unknown}`.
Unknown pallet: `404`.

## 9. `GET /items/{item_id}` → 200 (`Item`)

Purpose: read one item (edit-form round-trip). Related:
`backend/app/routes/items.py:20`. Shape = §8 element. `:` in ids is URL-safe —
do not percent-encode. Unknown id: `404`.

## 10. `PATCH /items/{item_id}` → 200 (`Item`)

Purpose: edit listing fields. Only provided keys change; explicit
`"suggested_price": null` clears the price. Related:
`backend/app/routes/items.py:25`, `backend/app/schemas/items.py: ItemPatch`.

Editable keys (7, all optional): `title, description, category, brand,
condition, suggested_price, needs_review`. Everything else (`image_urls`,
`price_source`, `confidence`, `review_reasons`, `provider`, …) is read-only.

```bash
curl -X PATCH http://127.0.0.1:8000/items/abc123…:item_2 \
  -H 'Content-Type: application/json' \
  -d '{"suggested_price": 10.0, "needs_review": false}'
```

Errors: `404` unknown id; `422` negative `suggested_price` or `condition`
outside the 7-value vocabulary. Verified in
`test_phase2.py::test_patch_validation_and_404s` (incl. null-clear round-trip).

## 11. `GET /pallets/{pallet_id}/export` → 200 (`text/csv`)

Purpose: UTF-8 CSV download (`Content-Disposition: attachment`,
`filename="pallet-<id>.csv"`). Related: `backend/app/routes/pallets.py:95`,
`backend/app/services/exports.py`.

Columns (exact order): `item_id,title,description,category,brand,condition,
suggested_price,currency,image_url,review_status`.
`image_url` = first `image_urls` entry or empty; `review_status` =
`needs_review|approved`; missing prices are empty cells; cells starting with
`= + - @` (or tab/CR) are `'`-prefixed. Unknown pallet: `404`.

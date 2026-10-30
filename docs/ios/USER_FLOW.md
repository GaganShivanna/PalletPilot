# PalletPilot iOS User Flow (backend-grounded)

Every screen below maps to endpoints verified in `API_CONTRACTS.md`. Where no
endpoint exists, the screen is marked LOCAL-ONLY and the gap is filed in
`INTEGRATION_GAPS.md`. Assumed backend flow (verified in
`backend/app/services/pipeline.py`, `test_phase2.py::test_end_to_end_mock_workflow`):

Create pallet → upload video → poll status → retrieve inventory → review/edit
items → view profit → export listings.

## Flow A — New pallet from video (primary)

1. **Create pallet** — `POST /pallets` `{name, purchase_cost, additional_costs}` → store returned `id` on-device. (`status: "empty"`)
2. **Upload video** — `POST /jobs` multipart (`video` + `pallet_id` form field) → store `job.id`. (Alternative order: upload first, then `POST /pallets` with `{"job_id": …}` to claim — Flow B.)
3. **Processing screen** — poll `GET /jobs/{job_id}` (~1 s, 60 s cap per server advice) and render the 8-state machine: `queued → sampling_frames → segmenting → identifying → generating_photos → generating_listings → completed/failed`. Show `frame_count` as progress detail; on `failed`, show `error` string.
4. **Inventory** — on `completed`: `GET /pallets/{pallet_id}/items` (list) + `GET /pallets/{pallet_id}` (header totals). Images load from relative `image_urls` via `GET /jobs/{job_id}/files/{path}` (prefix base URL).
5. **Review/edit** — per item: `GET /items/{item_id}` (fresh form state) → `PATCH /items/{item_id}` (7 editable keys) → re-fetch `GET /pallets/{pallet_id}` for updated totals.
6. **Profit** — `GET /pallets/{pallet_id}` (`PalletSummary`); label all money estimates; surface `unpriced_item_count`.
7. **Export/share** — `GET /pallets/{pallet_id}/export` → CSV bytes → share sheet.

## Screen → endpoint map

| Screen | Endpoint(s) | Notes |
|---|---|---|
| Health / connection check | `GET /health` | Gate server-dependent UI on `{status: ok}` |
| Pallet list | — LOCAL-ONLY | No `GET /pallets` exists; persist created ids on-device (see Gaps G1) |
| Create pallet | `POST /pallets` | Costs optional (default 0.0); `job_id` optional claim |
| Video upload | `POST /jobs` (multipart) | `pallet_id` optional form field; handle 413/415/409/404 before polling |
| Job list / history | `GET /jobs` | Full `Job` objects incl. listings arrays — heavy; newest first, no pagination |
| Processing status | `GET /jobs/{job_id}` | Poll to terminal state; `failed` carries `error`; restart-marked jobs surface `"Interrupted by restart"` |
| Inventory list | `GET /pallets/{pallet_id}/items` | Stable id order; read `needs_review`/`review_reasons` badges from each item |
| Item detail | `GET /items/{item_id}` | Fresh read before edit; `:` in id needs no encoding |
| Item edit | `PATCH /items/{item_id}` | Only 7 keys; null clears price; 422 shows validation message; edits flow into totals + CSV |
| Profit dashboard | `GET /pallets/{pallet_id}` | `PalletSummary`; always show `estimates: true` disclaimer + unpriced count |
| CSV share | `GET /pallets/{pallet_id}/export` | `text/csv` bytes; filename `pallet-<id>.csv` |
| Media viewer | `GET /jobs/{job_id}/files/{path}` | Binary; traversal-guarded (404 on bad path) |

## Flow B — Existing job → pallet (claim)

`POST /jobs` (no `pallet_id`) → poll to `completed` → `POST /pallets`
`{"job_id": …}` → items attach without reprocessing →
`GET /pallets/{id}/items`. Second claim of the same job → `409`; unknown job → `404`.

## Flow C — Failure handling (verified)

- Corrupt video → job `failed` with `error` set (test: `test_corrupted_video_fails_job_with_error`). Screen shows error + retry (retry = new upload; no re-run endpoint).
- Unknown ids → `404 {"detail": …}` on all detail routes.
- Invalid edit → `422` (negative price, off-vocabulary condition). Show inline.
- Oversize upload → `413`; wrong extension → `415`; pallet-with-job re-upload → `409`.

## Rules for iOS (from audit findings)

- Never read post-edit state from `GET /jobs/{id}.listings` (stale snapshot); use pallet-items endpoints.
- Never present mock drafts as verified: every item ships `needs_review: true`, `provider: "mock"`, `Demo draft: …` text, `price_source` fixture labels — the review UI is mandatory, not optional.
- Never append trailing slashes; never hand-build absolute media URLs (prefix base URL to the relative path); never treat null price as 0.

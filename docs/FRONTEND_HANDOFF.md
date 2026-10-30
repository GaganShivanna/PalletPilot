# PalletPilot — Frontend Handoff (Backend Phase 2)

Client-agnostic HTTP contract for the mock end-to-end backend. Machine-readable
schema: [`docs/openapi.json`](./openapi.json) (regenerate with
`cd backend && .venv/bin/python scripts/export_openapi.py`).
Interactive docs when the server runs: `/docs`.

- **Base URL (local):** `http://127.0.0.1:8000`
- **Run:** `cd backend && .venv/bin/uvicorn app.main:app`
- **Auth:** none (hackathon MVP).
- **Mock labeling:** every mock draft has `needs_review: true`, a
  `review_reasons` entry starting with `mock`, `price_source: "mock_fixture"`
  (or `"none"` when unpriced), and descriptions ending with the
  `Demo draft: ...` marker. Never present these as verified listings.

## Endpoints

### `GET /health`

```json
{ "status": "ok" }
```

### `POST /pallets` → 201

Create a pallet. `job_id` is optional; when given, the job must exist and be
unlinked, and its already-processed items are claimed (no reprocessing).

Request:

```json
{ "name": "Bin 12", "purchase_cost": 20.0, "additional_costs": 5.0, "job_id": null }
```

Response (`Pallet`):

```json
{
  "id": "9f3c…", "name": "Bin 12", "purchase_cost": 20.0, "additional_costs": 5.0,
  "job_id": null, "status": "empty", "item_count": 0, "priced_item_count": 0,
  "created_at": "2026-10-28T…", "updated_at": "2026-10-28T…"
}
```

Errors: `404` unknown `job_id`; `409` job already linked to a pallet.

### `POST /jobs` → 202 (multipart)

Upload a video. Optional `pallet_id` form field links the job to a pallet
(created via `POST /pallets` first); the pipeline then tags items with it.

```bash
curl -X POST http://127.0.0.1:8000/jobs \
  -F video=@unboxing.mp4 -F pallet_id=9f3c…
```

Response: `{ "id": "abc123…", "status": "queued" }`.

Errors: `415` unsupported extension (allowed: mp4 mov m4v avi webm mkv);
`413` over `MAX_UPLOAD_MB`; `404` unknown pallet; `409` pallet already has a job.

### `GET /jobs` / `GET /jobs/{id}` → 200

List jobs (newest first) or one job. Poll `GET /jobs/{id}` until
`status` is `completed` or `failed` (suggested: every 1s, 60s cap).

Status flow: `queued → sampling_frames → segmenting → identifying →
generating_photos → generating_listings → completed` (or `failed` with `error`).

Completed job (truncated):

```json
{
  "id": "abc123…", "status": "completed", "video_filename": "video.mp4",
  "frame_count": 6, "error": null,
  "listings": [
    {
      "item_id": "abc123…:item_0", "title": "Acme Cordless Drill",
      "description": "Acme Cordless Drill (Power Tools). … Demo draft: …",
      "category": "Power Tools", "brand": "Acme", "condition": "good",
      "price": { "amount": 45.0, "currency": "USD" },
      "image_urls": ["/jobs/abc123…/files/photos/item_0_0.jpg"],
      "confidence": 0.85, "needs_review": true, "review_reasons": ["mock …"]
    }
  ]
}
```

Failed job: `{ …, "status": "failed", "error": "Could not open video: video.mp4" }`.
Unknown id: `404 { "detail": "Job not found" }`.

### `GET /jobs/{id}/files/{path}` → 200 (binary)

Serves frames/photos under the job dir. Path traversal returns `404`.

### `GET /pallets/{id}` → 200 (`PalletSummary`)

Pallet detail + projected financials. `status`: `empty | processing | ready | failed`.
Money fields are **estimates** (`estimates: true`); unpriced items are excluded
from revenue and counted in `unpriced_item_count` — never silently $0.

```json
{
  "pallet": { "id": "9f3c…", "status": "ready", "item_count": 3, "priced_item_count": 2, … },
  "estimated_revenue": 77.5, "estimated_fees": 10.07, "projected_profit": 42.43,
  "fee_rate": 0.13, "unpriced_item_count": 1, "estimates": true
}
```

Errors: `404` unknown pallet.

### `GET /pallets/{id}/items` → 200 (`Item[]`)

Stable order (by id). Fields include `title/description/category/brand/
condition`, `suggested_price` (nullable) + `currency/price_source/
price_confidence/price_type`, `original_image_url`, `image_urls`,
`confidence`, `needs_review`, `review_reasons`, `provider`.

### `PATCH /items/{id}` → 200 (`Item`)

Edit any subset of: `title, description, category, brand, condition,
suggested_price, needs_review`. Only provided fields change (explicit `null`
price clears it). Changes persist and immediately affect the pallet summary
and CSV export. Item ids look like `<job_id>:item_0` (the `:` is URL-safe).

```bash
curl -X PATCH http://127.0.0.1:8000/items/abc123…:item_2 \
  -H 'Content-Type: application/json' \
  -d '{"suggested_price": 10.0, "needs_review": false}'
```

Validation (`422`): negative `suggested_price`; `condition` outside
`new, like_new, good, fair, poor, parts, unknown`. Unknown id: `404`.

### `GET /items/{id}` → 200 (`Item`)

Read one item (useful for edit-form round-trips). `404` when unknown.

### `GET /pallets/{id}/export` → 200 (`text/csv`)

UTF-8 CSV download (`Content-Disposition: attachment`). Columns:

```text
item_id,title,description,category,brand,condition,suggested_price,currency,image_url,review_status
```

Notes: stable id order; missing prices are empty cells; `review_status` is
`needs_review|approved`; formula-like cells (`= + - @ …`) are `'`-prefixed
against spreadsheet injection; includes latest user edits.

## Typical flows

**New pallet from video:** `POST /pallets` → `POST /jobs` (+`pallet_id`) →
poll `GET /jobs/{id}` → `GET /pallets/{id}` + `/items`.

**Existing job → pallet:** `POST /pallets` with `{"job_id": …}` claims its items.

**Edit flow:** `GET /pallets/{id}/items` → user edits → `PATCH /items/{id}` →
re-fetch `GET /pallets/{id}` for updated totals → `GET …/export` for CSV.

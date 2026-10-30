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
- **Real AI providers** (server runs with `AI_PROVIDER=sam|muse_spark|real`;
  endpoint shapes unchanged): drafts have no `Demo draft` marker, `provider`
  is `sam`/`muse_spark`, item ids look like `<job_id>:concept_0_7`, and all
  conditions still come from the documented `new … unknown` set (the server
  maps model observations conservatively; raw observations survive in
  `review_reasons`). Real items are currently unpriced (`price_source:
  "none"`) and excluded from revenue. Details: `docs/AI_INTEGRATION.md`.

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
Status names the *current activity*: the `identifying →
generating_photos → generating_listings` sequence repeats for every item,
and finished items are already readable via the item endpoints while later
items still process.

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
Items finished before the failure stay readable; failed jobs are not
automatically resumable (re-running would reuse the same item ids).
Unknown id: `404 { "Detail": "Job not found" }`.

### `GET /jobs/{id}/events` → 200 (`text/event-stream`)

Server-Sent Events for progressive updates. Polling `GET /jobs/{id}` keeps
working — SSE is additive. Every `listing.ready` is emitted only after its
row commits, so fetching the item on receipt always succeeds.

Event frames (`id` starts at 1 per job, strictly increasing):

```text
id: 1
event: job.started
data: {"id":1,"job_id":"abc123…","event_type":"job.started","item_id":null,"created_at":"2026-10-30T…","payload":{"video_filename":"video.mp4"}}

id: 2
event: segmentation.completed
data: {"id":2,"job_id":"abc123…","event_type":"segmentation.completed","item_id":null,"created_at":"2026-10-30T…","payload":{"track_count":3}}

id: 3
event: listing.ready
data: {"id":3,"job_id":"abc123…","event_type":"listing.ready","item_id":"abc123…:item_0","created_at":"2026-10-30T…","payload":{"item_id":"abc123…:item_0"}}

id: 6
event: job.completed
data: {"id":6,"job_id":"abc123…","event_type":"job.completed","item_id":null,"created_at":"2026-10-30T…","payload":{"item_count":3}}
```

`job.failed` carries `payload: {"error": "…"}`. Zero-detection jobs complete
normally with `track_count`/`item_count` 0 and no `listing.ready`. The server
closes the stream after the terminal event; idle connections get `: keepalive`
comments (~15s). Unknown id: `404` (JSON, not a stream).

Recommended client flow:

1. `POST /jobs`, then open the stream and `GET /pallets/{id}/items` once for
   the initial snapshot (covers the gap between upload and stream attach).
2. On each `listing.ready`, re-fetch `GET /pallets/{id}/items` (or
   `GET /items/{item_id}`) — events carry ids, not full records.
3. On `job.completed`, re-fetch items + summary once more, then close.
   On `job.failed`, show `payload.error`; already-received items stay valid.
4. Reconnects: the client library resends `Last-Event-ID` automatically and
   the server replays missed events. Delivery is at-least-once per
   connection — deduplicate by `id`.

Browser example:

```js
const src = new EventSource(`/jobs/${jobId}/events`);
src.addEventListener("listing.ready", (e) => refreshItems(JSON.parse(e.data).item_id));
src.addEventListener("job.completed", () => { refreshAll(); src.close(); });
src.addEventListener("job.failed", (e) => { showError(JSON.parse(e.data).payload.error); src.close(); });
```

SwiftUI note: `EventSource` is browser-only; a SwiftUI client needs an SSE
client library or a manual streaming-`URLSession` implementation that parses
`id:`/`event:`/`data:` frames and sends `Last-Event-ID` on reconnect.

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

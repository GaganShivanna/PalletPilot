# PalletPilot — iOS Integration Tasks (frontend handoff)

Branch: `integration/ios-backend`. Backend owner verified the contract below
against the merged tree on 2026-10-31 (10-step live mock run green; 57/57
pytest green). The iOS teammate owns all SwiftUI implementation.

Authoritative backend contracts (read these first):

- `docs/FRONTEND_HANDOFF.md` + `docs/openapi.json` (10 paths, SSE included).
- `docs/AI_INTEGRATION.md` for real-AI response shapes (no mock markers).

Superseded / stale (do not treat as current):

- `docs/ios/API_CONTRACTS.md`, `docs/ios/BACKEND_API_AUDIT.md`,
  `docs/ios/INTEGRATION_GAPS.md` — audited against the pre-SSE mock-only
  backend. REST shapes are still right; "11 routes", "poll-only" (G9), and
  "mock-only" (G12) are stale. Each file carries an integration-note header.
- `docs/ios/USER_FLOW.md` — flows still valid; polling steps will be
  superseded by the SSE workflow in T6 below.

Conventions (already established in the scaffold — keep them):

- Services own HTTP behind `*ServiceProtocol`; view models own state;
  views render. No HTTP in views, no invented endpoints/fields.
- Paths verbatim, no trailing slash. `:` in item ids stays unencoded.
- `null` price means unknown, never $0. `Job.listings` is a
  stale-after-edit snapshot — pallet-items endpoints are current truth.
- Error bodies use lowercase `detail` (verified live on 2026-10-31;
  ignore any capital-`Detail` typo in prose docs). 422 uses the standard
  FastAPI validation envelope, not `detail`.

## Prioritized task list

P0 (demo path — in dependency order):

1. **T1** `JobEvent` model (new file).
2. **T2** `SSEClient` streaming parser (new file).
3. **T3** `JobService.events` (extend service + protocol).
4. **T4** `APIClient.patch` (extend client + protocol; fix `PreviewStubClient`).
5. **T5** Pallet/item read + export services (extend `PalletService`,
   new `ItemService`).
6. **T6** `ProcessingViewModel` SSE workflow (rework; keep polling as fallback).
7. **T7** Inventory list (new feature: view + view model + route).
8. **T8** Item detail/edit (new feature; PATCH round-trip).
9. **T9** Summary header + CSV share (extend inventory feature).
10. **T10** Product media loading (relative-URL images).

P1 (demo polish):

11. **T11** Error-handling pass (job failure UX, HTTP mapping review).
12. **T12** Tests for T1–T10 (parser, view models, fakes).
13. **T13** Local pallet-id store (no `GET /pallets` exists; persist ids
    on-device so pallets survive app restarts).

## T1 — `JobEvent` model (new)

New file: `ios/PalletPilot/Core/Models/JobEvent.swift`.

```swift
enum JobEventType: String, Codable, Sendable {
    case started = "job.started"
    case segmentationCompleted = "segmentation.completed"
    case listingReady = "listing.ready"
    case completed = "job.completed"
    case failed = "job.failed"
    var isTerminal: Bool { self == .completed || self == .failed }
}

struct JobEventPayload: Codable, Sendable, Equatable {
    var videoFilename: String?
    var trackCount: Int?
    var itemCount: Int?
    var itemId: String?
    var error: String?
}

struct JobEvent: Codable, Sendable, Equatable, Identifiable {
    var id: Int
    var jobId: String
    var eventType: JobEventType
    var itemId: String?
    var createdAt: Date
    var payload: JobEventPayload
}
```

Notes: decode with the same snake_case + fractional-ISO8601 decoder as
`APIClient`. Payload keys vary per event — all stay optional. Event `id`
is a per-job integer starting at 1, strictly increasing. Delivery is
at-least-once per connection — receivers must deduplicate by `id` (T6).

Acceptance: `JobEvent` decodes the handoff's sample frames; unknown future
`event_type` values must not crash decoding (add a tolerant fallback or
skip unknown events in T2 — your call, but pick one deliberately).

## T2 — `SSEClient` (new)

New file: `ios/PalletPilot/Core/Networking/SSEClient.swift`. No third-party
dependencies (project has zero; keep it that way). Target iOS 17 supports
`URLSession.bytes`.

```swift
protocol SSEClientProtocol: Sendable {
    func events(jobId: String, lastEventId: Int?)
        -> AsyncThrowingStream<JobEvent, Error>
}

struct SSEClient: SSEClientProtocol {
    let configuration: APIConfiguration
    let session: URLSession
    let decoder: JSONDecoder  // same setup as APIClient
}
```

Behavior:

- `GET /jobs/{jobId}/events`, headers `Accept: text/event-stream` and
  `Last-Event-ID: <n>` when resuming (server also honors
  `?last_event_id=<n>` as fallback; prefer the header).
- Parse `id:` / `event:` / `data:` frames; a blank line dispatches one
  event. Ignore `: keepalive` comment lines. Multi-line `data:`: join
  with `\n` (server currently sends single-line JSON).
- Non-2xx status must throw `APIError.http` with the body's `detail`
  (unknown job → 404 JSON, not a stream — check status before streaming).
- End the stream on terminal events (`job.completed` / `job.failed`):
  yield the terminal event, then finish normally. The server also closes
  its side; idle connections receive `: keepalive` comments (~15 s).
- Cancellation (view disappear) ends the stream without error.

Acceptance: parser unit tests feed canned byte chunks (split mid-frame)
and assert frames, keepalive filtering, and terminal finish.

## T3 — `JobService.events` (extend)

File: `ios/PalletPilot/Services/JobService.swift`.

- Add to `JobServiceProtocol`: `func events(jobId:lastEventId:)`
  returning `AsyncThrowingStream<JobEvent, Error>`.
- `JobService` gains an `SSEClientProtocol` dependency (same init-injection
  pattern as `client`). Update `AppContainer.live/preview` wiring.
- Update `FakeJobService` with a scripted event sequence for T6/T12 tests.

Acceptance: `AppContainer` builds both live and preview configurations.

## T4 — `APIClient.patch` (extend)

File: `ios/PalletPilot/Core/Networking/APIClient.swift`.

- Add to `APIClientProtocol` and `APIClient`:
  `patch<B: Encodable, T: Decodable>(_ path:body:as:)` mirroring `post`
  (JSON in/out, 2xx success, `APIError.http` + `detail` otherwise).
- The `HTTPMethod.patch` case already exists — reuse it.
- Update `PreviewStubClient` (in `AppRoute.swift`) or previews break.

Acceptance: existing test suite still compiles; add one test asserting a
PATCH sends JSON without a trailing slash (follow `testCreatePallet…`).

## T5 — Pallet/item read + export services (extend + new)

Extend `PalletServiceProtocol` (`Services/PalletService.swift`):

- `getSummary(palletId:) -> PalletSummary` — `GET /pallets/{id}`.
- `getItems(palletId:) -> [Item]` — `GET /pallets/{id}/items` (stable id
  order, server-side).
- `exportCSV(palletId:) -> Data` — `GET /pallets/{id}/export` via
  `client.getData` (opaque bytes; do not JSON-decode).

New file `Services/ItemService.swift`:

- `ItemServiceProtocol`: `getItem(id:) -> Item` (`GET /items/{id}`),
  `patchItem(id:patch:) -> Item` (`PATCH /items/{id}`, body `ItemPatch`).
- `Item`/`ItemPatch` models already exist and match the schemas —
  no model changes. `ItemPatch` nil-omission + `clearsPrice` already match
  server provided-fields semantics.

Wire both into `AppContainer`; extend `FakePalletService`, add
`FakeItemService` in `TestHelpers.swift`.

Acceptance: each method covered by a stubbed-`URLProtocol` test asserting
exact path, verb, and (for PATCH) snake_case body keys.

## T6 — `ProcessingViewModel` SSE workflow (rework)

File: `Features/Processing/ProcessingViewModel.swift`. Keep the file's
`@MainActor` + injectable-service structure; replace poll-only with:

1. Create pallet + upload first (existing `UploadViewModel` flow, unchanged).
2. Fetch `GET /pallets/{id}/items` once as the initial snapshot (covers the
   gap between upload and stream attach).
3. Open `events(jobId:lastEventId: nil)`.
4. On `segmentation.completed`: show `payload.trackCount`.
5. On `listing.ready`: fetch `GET /items/{item_id}` once and insert into
   published items sorted by id (single-item fetch, not full refetch).
6. Deduplicate every event by `id` (`Set<Int>` — replay + reconnect overlap).
7. On `job.completed`: re-fetch items + summary once, finish stream,
   navigate to inventory.
8. On `job.failed`: publish `payload.error`; already-received items stay
   valid and visible; offer "upload again" (no re-run endpoint exists).

Reconnect: on transport error, back off (1 s, 2 s, 4 s … 15 s cap),
resume with the last seen id, retry ~5 times, then fall back to the
existing 1 s `GET /jobs/{id}` polling path (keep that code as the
fallback function). Cancel the stream task in `stop()`.

Drop the 60 s completion cap under SSE (long real-AI jobs legitimately
exceed it — the 1-item smoke test took 39 s wall). Keep a generous cap
only for the poll fallback.

Acceptance: scripted-fake tests prove append-per-event, duplicate-id
dedup, resume-after-drop (last id resent), completed-refresh, and
failed-with-partials. All published-state updates happen on the main actor.

## T7 — Inventory list (new feature)

New files: `Features/Inventory/InventoryView.swift`,
`Features/Inventory/InventoryViewModel.swift`
(plus `ItemRowView.swift` if you want it separate).

- Route: add `AppRoute.inventory(palletId:jobId:)`; wire in
  `PalletPilotApp.navigationDestination`; navigate there from
  `ProcessingView` on completion (and later from upload-success for
  already-finished jobs).
- View model owns `[Item]` + `PalletSummary?`, loads via `getItems` /
  `getSummary` on appear and refreshes on demand (pull-to-refresh).
- Each row shows title, condition, price-or-"Unpriced" (never $0),
  `needs_review` badge, and thumbnail (T10). Rows navigate to T8.
- Never read post-edit state from `Job.listings` (stale snapshot).

Acceptance: list renders mock items from fakes; row tap navigates to
detail; refresh re-fetches both endpoints.

## T8 — Item detail/edit (new feature)

New files: `Features/Inventory/ItemDetailView.swift`,
`Features/Inventory/ItemEditView.swift` (+ view model as needed).

- Detail: fresh `GET /items/{id}` on appear (never trust a passed-in copy
  for the edit form), full photo (T10), all fields, `review_reasons` list.
- Edit: PATCH the 7 editable keys only (`title, description, category,
  brand, condition, suggested_price, needs_review`) via existing
  `ItemPatch`. Price clear uses `ItemPatch.clearingPrice`. Condition
  picker uses the 7-value vocabulary (`ItemCondition`).
- After PATCH: re-fetch `GET /pallets/{id}` for updated totals (parent
  view model refresh), then pop or show saved state.
- 422 responses surface the validation message inline (negative price,
  off-vocabulary condition).

Acceptance: edit round-trip test with fakes (get → patch → summary
refresh called); price-clear encodes explicit null (already covered by
`ItemPatch` encoder — keep that test green).

## T9 — Summary header + CSV share (extend inventory)

- Header (in `InventoryView` or a `ProfitHeaderView`): `estimated_revenue`,
  `estimated_fees`, `projected_profit`, `fee_rate`, `unpriced_item_count`.
  Always show the estimates disclaimer (`estimates: true` — server values
  are projections, unpriced items excluded). Never recompute with a local
  fee rate — display server values.
- Share: `exportCSV(palletId:)` bytes → write to a temp
  `pallet-<id>.csv` file → SwiftUI `ShareLink`. Filename matches the
  server's `Content-Disposition` (`pallet-<id>.csv`).
- CSV columns (exact order): `item_id,title,description,category,brand,
  condition,suggested_price,currency,image_url,review_status`.
  `image_url` is relative (first `image_urls` entry or empty).

Acceptance: share sheet presents a `.csv` file whose header row matches
the column list; money labels show an "estimate" disclaimer.

## T10 — Product media loading

- `original_image_url` / `image_urls` are **relative** paths served by
  `GET /jobs/{job_id}/files/{path}`. Resolve with
  `configuration.url(for:)` (prefix base URL), e.g. in `AsyncImage`.
- Missing files / traversal → 404: show a placeholder, not an error screen.
- Thumbnails in T7 rows, full image in T8 detail.

Acceptance: simulator run against local backend shows frame-fallback
photos for mock items (all mock photos are frame fallbacks by design).

## T11 — Error-handling pass

- `APIError` mapping already covers transport, HTTP+`detail`, decoding.
  Review every new call site: user-facing message via
  `LocalizedError.errorDescription`, no raw dumps.
- Upload errors before polling: 413 (too large), 415 (extension — also
  pre-validated client-side by `UploadVideo`), 409 (pallet already has a
  job), 404 (unknown pallet). Job errors: `job.failed` payload + terminal
  `GET /jobs/{id}.error` (incl. `"Interrupted by restart"` after a server
  restart mid-job).
- Offline mid-stream: T6 reconnect path; offline at launch: Home
  connectivity check already gates server-dependent UI.

Acceptance: each error in the table above shows a readable message in a
manual simulator pass (kill backend mid-stream to test reconnect).

## T12 — Tests

- Extend `PalletPilotTests/`: SSE parser tests (T2), `patch` client test
  (T4), service tests for T5 reads/export, view-model tests for T6–T9
  with scripted fakes (`FakeItemService`, event-scripted `FakeJobService`,
  extended `FakePalletService`).
- Keep the existing suites green (decoding + `APIClientTests`); no live
  backend in unit tests (stubbed `URLProtocol` + fakes only).
- Simulator gate before demo: `xcodebuild -project
  ios/PalletPilot.xcodeproj -scheme PalletPilot -destination 'platform=iOS
  Simulator,name=iPhone 17' test`.

## T13 — Local pallet-id store (P1)

No `GET /pallets` endpoint exists, so the app cannot list server pallets.
Persist created `{palletId, name, jobId, createdAt}` records on-device
(UserDefaults is enough for the demo; SwiftData later) and offer a simple
"recent pallets" entry point from Home.

## API calls per screen

| Screen | Calls (in order) |
|---|---|
| Home | `GET /health` (existing) |
| Upload | `POST /pallets`, `POST /jobs` multipart (existing) |
| Processing | `GET /pallets/{id}/items` snapshot, `GET /jobs/{id}/events` stream, `GET /items/{item_id}` per `listing.ready`, `GET /jobs/{id}` poll fallback only |
| Inventory | `GET /pallets/{id}/items`, `GET /pallets/{id}` |
| Item detail/edit | `GET /items/{id}`, `PATCH /items/{id}`, `GET /pallets/{id}` refresh |
| Share | `GET /pallets/{id}/export` (bytes) |
| Media | `GET /jobs/{id}/files/{path}` (bytes, base-URL-prefixed) |

## Mock integration test (no paid inference)

Backend owner verified this exact flow live on 2026-10-31 via in-process
client (10/10 checks): 3 `listing.ready` events (ids 3–5), revenue
77.5 → 87.5 after a +$10 edit, 4-line CSV. Repeat it against a real
server + simulator for the demo.

Start the backend (explicit mock; never set a real `AI_PROVIDER` for tests):

```bash
cd backend && AI_PROVIDER=mock .venv/bin/uvicorn app.main:app
# serves http://127.0.0.1:8000 — the simulator shares the Mac's localhost
```

Simulator run: open `ios/PalletPilot.xcodeproj`, scheme **PalletPilot**,
iPhone simulator, Run. Any short `.mp4`/`.mov` clip works as the upload
(mock pipeline samples 2–5 fps, max 300 frames).

Manual steps and expected results:

1. Home → Check connection → `ok`.
2. New pallet from video → name + costs → Choose video → Create pallet
   and upload → job id received (202).
3. Track progress → stream opens; `segmentation.completed` shows
   track count (mock: 3).
4. Items appear one by one as `listing.ready` arrives (mock: 3).
5. `job.completed` → inventory shows 3 items; header shows revenue
   77.5, profit 42.42, estimates disclaimer.
6. Open an item → photo, fields, `needs_review` + `review_reasons`.
7. Edit price (+$10) → save → header revenue rises by exactly $10.
8. Share → CSV file `pallet-<id>.csv` with header
   `item_id,title,…` and the edited price in its row.
9. Failure drill: upload a corrupt `.mp4` → job `failed` with a readable
   error; already-finished items (if any) stay visible.
10. Reconnect drill: kill the backend mid-stream → client backs off and
    resumes (or falls back to polling); restart backend → behavior sane.

Backend-only equivalent (no UI): the same 10 steps are scriptable with
`curl` (`POST /pallets`, multipart `POST /jobs`, `curl -N
/jobs/{id}/events` for the live stream, item/summary/PATCH/export GETs).

## Backend readiness (owner's assessment, 2026-10-31)

No backend changes required for the demo. Verified points:

- Multipart uploads: server streams 1 MB chunks, enforces extension
  allowlist + `MAX_UPLOAD_MB` (500), ignores the client filename except
  its suffix. Compatible with `APIClient.upload` as-is.
- Relative image URLs: by contract; iOS prefixes the base URL (T10).
- SSE + URLSession: `text/event-stream`, `Cache-Control: no-cache`,
  `X-Accel-Buffering: no`, `: keepalive` comments, `Last-Event-ID` header
  + `?last_event_id=` fallback, close-on-terminal. Compatible with
  `URLSession.bytes` as specified in T2. No proxy in the demo path.
- Errors: lowercase `detail` (verified live), 422 envelope for validation.
- Long jobs: single serial worker, SQLite-durable, no progress percent,
  no cancel endpoint, restart marks in-flight jobs failed. iOS must drop
  the 60 s cap (T6) and surface `job.failed` text.
- Simulator networking: localhost shared with the Mac; existing
  `NSAllowsLocalNetworking` covers it. CORS is irrelevant to native apps.

## Demo-day acceptance (whole flow)

- [ ] Fresh simulator install → backend `AI_PROVIDER=mock` → full 10-step
  mock test passes end to end with no Xcode errors.
- [ ] Items visibly stream in during processing (not only at completion).
- [ ] Price edit moves revenue/profit; CSV contains the edit.
- [ ] Mock labeling honest everywhere (`needs_review`, no mock prices
  presented as market data).
- [ ] No paid inference performed without explicit approval.


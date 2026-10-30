# PalletPilot iOS Integration Gaps

Capabilities the iOS app can need that the backend (branch `backend/scaffold`,
as audited) does not provide. No speculation below: each gap names the missing
contract and the client-side consequence. No replacement backend is proposed;
workarounds are on-device only and marked as such.

## Missing endpoints (no route, no schema, no test)

- **G1 — No pallet list.** `GET /pallets` does not exist (`REPO_MAP.md` claims
  it; code + `openapi.json` refute it). Consequence: no server fund of pallets;
  iOS must persist created pallet ids locally (e.g. SwiftData/UserDefaults) and
  offer no cross-device pallet history.
- **G2 — No pallet update/delete.** No rename, no cost correction, no deletion.
  Consequence: creation-time typos in `name`/`purchase_cost` are permanent
  server-side; iOS can only relabel locally.
- **G3 — No item create/delete.** Items exist only as pipeline output. No manual
  item, no removal of junk detections. Consequence: inventory is append-only
  from the client's view; `PATCH` is the only mutation.
- **G4 — No item image management.** `PATCH` accepts no `image_urls` /
  `original_image_url`; no photo-upload endpoint. Consequence: iOS cannot add
  or replace item photos; mock fallback frames are the only imagery.
- **G5 — No job retry/re-run/delete.** No queue control; failed jobs stay
  failed; `GET /jobs` grows unboundedly. Consequence: retry = fresh upload;
  no server-side history cleanup.
- **G6 — No search, filter, sort, or pagination.** `GET /jobs` returns full
  `Job` objects (listings included) with no parameters. Consequence: job
  history screen must handle large payloads; all filtering is client-side.

## Missing platform capabilities

- **G7 — No auth, no users, no ownership.** Any client on the network can read
  and `PATCH` any item/pallet. Consequence: no login screen is implementable
  against this backend; local network only until auth lands.
- **G8 — No TLS/production host.** Contract targets `http://127.0.0.1:8000`
  (App Transport Security forbids cleartext by default). Consequence: iOS needs
  an ATS exception for dev and a real HTTPS host decision before release.
- **G9 — No push/websocket.** Status is poll-only. Consequence: polling policy
  (~1 s / 60 s cap) lives in the app; background completion needs local
  handling (BGTask) with no server assist.
- **G10 — CSV-only export.** No PDF, no marketplace-posting endpoint.
  Consequence: "list online" flows end at the share sheet.
- **G11 — Single serial worker, no progress percent.** `frame_count` is the
  only progress signal; concurrent uploads queue opaquely. Consequence: queue
  position/wait-time UI is not implementable.

## Data-quality constraints (present but limiting)

- **G12 — Mock-only inference.** All items `needs_review: true`,
  `provider: "mock"`; real SAM / Muse Spark / Muse Image adapters raise
  `ProviderUnavailable`. Fixture pricing covers 2 products; everything else is
  null-priced. Consequence: the app is a **review tool**, not a price authority;
  ship review-first UX and never show mock prices as market data.
- **G13 — Server-controlled fee math.** `fee_rate` (default 0.13) comes from
  the server per summary; estimates only. Consequence: iOS must not hardcode or
  recompute totals with its own rate — display server values.
- **G14 — Sparse error contract.** Errors are human `detail` strings (plus
  generic `422` envelopes). Consequence: iOS error mapping is string-matching;
  no stable error codes to switch on.
- **G15 — Stale `Job.listings` after edits.** Documented in audit D2.
  Consequence: one source-of-truth rule — post-completion reads go to
  pallet-items endpoints.

## Backend dependency risks for iOS planning

1. Contract drift: only `docs/FRONTEND_HANDOFF.md` + `docs/openapi.json`
   (regenerable via `scripts/export_openapi.py`) pin the contract; any backend
   change without re-export silently breaks typed models.
2. `REPO_MAP.md` already misstates the pallet surface (claims `GET /pallets`);
   treat it as stale until corrected.
3. Test evidence is partial in this environment (`cv2` missing from
   `backend/.venv`; 12/12 non-video tests pass, video/pipeline tests
   uncollectible here) — require a full green backend run before iOS
   integration testing.
4. Restart semantics: in-flight jobs flip to `failed: "Interrupted by restart"`;
   iOS must handle jobs that die without client action.

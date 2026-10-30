# CURRENT_STATUS.md

Last updated: 2026-10-28 (iOS Phase 1 verification pass).

## Implemented

- Project guidance setup only: `AGENTS.md`, 7 validated skills,
  `docs/REPO_MAP.md`, nested subsystem rules, `.agents/memory/` topics.
- Backend scaffold: upload, 2–5 fps frame sampling, job queue,
  job/status/file endpoints, `.env` key handling.
- Phase 1 (2026-10-28): provider interface (`app/providers/`, mock default,
  real adapters raise loudly), pallet/item schemas, SQLite metadata
  (`meta.db`: jobs/pallets/items) with restart recovery.
- Phase 2 (2026-10-28): complete mock workflow — pallet/item/CSV endpoints,
  mock identification, deterministic listing drafts, fixture pricing,
  financial estimates, photo fallback, per-item failure degradation with
  transient retry. Contract: `docs/FRONTEND_HANDOFF.md` + `docs/openapi.json`.
  Stubs remaining: real SAM / Muse Spark / Muse Image adapters.

## Implemented (iOS Phase 1, verified 2026-10-28)

- Native SwiftUI foundation in `ios/`: `.xcodeproj` (app + test targets,
  shared scheme, iOS 17.0, no third-party deps), `App/` entry/router/DI,
  `Core/Networking` (`APIConfiguration`, `APIClient`, `APIError`),
  `Core/Models` (contract Codables mirroring `backend/app/schemas/`),
  `Features/Home` (Home + `GET /health` connectivity check), `Services/`
  (`HealthService` + protocol). No uploads, inventory, or pricing yet.
- iOS upload + processing flows (2026-10-29): `POST /pallets` + multipart
  `POST /jobs` with pallet-id linking (`PalletService`/`JobService` +
  protocols, `UploadVideo` extension/MIME validation, retry reuses the created
  pallet id); `ProcessingViewModel` polls `GET /jobs/{id}` every ~1 s with a
  60 s cap and an 8-state timeline; `TEST BUILD SUCCEEDED` (app + test
  targets) with one fix (`.accentColor` is not a `ShapeStyle`); 28/28 behavior
  checks pass on the macOS host runner (12 new: JobCreated, PalletCreate
  snake_case, video validation, POST 201 body keys, multipart 202 parts,
  create-then-upload, retry reuse, poll-to-completed, job-error, timeout).
- iOS integration specs in `docs/ios/`: `BACKEND_API_AUDIT.md`,
  `API_CONTRACTS.md`, `USER_FLOW.md`, `INTEGRATION_GAPS.md`.

## Active blockers

- Real AI adapters unimplemented: need verified SAM / Muse Spark / Muse Image
  API details from the AI engineer (see `app/providers/real.py` messages).
- A real-looking `MUSE_API_KEY` value was committed in `backend/.env.example`
  (since blanked); rotate the key if it was ever valid.
- Skill auto-discovery unconfirmed in an unsandboxed terminal
  (pending: `muse skills list --source project`).

## Test status

- Backend: 25/25 pytest pass (18 Phase 1 + 7 Phase 2 e2e/failures), covering
  all endpoints over the full ASGI stack. Live TCP/uds serving could not be
  verified in-session: the sandbox denies all socket binds (uvicorn boots
  through "Application startup complete", then fails at bind). Recommend one
  unsandboxed run: `cd backend && .venv/bin/uvicorn app.main:app`.
- Skill validation: 7/7 pass `muse skills validate --json` with zero diagnostics.
- iOS (Xcode 26.5, license accepted 2026-10-28): `xcodebuild build` and
  `build-for-testing` SUCCEED for the simulator SDK (app + test targets,
  `-derivedDataPath /tmp/PalletPilotDerivedData`; `~/Library/Developer`
  is not writable in-session). One warning-level fix applied (`var` → `let`
  for the client decoder); zero errors.
- iOS unit tests: `xcodebuild test` NOT executable in-session — no concrete
  simulator device exists (CoreSimulatorService unreachable in the sandbox;
  "Tests must be run on a concrete device"). Instead, the behaviors asserted
  by both test suites were executed on a macOS host runner compiled from the
  identical app sources (`swiftc`, same module): 16/16 checks pass — 9 contract-decoding
  (health, job+listings, 8 statuses, pallet, summary, priced/unpriced items,
  patch omission, price-clear null), 5 networking (exact `/health` URL without
  trailing slash, 404/422 mapping, malformed → decoding, offline → network),
  2 ViewModel (connected + failure message). Test wrappers (Swift Testing /
  XCTest) compile but await one simulator run: `xcodebuild -project
  ios/PalletPilot.xcodeproj -scheme PalletPilot -destination 'platform=iOS
  Simulator,name=iPhone 16' test`.
- Backend `/health`: LIVE over HTTP 2026-10-28 via a one-shot user-approved
  unsandboxed probe of the unmodified app — `GET http://127.0.0.1:8000/health`
  → `200 {"status": "ok"}`. In-process `TestClient` also verified 7 routes
  (`/health`, create/get-pallet, items, export CSV, list-jobs, 404s) with
  contracted status codes. The sandbox still denies persistent binds, so no
  server was left running; `cv2` remains missing from `backend/.venv`, so the
  video pipeline/full 25-test suite still needs `pip install -r
  requirements-dev.txt` with network access. The iOS `APIClient` live path is
  code-identical to the verified stub path and resolves `GET /health` to
  `http://127.0.0.1:8000/health`.

## Remaining P0

1. Phase 3: real SAM / Muse Spark / Muse Image adapters; bounded concurrency
   for external calls; test on footage.
2. iOS: one simulator run of `xcodebuild test` + Home tap of Check connection
   against a live backend (both blocked only by this sandbox).
3. Phase 4: hardening, deployment config, demo prep.
4. Confirm skill discovery outside the sandbox.

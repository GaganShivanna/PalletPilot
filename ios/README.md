# PalletPilot iOS — local startup

Phase 1 foundation: SwiftUI app + typed networking against the verified backend
contracts (`docs/ios/API_CONTRACTS.md`). No uploads, inventory, or pricing yet.

## Prerequisites

- Xcode 26.x (project targets iOS 17.0+, Swift 5.0 language mode).
- Backend running locally (see `backend/AGENTS.md`):
  `cd backend && .venv/bin/python -m pytest -q` (full deps required),
  then `cd backend && .venv/bin/uvicorn app.main:app` → `http://127.0.0.1:8000`.

## Open, build, test

```bash
open ios/PalletPilot.xcodeproj
```

- Run: scheme **PalletPilot**, an installed simulator destination (⌘R).
- Tests: scheme **PalletPilot**, ⌘U, or (substitute an installed device name
  from `xcrun simctl list devices available`, e.g. iPhone 17):
  `xcodebuild -project ios/PalletPilot.xcodeproj -scheme PalletPilot \
    -destination 'platform=iOS Simulator,name=iPhone 17' test`
- If Xcode reports signing issues, set your Development Team on both targets.

## Backend connection

- Simulator: the app defaults to `http://127.0.0.1:8000` (same Mac). Tap
  **Check connection** on Home — it calls the verified `GET /health` route.
- Cleartext localhost is allowed via `NSAllowsLocalNetworking` in
  `PalletPilot/Info.plist`. No other ATS exceptions are included.
- Physical device: the Mac's loopback is unreachable. Set the Mac's LAN IP
  (e.g. `http://192.168.1.10:8000`) via UserDefaults once, e.g. in a debug
  session: `defaults write com.palletpilot.PalletPilot \
  PalletPilotAPIBaseURL -string "http://192.168.1.10:8000"`,
  or launch with env `PALLET_PILOT_API_BASE_URL=…`. A LAN-IP ATS exception is
  still required for device runs (not included; add per-device as needed).

## Layout

`App/` (entry, router, DI container), `Core/Networking` (config, `APIClient`,
errors), `Core/Models` (contract Codables), `Core/Components` + `Core/Theme`
(shared UI), `Features/Home`, `Services/` (`HealthService` + protocol).
Tests in `PalletPilotTests/`: contract decoding (Swift Testing) + networking and
ViewModel behavior (XCTest, stubbed `URLProtocol` — no live backend needed).

## Notes

- Canonical API paths have no trailing slash; item ids contain `:` (never
  percent-encode); media URLs are relative (prefix the base URL).
- Known doc bug: `docs/REPO_MAP.md` once claimed `GET /pallets` — it does not
  exist (see `docs/ios/BACKEND_API_AUDIT.md` D1). No pallet-list UI is built.

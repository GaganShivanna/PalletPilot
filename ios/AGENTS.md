# ios/AGENTS.md

Subsystem rules for the PalletPilot iOS app. The root `AGENTS.md` also applies.

## State

Phase 1 foundation (2026-10-28) + upload/processing flows (2026-10-29):
SwiftUI + MVVM, NavigationStack, URLSession APIClient (GET/POST/multipart),
contract Codables, services (Health/Pallet/Job + protocols), Home + connectivity
check, Upload (pallet form, video picker, create-then-upload with retry),
Processing (1 s poll, 60 s cap, status timeline). Unit tests compile; no
simulator run in sandbox. Inventory, item edit, profit, export not built yet.

## Stack

- SwiftUI, MVVM. Minimum iOS version: 17.0 (`IPHONEOS_DEPLOYMENT_TARGET`).
- Swift 5.0 language mode; Swift Concurrency (`async`/`await`, `@MainActor`).
- No third-party dependencies.

## Layout

- `ios/PalletPilot.xcodeproj` — project (schemes shared; scheme: PalletPilot).
- `ios/PalletPilot/App/` — `PalletPilotApp` entry, `AppRouter`, `AppContainer` (DI).
- `ios/PalletPilot/Core/Networking/` — `APIConfiguration`, `APIClient`, `APIError`.
- `ios/PalletPilot/Core/Models/` — contract Codables (mirror `backend/app/schemas/`).
- `ios/PalletPilot/Core/Components/`, `Core/Theme/` — shared UI.
- `ios/PalletPilot/Features/Home/` — Home view + view model.
- `ios/PalletPilot/Features/Upload/` — pallet form + video picker + upload VM.
- `ios/PalletPilot/Features/Processing/` — poll VM + status timeline view.
- `ios/PalletPilot/Services/` — `HealthService` (+ protocol; mocks in tests).
- `ios/PalletPilotTests/` — Swift Testing (decoding) + XCTest (networking/VM).
- `ios/PalletPilot/Info.plist` — includes `NSAllowsLocalNetworking` for dev HTTP.

## Conventions

- Views render; view models own state and side effects; services own HTTP.
- No HTTP in views; no invented endpoints/fields — see `docs/ios/API_CONTRACTS.md`.
- Paths verbatim, no trailing slash; `:` in item ids stays unencoded.
- `null` price means unknown, never 0; `Job.listings` is a stale-after-edit snapshot.

## Verification

- Build: open `ios/PalletPilot.xcodeproj`, scheme PalletPilot, iPhone simulator.
- `xcrun simctl list devices available` (pick an installed simulator, e.g. iPhone 17)
- `xcodebuild -project ios/PalletPilot.xcodeproj -scheme PalletPilot -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Backend must run locally first (`backend/AGENTS.md`); Home check uses `GET /health`.

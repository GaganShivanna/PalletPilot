# PalletPilot iOS — local startup

Phase 1 foundation: SwiftUI app + typed networking against the verified backend
contracts (`docs/ios/API_CONTRACTS.md`). No uploads, inventory, or pricing yet.

## Filming the demo (no experience needed)

Follow these steps in order. You need a Mac with Xcode installed, this
project folder, a short phone video of a pallet being unboxed (under
30 seconds works best), and the AI key already put in place by a developer
(`backend/.env` file — ask if you are not sure it is done).

### 1. Start the backend (the app's brain)

1. Open the **Terminal** app (Spotlight search: type `Terminal`, press Enter).
2. Type `cd`, press space, then **drag the PalletPilot folder** from Finder
   into the Terminal window and press Enter. This moves Terminal into the
   project.
3. Type `cd backend` and press Enter.
4. Type `.venv/bin/python -m uvicorn app.main:app` and press Enter.
5. Leave this window open. You will know it worked when the last lines say
   something like `Uvicorn running on http://127.0.0.1:8000`. If you close
   this window, the app stops working — just reopen it and repeat steps 2–4.

### 2. Open the app in Xcode

1. In Finder, open the PalletPilot folder, then the `ios` folder, and
   double-click `PalletPilot.xcodeproj`. Xcode opens.
2. At the top of the Xcode window, click the device dropdown (it may say
   something like "iPhone 17") and pick any iPhone simulator.
3. Press the **Play button** (top left, or ⌘R on your keyboard). The
   simulator (a fake iPhone on your screen) launches with the PalletPilot
   app. First launch can take a minute — that is normal.

### 3. Put your video inside the simulator

The simulator has its own photo library, separate from your Mac:

1. Find your pallet video in Finder.
2. **Drag the video file onto the simulator window** and drop it. It saves
   into the simulator's Photos app automatically.
3. (Alternative, if drag-and-drop misbehaves: open Terminal and run
   `xcrun simctl addmedia booted <video-file>`, replacing `<video-file>`
   with the file's path.)

### 4. Run the demo flow in the app

1. On the Home screen, tap **Check connection** — it should say Connected.
   If it says anything else, the backend from step 1 is not running.
2. Tap **New pallet from video**, type a name like "Demo pallet", and tap
   **Choose video**. Tap your clip to checkmark it, then **Select video**.
3. Tap **Create pallet and upload**. You will see a "Pallet created" message
   and a **Track progress** button — tap it.
4. Processing takes a few minutes on the first run (the AI is watching the
   whole video). Leave it alone; the progress screen updates by itself.
5. Tap **View inventory**, then tap an item: set its condition from the menu,
   type a price, and tap **Save** — look for the green "Saved" message.
6. Go back and open **Summary** (totals come straight from the server),
   then **Export** to share the CSV.

### If something goes wrong while filming

- **"Processing failed" in red:** the backend hit a problem. Keep the
  Terminal window from step 1 visible — its last lines usually say why
  (for example, a missing video encoder or API key).
- **Endless spinner on Processing:** the video may still be analyzing (large
  clips take a while). Give it up to a few minutes before retrying.
- **Old results on screen:** go back to Home and re-enter — the app always
  refetches from the server, so what you see is current.

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

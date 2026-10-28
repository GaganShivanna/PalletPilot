# ios/AGENTS.md

Subsystem rules for the PalletPilot iOS app. The root `AGENTS.md` also applies.

## State

No Xcode project exists yet. Conventions below apply when scaffolding.

## Stack

- SwiftUI, MVVM. Minimum iOS version: undecided — record here when chosen.

## Planned layout

- `ios/App/` — app entry, root composition.
- `ios/Features/<Feature>/` — views and view models per feature.
- `ios/Core/` — models, networking, shared UI.

## Verification

- No test target yet. When one exists, record the `xcodebuild` invocation here.

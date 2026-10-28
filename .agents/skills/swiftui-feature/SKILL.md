---
name: swiftui-feature
description: Build SwiftUI features in ios/ following MVVM placement and project conventions. Use when adding or changing iOS views, view models, models, or app state.
---

# SwiftUI Feature Development

Goal: Add or change iOS features with minimal, well-placed edits.

## Before writing code

1. Read `docs/REPO_MAP.md` for current iOS modules.
2. Read `ios/AGENTS.md` for layout and conventions.
3. Locate related views and view models with the repo-navigator procedure.

## Placement

- Follow the module layout in `ios/AGENTS.md`.
- Views render; view models own state and side effects; models stay dependency-free.
- Reuse existing components before creating new ones.

## Verification

- Build the affected target and run its tests (commands in `ios/AGENTS.md`).
- Prefer SwiftUI Previews for quick visual checks during development.
- Update `docs/REPO_MAP.md` if modules or dependencies changed.

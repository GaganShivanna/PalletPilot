# REPO_MAP.md

Feature and module index for PalletPilot. Read this before exploring
unfamiliar code. Verify entries against source; the map may lag the tree.

Last updated: 2026-10-28. State: config and docs only; no application code.

## Features

None implemented yet.

## Planned layout

- `ios/` — SwiftUI app (see `ios/AGENTS.md`). Not scaffolded.
- `backend/` — FastAPI service (see `backend/AGENTS.md`). Not scaffolded.

## Entry points

None. No app targets, servers, or CLIs exist.

## Dependencies

None. No package manifests (`Package.swift`, `Podfile`,
`requirements.txt`, and `pyproject.toml` are all absent).

## Tooling and config

- `AGENTS.md` — project-wide session rules.
- `docs/CURRENT_STATUS.md` — features, blockers, test status, P0 work.
- `.agents/skills/` — repo-navigator, context-optimizer, session-memory,
  swiftui-feature, fastapi-dev, debugging, api-integration.
- `.agents/memory/` — durable decisions, known issues, constraints.
- `.vscode/settings.json`, `.gitignore` — editor and ignore config.

## Tests

None. No test targets or runners configured.

## Needs verification

- Rebuild the Features section once the first modules land.
- Confirm SwiftUI/FastAPI versions when scaffolding.

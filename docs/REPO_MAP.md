# REPO_MAP.md

Feature and module index for PalletPilot. Read this before exploring
unfamiliar code. Verify entries against source; the map may lag the tree.

Last updated: 2026-10-28. State: backend Phase 2 done (mock end-to-end); iOS not started.

## Features

- Video-to-listings job (backend): `POST /jobs` upload -> `app/services/jobs.py`
  queue -> `app/services/pipeline.py` (frames -> provider segmentation ->
  identification -> photos w/ fallback -> fixture pricing -> listing drafts ->
  item persistence). All mock, no external calls.
- Pallets: `POST/GET /pallets`, `GET /pallets/{id}/items`, `PATCH /items/{id}`,
  `GET /pallets/{id}/export` (CSV). Financial summaries via
  `app/services/financials.py` (estimates; unpriced items excluded).
- Provider interface: `app/providers/` (base contracts, mock, factory, loud
  unimplemented real adapters). One DetectedProduct per physical item.
- Durable metadata: `app/services/persistence.py` (SQLite `meta.db`: jobs,
  pallets, items); restart marks interrupted jobs failed.

## Planned layout

- `ios/` — SwiftUI app (see `ios/AGENTS.md`). Not scaffolded.
- `backend/` — FastAPI service (see `backend/AGENTS.md`).
  - `app/routes/` — `health.py` (`GET /health`), `jobs.py` (`POST/GET /jobs`,
    `GET /jobs/{id}`, `GET /jobs/{id}/files/{path}`), `pallets.py`
    (`POST/GET /pallets`, `GET /pallets/{id}/items`, `GET …/export`),
    `items.py` (`GET/PATCH /items/{id}`).
  - `app/schemas/` — `jobs.py` (Job, JobStatus), `listings.py` (Listing, Price),
    `items.py` (Item, ItemPatch), `pallets.py` (Pallet, PalletSummary).
  - `app/providers/` — `base.py` (DetectedProduct/Identification/PhotoResult,
    protocols, errors), `mock.py`, `real.py` (raising adapters), `factory.py`.
  - `app/services/` — `jobs.py` (SQLite store + asyncio worker), `pipeline.py`,
    `frames.py` (OpenCV sampling), `segmentation.py`, `product_photos.py`
    (provider + fallback), `listings.py` (deterministic drafts),
    `pricing.py` (fixture table), `financials.py`, `exports.py` (CSV),
    `persistence.py` (SQLite Database).
  - `scripts/export_openapi.py` — regenerates `docs/openapi.json`.

## Entry points

- `backend/app/main.py` — `app` (uvicorn `app.main:app`), `create_app(settings)`.

## Dependencies

- `backend/requirements.txt`, `backend/requirements-dev.txt`. No iOS manifests yet.

## Tooling and config

- `AGENTS.md` — project-wide session rules.
- `docs/CURRENT_STATUS.md` — features, blockers, test status, P0 work.
- `.agents/skills/` — repo-navigator, context-optimizer, session-memory,
  swiftui-feature, fastapi-dev, debugging, api-integration.
- `.agents/memory/` — durable decisions, known issues, constraints.
- `.vscode/settings.json`, `.gitignore` — editor and ignore config.

## Tests

- `backend/tests/` — `test_jobs.py`, `test_providers.py`, `test_persistence.py`,
  `test_phase2.py` (mock e2e + failures); pytest; command in `backend/AGENTS.md`.
- `docs/FRONTEND_HANDOFF.md`, `docs/openapi.json` — client integration contract.

## Needs verification

- Rebuild the Features section once the first modules land.
- Confirm SwiftUI version when scaffolding iOS.

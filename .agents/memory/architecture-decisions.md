# Architecture Decisions

- 2026-10-28: Planned stack is SwiftUI (`ios/`) + FastAPI (`backend/`). Neither scaffolded yet.
- 2026-10-28: Single repo map at `docs/REPO_MAP.md`; removed `docs/FILE_MAP.md` to avoid duplicate indexes.
- 2026-10-28: `AGENTS.md` holds short stable rules; workflows live in `.agents/skills/` (7 skills).
- 2026-10-28: Map maintenance is rule-guided (see `AGENTS.md`); no git hooks installed yet.
- 2026-10-28: Backend job queue is in-memory (`app/services/jobs.py`) with one asyncio worker running blocking stages via `asyncio.to_thread`. Swap for DB + broker if durability/scale needed.


- 2026-10-28: Phase 1 provider interface landed: `backend/app/providers/` (`base.py` protocols + `DetectedProduct`/`Identification`/`PhotoResult`, `mock.py` deterministic labeled mocks, `real.py` adapters raising `ProviderUnavailable`, `factory.py` on `AI_PROVIDER`). Pipeline segmentation runs through the factory; mock default preserves stub behavior.
- 2026-10-28: Job metadata is durable in SQLite (`backend/app/services/persistence.py`, `data/meta.db`: jobs/pallets/items, WAL, per-operation connections for thread safety). Blobs stay on disk. Startup recovery marks non-terminal jobs failed ("Interrupted by restart").
- 2026-10-28: Item/pallet schemas added (`backend/app/schemas/items.py`, `pallets.py`); no routes yet — Phase 2. Unknown prices are null, never 0; profit figures are labeled estimates (`fee_rate` default 0.13).


- 2026-10-28: Phase 2 mock e2e landed: pipeline identifies (mock catalog: drill $45, espresso $32.50, sealed box unpriced/null) → photo fallback copy → fixture pricing (`backend/app/services/pricing.py`) → deterministic drafts (`listings.py`) → items persisted (`{job_id}:{item_id}`). Per-item failures degrade to reviewable drafts; transient identification errors retried (`provider_max_retries`).
- 2026-10-28: Pallet-job link is single-path: `POST /jobs` takes optional `pallet_id` form field, or `POST /pallets` with `job_id` claims finished items (`claim_job_items`, no reprocessing). Job→pallet resolved via `pallets.job_id` (`get_pallet_for_job`); one pallet per job (409 on double-link).
- 2026-10-28: Client contract is `docs/FRONTEND_HANDOFF.md` + `docs/openapi.json` (regen: `backend/scripts/export_openapi.py`). `GET /pallets/{id}` returns `PalletSummary` (estimates; unpriced excluded from revenue). CSV (`exports.py`) guards formula injection, empty-cell nulls, stable id order. Mock drafts carry `Demo draft` marker + `needs_review`.
- 2026-10-28: Phase 3 next step: implement real adapters in `backend/app/providers/real.py` from verified API docs (nothing verified yet), add bounded concurrency (semaphore on `provider_max_concurrency`) around external calls, test on real footage.

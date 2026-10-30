# CURRENT_STATUS.md

Last updated: 2026-10-30.

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
- Backend+AI integration (2026-10-30, `integration/backend-ai`): wired the
  AI engineer's hosted SAM segmentation (`app/providers/sam_*.py`) and Muse
  Spark identification (`app/providers/real.py`) behind the existing
  provider factory (`AI_PROVIDER=mock|sam|muse_spark|muse_image|real`).
  Integration glue only: lazy `sam_api` import (mock runs without
  `meta-sam-parser`), conservative Muse Spark→resale condition map with
  raw-observation preservation, `.env.example` additions. No route, schema,
  pricing, listing, or financial changes. Contract unchanged; details in
  `docs/AI_INTEGRATION.md`. Muse Image still unimplemented (fallback covers).

## Active blockers

- No `ios/` scaffolding exists.
- SAM API transport verified (job `084e388b…`: 3 completed `/responses`
  round-trips, zero matches — accepted as a valid completed result).
  End-to-end real AI verified: "trash can" smoke job `78bf4cbc…` PASSED
  (1 SAM track → 1 Spark ID → 1 item → CSV row; details in
  `docs/AI_INTEGRATION.md`). Broader detection accuracy untuned (AI
  engineer owns). No further paid calls without approval.
- Muse Image generation unimplemented; all product photos are fallbacks.
- A real-looking `MUSE_API_KEY` value was committed in `backend/.env.example`
  (since blanked); rotate the key if it was ever valid.
- Skill auto-discovery unconfirmed in an unsandboxed terminal
  (pending: `muse skills list --source project`).

## Test status

- Backend: 44/44 pytest pass (25 Phase 1+2, 13 AI-adapter HTTP-boundary,
  6 condition-mapping). Mock e2e over the full ASGI stack still green
  (7/7 Phase 2). Live TCP/uds serving could not be verified in-session:
  the sandbox denies all socket binds (uvicorn boots through "Application
  startup complete", then fails at bind). Recommend one unsandboxed run:
  `cd backend && .venv/bin/uvicorn app.main:app`.
- Skill validation: 7/7 pass `muse skills validate --json` with zero diagnostics.

## Remaining P0

1. Phase 3: live SAM/Muse Spark test on footage; Muse Image adapter or
   confirmed fallback; bounded concurrency for external calls
   (`PROVIDER_MAX_CONCURRENCY` unenforced — calls run sequentially).
2. Scaffold the `ios/` SwiftUI project against `docs/FRONTEND_HANDOFF.md`.
3. Phase 4: hardening, deployment config, demo prep.
4. Confirm skill discovery outside the sandbox.

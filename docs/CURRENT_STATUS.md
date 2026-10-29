# CURRENT_STATUS.md

Last updated: 2026-10-28.

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

## Active blockers

- No `ios/` scaffolding exists.
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

## Remaining P0

1. Phase 3: real SAM / Muse Spark / Muse Image adapters; bounded concurrency
   for external calls; test on footage.
2. Scaffold the `ios/` SwiftUI project against `docs/FRONTEND_HANDOFF.md`.
3. Phase 4: hardening, deployment config, demo prep.
4. Confirm skill discovery outside the sandbox.

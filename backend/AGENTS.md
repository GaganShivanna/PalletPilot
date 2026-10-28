# backend/AGENTS.md

Subsystem rules for the PalletPilot API service. The root `AGENTS.md` also applies.

## State

No service code exists yet. Conventions below apply when scaffolding.

## Stack

- FastAPI (Python). Version pins: undecided — record here with the manifest.

## Planned layout

- `backend/app/main.py` — app factory and router wiring.
- `backend/app/routes/` — thin route handlers.
- `backend/app/schemas/` — request/response models (contract source of truth, server side).
- `backend/app/services/` — business logic.

## Verification

- No test suite yet. When one exists, record the runner command here.

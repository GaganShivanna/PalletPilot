# backend/AGENTS.md

Subsystem rules for the PalletPilot API service. The root `AGENTS.md` also applies.

## State

Phase 1 done: upload -> frame sampling -> provider segmentation (mock default)
-> stub photos / listings. SQLite metadata (`meta.db`) with restart recovery.
Real SAM / Muse Spark / Muse Image adapters raise `ProviderUnavailable` until
integrated; `AI_PROVIDER` selects the provider set (mock default).

## Stack

- Python 3.13, FastAPI 0.162, OpenCV (headless) 5.0. Pins in `requirements.txt`; test deps in `requirements-dev.txt`.
- Secrets: `backend/.env` (gitignored), template in `.env.example`. Read via `app/config.py` only.

## Layout

- `backend/app/main.py` — app factory, lifespan (job store + worker), router wiring.
- `backend/app/config.py` — settings from env / `.env`.
- `backend/app/routes/` — thin route handlers.
- `backend/app/schemas/` — request/response models (contract source of truth, server side).
- `backend/app/providers/` — model adapters behind `base.py` protocols; selected
  via `AI_PROVIDER`. Mock output is labeled and reviewable; real adapters fail
  loudly until integrated. Never present mock output as real inference.
- `backend/app/services/` — business logic. `persistence.py` owns SQLite access;
  one `DetectedProduct`/item per physical item, never appearance-only merging.

## Verification

- Setup: `cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`
- Tests: `cd backend && .venv/bin/python -m pytest -q`
- Run: `cd backend && .venv/bin/uvicorn app.main:app --reload` (docs at `/docs`)

---
name: fastapi-dev
description: Build FastAPI routes, schemas, and services in backend/. Use when adding or changing API endpoints, request/response models, or server logic.
---

# FastAPI Development

Goal: Add or change server behavior with minimal, well-placed edits.

## Before writing code

1. Read `docs/REPO_MAP.md` for current backend modules.
2. Read `backend/AGENTS.md` for layout and conventions.
3. If iOS consumes the endpoint, also follow the api-integration skill.

## Placement

- Follow the module layout in `backend/AGENTS.md`.
- Keep route handlers thin; put logic in services and validation in schemas.
- Reuse existing dependencies and error handling before adding new ones.

## Verification

- Run targeted tests first, then the suite entry in `backend/AGENTS.md`.
- Exercise new endpoints against a local server run before finishing.
- Update `docs/REPO_MAP.md` if routes, modules, or dependencies changed.

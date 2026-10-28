---
name: api-integration
description: Define and wire the API contract between ios/ and backend/. Use when adding endpoints consumed by iOS, changing request/response shapes, or writing networking code.
---

# API Integration

Goal: Keep client and server in agreement on every endpoint.

## Procedure

1. Define the contract first: method, path, request/response shapes, error cases.
2. Implement the server side per the fastapi-dev skill; the client per swiftui-feature.
3. Keep server shapes in `backend/app/schemas/` and client models next to their call sites (see subsystem AGENTS.md files).
4. Verify end to end against a local server run before finishing.
5. Update `docs/REPO_MAP.md` for changed routes or client call sites.

## Rules

- Never change a response shape without updating its iOS call sites in the same change.
- Prefer additive, backward-compatible changes once the app is released.

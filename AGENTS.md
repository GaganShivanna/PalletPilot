# AGENTS.md

Muse Code reads this file as project rules when it runs in this directory.

## Project

- Name: PalletPilot
- Planned stack: SwiftUI app in `ios/`, FastAPI service in `backend/`.
- State: no application code yet; config and docs only.

## Guidance index

- Feature map: `docs/REPO_MAP.md` — read before unfamiliar code exploration.
- Status: `docs/CURRENT_STATUS.md` — features, blockers, test status, P0 work.
- Skills: `.agents/skills/` — repo-navigator, context-optimizer, session-memory, swiftui-feature, fastapi-dev, debugging, api-integration.
- Memory: `.agents/memory/` — durable decisions, known issues, constraints.
- Subsystem rules: `ios/AGENTS.md`, `backend/AGENTS.md`.

## Rules

### Context management

- Minimize repeated file reads and redundant searches.
- Prefer targeted source inspection over full-file dumps.
- Never scan the whole repository when a known file path or symbol is sufficient.
- Use progressive disclosure: repo map -> targeted search -> relevant code.
- Keep tool outputs concise without hiding errors.
- Use subagents only when isolation or parallelism adds value.

### Repository navigation

- Check docs/REPO_MAP.md before unfamiliar code exploration.
- Verify index entries against actual source when necessary.
- Update the repo map after structural changes.
- Never assume the repo map is perfectly current.

### Memory

- Preserve important architectural decisions and unresolved issues.
- Keep memory concise, factual, and organized by topic.
- Avoid duplicating entire source files in memory.
- Store references to source paths instead of copying code.

### Implementation

- Inspect existing implementations before writing new code.
- Reuse existing functions and dependencies.
- Make focused changes; avoid unrelated refactoring.
- Prefer running targeted tests before full test suites.
- Never skip necessary verification to save tokens.

### Response style

- Be concise and direct.
- Do not repeat the user's request.
- Report actual changes, test results, and remaining issues.
- Preserve important warnings and technical details.

## Repository map maintenance

After creating, deleting, renaming, or substantially changing a source module:

1. Check whether docs/REPO_MAP.md needs an update.
2. Update affected entries only.
3. Keep descriptions concise.
4. Verify new paths and relationships.
5. Do not rebuild the full index unnecessarily.

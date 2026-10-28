---
name: debugging
description: Diagnose failures systematically from reproduction to verified root-cause fix. Use when investigating crashes, errors, incorrect behavior, or failing tests.
---

# Debugging

Goal: Fix the root cause, verified — not the symptom.

## Procedure

1. Reproduce with the smallest reliable trigger; record exact steps and output.
2. Locate suspects via the repo-navigator procedure (map first, then targeted search).
3. Form one hypothesis at a time; test each against evidence before changing code.
4. Check `.agents/memory/known-issues.md` for matching past failures.
5. Apply the minimal fix at the root cause; avoid unrelated refactoring.
6. Re-run the reproduction plus related tests to confirm the fix and catch regressions.
7. Record durable findings (root cause, fix, paths) per the session-memory skill.

## Rules

- Never weaken correct code or tests to make a failure disappear.
- Preserve full error output until the cause is confirmed; summarize only in reports.

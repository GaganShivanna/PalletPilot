---
name: repo-navigator
description: Locate code via docs/REPO_MAP.md first, then targeted search. Use for unfamiliar code, debugging, and finding implementations.
---

# Repository Navigator

Goal: Locate relevant code without redundant repository scans.

## Procedure

1. Read docs/REPO_MAP.md if available.
2. Identify likely files and directories.
3. Verify file-map entries when needed.
4. Search targeted paths, symbols, and patterns.
5. Read only relevant code sections first.
6. Expand exploration only if necessary.
7. Avoid reopening unchanged files already in context.

## Index maintenance

After structural changes, update docs/REPO_MAP.md.

Track:

- File paths and module purposes
- Important symbols
- Dependencies and entry points
- Related tests

Avoid:

- Copying full source code
- Generated files and dependency directories
- Secrets and credentials
- Excessive detail

The index is a navigation aid, not a replacement
for source verification.

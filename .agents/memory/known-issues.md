# Known Issues

- 2026-10-28: `muse skills list` cannot run inside sandboxed sessions
  (global config unreadable); verify skill discovery from an unsandboxed
  terminal. Pending user confirmation.
- No application bugs recorded — no application code exists yet.


- 2026-10-28: `backend/.env.example` contained a real-looking `MUSE_API_KEY` value; blanked during Phase 1. Rotate the key if it was ever valid. Fixed (pending rotation confirmation).

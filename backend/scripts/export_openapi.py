"""Export the FastAPI OpenAPI schema for the frontend engineer.

Usage: cd backend && .venv/bin/python scripts/export_openapi.py
Writes: docs/openapi.json (regenerate after route/schema changes).
"""

import json
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent


def main() -> None:
    import sys

    sys.path.insert(0, str(BACKEND_DIR))
    from app.main import create_app

    schema = create_app().openapi()
    out = BACKEND_DIR.parent / "docs" / "openapi.json"
    out.write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out} ({len(schema['paths'])} paths)")


if __name__ == "__main__":
    main()

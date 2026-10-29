"""Durable metadata storage backed by SQLite (stdlib only, no new deps).

Threading: every method opens a short-lived connection, so the asyncio
worker thread and request handlers can share one :class:`Database`.
Large blobs (video, frames, photos) stay on disk under ``data_dir`` —
only metadata lives in ``meta.db``.
"""

import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    video_filename TEXT NOT NULL,
    frame_count INTEGER NOT NULL DEFAULT 0,
    listings_json TEXT NOT NULL DEFAULT '[]',
    error TEXT
);
CREATE TABLE IF NOT EXISTS pallets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    purchase_cost REAL NOT NULL DEFAULT 0,
    additional_costs REAL NOT NULL DEFAULT 0,
    job_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS items (
    id TEXT PRIMARY KEY,
    pallet_id TEXT,
    job_id TEXT,
    track_id TEXT,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'Uncategorized',
    brand TEXT,
    condition TEXT NOT NULL DEFAULT 'unknown',
    suggested_price REAL,
    currency TEXT NOT NULL DEFAULT 'USD',
    price_source TEXT NOT NULL DEFAULT 'none',
    price_confidence REAL,
    price_type TEXT NOT NULL DEFAULT 'unknown',
    original_image_url TEXT,
    image_urls_json TEXT NOT NULL DEFAULT '[]',
    confidence REAL,
    needs_review INTEGER NOT NULL DEFAULT 1,
    review_reasons_json TEXT NOT NULL DEFAULT '[]',
    provider TEXT NOT NULL DEFAULT 'mock',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_items_pallet ON items (pallet_id);
CREATE INDEX IF NOT EXISTS idx_items_job ON items (job_id);
"""


def utcnow() -> str:
    return datetime.now(UTC).isoformat()


class Database:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as conn:
            conn.executescript(SCHEMA)
            conn.execute("PRAGMA journal_mode=WAL")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    # -- jobs -----------------------------------------------------------

    def insert_job(self, job_id: str, video_filename: str) -> dict:
        now = utcnow()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO jobs (id, status, created_at, updated_at, video_filename)"
                " VALUES (?, 'queued', ?, ?, ?)",
                (job_id, now, now, video_filename),
            )
        return self.get_job(job_id)  # type: ignore[return-value]

    def get_job(self, job_id: str) -> dict | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
            return dict(row) if row else None

    def all_jobs(self) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM jobs ORDER BY created_at DESC").fetchall()
            return [dict(r) for r in rows]

    def update_job(self, job_id: str, **fields: object) -> None:
        fields["updated_at"] = utcnow()
        assignments = ", ".join(f"{k} = ?" for k in fields)
        with self._connect() as conn:
            conn.execute(
                f"UPDATE jobs SET {assignments} WHERE id = ?", (*fields.values(), job_id)
            )

    def recover_interrupted(self) -> int:
        """Mark jobs stuck in non-terminal states as failed after a restart."""
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE jobs SET status = 'failed', error = 'Interrupted by restart',"
                " updated_at = ? WHERE status NOT IN ('completed', 'failed')",
                (utcnow(),),
            )
            return cur.rowcount

    # -- pallets --------------------------------------------------------

    def insert_pallet(
        self,
        pallet_id: str,
        name: str,
        purchase_cost: float,
        additional_costs: float,
        job_id: str | None,
    ) -> dict:
        now = utcnow()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pallets (id, name, purchase_cost, additional_costs, job_id,"
                " created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (pallet_id, name, purchase_cost, additional_costs, job_id, now, now),
            )
        return self.get_pallet(pallet_id)  # type: ignore[return-value]

    def get_pallet(self, pallet_id: str) -> dict | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pallets WHERE id = ?", (pallet_id,)).fetchone()
            return dict(row) if row else None

    def get_pallet_for_job(self, job_id: str) -> dict | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pallets WHERE job_id = ?", (job_id,)).fetchone()
            return dict(row) if row else None

    def claim_job_items(self, job_id: str, pallet_id: str) -> int:
        """Attach a job's already-persisted items to a pallet (no reprocessing)."""
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE items SET pallet_id = ?, updated_at = ? WHERE job_id = ?",
                (pallet_id, utcnow(), job_id),
            )
            return cur.rowcount

    def update_pallet(self, pallet_id: str, **fields: object) -> None:
        fields["updated_at"] = utcnow()
        assignments = ", ".join(f"{k} = ?" for k in fields)
        with self._connect() as conn:
            conn.execute(
                f"UPDATE pallets SET {assignments} WHERE id = ?",
                (*fields.values(), pallet_id),
            )

    # -- items ----------------------------------------------------------

    def insert_item(self, item: dict) -> None:
        now = utcnow()
        item = _encode_item({**item, "created_at": now, "updated_at": now})
        cols = ", ".join(item.keys())
        placeholders = ", ".join("?" for _ in item)
        with self._connect() as conn:
            conn.execute(
                f"INSERT INTO items ({cols}) VALUES ({placeholders})",
                tuple(_encode(v) for v in item.values()),
            )

    def get_item(self, item_id: str) -> dict | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM items WHERE id = ?", (item_id,)).fetchone()
            return _decode_item(dict(row)) if row else None

    def items_for_pallet(self, pallet_id: str) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM items WHERE pallet_id = ? ORDER BY id", (pallet_id,)
            ).fetchall()
            return [_decode_item(dict(r)) for r in rows]

    def items_for_job(self, job_id: str) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM items WHERE job_id = ? ORDER BY id", (job_id,)
            ).fetchall()
            return [_decode_item(dict(r)) for r in rows]

    def update_item(self, item_id: str, **fields: object) -> None:
        fields = _encode_item(dict(fields))
        fields["updated_at"] = utcnow()
        assignments = ", ".join(f"{k} = ?" for k in fields)
        with self._connect() as conn:
            conn.execute(
                f"UPDATE items SET {assignments} WHERE id = ?",
                (*fields.values(), item_id),
            )


def _encode(value: object) -> object:
    if isinstance(value, (list, dict)):
        return json.dumps(value)
    if isinstance(value, bool):
        return int(value)
    return value


_ITEM_COLUMN_ALIASES = {"image_urls": "image_urls_json", "review_reasons": "review_reasons_json"}


def _encode_item(item: dict) -> dict:
    renamed = {_ITEM_COLUMN_ALIASES.get(k, k): v for k, v in item.items()}
    return {k: _encode(v) for k, v in renamed.items()}


def _decode_item(row: dict) -> dict:
    row["image_urls"] = json.loads(row.pop("image_urls_json") or "[]")
    row["review_reasons"] = json.loads(row.pop("review_reasons_json") or "[]")
    row["needs_review"] = bool(row["needs_review"])
    return row

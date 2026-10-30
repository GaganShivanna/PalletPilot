"""Durable job store (SQLite metadata) and a single background worker.

Job/file blobs stay on disk under ``data_dir``; status and listings live in
``meta.db`` so jobs survive restarts. Jobs found in a non-terminal state at
startup are marked failed explicitly — never silently resumed or dropped.
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime
from pathlib import Path

from app.config import Settings
from app.schemas.jobs import Job, JobStatus
from app.schemas.listings import Listing
from app.services.persistence import Database

log = logging.getLogger(__name__)


def _row_to_job(row: dict) -> Job:
    return Job(
        id=row["id"],
        status=JobStatus(row["status"]),
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
        video_filename=row["video_filename"],
        frame_count=row["frame_count"],
        listings=[Listing(**item) for item in json.loads(row["listings_json"] or "[]")],
        error=row["error"],
    )


class JobStore:
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.db = Database(data_dir / "meta.db")
        recovered = self.db.recover_interrupted()
        if recovered:
            log.warning("Marked %d interrupted job(s) as failed after restart", recovered)

    def job_dir(self, job_id: str) -> Path:
        return self.data_dir / "jobs" / job_id

    def create(self, video_filename: str) -> Job:
        row = self.db.insert_job(uuid.uuid4().hex, video_filename)
        return _row_to_job(row)

    def get(self, job_id: str) -> Job | None:
        row = self.db.get_job(job_id)
        return _row_to_job(row) if row else None

    def all(self) -> list[Job]:
        return [_row_to_job(row) for row in self.db.all_jobs()]

    def update(
        self,
        job_id: str,
        *,
        status: JobStatus | None = None,
        frame_count: int | None = None,
        listings: list[Listing] | None = None,
        error: str | None = None,
    ) -> None:
        fields: dict[str, object] = {}
        if status is not None:
            fields["status"] = status.value
        if frame_count is not None:
            fields["frame_count"] = frame_count
        if listings is not None:
            fields["listings_json"] = json.dumps([listing.model_dump() for listing in listings])
        if error is not None:
            fields["error"] = error
        if fields:
            self.db.update_job(job_id, **fields)


class JobQueue:
    def __init__(self, store: JobStore, settings: Settings):
        self.store = store
        self.settings = settings
        self._queue: asyncio.Queue[str] = asyncio.Queue()
        self._worker: asyncio.Task | None = None

    def start(self) -> None:
        self._worker = asyncio.create_task(self._run())

    async def stop(self) -> None:
        if self._worker:
            self._worker.cancel()
            try:
                await self._worker
            except asyncio.CancelledError:
                pass

    async def enqueue(self, job_id: str) -> None:
        await self._queue.put(job_id)

    async def _run(self) -> None:
        from app.services.pipeline import run_pipeline

        while True:
            job_id = await self._queue.get()
            try:
                # Pipeline stages are blocking (OpenCV, HTTP calls), so run off the event loop.
                await asyncio.to_thread(run_pipeline, job_id, self.store, self.settings)
            except Exception as exc:
                log.exception("Job %s failed", job_id)
                self.store.update(job_id, status=JobStatus.failed, error=str(exc))
            finally:
                self._queue.task_done()

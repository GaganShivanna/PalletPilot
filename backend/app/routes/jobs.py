import asyncio
import json
from pathlib import Path

from fastapi import APIRouter, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import FileResponse, StreamingResponse

from app.schemas.job_events import TERMINAL_EVENT_TYPES
from app.schemas.jobs import Job, JobCreated, JobStatus
from app.services.jobs import JobQueue, JobStore

router = APIRouter(prefix="/jobs", tags=["jobs"])

ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".webm", ".mkv"}
CHUNK_SIZE = 1024 * 1024

# Bounded SSE polling: lightweight indexed reads, not a busy-wait. Latency
# stays under ~POLL_INTERVAL_S per subscriber with no cross-thread signaling.
POLL_INTERVAL_S = 0.25
KEEPALIVE_EVERY_N_POLLS = 60  # comment line every ~15 s idle


def _store(request: Request) -> JobStore:
    return request.app.state.job_store


def _get_job_or_404(request: Request, job_id: str) -> Job:
    job = _store(request).get(job_id)
    if job is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Job not found")
    return job


@router.post("", status_code=status.HTTP_202_ACCEPTED, response_model=JobCreated)
async def create_job(
    request: Request, video: UploadFile, pallet_id: str | None = Form(default=None)
) -> JobCreated:
    ext = Path(video.filename or "").suffix.lower()
    if ext not in ALLOWED_VIDEO_EXTENSIONS:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, f"Unsupported video type: {ext or 'none'}")

    store = _store(request)
    if pallet_id is not None:
        pallet = store.db.get_pallet(pallet_id)
        if pallet is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Pallet not found")
        if pallet["job_id"] is not None:
            raise HTTPException(status.HTTP_409_CONFLICT, "Pallet already has a job")
    max_bytes = request.app.state.settings.max_upload_mb * 1024 * 1024
    job = store.create(video_filename=f"video{ext}")
    if pallet_id is not None:
        store.db.update_pallet(pallet_id, job_id=job.id)
    job_dir = store.job_dir(job.id)
    job_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    with open(job_dir / job.video_filename, "wb") as f:
        while chunk := await video.read(CHUNK_SIZE):
            written += len(chunk)
            if written > max_bytes:
                store.update(job.id, status=JobStatus.failed, error="Video too large")
                store.emit_event(job.id, "job.failed", payload={"error": "Video too large"})
                raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Video too large")
            f.write(chunk)

    queue: JobQueue = request.app.state.job_queue
    await queue.enqueue(job.id)
    return JobCreated(id=job.id, status=job.status)


@router.get("", response_model=list[Job])
def list_jobs(request: Request) -> list[Job]:
    return _store(request).all()


@router.get("/{job_id}", response_model=Job)
def get_job(request: Request, job_id: str) -> Job:
    return _get_job_or_404(request, job_id)


def _format_sse(event: dict) -> str:
    data = json.dumps(
        {
            "id": event["id"],
            "job_id": event["job_id"],
            "event_type": event["event_type"],
            "item_id": event["item_id"],
            "created_at": event["created_at"],
            "payload": event["payload"],
        }
    )
    return f"id: {event['id']}\nevent: {event['event_type']}\ndata: {data}\n\n"


def _resume_after_id(request: Request) -> int:
    """Parse Last-Event-ID (header first, ?last_event_id= fallback)."""
    raw = request.headers.get("last-event-id")
    if raw is None:
        raw = request.query_params.get("last_event_id")
    if raw is None:
        return 0
    try:
        return max(int(raw), 0)
    except ValueError:
        return 0


@router.get("/{job_id}/events")
async def job_events(request: Request, job_id: str) -> StreamingResponse:
    """Stream persisted job events; replay missed ones, close on terminal."""
    store = _store(request)
    _get_job_or_404(request, job_id)
    last_id = _resume_after_id(request)

    async def generate():
        nonlocal last_id
        idle_polls = 0
        while True:
            rows = store.db.events_after(job_id, last_id)
            if rows:
                idle_polls = 0
                for event in rows:
                    last_id = event["id"]
                    yield _format_sse(event)
                    if event["event_type"] in TERMINAL_EVENT_TYPES:
                        return
                continue
            # Caught up: close for terminal jobs (covers pre-event jobs),
            # otherwise wait for more (disconnect cancels this generator).
            job = store.get(job_id)
            if job is None or job.status in (JobStatus.completed, JobStatus.failed):
                return
            idle_polls += 1
            if idle_polls >= KEEPALIVE_EVERY_N_POLLS:
                idle_polls = 0
                yield ": keepalive\n\n"
            await asyncio.sleep(POLL_INTERVAL_S)

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/{job_id}/files/{file_path:path}")
def get_job_file(request: Request, job_id: str, file_path: str) -> FileResponse:
    _get_job_or_404(request, job_id)
    job_dir = _store(request).job_dir(job_id).resolve()
    target = (job_dir / file_path).resolve()
    if not target.is_relative_to(job_dir) or not target.is_file():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    return FileResponse(target)

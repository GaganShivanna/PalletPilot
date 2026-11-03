import asyncio
import json
from pathlib import Path

from fastapi import (
    APIRouter,
    File,
    Form,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse, StreamingResponse

from app.schemas.job_events import TERMINAL_EVENT_TYPES
from app.schemas.jobs import Job, JobCreated, JobStatus
from app.services.jobs import JobQueue, JobStore
from app.services.manifest import parse_manifest_csv


router = APIRouter(prefix="/jobs", tags=["jobs"])

ALLOWED_VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".m4v",
    ".avi",
    ".webm",
    ".mkv",
}

CHUNK_SIZE = 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024

POLL_INTERVAL_S = 0.25
KEEPALIVE_EVERY_N_POLLS = 60


def _store(request: Request) -> JobStore:
    return request.app.state.job_store


def _get_job_or_404(request: Request, job_id: str) -> Job:
    job = _store(request).get(job_id)

    if job is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Job not found",
        )

    return job


@router.post(
    "",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=JobCreated,
)
async def create_job(
    request: Request,
    video: UploadFile = File(...),
    pallet_id: str | None = Form(default=None),
    manifest: UploadFile | None = File(default=None),
) -> JobCreated:
    ext = Path(video.filename or "").suffix.lower()

    if ext not in ALLOWED_VIDEO_EXTENSIONS:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"Unsupported video type: {ext or 'none'}",
        )

    store = _store(request)

    if pallet_id is not None:
        pallet = store.db.get_pallet(pallet_id)

        if pallet is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                "Pallet not found",
            )

        if pallet["job_id"] is not None:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Pallet already has a job",
            )

    # Validate the optional manifest before creating a job.
    manifest_bytes = None

    if manifest is not None:
        try:
            manifest_ext = Path(
                manifest.filename or ""
            ).suffix.lower()

            if manifest_ext != ".csv":
                raise HTTPException(
                    status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                    "Manifest must be a CSV file",
                )

            manifest_bytes = await manifest.read(
                MAX_MANIFEST_BYTES + 1
            )

            try:
                parse_manifest_csv(manifest_bytes)
            except ValueError as exc:
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_ENTITY,
                    str(exc),
                ) from None

        finally:
            await manifest.close()

    max_bytes = (
        request.app.state.settings.max_upload_mb
        * 1024
        * 1024
    )

    job = store.create(video_filename=f"video{ext}")

    if pallet_id is not None:
        store.db.update_pallet(
            pallet_id,
            job_id=job.id,
        )

    job_dir = store.job_dir(job.id)
    job_dir.mkdir(parents=True, exist_ok=True)

    if manifest_bytes is not None:
        (job_dir / "manifest.csv").write_bytes(
            manifest_bytes
        )

    written = 0

    with open(job_dir / job.video_filename, "wb") as output:
        while chunk := await video.read(CHUNK_SIZE):
            written += len(chunk)

            if written > max_bytes:
                store.update(
                    job.id,
                    status=JobStatus.failed,
                    error="Video too large",
                )

                store.emit_event(
                    job.id,
                    "job.failed",
                    payload={"error": "Video too large"},
                )

                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    "Video too large",
                )

            output.write(chunk)

    queue: JobQueue = request.app.state.job_queue
    await queue.enqueue(job.id)

    return JobCreated(
        id=job.id,
        status=job.status,
    )


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

    return (
        f"id: {event['id']}\n"
        f"event: {event['event_type']}\n"
        f"data: {data}\n\n"
    )


def _resume_after_id(request: Request) -> int:
    """Read Last-Event-ID, falling back to the query parameter."""
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
async def job_events(
    request: Request,
    job_id: str,
) -> StreamingResponse:
    """Replay persisted events, then follow until the job ends."""
    store = _store(request)
    _get_job_or_404(request, job_id)

    last_id = _resume_after_id(request)

    async def generate():
        nonlocal last_id
        idle_polls = 0
        terminal_polls = 0

        while True:
            rows = store.db.events_after(job_id, last_id)

            if rows:
                idle_polls = 0
                terminal_polls = 0

                for event in rows:
                    last_id = event["id"]

                    yield _format_sse(event)

                    if event["event_type"] in TERMINAL_EVENT_TYPES:
                        return

                continue

            job = store.get(job_id)

            if job is None or job.status in (
                JobStatus.completed,
                JobStatus.failed,
            ):
                # The terminal status commits just before its event;
                # require consecutive terminal polls so a reader landing
                # in that gap still sees the closing event.
                terminal_polls += 1
                if terminal_polls >= 3:
                    return
                await asyncio.sleep(POLL_INTERVAL_S)
                continue

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
def get_job_file(
    request: Request,
    job_id: str,
    file_path: str,
) -> FileResponse:
    _get_job_or_404(request, job_id)

    job_dir = _store(request).job_dir(job_id).resolve()
    target = (job_dir / file_path).resolve()

    if not target.is_relative_to(job_dir) or not target.is_file():
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "File not found",
        )

    return FileResponse(target)
from pathlib import Path

from fastapi import APIRouter, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import FileResponse

from app.schemas.jobs import Job, JobCreated, JobStatus
from app.services.jobs import JobQueue, JobStore

router = APIRouter(prefix="/jobs", tags=["jobs"])

ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".webm", ".mkv"}
CHUNK_SIZE = 1024 * 1024


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


@router.get("/{job_id}/files/{file_path:path}")
def get_job_file(request: Request, job_id: str, file_path: str) -> FileResponse:
    _get_job_or_404(request, job_id)
    job_dir = _store(request).job_dir(job_id).resolve()
    target = (job_dir / file_path).resolve()
    if not target.is_relative_to(job_dir) or not target.is_file():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    return FileResponse(target)

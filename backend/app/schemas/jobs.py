from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel

from app.schemas.listings import Listing


class JobStatus(StrEnum):
    queued = "queued"
    sampling_frames = "sampling_frames"
    segmenting = "segmenting"
    identifying = "identifying"
    generating_photos = "generating_photos"
    generating_listings = "generating_listings"
    completed = "completed"
    failed = "failed"


class Job(BaseModel):
    id: str
    status: JobStatus = JobStatus.queued
    created_at: datetime
    updated_at: datetime
    video_filename: str
    frame_count: int = 0
    listings: list[Listing] = []
    error: str | None = None


class JobCreated(BaseModel):
    id: str
    status: JobStatus

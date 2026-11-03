"""Job-event contract for the SSE stream (GET /jobs/{job_id}/events).

Event IDs are monotonically increasing integers scoped to one job. Clients
resume with Last-Event-ID and deduplicate by id: delivery is at-least-once
per connection, ordered by id. Payloads stay small — clients fetch full
records from the existing item endpoints.
"""

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel


class JobEventType(StrEnum):
    started = "job.started"
    segmentation_completed = "segmentation.completed"
    listing_ready = "listing.ready"
    completed = "job.completed"
    failed = "job.failed"


TERMINAL_EVENT_TYPES = frozenset({JobEventType.completed, JobEventType.failed})


class JobEvent(BaseModel):
    id: int
    job_id: str
    event_type: JobEventType
    item_id: str | None = None
    created_at: datetime
    payload: dict = {}

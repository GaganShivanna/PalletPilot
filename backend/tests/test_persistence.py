"""Persistence tests: job/pallet/item round-trips and restart recovery."""

import uuid

from app.schemas.jobs import JobStatus
from app.services.jobs import JobStore


def test_job_round_trip_and_update(tmp_path):
    store = JobStore(tmp_path / "data")
    job = store.create("video.mp4")
    assert job.status == JobStatus.queued

    store.update(job.id, status=JobStatus.sampling_frames, frame_count=6)
    fetched = store.get(job.id)
    assert fetched is not None
    assert fetched.status == JobStatus.sampling_frames
    assert fetched.frame_count == 6
    assert fetched.video_filename == "video.mp4"
    assert [j.id for j in store.all()] == [job.id]


def test_jobs_survive_store_recreation(tmp_path):
    data_dir = tmp_path / "data"
    first = JobStore(data_dir)
    job = first.create("video.mp4")
    first.update(job.id, status=JobStatus.completed, frame_count=6)

    second = JobStore(data_dir)
    fetched = second.get(job.id)
    assert fetched is not None
    assert fetched.status == JobStatus.completed
    assert fetched.frame_count == 6


def test_restart_marks_interrupted_jobs_failed(tmp_path):
    data_dir = tmp_path / "data"
    first = JobStore(data_dir)
    stuck = first.create("video.mp4")
    first.update(stuck.id, status=JobStatus.segmenting)
    done = first.create("video.mp4")
    first.update(done.id, status=JobStatus.completed)

    second = JobStore(data_dir)  # simulates restart recovery
    assert second.get(stuck.id).status == JobStatus.failed
    assert "restart" in (second.get(stuck.id).error or "").lower()
    assert second.get(done.id).status == JobStatus.completed


def test_unknown_job_returns_none(tmp_path):
    store = JobStore(tmp_path / "data")
    assert store.get(uuid.uuid4().hex) is None


def test_pallet_and_item_round_trip(tmp_path):
    store = JobStore(tmp_path / "data")
    pallet = store.db.insert_pallet("p1", "Test pallet", 100.0, 10.0, job_id=None)
    assert pallet["name"] == "Test pallet"

    store.db.insert_item(
        {
            "id": "p1:item_0",
            "pallet_id": "p1",
            "job_id": None,
            "track_id": "track_00000",
            "title": "Mock Widget A",
            "suggested_price": 12.5,
            "image_urls": ["/jobs/j/files/photos/p1_item_0.jpg"],
            "needs_review": True,
        }
    )
    items = store.db.items_for_pallet("p1")
    assert len(items) == 1
    assert items[0]["title"] == "Mock Widget A"
    assert items[0]["suggested_price"] == 12.5
    assert items[0]["needs_review"] is True

    store.db.update_item("p1:item_0", title="Edited title", suggested_price=None)
    assert store.db.get_item("p1:item_0")["title"] == "Edited title"
    assert store.db.get_item("p1:item_0")["suggested_price"] is None

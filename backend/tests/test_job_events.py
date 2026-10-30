"""SSE job events: format, ordering, replay, resume, failure, disconnect.

All tests use mock providers (ai_provider="mock" is pinned explicitly on
every fixture — never the ambient .env). No network calls, no paid inference.
"""

import io
import json
import threading

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.providers.factory import Providers
from app.providers.mock import (
    MockIdentificationProvider,
    MockPhotoProvider,
    MockSegmentationProvider,
)
from app.services.persistence import Database
from tests.test_phase2 import make_video
from tests.test_progressive import GatedIdentificationProvider


@pytest.fixture
def settings(tmp_path):
    return Settings(_env_file=None, data_dir=tmp_path / "data", ai_provider="mock")


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def start_mock_job(client, tmp_path, video_name="v.mp4"):
    pallet = client.post(
        "/pallets",
        json={"name": "SSE pallet", "purchase_cost": 0.0, "additional_costs": 0.0},
    ).json()
    video = make_video(tmp_path / video_name)
    with open(video, "rb") as f:
        resp = client.post(
            "/jobs",
            files={"video": (video_name, f, "video/mp4")},
            data={"pallet_id": pallet["id"]},
        )
    assert resp.status_code == 202
    return pallet["id"], resp.json()["id"]


def wait_for_job(client, job_id, timeout_s=30.0):
    import time

    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        job = client.get(f"/jobs/{job_id}").json()
        if job["status"] in ("completed", "failed"):
            return job
        time.sleep(0.05)
    raise TimeoutError(f"job {job_id} did not finish")


def parse_sse_body(text):
    """Parse SSE frames; skip `: keepalive` comments."""
    events = []
    for block in text.strip().split("\n\n"):
        record = {}
        for line in block.splitlines():
            if not line or line.startswith(":"):
                continue
            key, _, value = line.partition(": ")
            record[key] = value
        if record:
            record["data"] = json.loads(record["data"])
            events.append(record)
    return events


def test_sse_response_format(client, tmp_path):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    resp = client.get(f"/jobs/{job_id}/events")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    assert resp.headers["cache-control"] == "no-cache"
    assert "\n\n" in resp.text  # blank-line frame separators

    events = parse_sse_body(resp.text)
    assert len(events) > 0
    for frame in events:
        assert set(frame) >= {"id", "event", "data"}
        assert frame["data"]["job_id"] == job_id
        assert frame["data"]["event_type"] == frame["event"]


def test_event_ordering(client, tmp_path):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert [int(e["id"]) for e in events] == list(range(1, len(events) + 1))
    assert [e["event"] for e in events] == [
        "job.started",
        "segmentation.completed",
        "listing.ready",
        "listing.ready",
        "listing.ready",
        "job.completed",
    ]
    assert events[1]["data"]["payload"] == {"track_count": 3}
    assert events[-1]["data"]["payload"] == {"item_count": 3}


def test_listing_ready_after_persistence(client, tmp_path, settings):
    """Every listing.ready observed on a live stream already has its row."""
    _, job_id = start_mock_job(client, tmp_path)
    db = Database(settings.data_dir / "meta.db")

    seen = []
    with client.stream("GET", f"/jobs/{job_id}/events") as resp:
        for line in resp.iter_lines():
            if line.startswith("data: "):
                data = json.loads(line[len("data: ") :])
                if data["event_type"] == "listing.ready":
                    item_id = data["item_id"]
                    assert data["payload"] == {"item_id": item_id}
                    assert db.get_item(item_id) is not None
                    seen.append(item_id)

    assert len(seen) == 3


def test_multiple_listing_ready_ids_match_db(client, tmp_path, settings):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    ready = [e for e in events if e["event"] == "listing.ready"]
    assert len(ready) == 3
    item_ids = [e["data"]["item_id"] for e in ready]
    assert len(set(item_ids)) == 3

    db = Database(settings.data_dir / "meta.db")
    rows = db.items_for_job(job_id)
    assert sorted(r["id"] for r in rows) == sorted(item_ids)


def test_completed_replay_terminates(client, tmp_path):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    # Buffered GET returns only because the server closes the stream.
    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert events[-1]["event"] == "job.completed"
    assert len(events) == 6  # started + segmentation + 3 ready + completed


def test_failed_job_delivers_job_failed(client, tmp_path):
    resp = client.post(
        "/jobs",
        files={"video": ("bad.mp4", io.BytesIO(b"\x00\x01notavideo"), "video/mp4")},
    )
    assert resp.status_code == 202
    job_id = resp.json()["id"]
    assert wait_for_job(client, job_id)["status"] == "failed"

    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert [e["event"] for e in events] == ["job.started", "job.failed"]
    assert "Could not open video" in events[-1]["data"]["payload"]["error"]


class EmptySegmentationProvider:
    provider_name = "empty_test"

    def detect(self, frame_paths, out_dir):
        out_dir.mkdir(parents=True, exist_ok=True)
        return []


def test_empty_detection_completes(client, tmp_path, monkeypatch):
    monkeypatch.setattr(
        "app.services.pipeline.get_providers",
        lambda settings: Providers(
            EmptySegmentationProvider(),
            MockIdentificationProvider(),
            MockPhotoProvider(),
        ),
    )
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert [e["event"] for e in events] == [
        "job.started",
        "segmentation.completed",
        "job.completed",
    ]
    assert events[1]["data"]["payload"] == {"track_count": 0}
    assert events[2]["data"]["payload"] == {"item_count": 0}


def test_last_event_id_resumes(client, tmp_path):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"

    full = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert [int(e["id"]) for e in full] == [1, 2, 3, 4, 5, 6]

    resumed = parse_sse_body(
        client.get(f"/jobs/{job_id}/events", headers={"Last-Event-ID": "2"}).text
    )
    assert [int(e["id"]) for e in resumed] == [3, 4, 5, 6]

    via_query = parse_sse_body(
        client.get(f"/jobs/{job_id}/events?last_event_id=5").text
    )
    assert [int(e["id"]) for e in via_query] == [6]


def test_unknown_job_404(client):
    resp = client.get("/jobs/does-not-exist/events")
    assert resp.status_code == 404
    assert resp.headers["content-type"].startswith("application/json")


def _collect_stream(client, job_id, out, index):
    with client.stream("GET", f"/jobs/{job_id}/events") as resp:
        out[index] = parse_sse_body(resp.read().decode("utf-8"))


def test_two_subscribers_same_history(settings, tmp_path, monkeypatch):
    gate = GatedIdentificationProvider()
    monkeypatch.setattr(
        "app.services.pipeline.get_providers",
        lambda s: Providers(MockSegmentationProvider(), gate, MockPhotoProvider()),
    )
    app = create_app(settings)
    with TestClient(app) as client:
        _, job_id = start_mock_job(client, tmp_path)
        assert gate.reached_item_2.wait(timeout=15)

        # Second client, own portal; shares the app (store + worker).
        other = TestClient(app)
        out = [None, None]
        threads = [
            threading.Thread(target=_collect_stream, args=(client, job_id, out, 0)),
            threading.Thread(target=_collect_stream, args=(other, job_id, out, 1)),
        ]
        try:
            for t in threads:
                t.start()
            gate.release.set()
            for t in threads:
                t.join(timeout=30)
                assert not t.is_alive()
        finally:
            gate.release.set()

        assert wait_for_job(client, job_id)["status"] == "completed"
        assert out[0] is not None and out[1] is not None
        assert [e["id"] for e in out[0]] == [e["id"] for e in out[1]]
        assert [e["event"] for e in out[0]] == [
            "job.started",
            "segmentation.completed",
            "listing.ready",
            "listing.ready",
            "listing.ready",
            "job.completed",
        ]


def test_events_survive_reopen(client, tmp_path, settings):
    _, job_id = start_mock_job(client, tmp_path)
    assert wait_for_job(client, job_id)["status"] == "completed"
    before = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)

    reopened = Database(settings.data_dir / "meta.db")
    rows = reopened.events_after(job_id, 0)
    assert [r["id"] for r in rows] == [int(e["id"]) for e in before]
    assert [r["event_type"] for r in rows] == [e["event"] for e in before]


def test_disconnect_does_not_stop_job(client, tmp_path, monkeypatch, settings):
    gate = GatedIdentificationProvider()
    monkeypatch.setattr(
        "app.services.pipeline.get_providers",
        lambda s: Providers(MockSegmentationProvider(), gate, MockPhotoProvider()),
    )
    pallet_id, job_id = start_mock_job(client, tmp_path)
    assert gate.reached_item_2.wait(timeout=15)

    try:
        with client.stream("GET", f"/jobs/{job_id}/events") as resp:
            for line in resp.iter_lines():
                if line == "event: listing.ready":
                    break  # disconnect right after the first item event
    finally:
        gate.release.set()

    assert wait_for_job(client, job_id)["status"] == "completed"
    assert len(client.get(f"/pallets/{pallet_id}/items").json()) == 3
    events = parse_sse_body(client.get(f"/jobs/{job_id}/events").text)
    assert len(events) == 6  # full history intact for the next subscriber

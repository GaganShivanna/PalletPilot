import time
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.frames import sample_frames


def make_video(path: Path, seconds: float = 2.0, fps: int = 30) -> Path:
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (64, 48))
    for i in range(int(seconds * fps)):
        writer.write(np.full((48, 64, 3), i % 255, dtype=np.uint8))
    writer.release()
    return path


@pytest.fixture
def client(tmp_path):
    settings = Settings(_env_file=None, data_dir=tmp_path / "data", sample_fps=3)
    with TestClient(create_app(settings)) as c:
        yield c


def test_sample_frames_rate(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=2.0, fps=30)
    frames = sample_frames(video, tmp_path / "frames", fps=3, max_frames=100)
    assert len(frames) == 6


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_job_runs_end_to_end(client, tmp_path):
    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        resp = client.post("/jobs", files={"video": ("v.mp4", f, "video/mp4")})
    assert resp.status_code == 202
    job_id = resp.json()["id"]

    for _ in range(50):
        job = client.get(f"/jobs/{job_id}").json()
        if job["status"] in ("completed", "failed"):
            break
        time.sleep(0.1)

    assert job["status"] == "completed", job.get("error")
    assert job["frame_count"] == 6
    assert job["listings"]
    image_url = job["listings"][0]["image_urls"][0]
    assert client.get(image_url).status_code == 200


def test_rejects_non_video(client):
    resp = client.post("/jobs", files={"video": ("notes.txt", b"hi", "text/plain")})
    assert resp.status_code == 415


def test_file_route_blocks_traversal(client, tmp_path):
    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        job_id = client.post("/jobs", files={"video": ("v.mp4", f, "video/mp4")}).json()["id"]
    assert client.get(f"/jobs/{job_id}/files/..%2F..%2F..%2Fetc%2Fpasswd").status_code == 404


def test_unknown_job_404(client):
    assert client.get("/jobs/nope").status_code == 404

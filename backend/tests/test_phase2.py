"""Phase 2: mock end-to-end workflow, editing, CSV, and failure cases."""

import csv
import io
import time
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.providers.base import DetectedProduct, Identification, ProviderError
from app.providers.factory import Providers
from app.providers.mock import MockPhotoProvider, MockSegmentationProvider
from app.services.pipeline import identify_with_fallback


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


def wait_for_job(client: TestClient, job_id: str, timeout_s: float = 15.0) -> dict:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        job = client.get(f"/jobs/{job_id}").json()
        if job["status"] in ("completed", "failed"):
            return job
        time.sleep(0.1)
    raise TimeoutError(f"job {job_id} did not finish within {timeout_s}s")


def test_end_to_end_mock_workflow(client, tmp_path):
    # 1. Create a pallet with costs.
    pallet = client.post(
        "/pallets", json={"name": "Demo pallet", "purchase_cost": 20.0, "additional_costs": 5.0}
    ).json()
    assert pallet["status"] == "empty"

    # 2-3. Upload a video linked to the pallet.
    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        resp = client.post(
            "/jobs", files={"video": ("v.mp4", f, "video/mp4")}, data={"pallet_id": pallet["id"]}
        )
    assert resp.status_code == 202
    job_id = resp.json()["id"]

    # 4. Bounded wait for completion.
    job = wait_for_job(client, job_id)
    assert job["status"] == "completed", job.get("error")
    assert job["frame_count"] == 6
    assert len(job["listings"]) == 3  # job contract preserved

    # 5-6. Items persisted with mock drafts.
    items = client.get(f"/pallets/{pallet['id']}/items").json()
    assert len(items) == 3
    by_title = {i["title"]: i for i in items}
    drill = by_title["Acme Cordless Drill"]
    assert drill["brand"] == "Acme"
    assert drill["suggested_price"] == 45.0
    assert drill["price_source"] == "mock_fixture"
    assert drill["needs_review"] is True
    assert "untested" in drill["description"].lower()
    assert "working" not in drill["description"].lower()
    assert "Demo draft" in drill["description"]
    assert drill["original_image_url"]
    assert client.get(drill["image_urls"][0]).status_code == 200  # photo fallback served

    sealed = by_title["Unidentified sealed box"]
    assert sealed["suggested_price"] is None  # unknown price is null, not zero
    assert sealed["price_source"] == "none"
    assert sealed["confidence"] == 0.1

    # 7. Financial totals exclude the unpriced item.
    summary = client.get(f"/pallets/{pallet['id']}").json()
    assert summary["pallet"]["status"] == "ready"
    assert summary["pallet"]["item_count"] == 3
    assert summary["unpriced_item_count"] == 1
    assert summary["estimated_revenue"] == 77.5
    assert summary["estimated_fees"] == round(77.5 * 0.13, 2)
    assert summary["projected_profit"] == round(77.5 - round(77.5 * 0.13, 2) - 25.0, 2)
    assert summary["estimates"] is True

    # 8-9. Edit the unpriced item; summary updates.
    patched = client.patch(
        f"/items/{sealed['id']}", json={"suggested_price": 10.0, "title": "Sealed box (lot)"}
    ).json()
    assert patched["title"] == "Sealed box (lot)"
    assert patched["suggested_price"] == 10.0
    assert patched["brand"] is None  # untouched fields preserved
    summary2 = client.get(f"/pallets/{pallet['id']}").json()
    assert summary2["estimated_revenue"] == 87.5
    assert summary2["unpriced_item_count"] == 0

    # 10. CSV validates: columns, quoting, empty-not-zero prices, edits included.
    export = client.get(f"/pallets/{pallet['id']}/export")
    assert export.status_code == 200
    assert "text/csv" in export.headers["content-type"]
    rows = list(csv.DictReader(io.StringIO(export.text)))
    assert len(rows) == 3
    assert list(rows[0].keys()) == [
        "item_id", "title", "description", "category", "brand",
        "condition", "suggested_price", "currency", "image_url", "review_status",
    ]
    assert all(r["review_status"] == "needs_review" for r in rows)
    assert "Sealed box (lot)" in [r["title"] for r in rows]
    assert [r["item_id"] for r in rows] == sorted(r["item_id"] for r in rows)


def test_corrupted_video_fails_job_with_error(client, tmp_path):
    video_path = tmp_path / "bad.mp4"
    video_path.write_bytes(b"not a video at all" * 100)
    with open(video_path, "rb") as f:
        job_id = client.post("/jobs", files={"video": ("bad.mp4", f, "video/mp4")}).json()["id"]
    job = wait_for_job(client, job_id)
    assert job["status"] == "failed"
    assert job["error"]


def test_pallet_claims_completed_job_without_reprocessing(client, tmp_path):
    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        job_id = client.post("/jobs", files={"video": ("v.mp4", f, "video/mp4")}).json()["id"]
    assert wait_for_job(client, job_id)["status"] == "completed"

    pallet = client.post("/pallets", json={"name": "Claimed", "job_id": job_id}).json()
    assert pallet["job_id"] == job_id
    items = client.get(f"/pallets/{pallet['id']}/items").json()
    assert len(items) == 3
    assert all(i["pallet_id"] == pallet["id"] for i in items)

    # A job can only be linked once.
    assert client.post("/pallets", json={"name": "Dup", "job_id": job_id}).status_code == 409
    assert client.post("/pallets", json={"name": "Missing", "job_id": "nope"}).status_code == 404


def test_patch_validation_and_404s(client, tmp_path):
    assert client.patch("/items/nope", json={"title": "x"}).status_code == 404
    assert client.get("/items/nope").status_code == 404
    assert client.get("/pallets/nope").status_code == 404
    assert client.get("/pallets/nope/items").status_code == 404
    assert client.get("/pallets/nope/export").status_code == 404

    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        job_id = client.post("/jobs", files={"video": ("v.mp4", f, "video/mp4")}).json()["id"]
    assert wait_for_job(client, job_id)["status"] == "completed"
    pallet_id = client.post("/pallets", json={"name": "P", "job_id": job_id}).json()["id"]
    item_id = client.get(f"/pallets/{pallet_id}/items").json()[0]["id"]

    assert client.patch(f"/items/{item_id}", json={"suggested_price": -1}).status_code == 422
    assert client.patch(f"/items/{item_id}", json={"condition": "minty"}).status_code == 422
    ok = client.patch(f"/items/{item_id}", json={"condition": "fair", "suggested_price": None})
    assert ok.status_code == 200
    assert ok.json()["condition"] == "fair"
    assert ok.json()["suggested_price"] is None


def test_csv_escapes_formulas_and_commas(client, tmp_path):
    video = make_video(tmp_path / "v.mp4")
    with open(video, "rb") as f:
        job_id = client.post("/jobs", files={"video": ("v.mp4", f, "video/mp4")}).json()["id"]
    assert wait_for_job(client, job_id)["status"] == "completed"
    pallet_id = client.post("/pallets", json={"name": "P", "job_id": job_id}).json()["id"]
    item_id = client.get(f"/pallets/{pallet_id}/items").json()[0]["id"]
    client.patch(f"/items/{item_id}", json={"title": '=1+1,"quoted"', "description": "@evil"})

    rows = list(csv.DictReader(io.StringIO(client.get(f"/pallets/{pallet_id}/export").text)))
    edited = next(r for r in rows if r["item_id"] == item_id)
    assert edited["title"] == "'=1+1,\"quoted\""
    assert edited["description"] == "'@evil"


class _FlakyIdentification:
    provider_name = "mock"

    def __init__(self, failures: int, transient: bool):
        self.failures = failures
        self.transient = transient
        self.calls = 0

    def identify(self, product: DetectedProduct) -> Identification:
        self.calls += 1
        if self.calls <= self.failures:
            raise ProviderError("boom", transient=self.transient)
        return Identification(name="Recovered", provider="mock")


def _providers_with(identification) -> Providers:
    return Providers(
        segmentation=MockSegmentationProvider(),
        identification=identification,
        photos=MockPhotoProvider(),
    )


def test_identification_retries_transient_then_succeeds(tmp_path):
    product = DetectedProduct(item_id="item_0", track_id="track_0", frame_path=str(tmp_path))
    flaky = _FlakyIdentification(failures=1, transient=True)
    result = identify_with_fallback(product, _providers_with(flaky), max_retries=2)
    assert result.name == "Recovered"
    assert flaky.calls == 2


def test_identification_failure_degrades_to_reviewable_draft(tmp_path):
    product = DetectedProduct(item_id="item_0", track_id="track_0", frame_path=str(tmp_path))
    flaky = _FlakyIdentification(failures=99, transient=False)
    result = identify_with_fallback(product, _providers_with(flaky), max_retries=2)
    assert result.needs_review is True
    assert "item_0" in result.name
    assert result.review_reasons

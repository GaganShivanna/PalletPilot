
import io
import threading
import time

import cv2
import numpy as np
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.providers.factory import Providers
from app.providers.mock import (
    MockIdentificationProvider,
    MockSegmentationProvider,
    MockPhotoProvider,
)


# --------------------------------------
# 1. Create a test video
# --------------------------------------

def make_video(path):
    writer = cv2.VideoWriter(
        str(path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        3.0,
        (320, 240),
    )

    assert writer.isOpened()

    for i in range(12):
        frame = np.full(
            (240, 320, 3),
            fill_value=(i * 15) % 255,
            dtype=np.uint8,
        )
        writer.write(frame)

    writer.release()
    return path.read_bytes()


# --------------------------------------
# 2. Fake identification provider
# --------------------------------------

class GatedIdentificationProvider:
    provider_name = "gated_test"

    def __init__(self):
        self.reached_item_2 = threading.Event()
        self.release = threading.Event()
        self.call_count = 0
        self.delegate = MockIdentificationProvider()

    def identify(self, product):
        self.call_count += 1

        # Pause BEFORE identifying the second item.
        if self.call_count == 2:
            self.reached_item_2.set()

            if not self.release.wait(timeout=15):
                raise TimeoutError(
                    "Test never released Item 2"
                )

        return self.delegate.identify(product)


# --------------------------------------
# 3. Test incremental persistence
# --------------------------------------

def test_incremental_item_visibility(
    tmp_path,
    monkeypatch,
):
    # Use isolated test settings and database.
    settings = Settings(
        data_dir=tmp_path / "data",
        ai_provider="mock",
    )

    gate = GatedIdentificationProvider()

    # Replace the real provider factory temporarily.
    monkeypatch.setattr(
        "app.services.pipeline.get_providers",
        lambda settings: Providers(
            MockSegmentationProvider(),
            gate,
            MockPhotoProvider(),
        ),
    )

    video_path = tmp_path / "test.mp4"
    video_bytes = make_video(video_path)

    app = create_app(settings)

    # Entering this context starts the job worker.
    with TestClient(app) as client:

        # A. Create a pallet.
        pallet_response = client.post(
            "/pallets",
            json={
                "name": "Progressive Test",
                "purchase_cost": 20,
                "additional_costs": 5,
            },
        )
        assert pallet_response.status_code in (200, 201)

        pallet_id = pallet_response.json()["id"]

        # B. Upload a video and start processing.
        job_response = client.post(
            "/jobs",
            data={"pallet_id": pallet_id},
            files={
                "video": (
                    "test.mp4",
                    io.BytesIO(video_bytes),
                    "video/mp4",
                )
            },
        )
        assert job_response.status_code == 202

        job_id = job_response.json()["id"]

        try:
            # C. Wait until the worker reaches Item 2.
            assert gate.reached_item_2.wait(timeout=15), (
                "Worker never reached Item 2"
            )

            # D. Item 2 is paused.
            # Item 1 should already be saved.
            store = app.state.job_store

            saved_items = store.db.items_for_job(job_id)

            assert len(saved_items) == 1

            # E. Verify the REST API sees the same item.
            items_response = client.get(
                f"/pallets/{pallet_id}/items"
            )

            assert items_response.status_code == 200

            api_items = items_response.json()

            assert len(api_items) == 1

            # F. The job should not be finished yet.
            job_response = client.get(
                f"/jobs/{job_id}"
            )

            assert job_response.json()["status"] not in (
                "completed",
                "failed",
            )

        finally:
            # G. Always unblock the worker.
            gate.release.set()

        # H. Wait for the job to finish.
        deadline = time.monotonic() + 15

        while time.monotonic() < deadline:
            job_response = client.get(
                f"/jobs/{job_id}"
            )
            status = job_response.json()["status"]

            if status in ("completed", "failed"):
                break

            time.sleep(0.05)
        else:
            raise AssertionError(
                "Job did not finish before timeout"
            )

        assert status == "completed", job_response.json()

        # I. All three products should now be saved.
        final_items = client.get(
            f"/pallets/{pallet_id}/items"
        ).json()

        assert len(final_items) == 3

        # J. CSV should include the same three items.
        csv_response = client.get(
            f"/pallets/{pallet_id}/export"
        )

        assert csv_response.status_code == 200

        import csv

        rows = list(
            csv.DictReader(
                io.StringIO(csv_response.text)
            )
        )

        assert len(rows) == 3

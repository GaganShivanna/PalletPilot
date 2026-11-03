from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from tests.test_phase2 import make_video, wait_for_job


def test_manifest_upload_and_reconciliation(tmp_path):
    settings = Settings(
        _env_file=None,
        data_dir=tmp_path / "data",
        ai_provider="mock",
        muse_api_key=None,
    )

    manifest = (
        b"id,name,brand,quantity\n"
        b"drill,Cordless drill,Acme,1\n"
        b"mug,Ceramic mug,,1\n"
    )

    with TestClient(create_app(settings)) as client:
        pallet = client.post(
            "/pallets",
            json={
                "name": "Manifest test",
                "purchase_cost": 20,
                "additional_costs": 0,
            },
        ).json()

        video = make_video(tmp_path / "video.mp4")

        with video.open("rb") as stream:
            response = client.post(
                "/jobs",
                data={"pallet_id": pallet["id"]},
                files={
                    "video": (
                        "video.mp4",
                        stream,
                        "video/mp4",
                    ),
                    "manifest": (
                        "manifest.csv",
                        manifest,
                        "text/csv",
                    ),
                },
            )

        assert response.status_code == 202
        job_id = response.json()["id"]

        job = wait_for_job(client, job_id)
        assert job["status"] == "completed", job.get("error")

        response = client.get(
            f"/jobs/{job_id}/files/manifest_report.json"
        )
        assert response.status_code == 200

        report = response.json()
        assert report["processing_complete"] is True

        rows = {
            row["id"]: row
            for row in report["manifest_rows"]
        }

        assert rows["drill"]["status"] == "matched"
        assert rows["drill"]["matched_quantity"] == 1
        assert rows["mug"]["status"] == "not_seen"
        assert rows["mug"]["not_seen_quantity"] == 1

        items = client.get(
            f"/pallets/{pallet['id']}/items"
        ).json()

        drill = next(
            item
            for item in items
            if item["title"] == "Acme Cordless Drill"
        )

        assert drill["brand"] == "Acme"
        assert "Manifest check: matched." in drill["review_reasons"]


def test_invalid_manifest_does_not_create_job(tmp_path):
    settings = Settings(
        _env_file=None,
        data_dir=tmp_path / "data",
        ai_provider="mock",
        muse_api_key=None,
    )

    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/jobs",
            files={
                "video": (
                    "video.mp4",
                    b"not decoded because manifest is invalid",
                    "video/mp4",
                ),
                "manifest": (
                    "manifest.csv",
                    b"name,quantity\nMug,-1\n",
                    "text/csv",
                ),
            },
        )

        assert response.status_code == 422
        assert client.get("/jobs").json() == []
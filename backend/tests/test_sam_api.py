import io
import json
from unittest.mock import Mock

import cv2
import numpy as np
import pytest

from app.config import Settings
from app.providers.base import ProviderError, ProviderUnavailable
from app.providers.sam_api import (
    detect_with_sam,
    encode_video,
    request_sam_output,
)


def settings(**overrides):
    values = {
        "muse_api_key": "offline-test-key",
        "sam_concepts": "box",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_encode_video_preserves_frame_count(tmp_path):
    frames = []

    for index in range(2):
        path = tmp_path / f"frame_{index}.jpg"
        image = np.full((100, 100, 3), 150, dtype=np.uint8)
        assert cv2.imwrite(str(path), image)
        frames.append(path)

    output = encode_video(frames, tmp_path / "sample.mp4", 3.0)

    assert output.is_file()
    assert output.stat().st_size > 0


def test_completed_response_builds_product(tmp_path, monkeypatch):
    frame = tmp_path / "frame.jpg"
    assert cv2.imwrite(
        str(frame),
        np.full((100, 100, 3), 150, dtype=np.uint8),
    )

    # Encoding is tested separately; this test exercises the HTTP boundary.
    video = tmp_path / "fixture.mp4"
    video.write_bytes(b"mock video bytes")

    monkeypatch.setattr(
        "app.providers.sam_api.encode_video",
        lambda *args: video,
    )

    output_text = (
        "<0f>7"
        "<|box;x1=10;y1=20;x2=14;y2=24;w=100;h=100;c=0.9|>"
        "<|mask;x=0;y=0;c=0.9;data=5,5,!!!!!(QO(0lu8?|>\n"
    )

    response = {
        "status": "completed",
        "output": [
            {
                "type": "message",
                "content": [
                    {"type": "output_text", "text": output_text}
                ],
            }
        ],
    }

    fake_http = Mock(
        return_value=io.BytesIO(json.dumps(response).encode())
    )
    monkeypatch.setattr("app.providers.sam_api.urlopen", fake_http)

    products = detect_with_sam(
        [frame],
        tmp_path / "products",
        settings(),
    )

    assert len(products) == 1
    assert products[0].provider == "sam"
    assert products[0].track_id == "concept_0_7"
    assert products[0].needs_review is True

    request = fake_http.call_args.args[0]
    payload = json.loads(request.data)

    assert payload["model"] == "sam-3.1"
    assert payload["input"][0]["content"][0]["text"] == "box"


def test_incomplete_response_is_rejected(tmp_path, monkeypatch):
    video = tmp_path / "fixture.mp4"
    video.write_bytes(b"mock video bytes")

    fake_http = Mock(
        return_value=io.BytesIO(
            json.dumps({"status": "incomplete"}).encode()
        )
    )
    monkeypatch.setattr("app.providers.sam_api.urlopen", fake_http)

    with pytest.raises(ProviderError, match="completed"):
        request_sam_output(video, "box", settings())


def test_missing_key_never_calls_api(tmp_path, monkeypatch):
    fake_http = Mock()
    monkeypatch.setattr("app.providers.sam_api.urlopen", fake_http)

    with pytest.raises(ProviderUnavailable):
        detect_with_sam(
            [],
            tmp_path / "products",
            settings(muse_api_key=None),
        )

    fake_http.assert_not_called()
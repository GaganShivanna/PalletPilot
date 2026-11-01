import io
import json
from unittest.mock import Mock

import cv2
import numpy as np
import pytest

from app.config import Settings
from app.providers.base import ProviderError, ProviderUnavailable
from app.providers.concept_discovery import (
    clean_concepts,
    discover_concepts,
    select_frame_indices,
)


def make_frames(tmp_path):
    frames = []

    for index in range(3):
        path = tmp_path / f"frame_{index}.jpg"

        assert cv2.imwrite(
            str(path),
            np.full(
                (64, 64, 3),
                50 + index * 40,
                dtype=np.uint8,
            ),
        )

        frames.append(path)

    return frames


def test_frame_selection_covers_clip():
    indices = select_frame_indices(100)

    assert len(indices) == 8
    assert indices[0] == 0
    assert indices[-1] == 99
    assert indices == sorted(set(indices))


def test_duplicate_concepts_are_normalized():
    assert clean_concepts(
        {"concepts": [" Mug ", "mug", "headphones"]}
    ) == ["Mug", "headphones"]


@pytest.mark.parametrize(
    "data",
    [
        {"concepts": "mug"},
        {"concepts": [""]},
        {"concepts": ["mug, headphones"]},
        {"concepts": [42]},
    ],
)
def test_invalid_concepts_are_rejected(data):
    with pytest.raises(ProviderError):
        clean_concepts(data)


def test_request_and_cache(tmp_path, monkeypatch):
    settings = Settings(
        _env_file=None,
        data_dir=tmp_path / "data",
        muse_api_key="offline-test-key",
    )

    frames = make_frames(tmp_path)

    completion = {
        "choices": [
            {
                "finish_reason": "stop",
                "message": {
                    "content": json.dumps(
                        {"concepts": ["mug", "headphones"]}
                    )
                },
            }
        ],
        "usage": {"prompt_tokens": 100, "completion_tokens": 10},
    }

    fake_http = Mock(
        return_value=io.BytesIO(json.dumps(completion).encode())
    )

    monkeypatch.setattr(
        "app.providers.concept_discovery.urlopen",
        fake_http,
    )

    first = discover_concepts(
        frames,
        tmp_path / "job_one",
        settings,
    )

    second = discover_concepts(
        frames,
        tmp_path / "job_two",
        settings,
    )

    assert first == second == ["mug", "headphones"]

    # The second identical discovery uses the cache.
    fake_http.assert_called_once()

    request = fake_http.call_args.args[0]
    payload = json.loads(request.data)
    images = payload["messages"][0]["content"][1:]

    assert len(images) == 3
    assert all(part["type"] == "image_url" for part in images)

    evidence = json.loads(
        (tmp_path / "job_two" / "concept_discovery.json").read_text()
    )

    assert evidence["cache_hit"] is True


def test_missing_key_never_calls_model(tmp_path, monkeypatch):
    fake_http = Mock()

    monkeypatch.setattr(
        "app.providers.concept_discovery.urlopen",
        fake_http,
    )

    settings = Settings(
        _env_file=None,
        data_dir=tmp_path / "data",
        muse_api_key=None,
    )

    with pytest.raises(ProviderUnavailable):
        discover_concepts([], tmp_path / "job", settings)

    fake_http.assert_not_called()
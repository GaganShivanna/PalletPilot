import io
import json
from unittest.mock import Mock

import pytest

from app.config import Settings
from app.providers.base import DetectedProduct, ProviderUnavailable
from app.providers.real import MUSE_SPARK_CONDITION_MAP, MuseSparkIdentificationProvider
from app.schemas.items import CONDITIONS


def test_identification_with_mocked_http(tmp_path, monkeypatch):
    # Only the HTTP contract is tested; no real image inference occurs.
    image = tmp_path / "product.jpg"
    image.write_bytes(b"image fixture")

    identity = {
        "name": "Ceramic mug",
        "brand": None,
        "category": "Kitchen",
        "condition": "unknown",
        "confidence": 0.7,
        "review_reasons": ["Confirm the visible condition."],
    }

    response = {
        "choices": [
            {
                "finish_reason": "stop",
                "message": {"content": json.dumps(identity)},
            }
        ]
    }

    fake_http = Mock(
        return_value=io.BytesIO(json.dumps(response).encode())
    )
    monkeypatch.setattr("app.providers.real.urlopen", fake_http)

    settings = Settings(
        _env_file=None,
        muse_api_key="offline-test-key",
    )
    provider = MuseSparkIdentificationProvider(settings)

    result = provider.identify(
        DetectedProduct(
            item_id="item_1",
            track_id="track_1",
            frame_path=str(image),
            provider="custom",
        )
    )

    assert result.name == "Ceramic mug"
    assert result.brand is None
    assert result.provider == "muse_spark"
    assert result.needs_review is True

    fake_http.assert_called_once()
    request = fake_http.call_args.args[0]
    payload = json.loads(request.data)

    assert payload["model"] == settings.muse_spark_model
    assert payload["response_format"]["type"] == "json_schema"
    assert payload["messages"][0]["content"][1]["type"] == "image_url"


def test_missing_key_does_not_make_request(monkeypatch):
    fake_http = Mock()
    monkeypatch.setattr("app.providers.real.urlopen", fake_http)

    provider = MuseSparkIdentificationProvider(
        Settings(_env_file=None, muse_api_key=None)
    )

    with pytest.raises(ProviderUnavailable):
        provider.identify(
            DetectedProduct(
                item_id="item_1",
                track_id="track_1",
                frame_path="unused.jpg",
            )
        )

    fake_http.assert_not_called()


def test_condition_map_covers_every_model_condition():
    # Every condition the strict _ProductIdentity schema can emit must have
    # an explicit mapping — no silent fallthrough for known values.
    assert set(MUSE_SPARK_CONDITION_MAP) == {
        "new_sealed",
        "open_box",
        "used",
        "damaged",
        "unknown",
    }
    assert set(MUSE_SPARK_CONDITION_MAP.values()) <= CONDITIONS


@pytest.mark.parametrize(
    ("raw_condition", "expected"),
    [
        ("new_sealed", "new"),
        ("open_box", "unknown"),
        ("used", "unknown"),
        ("damaged", "unknown"),
        ("unknown", "unknown"),
    ],
)
def test_condition_mapping_is_conservative(
    tmp_path, monkeypatch, raw_condition, expected
):
    # Only the HTTP contract is tested; no real image inference occurs.
    image = tmp_path / "product.jpg"
    image.write_bytes(b"image fixture")

    identity = {
        "name": "Ceramic mug",
        "brand": None,
        "category": "Kitchen",
        "condition": raw_condition,
        "confidence": 0.7,
        "review_reasons": ["Confirm the visible condition."],
    }

    response = {
        "choices": [
            {
                "finish_reason": "stop",
                "message": {"content": json.dumps(identity)},
            }
        ]
    }

    fake_http = Mock(
        return_value=io.BytesIO(json.dumps(response).encode())
    )
    monkeypatch.setattr("app.providers.real.urlopen", fake_http)

    provider = MuseSparkIdentificationProvider(
        Settings(_env_file=None, muse_api_key="offline-test-key")
    )

    result = provider.identify(
        DetectedProduct(
            item_id="item_1",
            track_id="track_1",
            frame_path=str(image),
            provider="custom",
        )
    )

    assert result.condition == expected
    assert result.condition in CONDITIONS
    if raw_condition != expected:
        # The raw model observation must survive for seller review.
        assert any(raw_condition in reason for reason in result.review_reasons)
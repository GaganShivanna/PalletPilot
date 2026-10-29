import io
import json
from unittest.mock import Mock

import pytest

from app.config import Settings
from app.providers.base import DetectedProduct, ProviderUnavailable
from app.providers.real import MuseSparkIdentificationProvider


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
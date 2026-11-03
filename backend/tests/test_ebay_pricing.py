"""eBay Browse pricing: medians, fallbacks, and failure isolation."""

import io
import json
from unittest.mock import patch

import app.services.ebay_pricing as ebay_pricing
from app.config import Settings
from app.schemas.items import PriceEstimate
from app.services.ebay_pricing import EbayPricingProvider


def _settings(**overrides):
    values = {"ebay_client_id": "id", "ebay_client_secret": "secret"}
    values.update(overrides)
    return Settings(**values)


def _provider(**overrides):
    provider = EbayPricingProvider.from_settings(_settings(**overrides))
    assert provider is not None
    return provider


class _FakeResponse:
    def __init__(self, payload):
        self._stream = io.StringIO(json.dumps(payload))

    def __enter__(self):
        return self._stream

    def __exit__(self, *args):
        return False


def _search_payload(values):
    return {
        "itemSummaries": [
            {"price": {"value": str(v), "currency": "USD"}} for v in values
        ]
    }


def _mock_urlopen_factory(search_values, token="tok"):
    calls = []

    def fake_urlopen(request, timeout=None):
        url = request.full_url
        calls.append(url)
        if url.endswith("/identity/v1/oauth2/token"):
            return _FakeResponse({"access_token": token, "expires_in": 7200})
        return _FakeResponse(_search_payload(search_values))

    fake_urlopen.calls = calls
    return fake_urlopen


def teardown_function():
    ebay_pricing._token_cache.clear()
    ebay_pricing._estimate_cache.clear()


def test_no_credentials_yields_no_provider():
    assert EbayPricingProvider.from_settings(_settings(ebay_client_id="")) is None
    assert (
        EbayPricingProvider.from_settings(_settings(ebay_client_secret="")) is None
    )


def test_median_of_active_listings():
    fake = _mock_urlopen_factory([10.0, 30.0, 20.0])
    with patch.object(ebay_pricing, "urlopen", side_effect=fake):
        estimate = _provider().estimate("Mesh Wastebasket", "Trash Cans")
    assert estimate is not None
    assert estimate.amount == 20.0
    assert estimate.currency == "USD"
    assert estimate.source == "ebay_active"
    assert estimate.price_type == "asking"
    assert estimate.confidence == 0.3  # 0.15 + 0.05 * 3


def test_single_result_is_unusable():
    fake = _mock_urlopen_factory([99.0])
    with patch.object(ebay_pricing, "urlopen", side_effect=fake):
        # Name query yields 1 hit, category query also yields 1 hit.
        assert _provider().estimate("Rare Thing", "Rugs") is None


def test_falls_back_to_category_query():
    seen = []

    def fake_urlopen(request, timeout=None):
        url = request.full_url
        if url.endswith("/identity/v1/oauth2/token"):
            return _FakeResponse({"access_token": "tok", "expires_in": 7200})
        seen.append(url)
        if "q=Rugs" in url:
            return _FakeResponse(_search_payload([18.0, 22.0]))
        return _FakeResponse(_search_payload([999.0]))

    with patch.object(ebay_pricing, "urlopen", side_effect=fake_urlopen):
        estimate = _provider().estimate("Unidentifiable blob", "Rugs")
    assert estimate is not None
    assert estimate.amount == 20.0


def test_vague_category_is_never_queried():
    fake = _mock_urlopen_factory([999.0])
    with patch.object(ebay_pricing, "urlopen", side_effect=fake):
        assert _provider().estimate("blur", "Unknown") is None
    assert not [c for c in fake.calls if "item_summary" in c and "q=Unknown" in c]


def test_oauth_failure_returns_none():
    def fake_urlopen(request, timeout=None):
        raise OSError("no network")

    with patch.object(ebay_pricing, "urlopen", side_effect=fake_urlopen):
        assert _provider().estimate("Drill", "Power Tools") is None


def test_repeat_query_uses_cache():
    fake = _mock_urlopen_factory([10.0, 20.0])
    with patch.object(ebay_pricing, "urlopen", side_effect=fake):
        provider = _provider()
        first = provider.estimate("Drill", "Power Tools")
        second = provider.estimate("Drill", "Power Tools")
    assert first is not None and second is not None
    searches = [c for c in fake.calls if "item_summary" in c]
    assert len(searches) == 1


def test_result_is_a_price_estimate_model():
    fake = _mock_urlopen_factory([5.0, 7.0])
    with patch.object(ebay_pricing, "urlopen", side_effect=fake):
        estimate = _provider().estimate("Book", "Books")
    assert isinstance(estimate, PriceEstimate)

"""Muse price guesses: parsing, guards, tier order, failure isolation."""

import io
import json
from unittest.mock import patch

import app.services.muse_pricing as muse_pricing
from app.config import Settings
from app.services.muse_pricing import MusePriceProvider
from app.services.pricing import get_price


def _settings(**overrides):
    values = {
        "muse_api_key": "key",
        "muse_pricing_enabled": True,
    }
    values.update(overrides)
    return Settings(**values)


def _provider(**overrides):
    provider = MusePriceProvider.from_settings(_settings(**overrides))
    assert provider is not None
    return provider


def _completion(content):
    return {"choices": [{"message": {"content": json.dumps(content)}}]}


class _FakeResponse:
    def __init__(self, payload):
        self._stream = io.StringIO(json.dumps(payload))

    def __enter__(self):
        return self._stream

    def __exit__(self, *args):
        return False


def teardown_function():
    muse_pricing._guess_cache.clear()


def test_disabled_by_default():
    assert MusePriceProvider.from_settings(_settings(muse_pricing_enabled=False)) is None
    assert MusePriceProvider.from_settings(_settings(muse_api_key="")) is None


def test_valid_guess():
    payload = _completion({"amount": 24.5, "confidence": 0.6})
    with patch.object(muse_pricing, "urlopen", return_value=_FakeResponse(payload)):
        estimate = _provider().estimate("Mesh Wastebasket", "Trash Cans")
    assert estimate is not None
    assert estimate.amount == 24.5
    assert estimate.source == "muse_estimate"
    assert estimate.price_type == "estimate"
    assert estimate.confidence == 0.6


def test_null_amount_falls_through():
    payload = _completion({"amount": None, "confidence": 0.9})
    with patch.object(muse_pricing, "urlopen", return_value=_FakeResponse(payload)):
        assert _provider().estimate("???", "Unknown") is None


def test_low_confidence_falls_through():
    payload = _completion({"amount": 50.0, "confidence": 0.1})
    with patch.object(muse_pricing, "urlopen", return_value=_FakeResponse(payload)):
        assert _provider().estimate("Vague thing", "Other") is None


def test_implausible_amount_rejected():
    payload = _completion({"amount": 999999.0, "confidence": 0.9})
    with patch.object(muse_pricing, "urlopen", return_value=_FakeResponse(payload)):
        assert _provider().estimate("Box", "Other") is None


def test_network_failure_returns_none():
    with patch.object(muse_pricing, "urlopen", side_effect=OSError("down")):
        assert _provider().estimate("Drill", "Power Tools") is None


def test_malformed_response_returns_none():
    with patch.object(muse_pricing, "urlopen", return_value=_FakeResponse({"nope": 1})):
        assert _provider().estimate("Drill", "Power Tools") is None


def test_empty_name_never_calls_model():
    with patch.object(muse_pricing, "urlopen", side_effect=AssertionError("called")):
        assert _provider().estimate("  ", "Rugs") is None


def test_tier_order_muse_between_ebay_and_category():
    from app.schemas.items import PriceEstimate

    class Stub:
        def __init__(self, estimate):
            self.value = estimate

        def estimate(self, name, category):
            return self.value

    muse = Stub(
        PriceEstimate(
            amount=33.0,
            currency="USD",
            source="muse_estimate",
            confidence=0.5,
            price_type="estimate",
        )
    )
    # Muse beats the category table...
    estimate = get_price("Mesh Wastebasket", "Trash Cans & Wastebaskets", muse=muse)
    assert (estimate.amount, estimate.source) == (33.0, "muse_estimate")
    # ...but eBay beats Muse.
    ebay = Stub(
        PriceEstimate(
            amount=27.5,
            currency="USD",
            source="ebay_active",
            confidence=0.4,
            price_type="asking",
        )
    )
    estimate = get_price("Mesh Wastebasket", "Trash Cans", ebay=ebay, muse=muse)
    assert (estimate.amount, estimate.source) == (27.5, "ebay_active")
    # Muse returning None falls to the category table.
    estimate = get_price("Some rug", "Rugs", muse=Stub(None))
    assert (estimate.amount, estimate.source) == (20.0, "category_estimate")

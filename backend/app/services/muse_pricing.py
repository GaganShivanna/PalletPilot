"""Muse Spark resale-price guesses (model knowledge, no market data).

Asks the already-configured Muse model for a typical US used-resale
value given the product name and category. Text-only and strict-schema;
labeled ``source="muse_estimate"`` so it is never mistaken for market
data. Guesses sit below eBay (real listings win) and above the static
category table.

Needs only ``MUSE_API_KEY`` (no new credentials). Guesses outside a
plausible used-goods range, low-confidence answers, and any API failure
return None so pricing falls through to the category table.
"""

import json
import logging
import time
from dataclasses import dataclass
from urllib.request import Request, urlopen

from pydantic import BaseModel, ConfigDict, Field

from app.config import Settings, get_settings
from app.schemas.items import PriceEstimate

log = logging.getLogger(__name__)

# Used pallet goods above this are treated as model error, not signal.
MAX_PLAUSIBLE_USD = 25_000.0
MIN_CONFIDENCE = 0.15

_guess_cache: dict[tuple[str, str], tuple[float, PriceEstimate | None]] = {}
_GUESS_TTL_S = 3600.0
_GUESS_CACHE_MAX = 500


class _PriceGuess(BaseModel):
    """Validate the model's price guess before trusting it."""

    model_config = ConfigDict(extra="forbid", strict=True)

    amount: float | None = Field(default=None, gt=0)
    confidence: float = Field(ge=0, le=1)


@dataclass(frozen=True)
class MusePriceProvider:
    """Model-knowledge resale guesses. Construct via ``from_settings``."""

    base_url: str
    model: str
    api_key: str
    timeout_s: float = 60.0

    @classmethod
    def from_settings(cls, settings: Settings) -> "MusePriceProvider | None":
        if not settings.muse_pricing_enabled:
            return None
        secret = settings.muse_api_key
        api_key = secret.get_secret_value().strip() if secret else ""
        if not api_key:
            return None
        return cls(
            base_url=settings.muse_base_url.rstrip("/"),
            model=settings.muse_spark_model,
            api_key=api_key,
            timeout_s=settings.provider_timeout_s,
        )

    def estimate(self, product_name: str, category: str | None) -> PriceEstimate | None:
        name = (product_name or "").strip()
        if not name:
            return None
        key = (name, (category or "").strip().lower())
        now = time.time()
        hit = _guess_cache.get(key)
        if hit is not None and now < hit[0]:
            return hit[1]
        try:
            estimate = self._guess(name, category)
        except Exception as exc:  # noqa: BLE001 - fall through to category tier
            log.warning("Muse price guess failed for %r: %s", name, exc)
            estimate = None
        if len(_guess_cache) >= _GUESS_CACHE_MAX:
            _guess_cache.clear()
        _guess_cache[key] = (now + _GUESS_TTL_S, estimate)
        return estimate

    def _guess(self, name: str, category: str | None) -> PriceEstimate | None:
        prompt = (
            "Estimate the typical US used-resale value in USD (like an "
            "eBay sold price) for one unit of this product. Be "
            "conservative: prefer a low typical value over a high one. "
            "Visual condition is unknown — assume average used condition "
            "unless the name says otherwise. "
            "Return amount null when you cannot form even a rough guess. "
            "Confidence is your certainty in the amount, 0 to 1.\n"
            f"Product: {name}\n"
            f"Category: {category or 'unknown'}"
        )
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "price_guess",
                    "schema": _PriceGuess.model_json_schema(),
                },
            },
        }
        request = Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urlopen(request, timeout=self.timeout_s) as response:
            completion = json.load(response)
        content = completion["choices"][0]["message"]["content"]
        guess = _PriceGuess.model_validate_json(content)
        if guess.amount is None or guess.confidence < MIN_CONFIDENCE:
            return None
        if not 0 < guess.amount <= MAX_PLAUSIBLE_USD:
            log.warning("Implausible Muse price rejected: %s", guess.amount)
            return None
        return PriceEstimate(
            amount=round(guess.amount, 2),
            currency="USD",
            source="muse_estimate",
            confidence=round(guess.confidence, 2),
            price_type="estimate",
        )


def get_muse_provider() -> MusePriceProvider | None:
    """Provider from active settings, or None when the key is absent."""
    return MusePriceProvider.from_settings(get_settings())

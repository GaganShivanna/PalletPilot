"""eBay Browse API pricing (active-listing asking prices).

Uses the public Browse API (``item_summary/search``) with an OAuth2
application token (client-credentials grant, no user login). This sees
ACTIVE listings only, so estimates are asking-price medians labeled
``source="ebay_active"`` / ``price_type="asking"`` — never presented
as sold prices.

True sold history lives in eBay's Marketplace Insights API, which is a
Limited Release closed to new applicants. If a grant is ever approved,
add a sold-history lookup here and prefer it over the active median.

Needs ``EBAY_CLIENT_ID`` + ``EBAY_CLIENT_SECRET`` in ``backend/.env``.
Without credentials (or on any API failure) this module returns None
and pricing falls through to the category table — eBay problems must
never break the pipeline.
"""

import base64
import json
import logging
import statistics
import time
import urllib.parse
from collections import Counter
from dataclasses import dataclass
from urllib.request import Request, urlopen

from app.config import Settings, get_settings
from app.schemas.items import PriceEstimate

log = logging.getLogger(__name__)

_OAUTH_SCOPE = "https://api.ebay.com/oauth/api_scope"

# In-memory OAuth token cache: {"access_token": str, "expires_at": float}.
_token_cache: dict[str, object] = {}

# Estimate cache: {query: (expires_at, PriceEstimate | None)}. eBay rate
# limits daily calls, so repeat names within an hour reuse one lookup.
_estimate_cache: dict[str, tuple[float, PriceEstimate | None]] = {}
_ESTIMATE_TTL_S = 3600.0
_ESTIMATE_CACHE_MAX = 500


@dataclass(frozen=True)
class EbayPricingProvider:
    """Active-listing median estimates. Construct via ``from_settings``."""

    base_url: str
    marketplace_id: str
    client_id: str
    client_secret: str
    timeout_s: float = 15.0
    max_results: int = 20

    @classmethod
    def from_settings(cls, settings: Settings) -> "EbayPricingProvider | None":
        """Return a provider when credentials exist, else None (skip eBay)."""
        secret = settings.ebay_client_secret
        client_id = (settings.ebay_client_id or "").strip()
        client_secret = secret.get_secret_value().strip() if secret else ""
        if not client_id or not client_secret:
            return None
        return cls(
            base_url=settings.ebay_base_url.rstrip("/"),
            marketplace_id=settings.ebay_marketplace,
            client_id=client_id,
            client_secret=client_secret,
        )

    def estimate(self, product_name: str, category: str | None) -> PriceEstimate | None:
        """Median asking price for a product, or None when unusable."""
        query = (product_name or "").strip()
        if query:
            estimate = self._cached_estimate(query)
            if estimate is not None:
                return estimate
        if category and category.strip().lower() not in {"unknown", "uncategorized", "other", ""}:
            return self._cached_estimate(category.strip())
        return None

    def _cached_estimate(self, query: str) -> PriceEstimate | None:
        now = time.time()
        hit = _estimate_cache.get(query)
        if hit is not None and now < hit[0]:
            return hit[1]
        estimate = self._estimate_for_query(query)
        if len(_estimate_cache) >= _ESTIMATE_CACHE_MAX:
            _estimate_cache.clear()
        _estimate_cache[query] = (now + _ESTIMATE_TTL_S, estimate)
        return estimate

    def _estimate_for_query(self, query: str) -> PriceEstimate | None:
        try:
            token = self._access_token()
        except Exception as exc:  # noqa: BLE001 - eBay must never break pricing
            log.warning("eBay OAuth failed: %s", exc)
            return None
        try:
            prices = self._active_prices(query, token)
        except Exception as exc:  # noqa: BLE001 - fall through to category tier
            log.warning("eBay search failed for %r: %s", query, exc)
            return None
        if len(prices) < 2:
            return None
        values = sorted(p[0] for p in prices)
        currency = Counter(p[1] for p in prices).most_common(1)[0][0]
        amount = round(
            statistics.median(v for v, c in prices if c == currency), 2
        )
        # Confidence grows with sample size; active listings cap at 0.5
        # because asking prices overstate realized resale.
        confidence = round(min(0.15 + 0.05 * len(values), 0.5), 2)
        return PriceEstimate(
            amount=amount,
            currency=currency,
            source="ebay_active",
            confidence=confidence,
            price_type="asking",
        )

    def _access_token(self) -> str:
        now = time.time()
        cached_token = _token_cache.get("access_token")
        expires_at = _token_cache.get("expires_at", 0.0)
        if cached_token and now < float(expires_at) - 60:
            return str(cached_token)
        credentials = base64.b64encode(
            f"{self.client_id}:{self.client_secret}".encode("utf-8")
        ).decode("ascii")
        request = Request(
            f"{self.base_url}/identity/v1/oauth2/token",
            data=urllib.parse.urlencode(
                {"grant_type": "client_credentials", "scope": _OAUTH_SCOPE}
            ).encode("utf-8"),
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            method="POST",
        )
        with urlopen(request, timeout=self.timeout_s) as response:
            body = json.load(response)
        token = body["access_token"]
        _token_cache["access_token"] = token
        _token_cache["expires_at"] = now + float(body.get("expires_in", 7200))
        return str(token)

    def _active_prices(self, query: str, token: str) -> list[tuple[float, str]]:
        params = urllib.parse.urlencode(
            {"q": query, "limit": self.max_results, "sort": "price"}
        )
        request = Request(
            f"{self.base_url}/buy/browse/v1/item_summary/search?{params}",
            headers={
                "Authorization": f"Bearer {token}",
                "X-EBAY-C-MARKETPLACE-ID": self.marketplace_id,
            },
            method="GET",
        )
        with urlopen(request, timeout=self.timeout_s) as response:
            body = json.load(response)
        prices: list[tuple[float, str]] = []
        for summary in body.get("itemSummaries", []) or []:
            price = summary.get("price") or {}
            try:
                prices.append((float(price["value"]), str(price["currency"])))
            except (KeyError, TypeError, ValueError):
                continue
        return prices


def get_ebay_provider() -> EbayPricingProvider | None:
    """Provider from active settings, or None when eBay is unconfigured."""
    return EbayPricingProvider.from_settings(get_settings())

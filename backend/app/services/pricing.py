"""Tiered resale pricing.

No marketplace APIs or scraping yet. Estimates resolve in tiers:

1. ``MOCK_FIXTURES`` — exact product-name matches for the deterministic
   demo catalog (``source="mock_fixture"``). Kept so mock end-to-end
   tests stay stable.
2. eBay Browse median (``app.services.ebay_pricing``) — median of live
   active-listing asking prices (``source="ebay_active"``). Only when
   ``EBAY_CLIENT_ID``/``EBAY_CLIENT_SECRET`` are configured; any failure
   falls through silently.
3. Muse guess (``app.services.muse_pricing``) — model-knowledge resale
   guess (``source="muse_estimate"``). Only when ``MUSE_PRICING_ENABLED``
   is true (and ``MUSE_API_KEY`` set); null/low-confidence/implausible
   answers and any failure fall through silently.
4. ``CATEGORY_ESTIMATES`` — conservative used-resale placeholders keyed
   by normalized (lowercased, stripped) category
   (``source="category_estimate"``, low confidence).
5. Unknown — ``amount=None`` (never 0.0, never fabricated) for
   ``Unknown``/``Uncategorized``/empty categories and anything unmatched.
"""

from app.schemas.items import PriceEstimate
from app.services.ebay_pricing import EbayPricingProvider, get_ebay_provider
from app.services.muse_pricing import MusePriceProvider, get_muse_provider

# Reference prices for mock-catalog products only. Not market data.
MOCK_FIXTURES: dict[str, PriceEstimate] = {
    "Acme Cordless Drill": PriceEstimate(
        amount=45.00,
        currency="USD",
        source="mock_fixture",
        confidence=0.4,
        price_type="asking",
    ),
    "BrewCo Espresso Maker": PriceEstimate(
        amount=32.50,
        currency="USD",
        source="mock_fixture",
        confidence=0.4,
        price_type="asking",
    ),
}

# Conservative used-resale placeholders by category. Keys are normalized
# (lowercased). Deliberately excludes vague buckets ("unknown",
# "uncategorized", "other", ""): items with no meaningful category stay
# null rather than getting a misleading number.
_CATEGORY_AMOUNTS: dict[str, float] = {
    "rugs": 20.0,
    "bedding": 12.0,
    "home textiles": 10.0,
    "clothing": 8.0,
    "office supplies": 10.0,
    "sports equipment": 15.0,
    "trash cans & wastebaskets": 8.0,
    "trash can": 8.0,
    "home goods": 10.0,
    "home & office": 10.0,
    "apparel": 8.0,
    "power tools": 30.0,
    "kitchen appliances": 25.0,
    "electronics": 20.0,
    "toys": 8.0,
    "shoes": 12.0,
    "books": 5.0,
}

CATEGORY_ESTIMATES: dict[str, PriceEstimate] = {
    category: PriceEstimate(
        amount=amount,
        currency="USD",
        source="category_estimate",
        confidence=0.2,
        price_type="estimate",
    )
    for category, amount in _CATEGORY_AMOUNTS.items()
}

UNKNOWN_PRICE = PriceEstimate(
    amount=None, currency="USD", source="none", confidence=None, price_type="unknown"
)


def get_price(
    product_name: str,
    category: str | None = None,
    *,
    ebay: EbayPricingProvider | None = None,
    muse: MusePriceProvider | None = None,
) -> PriceEstimate:
    """Return the best available estimate for a product.

    Exact-name fixtures win, then the live eBay median, then the Muse
    guess, then the normalized category table, otherwise unknown
    (null). ``None`` providers (the pipeline default) resolve from
    settings and yield None when their credentials are absent — no
    network, no behavior change.
    """
    estimate = MOCK_FIXTURES.get(product_name)
    if estimate is not None:
        return estimate.model_copy(deep=True)
    ebay_provider = ebay if ebay is not None else _default_ebay_provider()
    if ebay_provider is not None:
        estimate = ebay_provider.estimate(product_name, category)
        if estimate is not None:
            return estimate
    muse_provider = muse if muse is not None else _default_muse_provider()
    if muse_provider is not None:
        estimate = muse_provider.estimate(product_name, category)
        if estimate is not None:
            return estimate
    if category:
        estimate = CATEGORY_ESTIMATES.get(category.strip().lower())
        if estimate is not None:
            return estimate.model_copy(deep=True)
    return UNKNOWN_PRICE.model_copy(deep=True)


def _default_ebay_provider() -> EbayPricingProvider | None:
    try:
        return get_ebay_provider()
    except Exception:  # noqa: BLE001 - eBay must never break pricing
        return None


def _default_muse_provider() -> MusePriceProvider | None:
    try:
        return get_muse_provider()
    except Exception:  # noqa: BLE001 - Muse must never break pricing
        return None

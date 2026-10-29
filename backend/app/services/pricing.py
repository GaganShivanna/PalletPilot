"""Fixture-based pricing for the hackathon demo.

No marketplace APIs or scraping: every estimate comes from the documented
``MOCK_FIXTURES`` table below and is labeled ``source="mock_fixture"``.
Products without a fixture row return ``amount=None`` (never 0.0, never a
fabricated market price).
"""

from app.schemas.items import PriceEstimate

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

UNKNOWN_PRICE = PriceEstimate(
    amount=None, currency="USD", source="none", confidence=None, price_type="unknown"
)


def get_price(product_name: str) -> PriceEstimate:
    """Return the fixture estimate for a product, or an unknown (null) price."""
    estimate = MOCK_FIXTURES.get(product_name)
    return estimate.model_copy(deep=True) if estimate else UNKNOWN_PRICE.model_copy(deep=True)

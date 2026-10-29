"""Deterministic listing drafts from identification + fixture pricing.

No LLM calls: descriptions are templates over verified-or-mocked attributes.
Unverified electronics are never described as tested or working, and mock
drafts carry an explicit demo marker so they cannot be mistaken for
reviewed listings.
"""

from app.providers.base import DetectedProduct, Identification
from app.schemas.items import Item, PriceEstimate
from app.schemas.listings import Listing, Price

ELECTRONIC_CATEGORIES = {"Power Tools", "Kitchen Appliances", "Electronics"}

DEMO_MARKER = "Demo draft: attributes are mocked fixture data — verify before posting."


def draft_description(identification: Identification) -> str:
    brand = identification.brand or "unknown brand"
    parts = [
        f"{identification.name} ({identification.category}).",
        f"Brand: {brand}.",
        f"Observed condition: {identification.condition}.",
    ]
    if identification.category in ELECTRONIC_CATEGORIES:
        parts.append("Functionality untested; sold as pictured.")
    if identification.provider == "mock":
        parts.append(DEMO_MARKER)
    return " ".join(parts)


def draft_item(
    product: DetectedProduct,
    identification: Identification,
    price: PriceEstimate,
    *,
    item_id: str,
    job_id: str,
    pallet_id: str | None,
    image_urls: list[str],
    original_image_url: str | None,
) -> Item:
    return Item(
        id=item_id,
        pallet_id=pallet_id,
        job_id=job_id,
        track_id=product.track_id,
        title=identification.name,
        description=draft_description(identification),
        category=identification.category,
        brand=identification.brand,
        condition=identification.condition,
        suggested_price=price.amount,
        currency=price.currency,
        price_source=price.source,
        price_confidence=price.confidence,
        price_type=price.price_type,
        original_image_url=original_image_url,
        image_urls=list(image_urls),
        confidence=identification.confidence,
        needs_review=True,
        review_reasons=list(identification.review_reasons),
        provider=identification.provider,
    )


def item_to_listing(item: Item) -> Listing:
    return Listing(
        item_id=item.id,
        title=item.title,
        description=item.description,
        category=item.category,
        brand=item.brand,
        condition=item.condition,
        price=Price(amount=item.suggested_price, currency=item.currency),
        image_urls=list(item.image_urls),
        confidence=item.confidence,
        needs_review=item.needs_review,
        review_reasons=list(item.review_reasons),
    )

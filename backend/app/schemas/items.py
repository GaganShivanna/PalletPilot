from datetime import datetime

from pydantic import BaseModel, field_validator

CONDITIONS = {"new", "like_new", "good", "fair", "poor", "parts", "unknown"}


class PriceEstimate(BaseModel):
    amount: float | None = None
    currency: str = "USD"
    source: str = "none"
    confidence: float | None = None
    price_type: str = "unknown"


class Item(BaseModel):
    id: str
    pallet_id: str | None = None
    job_id: str | None = None
    track_id: str | None = None

    title: str
    description: str = ""
    category: str = "Uncategorized"
    brand: str | None = None
    condition: str = "unknown"

    suggested_price: float | None = None
    currency: str = "USD"
    price_source: str = "none"
    price_confidence: float | None = None
    price_type: str = "unknown"

    original_image_url: str | None = None
    image_urls: list[str] = []

    confidence: float | None = None
    needs_review: bool = True
    review_reasons: list[str] = []

    provider: str = "mock"
    created_at: datetime | None = None
    updated_at: datetime | None = None


class ItemPatch(BaseModel):
    title: str | None = None
    description: str | None = None
    category: str | None = None
    brand: str | None = None
    condition: str | None = None
    suggested_price: float | None = None
    needs_review: bool | None = None

    @field_validator("suggested_price")
    @classmethod
    def _non_negative_price(cls, v: float | None) -> float | None:
        if v is not None and v < 0:
            raise ValueError("suggested_price must be non-negative")
        return v

    @field_validator("condition")
    @classmethod
    def _known_condition(cls, v: str | None) -> str | None:
        if v is not None and v not in CONDITIONS:
            raise ValueError(f"condition must be one of: {sorted(CONDITIONS)}")
        return v

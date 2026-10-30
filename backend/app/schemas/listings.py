from pydantic import BaseModel


class Price(BaseModel):
    amount: float | None = None
    currency: str = "USD"


class Listing(BaseModel):
    item_id: str
    title: str
    description: str
    category: str
    brand: str | None = None
    condition: str = "unknown"
    price: Price = Price()
    # URLs served by GET /jobs/{job_id}/files/{path}
    image_urls: list[str] = []
    confidence: float | None = None
    needs_review: bool = True
    review_reasons: list[str] = []

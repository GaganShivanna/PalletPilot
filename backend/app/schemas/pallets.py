from datetime import datetime

from pydantic import BaseModel, Field


class PalletCreate(BaseModel):
    name: str = "Untitled pallet"
    purchase_cost: float = Field(default=0.0, ge=0.0)
    additional_costs: float = Field(default=0.0, ge=0.0)
    job_id: str | None = None


class Pallet(BaseModel):
    id: str
    name: str
    purchase_cost: float = 0.0
    additional_costs: float = 0.0
    job_id: str | None = None
    # Derived, not stored: empty | processing | ready | failed.
    status: str = "empty"
    item_count: int = 0
    priced_item_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class PalletSummary(BaseModel):
    pallet: Pallet
    # Estimates, not realized figures. Unknown item prices are excluded
    # from revenue (never counted as $0 of value silently).
    estimated_revenue: float | None = None
    estimated_fees: float | None = None
    projected_profit: float | None = None
    fee_rate: float
    unpriced_item_count: int = 0
    estimates: bool = True

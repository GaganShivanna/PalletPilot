"""Pallet financial summaries — projected estimates, never realized profit.

Unknown item prices are excluded from revenue (counted as unpriced), never
treated as $0 of resale value.
"""

from app.schemas.items import Item
from app.schemas.pallets import Pallet, PalletSummary


def summarize(pallet: Pallet, items: list[Item], fee_rate: float) -> PalletSummary:
    priced = [i.suggested_price for i in items if i.suggested_price is not None]
    revenue = round(sum(priced), 2)
    fees = round(revenue * fee_rate, 2)
    profit = round(revenue - fees - pallet.purchase_cost - pallet.additional_costs, 2)
    pallet.item_count = len(items)
    pallet.priced_item_count = len(priced)
    return PalletSummary(
        pallet=pallet,
        estimated_revenue=revenue,
        estimated_fees=fees,
        projected_profit=profit,
        fee_rate=fee_rate,
        unpriced_item_count=len(items) - len(priced),
        estimates=True,
    )

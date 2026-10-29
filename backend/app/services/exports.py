"""CSV export for pallet listings.

- UTF-8, stable item order (by id), standard quoting/escaping.
- Spreadsheet formula injection guard: values starting with ``= + - @``
  (or tab/CR) are prefixed with a single quote.
- Missing prices export as empty cells, never 0.
- Mock drafts are identifiable: ``review_status`` is ``needs_review`` and
  mock descriptions carry the demo marker from the listings service.
"""

import csv
import io

from app.schemas.items import Item

COLUMNS = [
    "item_id",
    "title",
    "description",
    "category",
    "brand",
    "condition",
    "suggested_price",
    "currency",
    "image_url",
    "review_status",
]

_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


def _safe(value: object) -> str:
    text = "" if value is None else str(value)
    if text.startswith(_FORMULA_PREFIXES):
        return "'" + text
    return text


def build_csv(items: list[Item]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(COLUMNS)
    for item in sorted(items, key=lambda i: i.id):
        writer.writerow(
            [
                _safe(item.id),
                _safe(item.title),
                _safe(item.description),
                _safe(item.category),
                _safe(item.brand),
                _safe(item.condition),
                "" if item.suggested_price is None else item.suggested_price,
                _safe(item.currency),
                _safe(item.image_urls[0] if item.image_urls else ""),
                "needs_review" if item.needs_review else "approved",
            ]
        )
    return buffer.getvalue()

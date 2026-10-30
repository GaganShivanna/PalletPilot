from fastapi import APIRouter, HTTPException, Request, status

from app.schemas.items import Item, ItemPatch
from app.services.jobs import JobStore

router = APIRouter(prefix="/items", tags=["items"])


def _store(request: Request) -> JobStore:
    return request.app.state.job_store


def _item_or_404(store: JobStore, item_id: str) -> Item:
    row = store.db.get_item(item_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found")
    return Item(**row)


@router.get("/{item_id}", response_model=Item)
def get_item(request: Request, item_id: str) -> Item:
    return _item_or_404(_store(request), item_id)


@router.patch("/{item_id}", response_model=Item)
def patch_item(request: Request, item_id: str, patch: ItemPatch) -> Item:
    """Edit listing fields. Only provided fields change; edits persist to SQLite
    and flow into pallet summaries and CSV export."""
    store = _store(request)
    _item_or_404(store, item_id)
    changes = {k: v for k, v in patch.model_dump().items() if k in patch.model_fields_set}
    if changes:
        store.db.update_item(item_id, **changes)
    return _item_or_404(store, item_id)

import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException, Request, Response, status

from app.schemas.items import Item
from app.schemas.jobs import JobStatus
from app.schemas.pallets import Pallet, PalletCreate, PalletSummary
from app.services.exports import build_csv
from app.services.financials import summarize
from app.services.jobs import JobStore

router = APIRouter(prefix="/pallets", tags=["pallets"])


def _store(request: Request) -> JobStore:
    return request.app.state.job_store


def _pallet_or_404(store: JobStore, pallet_id: str) -> dict:
    row = store.db.get_pallet(pallet_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pallet not found")
    return row


def _status_for(store: JobStore, row: dict) -> str:
    if not row["job_id"]:
        return "empty"
    job = store.get(row["job_id"])
    if job is None:
        return "empty"
    if job.status == JobStatus.completed:
        return "ready"
    if job.status == JobStatus.failed:
        return "failed"
    return "processing"


def _to_pallet(store: JobStore, row: dict) -> Pallet:
    return Pallet(
        id=row["id"],
        name=row["name"],
        purchase_cost=row["purchase_cost"],
        additional_costs=row["additional_costs"],
        job_id=row["job_id"],
        status=_status_for(store, row),
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
    )


def _items(store: JobStore, pallet_id: str) -> list[Item]:
    return [Item(**row) for row in store.db.items_for_pallet(pallet_id)]


@router.post("", status_code=status.HTTP_201_CREATED, response_model=Pallet)
def create_pallet(request: Request, body: PalletCreate) -> Pallet:
    """Create a pallet, optionally linking (and claiming items from) a job."""
    store = _store(request)
    if body.job_id is not None:
        if store.get(body.job_id) is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Job not found")
        existing = store.db.get_pallet_for_job(body.job_id)
        if existing is not None:
            raise HTTPException(status.HTTP_409_CONFLICT, "Job is already linked to a pallet")
    pallet_id = uuid.uuid4().hex
    row = store.db.insert_pallet(
        pallet_id, body.name, body.purchase_cost, body.additional_costs, body.job_id
    )
    if body.job_id is not None:
        store.db.claim_job_items(body.job_id, pallet_id)
    pallet = _to_pallet(store, row)
    items = _items(store, pallet_id)
    pallet.item_count = len(items)
    pallet.priced_item_count = sum(1 for i in items if i.suggested_price is not None)
    return pallet


@router.get("/{pallet_id}", response_model=PalletSummary)
def get_pallet(request: Request, pallet_id: str) -> PalletSummary:
    """Pallet detail with projected financial summary (estimates)."""
    store = _store(request)
    row = _pallet_or_404(store, pallet_id)
    return summarize(_to_pallet(store, row), _items(store, pallet_id), request.app.state.settings.fee_rate)


@router.get("/{pallet_id}/items", response_model=list[Item])
def list_pallet_items(request: Request, pallet_id: str) -> list[Item]:
    store = _store(request)
    _pallet_or_404(store, pallet_id)
    return _items(store, pallet_id)


@router.get("/{pallet_id}/export")
def export_pallet(request: Request, pallet_id: str) -> Response:
    store = _store(request)
    _pallet_or_404(store, pallet_id)
    csv_text = build_csv(_items(store, pallet_id))
    return Response(
        content=csv_text.encode("utf-8"),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="pallet-{pallet_id}.csv"'},
    )

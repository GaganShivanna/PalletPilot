"""End-to-end pipeline: video -> frames -> detection -> identification -> photos -> listings.

Per-item failures (identification errors, photo errors) degrade that item to
a reviewable draft — they never fail the whole pallet. Transient provider
errors are retried per ``settings.provider_max_retries``.
"""

import logging
from pathlib import Path

from app.config import Settings
from app.providers.base import DetectedProduct, Identification, ProviderError
from app.providers.factory import Providers, get_providers
from app.schemas.jobs import JobStatus
from app.services.frames import sample_frames
from app.services.jobs import JobStore
from app.services.listings import draft_item, item_to_listing
from app.services.pricing import get_price
from app.services.product_photos import generate_product_photos

log = logging.getLogger(__name__)


def identify_with_fallback(
    product: DetectedProduct, providers: Providers, max_retries: int
) -> Identification:
    """Identify one product, retrying transient errors.

    On permanent failure or exhausted retries, return an explicit
    unidentified draft (never fabricated attributes, never a pipeline abort).
    """
    attempts = 0
    while True:
        try:
            return providers.identification.identify(product)
        except ProviderError as exc:
            attempts += 1
            if exc.transient and attempts <= max_retries:
                log.warning("Transient identification error for %s (attempt %d)", product.item_id, attempts)
                continue
            log.warning("Identification failed for %s: %s", product.item_id, exc)
            return Identification(
                name=f"Unidentified item ({product.item_id})",
                category="Uncategorized",
                needs_review=True,
                review_reasons=[f"identification failed: {exc}"],
                provider=providers.identification.provider_name
                if providers.identification.provider_name in ("mock", "muse_spark", "custom")
                else "custom",
            )


def run_pipeline(job_id: str, store: JobStore, settings: Settings) -> None:
    job = store.get(job_id)
    if job is None:
        raise KeyError(job_id)
    job_dir = store.job_dir(job_id)
    providers = get_providers(settings)
    pallet = store.db.get_pallet_for_job(job_id)
    pallet_id = pallet["id"] if pallet else None

    store.update(job_id, status=JobStatus.sampling_frames)
    frames = sample_frames(
        job_dir / job.video_filename, job_dir / "frames", settings.sample_fps, settings.max_frames
    )
    store.update(job_id, frame_count=len(frames))

    store.update(job_id, status=JobStatus.segmenting)
    products = providers.segmentation.detect(frames, job_dir / "masks")

    store.update(job_id, status=JobStatus.identifying)
    identified = [
        (p, identify_with_fallback(p, providers, settings.provider_max_retries)) for p in products
    ]

    store.update(job_id, status=JobStatus.generating_photos)
    photos = {
        p.item_id: generate_product_photos(p, job_dir / "photos", providers.photos)
        for p, _ in identified
    }

    store.update(job_id, status=JobStatus.generating_listings)
    listings = []
    for product, identification in identified:
        stored_id = f"{job_id}:{product.item_id}"
        urls = [f"/jobs/{job_id}/files/{p.relative_to(job_dir).as_posix()}" for p in photos[product.item_id]]
        original_url = f"/jobs/{job_id}/files/{Path(product.frame_path).relative_to(job_dir).as_posix()}"
        item = draft_item(
            product,
            identification,
            get_price(identification.name),
            item_id=stored_id,
            job_id=job_id,
            pallet_id=pallet_id,
            image_urls=urls,
            original_image_url=original_url,
        )
        store.db.insert_item(item.model_dump(exclude={"created_at", "updated_at"}))
        listings.append(item_to_listing(item))

    store.update(job_id, status=JobStatus.completed, listings=listings)

"""Progressive video-to-listings pipeline with optional manifest checking."""

import json
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from app.config import Settings
from app.providers.base import (
    DetectedProduct,
    Identification,
    ProviderError,
)
from app.providers.factory import Providers, get_providers
from app.schemas.jobs import JobStatus
from app.services.ebay_pricing import EbayPricingProvider
from app.services.frames import sample_frames
from app.services.jobs import JobStore
from app.services.listings import draft_item, item_to_listing
from app.services.muse_pricing import MusePriceProvider
from app.services.manifest import ManifestMatcher, parse_manifest_csv
from app.services.pricing import get_price
from app.services.product_photos import generate_product_photos

log = logging.getLogger(__name__)


def identify_with_fallback(
    product: DetectedProduct,
    providers: Providers,
    max_retries: int,
) -> Identification:
    attempts = 0

    while True:
        try:
            return providers.identification.identify(product)

        except ProviderError as exc:
            attempts += 1

            if exc.transient and attempts <= max_retries:
                log.warning(
                    "Transient identification error for %s (attempt %d)",
                    product.item_id,
                    attempts,
                )
                continue

            log.warning(
                "Identification failed for %s: %s",
                product.item_id,
                exc,
            )

            provider_name = providers.identification.provider_name

            return Identification(
                name=f"Unidentified item ({product.item_id})",
                category="Uncategorized",
                needs_review=True,
                review_reasons=[f"identification failed: {exc}"],
                provider=(
                    provider_name
                    if provider_name in ("mock", "muse_spark", "custom")
                    else "custom"
                ),
            )


def write_manifest_report(
    job_dir: Path,
    matcher: ManifestMatcher,
    *,
    processing_complete: bool,
) -> None:
    report = matcher.report()
    report["processing_complete"] = processing_complete

    if not processing_complete:
        report["note"] += (
            " Processing is incomplete; remaining quantities are provisional."
        )

    destination = job_dir / "manifest_report.json"
    temporary = job_dir / "manifest_report.json.tmp"

    temporary.write_text(
        json.dumps(report, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    temporary.replace(destination)


@dataclass
class _ItemContext:
    """Shared read-mostly state for per-item workers."""

    job_id: str
    store: JobStore
    settings: Settings
    providers: Providers
    job_dir: Path
    pallet_id: str | None
    matcher: ManifestMatcher | None
    matcher_lock: threading.Lock
    ebay: EbayPricingProvider | None
    muse: MusePriceProvider | None


def _process_product(context: _ItemContext, product: DetectedProduct):
    """Identify, photograph, price, and persist one product.

    Runs on worker threads. Only the matcher (mutable) and event
    emission (MAX+1 ids, locked inside JobStore) need serializing;
    HTTP calls, files, and item rows are all per-product.
    """
    job_id = context.job_id
    store = context.store
    stored_id = f"{job_id}:{product.item_id}"

    identification = identify_with_fallback(
        product,
        context.providers,
        context.settings.provider_max_retries,
    )

    review_reasons = [
        *product.review_reasons,
        *identification.review_reasons,
    ]

    if context.matcher is not None:
        with context.matcher_lock:
            decision = context.matcher.check(
                stored_id,
                identification,
            )
        review_reasons.extend(
            [
                f"Manifest check: {decision['status']}.",
                *decision["reasons"],
            ]
        )

    # Preserve visual identity; add review notes without replacing it
    # with a manifest name, brand or condition.
    identification = identification.model_copy(
        update={
            "needs_review": True,
            "review_reasons": list(
                dict.fromkeys(review_reasons)
            ),
        }
    )

    photo_paths = generate_product_photos(
        product,
        context.job_dir / "photos",
        context.providers.photos,
    )

    urls = [
        f"/jobs/{job_id}/files/{path.relative_to(context.job_dir).as_posix()}"
        for path in photo_paths
    ]

    original_url = (
        f"/jobs/{job_id}/files/"
        f"{Path(product.frame_path).relative_to(context.job_dir).as_posix()}"
    )

    item = draft_item(
        product,
        identification,
        get_price(
            identification.name,
            identification.category,
            ebay=context.ebay,
            muse=context.muse,
            identification_confidence=identification.confidence,
        ),
        item_id=stored_id,
        job_id=job_id,
        pallet_id=context.pallet_id,
        image_urls=urls,
        original_image_url=original_url,
    )

    store.db.insert_item(
        item.model_dump(
            exclude={"created_at", "updated_at"}
        )
    )

    # Only publish report decisions for items already persisted.
    if context.matcher is not None:
        with context.matcher_lock:
            write_manifest_report(
                context.job_dir,
                context.matcher,
                processing_complete=False,
            )

    store.emit_event(
        job_id,
        "listing.ready",
        item_id=stored_id,
        payload={"item_id": stored_id},
    )

    return item_to_listing(item)


def run_pipeline(
    job_id: str,
    store: JobStore,
    settings: Settings,
) -> None:
    job = store.get(job_id)

    if job is None:
        raise KeyError(job_id)

    job_dir = store.job_dir(job_id)

    # A manifest is optional. No model calls are used to reconcile it.
    matcher = None
    manifest_path = job_dir / "manifest.csv"

    if manifest_path.is_file():
        matcher = ManifestMatcher(
            parse_manifest_csv(manifest_path.read_bytes())
        )
        write_manifest_report(
            job_dir,
            matcher,
            processing_complete=False,
        )

    providers = get_providers(settings)
    pallet = store.db.get_pallet_for_job(job_id)
    pallet_id = pallet["id"] if pallet else None

    store.emit_event(
        job_id,
        "job.started",
        payload={"video_filename": job.video_filename},
    )

    store.update(
        job_id,
        status=JobStatus.sampling_frames,
    )

    frames = sample_frames(
        job_dir / job.video_filename,
        job_dir / "frames",
        settings.sample_fps,
        settings.max_frames,
    )

    store.update(job_id, frame_count=len(frames))
    store.update(job_id, status=JobStatus.segmenting)

    products = providers.segmentation.detect(
        frames,
        job_dir / "masks",
    )

    store.emit_event(
        job_id,
        "segmentation.completed",
        payload={"track_count": len(products)},
    )

    # One coarse status for the whole fan-out: per-item status writes
    # would flap meaninglessly across worker threads.
    store.update(job_id, status=JobStatus.identifying)

    # Live pricing providers resolve once from THIS run's settings
    # (never global config): tests with isolated settings get None and
    # stay offline, live runs get whatever .env enables.
    context = _ItemContext(
        job_id=job_id,
        store=store,
        settings=settings,
        providers=providers,
        job_dir=job_dir,
        pallet_id=pallet_id,
        matcher=matcher,
        matcher_lock=threading.Lock(),
        ebay=EbayPricingProvider.from_settings(settings),
        muse=MusePriceProvider.from_settings(settings),
    )

    # Items are independent (own HTTP calls, files, DB rows); the pool
    # size reuses the previously idle provider_max_concurrency setting.
    # map() preserves product order and re-raises worker failures, so a
    # bad item still fails the job exactly as the sequential loop did.
    with ThreadPoolExecutor(
        max_workers=settings.provider_max_concurrency,
        thread_name_prefix=f"pp-{job_id[:8]}",
    ) as pool:
        listings = list(
            pool.map(
                lambda product: _process_product(context, product),
                products,
            )
        )

    if matcher is not None:
        write_manifest_report(
            job_dir,
            matcher,
            processing_complete=True,
        )

    store.update(
        job_id,
        status=JobStatus.completed,
        listings=listings,
    )

    store.emit_event(
        job_id,
        "job.completed",
        payload={"item_count": len(listings)},
    )
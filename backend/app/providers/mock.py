"""Deterministic mock providers for offline development, tests, and demos.

Mock output is explicitly labeled ``provider="mock"`` and always
``needs_review=True``: it exercises the pipeline without ever posing as
real inference.
"""

from pathlib import Path

from app.providers.base import DetectedProduct, Identification, PhotoResult

MOCK_CATALOG = (
    {
        "name": "Acme Cordless Drill",
        "brand": "Acme",
        "category": "Power Tools",
        "condition": "good",
        "confidence": 0.85,
        "review_reasons": ["mock identification: not verified against imagery"],
    },
    {
        "name": "BrewCo Espresso Maker",
        "brand": "BrewCo",
        "category": "Kitchen Appliances",
        "condition": "unknown",
        "confidence": 0.62,
        "review_reasons": ["mock identification: not verified against imagery"],
    },
    {
        "name": "Unidentified sealed box",
        "brand": None,
        "category": "Uncategorized",
        "condition": "unknown",
        "confidence": 0.1,
        "review_reasons": [
            "mock identification: not verified against imagery",
            "sealed box: contents unverifiable",
            "low-confidence identification",
        ],
    },
)


class MockSegmentationProvider:
    """Deterministic stand-in: evenly spaced frames become distinct items.

    Each pick gets its own ``track_id`` — the mock never merges detections,
    mirroring the contract that visually identical products may be separate
    physical items. IDs are derived from frame position, so repeated runs
    over the same frames return identical ``item_id``/``track_id`` values.
    """

    provider_name = "mock"

    def __init__(self, max_items: int = 3):
        self.max_items = max_items

    def detect(self, frame_paths: list[Path], out_dir: Path) -> list[DetectedProduct]:
        out_dir.mkdir(parents=True, exist_ok=True)
        step = max(len(frame_paths) // self.max_items, 1)
        picked = list(enumerate(frame_paths))[::step][: self.max_items]
        return [
            DetectedProduct(
                item_id=f"item_{i}",
                track_id=f"track_{frame_index:05d}",
                frame_path=str(p),
                mask_path=None,
                needs_review=True,
                review_reasons=["mock segmentation: representative frame, no mask"],
                provider="mock",
            )
            for i, (frame_index, p) in enumerate(picked)
        ]


class MockIdentificationProvider:
    """Deterministic structured metadata drawn from a fixed catalog."""

    provider_name = "mock"

    def identify(self, product: DetectedProduct) -> Identification:
        try:
            index = int(product.item_id.rsplit("_", 1)[1])
        except (IndexError, ValueError):
            index = 0
        entry = MOCK_CATALOG[index % len(MOCK_CATALOG)]
        return Identification(
            name=str(entry["name"]),
            brand=str(entry["brand"]) if entry["brand"] is not None else None,
            category=str(entry["category"]),
            condition=str(entry["condition"]),
            confidence=float(str(entry["confidence"])),
            needs_review=True,
            review_reasons=[str(r) for r in entry["review_reasons"]],  # type: ignore[union-attr]
            provider="mock",
        )


class MockPhotoProvider:
    """Mock photo step: no generation, always signals original-frame fallback."""

    provider_name = "mock"

    def generate(self, product: DetectedProduct, out_dir: Path) -> PhotoResult:
        out_dir.mkdir(parents=True, exist_ok=True)
        return PhotoResult(photo_path=product.frame_path, used_fallback=True, provider="mock")

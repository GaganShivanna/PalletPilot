"""Real provider adapters.

Each adapter below raises :class:`ProviderUnavailable` until the AI engineer
lands a verified integration. The factory never silently substitutes mock
output when a real provider is selected — a missing model is a loud error,
not fabricated results.

Handoff contract for the AI engineer (see docs/AI_HANDOFF.md in Phase 2):

- ``SamSegmentationProvider.detect``: accept sampled frames, detect products,
  associate detections across time (one ``track_id`` per physical item, no
  appearance-only merging), write masks under ``out_dir``, and return
  :class:`DetectedProduct` with ``provider="sam"``.
- ``MuseSparkIdentificationProvider.identify``: accept a representative item
  image and return :class:`Identification` (name/brand/category/condition/
  confidence/review reasons). Mark unverifiable items ``needs_review=True``.
- ``MuseImagePhotoProvider.generate``: accept a representative frame (+ mask)
  and write a neutral-background product photo under ``out_dir``. Raise
  :class:`ProviderError` (transient when retryable) on failure so the
  pipeline falls back to the original frame for that item only.
"""

from pathlib import Path

from app.providers.base import (
    DetectedProduct,
    Identification,
    PhotoResult,
    ProviderUnavailable,
)

SAM_NEEDED = (
    "SAM segmentation is not integrated yet. Needed from the AI engineer: verified "
    "model/version + SDK or endpoint, frame/video input format, mask output handling, "
    "and cross-frame track association (one track_id per physical item)."
)
MUSE_SPARK_NEEDED = (
    "Muse Spark identification is not integrated yet. Needed from the AI engineer: "
    "verified vision-capable API request/response format, credentials, timeout and "
    "rate-limit guidance."
)
MUSE_IMAGE_NEEDED = (
    "Muse Image photo editing is not integrated yet. Needed from the AI engineer: "
    "verified image-edit API request/response format, credentials, and confirmation "
    "that this environment may call Muse Image inference."
)


class SamSegmentationProvider:
    provider_name = "sam"

    def detect(self, frame_paths: list[Path], out_dir: Path) -> list[DetectedProduct]:
        raise ProviderUnavailable(SAM_NEEDED)


class MuseSparkIdentificationProvider:
    provider_name = "muse_spark"

    def identify(self, product: DetectedProduct) -> Identification:
        raise ProviderUnavailable(MUSE_SPARK_NEEDED)


class MuseImagePhotoProvider:
    provider_name = "muse_image"

    def generate(self, product: DetectedProduct, out_dir: Path) -> PhotoResult:
        raise ProviderUnavailable(MUSE_IMAGE_NEEDED)

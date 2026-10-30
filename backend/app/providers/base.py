"""Stable AI provider interface.

The pipeline depends only on the protocols in this module. The AI engineer
can swap ``AI_PROVIDER=mock`` for a real implementation without touching
routes, schemas, or pipeline code.

Contract notes:

- One :class:`DetectedProduct` per *physical* item. Two visually identical
  products in different places/times are separate items: never deduplicate
  on appearance alone. ``track_id`` must be stable for one physical item
  across frames; ``item_id`` must be stable through later pipeline stages.
- Mock output is explicitly labeled (``provider="mock"``) and must never be
  presented as real inference. The factory raises instead of silently
  substituting fabricated results for a real provider.
- One item failing photo generation must not fail the whole pallet: photo
  providers raise :class:`ProviderError` per item and the pipeline falls
  back to the original frame for that item only.
"""

from pathlib import Path
from typing import Literal, Protocol

from pydantic import BaseModel, Field


class DetectedProduct(BaseModel):
    """One distinct physical product found in the video."""

    item_id: str
    track_id: str

    frame_path: str
    mask_path: str | None = None

    name: str | None = None
    brand: str | None = None
    category: str | None = None
    condition: str = "unknown"

    confidence: float | None = None
    needs_review: bool = True
    review_reasons: list[str] = []

    provider: Literal["mock", "sam", "muse_spark", "custom"] = "mock"


class Identification(BaseModel):
    """Structured metadata for one detected product."""

    name: str
    brand: str | None = None
    category: str = "Uncategorized"
    condition: str = "unknown"
    confidence: float | None = None
    needs_review: bool = True
    review_reasons: list[str] = Field(default_factory=list)
    provider: Literal["mock", "muse_spark", "custom"] = "mock"


class PhotoResult(BaseModel):
    """Outcome of product-photo generation for one item."""

    photo_path: str
    used_fallback: bool = False
    provider: Literal["mock", "muse_image", "original"] = "mock"


class ProviderError(Exception):
    """Base error for provider failures.

    ``transient=True`` means a retry may succeed (timeout, 429, 5xx).
    Permanent errors (bad request, unsupported content) must not be retried.
    """

    def __init__(self, message: str, *, transient: bool = False):
        super().__init__(message)
        self.transient = transient


class ProviderTimeout(ProviderError):
    def __init__(self, message: str):
        super().__init__(message, transient=True)


class ProviderUnavailable(ProviderError):
    """Real provider selected but not configured/accessible.

    Raised loudly so a missing model is never mistaken for working output.
    """

    def __init__(self, message: str):
        super().__init__(message, transient=False)


class SegmentationProvider(Protocol):
    """Detect distinct physical products in sampled frames."""

    provider_name: str

    def detect(self, frame_paths: list[Path], out_dir: Path) -> list[DetectedProduct]:
        """Return one DetectedProduct per physical item, stable IDs."""
        ...


class IdentificationProvider(Protocol):
    """Identify one detected product from its representative image."""

    provider_name: str

    def identify(self, product: DetectedProduct) -> Identification:
        ...


class PhotoProvider(Protocol):
    """Generate a clean product photo for one detected product."""

    provider_name: str

    def generate(self, product: DetectedProduct, out_dir: Path) -> PhotoResult:
        """Return the generated photo; raise ProviderError to trigger fallback."""
        ...

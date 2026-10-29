"""Select provider implementations from configuration."""

from dataclasses import dataclass

from app.config import Settings
from app.providers.base import (
    IdentificationProvider,
    PhotoProvider,
    ProviderUnavailable,
    SegmentationProvider,
)
from app.providers.mock import (
    MockIdentificationProvider,
    MockPhotoProvider,
    MockSegmentationProvider,
)
from app.providers.real import (
    MuseImagePhotoProvider,
    MuseSparkIdentificationProvider,
    SamSegmentationProvider,
)


@dataclass(frozen=True)
class Providers:
    segmentation: SegmentationProvider
    identification: IdentificationProvider
    photos: PhotoProvider


def get_providers(settings: Settings) -> Providers:
    """Return the provider set for ``settings.ai_provider``.

    ``mock`` is fully local. ``sam`` / ``muse_spark`` / ``muse_image`` select
    the matching real adapter (currently raising ``ProviderUnavailable``)
    while keeping the other stages on mock. Unknown names raise loudly —
    never silently fall back to fabricated results.
    """
    name = settings.ai_provider.strip().lower()
    segmentation: SegmentationProvider = MockSegmentationProvider()
    identification: IdentificationProvider = MockIdentificationProvider()
    photos: PhotoProvider = MockPhotoProvider()
    if name == "mock":
        return Providers(segmentation, identification, photos)
    if name == "sam":
        return Providers(SamSegmentationProvider(), identification, photos)
    if name == "muse_spark":
        return Providers(segmentation, MuseSparkIdentificationProvider(settings), photos)
    if name == "muse_image":
        return Providers(segmentation, identification, MuseImagePhotoProvider())
    if name == "real":
        return Providers(
            SamSegmentationProvider(),
            MuseSparkIdentificationProvider(settings),
            MuseImagePhotoProvider(),
        )
    raise ProviderUnavailable(f"Unknown AI_PROVIDER={settings.ai_provider!r}; expected mock, sam, muse_spark, muse_image, or real.")

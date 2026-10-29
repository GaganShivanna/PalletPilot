"""Provider package: adapters isolating external model APIs from the pipeline."""

from app.providers.base import (
    DetectedProduct,
    Identification,
    PhotoResult,
    ProviderError,
    ProviderTimeout,
    ProviderUnavailable,
)

__all__ = [
    "DetectedProduct",
    "Identification",
    "PhotoResult",
    "ProviderError",
    "ProviderTimeout",
    "ProviderUnavailable",
]

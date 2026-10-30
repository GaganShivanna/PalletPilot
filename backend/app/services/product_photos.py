"""Product photos via the provider interface, with per-item fallback.

Flow per item: ask the photo provider to generate a clean photo; on any
provider failure — or when the provider reports it used a fallback — copy
the original frame into the photos directory instead. The original frame is
always preserved, and one item's failure never fails the pallet.
"""

import logging
import shutil
from pathlib import Path

from app.providers.base import DetectedProduct, PhotoProvider, ProviderError

log = logging.getLogger(__name__)


def generate_product_photos(
    product: DetectedProduct, out_dir: Path, provider: PhotoProvider
) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        result = provider.generate(product, out_dir)
    except ProviderError as exc:
        log.warning("Photo generation failed for %s (%s); using original frame", product.item_id, exc)
        return [_fallback_copy(product, out_dir)]

    generated = Path(result.photo_path)
    if result.used_fallback or not generated.is_file() or generated.resolve() == Path(product.frame_path).resolve():
        return [_fallback_copy(product, out_dir)]
    return [generated]


def _fallback_copy(product: DetectedProduct, out_dir: Path) -> Path:
    dest = out_dir / f"{product.item_id}_0.jpg"
    shutil.copyfile(product.frame_path, dest)
    return dest

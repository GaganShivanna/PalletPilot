"""Build reviewable product crops from parsed SAM observations."""

import re
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

from app.providers.base import DetectedProduct, ProviderError
from app.providers.sam_output import SamObservation


def build_sam_products(
    observations: list[SamObservation],
    frame_paths: list[Path],
    out_dir: Path,
    *,
    request_id: str,
) -> list[DetectedProduct]:
    """Select one representative crop per track within one SAM response.

    request_id namespaces IDs across separate SAM requests.
    This does not resolve duplicates caused by occlusion or re-entry.
    """
    if not re.fullmatch(r"[A-Za-z0-9_-]+", request_id):
        raise ProviderError("Invalid SAM request identifier.")

    tracks = defaultdict(list)

    for observation in observations:
        if not re.fullmatch(r"[0-9]+", observation.object_id):
            raise ProviderError("Invalid SAM object identifier.")

        tracks[observation.object_id].append(observation)

    out_dir.mkdir(parents=True, exist_ok=True)
    products = []

    for object_id, track in sorted(tracks.items()):
        best = None
        best_score = -1.0

        for observation in track:
            index = observation.frame_index

            if not 0 <= index < len(frame_paths):
                raise ProviderError(
                    "SAM frame index does not match the supplied frames."
                )

            frame = cv2.imread(str(frame_paths[index]))

            if frame is None:
                raise ProviderError("A source frame could not be read.")

            height, width = frame.shape[:2]
            left, top, right, bottom = observation.box

            if not (
                0 <= left < right <= width
                and 0 <= top < bottom <= height
            ):
                raise ProviderError(
                    "SAM bounding box is outside the source frame."
                )

            expected_size = (
                observation.mask_width * observation.mask_height
            )

            if (
                observation.mask_width <= 0
                or observation.mask_height <= 0
                or len(observation.mask) != expected_size
            ):
                raise ProviderError("SAM mask dimensions are invalid.")

            crop = frame[top:bottom, left:right].copy()

            mask = np.frombuffer(
                observation.mask,
                dtype=np.uint8,
            ).reshape(
                observation.mask_height,
                observation.mask_width,
            )

            if not np.isin(mask, [0, 1]).all():
                raise ProviderError("SAM mask must contain only 0 and 1.")

            # Align the mask raster with its bounding-box crop.
            mask = cv2.resize(
                mask,
                (right - left, bottom - top),
                interpolation=cv2.INTER_NEAREST,
            )

            if not mask.any():
                continue

            gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            score = float(cv2.Laplacian(gray, cv2.CV_64F).var())

            if score > best_score:
                best_score = score
                best = (observation, crop, mask)

        if best is None:
            raise ProviderError(
                f"SAM track {object_id} has no usable foreground mask."
            )

        observation, crop, mask = best

        track_id = f"{request_id}_{object_id}"
        crop_path = out_dir / f"{track_id}_crop.jpg"
        mask_path = out_dir / f"{track_id}_mask.png"

        if not cv2.imwrite(str(crop_path), crop):
            raise ProviderError("Could not save the product crop.")

        if not cv2.imwrite(str(mask_path), mask * 255):
            raise ProviderError("Could not save the product mask.")

        products.append(
            DetectedProduct(
                item_id=track_id,
                track_id=track_id,
                frame_path=str(crop_path),
                mask_path=str(mask_path),
                confidence=observation.confidence,
                needs_review=True,
                review_reasons=[
                    "Confirm product identity and physical quantity.",
                    "Check for repeated items after occlusion or re-entry.",
                ],
                provider="sam",
            )
        )

    return products
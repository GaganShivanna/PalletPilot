"""Build reviewable product crops from parsed SAM observations."""

import re
from collections import defaultdict
from pathlib import Path
from statistics import median

import cv2
import numpy as np

from app.providers.base import DetectedProduct, ProviderError
from app.providers.sam_output import SamObservation


# Observations narrower or shorter than this are degenerate tracking
# fragments (e.g. a 3x204 sliver). They score spuriously high on
# sharpness-per-pixel but are unidentifiable, so they are skipped in
# favor of larger observations of the same track.
MIN_CROP_SIDE = 48

# Cross-concept duplicate criterion: tracks from different SAM requests
# are the same physical item when their boxes overlap this strongly on
# enough shared frames. Medians of 0.96+ for true duplicates vs 0.41 max
# for distinct items on demo_1104 (jobs 08736b88, f287e378).
DUPLICATE_MEDIAN_IOU = 0.5
DUPLICATE_MIN_SHARED_FRAMES = 3


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
        fallback = None
        fallback_area = -1

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

            area = (right - left) * (bottom - top)

            if area > fallback_area:
                fallback_area = area
                fallback = (observation, crop, mask)

            if (right - left) < MIN_CROP_SIDE or (
                bottom - top
            ) < MIN_CROP_SIDE:
                continue

            gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            score = float(cv2.Laplacian(gray, cv2.CV_64F).var())

            if score > best_score:
                best_score = score
                best = (observation, crop, mask)

        if best is None:
            best = fallback

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


def _box_iou(
    first: tuple[int, int, int, int],
    second: tuple[int, int, int, int],
) -> float:
    inter_w = max(
        0, min(first[2], second[2]) - max(first[0], second[0])
    )
    inter_h = max(
        0, min(first[3], second[3]) - max(first[1], second[1])
    )
    inter = inter_w * inter_h
    union = (
        (first[2] - first[0]) * (first[3] - first[1])
        + (second[2] - second[0]) * (second[3] - second[1])
        - inter
    )
    return inter / union if union else 0.0


def deduplicate_products(
    grouped: list[
        tuple[str, list[DetectedProduct], list[SamObservation]]
    ],
) -> list[DetectedProduct]:
    """Merge tracks from different SAM requests on the same item.

    Takes one (request_id, products, observations) triple per concept
    request. Tracks from different requests whose boxes overlap strongly
    (median IoU >= DUPLICATE_MEDIAN_IOU over shared frames) are the same
    physical item found under two concepts; only the largest-max-area
    track is kept, with the merge recorded in its review reasons. Tracks
    within one response are left to SAM's own association.
    """
    boxes: dict[str, dict[int, tuple[int, int, int, int]]] = {}
    max_area: dict[str, int] = {}
    owner: dict[str, str] = {}
    products: dict[str, DetectedProduct] = {}
    order: list[str] = []

    for request_id, prods, observations in grouped:
        for observation in observations:
            track_id = f"{request_id}_{observation.object_id}"
            left, top, right, bottom = observation.box
            boxes.setdefault(track_id, {})[
                observation.frame_index
            ] = observation.box
            area = (right - left) * (bottom - top)
            max_area[track_id] = max(max_area.get(track_id, 0), area)

        for product in prods:
            owner[product.track_id] = request_id

            if product.track_id not in products:
                products[product.track_id] = product
                order.append(product.track_id)

    parent = {track_id: track_id for track_id in products}

    def find(track_id: str) -> str:
        while parent[track_id] != track_id:
            parent[track_id] = parent[parent[track_id]]
            track_id = parent[track_id]

        return track_id

    def union(first: str, second: str) -> None:
        root_first = find(first)
        root_second = find(second)

        if root_first != root_second:
            parent[max(root_first, root_second)] = min(
                root_first, root_second
            )

    ids = sorted(products)

    for pos, first in enumerate(ids):
        for second in ids[pos + 1 :]:
            if owner[first] == owner[second]:
                continue

            shared = sorted(
                set(boxes.get(first, ())) & set(boxes.get(second, ()))
            )

            if len(shared) < DUPLICATE_MIN_SHARED_FRAMES:
                continue

            ious = sorted(
                _box_iou(boxes[first][frame], boxes[second][frame])
                for frame in shared
            )

            if median(ious) >= DUPLICATE_MEDIAN_IOU:
                union(first, second)

    groups: dict[str, list[str]] = {}

    for track_id in ids:
        groups.setdefault(find(track_id), []).append(track_id)

    kept = []

    for track_id in order:
        members = groups[find(track_id)]
        keeper = min(
            members, key=lambda t: (-max_area.get(t, 0), t)
        )

        if track_id != keeper:
            continue

        dropped = sorted(set(members) - {track_id})

        if dropped:
            products[track_id].review_reasons.append(
                "Merged duplicate track(s) "
                + ", ".join(dropped)
                + " (overlapping segmentation across concepts)."
            )

        kept.append(products[track_id])

    return kept
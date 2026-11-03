from dataclasses import replace
from pathlib import Path

import cv2
import numpy as np
import pytest

from app.providers.base import ProviderError
from app.providers.sam_output import SamObservation
from app.providers.sam_products import build_sam_products


def observation(object_id="7", frame_index=0):
    return SamObservation(
        object_id=object_id,
        frame_index=frame_index,
        box=(10, 20, 15, 25),
        mask=bytes([1] * 25),
        mask_width=5,
        mask_height=5,
        confidence=0.9,
    )


def make_frames(tmp_path):
    paths = []

    for index in range(2):
        frame = np.full((40, 50, 3), 150, dtype=np.uint8)
        path = tmp_path / f"frame_{index}.jpg"
        assert cv2.imwrite(str(path), frame)
        paths.append(path)

    return paths


def test_creates_one_product_per_track(tmp_path):
    frames = make_frames(tmp_path)

    products = build_sam_products(
        [
            observation("7", 0),
            observation("7", 1),
            observation("11", 0),
        ],
        frames,
        tmp_path / "products",
        request_id="request_1",
    )

    # Repeated observations of ID 7 become one candidate.
    # ID 11 remains separate despite identical appearance.
    assert len(products) == 2
    assert {p.track_id for p in products} == {
        "request_1_7",
        "request_1_11",
    }

    for product in products:
        assert product.provider == "sam"
        assert product.needs_review is True

        assert Path(product.frame_path).is_file()
        assert product.mask_path is not None

        crop = cv2.imread(product.frame_path)
        mask = cv2.imread(
            product.mask_path,
            cv2.IMREAD_GRAYSCALE,
        )

        assert crop.shape[:2] == (5, 5)
        assert mask.shape == (5, 5)
        assert np.all(mask == 255)


def test_rejects_unknown_frame(tmp_path):
    with pytest.raises(ProviderError, match="frame index"):
        build_sam_products(
            [observation(frame_index=9)],
            make_frames(tmp_path),
            tmp_path / "products",
            request_id="request_1",
        )


def test_rejects_invalid_mask_size(tmp_path):
    invalid = replace(
        observation(),
        mask=bytes([1] * 24),
    )

    with pytest.raises(ProviderError, match="mask dimensions"):
        build_sam_products(
            [invalid],
            make_frames(tmp_path),
            tmp_path / "products",
            request_id="request_1",
        )
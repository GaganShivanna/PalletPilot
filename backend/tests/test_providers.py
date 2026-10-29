"""Provider interface tests: determinism, dedup contract, loud failures."""

from pathlib import Path

import pytest

from app.config import Settings
from app.providers.base import ProviderUnavailable
from app.providers.factory import get_providers
from app.providers.mock import MockIdentificationProvider, MockSegmentationProvider
from app.providers.real import (
    MuseImagePhotoProvider,
    MuseSparkIdentificationProvider,
    SamSegmentationProvider,
)


def _frames(tmp_path: Path, n: int = 9) -> list[Path]:
    paths = []
    for i in range(n):
        p = tmp_path / f"frame_{i:05d}.jpg"
        p.write_bytes(b"fake")
        paths.append(p)
    return paths


def _settings(**overrides):
    return Settings(_env_file=None, **overrides)


def test_mock_segmentation_is_deterministic(tmp_path):
    frames = _frames(tmp_path)
    first = MockSegmentationProvider().detect(frames, tmp_path / "m1")
    second = MockSegmentationProvider().detect(frames, tmp_path / "m2")
    assert [(p.item_id, p.track_id) for p in first] == [(p.item_id, p.track_id) for p in second]
    assert len(first) == 3


def test_dedup_contract_distinct_tracks_never_merged(tmp_path):
    """Visually identical frames still yield distinct physical items."""
    same = tmp_path / "same.jpg"
    same.write_bytes(b"identical-bytes")
    frames = [same] * 6
    products = MockSegmentationProvider().detect(frames, tmp_path / "masks")
    track_ids = [p.track_id for p in products]
    assert len(track_ids) == len(set(track_ids)) > 1
    assert all(p.provider == "mock" and p.needs_review for p in products)


def test_mock_products_carry_stable_ids(tmp_path):
    frames = _frames(tmp_path)
    products = MockSegmentationProvider().detect(frames, tmp_path / "masks")
    assert [p.item_id for p in products] == ["item_0", "item_1", "item_2"]
    assert all(p.frame_path for p in products)


def test_mock_identification_is_labeled_and_reviewable(tmp_path):
    product = MockSegmentationProvider().detect(_frames(tmp_path), tmp_path / "m")[0]
    result = MockIdentificationProvider().identify(product)
    assert result.provider == "mock"
    assert result.needs_review is True
    assert result.name
    assert result.review_reasons


def test_factory_defaults_to_mock(tmp_path):
    providers = get_providers(_settings(data_dir=tmp_path))
    assert providers.segmentation.provider_name == "mock"
    assert providers.identification.provider_name == "mock"
    assert providers.photos.provider_name == "mock"


def test_real_adapters_fail_loudly_never_silent_mock(tmp_path):
    frames = _frames(tmp_path)
    product = MockSegmentationProvider().detect(frames, tmp_path / "m")[0]
    with pytest.raises(ProviderUnavailable):
        SamSegmentationProvider(_settings(muse_api_key=None)).detect(frames, tmp_path / "masks")
    with pytest.raises(ProviderUnavailable):
        MuseSparkIdentificationProvider(_settings(muse_api_key=None)).identify(product)
    with pytest.raises(ProviderUnavailable):
        MuseImagePhotoProvider().generate(product, tmp_path / "photos")


def test_factory_unknown_provider_raises(tmp_path):
    with pytest.raises(ProviderUnavailable):
        get_providers(_settings(data_dir=tmp_path, ai_provider="bogus"))

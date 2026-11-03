"""Tiered pricing: exact fixtures beat category estimates beat unknown."""

from app.services.pricing import get_price


def test_exact_fixture_wins_over_category():
    estimate = get_price("Acme Cordless Drill", "Power Tools")
    assert estimate.amount == 45.0
    assert estimate.source == "mock_fixture"


def test_category_estimate_for_unknown_product():
    estimate = get_price("Black Mesh Wastebasket", "Trash Cans & Wastebaskets")
    assert estimate.amount == 8.0
    assert estimate.source == "category_estimate"
    assert estimate.price_type == "estimate"


def test_category_lookup_is_case_and_space_insensitive():
    estimate = get_price("Some rug", "  RUGS ")
    assert estimate.amount == 20.0
    assert estimate.source == "category_estimate"


def test_vague_categories_stay_null():
    for category in ["Unknown", "Uncategorized", "Other", "", None]:
        estimate = get_price("Unidentifiable item", category)
        assert estimate.amount is None
        assert estimate.source == "none"


def test_unmatched_category_stays_null():
    estimate = get_price("Exotic gadget", "Quantum Devices")
    assert estimate.amount is None
    assert estimate.source == "none"


def test_results_are_independent_copies():
    first = get_price("Some rug", "Rugs")
    first.amount = 999.0
    assert get_price("Other rug", "rugs").amount == 20.0

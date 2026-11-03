import pytest

from app.providers.base import Identification
from app.services.manifest import ManifestMatcher, parse_manifest_csv


def test_reads_manifest_and_defaults_quantity():
    entries = parse_manifest_csv(
        b"id,name,brand,quantity\n"
        b"mug,Ceramic mug,,2\n"
        b"drill,Cordless drill,Acme,\n"
    )

    assert len(entries) == 2
    assert entries[0]["quantity"] == 2
    assert entries[1]["quantity"] == 1


@pytest.mark.parametrize(
    "data",
    [
        b"title,quantity\nMug,1\n",
        b"name,quantity\nMug,-1\n",
        b"name,quantity\nMug,1.5\n",
        b"name,quantity\nMug,0\n",
        b"id,name\nsame,Mug\nsame,Drill\n",
    ],
)
def test_rejects_invalid_manifest(data):
    with pytest.raises(ValueError):
        parse_manifest_csv(data)


def test_matches_brand_without_overwriting_identification():
    matcher = ManifestMatcher(
        parse_manifest_csv(
            b"id,name,brand,quantity\n"
            b"drill,Cordless drill,Acme,1\n"
        )
    )

    identity = Identification(
        name="Acme Cordless Drill",
        brand="Acme",
        condition="unknown",
        provider="muse_spark",
    )

    before = identity.model_dump()
    decision = matcher.check("item_1", identity)

    assert decision["status"] == "matched"
    assert identity.model_dump() == before
    assert matcher.report()["manifest_rows"][0]["matched_quantity"] == 1


def test_generic_candy_is_not_upgraded_to_skittles():
    matcher = ManifestMatcher(
        parse_manifest_csv(
            b"id,name,brand,quantity\n"
            b"candy,Candy bag,Skittles,1\n"
        )
    )

    identity = Identification(
        name="Candy bag",
        brand=None,
        provider="muse_spark",
    )

    decision = matcher.check("item_1", identity)

    assert decision["status"] == "uncertain"
    assert identity.brand is None
    assert identity.name == "Candy bag"
    assert matcher.report()["manifest_rows"][0]["matched_quantity"] == 0


def test_reports_unseen_items_without_claiming_absence():
    matcher = ManifestMatcher(
        parse_manifest_csv(
            b"id,name,brand,quantity\n"
            b"mug,Ceramic mug,,2\n"
        )
    )

    matcher.check(
        "item_1",
        Identification(name="Ceramic mug"),
    )

    report = matcher.report()
    row = report["manifest_rows"][0]

    assert row["status"] == "partially_seen"
    assert row["not_seen_quantity"] == 1
    assert "does not mean absent" in report["note"]


def test_excess_count_is_flagged_not_merged():
    matcher = ManifestMatcher(
        parse_manifest_csv(b"id,name,quantity\nmug,Ceramic mug,1\n")
    )

    identity = Identification(name="Ceramic mug")

    assert matcher.check("item_1", identity)["status"] == "matched"
    assert matcher.check("item_2", identity)["status"] == "uncertain"

    row = matcher.report()["manifest_rows"][0]

    assert row["matched_quantity"] == 1
    assert row["uncertain_item_ids"] == ["item_2"]


def test_does_not_count_same_item_twice():
    matcher = ManifestMatcher(
        parse_manifest_csv(b"name,quantity\nCeramic mug,2\n")
    )

    identity = Identification(name="Ceramic mug")
    matcher.check("item_1", identity)

    with pytest.raises(ValueError, match="already"):
        matcher.check("item_1", identity)
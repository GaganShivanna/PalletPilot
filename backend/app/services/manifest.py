"""Conservative manifest reconciliation.

Manifest matches are associations, not proof of identity or quantity.
Unseen manifest entries are not automatically absent from the pallet.
"""

import copy
import csv
import io
import re
import unicodedata

from app.providers.base import Identification


def normalize(value: str | None) -> str:
    value = unicodedata.normalize("NFKC", value or "").casefold()
    return " ".join(re.findall(r"[^\W_]+", value))


def name_key(name: str, brand: str | None) -> str:
    """Compare product names with an explicitly supplied brand removed."""
    brand_words = set(normalize(brand).split())
    return " ".join(
        word
        for word in normalize(name).split()
        if word not in brand_words
    )


def parse_manifest_csv(data: bytes) -> list[dict]:
    """Read UTF-8 CSV with name, optional id/brand, and optional quantity."""
    if not data or len(data) > 1024 * 1024:
        raise ValueError("Manifest must contain 1 byte to 1 MB of CSV data.")

    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise ValueError("Manifest must use UTF-8 encoding.") from None

    if "\x00" in text:
        raise ValueError("Manifest contains invalid null characters.")

    try:
        reader = csv.DictReader(io.StringIO(text), strict=True)

        if not reader.fieldnames:
            raise ValueError("Manifest needs a header row.")

        headers = [
            header.strip().casefold()
            for header in reader.fieldnames
        ]

        if len(headers) != len(set(headers)):
            raise ValueError("Manifest contains duplicate column names.")

        if "name" not in headers:
            raise ValueError("Manifest requires a 'name' column.")

        reader.fieldnames = headers
        entries = []
        ids = set()

        for line_number, row in enumerate(reader, start=2):
            if len(entries) >= 1000:
                raise ValueError("Manifest supports at most 1,000 rows.")

            if None in row:
                raise ValueError(
                    f"Manifest row {line_number} has extra columns."
                )

            name = (row.get("name") or "").strip()
            brand = (row.get("brand") or "").strip() or None
            entry_id = (
                (row.get("id") or "").strip()
                or f"row_{line_number}"
            )
            raw_quantity = (row.get("quantity") or "1").strip() or "1"

            if not normalize(name) or len(name) > 200:
                raise ValueError(
                    f"Manifest row {line_number} needs a valid product name."
                )

            if len(entry_id) > 100 or entry_id in ids:
                raise ValueError(
                    f"Manifest row {line_number} has an invalid or duplicate ID."
                )

            if brand is not None and len(brand) > 100:
                raise ValueError(
                    f"Manifest row {line_number} has an invalid brand."
                )

            if not re.fullmatch(r"[0-9]+", raw_quantity):
                raise ValueError(
                    f"Manifest row {line_number} needs a whole-number quantity."
                )

            quantity = int(raw_quantity)

            if not 1 <= quantity <= 1000:
                raise ValueError(
                    f"Manifest row {line_number} quantity must be 1–1,000."
                )

            ids.add(entry_id)
            entries.append(
                {
                    "id": entry_id,
                    "name": name,
                    "brand": brand,
                    "quantity": quantity,
                }
            )

    except csv.Error:
        raise ValueError("Manifest contains malformed CSV.") from None

    if not entries:
        raise ValueError("Manifest must contain at least one product row.")

    return entries


class ManifestMatcher:
    def __init__(self, entries: list[dict]):
        self.entries = copy.deepcopy(entries)
        self.matched = {entry["id"]: [] for entry in entries}
        self.uncertain = {entry["id"]: [] for entry in entries}
        self.decisions = {}

    def check(
        self,
        item_id: str,
        identification: Identification,
    ) -> dict:
        """Associate one detected item without modifying its identification."""
        if item_id in self.decisions:
            raise ValueError("This item has already been reconciled.")

        exact = []
        possible = []

        observed_brand = normalize(identification.brand)
        observed_words = set(normalize(identification.name).split())

        for entry in self.entries:
            expected_brand = normalize(entry["brand"])
            expected_name = name_key(entry["name"], entry["brand"])
            observed_name = name_key(
                identification.name,
                identification.brand,
            )

            names_align = (
                bool(expected_name)
                and expected_name == observed_name
            )

            brands_align = (
                not expected_brand
                or expected_brand == observed_brand
            )

            if names_align and brands_align:
                exact.append(entry)

            if (
                names_align
                or observed_words
                & set(normalize(entry["name"]).split())
            ):
                possible.append(entry)

        if len(exact) == 1:
            entry = exact[0]
            entry_id = entry["id"]

            if len(self.matched[entry_id]) < entry["quantity"]:
                self.matched[entry_id].append(item_id)

                decision = {
                    "item_id": item_id,
                    "status": "matched",
                    "manifest_ids": [entry_id],
                    "reasons": [
                        "Name and supplied brand agree with one manifest row.",
                        "Seller must still verify the physical item.",
                    ],
                }
            else:
                self.uncertain[entry_id].append(item_id)

                decision = {
                    "item_id": item_id,
                    "status": "uncertain",
                    "manifest_ids": [entry_id],
                    "reasons": [
                        "Detected count exceeds the manifest quantity.",
                        "Check for an extra item or a repeated SAM track.",
                    ],
                }

        elif exact or possible:
            candidates = exact or possible
            candidate_ids = [entry["id"] for entry in candidates]

            for entry_id in candidate_ids:
                self.uncertain[entry_id].append(item_id)

            decision = {
                "item_id": item_id,
                "status": "uncertain",
                "manifest_ids": candidate_ids,
                "reasons": [
                    "Possible manifest association is ambiguous, "
                    "or the expected brand is missing or conflicting.",
                    "Do not replace the observed identity with the manifest name.",
                ],
            }

        else:
            decision = {
                "item_id": item_id,
                "status": "unmatched",
                "manifest_ids": [],
                "reasons": [
                    "No conservative manifest match was established.",
                    "This may be an extra item or a naming mismatch; review it.",
                ],
            }

        self.decisions[item_id] = decision
        return copy.deepcopy(decision)

    def report(self) -> dict:
        rows = []

        for entry in self.entries:
            entry_id = entry["id"]
            matched_ids = self.matched[entry_id]
            uncertain_ids = self.uncertain[entry_id]
            remaining = entry["quantity"] - len(matched_ids)

            if uncertain_ids:
                status = "uncertain"
            elif remaining == 0:
                status = "matched"
            elif matched_ids:
                status = "partially_seen"
            else:
                status = "not_seen"

            rows.append(
                {
                    **entry,
                    "status": status,
                    "matched_quantity": len(matched_ids),
                    "not_seen_quantity": remaining,
                    "matched_item_ids": list(matched_ids),
                    "uncertain_item_ids": list(uncertain_ids),
                }
            )

        return {
            "manifest_rows": rows,
            "items": copy.deepcopy(list(self.decisions.values())),
            "note": (
                "Not seen in the video does not mean absent from the pallet. "
                "Matches do not independently verify product identity."
            ),
        }
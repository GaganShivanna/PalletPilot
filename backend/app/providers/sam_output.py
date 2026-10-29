"""Convert completed SAM output into usable per-frame observations."""

from dataclasses import dataclass

from meta_sam_parser import (
    CompletedOutcome,
    SegmentationBoxRecord,
    SegmentationMaskRecord,
    decode_mask_to_raster,
    video_segmentation_format,
)

from app.providers.base import ProviderError


@dataclass(frozen=True)
class SamObservation:
    object_id: str
    frame_index: int

    # Source-pixel coordinates; right and bottom are exclusive.
    box: tuple[int, int, int, int]

    # Row-major bytes containing 0 or 1.
    mask: bytes
    mask_width: int
    mask_height: int

    confidence: float | None


def parse_completed_sam_output(
    output_text: str,
) -> list[SamObservation]:
    """Parse output from a successfully completed SAM response.

    The HTTP adapter must verify response completion before calling this.
    Object IDs belong to this response, not to other SAM requests.
    """
    parser = video_segmentation_format().create_parser()

    try:
        parser.push(output_text)
        result = parser.finish(CompletedOutcome()).result
    except (ValueError, TypeError) as exc:
        raise ProviderError(
            "SAM output could not be parsed."
        ) from exc

    # Reject diagnostics conservatively rather than silently dropping items.
    if result.diagnostics:
        details = "; ".join(
            f"{diagnostic.code}: {diagnostic.message}"
            for diagnostic in result.diagnostics
        )
        raise ProviderError(f"SAM parsing failed: {details}")

    boxes = {}
    masks = {}

    for record in result.records:
        if not isinstance(
            record,
            (SegmentationBoxRecord, SegmentationMaskRecord),
        ):
            raise ProviderError(
                "SAM returned unexpected content instead of segmentation."
            )

        if record.frame is None:
            raise ProviderError(
                "A SAM video record is missing its frame reference."
            )

        key = (record.frame.frame_index, record.object_id)

        if isinstance(record, SegmentationBoxRecord):
            if key in boxes:
                raise ProviderError(
                    "SAM returned a duplicate box for the same observation."
                )
            boxes[key] = record
        else:
            if key in masks:
                raise ProviderError(
                    "SAM returned a duplicate mask for the same observation."
                )
            masks[key] = record

    if boxes.keys() != masks.keys():
        raise ProviderError(
            "SAM returned unmatched boxes and masks."
        )

    observations = []

    for frame_index, object_id in sorted(boxes):
        key = (frame_index, object_id)
        box = boxes[key]
        mask = masks[key].mask

        observations.append(
            SamObservation(
                object_id=object_id,
                frame_index=frame_index,
                box=(
                    box.left,
                    box.top,
                    box.right,
                    box.bottom,
                ),
                mask=decode_mask_to_raster(mask),
                mask_width=mask.width,
                mask_height=mask.height,
                confidence=box.confidence,
            )
        )

    return observations
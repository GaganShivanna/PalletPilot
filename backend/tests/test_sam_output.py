import pytest

from app.providers.base import ProviderError
from app.providers.sam_output import parse_completed_sam_output


def record(object_id, left=10):
    # Complete encoded payload, including its encoding marker.
    encoded_mask = "!!!!!(QO(0lu8?"

    return (
        f"{object_id}"
        f"<|box;x1={left};y1=20;x2={left + 4};"
        "y2=24;w=100;h=100;c=0.9|>"
        "<|mask;x=0;y=0;c=0.9;data=5,5,"
        f"{encoded_mask}|>"
    )


def test_reads_frame_ids_boxes_and_masks():
    # Frames can arrive out of order and can skip indices.
    output = (
        "<3f>" + record(7) + "\n"
        "<0f>" + record(7) + "\n"
    )

    observations = parse_completed_sam_output(output)

    assert len(observations) == 2
    assert [o.frame_index for o in observations] == [0, 3]
    assert all(o.object_id == "7" for o in observations)

    first = observations[0]

    # Inclusive wire corners become exclusive crop boundaries.
    assert first.box == (10, 20, 15, 25)
    assert first.mask_width == 5
    assert first.mask_height == 5
    assert len(first.mask) == 25
    assert set(first.mask) <= {0, 1}
    assert first.confidence == pytest.approx(0.9)


def test_keeps_distinct_objects_separate():
    output = (
        "<0f>"
        + record(7, left=10)
        + ","
        + record(11, left=40)
        + "\n"
    )

    observations = parse_completed_sam_output(output)

    assert len(observations) == 2
    assert {o.object_id for o in observations} == {"7", "11"}


def test_empty_completed_output_is_valid():
    assert parse_completed_sam_output("") == []


def test_rejects_incomplete_geometry():
    output = (
        "<0f>7"
        "<|box;x1=10;y1=20;x2=14;y2=24;w=100;h=100|>\n"
    )

    with pytest.raises(ProviderError):
        parse_completed_sam_output(output)
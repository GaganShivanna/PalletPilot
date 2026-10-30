"""Find distinct items in sampled frames and produce SAM masks for each.

STUB: picks evenly spaced frames as stand-in "items" with no mask, so the
pipeline runs end to end. Replace with SAM inference + de-duplication.
"""

from dataclasses import dataclass
from pathlib import Path


@dataclass
class DetectedItem:
    item_id: str
    frame_path: Path
    mask_path: Path | None = None


def detect_items(frame_paths: list[Path], out_dir: Path, max_items: int = 3) -> list[DetectedItem]:
    out_dir.mkdir(parents=True, exist_ok=True)
    step = max(len(frame_paths) // max_items, 1)
    picked = frame_paths[::step][:max_items]
    return [DetectedItem(item_id=f"item_{i}", frame_path=p) for i, p in enumerate(picked)]

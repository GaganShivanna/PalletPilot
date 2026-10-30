"""Sample frames from an uploaded video at a fixed rate."""

from pathlib import Path

import cv2


class FrameSamplingError(Exception):
    pass


def sample_frames(video_path: Path, out_dir: Path, fps: float, max_frames: int) -> list[Path]:
    """Write every ~1/fps seconds of video to out_dir as JPEGs; return the paths in order."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FrameSamplingError(f"Could not open video: {video_path.name}")

    out_dir.mkdir(parents=True, exist_ok=True)
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(src_fps / fps, 1.0)

    paths: list[Path] = []
    next_index = 0.0
    index = 0
    try:
        while len(paths) < max_frames:
            ok, frame = cap.read()
            if not ok:
                break
            if index >= next_index:
                path = out_dir / f"frame_{len(paths):05d}.jpg"
                cv2.imwrite(str(path), frame)
                paths.append(path)
                next_index += step
            index += 1
    finally:
        cap.release()

    if not paths:
        raise FrameSamplingError("Video contained no readable frames")
    return paths

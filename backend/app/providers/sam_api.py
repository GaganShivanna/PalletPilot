"""SAM video segmentation with manual or automatic concept discovery."""

import base64
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import cv2

from app.config import Settings
from app.providers.base import (
    DetectedProduct,
    ProviderError,
    ProviderTimeout,
    ProviderUnavailable,
)
from app.providers.concept_discovery import discover_concepts
from app.providers.sam_output import parse_completed_sam_output
from app.providers.sam_products import (
    build_sam_products,
    deduplicate_products,
)


# Codecs tried in order for the SAM input clip. mp4v is preferred, but
# some OpenCV builds (missing ffmpeg codecs) cannot open it — that was the
# "encoder could not be opened" failure. avc1/mp4s cover those builds; the
# container stays .mp4 either way.
_FOURCC_TAGS = ("mp4v", "avc1", "mp4s")


def _codec_order(preferred: tuple[str, ...] = ()) -> tuple[str, ...]:
    """Preferred codecs first (from `SAM_FOURCC`), then the defaults."""
    order = [tag for tag in preferred if len(tag) == 4]
    order.extend(tag for tag in _FOURCC_TAGS if tag not in order)
    return tuple(order)


def _encode_with_codec(
    frame_paths: list[Path],
    destination: Path,
    fps: float,
    size: tuple[int, int],
    source_shape: tuple[int, int],
    tag: str,
) -> None:
    """Encode and verify the clip with one codec.

    Opening is not proof: some backends report an opened writer and then
    write nothing readable (0-byte AVFoundation output in headless
    sessions). Only a clip that re-decodes with the expected frame count
    and dimensions counts as success.
    """
    height, width = source_shape
    target_height, target_width = size[1], size[0]
    writer = cv2.VideoWriter(
        str(destination),
        cv2.VideoWriter_fourcc(*tag),
        fps,
        size,
    )

    if not writer.isOpened():
        writer.release()
        raise ProviderError(f"codec {tag} could not be opened")

    try:
        for path in frame_paths:
            frame = cv2.imread(str(path))

            if frame is None or frame.shape[:2] != (height, width):
                raise ProviderError(
                    "Source frames must be readable and have equal dimensions."
                )

            writer.write(frame[0:target_height, 0:target_width])
    finally:
        writer.release()

    capture = cv2.VideoCapture(str(destination))

    try:
        if not capture.isOpened():
            raise ProviderError(
                f"codec {tag} produced a clip that could not be opened"
            )

        count = 0

        while True:
            ok, frame = capture.read()

            if not ok:
                break

            if frame.shape[:2] != (target_height, target_width):
                raise ProviderError(
                    f"codec {tag} changed frame dimensions"
                )

            count += 1

        if count != len(frame_paths):
            raise ProviderError(
                f"codec {tag} wrote {count} of {len(frame_paths)} frames"
            )
    finally:
        capture.release()


def encode_video(
    frame_paths: list[Path],
    destination: Path,
    fps: float,
    preferred_tags: tuple[str, ...] = (),
) -> Path:
    """Encode frames in order while preserving their indices."""
    if not frame_paths:
        raise ProviderError("No source frames were supplied to SAM.")

    if fps <= 0:
        raise ProviderError("The SAM encode frame rate must be positive.")

    first = cv2.imread(str(frame_paths[0]))

    if first is None:
        raise ProviderError("The first source frame could not be read.")

    height, width = first.shape[:2]

    # Trim a stray odd row/column instead of failing the whole job: phone
    # footage is occasionally odd-sized and no detection signal lives in the
    # last pixel line. Frames with genuinely different dimensions still fail.
    target_height = height - (height % 2)
    target_width = width - (width % 2)

    destination.parent.mkdir(parents=True, exist_ok=True)

    order = _codec_order(preferred_tags)
    failures = []

    for tag in order:
        try:
            _encode_with_codec(
                frame_paths,
                destination,
                fps,
                (target_width, target_height),
                (height, width),
                tag,
            )
        except ProviderError as exc:
            failures.append(f"{tag} ({exc})")
            continue

        return destination

    raise ProviderError(
        "The MP4 video encoder could not be opened "
        f"(tried {', '.join(order)}: {'; '.join(failures)}). "
        "The OpenCV build may lack working video encoders — "
        "reinstall opencv-python with ffmpeg support."
    )

    return destination


def request_sam_output(
    video_path: Path,
    concept: str,
    settings: Settings,
) -> str:
    """Make one SAM request and return successfully completed output text."""
    secret = settings.muse_api_key
    api_key = secret.get_secret_value().strip() if secret else ""

    if not api_key:
        raise ProviderUnavailable("SAM requires MUSE_API_KEY.")

    # Conservative local limit for the inline-video adapter.
    if video_path.stat().st_size > 20 * 1024 * 1024:
        raise ProviderError(
            "The sampled SAM clip exceeds 20 MB. "
            "Use a shorter test video."
        )

    encoded = base64.b64encode(
        video_path.read_bytes()
    ).decode("ascii")

    payload = {
        "model": settings.sam_model,
        "stream": False,
        "metadata": {
            "include_confidence": "true",
            "mask_encoding": "one_bit",
        },
        "input": [
            {
                "type": "message",
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": concept,
                    },
                    {
                        "type": "input_video",
                        "video_url": (
                            f"data:video/mp4;base64,{encoded}"
                        ),
                    },
                ],
            }
        ],
    }

    request = Request(
        settings.muse_base_url.rstrip("/") + "/responses",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(
            request,
            timeout=settings.sam_timeout_s,
        ) as response:
            result = json.load(response)

    except HTTPError as exc:
        if exc.code in {401, 403, 404}:
            raise ProviderUnavailable(
                f"SAM returned HTTP {exc.code}. "
                "Check model access and credentials."
            ) from None

        raise ProviderError(
            f"SAM returned HTTP {exc.code}.",
            transient=exc.code in {408, 429} or exc.code >= 500,
        ) from None

    except TimeoutError:
        raise ProviderTimeout(
            "SAM processing timed out."
        ) from None

    except URLError:
        raise ProviderError(
            "Could not connect to SAM.",
            transient=True,
        ) from None

    except ValueError:
        raise ProviderError(
            "SAM returned invalid JSON."
        ) from None

    try:
        if result["status"] != "completed":
            raise ValueError("Incomplete response.")

        texts = []

        for item in result["output"]:
            if item.get("type") != "message":
                continue

            for part in item.get("content", []):
                if part.get("type") == "refusal":
                    raise ValueError("Response refused.")

                if part.get("type") == "output_text":
                    text = part["text"]

                    if not isinstance(text, str):
                        raise ValueError("Invalid output text.")

                    texts.append(text)

        if len(texts) > 1:
            raise ValueError(
                "Unexpected multiple output-text lanes."
            )

        return texts[0] if texts else ""

    except (
        KeyError,
        TypeError,
        ValueError,
        AttributeError,
    ):
        raise ProviderError(
            "SAM did not return a valid, completed "
            "segmentation response."
        ) from None


def detect_with_sam(
    frame_paths: list[Path],
    out_dir: Path,
    settings: Settings,
) -> list[DetectedProduct]:
    """Discover concepts, run SAM and build reviewable product crops.

    A non-empty SAM_CONCEPTS setting overrides automatic discovery.
    Each concept gets a separate SAM request and track-ID namespace.
    """
    secret = settings.muse_api_key

    if secret is None or not secret.get_secret_value().strip():
        raise ProviderUnavailable("SAM requires MUSE_API_KEY.")

    out_dir.mkdir(parents=True, exist_ok=True)

    if settings.sam_concepts.strip():
        concepts = list(
            dict.fromkeys(
                value.strip()
                for value in settings.sam_concepts.split(",")
                if value.strip()
            )
        )

        if not 1 <= len(concepts) <= 5:
            raise ProviderUnavailable(
                "SAM_CONCEPTS must contain 1–5 "
                "comma-separated product types."
            )
    else:
        concepts = discover_concepts(
            frame_paths,
            out_dir,
            settings,
        )

    if not concepts:
        # Valid empty discovery result: no SAM calls are necessary.
        return []

    preferred = tuple(
        value.strip().lower()
        for value in settings.sam_fourcc.split(",")
        if value.strip()
    )
    video_path = encode_video(
        frame_paths,
        out_dir / "sam_input.mp4",
        settings.sample_fps,
        preferred,
    )

    grouped = []

    for index, concept in enumerate(concepts):
        output_text = request_sam_output(
            video_path,
            concept,
            settings,
        )

        # Preserve the original response for debugging and evaluation.
        response_path = out_dir / f"sam_response_{index}.txt"
        response_path.write_text(
            output_text,
            encoding="utf-8",
        )

        observations = parse_completed_sam_output(output_text)

        candidates = build_sam_products(
            observations,
            frame_paths,
            out_dir,
            request_id=f"concept_{index}",
        )

        for candidate in candidates:
            candidate.review_reasons.append(
                f"Detected using concept '{concept}'; "
                "check for duplicates across concepts."
            )

        grouped.append(
            (f"concept_{index}", candidates, observations)
        )

    return deduplicate_products(grouped)
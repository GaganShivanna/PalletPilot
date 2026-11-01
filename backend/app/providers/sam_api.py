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
from app.providers.sam_products import build_sam_products


def encode_video(
    frame_paths: list[Path],
    destination: Path,
    fps: float,
) -> Path:
    """Encode frames in order while preserving their indices."""
    if not frame_paths:
        raise ProviderError("No source frames were supplied to SAM.")

    first = cv2.imread(str(frame_paths[0]))

    if first is None:
        raise ProviderError("The first source frame could not be read.")

    height, width = first.shape[:2]

    # Prevent silent dimension changes by the encoder.
    if width % 2 or height % 2:
        raise ProviderError(
            "SAM input frames must have even width and height."
        )

    destination.parent.mkdir(parents=True, exist_ok=True)

    writer = cv2.VideoWriter(
        str(destination),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )

    if not writer.isOpened():
        writer.release()
        raise ProviderError("The MP4 video encoder could not be opened.")

    try:
        for path in frame_paths:
            frame = cv2.imread(str(path))

            if frame is None or frame.shape[:2] != (height, width):
                raise ProviderError(
                    "Source frames must be readable and have equal dimensions."
                )

            writer.write(frame)
    finally:
        writer.release()

    # Check that the encoded video matches the supplied source frames.
    capture = cv2.VideoCapture(str(destination))

    try:
        if not capture.isOpened():
            raise ProviderError(
                "The encoded SAM video could not be opened."
            )

        count = 0

        while True:
            ok, frame = capture.read()

            if not ok:
                break

            if frame.shape[:2] != (height, width):
                raise ProviderError(
                    "Video encoding changed frame dimensions."
                )

            count += 1

        if count != len(frame_paths):
            raise ProviderError(
                "Video encoding changed the frame count."
            )
    finally:
        capture.release()

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

    video_path = encode_video(
        frame_paths,
        out_dir / "sam_input.mp4",
        settings.sample_fps,
    )

    products = []

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

        products.extend(candidates)

    return products
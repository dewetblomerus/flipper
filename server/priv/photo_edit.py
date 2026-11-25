import os
import json
import math
import sys

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

import numpy as np
from PIL import Image
from skimage import color, feature, transform
import torch
from transformers import AutoModelForZeroShotObjectDetection, AutoProcessor

MODEL_ID = "IDEA-Research/grounding-dino-base"
MIN_TILT = 1
MAX_TILT = 20

_processor = None
_model = None


def main() -> None:
    source = sys.argv[1]
    dest = sys.argv[2]
    image = Image.open(source).convert("RGB")
    text = phrase(sys.argv[3])
    box = product_box(image, text)
    angle = tilt(image, box)

    if angle:
        turned = image.rotate(angle, resample=Image.BICUBIC, expand=True, fillcolor="white")
        turned_box = product_box(turned, text)

        if inside_photo(image.size, angle, turned_box):
            image, box = turned, turned_box
        else:
            angle = 0.0

    left, top, width, height = box
    save_crop(image.crop((left, top, left + width, top + height)), dest)
    json.dump(
        {"left": left, "top": top, "width": width, "height": height, "angle": angle},
        sys.stdout,
    )
    sys.stdout.write("\n")


def phrase(title: str) -> str:
    kept = [char.lower() if char.isalnum() or char in " '-" else " " for char in title]
    text = " ".join("".join(kept).split())

    if not text:
        sys.exit("no subject")

    return text


def product_box(image, text):
    processor, model = detector()
    inputs = processor(images=image, text=[[text]], return_tensors="pt")

    with torch.no_grad():
        outputs = model(**inputs)

    result = processor.post_process_grounded_object_detection(
        outputs,
        inputs.input_ids,
        threshold=0.25,
        text_threshold=0.25,
        target_sizes=[image.size[::-1]],
    )[0]

    return top_box(result["scores"], result["boxes"], image.size)


def detector():
    global _processor, _model

    if _model is None:
        _processor = AutoProcessor.from_pretrained(MODEL_ID)
        _model = AutoModelForZeroShotObjectDetection.from_pretrained(MODEL_ID)
        _model.eval()

    return _processor, _model


def top_box(scores, boxes, size):
    if scores.numel() == 0:
        sys.exit("no subject")

    index = int(torch.argmax(scores))
    x0, y0, x1, y1 = (int(round(value)) for value in boxes[index].tolist())
    width, height = size
    x0 = min(max(x0, 0), width - 1)
    y0 = min(max(y0, 0), height - 1)
    x1 = min(max(x1, x0 + 1), width)
    y1 = min(max(y1, y0 + 1), height)
    return x0, y0, x1 - x0, y1 - y0


def tilt(image, box):
    """Degrees counterclockwise that square the product's straight edges, or 0.0."""
    left, top, width, height = box
    pad = max(width, height) // 20
    region = image.crop(
        (
            max(left - pad, 0),
            max(top - pad, 0),
            min(left + width + pad, image.width),
            min(top + height + pad, image.height),
        )
    )
    edges = feature.canny(color.rgb2gray(np.asarray(region)), sigma=2)
    segments = transform.probabilistic_hough_line(
        edges, threshold=10, line_length=max(min(width, height) // 4, 10), line_gap=3, rng=0
    )

    if not segments:
        return 0.0

    angles = np.array([axis_tilt(start, end) for start, end in segments])
    lengths = np.array([math.dist(start, end) for start, end in segments])
    order = np.argsort(angles)
    middle = np.searchsorted(np.cumsum(lengths[order]), lengths.sum() / 2)
    agree = np.abs(angles - angles[order][middle]) <= 3

    if lengths[agree].sum() < lengths.sum() / 2:
        return 0.0

    angle = float(np.average(angles[agree], weights=lengths[agree]))
    return round(angle, 1) if MIN_TILT <= abs(angle) <= MAX_TILT else 0.0


def inside_photo(size, angle, box):
    """True when at most 1% of the turned crop is fill from outside the original."""
    left, top, width, height = box
    mask = Image.new("L", size, 255).rotate(angle, expand=True, fillcolor=0)
    fill = mask.crop((left, top, left + width, top + height)).histogram()[0]
    return fill <= width * height / 100


def axis_tilt(start, end):
    (x0, y0), (x1, y1) = start, end
    return (math.degrees(math.atan2(y1 - y0, x1 - x0)) + 45) % 90 - 45


def save_crop(cropped, dest) -> None:
    if cropped.mode == "RGBA":
        white = Image.new("RGB", cropped.size, (255, 255, 255))
        white.paste(cropped, mask=cropped.getchannel("A"))
        cropped = white
    elif cropped.mode != "RGB":
        cropped = cropped.convert("RGB")

    cropped.save(dest, "PNG")


if __name__ == "__main__":
    main()

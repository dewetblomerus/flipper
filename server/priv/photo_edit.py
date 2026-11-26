import os
import json
import sys

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

from PIL import Image, ImageEnhance
import torch
from transformers import AutoModelForZeroShotObjectDetection, AutoProcessor

MODEL_ID = "IDEA-Research/grounding-dino-base"
MARGIN = 0.05
SCENE_AREA = 0.8
BRIGHTNESS = 1.2

_processor = None
_model = None


def main() -> None:
    source = sys.argv[1]
    dest = sys.argv[2]
    image = Image.open(source).convert("RGB")
    left, top, width, height = framing(image, sys.argv[3])
    save_crop(image.crop((left, top, left + width, top + height)), dest)
    json.dump({"left": left, "top": top, "width": width, "height": height}, sys.stdout)
    sys.stdout.write("\n")


def framing(image, title):
    """The subject crop of a camera photo. Any other shape is already cropped."""
    if not camera_shaped(image.size):
        return 0, 0, *image.size

    return crop_box(subject_box(image, phrase(title)), image.size)


def camera_shaped(size):
    short, long = sorted(size)
    return short * 4 == long * 3


def phrase(title: str) -> str:
    kept = [char.lower() if char.isalnum() or char in " '-" else " " for char in title]
    text = " ".join("".join(kept).split())

    if not text:
        sys.exit("no subject")

    return text


def subject_box(image, text):
    """The title's best match joined with each product match smaller than the scene."""
    titled = detections(image, text)
    boxes = [max(titled)[1]] if titled else []
    scene = SCENE_AREA * image.width * image.height
    boxes += [box for _score, box in detections(image, "product") if area(box) <= scene]

    if not boxes:
        sys.exit("no subject")

    return union(boxes)


def detections(image, text):
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

    return [
        (score, inside(box, image.size))
        for score, box in zip(result["scores"].tolist(), result["boxes"].tolist())
    ]


def detector():
    global _processor, _model

    if _model is None:
        _processor = AutoProcessor.from_pretrained(MODEL_ID)
        _model = AutoModelForZeroShotObjectDetection.from_pretrained(MODEL_ID)
        _model.eval()

    return _processor, _model


def inside(box, size):
    x0, y0, x1, y1 = (int(round(value)) for value in box)
    width, height = size
    x0 = min(max(x0, 0), width - 1)
    y0 = min(max(y0, 0), height - 1)
    x1 = min(max(x1, x0 + 1), width)
    y1 = min(max(y1, y0 + 1), height)
    return x0, y0, x1, y1


def area(box):
    x0, y0, x1, y1 = box
    return (x1 - x0) * (y1 - y0)


def union(boxes):
    lefts, tops, rights, bottoms = zip(*boxes)
    left, top = min(lefts), min(tops)
    return left, top, max(rights) - left, max(bottoms) - top


def crop_box(box, size):
    """The subject and its margin, grown toward a square inside the photo."""
    left, top, width, height = box
    pad = round(MARGIN * max(width, height))
    spans = [
        (max(left - pad, 0), min(left + width + pad, size[0])),
        (max(top - pad, 0), min(top + height + pad, size[1])),
    ]
    side = max(end - start for start, end in spans)
    (x, w), (y, h) = (grown(span, side, limit) for span, limit in zip(spans, size))
    return x, y, w, h


def grown(span, side, limit):
    """Origin and length of a span stretched toward side, within 0 to limit."""
    start, end = span
    length = min(side, limit)
    origin = start - (length - (end - start)) // 2
    return min(max(origin, 0), limit - length), length


def save_crop(cropped, dest) -> None:
    if cropped.mode == "RGBA":
        white = Image.new("RGB", cropped.size, (255, 255, 255))
        white.paste(cropped, mask=cropped.getchannel("A"))
        cropped = white
    elif cropped.mode != "RGB":
        cropped = cropped.convert("RGB")

    ImageEnhance.Brightness(cropped).enhance(BRIGHTNESS).save(dest, "PNG")


if __name__ == "__main__":
    main()

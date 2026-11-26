import os
import json
import sys

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

from PIL import Image
import torch
from transformers import AutoModelForZeroShotObjectDetection, AutoProcessor

MODEL_ID = "IDEA-Research/grounding-dino-base"
MARGIN = 0.05

_processor = None
_model = None


def main() -> None:
    source = sys.argv[1]
    dest = sys.argv[2]
    image = Image.open(source).convert("RGB")
    text = phrase(sys.argv[3])
    left, top, width, height = with_margin(product_box(image, text), image.size)
    save_crop(image.crop((left, top, left + width, top + height)), dest)
    json.dump({"left": left, "top": top, "width": width, "height": height}, sys.stdout)
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


def with_margin(box, size):
    left, top, width, height = box
    pad = round(MARGIN * (width + height) / 2)
    x0, y0 = max(left - pad, 0), max(top - pad, 0)
    x1, y1 = min(left + width + pad, size[0]), min(top + height + pad, size[1])
    return x0, y0, x1 - x0, y1 - y0


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

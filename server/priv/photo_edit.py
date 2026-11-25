import json
import sys

from PIL import Image
from rembg import remove


def main() -> None:
    source = sys.argv[1]
    dest = sys.argv[2]
    cut = remove(Image.open(source))
    box = cut.getchannel("A").getbbox()

    if box is None:
        sys.exit("no subject")

    left, top, right, bottom = box
    width = right - left
    height = bottom - top

    if width <= 0 or height <= 0:
        sys.exit("no subject")

    cut.crop(box).save(dest, "PNG")
    json.dump({"left": left, "top": top, "width": width, "height": height}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()

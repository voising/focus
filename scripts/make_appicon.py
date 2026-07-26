"""Turn the generated 1024px artwork into a macOS AppIcon asset catalog.

The source PNG comes from the app-factory image pipeline:

    cd ../app-factory && .venv/bin/python scripts/generate_image.py \
        --prompt-file ../focus/branding/logo-prompt.txt \
        --output ../focus/branding/icon-1024.png --size 1024x1024

Gemini returns a rounded square painted onto an opaque background, so this script
re-masks it to a clean superellipse-ish rounded rect with real transparency, then
downsamples to every size macOS asks for.

    python3 scripts/make_appicon.py branding/icon-1024-v2.png
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "focus" / "Assets.xcassets" / "AppIcon.appiconset"

# macOS corner radius is ~22.5% of the icon edge.
CORNER_RATIO = 0.2255

# (point size, scale) pairs macOS expects for an app icon.
VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

# Supersample before masking so the rounded corners stay smooth at 16px.
WORK_SIZE = 4096


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=radius, fill=255)
    return mask


def build(source_path: Path) -> None:
    source = Image.open(source_path).convert("RGB").resize((WORK_SIZE, WORK_SIZE), Image.LANCZOS)
    source.putalpha(rounded_mask(WORK_SIZE, int(WORK_SIZE * CORNER_RATIO)))

    ICONSET.mkdir(parents=True, exist_ok=True)
    images = []

    for point, scale in VARIANTS:
        pixels = point * scale
        filename = f"icon_{point}x{point}{'@2x' if scale == 2 else ''}.png"
        source.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / filename)
        images.append(
            {
                "size": f"{point}x{point}",
                "idiom": "mac",
                "filename": filename,
                "scale": f"{scale}x",
            }
        )
        print(f"  {filename:24} {pixels}x{pixels}")

    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"\nWrote {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "branding" / "icon-1024-v2.png"
    if not source.is_absolute():
        source = ROOT / source
    if not source.exists():
        sys.exit(f"Source artwork not found: {source}")
    print(f"Source: {source.relative_to(ROOT)}")
    build(source)

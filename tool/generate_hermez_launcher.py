"""Regenerate the debug-only Hermez Android launcher assets.

Requires Pillow. The source artwork is intentionally retained so every density
and the adaptive/themed icon can be rebuilt from the same mark.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "icons" / "hermez_launcher_source.png"
RES = ROOT / "android" / "app" / "src" / "debug" / "res"
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BACKGROUND = (23, 24, 28, 255)


def centered_mark(source: Image.Image, size: int, fraction: float) -> Image.Image:
    alpha = source.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("Hermez source mark is transparent")
    cropped = source.crop(bounds)
    scale = min(size * fraction / cropped.width, size * fraction / cropped.height)
    mark = cropped.resize(
        (round(cropped.width * scale), round(cropped.height * scale)),
        Image.Resampling.LANCZOS,
    )
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return layer


def legacy_icon(source: Image.Image, size: int) -> Image.Image:
    high = size * 4
    tile = Image.new("RGBA", (high, high), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle((0, 0, high - 1, high - 1), radius=round(high * 0.22), fill=BACKGROUND)
    tile.alpha_composite(centered_mark(source, high, 0.67))
    return tile.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    for density, legacy_size in SIZES.items():
        directory = RES / f"mipmap-{density}"
        adaptive_size = legacy_size * 108 // 48
        foreground = centered_mark(source, adaptive_size, 0.60)
        foreground.save(directory / "ic_launcher_foreground.png")
        Image.new("RGBA", (adaptive_size, adaptive_size), BACKGROUND).save(
            directory / "ic_launcher_background.png"
        )
        mono = Image.new("RGBA", foreground.size, (255, 255, 255, 0))
        mono.putalpha(foreground.getchannel("A"))
        mono.save(directory / "ic_launcher_monochrome.png")
        legacy_icon(source, legacy_size).save(directory / "ic_launcher.png")


if __name__ == "__main__":
    main()

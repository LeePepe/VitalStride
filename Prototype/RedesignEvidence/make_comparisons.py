"""Pair the native SwiftUI exports for the offline comparison gallery."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
STYLES = {"tide": "S1 Tide", "graphite": "S2 Graphite", "ember": "S3 Ember"}
LAYOUTS = {"flow": "L1 Flow", "focus": "L2 Focus", "board": "L3 Board"}
KEYBOARDS = {"grid": "K1 Full-width", "thumb": "K2 Thumb rail", "sequence": "K3 Log in sequence"}


def main():
    output = ROOT / "comparisons"
    output.mkdir(exist_ok=True)
    font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
    title_font = ImageFont.truetype(font_path, 26)
    detail_font = ImageFont.truetype(font_path, 15)
    for style, style_title in STYLES.items():
        for layout, layout_title in LAYOUTS.items():
            for mode in ("light", "dark"):
                board = Image.new("RGB", (826, 950), "#e7e8ea")
                draw = ImageDraw.Draw(board)
                draw.text((20, 14), f"{style_title} / {layout_title}", font=title_font, fill="#20242a")
                draw.text((20, 50), f"Exercise selection + Active workout  |  {mode}  |  DEMO DATA",
                          font=detail_font, fill="#555b65")
                for screen, x in (("picker", 14), ("workout", 419)):
                    source = ROOT / "shots" / f"{style}-{layout}-{screen}-{mode}.png"
                    with Image.open(source) as image:
                        board.paste(image.convert("RGB").resize((393, 852), Image.Resampling.LANCZOS), (x, 84))
                board.save(output / f"{style}-{layout}-{mode}.png")
    keyboard_output = ROOT / "keyboard-comparisons"
    keyboard_output.mkdir(exist_ok=True)
    for style, style_title in STYLES.items():
        for layout, layout_title in KEYBOARDS.items():
            for mode in ("light", "dark"):
                board = Image.new("RGB", (826, 950), "#e7e8ea")
                draw = ImageDraw.Draw(board)
                draw.text((20, 14), f"{style_title} / {layout_title}", font=title_font, fill="#20242a")
                draw.text((20, 50), f"Weight entry + Rep entry  |  {mode}  |  DEMO DATA",
                          font=detail_font, fill="#555b65")
                for field, x in (("weight", 14), ("reps", 419)):
                    source = ROOT / "keyboards" / f"{style}-keyboard-{layout}-{field}-{mode}.png"
                    with Image.open(source) as image:
                        board.paste(image.convert("RGB").resize((393, 852), Image.Resampling.LANCZOS), (x, 84))
                board.save(keyboard_output / f"{style}-{layout}-{mode}.png")
    print("Created 18 page comparison boards + 18 keyboard comparison boards")


if __name__ == "__main__":
    main()

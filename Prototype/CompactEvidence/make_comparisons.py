"""Compose actual SwiftUI exports; no screens are reconstructed here."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "comparisons"
OUT.mkdir(exist_ok=True)
STATES = ("normal", "keyboard", "rest", "undo", "keyboard-rest", "keyboard-undo")
LAYOUTS = (("table", "A / Current exercise"), ("rail", "B / Exercise rail"), ("matrix", "C / Plan matrix"))

for mode in ("light", "dark"):
    for state in STATES:
        board = Image.new("RGB", (1235, 918), "#e8eaed")
        draw = ImageDraw.Draw(board)
        draw.text((16, 8), f"VitalStride V2 / {state} / {mode} / Demo data / macOS ImageRenderer", fill="#1d232c")
        for index, (layout, title) in enumerate(LAYOUTS):
            x = 16 + index * 409
            draw.text((x, 32), title, fill="#1d232c")
            with Image.open(ROOT / "shots" / f"{layout}-{state}-{mode}.png") as screen:
                board.paste(screen.convert("RGB").resize((393, 852), Image.Resampling.LANCZOS), (x, 56))
        board.save(OUT / f"{state}-{mode}.png", optimize=True)

print("Composed 12 comparison boards from the 52 native screenshots")

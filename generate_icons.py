#!/usr/bin/env python3
"""Generate 吾爱破解 app icons (dark red rounded square, white 吾， red bar)
and write AppIcon.appiconset/Contents.json with explicit filenames so
actool actually compiles them into the app icon."""
import os
import json
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "WuAiPoJie", "Assets.xcassets", "AppIcon.appiconset")
DARK_RED = (127, 29, 29)
RED = (239, 68, 68)
WHITE = (255, 255, 255)

# "吾" needs a CJK font. macOS runners have PingFang; this VM has Noto CJK.
FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

def find_font():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    return None

def draw_icon(size):
    img = Image.new("RGB", (size, size), DARK_RED)
    d = ImageDraw.Draw(img)
    r = int(size * 0.225)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=DARK_RED)
    font_path = find_font()
    if font_path:
        try:
            font = ImageFont.truetype(font_path, int(size * 0.58))
            text = "吾"
            bbox = d.textbbox((0, 0), text, font=font)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            d.text(((size - tw) / 2 - bbox[0], (size - th) / 2 - bbox[1] - size * 0.04), text, font=font, fill=WHITE)
        except Exception as e:
            print("font draw failed:", e)
    bar_h = max(2, int(size * 0.055))
    bar_w = int(size * 0.42)
    y0 = int(size * 0.78)
    d.rounded_rectangle([(size - bar_w) / 2, y0, (size + bar_w) / 2, y0 + bar_h], radius=bar_h // 2, fill=RED)
    return img

SIZES = [1024, 180, 120, 87, 80, 60, 58, 40, 29, 20]
os.makedirs(OUT, exist_ok=True)
for s in SIZES:
    img = draw_icon(s)
    name = "icon-1024.png" if s == 1024 else f"icon-{s}.png"
    img.save(os.path.join(OUT, name))
    print("wrote", name)

# Write Contents.json with explicit filenames (actool ignores unreferenced files).
def entry(idiom, size, scale, px):
    return {"idiom": idiom, "size": size, "scale": scale,
            "filename": "icon-1024.png" if px == 1024 else f"icon-{px}.png"}

images = [
    entry("iphone", "20x20", "2x", 40),
    entry("iphone", "20x20", "3x", 60),
    entry("iphone", "29x29", "2x", 58),
    entry("iphone", "29x29", "3x", 87),
    entry("iphone", "40x40", "2x", 80),
    entry("iphone", "40x40", "3x", 120),
    entry("iphone", "60x60", "2x", 120),
    entry("iphone", "60x60", "3x", 180),
    entry("ipad", "20x20", "1x", 20),
    entry("ipad", "20x20", "2x", 40),
    entry("ipad", "29x29", "1x", 29),
    entry("ipad", "29x29", "2x", 58),
    entry("ipad", "40x40", "1x", 40),
    entry("ipad", "40x40", "2x", 80),
    entry("ipad", "76x76", "2x", 152),
    entry("ipad", "83.5x83.5", "2x", 167),
    entry("ios-marketing", "1024x1024", "1x", 1024),
]
# 152 and 167 are not in SIZES; draw them too so every entry has a file.
for px in (152, 167):
    img = draw_icon(px)
    img.save(os.path.join(OUT, f"icon-{px}.png"))
    print("wrote", f"icon-{px}.png")

contents = {"images": images, "info": {"author": "xcode", "version": 1}}
with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(contents, f, indent=2)
print("wrote Contents.json")
print("done")

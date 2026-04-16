#!/usr/bin/env python3
"""
GuardianPlay — Icon Generator
Generates the app icon (96x96 PNG) for Onion OS.

Requirements: Pillow (pip install Pillow)
Output: guardianplay.png (copy to /mnt/SDCARD/Icons/Default/app/)
"""

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Please install Pillow: pip install Pillow")
    exit(1)

import math
import os

SIZE = 96
OUT_FILE = os.path.join(os.path.dirname(__file__), "guardianplay.png")

# Colour palette
BG_COLOR       = (18, 22, 38, 255)      # Dark navy background
SHIELD_OUTER   = (90, 160, 255, 255)    # Blue shield
SHIELD_INNER   = (30, 50, 100, 255)     # Darker blue fill
CLOCK_BG       = (255, 255, 255, 220)   # Clock face
CLOCK_BORDER   = (255, 200, 50, 255)    # Gold clock ring
HAND_COLOR     = (30, 30, 60, 255)      # Dark clock hands
LOCK_COLOR     = (255, 220, 60, 255)    # Gold lock icon

img = Image.new("RGBA", (SIZE, SIZE), BG_COLOR)
draw = ImageDraw.Draw(img)

# ---- Rounded background ----
def rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.ellipse([x0, y0, x0 + 2*radius, y0 + 2*radius], fill=fill)
    draw.ellipse([x1 - 2*radius, y0, x1, y0 + 2*radius], fill=fill)
    draw.ellipse([x0, y1 - 2*radius, x0 + 2*radius, y1], fill=fill)
    draw.ellipse([x1 - 2*radius, y1 - 2*radius, x1, y1], fill=fill)

rounded_rect(draw, [2, 2, SIZE-2, SIZE-2], 14, (25, 32, 56, 255))

# ---- Shield shape ----
cx, cy = SIZE // 2, SIZE // 2

def shield_polygon(cx, cy, w, h):
    """Create shield polygon points."""
    pts = []
    # Top-left corner (rounded)
    pts.append((cx - w//2, cy - h//2))
    pts.append((cx + w//2, cy - h//2))
    pts.append((cx + w//2, cy))
    # Bottom point
    pts.append((cx, cy + h//2))
    pts.append((cx - w//2, cy))
    return pts

shield_pts = shield_polygon(cx, cy - 2, 56, 62)
draw.polygon(shield_pts, fill=SHIELD_OUTER)
# Inner shield (smaller, offset up)
inner_pts = shield_polygon(cx, cy - 2, 46, 52)
draw.polygon(inner_pts, fill=SHIELD_INNER)

# ---- Clock face (centered on shield) ----
clock_cx, clock_cy = cx, cy - 4
clock_r = 18

# Clock glow / border
draw.ellipse([clock_cx - clock_r - 3, clock_cy - clock_r - 3,
              clock_cx + clock_r + 3, clock_cy + clock_r + 3],
             fill=CLOCK_BORDER)
# Clock background
draw.ellipse([clock_cx - clock_r, clock_cy - clock_r,
              clock_cx + clock_r, clock_cy + clock_r],
             fill=CLOCK_BG)

# Clock tick marks (12 positions)
for i in range(12):
    angle = math.radians(i * 30 - 90)
    if i % 3 == 0:
        r_start, r_end, width = clock_r - 5, clock_r - 1, 2
    else:
        r_start, r_end, width = clock_r - 4, clock_r - 1, 1
    x0 = clock_cx + r_start * math.cos(angle)
    y0 = clock_cy + r_start * math.sin(angle)
    x1 = clock_cx + r_end * math.cos(angle)
    y1 = clock_cy + r_end * math.sin(angle)
    draw.line([(x0, y0), (x1, y1)], fill=(180, 180, 200, 255), width=width)

# Hour hand (pointing to ~10)
h_angle = math.radians(-60)
draw.line([
    (clock_cx, clock_cy),
    (clock_cx + 10 * math.cos(h_angle), clock_cy + 10 * math.sin(h_angle))
], fill=HAND_COLOR, width=3)

# Minute hand (pointing to ~2)
m_angle = math.radians(60)
draw.line([
    (clock_cx, clock_cy),
    (clock_cx + 14 * math.cos(m_angle), clock_cy + 14 * math.sin(m_angle))
], fill=HAND_COLOR, width=2)

# Center dot
draw.ellipse([clock_cx - 2, clock_cy - 2, clock_cx + 2, clock_cy + 2],
             fill=HAND_COLOR)

# ---- Small lock icon at bottom of shield ----
lx, ly = cx, cy + 26
# Lock body
draw.rounded_rectangle([lx - 7, ly - 5, lx + 7, ly + 7], radius=2,
                        fill=LOCK_COLOR)
# Lock shackle (arc)
draw.arc([lx - 5, ly - 13, lx + 5, ly - 3], start=200, end=340,
         fill=LOCK_COLOR, width=3)
# Keyhole
draw.ellipse([lx - 2, ly - 2, lx + 2, ly + 2], fill=SHIELD_INNER)

# ---- Apply slight vignette border ----
border = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
bd = ImageDraw.Draw(border)
bd.rounded_rectangle([0, 0, SIZE-1, SIZE-1], radius=14,
                      outline=(0, 0, 0, 120), width=2)
img = Image.alpha_composite(img, border)

# Save
img.save(OUT_FILE, "PNG")
print(f"Icon saved to: {OUT_FILE}")
print("Copy it to: /mnt/SDCARD/Icons/Default/app/guardianplay.png")

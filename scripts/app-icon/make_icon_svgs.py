#!/usr/bin/env python3
"""Writes the Pace Off app icon as three SVGs: light, dark and tinted.

The glyph is a pace gauge: a 250° dial whose far end warms into orange,
the "push" zone, with a tapered needle pointing into it. Pure geometry,
no SF Symbols (their licence rules them out of app icons).

Run from anywhere: python3 scripts/app-icon/make_icon_svgs.py
Then render with scripts/app-icon/render.sh.
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent
C = (512.0, 560.0)   # dial centre on the 1024 canvas
R = 290.0            # dial radius
STROKE = 92.0


def point(theta_deg: float, r: float = R) -> tuple[float, float]:
    t = math.radians(theta_deg)
    return (C[0] + r * math.cos(t), C[1] - r * math.sin(t))


start, end = point(215), point(-35)
ARC = f"M {start[0]:.1f} {start[1]:.1f} A {R:.0f} {R:.0f} 0 1 1 {end[0]:.1f} {end[1]:.1f}"

# Tapered needle at 38°, pointing into the warm end of the dial.
theta = math.radians(38)
LENGTH, BASE_HALF, TIP_HALF = 215.0, 34.0, 17.0
u = (math.cos(theta), -math.sin(theta))
n = (-u[1], u[0])
tip = (C[0] + u[0] * LENGTH, C[1] + u[1] * LENGTH)


def offset(p, k):
    return (p[0] + n[0] * k, p[1] + n[1] * k)


p1, p2, p3, p4 = offset(C, BASE_HALF), offset(tip, TIP_HALF), offset(tip, -TIP_HALF), offset(C, -BASE_HALF)
NEEDLE = (
    f"M {p1[0]:.1f} {p1[1]:.1f} L {p2[0]:.1f} {p2[1]:.1f} "
    f"A {TIP_HALF:.0f} {TIP_HALF:.0f} 0 0 0 {p3[0]:.1f} {p3[1]:.1f} "
    f"L {p4[0]:.1f} {p4[1]:.1f} Z"
)


def svg(*, background: bool, glyph: str, hub_dot: str, warm: bool, shadow: str) -> str:
    if warm:
        arc_stops = (
            f'<stop offset="0" stop-color="{glyph}"/><stop offset="0.5" stop-color="{glyph}"/>'
            '<stop offset="0.7" stop-color="#FFC04D"/><stop offset="0.86" stop-color="#FF8A2A"/>'
            '<stop offset="1" stop-color="#FF4F3A"/>'
        )
    else:
        arc_stops = f'<stop offset="0" stop-color="{glyph}"/><stop offset="1" stop-color="{glyph}"/>'
    ground = (
        '<rect width="1024" height="1024" fill="url(#bg)"/>'
        '<rect width="1024" height="1024" fill="url(#hl)"/>'
        if background else ""
    )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3D8BFF"/><stop offset="1" stop-color="#1640C9"/></linearGradient>
<radialGradient id="hl" cx="0.28" cy="0.12" r="0.85"><stop offset="0" stop-color="#fff" stop-opacity="0.2"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="{shadow}" flood-opacity="0.3"/></filter>
<linearGradient id="arc" gradientUnits="userSpaceOnUse" x1="222" y1="0" x2="802" y2="0">{arc_stops}</linearGradient>
</defs>
{ground}
<g filter="url(#sh)">
  <path d="{ARC}" fill="none" stroke="url(#arc)" stroke-width="{STROKE:.0f}" stroke-linecap="round"/>
  <path d="{NEEDLE}" fill="{glyph}"/>
  <circle cx="{C[0]:.0f}" cy="{C[1]:.0f}" r="64" fill="{glyph}"/>
  <circle cx="{C[0]:.0f}" cy="{C[1]:.0f}" r="22" fill="{hub_dot}"/>
</g>
</svg>
"""


# Light (default) appearance: opaque brand-blue ground, as App Store icons must be.
(OUT / "PaceOffIcon.svg").write_text(svg(background=True, glyph="#fff", hub_dot="#1F55DE", warm=True, shadow="#001a66"))
# Dark appearance: transparent ground; iOS draws the dark backdrop behind it.
(OUT / "PaceOffIcon-dark.svg").write_text(svg(background=False, glyph="#fff", hub_dot="#3D8BFF", warm=True, shadow="#000"))
# Tinted appearance: grayscale on transparent; iOS applies the user's tint.
(OUT / "PaceOffIcon-tinted.svg").write_text(svg(background=False, glyph="#fff", hub_dot="#808080", warm=False, shadow="#000"))
print("wrote", ", ".join(p.name for p in sorted(OUT.glob("PaceOffIcon*.svg"))))

#!/usr/bin/env python3
"""Writes Reclaim's app icon as SVG (Support/AppIcon.svg).

The mark is the Space Map: your disk as two rings of coloured slices, with one mint slice lifting
out of the ring, which is the space Reclaim gets back. Render it to Support/AppIcon.png with
Scripts/render_icon.py; build.sh turns that into the .icns file.
"""
import math, sys

S = 1024
X, Y, W = 100, 100, 824           # macOS icon grid: an 824 pt body centred on a 1024 canvas
CX, CY = 512, 512

def squircle(x=X, y=Y, w=W, n=5.0, steps=360):
    """Apple-style continuous-corner square, as a superellipse."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((x + w / 2 + abs(c) ** (2 / n) * (1 if c >= 0 else -1) * w / 2,
                    y + w / 2 + abs(s) ** (2 / n) * (1 if s >= 0 else -1) * w / 2))
    return "M" + " L".join(f"{a:.1f},{b:.1f}" for a, b in pts) + " Z"

def slice_path(r0, r1, a0, a1, dx=0.0, dy=0.0):
    """A ring slice from angle a0 to a1 (degrees, clockwise from 12 o'clock)."""
    t0, t1 = math.radians(a0 - 90), math.radians(a1 - 90)
    large = 1 if a1 - a0 > 180 else 0
    p = lambda r, t: (CX + dx + r * math.cos(t), CY + dy + r * math.sin(t))
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p(r1, t0), p(r1, t1), p(r0, t1), p(r0, t0)
    return (f"M{x0:.1f},{y0:.1f} A{r1},{r1} 0 {large} 1 {x1:.1f},{y1:.1f} "
            f"L{x2:.1f},{y2:.1f} A{r0},{r0} 0 {large} 0 {x3:.1f},{y3:.1f} Z")

def lift(a0, a1, distance):
    mid = math.radians((a0 + a1) / 2 - 90)
    return distance * math.cos(mid), distance * math.sin(mid)

INNER = (150, 268)     # the main ring
OUTER = (282, 322)     # the thinner ring of what's inside each slice
GAP = 2.2              # degrees between slices

inner = [  # start, end, gradient id
    (0, 146, "blue"), (146, 226, "violet"), (226, 282, "teal"),
]
outer = [  # start, end, colour, opacity
    (0, 86, "#7DB3FF", 0.75), (86, 124, "#7DB3FF", 0.55), (124, 146, "#7DB3FF", 0.38),
    (146, 196, "#B4A7FF", 0.7), (196, 226, "#B4A7FF", 0.45),
    (226, 262, "#6BDDEB", 0.7), (262, 282, "#6BDDEB", 0.45),
]
mint = (290, 352)
dx, dy = lift(*mint, 46)

def g(i, a0, a1):
    return f'<path d="{slice_path(*INNER, a0 + GAP / 2, a1 - GAP / 2)}" fill="url(#{i})"/>'

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <clipPath id="body"><path d="{squircle()}"/></clipPath>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1D3159"/>
      <stop offset="1" stop-color="#090F22"/>
    </linearGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#3D6FD0" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#3D6FD0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="blue" cx="{CX}" cy="{CY}" r="{INNER[1]}" gradientUnits="userSpaceOnUse">
      <stop offset="0.55" stop-color="#2F6FD6"/><stop offset="1" stop-color="#5A9BF5"/>
    </radialGradient>
    <radialGradient id="violet" cx="{CX}" cy="{CY}" r="{INNER[1]}" gradientUnits="userSpaceOnUse">
      <stop offset="0.55" stop-color="#6A55D8"/><stop offset="1" stop-color="#9B8BF7"/>
    </radialGradient>
    <radialGradient id="teal" cx="{CX}" cy="{CY}" r="{INNER[1]}" gradientUnits="userSpaceOnUse">
      <stop offset="0.55" stop-color="#1596AE"/><stop offset="1" stop-color="#45C8DC"/>
    </radialGradient>
    <radialGradient id="mint" cx="{CX + dx:.1f}" cy="{CY + dy:.1f}" r="{OUTER[1]}" gradientUnits="userSpaceOnUse">
      <stop offset="0.45" stop-color="#2FC79F"/><stop offset="1" stop-color="#9BFAE0"/>
    </radialGradient>
    <radialGradient id="hole" cx="0.5" cy="0.4" r="0.6">
      <stop offset="0" stop-color="#16264A"/><stop offset="1" stop-color="#0B142B"/>
    </radialGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.13"/>
      <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="22"/></filter>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="14"/>
      <feOffset dy="14"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.38"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="drop" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
      <feOffset dy="8"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <g filter="url(#shadow)">
    <path d="{squircle()}" fill="url(#tile)"/>
    <g clip-path="url(#body)">
      <circle cx="{CX}" cy="{CY}" r="400" fill="url(#halo)"/>
      <!-- outer ring: what's inside each slice -->
      {"".join(f'<path d="{slice_path(*OUTER, a0 + GAP / 2, a1 - GAP / 2)}" fill="{c}" fill-opacity="{o}"/>' for a0, a1, c, o in outer)}
      <!-- the empty place the mint slice lifted out of -->
      <path d="{slice_path(*INNER, mint[0] + GAP / 2, mint[1] - GAP / 2)}" fill="none" stroke="#5EE0C1" stroke-opacity="0.35" stroke-width="4" stroke-dasharray="14 12"/>
      <!-- main ring -->
      <g filter="url(#drop)">{"".join(g(i, a0, a1) for a0, a1, i in inner)}</g>
      <circle cx="{CX}" cy="{CY}" r="{INNER[0] - 6}" fill="url(#hole)"/>
      <!-- the mint slice, lifting out: space Reclaim gets back -->
      <path d="{slice_path(INNER[0], OUTER[1], mint[0] + GAP, mint[1] - GAP, dx, dy)}" fill="#5EE0C1" opacity="0.55" filter="url(#glow)"/>
      <path d="{slice_path(INNER[0], OUTER[1], mint[0] + GAP, mint[1] - GAP, dx, dy)}" fill="url(#mint)" filter="url(#drop)"/>
      <path d="{squircle()}" fill="url(#sheen)"/>
    </g>
    <path d="{squircle()}" fill="none" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="4"/>
  </g>
</svg>
'''
out = sys.argv[1] if len(sys.argv) > 1 else "Support/AppIcon.svg"
open(out, "w").write(svg)
print("wrote", out)

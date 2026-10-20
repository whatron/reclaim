#!/usr/bin/env python3
"""Writes Reclaim's app icon as SVG (Support/AppIcon.svg).

The icon is the app's tide gauge: a glass vessel of deep-blue water (your data) with a glowing
mint crest (what Reclaim can clear) and bubbles of freed space rising into the air above.
Render it with Scripts/render_icon.py to get Support/AppIcon.png, which build.sh turns into
the .icns file.
"""
import math, sys

S = 1024
X, Y, W = 100, 100, 824            # macOS icon grid: 824 pt body centred on a 1024 canvas
CX, CY = X + W / 2, Y + W / 2

def squircle(x, y, w, n=5.0, steps=360):
    """Apple-style continuous-corner square as a superellipse."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        px = abs(c) ** (2 / n) * (1 if c >= 0 else -1)
        py = abs(s) ** (2 / n) * (1 if s >= 0 else -1)
        pts.append((x + w / 2 + px * w / 2, y + w / 2 + py * w / 2))
    return "M" + " L".join(f"{a:.2f},{b:.2f}" for a, b in pts) + " Z"

def wave(level, amp, phase, cycles=1.15, bottom=None):
    """A filled wave whose surface sits at `level` (y), closed at the bottom of the icon."""
    bottom = bottom or Y + W + 10
    pts = []
    for i in range(121):
        u = i / 120
        x = X - 20 + (W + 40) * u
        y = level + amp * math.sin(u * 2 * math.pi * cycles + phase) \
            + amp * 0.35 * math.sin(u * 2 * math.pi * 2.3 - phase * 1.3)
        pts.append((x, y))
    d = f"M{pts[0][0]:.1f},{bottom} " + " ".join(f"L{a:.1f},{b:.1f}" for a, b in pts)
    return d + f" L{pts[-1][0]:.1f},{bottom} Z"

def wave_line(level, amp, phase, cycles=1.15):
    pts = []
    for i in range(121):
        u = i / 120
        x = X - 20 + (W + 40) * u
        y = level + amp * math.sin(u * 2 * math.pi * cycles + phase) \
            + amp * 0.35 * math.sin(u * 2 * math.pi * 2.3 - phase * 1.3)
        pts.append((x, y))
    return "M" + " L".join(f"{a:.1f},{b:.1f}" for a, b in pts)

body = squircle(X, Y, W)
surface = Y + W * 0.50
bubbles = [  # (x, y, r): rising and getting smaller, drifting right
    (CX + 70, surface - 92, 62),
    (CX + 182, surface - 238, 40),
    (CX + 118, surface - 352, 25),
]

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <clipPath id="body"><path d="{body}"/></clipPath>
    <linearGradient id="air" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#14305A"/>
      <stop offset="0.6" stop-color="#0C1F40"/>
      <stop offset="1" stop-color="#081631"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.68" cy="0.28" r="0.55">
      <stop offset="0" stop-color="#5EE0C1" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#5EE0C1" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2E7BD6"/>
      <stop offset="0.45" stop-color="#1A4F98"/>
      <stop offset="1" stop-color="#0B2753"/>
    </linearGradient>
    <linearGradient id="deep" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1F5FB0" stop-opacity="0.0"/>
      <stop offset="1" stop-color="#06173A" stop-opacity="0.85"/>
    </linearGradient>
    <linearGradient id="mint" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8FF5DC"/>
      <stop offset="1" stop-color="#3CC9A6"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="0.3" stop-color="#FFFFFF" stop-opacity="0.03"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#8FD0FF" stop-opacity="0.35"/>
    </linearGradient>
    <radialGradient id="bubble" cx="0.35" cy="0.3" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.65"/>
      <stop offset="0.45" stop-color="#8FF5DC" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#5EE0C1" stop-opacity="0.08"/>
    </radialGradient>
    <filter id="blur18" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="18"/></filter>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="14"/>
      <feOffset dy="14"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.38"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <g filter="url(#shadow)">
    <path d="{body}" fill="url(#air)"/>
    <g clip-path="url(#body)">
      <rect x="0" y="0" width="{S}" height="{S}" fill="url(#glow)"/>
      <!-- glow under the crest -->
      <path d="{wave(surface - 34, 28, 0.9)}" fill="#5EE0C1" opacity="0.6" filter="url(#blur18)"/>
      <!-- mint crest: what can be cleared -->
      <path d="{wave(surface - 46, 28, 0.9)}" fill="url(#mint)"/>
      <!-- the water: your data -->
      <path d="{wave(surface + 14, 24, 1.35)}" fill="url(#water)"/>
      <path d="{wave(surface + 150, 18, 2.4)}" fill="url(#deep)"/>
      <path d="{wave_line(surface + 16, 24, 1.35)}" fill="none" stroke="#A8E6FF" stroke-opacity="0.45" stroke-width="5"/>
      <!-- bubbles of freed space rising into the air -->
      {"".join(f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="{r}" fill="url(#bubble)" stroke="#9BF7E0" stroke-opacity="0.9" stroke-width="{max(3, r*0.16):.1f}"/>' for bx, by, r in bubbles)}
      {"".join(f'<circle cx="{bx - r*0.35:.1f}" cy="{by - r*0.38:.1f}" r="{r*0.18:.1f}" fill="#FFFFFF" fill-opacity="0.9"/>' for bx, by, r in bubbles)}
      <!-- glass -->
      <path d="{body}" fill="url(#sheen)"/>
    </g>
    <path d="{body}" fill="none" stroke="url(#rim)" stroke-width="5"/>
  </g>
</svg>
'''
out = sys.argv[1] if len(sys.argv) > 1 else "Support/AppIcon.svg"
open(out, "w").write(svg)
print("wrote", out)

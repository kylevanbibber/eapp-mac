#!/usr/bin/env python3
"""Build a small icon font for the Atlas eApp add-in toolbar.

Usage: make-icon-font.py <output.ttf>   (needs fontTools)

The add-in draws its six toolbar icons with the Windows font "Segoe MDL2
Assets". macOS and the engine do not have that font, so the icons show as
empty boxes. This script makes a font with the same family name and our own
drawings at the six code points the add-in uses. It has no Microsoft outlines.
"""
import math
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

W = 70  # stroke width, in 1000 units per em


def cw(pts):
    area = sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]))
    return pts if area < 0 else pts[::-1]


def circle(cx, cy, r, n=24):
    return cw([(round(cx + r * math.cos(2 * math.pi * i / n)), round(cy + r * math.sin(2 * math.pi * i / n))) for i in range(n)])


def seg(a, b, w=W):
    (x1, y1), (x2, y2) = a, b
    d = math.hypot(x2 - x1, y2 - y1)
    nx, ny = -(y2 - y1) / d * w / 2, (x2 - x1) / d * w / 2
    return cw([(round(x1 + nx), round(y1 + ny)), (round(x2 + nx), round(y2 + ny)),
               (round(x2 - nx), round(y2 - ny)), (round(x1 - nx), round(y1 - ny))])


def stroke(pts, closed=False, w=W):
    out = []
    pairs = list(zip(pts, pts[1:])) + ([(pts[-1], pts[0])] if closed else [])
    for a, b in pairs:
        out.append(seg(a, b, w))
    for p in pts:
        out.append(circle(p[0], p[1], w / 2, 12))
    return out


def rect(x1, y1, x2, y2):
    return [cw([(x1, y1), (x2, y1), (x2, y2), (x1, y2)])]


def arc(cx, cy, r, a0, a1, n=14):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


GLYPHS = {
    0xE710: stroke([(120, 500), (880, 500)]) + stroke([(500, 120), (500, 880)]),                       # Add
    0xE768: stroke([(290, 140), (290, 860), (850, 500)], closed=True),                                  # Play
    0xE74E: stroke([(130, 130), (870, 130), (870, 720), (720, 870), (130, 870)], closed=True)           # Save
            + stroke([(330, 870), (330, 640), (670, 640), (670, 870)])
            + stroke([(300, 130), (300, 420), (700, 420), (700, 130)]),
    0xE897: stroke(arc(500, 670, 190, 170, -50) + [(500, 430), (500, 330)], w=80)                       # Help
            + [circle(500, 150, 58)],
    0xE71D: [c for y in (250, 500, 750) for c in ([circle(160, y, 52)] + stroke([(340, y), (880, y)]))],  # AllApps
    0xE71A: rect(190, 190, 810, 810),                                                                   # Stop
}

names = [".notdef"] + ["uni%04X" % cp for cp in GLYPHS]
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder(names)
fb.setupCharacterMap({cp: "uni%04X" % cp for cp in GLYPHS})
glyphs = {".notdef": TTGlyphPen(None).glyph()}
for cp, contours in GLYPHS.items():
    pen = TTGlyphPen(None)
    for c in contours:
        pen.moveTo(c[0])
        for p in c[1:]:
            pen.lineTo(p)
        pen.closePath()
    glyphs["uni%04X" % cp] = pen.glyph()
fb.setupGlyf(glyphs)
fb.setupHorizontalMetrics({n: (1000, 0) for n in names})
fb.setupHorizontalHeader(ascent=1000, descent=0)
fb.setupNameTable({"familyName": "Segoe MDL2 Assets", "styleName": "Regular",
                   "uniqueFontIdentifier": "Atlas eApp toolbar icons 1.0",
                   "fullName": "Segoe MDL2 Assets", "psName": "SegoeMDL2Assets",
                   "version": "Version 1.0"})
fb.setupOS2(sTypoAscender=1000, sTypoDescender=0, usWinAscent=1000, usWinDescent=0)
fb.setupPost()
fb.save(sys.argv[1])

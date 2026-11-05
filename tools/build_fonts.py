"""Belarusian versions of Forever's own decorative fonts (MORPHEUS_CYR / SKURRI_CYR lack і, ў).

    python tools/build_fonts.py    -> addon/WoWBY/Fonts/MORPHEUS_BY.ttf, SKURRI_BY.ttf, FRIZQT_BY.ttf

Sources: ext/beta-fonts/enUS_*_cyr.ttf (extracted from the beta client; see CLAUDE.md).
- і / І : cmap-mapped to the font's own Latin i / I (visually identical).
- ў / Ў : new glyphs = у / У + the breve lifted from й / Й (the contours of й above и's height),
          centred over у. The fonts have no standalone breve glyph."""
import copy, os
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "ext", "beta-fonts")
OUT = os.path.join(ROOT, "addon", "WoWBY", "Fonts")
JOBS = [("enUS_morpheus_cyr.ttf", "MORPHEUS_BY.ttf"), ("enUS_skurri_cyr.ttf", "SKURRI_BY.ttf"),
        ("enUS_frizqt___cyr.ttf", "FRIZQT_BY.ttf")]   # Friz already has і / ў: renamed copy (was ClassicUA's font)


def contours(font, gname):
    """Decomposed glyph -> list of contours (each a list of recorded pen ops)."""
    gs = font.getGlyphSet()
    rec = DecomposingRecordingPen(gs)
    gs[gname].draw(rec)
    out, cur = [], []
    for op, args in rec.value:
        cur.append((op, args))
        if op in ("closePath", "endPath"):
            out.append(cur); cur = []
    return out


def bounds(font, ops_list):
    bp = BoundsPen(font.getGlyphSet())
    for c in ops_list:
        for op, args in c:
            getattr(bp, op)(*args)
    return bp.bounds


def add_breve_glyph(font, base, with_breve, plain, new_name, cp):
    """new glyph = contours(base) + (contours(with_breve) above plain's top), breve centred over base."""
    cmap = font.getBestCmap()
    gb, gw, gp = cmap[base], cmap[with_breve], cmap[plain]
    top = bounds(font, contours(font, gp))[3]
    breve = [c for c in contours(font, gw) if bounds(font, [c])[1] > top * 0.9]
    if not breve:
        raise RuntimeError("no breve contours in %s" % gw)
    bx = bounds(font, breve); ux = bounds(font, contours(font, gb))
    dx = ((ux[0] + ux[2]) - (bx[0] + bx[2])) / 2.0
    pen = TTGlyphPen(font.getGlyphSet())
    tp = TransformPen(pen, (1, 0, 0, 1, 0, 0))
    for c in contours(font, gb):
        for op, args in c: getattr(tp, op)(*args)
    tb = TransformPen(pen, (1, 0, 0, 1, dx, 0))
    for c in breve:
        for op, args in c: getattr(tb, op)(*args)
    font["glyf"][new_name] = pen.glyph()
    font["hmtx"].metrics[new_name] = font["hmtx"].metrics[gb]
    order = font.getGlyphOrder()
    if new_name not in order:
        font.setGlyphOrder(order + [new_name])
    for t in font["cmap"].tables:
        if t.isUnicode():
            t.cmap[cp] = new_name


def main():
    os.makedirs(OUT, exist_ok=True)
    for src, dst in JOBS:
        f = TTFont(os.path.join(SRC, src))
        cmap = f.getBestCmap()
        if 0x456 not in cmap:
            for t in f["cmap"].tables:                  # і І -> Latin i I
                if t.isUnicode():
                    t.cmap[0x456] = cmap[0x69]; t.cmap[0x406] = cmap[0x49]
        if 0x45E not in cmap:
            add_breve_glyph(f, 0x443, 0x439, 0x438, "uni045E", 0x45E)   # ў = у + breve(й over и)
            add_breve_glyph(f, 0x423, 0x419, 0x418, "uni040E", 0x40E)   # Ў = У + breve(Й over И)
        if "maxp" in f: f["maxp"].numGlyphs = len(f.getGlyphOrder())
        # rename so it never collides with the client's own font
        for rec in f["name"].names:
            if rec.nameID in (1, 3, 4, 6):
                try:
                    rec.string = (rec.toUnicode() + " BY")[:63]
                except Exception:
                    pass
        out = os.path.join(OUT, dst)
        f.save(out)
        chk = TTFont(out).getBestCmap()
        print("%s: і=%s ў=%s Ў=%s (%d KB)" % (dst, 0x456 in chk, 0x45E in chk, 0x40E in chk, os.path.getsize(out) // 1024))


if __name__ == "__main__":
    main()

"""The wordmark as a candidate: THR from Archivo ExtraBold's own outlines, the Ø as the mark with the
proportions the wordmark gives it (a heavier ring than the standalone mark). NOT shipped until the
founder confirms the face — see README.md.

Measured against the founder's 2000 px wordmark, in units of the cap height C: letters set at C with
0.10 C between inked edges; ring outer radius 0.53 C, inner 0.30 C, centred on the cap midline; dart
half-width 0.067 C, full width to the ring's outer edge, tapering to points 0.95 C from the centre at 45°.

Usage:
  python3 docs/design/brand/render_wordmark.py <repo root>            # previews + SVG into candidates/
  python3 docs/design/brand/render_wordmark.py <repo root> --launch   # ALSO write the composed launch
                                                                       # image (mark above wordmark) as
                                                                       # LaunchMark.pdf — founder-approved only
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ttf_outlines import TTF, quad_segments, contour_to_pdf, rasterise, write_png
from render_mark import R_OUT, R_IN, HALF_W, TIP, GREEN, CHALK, INK, hexagon, circle_path

FACE = "apps/ios/ThroDarts/Fonts/Archivo-ExtraBold.ttf"
GAP, RING_OUT, RING_IN, BAR, TIPS = 0.10, 0.53, 0.30, 0.067, 0.95
K = math.sqrt(0.5)

def wordmark_geometry(font, C):
    """Letters as font contours with placement, and the Ø's circles and dart, in a y-up frame with the
    baseline at y=0 and the first letter's ink starting at x=0. Returns (letters, ring, dart, width, top, bottom)."""
    f = TTF(font); scale = C / f.cap_height
    letters = []; pen = 0.0
    for ch in "THR":
        gid = f.cmap[ord(ch)]; cs = f.contours(gid)
        xs = [x for c in cs for x, _, _ in c]
        x0 = pen - min(xs) * scale
        letters.append((x0, scale, cs))
        pen += (max(xs) - min(xs)) * scale + GAP * C
    cx, cy = pen + RING_OUT * C, C / 2
    L, R, w = TIPS * C, RING_OUT * C, BAR * C
    local = [(L, 0), (R, w), (-R, w), (-L, 0), (-R, -w), (R, -w)]
    dart = [(cx + u * K - v * K, cy + u * K + v * K) for u, v in local]
    width = cx + TIPS * C * K
    return letters, (cx, cy, RING_OUT * C, RING_IN * C), dart, width, cy + TIPS * C * K, cy - TIPS * C * K

def polys_for(letters, ring, dart, tx):
    polys = []
    for x0, scale, cs in letters:
        for c in cs:
            polys.append([tx(x0 + x * scale, y * scale) for x, y in quad_segments(c)])
    cx, cy, ro, ri = ring
    n = 240
    outer = [tx(cx + ro * math.cos(2 * math.pi * i / n), cy + ro * math.sin(2 * math.pi * i / n)) for i in range(n)]
    inner = [tx(cx + ri * math.cos(2 * math.pi * i / n), cy + ri * math.sin(2 * math.pi * i / n)) for i in range(n)]
    # Nonzero winding: the outer ring and the dart must wind the same way, the inner ring the other way.
    polys.append(orient(outer, +1)); polys.append(orient(inner, -1)); polys.append(orient([tx(*p) for p in dart], +1))
    return polys

def orient(poly, sign):
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
    return poly if (area > 0) == (sign > 0) else poly[::-1]

def render_candidate_png(path, font, C, fg, bg):
    letters, ring, dart, width, top, bottom = wordmark_geometry(font, C)
    pad = 0.15 * C
    W, H = int(width + 2 * pad), int(top - bottom + 2 * pad)
    tx = lambda x, y: (x + pad, top + pad - y)          # y down for pixels
    cov = rasterise(polys_for(letters, ring, dart, tx), W, H, ss=3)
    rows = [bytes(int(round(b * (1 - v / 255) + f * v / 255)) for v in r for b, f in zip(bg, fg)) for r in cov]
    write_png(path, rows, W, H)

def wordmark_svg(path, font, C, fg):
    letters, ring, dart, width, top, bottom = wordmark_geometry(font, C)
    col = "#%02X%02X%02X" % fg
    def tx(x, y): return (x, top - y)
    d = []
    for x0, scale, cs in letters:
        for c in cs:
            pts = quad_segments(c, steps=6)
            d.append("M" + " L".join(f"{x0 + x*scale:.2f},{top - y*scale:.2f}" for x, y in pts) + " Z")
    cx, cy, ro, ri = ring
    pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in (tx(*p) for p in dart))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {top - bottom:.0f}" width="{width:.0f}" height="{top - bottom:.0f}">\n'
           f'  <!-- THRØ wordmark CANDIDATE: THR from Archivo ExtraBold outlines; Ø from the mark geometry at the wordmark\'s proportions. Not confirmed by the founder. -->\n'
           f'  <path d="{" ".join(d)}" fill="{col}" fill-rule="nonzero"/>\n'
           f'  <circle cx="{cx:.2f}" cy="{top - cy:.2f}" r="{(ro + ri)/2:.2f}" fill="none" stroke="{col}" stroke-width="{ro - ri:.2f}"/>\n'
           f'  <polygon points="{pts}" fill="{col}"/>\n</svg>\n')
    open(path, "w").write(svg)

def splash_preview_png(path, font):
    """A 390 x 844 point screen at 2x: the Splash's green field, the chalk mark 104 wide, 28 below it the chalk
    wordmark 150 wide, the group centred. The tagline and the buttons of the Splash are not launch-screen content."""
    S = 2; W, H = 390 * S, 844 * S
    mark_w = 104 * S; gap = 28 * S; word_w = 150 * S
    # wordmark cap height from its width: width = f(C) is linear in C, so solve with a unit run
    _, _, _, unit_w, unit_top, unit_bottom = wordmark_geometry(font, 100.0)
    C = word_w * 100.0 / unit_w
    letters, ring, dart, width, top, bottom = wordmark_geometry(font, C)
    word_h = top - bottom
    total_h = mark_w + gap + word_h
    y0 = (H - total_h) / 2
    polys = []
    # the mark, tips spanning mark_w, centred horizontally
    scale = mark_w / (2 * TIP); mcx, mcy = W / 2, y0 + mark_w / 2
    n = 240
    ro, ri = R_OUT * scale, R_IN * scale
    polys.append(orient([(mcx + ro * math.cos(2*math.pi*i/n), mcy + ro * math.sin(2*math.pi*i/n)) for i in range(n)], +1))
    polys.append(orient([(mcx + ri * math.cos(2*math.pi*i/n), mcy + ri * math.sin(2*math.pi*i/n)) for i in range(n)], -1))
    polys.append(orient([(mcx + x, mcy - y) for x, y in hexagon(scale)], +1))
    # the wordmark below
    wx = (W - width) / 2; wy = y0 + mark_w + gap
    tx = lambda x, y: (wx + x, wy + top - y)
    polys += polys_for(letters, ring, dart, tx)
    cov = rasterise(polys, W, H, ss=2)
    rows = [bytes(int(round(b * (1 - v / 255) + f * v / 255)) for v in r for b, f in zip(GREEN, CHALK)) for r in cov]
    write_png(path, rows, W, H)

def composed_launch_pdf(path, font):
    """Vector launch image: the mark 104 wide, the wordmark 150 wide 28 below, chalk, in a 150 x (104+28+h) box."""
    mark_w, gap, word_w = 104.0, 28.0, 150.0
    _, _, _, unit_w, unit_top, unit_bottom = wordmark_geometry(font, 100.0)
    C = word_w * 100.0 / unit_w
    letters, ring, dart, width, top, bottom = wordmark_geometry(font, C)
    word_h = top - bottom
    box_w, box_h = word_w, mark_w + gap + word_h
    r, g, b = (c / 255 for c in CHALK)
    content = f"{r:.4f} {g:.4f} {b:.4f} rg\n"
    # mark (PDF y up): centred at top of the box
    scale = mark_w / (2 * TIP); mcx, mcy = box_w / 2, box_h - mark_w / 2
    content += circle_path(mcx, mcy, R_OUT * scale) + circle_path(mcx, mcy, R_IN * scale) + "f*\n"
    content += " ".join(f"{mcx + x:.3f} {mcy + y:.3f} {'m' if i == 0 else 'l'}" for i, (x, y) in enumerate(hexagon(scale))) + " h f\n"
    # wordmark: baseline sits so that its bottom tip is at y=0
    wx = (box_w - width) / 2; base_y = -bottom
    for x0, s, cs in letters:
        for c in cs:
            content += contour_to_pdf(c, lambda x, y, x0=x0, s=s: (wx + x0 + x * s, base_y + y * s)) + "\n"
    content += "f\n"
    cx, cy, ro, ri = ring
    content += circle_path(wx + cx, base_y + cy, ro) + circle_path(wx + cx, base_y + cy, ri) + "f*\n"
    content += " ".join(f"{wx + x:.3f} {base_y + y:.3f} {'m' if i == 0 else 'l'}" for i, (x, y) in enumerate(dart)) + " h f\n"
    content = content.encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {box_w:.2f} {box_h:.2f}] /Contents 4 0 R /Resources << >> >>".encode(),
            b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream"]
    out = b"%PDF-1.4\n"; offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out)); out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode()
    for off in offsets: out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    open(path, "wb").write(out)

if __name__ == "__main__":
    root = sys.argv[1]; font = os.path.join(root, FACE)
    cand = os.path.join(root, "docs/design/brand/candidates"); os.makedirs(cand, exist_ok=True)
    render_candidate_png(os.path.join(cand, "wordmark-archivo-extrabold.png"), font, 300.0, INK, (255, 255, 255))
    wordmark_svg(os.path.join(cand, "wordmark-archivo-extrabold.svg"), font, 300.0, GREEN)
    splash_preview_png(os.path.join(cand, "splash-preview.png"), font)
    print("candidate wordmark and splash preview written to", cand)
    if "--launch" in sys.argv:
        composed_launch_pdf(os.path.join(root, "apps/ios/ThroDarts/Assets.xcassets/LaunchMark.imageset/LaunchMark.pdf"), font)
        print("LaunchMark.pdf replaced by the composed mark + wordmark")

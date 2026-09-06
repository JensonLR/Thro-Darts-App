"""The THRØ mark as geometry, from the founder's supplied artwork (2026-09-06): a ring with a dart
through it at 45 degrees, lower-left to upper-right, both ends drawn to a point beyond the ring.

Proportions were measured from the supplied 1250 px mark and are expressed against that frame (W):
ring outer radius 0.364 W, inner radius 0.250 W (stroke 0.114 W); dart half-width 0.040 W inside the
ring; the dart keeps its width to the ring's outer edge and tapers to a point 0.643 W from the centre.
"""
import math, struct, zlib, json, sys, os

R_OUT, R_IN, HALF_W, TIP = 0.364, 0.250, 0.040, 0.643
GREEN = (0x0F, 0x3D, 0x2E)   # --thro-green
CHALK = (0xF7, 0xF6, 0xF2)   # --thro-chalk
INK   = (0x10, 0x12, 0x11)   # --thro-ink
COS45 = math.sqrt(0.5)

def hexagon(scale):
    """Dart outline in the mark's frame (centre 0,0; y up), in units of `scale` (= W in pixels)."""
    L, R, w = TIP*scale, R_OUT*scale, HALF_W*scale
    local = [(L, 0), (R, w), (-R, w), (-L, 0), (-R, -w), (R, -w)]
    # rotate +45°: the axis runs lower-left → upper-right
    return [(u*COS45 - v*COS45, u*COS45 + v*COS45) for u, v in local]

def sdf_hexagon(px, py, verts):
    # signed distance to a convex polygon: max over edges of the half-plane distance (exact inside,
    # within a fraction of a pixel outside near the vertices, which is enough for coverage)
    best = -1e9
    n = len(verts)
    for i in range(n):
        x0, y0 = verts[i]; x1, y1 = verts[(i+1) % n]
        ex, ey = x1-x0, y1-y0
        ln = math.hypot(ex, ey)
        # outward normal for a counter-clockwise polygon is (ey, -ex)
        d = ((px-x0)*ey - (py-y0)*ex) / ln
        if d > best: best = d
    return best

def render_png(path, size, scale, bg, fg):
    cx = cy = size/2
    verts = hexagon(scale)
    # ensure counter-clockwise (positive area) for the normal convention above
    area = sum(verts[i][0]*verts[(i+1)%6][1] - verts[(i+1)%6][0]*verts[i][1] for i in range(6))
    if area < 0: verts = verts[::-1]
    Ro, Ri = R_OUT*scale, R_IN*scale
    mid, half = (Ro+Ri)/2, (Ro-Ri)/2
    rows = []
    for j in range(size):
        py = cy - (j + 0.5)          # y up
        row = bytearray([0])
        for i in range(size):
            px = (i + 0.5) - cx
            d_ring = abs(math.hypot(px, py) - mid) - half
            d = min(d_ring, sdf_hexagon(px, py, verts))
            a = min(1.0, max(0.0, 0.5 - d))   # coverage from signed distance in pixels
            row += bytes(int(round(b*(1-a) + f*a)) for b, f in zip(bg, fg))
        rows.append(bytes(row))
    raw = b"".join(rows)
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)

def circle_path(cx, cy, r, reverse=False):
    k = 0.5522847498 * r
    pts = [(cx+r, cy), (cx+r, cy+k, cx+k, cy+r, cx, cy+r), (cx-k, cy+r, cx-r, cy+k, cx-r, cy),
           (cx-r, cy-k, cx-k, cy-r, cx, cy-r), (cx+k, cy-r, cx+r, cy-k, cx+r, cy)]
    s = f"{pts[0][0]:.3f} {pts[0][1]:.3f} m\n"
    for c in pts[1:]:
        s += " ".join(f"{v:.3f}" for v in c) + " c\n"
    return s + "h\n"

def render_pdf(path, box, scale, fg):
    cx = cy = box/2
    r, g, b = (c/255 for c in fg)
    verts = hexagon(scale)
    content = f"{r:.4f} {g:.4f} {b:.4f} rg\n"
    content += circle_path(cx, cy, R_OUT*scale) + circle_path(cx, cy, R_IN*scale) + "f*\n"
    content += " ".join(f"{cx+x:.3f} {cy+y:.3f} {'m' if i == 0 else 'l'}" for i, (x, y) in enumerate(verts)) + " h f\n"
    content = content.encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {box} {box}] /Contents 4 0 R /Resources << >> >>".encode(),
            b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream"]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode()
    for off in offsets: out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    open(path, 'wb').write(out)

def render_svg(path, box, scale, fg):
    cx = cy = box/2
    verts = hexagon(scale)
    ring_r, ring_w = (R_OUT+R_IN)/2*scale, (R_OUT-R_IN)*scale
    col = "#%02X%02X%02X" % fg
    pts = " ".join(f"{cx+x:.2f},{cy-y:.2f}" for x, y in verts)   # SVG y is down
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {box} {box}" width="{box}" height="{box}">\n'
           f'  <!-- THRØ mark: ring and dart, reconstructed from the founder\'s artwork; see README.md -->\n'
           f'  <circle cx="{cx}" cy="{cy}" r="{ring_r:.2f}" fill="none" stroke="{col}" stroke-width="{ring_w:.2f}"/>\n'
           f'  <polygon points="{pts}" fill="{col}"/>\n</svg>\n')
    open(path, 'w').write(svg)

if __name__ == "__main__":
    root = sys.argv[1]
    # The export's Splash screen (screens-account.jsx) is the one composition the design gives the
    # mark: a --thro-green field with the chalk mark, 104 wide. The icon and the launch screen follow it.
    icon = os.path.join(root, "apps/ios/ThroDarts/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    # Icon: 1024 px; the tips reach 0.46 of the canvas from the centre, clear of the corner mask.
    render_png(icon, 1024, 0.46*1024/TIP, GREEN, CHALK)
    launch = os.path.join(root, "apps/ios/ThroDarts/Assets.xcassets/LaunchMark.imageset")
    # Launch mark: a 104-point box the mark fills tip to tip, as the splash draws it.
    render_pdf(os.path.join(launch, "LaunchMark.pdf"), 104, 104/(2*TIP), CHALK)
    brand = os.path.join(root, "docs/design/brand")
    render_svg(os.path.join(brand, "thro-mark-green.svg"), 1000, 1000/(2*TIP)*0.92, GREEN)
    render_svg(os.path.join(brand, "thro-mark-chalk.svg"), 1000, 1000/(2*TIP)*0.92, CHALK)
    print("rendered icon, launch mark and reference svgs")

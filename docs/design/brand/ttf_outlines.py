"""Minimal TrueType outline reader and rasteriser, pure Python, no dependencies.

Reads glyph outlines (simple and composite glyphs, format-4 cmap, advances), flattens the quadratic
contours to polylines, writes them as PDF path operators, fills polylines with the nonzero rule at a
supersampled resolution, and writes RGB PNGs. Enough to draw a wordmark from the embedded faces and to
look at it; not a text engine (no kerning, no shaping)."""
import struct, zlib, math, sys

class TTF:
    def __init__(self, path):
        d = self.d = open(path, 'rb').read()
        n = struct.unpack('>H', d[4:6])[0]
        self.tables = {}
        for i in range(n):
            o = 12 + 16*i
            self.tables[d[o:o+4].decode('latin1')] = struct.unpack('>II', d[o+8:o+16])
        head = self.tables['head'][0]
        self.upem = struct.unpack('>H', d[head+18:head+20])[0]
        self.locfmt = struct.unpack('>h', d[head+50:head+52])[0]
        maxp = self.tables['maxp'][0]
        self.nglyphs = struct.unpack('>H', d[maxp+4:maxp+6])[0]
        hhea = self.tables['hhea'][0]
        self.nhm = struct.unpack('>H', d[hhea+34:hhea+36])[0]
        self.ascender, self.descender = struct.unpack('>hh', d[hhea+4:hhea+8])
        os2 = self.tables.get('OS/2')
        self.cap_height = struct.unpack('>h', d[os2[0]+88:os2[0]+90])[0] if os2 and os2[1] >= 90 else None
        self._cmap()
    def _cmap(self):
        d = self.d; base = self.tables['cmap'][0]
        n = struct.unpack('>H', d[base+2:base+4])[0]
        self.cmap = {}
        for i in range(n):
            pid, eid, off = struct.unpack('>HHI', d[base+4+8*i:base+12+8*i])
            sub = base + off
            fmt = struct.unpack('>H', d[sub:sub+2])[0]
            if fmt == 4 and pid == 3 and eid in (1, 10):
                segx2 = struct.unpack('>H', d[sub+6:sub+8])[0]; seg = segx2//2
                ends = struct.unpack(f'>{seg}H', d[sub+14:sub+14+segx2])
                starts = struct.unpack(f'>{seg}H', d[sub+16+segx2:sub+16+2*segx2])
                deltas = struct.unpack(f'>{seg}h', d[sub+16+2*segx2:sub+16+3*segx2])
                rng_off_pos = sub+16+3*segx2
                rngs = struct.unpack(f'>{seg}H', d[rng_off_pos:rng_off_pos+segx2])
                for s in range(seg):
                    for c in range(starts[s], min(ends[s], 0xFFFE)+1):
                        if rngs[s] == 0:
                            g = (c + deltas[s]) & 0xFFFF
                        else:
                            gp = rng_off_pos + 2*s + rngs[s] + 2*(c - starts[s])
                            g = struct.unpack('>H', d[gp:gp+2])[0]
                            if g: g = (g + deltas[s]) & 0xFFFF
                        if g: self.cmap[c] = g
                return
        raise ValueError("no format-4 cmap")
    def advance(self, gid):
        hmtx = self.tables['hmtx'][0]
        i = min(gid, self.nhm-1)
        return struct.unpack('>H', self.d[hmtx+4*i:hmtx+4*i+2])[0]
    def _loc(self, gid):
        loca = self.tables['loca'][0]
        if self.locfmt == 0:
            a, b = struct.unpack('>HH', self.d[loca+2*gid:loca+2*gid+4]); return a*2, b*2
        return struct.unpack('>II', self.d[loca+4*gid:loca+4*gid+8])
    def contours(self, gid, dx=0, dy=0):
        """List of contours; each a list of (x, y, on_curve) in font units."""
        a, b = self._loc(gid)
        if b <= a: return []
        g = self.tables['glyf'][0] + a; d = self.d
        nc = struct.unpack('>h', d[g:g+2])[0]
        if nc < 0:
            out = []; p = g + 10
            while True:
                flags, gi = struct.unpack('>HH', d[p:p+4]); p += 4
                if flags & 1: a1, a2 = struct.unpack('>hh', d[p:p+4]); p += 4
                else: a1, a2 = struct.unpack('>bb', d[p:p+2]); p += 2
                if flags & 8: p += 2
                elif flags & 0x40: p += 4
                elif flags & 0x80: p += 8
                out += self.contours(gi, dx + a1, dy + a2)
                if not flags & 0x20: break
            return out
        p = g + 10
        ends = struct.unpack(f'>{nc}H', d[p:p+2*nc]); p += 2*nc
        npts = ends[-1] + 1
        il = struct.unpack('>H', d[p:p+2])[0]; p += 2 + il
        flags = []
        while len(flags) < npts:
            f = d[p]; p += 1; flags.append(f)
            if f & 8:
                r = d[p]; p += 1; flags += [f]*r
        xs = []; v = 0
        for f in flags:
            if f & 2:
                dxv = d[p]; p += 1; v += dxv if f & 16 else -dxv
            elif not f & 16:
                v += struct.unpack('>h', d[p:p+2])[0]; p += 2
            xs.append(v)
        ys = []; v = 0
        for f in flags:
            if f & 4:
                dyv = d[p]; p += 1; v += dyv if f & 32 else -dyv
            elif not f & 32:
                v += struct.unpack('>h', d[p:p+2])[0]; p += 2
            ys.append(v)
        out = []; s = 0
        for e in ends:
            out.append([(xs[i]+dx, ys[i]+dy, bool(flags[i] & 1)) for i in range(s, e+1)]); s = e+1
        return out

def quad_segments(contour, steps=8):
    """Flatten a TrueType contour (quadratic B-spline) to a closed polyline."""
    pts = contour
    n = len(pts)
    # start from an on-curve point (insert midpoint if none)
    start = next((i for i, p in enumerate(pts) if p[2]), None)
    if start is None:
        mid = ((pts[0][0]+pts[1][0])/2, (pts[0][1]+pts[1][1])/2, True)
        pts = [mid] + pts[1:] + [pts[0]]; start = 0; n = len(pts)
    pts = pts[start:] + pts[:start]
    poly = [(pts[0][0], pts[0][1])]
    i = 1
    prev = (pts[0][0], pts[0][1])
    while i <= n:
        p = pts[i % n]
        if p[2]:
            poly.append((p[0], p[1])); prev = (p[0], p[1]); i += 1
        else:
            nxt = pts[(i+1) % n]
            if nxt[2]:
                end = (nxt[0], nxt[1]); i += 2
            else:
                end = ((p[0]+nxt[0])/2, (p[1]+nxt[1])/2); i += 1
            for s in range(1, steps+1):
                t = s/steps
                x = (1-t)**2*prev[0] + 2*(1-t)*t*p[0] + t*t*end[0]
                y = (1-t)**2*prev[1] + 2*(1-t)*t*p[1] + t*t*end[1]
                poly.append((x, y))
            prev = end
    return poly

def quad_to_cubic(p0, p1, p2):
    c1 = (p0[0] + 2/3*(p1[0]-p0[0]), p0[1] + 2/3*(p1[1]-p0[1]))
    c2 = (p2[0] + 2/3*(p1[0]-p2[0]), p2[1] + 2/3*(p1[1]-p2[1]))
    return c1, c2

def contour_to_pdf(contour, tx):
    """PDF path operators for one contour, points mapped through tx(x, y)."""
    pts = contour; n = len(pts)
    start = next((i for i, p in enumerate(pts) if p[2]), None)
    if start is None:
        mid = ((pts[0][0]+pts[1][0])/2, (pts[0][1]+pts[1][1])/2, True)
        pts = [mid] + pts[1:] + [pts[0]]; start = 0; n = len(pts)
    pts = pts[start:] + pts[:start]
    x, y = tx(pts[0][0], pts[0][1]); ops = [f"{x:.3f} {y:.3f} m"]
    prev = (pts[0][0], pts[0][1]); i = 1
    while i <= n:
        p = pts[i % n]
        if p[2]:
            x, y = tx(p[0], p[1]); ops.append(f"{x:.3f} {y:.3f} l"); prev = (p[0], p[1]); i += 1
        else:
            nxt = pts[(i+1) % n]
            if nxt[2]: end = (nxt[0], nxt[1]); i += 2
            else: end = ((p[0]+nxt[0])/2, (p[1]+nxt[1])/2); i += 1
            c1, c2 = quad_to_cubic(prev, (p[0], p[1]), end)
            a = tx(*c1); b = tx(*c2); e = tx(*end)
            ops.append(f"{a[0]:.3f} {a[1]:.3f} {b[0]:.3f} {b[1]:.3f} {e[0]:.3f} {e[1]:.3f} c"); prev = end
    ops.append("h")
    return "\n".join(ops)

def rasterise(polys, width, height, ss=4):
    """Nonzero-winding scanline fill of closed polylines (pixel coords, y down) → coverage rows (0-255)."""
    W, H = width*ss, height*ss
    edges = []
    for poly in polys:
        for i in range(len(poly)):
            x0, y0 = poly[i]; x1, y1 = poly[(i+1) % len(poly)]
            if y0 == y1: continue
            edges.append((x0*ss, y0*ss, x1*ss, y1*ss))
    cov = [bytearray(W) for _ in range(H)]
    for j in range(H):
        sy = j + 0.5; xs = []
        for x0, y0, x1, y1 in edges:
            if (y0 <= sy < y1) or (y1 <= sy < y0):
                t = (sy - y0)/(y1 - y0); xs.append((x0 + t*(x1-x0), 1 if y1 > y0 else -1))
        xs.sort(); wind = 0; row = cov[j]
        for k in range(len(xs)):
            xa, w = xs[k]; prev_w = wind; wind += w
            if prev_w == 0 and wind != 0: span_start = xa
            elif prev_w != 0 and wind == 0:
                a, b = max(0, int(round(span_start))), min(W, int(round(xa)))
                if b > a: row[a:b] = b'\xff'*(b-a)
    out = []
    for j in range(height):
        row = bytearray(width)
        for i in range(width):
            s = 0
            for jj in range(ss):
                r = cov[j*ss+jj]; s += sum(r[i*ss:(i+1)*ss])
            row[i] = s//(ss*ss)
        out.append(bytes(row))
    return out

def write_png(path, rows_rgb, width, height):
    raw = b"".join(b"\x00" + r for r in rows_rgb)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag+data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)

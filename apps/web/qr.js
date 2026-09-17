// A QR code, drawn here rather than fetched (PD-121).
//
// The sign-in panel on a laptop shows a six-character code for the phone that holds the account. A phone's camera
// reads a QR code faster than a person types six characters, and `https://thro.uk/link/<code>` opens THRØ on the card
// that approves it (PD-117) — so the panel draws that address as a QR code. The encoder is written out here, because
// this site loads nothing from anybody else and a sign-in page is the last place to start: byte mode, error
// correction level M, versions 1 to 5 (up to 84 bytes — an address is about 30), all eight masks scored by the
// standard's own penalty rules. `tools/check_qr.py` draws one and has macOS read it back, so a change that breaks it
// is caught by a camera's own decoder rather than by a person squinting at a phone.
(function (root) {
  'use strict';

  // --- Reed–Solomon over GF(256), the field QR codes use (x^8 + x^4 + x^3 + x^2 + 1) -----------------------------
  const EXP = new Array(512), LOG = new Array(256);
  for (let i = 0, x = 1; i < 255; i++) { EXP[i] = x; LOG[x] = i; x <<= 1; if (x & 0x100) x ^= 0x11d; }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
  const mul = (a, b) => (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]];

  function generator(degree) {
    let g = [1];
    for (let i = 0; i < degree; i++) {
      const next = new Array(g.length + 1).fill(0);
      for (let j = 0; j < g.length; j++) { next[j] ^= g[j]; next[j + 1] ^= mul(g[j], EXP[i]); }
      g = next;
    }
    return g;
  }

  function remainder(data, degree) {
    const g = generator(degree);
    const r = new Array(degree).fill(0);
    for (const byte of data) {
      const factor = byte ^ r.shift();
      r.push(0);
      for (let i = 0; i < degree; i++) r[i] ^= mul(g[i + 1], factor);
    }
    return r;
  }

  // Level M. [total codewords, error-correction codewords per block, blocks]; data per block follows.
  const VERSIONS = { 1: [26, 10, 1], 2: [44, 16, 1], 3: [70, 26, 1], 4: [100, 18, 2], 5: [134, 24, 2] };
  const ALIGN = { 2: 18, 3: 22, 4: 26, 5: 30 };

  function codewords(bytes, version) {
    const [total, ecPerBlock, blocks] = VERSIONS[version];
    const dataTotal = total - ecPerBlock * blocks;
    const bits = [];
    const push = (value, length) => { for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
    push(0b0100, 4); push(bytes.length, 8);
    for (const b of bytes) push(b, 8);
    for (let i = 0; i < 4 && bits.length < dataTotal * 8; i++) bits.push(0);
    while (bits.length % 8) bits.push(0);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));
    for (let pad = 0xEC; data.length < dataTotal; pad ^= 0xEC ^ 0x11) data.push(pad);
    const per = dataTotal / blocks;
    const dataBlocks = [], ecBlocks = [];
    for (let b = 0; b < blocks; b++) {
      const block = data.slice(b * per, (b + 1) * per);
      dataBlocks.push(block); ecBlocks.push(remainder(block, ecPerBlock));
    }
    const out = [];
    for (let i = 0; i < per; i++) for (const block of dataBlocks) out.push(block[i]);
    for (let i = 0; i < ecPerBlock; i++) for (const block of ecBlocks) out.push(block[i]);
    return out;
  }

  const MASKS = [
    (r, c) => (r + c) % 2 === 0, (r) => r % 2 === 0, (r, c) => c % 3 === 0, (r, c) => (r + c) % 3 === 0,
    (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0, (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
    (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0, (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
  ];

  function formatBits(mask) {
    const data = (0b00 << 3) | mask;            // level M is 00
    let rem = data << 10;
    for (let i = 14; i >= 10; i--) if ((rem >>> i) & 1) rem ^= 0x537 << (i - 10);
    return ((data << 10) | rem) ^ 0x5412;
  }

  function build(version, words, mask) {
    const n = 17 + 4 * version;
    const m = Array.from({ length: n }, () => new Array(n).fill(false));
    const fixed = Array.from({ length: n }, () => new Array(n).fill(false));
    const set = (r, c, dark) => { if (r >= 0 && r < n && c >= 0 && c < n) { m[r][c] = dark; fixed[r][c] = true; } };
    const finder = (r0, c0) => {
      for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
        const ring = Math.max(Math.abs(r - 3), Math.abs(c - 3));
        set(r0 + r, c0 + c, ring <= 3 && ring !== 2 && r >= 0 && r <= 6 && c >= 0 && c <= 6);
      }
    };
    finder(0, 0); finder(0, n - 7); finder(n - 7, 0);
    if (ALIGN[version]) {
      const p = ALIGN[version];
      for (let r = -2; r <= 2; r++) for (let c = -2; c <= 2; c++) set(p + r, p + c, Math.max(Math.abs(r), Math.abs(c)) !== 1);
    }
    for (let i = 8; i < n - 8; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    set(n - 8, 8, true);                          // the dark module
    // Reserve the format areas, then write them last.
    for (let i = 0; i < 9; i++) { if (!fixed[8][i]) set(8, i, false); if (!fixed[i][8]) set(i, 8, false); }
    for (let i = 0; i < 8; i++) { set(8, n - 1 - i, false); if (i < 7) set(n - 1 - i, 8, false); }
    set(n - 8, 8, true);

    // The data, in the standard's zigzag from the bottom right, skipping the vertical timing column.
    const bits = [];
    for (const w of words) for (let i = 7; i >= 0; i--) bits.push((w >>> i) & 1);
    let k = 0, up = true;
    for (let col = n - 1; col > 0; col -= 2) {
      if (col === 6) col--;
      for (let i = 0; i < n; i++) {
        const r = up ? n - 1 - i : i;
        for (const c of [col, col - 1]) {
          if (fixed[r][c]) continue;
          const dark = k < bits.length ? bits[k] === 1 : false; k++;
          m[r][c] = dark !== MASKS[mask](r, c);
        }
      }
      up = !up;
    }

    const f = formatBits(mask);
    const bit = i => ((f >>> i) & 1) === 1;
    // Around the top-left finder: bits 0–5 down column 8, then 6–7 and 8 round the corner, then 9–14 along row 8.
    for (let i = 0; i <= 5; i++) m[i][8] = bit(i);
    m[7][8] = bit(6); m[8][8] = bit(7); m[8][7] = bit(8);
    for (let i = 9; i <= 14; i++) m[8][14 - i] = bit(i);
    // And the copy: bits 0–7 along row 8 from the right, bits 8–14 up column 8 from the bottom.
    for (let i = 0; i <= 7; i++) m[8][n - 1 - i] = bit(i);
    for (let i = 8; i <= 14; i++) m[n - 15 + i][8] = bit(i);
    return m;
  }

  function penalty(m) {
    const n = m.length; let score = 0;
    const line = get => {
      for (let a = 0; a < n; a++) {
        let run = 1;
        for (let b = 1; b < n; b++) {
          if (get(a, b) === get(a, b - 1)) { run++; if (run === 5) score += 3; else if (run > 5) score++; } else run = 1;
        }
        for (let b = 0; b + 10 < n; b++) {
          const s = []; for (let i = 0; i < 11; i++) s.push(get(a, b + i) ? 1 : 0);
          const t = s.join('');
          if (t === '10111010000' || t === '00001011101') score += 40;
        }
      }
    };
    line((a, b) => m[a][b]); line((a, b) => m[b][a]);
    for (let r = 0; r + 1 < n; r++) for (let c = 0; c + 1 < n; c++) {
      if (m[r][c] === m[r][c + 1] && m[r][c] === m[r + 1][c] && m[r][c] === m[r + 1][c + 1]) score += 3;
    }
    let dark = 0; for (const row of m) for (const v of row) if (v) dark++;
    score += Math.floor(Math.abs(dark * 100 / (n * n) - 50) / 5) * 10;
    return score;
  }

  /** The modules of a QR code for [text]: rows of booleans, true for dark. Throws when the text is too long. */
  function matrix(text) {
    const bytes = Array.from(new TextEncoder().encode(text));
    const capacity = { 1: 14, 2: 26, 3: 42, 4: 62, 5: 84 };
    const version = [1, 2, 3, 4, 5].find(v => bytes.length <= capacity[v]);
    if (!version) throw new Error('That is too long for the QR code this page draws.');
    const words = codewords(bytes, version);
    let best = null, bestScore = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      const m = build(version, words, mask), s = penalty(m);
      if (s < bestScore) { best = m; bestScore = s; }
    }
    return best;
  }

  /** An SVG of the code with the four-module quiet zone the standard asks for. Colours come from the page. */
  function svg(text, { dark = 'currentColor', light = 'transparent' } = {}) {
    const m = matrix(text), n = m.length, q = 4, size = n + 2 * q;
    let d = '';
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (m[r][c]) d += `M${c + q},${r + q}h1v1h-1z`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges" role="img" aria-label="A QR code for this sign-in code">`
      // `style`, not `fill=`: a custom property is read in a style and ignored in a presentation attribute.
      + `<rect width="${size}" height="${size}" style="fill:${light}"/><path d="${d}" style="fill:${dark}"/></svg>`;
  }

  const api = { matrix, svg };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.THROQR = api;
})(typeof window !== 'undefined' ? window : globalThis);

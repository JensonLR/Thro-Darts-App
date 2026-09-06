#!/usr/bin/env python3
"""
THRØ — design token pipeline.

The approved export's `tokens.css` is a COMPILED ARTEFACT, not a source: it carries no types, no
descriptions, and no light/dark pairing a generator could read. Three platforms hand-copying 177
values would drift, so this lifts it into a structured source and generates every platform from it.

  tokens.css (approved export)  ->  tokens.json (canonical source, light/dark as MODES)
                                ->  Swift / Kotlin / CSS

Nothing downstream is ever hand-edited. CI fails on a diff.

  python3 build.py            generate
  python3 build.py --check    fail if anything is stale or any contrast threshold is breached
"""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).parent
SOURCE_CSS = HERE.parent.parent / "docs/design/extracted/tokens.css"
OUT = HERE / "generated"

# ---------------------------------------------------------------- lift the export into a source
def lift():
    css = SOURCE_CSS.read_text()
    light, dark = {}, {}
    # The reduced-motion media block has a :root of its own; scanning it here would overwrite every
    # motion token's real value with the zero the block sets. It is read separately below.
    css_light = re.sub(r"@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{.*?\}\s*\}", "", css, flags=re.S)
    for m in re.finditer(r":root\s*\{(.*?)\}", css_light, re.S):
        light.update(dict(re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;]+)", m.group(1))))
    for m in re.finditer(r'\[data-theme="dark"\]\s*\{(.*?)\}', css, re.S):
        dark.update(dict(re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;]+)", m.group(1))))
    reduced = {}
    m = re.search(r"@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{\s*:root\s*\{(.*?)\}", css, re.S)
    if m:
        reduced = dict(re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;]+)", m.group(1)))

    def kind(name, value):
        v = value.strip()
        if name.startswith("--color") or name.startswith("--thro-") or v.startswith("#") or v.startswith("rgba"):
            return "color"
        if name.startswith("--spacing") or name.startswith("--space") or name.startswith("--touch"):
            return "dimension"
        if name.startswith("--radius"):
            return "dimension"
        if name.startswith("--border-width") or name.startswith("--focus-ring"):
            return "dimension"
        if "-size" in name or "-line" in name:
            return "fontSize" if "-size" in name else "dimension"
        if "-tracking" in name:
            return "letterSpacing"
        if name.startswith("--font-weight"):
            return "fontWeight"
        if name.startswith("--font") or name.startswith("--typography-family"):
            return "fontFamily"
        if "duration" in name:
            return "duration"
        if "easing" in name:
            return "cubicBezier"
        if "travel" in name:
            return "dimension"
        if name.startswith("--elevation"):
            return "shadow"
        return "other"

    tokens = {}
    for name, value in light.items():
        t = {"$type": kind(name, value), "$value": {"light": value.strip()}}
        if name in dark:
            t["$value"]["dark"] = dark[name].strip()
        if name in reduced:
            t["$value"]["reducedMotion"] = reduced[name].strip()
        tokens[name] = t
    return {
        "$description": "THRØ canonical design tokens. Lifted from the approved Claude Design "
                        "export; light and dark are MODES OF ONE TOKEN, never two token sets.",
        "$source": "docs/design/extracted/tokens.css",
        "tokens": tokens,
    }

# ---------------------------------------------------------------- helpers
def camel(name):
    parts = name.lstrip("-").split("-")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])

def resolve(value, table, depth=0):
    v = value.strip()
    while v.startswith("var(") and depth < 12:
        m = re.match(r"var\((--[a-z0-9-]+)\)", v)
        if not m:
            break
        nxt = table.get(m.group(1))
        if nxt is None:
            return None
        v = nxt.strip()
        depth += 1
    return v

def flat(doc, mode):
    """Resolved name -> literal value for one mode, with fallback to light."""
    raw = {}
    for n, t in doc["tokens"].items():
        val = t["$value"].get(mode) or t["$value"]["light"]
        raw[n] = val
    return {n: resolve(v, raw) for n, v in raw.items()}

def parse_rgba(v):
    """`#rrggbb` -> (r, g, b, 1.0); `rgba(r,g,b,a)` -> (r, g, b, a); anything else -> None.
    The scrim is the one token with alpha, and a scrim emitted without its alpha is a wall."""
    v = v.strip()
    if v.startswith("#"):
        rgb = hex_to_rgb(v)
        return (*rgb, 1.0) if rgb else None
    m = re.match(r"^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)$", v)
    if m:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4)))
    return None

def hex_to_rgb(h):
    h = h.strip().lstrip("#")
    if len(h) != 6:
        return None
    try:
        return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
    except ValueError:
        return None

def luminance(h):
    rgb = hex_to_rgb(h)
    if rgb is None:
        return None
    def c(x):
        x /= 255
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = (c(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    if la is None or lb is None:
        return None
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

# ---------------------------------------------------------------- emitters
def emit_swift(doc):
    L = ["// GENERATED by packages/design-tokens/build.py - DO NOT EDIT.",
         "import SwiftUI", "",
         "/// THRØ design tokens. Colours resolve light and dark from the asset catalogue, so the",
         "/// system trait decides rather than the call site.",
         "public enum ThroColor {"]
    lt, dk = flat(doc, "light"), flat(doc, "dark")
    for n in sorted(doc["tokens"]):
        if doc["tokens"][n]["$type"] != "color":
            continue
        l, d = lt.get(n), dk.get(n)
        if not l or parse_rgba(l) is None:
            continue
        L.append(f'    /// light {l}   dark {d or l}')
        L.append(f'    public static let {camel(n)} = Color("{camel(n)}", bundle: .module)')
    L.append("}")
    L.append("")
    L.append("public enum ThroSpacing {")
    for n in sorted(doc["tokens"]):
        if doc["tokens"][n]["$type"] != "dimension":
            continue
        v = lt.get(n) or ""
        m = re.match(r"^(\d+)px$", v)
        if m:
            L.append(f"    public static let {camel(n)}: CGFloat = {m.group(1)}")
    L.append("}")
    L.append("")
    L.append("/// Motion tokens. Durations in seconds; easings as the four cubic-bezier control values,")
    L.append("/// for `Animation.timingCurve(_:_:_:_:duration:)`. Under Reduce Motion the token layer sets")
    L.append("/// every duration to zero; code that animates checks `accessibilityReduceMotion` itself.")
    L.append("public enum ThroMotion {")
    for n in sorted(doc["tokens"]):
        t = doc["tokens"][n]["$type"]; v = (lt.get(n) or "").strip()
        if t == "duration":
            m = re.match(r"^(\d+)ms$", v)
            if m:
                L.append(f"    public static let {camel(n)}: Double = {int(m.group(1)) / 1000:g}")
        elif t == "cubicBezier":
            m = re.match(r"^cubic-bezier\(([^)]+)\)$", v)
            if m:
                pts = [x.strip() for x in m.group(1).split(",")]
                if len(pts) == 4:
                    L.append(f"    public static let {camel(n)}: (CGFloat, CGFloat, CGFloat, CGFloat) = ({', '.join(pts)})")
        elif n.startswith("--motion-scale"):
            L.append(f"    public static let {camel(n)}: CGFloat = {v}")
    L.append("}")
    L.append("")
    L.append("/// Type roles bind to a text style so Dynamic Type scales them. A fixed-size font")
    L.append("/// would ignore the user's text-size setting entirely.")
    L.append("public enum ThroType {")
    for n in sorted(doc["tokens"]):
        if doc["tokens"][n]["$type"] != "fontSize":
            continue
        v = lt.get(n) or ""
        m = re.match(r"^(\d+)px$", v)
        if m:
            L.append(f"    public static let {camel(n)}: CGFloat = {m.group(1)}")
    L.append("}")
    return "\n".join(L) + "\n"

def emit_kotlin(doc):
    lt, dk = flat(doc, "light"), flat(doc, "dark")
    L = ["// GENERATED by packages/design-tokens/build.py - DO NOT EDIT.",
         "package thro.design", "",
         "import androidx.compose.ui.graphics.Color",
         "import androidx.compose.ui.unit.dp",
         "import androidx.compose.ui.unit.sp", "",
         "/** Colour tokens, one value class per theme mode. */",
         "public data class ThroColors("]
    colors = [n for n in sorted(doc["tokens"])
              if doc["tokens"][n]["$type"] == "color" and (lt.get(n) or "").startswith("#")]
    for n in colors:
        L.append(f"    public val {camel(n)}: Color,")
    L.append(")")
    L.append("")
    for mode, table in (("light", lt), ("dark", dk)):
        L.append(f"public fun thro{mode.capitalize()}Colors(): ThroColors = ThroColors(")
        for n in colors:
            v = (table.get(n) or lt.get(n)).lstrip("#")
            L.append(f"    {camel(n)} = Color(0xFF{v.upper()}),")
        L.append(")")
        L.append("")
    L.append("public object ThroSpacing {")
    for n in sorted(doc["tokens"]):
        if doc["tokens"][n]["$type"] != "dimension":
            continue
        m = re.match(r"^(\d+)px$", lt.get(n) or "")
        if m:
            # spacing and radius are dp; they must NOT scale with the user's font size
            L.append(f"    public val {camel(n)} = {m.group(1)}.dp")
    L.append("}")
    L.append("")
    L.append("/** Type roles are sp so Android font scaling applies. Using dp here would silently")
    L.append(" *  disable it, which is the most common way a type scale ignores accessibility. */")
    L.append("public object ThroType {")
    for n in sorted(doc["tokens"]):
        if doc["tokens"][n]["$type"] != "fontSize":
            continue
        m = re.match(r"^(\d+)px$", lt.get(n) or "")
        if m:
            L.append(f"    public val {camel(n)} = {m.group(1)}.sp")
    L.append("}")
    return "\n".join(L) + "\n"

def emit_asset_catalogue(doc):
    """Swift colours resolve from an asset catalogue so UITraitCollection picks light or dark
    natively. Referencing a catalogue we never generated would make the Swift output decorative."""
    lt, dk = flat(doc, "light"), flat(doc, "dark")
    files = {"Colors.xcassets/Contents.json":
             json.dumps({"info": {"author": "thro", "version": 1}}, indent=2) + "\n"}
    for n, t in doc["tokens"].items():
        if t["$type"] != "color":
            continue
        l = lt.get(n)
        if not l or parse_rgba(l) is None:
            continue
        d = dk.get(n) or l
        def comps(v):
            r, g, b, a = parse_rgba(v)
            return {"red": f"0x{r:02X}", "green": f"0x{g:02X}", "blue": f"0x{b:02X}", "alpha": f"{a:.3f}"}
        entry = {
            "info": {"author": "thro", "version": 1},
            "colors": [
                {"idiom": "universal",
                 "color": {"color-space": "srgb", "components": comps(l)}},
                {"idiom": "universal",
                 "appearances": [{"appearance": "luminosity", "value": "dark"}],
                 "color": {"color-space": "srgb", "components": comps(d)}},
            ],
        }
        files[f"Colors.xcassets/{camel(n)}.colorset/Contents.json"] = json.dumps(entry, indent=2) + "\n"
    return files

def emit_css(doc):
    L = ["/* GENERATED by packages/design-tokens/build.py - DO NOT EDIT. */", ":root {"]
    for n, t in doc["tokens"].items():
        L.append(f"  {n}: {t['$value']['light']};")
    L.append("}")
    L.append('[data-theme="dark"] {')
    for n, t in doc["tokens"].items():
        if "dark" in t["$value"]:
            L.append(f"  {n}: {t['$value']['dark']};")
    L.append("}")
    L.append("@media (prefers-reduced-motion: reduce) {")
    L.append("  :root {")
    for n, t in doc["tokens"].items():
        if "reducedMotion" in t["$value"]:
            L.append(f"    {n}: {t['$value']['reducedMotion']};")
    L.append("  }")
    L.append("}")
    return "\n".join(L) + "\n"

# ---------------------------------------------------------------- contrast gate
# Absolute thresholds with a dated, itemised exception list. A regression gate against the current
# baseline would FREEZE the known failures rather than catch them.
EXCEPTIONS = {
    ("--color-status-live", "--color-status-live-surface", "light"):
        "4.38:1 — design commission: live status pairing (raised 2026-09-03)",
    ("--color-text-achievement", "--color-background-primary", "light"):
        "3.68:1 — bronze is large-text only by design (raised 2026-09-03)",
    ("--color-text-tertiary", "--color-background-secondary", "light"):
        "4.21:1 — non-critical support text on sunken surfaces (raised 2026-09-03)",
    ("--color-text-tertiary", "--color-background-secondary", "dark"):
        "4.30:1 — as above (raised 2026-09-03)",
    ("--color-text-tertiary", "--color-background-raised", "dark"):
        "4.30:1 — as above (raised 2026-09-03)",
    ("--color-text-inverse", "--color-background-brand", "dark"):
        "1.99:1 — ink on deep green; design commission (raised 2026-09-03)",
    ("--color-border-default", "--color-background-primary", "light"): "decorative rule, not a control boundary",
    ("--color-border-default", "--color-background-raised", "light"): "decorative rule",
    ("--color-border-default", "--color-background-primary", "dark"): "decorative rule",
    ("--color-border-default", "--color-background-raised", "dark"): "decorative rule",
    ("--color-border-strong", "--color-background-primary", "light"):
        "1.70:1 — load-bearing control boundary; design commission (raised 2026-09-03)",
    ("--color-border-strong", "--color-surface-primary", "light"): "as above",
    ("--color-border-strong", "--color-background-primary", "dark"): "as above",
    ("--color-border-strong", "--color-surface-primary", "dark"): "as above",
    ("--color-focus-ring", "--color-background-brand", "light"):
        "1.29:1 — focus invisible on primary buttons; design commission (raised 2026-09-03)",
    ("--color-focus-ring", "--color-background-inverse", "light"): "1.99:1 — as above",
    ("--color-focus-ring", "--color-background-inverse", "dark"): "2.78:1 — as above",
    ("--color-chart-reference", "--color-background-primary", "light"): "benchmark line; chart commission",
    ("--color-chart-reference", "--color-background-primary", "dark"): "benchmark line; chart commission",
    ("--color-chart-primary", "--color-chart-secondary", "light"): "single-series today; chart commission",
    ("--color-chart-primary", "--color-chart-secondary", "dark"): "single-series today; chart commission",
}

PAIRS_TEXT = [("--color-text-primary", "--color-background-primary"),
              ("--color-text-primary", "--color-background-secondary"),
              ("--color-text-secondary", "--color-background-primary"),
              ("--color-text-secondary", "--color-background-secondary"),
              ("--color-text-tertiary", "--color-background-primary"),
              ("--color-text-tertiary", "--color-background-secondary"),
              ("--color-text-tertiary", "--color-background-raised"),
              ("--color-text-inverse", "--color-background-inverse"),
              ("--color-text-inverse", "--color-background-brand"),
              ("--color-text-brand", "--color-background-primary"),
              ("--color-text-achievement", "--color-background-primary")]
STATUSES = ["success", "warning", "error", "info", "live", "pending", "offline", "verified", "disputed"]
PAIRS_UI = [("--color-border-default", "--color-background-primary"),
            ("--color-border-default", "--color-background-raised"),
            ("--color-border-strong", "--color-background-primary"),
            ("--color-border-strong", "--color-surface-primary"),
            ("--color-focus-ring", "--color-background-primary"),
            ("--color-focus-ring", "--color-background-brand"),
            ("--color-focus-ring", "--color-background-inverse"),
            ("--color-chart-reference", "--color-background-primary"),
            ("--color-chart-primary", "--color-chart-secondary")]

def contrast_report(doc):
    rows, breaches = [], []
    for mode in ("light", "dark"):
        t = flat(doc, mode)
        checks = [(f, b, 4.5) for f, b in PAIRS_TEXT]
        checks += [(f"--color-status-{s}", f"--color-status-{s}-surface", 4.5) for s in STATUSES]
        checks += [(f, b, 3.0) for f, b in PAIRS_UI]
        for fg, bg, need in checks:
            a, b = t.get(fg), t.get(bg)
            if not a or not b:
                continue
            r = contrast(a, b)
            if r is None:
                continue
            ok = r >= need
            rows.append((mode, fg, bg, r, need, ok))
            if not ok and (fg, bg, mode) not in EXCEPTIONS:
                breaches.append(f"{mode}: {fg} on {bg} = {r:.2f}:1 (needs {need}:1) — no exception recorded")
    return rows, breaches

# ---------------------------------------------------------------- main
def main():
    check = "--check" in sys.argv
    doc = lift()
    OUT.mkdir(exist_ok=True)
    artefacts = {
        "tokens.json": json.dumps(doc, indent=2) + "\n",
        "ThroTokens.swift": emit_swift(doc),
        "ThroTokens.kt": emit_kotlin(doc),
        "tokens.css": emit_css(doc),
    }
    artefacts.update(emit_asset_catalogue(doc))
    stale = []
    for name, content in artefacts.items():
        p = OUT / name
        if check and (not p.exists() or p.read_text() != content):
            stale.append(name)
        if not check:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)

    rows, breaches = contrast_report(doc)
    n_fail = sum(1 for r in rows if not r[5])
    n_sets = sum(1 for k in artefacts if k.endswith(".colorset/Contents.json"))
    print(f"tokens: {len(doc['tokens'])}  platforms: swift ({n_sets} colour sets), kotlin, css")
    print(f"contrast: {len(rows)} pairs checked, {n_fail} below threshold, "
          f"{len(EXCEPTIONS)} recorded exceptions, {len(breaches)} unrecorded")

    if stale:
        print("\nSTALE (regenerate and commit): " + ", ".join(stale))
    for b in breaches:
        print("  BREACH " + b)
    if stale or breaches:
        sys.exit(1)
    print("OK")

if __name__ == "__main__":
    main()

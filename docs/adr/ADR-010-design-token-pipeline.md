# ADR-010 — Design token pipeline

**Status:** Accepted · **Date:** 2026-09-03

## Context

The recovered `tokens.css` is a **compiled artefact, not a source** — the stripped font-face rules
left orphaned subset comments behind, and annotation residue survives on several tokens. It carries
no types, no descriptions and no light/dark pairing structure a generator could read. Three platforms
would hand-copy 177 tokens, and drift would be certain.

Generated evidence in [`../design/TOKEN_HEALTH.md`](../design/TOKEN_HEALTH.md): **48 tokens are dead**
and there are already **26 bypasses** inside the export itself.

## Decision

**A platform-neutral structured token source, generating Swift, Kotlin and CSS. No platform token
file is ever hand-edited.**

- **Source:** a versioned, reviewable token document with explicit types and descriptions, structured
  in three tiers — primitives, semantic aliases, and component-level values only where genuinely
  needed.
- **Light and dark are two *modes of one token*, never two token sets.** This makes parity a
  mechanical check rather than a discipline.
- **Motion emits as data, not strings** — durations as integers and easings as control-point
  quadruples, so each platform builds its native curve. **Reduced motion is a second mode** of every
  duration and travel token, so each platform reads the accessibility setting and selects a mode
  rather than reimplementing a media query three times.
- **The scalable-versus-fixed distinction is encoded in the token type**, not decided by the
  implementer. Type roles must scale with the user's text size; spacing and radius must not. Getting
  this wrong on Android silently disables font scaling or clips every hero.

## CI gates

1. Regenerate and fail on any diff — **a hand-edited platform token file breaks the build.**
2. **Regenerate the contrast matrix and fail against absolute thresholds** — 4.5:1 for text, 3:1 for
   boundaries and focus — **with a dated, itemised exception list**, not an open-ended baseline.

   A regression gate against the current baseline would have *frozen* the 21 known failures rather
   than caught them, including `live` on its own surface at 4.38:1. Each exception names the pair, the
   ratio, and the design commission that will resolve it. An exception without a commission fails the
   build.
3. Reject raw colour values and off-scale font sizes in all three platform sources.
4. Fail if any semantic token lacks a dark-mode value.

## Blocked on design input

The pipeline can be built now, but three inputs must come from Design before native layout begins,
and must not be invented: the **Dynamic Type scaling contract** (which roles scale, clamps, and what
hero numerals do at accessibility sizes); **focus, hover and pressed appearance**, noting the focus
ring currently fails contrast on brand and ink surfaces so a colour alone will not fix it; and a
resolution for the **theme-scope defect**, where four scoring components default to dark and paint no
background, rendering chalk on chalk at 1.00:1 and surviving only by CSS cascade — which does not
exist on either native platform.

## Consequences

- Fonts are embedded per platform, not fetched at runtime; the design system says so itself, and a
  CDN reference also leaks user IPs on every launch.
- The generated CSS reproduces the approved export's **structure and semantics** — not its bytes.
  Byte-comparability was revision 1's stated consequence and it is incompatible with this record's
  own gates: the export contains 48 dead tokens, 16 raw colour values and 10 off-scale font sizes,
  all of which gate 3 rejects.

## Revisit trigger

A fourth platform target; or Design moving to a source of truth that can export tokens directly, at
which point this pipeline consumes that instead.

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
2. **Regenerate the contrast matrix and fail on any regression** against the committed baseline. This
   is cheap and would have caught both the invisible focus ring and the failing live status.
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
- The generated CSS keeps the web and organiser surface byte-comparable to the approved export.

## Revisit trigger

A fourth platform target; or Design moving to a source of truth that can export tokens directly, at
which point this pipeline consumes that instead.

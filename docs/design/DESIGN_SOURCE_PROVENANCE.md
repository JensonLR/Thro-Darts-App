# THRØ Design Source — Provenance

## Status: RECOVERED (export snapshot), not a live Design connection

The approved THRØ Design System is the visual and interaction authority for this build
(source precedence rank 3). This document records exactly where the copy in this
repository came from, so that no future session has to guess — and so that nobody
mistakes this snapshot for the live design project.

## What was inspected

| Item | Value |
|---|---|
| Source | Claude Design export, published as a Claude artifact owned by the founder |
| Artifact | `THRØ Design System` — https://claude.ai/code/artifact/7e217774-52db-4968-9c02-868c718f940d |
| Artifact title | `THRØ — mobile UI kit` |
| Retrieved | 2026-09-03 |
| Bundle format | `@ds-bundle` format 4, namespace `THRDesignSystem_ac73b5` |
| Authenticity | Carries the Claude Design bundle manifest, per-file `sourceHashes`, and the Claude Design branding block. It is a genuine Design export, not a reconstruction. |

## What the snapshot contains

- `extracted/tokens.css` — the complete token layer: brand + semantic colour for **both**
  light and dark themes, typography scale, spacing, radius, borders, elevation, motion
  (including reduced-motion overrides).
- `extracted/components/` — **61 components** in 11 families: core, data, development,
  forms, identity, navigation, organiser, rating, scoring, state.
- `extracted/ui_kits/thro-app/` — **33 participant screens** in 9 groups
  (Start 2, Home 3, Play 6, Live 4, Tournament 4, Shadow 4, Discover 2, You 4, Account 4)
  plus the navigation model (`app.jsx`).
- `extracted/ui_kits/thro-organiser/` — **9 organiser screens** (control, boards, queue,
  entries, draw, disputes, verification, league, venue) plus the organiser shell.

## Important limitations — read before relying on this

1. **This is compiled output, not the design master.** The `.jsx` files are Babel-compiled
   (`React.createElement`) rather than authored JSX. They are faithful to behaviour and to
   token usage, and they are readable, but they are a derivative. Per source precedence,
   they rank as a *reference implementation* for anything the token layer or an explicit
   design rule already covers — where they disagree with a token, **the token wins**.
2. **The live Claude Design project was NOT reachable from this session.** The `DesignSync`
   integration requires an interactive `/design-login`, which cannot run in a remote
   session. So this snapshot cannot be diffed against the current state of the design
   project, and any design changes made after 2026-09-03 are not reflected here.
3. **Fonts were deliberately not committed.** The export bundles Archivo and IBM Plex Sans
   Condensed as woff2 derived from the Google Fonts CDN. The design template itself states
   that production must embed the binaries locally rather than fetch at runtime. Font
   packaging and licence confirmation is tracked as an open item, not assumed.
4. **Sample data in these files is not product truth.** Player names, ratings, band labels,
   venue names and statistics inside the screens are fixtures (source precedence rank 8).
   They must never be promoted into the domain model or copy by implementation convenience.

## How to re-verify or refresh

Re-read the artifact above and re-extract. To connect the *live* design project instead,
run `/design-login` once from an interactive Claude Code session on a local machine; remote
sessions then reuse that authorization and `DesignSync` becomes available.

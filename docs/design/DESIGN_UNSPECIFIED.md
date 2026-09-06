# What the approved design system does not specify

Twenty-five behaviours that production needs and the approved system does not define. **None of
these may be invented by engineering** — each is a design decision with brand or accessibility
consequences. Where implementation is blocked on one, say so and escalate rather than choosing.

Sourced by reading the whole export: 61 components, 33 participant screens, 9 organiser screens.

## Blocking — implementation cannot proceed correctly without these

1. **Dynamic Type / font-scaling contract.** The entire type scale is fixed pixels; there is no
   `rem`, `em` or scaling ramp anywhere. Needed per type role: does it scale, what are the min/max
   clamps, and what do the hero numerals do at accessibility sizes. Several heroes already have
   tight or negative leading (96/88), so naive scaling clips them. This changes every layout, not
   every colour — it is the most expensive item here to retrofit.
2. **Focus, hover and pressed appearance.** Zero of 61 components implement any of them. For a
   keypad used one-handed at speed, the absence of a pressed state is a functional defect: the
   player gets no confirmation a score registered. Note the focus ring currently fails contrast on
   brand and ink surfaces (see `CONTRAST_MATRIX.md`), so this needs a solution, not just a colour.

   **Worse than absent in two places.** `TextField` and `SearchField` set `outline: 'none'` on the
   input itself and supply no replacement — no focus box-shadow, no focus border, no handler. They
   do not omit a focus state; they remove the one the platform provided. A keyboard or
   switch-control user gets no visible focus at all, on the two components where entering text is
   the entire purpose. Found by `audit_components.py`, which now fails CI on any new instance.
3. **Organiser layout and breakpoint contract.** The organiser CSS classes have no definitions:
   no sidebar width, content max-width, column ratios, grid gutters, breakpoints, or minimum
   supported width. The screens are readable as composition but not reproducible as layout.
4. **Keyboard operability of the organiser controls.** `DataTable` — used across disputes, entries,
   verification, draw and league — renders rows as a clickable `<tr>` with no tab index, no role and
   no key handler. It is the surface where an official decides competitive results.
5. **Participant layout frame.** The participant harness classes are equally undefined, so
   **safe-area insets are specified nowhere** — on a full-bleed dark scoring screen whose bottom
   element is the keypad.
6. **The authentication and identity surface.** There is no sign-in screen, no enrolment, no email
   verification, no recovery, no re-auth path and no device or session management anywhere in the
   42 screens — only a splash "Sign in" button that routes nowhere and a settings row reading
   "Sign-in method · Passkey". Passkey *recovery* and the organiser-verified **identity-claim** flow
   are the two highest-risk flows in the product and neither is drawn.

7. **Participant result attestation.** There is no way for a player to confirm, or contest, a
   result. The match result screen's only action is "Back to tournament". The organiser's per-leg
   `Confirmed` column reads from an event no participant client can author, so the trust model's
   `participant-confirmed` state is currently unreachable from the participant app.

   **This gates rating eligibility** (decision PD-002): without it, only organiser-confirmed results
   can rate, so anything outside an organised competition does not count. It is the single highest-
   value item on this list.

## State and component gaps

8. **The `quarantined` verification state.** The trust model needs it; `VerificationState`
   implements eight states and does not include it.
9. **A `Stat` variant for unavailable or bounded values.** `Stat` accepts only label/value/delta/unit.
   Without an "unavailable" and an "approximate" rendering, statistics that cannot be honestly
   computed have nowhere truthful to go.
10. **A pending / not-yet-eligible rating state.** The result screen shows rating movement beside a
   verified badge only. There is no way to say *"your rating has not moved yet, because this result
   is not yet eligible"* — which will be the majority case at launch.
11. **An offline-completed result state.** The result screen shows only the happy path (verified +
    synced). A match completed offline must honestly render as self-reported and queued.
12. **A whole-match-contested dispute state.** The dispute screen's copy and its four actions assume
    a dispute narrowed to one leg. Two players scoring the same match offline produces a fully
    contested match, which has no representation.
13. **`bye` and `walkover` states on `TournamentProgress`**, which supports only won/lost/active/future.
14. **Loading state for any screen.** `LoadingState` exists and is used by none of the 42 screens.
15. **Disabled appearance** beyond a flat opacity multiplier (which produces real contrast failures).
16. **`Dialog` and `Sheet` modal behaviour** — scrim, focus trap, dismissal, initial focus.
    `--color-scrim` is defined and unused; both currently claim `aria-modal` without being modal.
17. **`DataTable` sort, pagination, empty, loading and error states.**
18. **Invalid and impossible score feedback**, and remaining-score validation, on the keypad.
19. **Multi-series charts, axes, y-scale policy and a data-table alternative.** `TrendChart`
    auto-scales with no axis, so a 3-point and a 300-point rating change render identically.

## Behaviour and platform

20. **Whether a user-selectable dark mode exists**, or dark is purely contextual. There is no
    `prefers-color-scheme` block, and the organiser sidebar uses a second, hardcoded dark mechanism.
    **Decided by the founder, 2026-09-06 (PD-003):** user-selectable System / Light / Dark for the
    screens the export draws light; setup and scoring stay dark as drawn. The dark rendering of the
    light-drawn screens is the token layer's, unreviewed by design.
21. **Whether the organiser has a dark theme** — it runs in the venue, often on a laptop in a dim hall.
22. **Increased-contrast and reduced-transparency variants.** Given the boundary failures, an
    increased-contrast variant is genuinely needed.
23. **Landscape orientation for scoring.**
24. **Truncation policy for long player, venue and team names.** Only 8 of 61 components handle overflow.
25. **Haptics** — nothing is specified for the scoring keypad, where it matters most.

Also outstanding, and smaller: **the brand assets** (`logo-chalk.svg` and `mark-chalk.svg` are both
referenced throughout and neither was exported); the **icon legibility floor** (a 2px stroke on a 24
grid rendered at 13–14px); **RTL and bidirectional layout**; **Snackbar timing, position, stacking
and dismissal**; and **font substitution behaviour** on load failure, given that "no silent
substitution" is stated but no fallback behaviour is defined.


## Found mechanically, 2026-09-04

`audit_components.py` was written because every finding above was found by reading the components,
and nothing re-checked them. It reports 12 findings across the 61 components and holds them as a
baseline, so a re-export cannot regress silently.

Six were already known. **Six were not:**

| Component | Finding |
|---|---|
| `forms/TextField` | suppresses the focus ring with no replacement |
| `forms/SearchField` | suppresses the focus ring with no replacement |
| `rating/FormIndicator` | hardcodes `fontSize: 12` — does not scale with Dynamic Type |
| `scoring/TurnIndicator` | colour literal `rgba(247,246,242,0.6)` outside the token layer |
| `forms/FilterChip` | interactive, `minHeight: 36` — below the 44px minimum |
| `forms/SegmentedControl` | interactive, `minHeight: 40` — below the 44px minimum |
| `development/PathwayStep` | interactive, `minHeight: 32` — below the 44px minimum |

The three sub-minimum targets each carry an `onClick` and `cursor: pointer` on the element whose
height is short, so they are real targets rather than decorative rules — checked individually rather
than inferred from the pattern.

The colour literal matters beyond itself: the contrast matrix is computed from the token layer, so a
literal is a colour no contrast check has ever seen.

**None of these were fixed here.** The design system is source-precedence rank 3 and the founder's to
change; the audit reports and CI holds the line, but the export is not edited.

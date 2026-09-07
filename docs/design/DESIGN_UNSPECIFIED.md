# What the approved design system does not specify

Twenty-five behaviours that production needs and the approved system does not define. **None of
these may be invented by engineering** — each is a design decision with brand or accessibility
consequences. Where implementation is blocked on one, say so and escalate rather than choosing.

Sourced by reading the whole export: 61 components, 33 participant screens, 9 organiser screens.

## Blocking — implementation cannot proceed correctly without these

1. ~~**Dynamic Type / font-scaling contract.**~~ **COMMISSIONED (PD-015) AND BUILT, 2026-09-07.**
   The scaling ramp came first: every type role carries a `relativeTo:` text style, so the embedded
   faces grow with the player's setting. What was missing was the *contract* at the top of the
   range, and it is now written down in `docs/design/DYNAMIC_TYPE.md`: reading screens scale to
   `.accessibility5` and scroll; the scoring screen stops at `.accessibility1`, because it must fit
   without scrolling and holds a keypad already at the minimum touch target. That was a real
   limit for a player who needs the largest text, and it is now **lifted (PD-024, 2026-09-07)**: past
   `.accessibility1` the upper region scrolls and its text grows to `.accessibility5`, while the
   keypad keeps the old ceiling — pinned, because a keypad that moves under a thumb mid-visit is the
   thing the cap existed to prevent. The founder chose that shape from the two `DYNAMIC_TYPE.md`
   named; engineering did not pick it, and **no design commission is outstanding on this item.**
2. ~~**Focus, hover and pressed appearance.**~~ **COMMISSIONED (PD-015) AND BUILT ON THE CLIENT,
   2026-09-07.** `ThroPressStyle` replaces `.buttonStyle(.plain)` — which was SwiftUI for *do
   nothing at all* — on the keypad and its Enter key. A press goes in by the inverse of the design's
   own `motionScaleImpact`, so a key travels exactly as far in as the design says an impact travels
   out; the scale is withdrawn under Reduce Motion and the surface change is kept, because that
   setting means what it says. `ThroFocusRing` draws the focus ring *outside* the control's own
   border, so it never overlaps an error border and the contrast problem below does not arise.
   **The export's own components are unchanged and this item stands for them** — the React
   components still implement none of this, and `audit_components.py` still fails CI on any new
   instance of the `outline: 'none'` defect below.

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

7. **Participant result attestation.** ~~There is no way for a player to confirm, or contest, a
   result.~~ **Commissioned and built, 2026-09-07 — PD-011.** The export still draws no such screen;
   the founder extended PD-010's authority to cover this one, and `ConfirmResultScreen` is composed
   from approved components on those terms.

   What is built is the local case: both players at one phone, each asked in turn by name, their
   answers appended to the journal. That reaches `participant-confirmed` — the state that was
   unreachable — while saying plainly that two people at one phone is the weakest form of it, not
   the two-device corroboration the trust model prefers.

   **What is still missing** is the export's own drawing of it, and the online case: an opponent on
   their own device confirming a result they did not enter, which needs identity (B4) and sync.

   **This gates rating eligibility** (decision PD-002): without it, only organiser-confirmed results
   can rate, so anything outside an organised competition does not count. It was the single highest-
   value item on this list.

## State and component gaps

8. **The `quarantined` verification state.** The trust model needs it; `VerificationState`
   implements eight states and does not include it.
9. ~~**A `Stat` variant for unavailable or bounded values.**~~ **COMMISSIONED (PD-015) AND BUILT ON
   THE CLIENT, 2026-09-07.** `StatItem` now carries a confidence — exact, range or unavailable —
   and `StatGrid` draws the three differently and speaks the basis to a screen reader, since colour
   is not available to one. The guarantee is in the type rather than in the drawing: `range` and
   `unavailable` take the reason as a **non-optional** argument, so it is not possible to put a dash
   or an interval on a screen without saying why it is one. Until this, all three were drawn
   identically — same weight, same colour, same size — so the one thing the honesty layer exists to
   communicate was the one thing the screen did not show. The export's `Stat` is unchanged.
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
    **Partly decided by the founder, 2026-09-06 (PD-005):** the bust and won-leg card over the scoring
    screen uses the Dialog surface and `--color-scrim`, dismisses on its button or a scrim tap, traps
    nothing and animates nothing. Focus trap, initial focus and animation stay open.
17. **`DataTable` sort, pagination, empty, loading and error states.**
18. **Invalid and impossible score feedback**, and remaining-score validation, on the keypad.
19. **Multi-series charts, axes, y-scale policy and a data-table alternative.** `TrendChart`
    auto-scales with no axis, so a 3-point and a 300-point rating change render identically.

## Behaviour and platform

20. **Whether a user-selectable dark mode exists**, or dark is purely contextual. There is no
    `prefers-color-scheme` block, and the organiser sidebar uses a second, hardcoded dark mechanism.
    **Decided by the founder, 2026-09-06 (PD-003, amended the same day):** user-selectable System /
    Light / Dark for **every** screen, set in Settings. Each screen's undrawn rendering — dark Home,
    light scoring — is the token layer's, unreviewed by design.
21. **Whether the organiser has a dark theme** — it runs in the venue, often on a laptop in a dim hall.
22. **Increased-contrast and reduced-transparency variants.** Given the boundary failures, an
    increased-contrast variant is genuinely needed.
23. **Landscape orientation for scoring.** The app is portrait-only, as every screen in the export is drawn;
    a landscape scoring screen would need a design.
24. **Truncation policy for long player, venue and team names.** Only 8 of 61 components handle overflow.
25. ~~**Haptics**~~ **COMMISSIONED (PD-015) AND BUILT, 2026-09-07.** Four events, four sensations:
   a light tap on a key, a firmer one when a visit commits, and two deliberately distinct ones for a
   bust and for a leg won — the two things a player needs to know while looking at the board rather
   than at the phone. Off is offered in Settings under a key that is a contract with every install;
   default on. The mapping is asserted by a test rather than left as a comment, because "four
   different sensations" is the whole claim and three of them being the same would be silent.

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

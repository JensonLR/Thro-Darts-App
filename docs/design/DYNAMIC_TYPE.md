# The Dynamic Type contract

Commissioned by the founder as part of **PD-015**, drawn under PD-010's terms. Before this the app
already scaled — every type role in `ThroTypography` carries a `relativeTo:` text style, so
`Font.custom(_:size:relativeTo:)` grows the embedded faces with the player's setting — but nothing
stated what should happen at the top of the range, so the answer was whatever SwiftUI happened to do.

## The contract

| Surface | Ceiling | Why |
|---|---|---|
| Result, Settings, Clubs, a person's page, match setup, the confirm-result screen | `.accessibility5` (no cap) | They scroll. Nothing on them is harmed by being tall. |
| **The scoring screen** | `.accessibility1` | It is the one screen that must fit without scrolling, and it holds a keypad whose targets are already at the 44-point minimum. |

At `.accessibility5` body text is roughly three times its default size. On the scoring screen that
puts a hero numeral, a checkout card, a turn indicator and twenty keys into a space that cannot grow,
and something has to give.

## What was given up, and why

**A player who needs `.accessibility5` gets `.accessibility1` while scoring.** That is a real
accessibility limit and it is written down here rather than discovered.

The choice on that screen is between:

1. **A keypad that scrolls.** The player's thumb is on a key; the announcement of a bust pushes the
   layout; the next tap lands on a different number. A scoring keypad that moves under the hand is
   worse than one that is small, because a mis-key at the oche is a scoring error in an evidence
   journal rather than an inconvenience.
2. **Text that stops growing.** What this does.

The thing that would serve that player properly is neither: a scoring screen that **reflows** at
accessibility sizes — the upper region scrolling above a pinned keypad, or a single-column layout
with the remaining score and the keypad only. That is a screen the export does not draw, so it is a
**design commission**, not something engineering should invent. It is the next item on this contract
when somebody wants it.

## What holds it

`ThroDynamicType.scoringCeiling` and `throScoringTypeCeiling()` in `ThroDesign/Interaction.swift`.
`DesignTests` asserts the ceiling is the accessibility size named here, and that the reading ceiling
is genuinely above it — a ceiling that quietly became the same value everywhere would be this
contract failing in the direction that costs the most.

Two mechanisms were already in place and stay:

- `minimumScaleFactor(0.5)` on the hero numeral, so a 96-point face shrinks rather than clips on a
  short phone. That is a floor for small screens; this contract is a ceiling for large text. They
  are different problems and both are needed.
- `fixedSize(horizontal: false, vertical: true)` on every explanatory line, so a note that grows
  wraps rather than truncating. An honesty layer whose explanation is cut off at one line is an
  honesty layer that has stopped working.

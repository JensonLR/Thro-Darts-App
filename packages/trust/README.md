# thro-trust

Provenance, verification labels and rating eligibility. Pure Kotlin, no dependencies, no I/O.

## The one rule this module exists to enforce

**A trust label is derived from provenance, never stored beside it.** A stored label can disagree
with the facts underneath it; a derived one cannot. `VerificationState.of(provenance)` is a pure
function, and there is no setter.

## Two axes the design collapses into one

The approved `VerificationState` enum has eight labels, and two of them answer different questions:

| Label | Actually describes |
|---|---|
| `thro-recorded` | **how** the result was captured |
| `participant-confirmed` | **who** attested to it |

A match scored live in THRØ by one player, never confirmed by the other, is live-captured and
uncorroborated at the same time. So the domain keeps `CaptureChannel` and `Attestation` separate and
derives the design's single label from both — the approved surface is unchanged, and rating
eligibility is decided on the axis that actually bears on it. See OD-014.

## Eligible and qualifying

| | Means |
|---|---|
| **Eligible** | permitted to inform the rating model at all |
| **Qualifying** | counts toward *establishing* a rating — strictly narrower |

Qualifying is checked to be narrower exhaustively, across every combination of outcome type,
attestation, quarantine, dispute and opponent state.

**PD-002:** the minimum attestation for eligibility is `participant-confirmed`. One player's
unilateral claim never moves either rating. Self-reported results still progress the bracket, still
appear in the record, and are shown with honest provenance — they simply do not move the number.

Attestation counts **distinct competitors**. The player who entered the result confirming their own
entry adds no independent voice, and counting it would let one player manufacture participant
confirmation alone — the exact attack PD-002 closes.

## Quarantine is orthogonal

Quarantine suspends *eligibility* without accusation and without touching the verification label. It
is not a ninth state: overloading the enum would destroy the provenance underneath, and a device
fault triggers quarantine as readily as fraud. It is reversible, and a test asserts the label is
byte-identical with and without it.

## What is policy, not domain

OD-001 (the rating model) is open, so which outcome types feed it is `EligibilityPolicy`, not a
hardcoded predicate. The defaults are the conservative reading of PD-002 — `played` only — and a
policy that would let an outcome *establish* a rating it may not even *inform* is refused at
construction.

```bash
gradle -p packages/trust test
```

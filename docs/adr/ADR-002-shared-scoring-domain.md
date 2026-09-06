# ADR-002 — Shared deterministic scoring domain

**Status:** DEFERRED, with explicit criteria · **Spike run 2026-09-04, half of its exit condition met** · **Date:** 2026-09-03 (revision 2)

This is the single decision that forces a rewrite if made wrongly, which is why it is not being made
on the strength of an argument alone.

## Context

The scoring engine must produce identical results on iOS, Android and server validation. Two Gate 0
specialists reached opposite conclusions:

- The **mobile review** recommends three native implementations governed by a conformance corpus,
  with rule *data* generated into all three languages. It rejects a shared Kotlin core on toolchain
  burden, iOS debuggability, and the observation that agents debug Gradle and cross-compilation
  failures badly.
- The **backend review** recommends a shared Kotlin Multiplatform module, arguing it collapses the
  drift surface from three implementations to one.

Both are right about their own risk. Divergence in the *sequence-level* rules — throw order after a
set boundary, undo-after-checkout, correcting a visit three legs back — would be a **player-facing
integrity failure**, not merely a bug. Equally, a toolchain that blocks an iOS release during a
tournament weekend is a real operational risk for a one-person team.

## Decision

**Defer the choice. Build the common prefix now.**

Two things are prerequisites of *both* paths and are started immediately:

1. **A pure, dependency-free, value-typed engine module** — no floating point, no clock access, no
   randomness, no I/O, no exceptions for control flow. Integer arithmetic only. A small public API of
   immutable structs and enums, which keeps the interop surface trivial if a shared core is later
   adopted.
2. **The versioned conformance corpus** specified in
   [`../architecture/CONFORMANCE_CORPUS.md`](../architecture/CONFORMANCE_CORPUS.md). The corpus, not
   any shared code, is the contract — and it is what makes a later replacement provably correct.

## What this deferral honestly costs

The corpus is a genuine common prefix and is never wasted. The engine module is *mostly* common. The
**rule-table generator is not** — it is only needed on the three-implementation path. That is the
real, acknowledged cost of deferring, and it is small relative to choosing wrongly.

## The spike, actually defined

Revision 1's status line claimed "a defined spike" and then defined none — no scope, no owner, no
budget, no exit condition. Hostile review was right to call that a false claim about the document's
own contents. Defined now:

**Scope.** Port the pure engine module to a second platform behind the conformance corpus, and run
the corpus on both. Nothing else — no UI, no persistence, no networking.
**Exit condition.** The corpus passes identically on both platforms, and the cost of the *second*
rule change (not the first) is measured.
**Budget.** Two days. If the toolchain has not produced a passing corpus run in two days, that is
itself the answer.
**What it must not test.** Build times and debugger ergonomics. Those were the grounds on which a
shared core was rejected a priori, so measuring them again decides nothing.

## Spike result — 2026-09-04

**Ported.** `packages/engine-swift` is the pure engine in Swift, 218 lines of state machine, with
the rule tables generated into it by the same enumeration that produces the Kotlin tables. CI fails
on a stale generated copy, so no platform can drift by hand-editing its own checkout set.

**Corpus outcome — the exit condition, met:**

| | Kotlin | Swift |
|---|---|---|
| Hand-shaped corpus | 64 cases, 393 commands | 64 cases, 393 commands |
| Exhaustive transitions | 86,000 | 86,000 |
| Divergences | — | **0** |

The Swift engine passed the entire corpus on the first run that reached the compiler. Two defects
were found before that, and both are worth recording because neither was a scoring bug: enum cases
cannot carry default parameter values in Swift, and the exhaustive vector family has a different
shape from the rest of the corpus, which the first runner read wrongly.

### What this does NOT settle

The exit condition has two halves and this is one of them. **The cost of the *second* rule change
was not measured**, because no second rule change has happened. The spike therefore says the two
implementations *can* agree; it says nothing about what keeping them agreeing costs over time, which
is the thing that actually decides this record.

It is also the most favourable possible conditions for agreement: the Swift was written by reading
the Kotlin line by line, deliberately preserving even the order of its checks, because that order
decides the answer in several places. A port written from the specification instead of from the
other implementation would be a harder and more honest test — and is what the next rule change will
accidentally provide.

### Standing position

Neither kill criterion has fired: no divergence has reached a human-tested build, and the rule
surface has not grown past X01, sets and pairs. **Three native implementations stand**, with the
corpus as the contract, per the criteria below. That is the ADR's own answer to this evidence, not a
new decision.

One thing the spike did change: the rule-table generator, listed above as the acknowledged cost of
deferring, now emits Swift as well as Kotlin. That cost has been paid and is no longer hypothetical.

## Kill criteria — correctness, not ergonomics

The spike must test the thing that actually decides this, not re-litigate a settled argument. Build
time and debuggability are the grounds on which the mobile review already rejected a shared core;
measuring them again decides nothing.

**Migrate to a single shared core if either holds:**

- **two or more genuine cross-platform divergences reach a human-tested build**, or
- **the rule surface grows past X01 plus sets** (pairs, team formats, league variants, deciding-leg
  rules).

**Two honest problems with these criteria**, raised by hostile review and accepted:

*The second is already tripped.* ADR-012 models pairs and team fixtures now, and the corpus already
carries set structure. Read strictly, the criterion fires today. It is therefore restated as:
**the rule surface growing past X01, sets and pairs** — team fixtures being a competitor-resolution
concern (ADR-012) rather than a scoring-rule concern.

*The first is a lagging indicator.* It fires only once all implementations exist, which is when
migrating is most expensive. It is retained because there is no leading indicator available, but it
is deliberately paired with a **numeric threshold set now rather than later**: the divergence-alert
rate is instrumented from the first release, and **any** divergence in the first 500 rated matches
triggers the review, not two.

**Stay on three native implementations otherwise.** Under either outcome the corpus proves the
result correct, which is why it is built first.

## Consequences

- No implementation is blocked: engine work starts immediately under constraints both paths share.
- Every visit recorded from the first release is covered by the corpus, so no match carries unknown
  provenance.
- A divergence detector is available cheaply in production: every sync command carries the client's
  computed outcome and engine version, the server recomputes, and a mismatch appends the server's
  outcome and raises an alert. This turns the residual risk into a monitored metric.

## Revisit trigger

The kill criteria above, evaluated at every release. Also revisit if a fourth consumer appears (a web
scorer), in which case add a target to a shared core rather than a fourth hand-written implementation.

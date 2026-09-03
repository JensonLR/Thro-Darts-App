# ADR-006 — Offline sync protocol and scoring authority

**Status:** Accepted · **Date:** 2026-09-03

The highest-risk subsystem. Venues have poor signal; that is the premise, not an edge case.

## Client model

Local SQLite with two tables: an **append-only command journal** and a **rebuildable projection**.
The UI renders the projection; the projection is a fold of the journal through the same pure engine
the server runs. Recovery from process death is a journal replay, which is only viable because the
engine is pure (ADR-002).

**Durability rule, non-negotiable: the command is flushed to the journal *before* it is applied and
acknowledged.** Paint optimistically first; acknowledge only once durable. Rendering first and
persisting second loses a dart on any crash between, and the player will not notice until the scores
disagree with the board.

**Durability must be configured explicitly.** SQLite and Room default to a mode that survives process
death but **not power loss**. Losing an acknowledged competitive visit has no repair path, so the
setting is raised and validated with real kill tests and power-cut tests on device — not assumed.

The half-typed entry buffer is **UI draft state in a separate non-evidence table**. It must never be
foldable into the journal.

## Scoring authority — three mechanisms

A single writer is not sufficient on its own, because the approved dispute screen shows a per-leg
`Confirmed` column authored by the participant who scored nothing.

1. **A scoped offline scoring grant**, issued by the server at match-open — the moment the design
   already draws ("Both players must confirm before scoring opens"). Server-authored, device-held,
   and **valid without a network at scoring time**. This is what makes authority compatible with
   offline scoring rather than contradicting it.
2. **Per-device evidence streams**, gapless per `(aggregate, device)`, never discarded and never
   deduplicated across devices. Two streams for one match is *corroboration*; divergence is a dispute.
3. **Per-leg participant attestation** as a first-class event, authored by the non-scoring
   participant. This is what the `Confirmed` column reads from.

**The offline two-device case:** both players score the whole match offline. Reconcile at **outcome
level** — winner and per-player leg scores — not by digest equality, because a digest over a leg's
events makes a single mis-keyed-then-corrected visit mismatch on a leg both players agree about. Use
a visit-level diff only to *explain* a mismatch. This yields a whole-match-contested state that the
design does not currently draw (raised as a design commission).

**Offline matches remain self-reported until sync.** That is a recorded product consequence, not a
defect, and it feeds directly into founder decision B2.

**Peer-to-peer sync is not built in the first slice** — iOS and Android share only Bluetooth LE,
which costs a permission and a privacy declaration for no first-release benefit.

## Server algorithm — order matters, each step prevents a named failure

1. **Receipt lookup** on `(device, command_id)`. Hit returns the stored response verbatim, including
   a stored rejection.
2. **Authorise** — does this actor hold a current grant for this match?
3. **Gap check** on the per-device sequence. A gap is rejected with the expected value, never applied
   past.
4. **Rehydrate** and check the expected stream sequence.
5. **Revalidate against the rules engine.** Reject with a stable code: total not achievable, checkout
   not permitted for the out-rule, negative remaining, bust mishandled, wrong thrower, leg already won,
   match finalised.
6. **Compare the client's computed outcome.** A mismatch appends the server's outcome and raises an
   engine-divergence alert carrying both outcomes and both engine versions.
7. **Append**, relying on the unique constraint; retry the read-validate-append cycle on conflict.
8. **Write the receipt in the same transaction.**

**Never accept an asserted result.** A client cannot say "I won 5–3"; the server derives the outcome
from the visit stream. And the honest limit must be stated in the API contract: the server validates
that a claim is **rule-consistent**, never that it is what happened.

## Failure modes and their prevention

| Failure | How it corrupts a match | Prevention |
|---|---|---|
| Retried command applied twice | Phantom visit, wrong remaining | Receipt unique per device, written in the append transaction |
| Commands arrive out of order | Bust evaluated against the wrong total | Gapless sequence; server rejects gaps rather than applying past them |
| Process killed mid-visit | Lost visit; app disagrees with the board | Journal flush precedes acknowledgement |
| Client engine drifts from server | Player told they won a leg the server rejects | Conformance corpus in CI, plus per-command divergence detection |
| Device clock wrong or manipulated | Fraudulent backdating | Ordering by sequence; device time is evidence only |
| Stale journal replayed weeks later | Old commands applied to a finalised match | Grant expiry and a finalised-match rejection |
| Token expires offline | — | **Scoring is unaffected; auth is not on the scoring path.** On reconnect a 401 must not drop the queue, sign the user out, or clear local data |
| Rejected batch | Evidence destroyed | **Never discarded client-side.** Persist durably with the server's reason until resolved |

## Revisit trigger

Any evidence loss observed in the field; or divergence alerts firing more than negligibly, which
would trigger ADR-002's kill criteria.

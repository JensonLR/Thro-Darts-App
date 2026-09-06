# ADR-008 — Authentication and authorization

**Status:** Accepted (mechanism) · Blocked on founder decision B4 (surface) · **Date:** 2026-09-03

## Context

**No authentication surface exists in the approved design** — across all 42 screens there is a splash
button that routes nowhere and one settings row. The technical mechanism can be decided now; the
flows cannot be invented, and are raised as blocker B4.

## Authentication

**Passkeys as primary** — already the design's stated method — with platform sign-in on iOS and email
as bootstrap and fallback. Phone only as a secondary signal: SIM-swap makes it a poor sole recovery
factor for a competitive identity.

Short-lived access tokens; refresh tokens with **rotation and reuse detection**, so a replayed
refresh revokes the whole family. Platform secure storage only. **Identity in the token, never
permissions.**

**The offline scoring case drives an API shape.** A scorer at a venue with no signal must score for
hours, well past any sane access-token lifetime. Resolved by ADR-006's scoping grant, issued at
match-open and bound to device, match and validity window: the journal is authorised at open time and
submits later under a fresh token. **Recording evidence must never require interactive
authentication.**

**Device binding:** registered devices, a stable device id on every scoring event, per-device
revocation. Platform attestation is a **provenance input** — an attested device produces stronger
evidence — never a gate, since it is bypassable and fails legitimate users.

## Authorization — relationship-based, from the first commit

One person in the approved design is simultaneously tournament director, captain, listed player and
venue scorer. Permissions sit *below* the event (scorers are assigned to individual boards) and roles
are season-bounded. A global role column, or roles embedded in the token, forces a rewrite of every
endpoint on day one.

**Model:** relationship tuples over objects — organisation, league, season, division, team, event,
draw, match, board, venue, player — with relations such as `event#organiser`, `board#scorer`,
`match#participant`, `team#captain`, `player#guardian`.

**The rule that constrains the engine choice:**

```
match#can_correct = event#official BUT NOT (match#participant ∪ participant's team)
```

That negation is the conflict-of-interest rule, and naive role-based access control cannot express
it. Organiser conflict of interest is not hypothetical here — it is structurally certain, because the
same people organise and play.

**Engine: relationship tuples in Postgres, evaluated by a single in-process decision point.** Not a
dedicated authorization service. A separate engine would add a second datastore and a second
durability domain against ADR-003's central argument, and the relation set here is small and
slow-changing. The negation the conflict-of-interest rule needs is a query, not a product feature.

**The cost of that choice, stated:** recursive relation resolution on every request, inside a 150 ms
command budget. Mitigated by caching a subject's resolved relations for a **short, explicitly bounded
window (30 seconds)**, invalidated eagerly on any role-change event. That window is the honest
version of "permissions are never carried in the token" — they are not carried by the *client*, which
is the property that matters, and a 30-second server-side cache is bounded and revocable in a way a
token is not.

**Enforcement:** one central decision point resolving `(subject, action, object)` before any handler
runs, deny by default, no ambient admin bypass. **Permissions are resolved per request, never carried
in the token**, or a removed organiser keeps power until expiry.

**The highest-value attack is cross-match evidence injection:** post a leg event carrying a stranger's
match id and you move a stranger's rating. Every event is validated against the aggregate's own
participant set, **loaded from the store** — never against ids in the request body. List endpoints are
the other leak and must filter on the caller's relation, not on a client-supplied identifier.

**Hidden UI is never sufficient.** Both clients are native, the API is the real surface, and
offline-first *requires* the client to contain the complete command vocabulary in order to construct
valid events with no server present. Hiding an action removes a hint, not a capability.

## The offline grant is a bounded exception

ADR-006 issues a device-held scoring grant valid without a network. That is, precisely, a permission
carried on the client — the thing this record otherwise forbids. It is an exception, not an
oversight, and it is bounded: it authorises **recording evidence only**, never reading another
player's data, never an organiser action. Evidence recorded under a revoked grant is accepted and
flagged for review rather than trusted or destroyed. See ADR-006 for lifetime and revocation.

## Age as an authorization dimension

An age band is a **first-class authorization attribute from the first account**, available at every
read and write decision, with a guardian relation in the graph. This is the retrofit-killer:
visibility rules written without an age dimension mean re-auditing every endpoint and every public
page later. The *policy* — declared date of birth, band, or verified assurance — remains a founder
decision; the field and the dimension do not wait for it.

## Audit

Every granting decision on a mutating competitive or personal-data action records subject, object,
the relation that granted it, and the policy version, into an append-only hash-chained log with its
own retention and a restricted read path. When a fraud allegation arrives fourteen months later,
"who could have done this, and who did?" must be answerable.

## Revisit trigger

B4 answered, which will settle enrolment, recovery, re-authentication and the identity-claim flow; or
a second organisation type appearing that the relation vocabulary cannot express.

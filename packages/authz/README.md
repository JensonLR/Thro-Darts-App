# thro-authz

Relationship-based authorization. Pure Kotlin, no dependencies, no I/O.

## Why not roles

One person in the approved design is simultaneously tournament director, captain, listed player and
venue scorer. Permissions sit **below** the event — a scorer is assigned to an individual board, not
to a competition — and roles are season-bounded.

The rule that settles it:

```
match#can_correct = event#official  BUT NOT  (match#participant ∪ participant's team)
```

In darts the same people organise and play, so an official who is also a competitor in the match
they would adjudicate is the ordinary case, not an edge case. A role column stores the permission
against `(subject, role)` and has nowhere to put the difference between Dana's own match and
everyone else's — so it must either let her correct her own result or stop her doing her job at all.

A test asserts exactly that: same subject, same action, **identical granting relation**, opposite
answers, with only the object different.

## The algebra

Four constructs, and no more. This is the one point in the system where being wrong hands someone
else's authority away, so it is small enough to hold in your head.

| | |
|---|---|
| `Direct` | the subject holds the relation on this object |
| `Inherited` | …on one of its ancestors — how `event#official` reaches a match |
| `AnyOf` | union |
| `Except` | base **minus** exclusion — the negation RBAC cannot express |

## Properties held

- **Deny by default.** An action with no rule is denied. A stranger is checked against every action
  on every object and holds nothing.
- **No ambient administrator bypass.** An organisation owner is a subject with tuples like anyone
  else; a test gives one every relation name it does not need and confirms it grants nothing.
- **Exclusions follow the team.** A conflict one indirection away — the official's *team* is playing
  — is still a conflict.
- **Denials explain themselves.** A decision carries both the relation that granted it and the one
  that withdrew it, because "you are an official here but you are also playing in this match" is the
  only operable thing to tell someone. A bare 403 is not.
- **Cycles terminate**, and an object with no parents inherits nothing.

## Age is a dimension, not a policy

ADR-008 calls this the retrofit-killer: visibility rules written without an age dimension mean
re-auditing every endpoint and every public page later. So `SubjectAttributes` is a parameter of
**every** decision rather than a lookup inside some of them, and attaching an age requirement to an
action later needs no change at any call site. A test asserts exactly that.

Only the minor/adult distinction is modelled, because it is the one every safeguarding regime
shares. The thresholds, the evidence that establishes them, and what each unlocks are **OD-010** —
to be researched against primary sources. Nothing here is a legal conclusion, and **no action
carries an age requirement by default**: inventing restrictions while that decision is open would be
as wrong as omitting the dimension, in the opposite direction.

`UNKNOWN` is a band, never an absence. A nullable band is one that gets forgotten in a condition; an
explicit unknown has to be handled, and is handled as the most restrictive case — the safe direction
when what you do not know is whether you are dealing with a child. An age requirement is always a
further restriction and never a substitute for a relationship.

## Not in here

Permissions are resolved per request and never carried by the client or embedded in a token — a
removed organiser who kept power until token expiry is a live authority the system believes it has
revoked. ADR-006's offline scoring grant is the one bounded exception, and it authorises *recording
evidence* only: never reading another player's data, never an organiser action.

```bash
gradle -p packages/authz test
```

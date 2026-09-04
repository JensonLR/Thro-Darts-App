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

## Not in here

Permissions are resolved per request and never carried by the client or embedded in a token — a
removed organiser who kept power until token expiry is a live authority the system believes it has
revoked. ADR-006's offline scoring grant is the one bounded exception, and it authorises *recording
evidence* only: never reading another player's data, never an organiser action.

```bash
gradle -p packages/authz test
```

# ADR-015 — Notifications

**Status:** Accepted · **Date:** 2026-09-03

## Context

This is a competitive-integrity surface, not a growth one. **A missed "match called" causes a
forfeit.** The approved design promises `Match called · Always on` and mutes everything else while a
player is called — so the priority model is already a design commitment, not a preference.

The design defines **seven notification classes** and Settings exposes **four toggles**. Those do not
map one-to-one, and no record said how they should.

## Decision

### Classes, and what each is allowed to do

| Class | Example | Delivery |
|---|---|---|
| **Action required** | Match called; check-in closing | Highest interruption the platform allows; **not user-suppressible below "on"** |
| **Live** | A followed player is now playing | Standard, user-controlled |
| **Information** | Draw published; result confirmed | Standard, user-controlled |
| **Opportunity** | An event matching your level opens | Standard, off by default |
| **Development** | A new coaching insight | Standard, off by default |
| **Social** | A new follower | Standard, off by default |
| **Milestone** | A personal best | Standard, user-controlled |

The four settings toggles map to groups, not classes: **Match and competition** (action required +
information), **Live**, **Development** (development + opportunity), **Social**. Milestones follow
Live. This is the mapping the design's four toggles imply; it is written down here so the seven
classes cannot quietly drift.

### "Always on" is a promise the platforms may refuse

Neither platform guarantees delivery, and both allow a user to disable a channel entirely. The design
says "Always on"; the honest reading is **THRØ never suppresses it**, not that the OS never does.

Therefore **push is a notification, never the mechanism**. A called match must be discoverable
without it:

- The Home "match called" state is authoritative and is reached by opening the app.
- The realtime stream carries the call, so a foregrounded app shows it with no push at all.
- The organiser sees an unacknowledged call and can act — the design already surfaces
  "result outstanding" timers, and the same applies to calls.

**A forfeit must never be caused by an undelivered push**, which means the organiser's calling flow
needs an acknowledgement state rather than fire-and-forget. That is a product requirement this record
surfaces rather than resolves.

### Payload rules

**Push payloads carry notification, never competitive evidence.** A payload names the event and the
board; it never carries a score, a result, or anything that could be replayed as evidence. It also
must not name a venue or a player for an under-18 account — a lock-screen notification is a
disclosure, and it is visible to anyone holding the phone.

### Delivery record

Every send is recorded with class, target, dispatch time, and provider response. Delivery cannot be
guaranteed, but **whether THRØ tried** must be answerable — a forfeit dispute will ask it.

## Requires verification at implementation time

The interruption level required for a time-critical call, the entitlement it needs, and current
review expectations for it, on both platforms. Also the current behaviour when a user has disabled a
channel that carries an action-required notification. These change, and they are not guessed here.

## Revisit trigger

Any forfeit attributable to a notification not arriving; or either platform changing its
interruption-level policy.

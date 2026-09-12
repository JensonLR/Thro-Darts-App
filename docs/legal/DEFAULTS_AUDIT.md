# High-privacy defaults, surface by surface

**ICO *Age appropriate design code*, Standard 7:** *"Settings must be 'high privacy' by default
(unless you can demonstrate a compelling reason for a different default, taking account of the best
interests of the child)."*

The DPIA left this open with a one-line instruction to itself: *"Needs an audit of every public
surface for high-privacy defaults, one screen at a time."* This is that audit, done on
**12 September 2026** against the code as committed.

**How to read a verdict.** Every row says how it was checked, not that it was checked. Where the
answer is "high privacy", the interesting question is *what makes it stay that way* — a default that
holds because nobody has got round to lowering it is not a default, it is a delay. Two of the
strongest properties here were held only by a comment when the audit started; one now has a guard
and the other has a test, and those are the two real outputs of the exercise.

---

## 1. Is a person ever named to somebody who is not signed in?

**No, and it takes two independent things to change that.**

The public routes are declared, not discovered: `Api.kt` marks each endpoint `authenticated = true`
or `false`, and the unauthenticated ones are the sign-in routes plus four reads —
`GET /v1/teams/{teamId}`, `GET /v1/venues`, `GET /v1/leagues`, `GET /v1/seasons/…/fixtures`,
`GET /v1/seasons/…/standings` and `GET /v1/events`. Of those, only a team's front has anything to do
with people: it carries a **roster**.

A roster names somebody only when `identity.player_may_be_disclosed` says so, and that function
(V016) requires **both**:

1. a live claim tying that player to an account that has not been deleted, **and**
2. a consent record that is either `basis = 'guardian'`, or `basis = 'self'` **and** the account's
   `age_band = 'adult'`.

An account is created with `age_band = 'unknown'` and `age_assurance = 'none'` — those are the
column defaults in V011 — and there is no self-consent path for an unknown band. So a new account is
never nameable, and **an unknown age behaves as a minor here without any code saying "minor"**,
which is the shape you want: the rule is not a special case that can be forgotten, it is what falls
out when neither branch is satisfied.

Everybody else on a roster is **counted and not named**. `TeamsTest` holds it —
*"a team is started, filled by code, and names only those who may be named"*.

**One thing found while auditing, and it is worth writing down.** `Secretary.recordConsent` is the
only code in the repository that writes a consent record, and it has **no production caller** — the
secretary module is built but not yet routed over HTTP. So today `player_may_be_disclosed` answers
false for every player alive, and no roster names anybody at all. That is not a Standard 7 failure;
it is the maximally private state. It is recorded here because of what it implies for the route that
will eventually exist: **recording consent must be a thing a person does on purpose, never a side
effect of joining a team.** If entering a team code ever writes a consent record, this entire
section becomes untrue in one commit and nothing would fail.

## 2. The pub television

The Apple TV app is the most exposed screen THRØ has: nobody owns it, nobody signs out of it, and
whoever picks up the remote is the operator. What makes it safe is not a rule about what it draws —
it is that **it holds no credential**, so it can only read the routes in §1, and those name teams and
venues and never a person.

That was a comment. It is now `tools/check_the_wall_never_signs_in.py`, which refuses any mention of
a session store, a token, the keychain, or the authenticated match stream anywhere in
`ThroVenueKit`. The guard was verified by breaking the wall on purpose — adding a `SessionStore` to
`Wall.swift` — and confirming it failed, before restoring the file.

**The open decision, stated as a decision rather than a gap.** `stream.match` is authenticated, so
the wall cannot show a **live leg**, and that is deliberate: *an under-18 fixture named on a pub wall
is a safeguarding question, not a plumbing one.* Somebody has to decide it before it is built. A
room that wants a live board today gets it the way PD-041 already provides — the phone, by cable or
AirPlay, where a person is present and answerable for the screen.

## 3. Location

**Off until pressed; one fix; never written; forgotten on leaving.** Met at PD-086, which also added
the sign while it is in use and the Stop beside it, because Standard 10 asks for both. Nothing in
this audit changes it. The ROPA's row for location reads *"Categories of data: none stored"*.

## 4. Every stored preference in the phone app

There are eight, and they were listed by reading every `@AppStorage` in the iOS sources rather than
from memory:

| Preference | Default | Privacy-bearing? |
| --- | --- | --- |
| Appearance | System | No — a display choice (PD-003). |
| Keep the screen awake while scoring | On | No. |
| Entry mode (visit or dart) | Visit | No. |
| Haptics | On | No. |
| Opening sound | On | No. |
| Opening haptics | On | No. |
| **Spotlight indexing** | **On** | **Yes — assessed below.** |
| **Diagnostics** | **Off** | **Yes — and off is the right default, which it already is.** |

**Spotlight, on by default, and the argument for it.** Standard 7 allows a different default where
there is a compelling reason in the child's interests. The case here rests on three checkable facts,
each of which was checked in `Spotlight.swift`:

- **Nothing leaves the device.** The app writes to `CSSearchableIndex` only. It never donates an
  `NSUserActivity`, and `isEligibleForPublicIndexing` — the flag that would send a title to Apple —
  appears nowhere in the codebase. (Grepped; it does not.)
- **It indexes nothing the phone does not already show.** A match's title is the two names already
  on Home; a person is somebody already typed into this phone; a club is already in the club book.
  Turning it on adds reachability, not information.
- **Turning it off removes what was indexed**, rather than only stopping new writes. A switch that
  left the old entries behind would be a switch that lies, and the code deletes by domain before it
  decides whether to write.

The residual is real and should be said: on a shared family iPad, a match title in Spotlight can be
read by somebody who would not have opened the app. That is an argument for the switch being easy to
find, not for a search feature that starts broken. **Verdict: compelling reason demonstrated, and
the three facts above are what makes it demonstrable rather than asserted.**

**Diagnostics off** is the one preference where the high-privacy default was a choice somebody had
to make and did make correctly.

## 5. What a person can send out of the app

**The share card** is the only surface that leaves the phone, and its default is that it does not:
nothing is rendered until a person presses share, nothing is uploaded, and the card is drawn on
device. THRØ cannot age-gate it, because the two names on it were typed into this phone and THRØ has
never been told whose they are — which is itself the minimisation working, and is why the guidance
about a child's name belongs to the person pressing the button. The safeguarding rule for THRØ's
*own* accounts is written down at `docs/product/PRESENCE.md`: an unknown age is a no.

**The export** (PD-017) goes where the player sends it and carries every row as written, including
each club member's age band. That is correct for a subject-access export and would be wrong for
anything else; nothing else uses that path.

## 6. Teams and venues default to public

`competition.team.visibility` and `competition.venue.visibility` both default to `'public'`
(V014). Considered and **left as they are**:

- Nothing on either row is a person. A team row is a name, a short name, a locality and a founded
  year; a venue is a pub. The schema comment says so and the audit confirms the columns.
- A league's published competition being public is the product (PD-054, PD-056) — a fixture list
  nobody can read is not a fixture list.
- The personal part of a team — who is in it — is §1's gate, and that is private by default
  regardless of the team's own visibility.
- A team or venue marked private is not named at all on a public route, and a private team answers
  404 to anyone not in it.

## 7. Announcements, and who does not get one

An announcement reaches nobody recorded as a minor **or of unknown age**. The unknown case is the
load-bearing half, and it is the same shape as §1: the rule is written so that the absence of
knowledge is a refusal rather than a permission.

## 8. Android

`packages/client-android` has **no network code at all** — the package graph contains nothing that
speaks HTTP, which is the same structural enforcement the iOS client uses for its own offline claim.
Its one persisted preference is a journal device id, a random UUID written once into
`MODE_PRIVATE` shared preferences, and the code comment is explicit that it is deliberately *not*
the hardware identifier: it says which device wrote a row, not which person is holding it.

---

## What this audit changed

1. `tools/check_the_wall_never_signs_in.py` — §2's property was a comment and is now a guard,
   verified by breaking it.
2. This document, which is the Standard 7 line item in the DPIA.

## What it deliberately did not change

Nothing else. Every default examined was already the private one, and the audit's value is in §1's
note about the consent route that does not exist yet and §2's decision that has not been made yet —
both of which are places where the *next* commit is the risk, not this one.

## The one decision still owed

**May a live leg be shown on a public screen, and under what conditions?** Not built, deliberately.
The question is not technical: it is whether a named under-18 fixture may appear on a pub wall, and
if the answer is "only when every player on it is a confirmed adult", then THRØ needs a way to know
that — which today it does not, because §1's consent route does not exist. The two are the same
piece of work.

---

*Audited against the code committed on 12 September 2026. Re-run it when the consent route lands,
when the live board is decided, or when a new preference is added — those are the three things that
can make any of the above untrue.*

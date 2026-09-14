# thro-organisation

Teams, leagues and tournaments: the bodies a player belongs to, their branding, and the boundary a
communications feature cannot cross until the safeguarding question is answered.

The founder asked for clubs and leagues to customise, hold their own data, and become a hub where a
club can reach its members and arrange things. This package is the part engineering can build without
inventing product.

## What is here

| | |
|---|---|
| `Organisation.kt` | A team, league or tournament as one type with a kind (`TEAM` was `CLUB` until ADR-017 / PD-028 — the standing organisation is the Team whatever it calls itself); membership with three roles; and the whole authority surface stated as data, so an action cannot acquire an authority nobody granted it |
| `Branding.kt` | A club's accent, measured rather than trusted — the text on it is chosen, and a sweep of the colour cube proves no choice a club can make falls below the contrast floor |
| `Communications.kt` | Announcements: broadcast, from a role, to a membership, with an author. A member whose age is minor **or unknown** receives nothing until OD-010 is answered |
| `Fixtures.kt` | A date, two sides, a venue, a state. No result: that belongs to the match aggregate and its provenance |

## The two guarantees worth knowing

**A club cannot make the app unreadable.** The accent is never used to set text unless it passes
contrast there too, and the text that sits *on* the accent is chosen — whichever of the brand's two
neutrals reads better against it. That turned out to be a stronger promise than "we will refuse a bad
colour": because the brand's neutrals sit 17.4:1 apart, near the ends of the luminance range, the
worst any colour can do against the better of them is 4.17:1. Nothing a club picks can fall below the
3:1 floor. The refusal in `Branding` stays as a guard on the *palette*, and a test asserts the
headroom, so the day the neutrals move towards each other is the day a test says so rather than the
day a club sees an unreadable page.

**An app shipped with no answer cannot message a child.** `CommunicationPolicy.undecided` is the
default, and while it holds, every member whose band is `MINOR` or `UNKNOWN` is withheld with the
reason on the record. Unknown is treated exactly as minor, because the thing not known is whether
this is a child. Member-to-member messaging is not built at all — see OD-017 for why building the
data model first would prejudge the controls.

## What is not here, and why

- **Persistence.** No migration, no schema. The shapes above are settled; what is stored *about an
  announcement* — how long, who may delete it, whether an official can read one back — is OD-017,
  and a schema written before that answer is a schema written twice.
- **Screens.** The design export draws no club, league, tournament or profile screen.
  `docs/design/DESIGN_UNSPECIFIED.md` says none of these may be invented by engineering; they are B3.
- **Identity.** A `PersonId` here is an opaque handle. Who a person is, and how they prove it, is B4.

## Running it

```bash
gradle -p packages/organisation test
```

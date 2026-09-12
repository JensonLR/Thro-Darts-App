# Record of processing activities

**UK GDPR Article 30.** Required at this size because THRØ processes children's data and special-category-
adjacent risk is present, so the small-organisation exemption in Art 30(5) does not apply.

**Status: a draft written from the schema, for the founder to adopt and a solicitor to check.** Every row
below was read out of the live migrations rather than described from memory, and the date it was read is at
the foot. Nothing here is legal advice.

| | |
| --- | --- |
| **Controller** | *(the founder / trading name — to complete on ICO registration)* |
| **Contact** | `privacy@thro.uk` *(not live yet — see `docs/product/MAILBOX.md`)* |
| **DPO** | Not required at this size. The contact above answers instead. |
| **EU representative** | **Not appointed.** Required under Art 27 if EU users are targeted — see the DPIA's open items. |

## What is held, and where

THRØ's shape is unusual and it is the first thing an assessor should be told: **there is no email address,
no phone number, no postal address and no date of birth anywhere in the system.** That is not a claim about
policy, it is a claim about the schema, and it was checked by querying every column in every schema for
those names. The only postcode is a **venue's** — a pub's address, which is not personal data about a
player.

### 1. Accounts and sign-in

| | |
| --- | --- |
| **Purpose** | To let a person be the same person across devices, and to let a result be attributed. |
| **Lawful basis** | Contract (Art 6(1)(b)) for the account itself. |
| **Categories of data** | `account_id` (a UUID THRØ generates), `display_name` (typed by the person), `age_band` (`unknown` / `minor` / `adult`), `age_assurance` (`none` / `self_declared` / `guardian_declared` / `verified`), `consent_basis` (`self` / `guardian` / `none`), `created_via`, `user_handle` (an opaque WebAuthn identifier), timestamps. |
| **Sign-in credentials** | For Apple or Google: the **provider's subject identifier only** — a pseudonymous string specific to THRØ. THRØ asks for no email, no name, no profile. For a passkey: a public key and a signature counter. Tokens are stored **hashed**. |
| **Data subjects** | Players, including children. |
| **Recipients** | Apple and Google, as identity providers, at the moment of sign-in only. |
| **Retention** | Until erasure is requested. `identity.erasure` records what was removed. |
| **Transfers** | Hosting in the EEA (Frankfurt). See "Processors". |

### 2. Matches and results

| | |
| --- | --- |
| **Purpose** | To keep a record of darts played, and to compute a league table from results. |
| **Lawful basis** | Contract (Art 6(1)(b)). |
| **Categories of data** | Match records (the two names typed, format, times), visits (a total per throw and the darts where entered), retractions, attestations, endings. On the phone this lives in the on-device journal; uploaded matches also live on the server. |
| **Note on names** | A match may name somebody who has no account — the person typed at the start. ADR-016 records who a name referred to *where the device knows*; null is normal. |
| **Retention** | Indefinite while the account exists, because a result is a record of something that happened. Erasure removes it. |

### 3. Leagues, teams and fixtures

| | |
| --- | --- |
| **Purpose** | To publish a league's own competition: its teams, fixtures, results and table. |
| **Lawful basis** | Legitimate interests (Art 6(1)(f)) for publishing a league's own published competition; contract for a player's membership of a team. |
| **Categories of data** | Team membership, roles, fixtures, results, venues (including a pub's postcode and coordinates). |
| **Public exposure** | The public routes name **teams and venues, never people**, and a team or venue marked private is not named at all. A member recorded as a minor is never listed to anyone but an admin. |
| **Retention** | While the league exists. |

### 4. Safety: reports, blocks and decisions

| | |
| --- | --- |
| **Purpose** | To let a person report another and to act on it; to let a person block another. |
| **Lawful basis** | Legal obligation and legitimate interests — the safety of users, including children. |
| **Categories of data** | `report` (who reported, about whom or what, the reason), `block` (who blocked whom, and when it was lifted), `decision` (the outcome, a note, who decided). |
| **Special category risk** | A free-text reason or note **may** contain special-category data, because a reporter writes what they think matters. This is the highest-risk store in the system and the DPIA treats it as such. |
| **Retention** | **Two years after the report is decided** (PD-087), swept daily by the server. An undecided report is kept indefinitely — deleting one would hide that nobody answered it. What survives a forgotten report is a count of decisions by outcome against the subject, with no text and no reporter. |

### 5. Location

| | |
| --- | --- |
| **Purpose** | To order leagues and venues by how far away they are. |
| **Lawful basis** | Consent (Art 6(1)(a)), given by pressing "Use my location". |
| **Categories of data** | **None stored.** One coordinate is read into memory when asked for and used to sort a list. It is never written to disk, never sent to the server, and forgotten when the screen is left or Stop is pressed. Distances are computed on the device from venue coordinates the server publishes. |
| **Retention** | None. |

### 6. Pictures

| | |
| --- | --- |
| **Purpose** | Club and team badges. |
| **Categories of data** | An image, stored on the device. **Location metadata is stripped at intake** and proved stripped by a test that builds a real JPEG carrying GPS, puts it through the same path, and reads the bytes back. A picture is refused for a minor at the point of writing. |

## Processors

| Processor | What for | Where |
| --- | --- | --- |
| Render | Hosting the API | Frankfurt (EEA) |
| Neon | The PostgreSQL database | *(region to confirm on the account)* |
| Apple, Google | Identity providers at sign-in | Their own terms |
| *(mail host — to be chosen)* | The `privacy@` / `safeguarding@` mailbox | See `docs/product/MAILBOX.md` |

Written processor terms under Art 28 are **outstanding** for each of these and are on the founder's list.

## Technical and organisational measures

- Tokens stored hashed; passkeys hold a public key only.
- Every request runs under a PostgreSQL role (`SET ROLE` per request), so a bug in one area cannot read
  another's tables. Personal data lives in the `identity` schema and match, trust and rating cannot read it.
- Age is a parameter of every authorisation decision, and **an unknown age is never treated as an adult**.
- The on-device journal is append-only, enforced by database triggers on both iOS and Android.
- Erasure is a route (`DELETE /v1/me`) and records what it removed.

---

*Read from the migrations and the live schema on 12 September 2026. Re-read it before filing anything: the
schema moves.*

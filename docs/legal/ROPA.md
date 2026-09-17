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

THRØ's shape is unusual and it is the first thing an assessor should be told: **there is no phone number, no
postal address and no date of birth anywhere in the system, and no email address for any player or child** — the
one email held is an adult organiser's, given by them so the teams in their league can reach them (PD-104, V049,
16 September 2026). That is not a claim about
policy, it is a claim about the schema, and it was checked by querying every column in every schema for
those names. The only postcode is a **venue's** — a pub's address, which is not personal data about a
player.

### 1. Accounts and sign-in

| | |
| --- | --- |
| **Purpose** | To let a person be the same person across devices, and to let a result be attributed. |
| **Lawful basis** | Contract (Art 6(1)(b)) for the account itself. |
| **Categories of data** | `account_id` (a UUID THRØ generates), `display_name` (typed by the person), `age_band` (`unknown` / `minor` / `adult`), `age_assurance` (`none` / `self_declared` / `guardian_declared` / `verified`), `consent_basis` (`self` / `guardian` / `none`), `created_via`, `user_handle` (an opaque WebAuthn identifier), timestamps; and for an adult who runs a league or a team, an optional `contact_email` with the hour it was given (PD-104), shown only to the season's administrators and the admins of its accepted teams, removable, erased with the account. |
| **Sign-in credentials** | For Apple or Google: the **provider's subject identifier only** — a pseudonymous string specific to THRØ. THRØ asks for no email, no name, no profile. For a passkey: a public key and a signature counter. Tokens are stored **hashed**. |
| **Data subjects** | Players, including children. |
| **Recipients** | Apple and Google, as identity providers, at the moment of sign-in only. |
| **Retention** | Until erasure is requested. `identity.erasure` records what was removed. |
| **Transfers** | The database is in **London**; the API compute is in **Frankfurt** (Render, EEA) or London (Fly, per `DEPLOY.md`). **Render's own terms provide for transfer to the US all the same**: its DPA (§6.1, last modified 19 Dec 2024) says Render's primary processing operations take place in the United States and that transfer there is necessary to provide the service — made under the EU-US Data Privacy Framework or, failing that, the EU standard contractual clauses, with a UK Addendum (its Exhibit D); Render's trust page says it is certified under the Data Privacy Framework including the UK Extension. Requests also reach Render through Cloudflare's network first (see "Processors"). Read 13 Sep 2026; whether this suffices is for the solicitor. |

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
| **Retention** | **Two years after the report is decided** (PD-087), swept daily by the server. An undecided report is kept indefinitely — deleting one would hide that nobody answered it. What survives a forgotten report is a count of decisions by outcome against the subject, with no text and no reporter. **Not yet working in production (13 Sep 2026):** since V044 reached production that day, the sweep has failed at every server start with *permission denied for table decision_tally* — the function runs with the server's own rights, which do not reach the tally. Production held no reports when this was found, so nothing has yet been kept past the period. V047 (PD-096) fixes it, and takes effect when the deploy pipeline next migrates production. |

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

## Walk-up entrants (PD-124)

| | |
| --- | --- |
| **What** | A name an event's organiser types for somebody at a knockout who has no account: `competition.guest.name`, with the organiser's tick that the person is an adult happy to be named publicly. Nothing else about them. |
| **Whose** | People who have no account and have agreed to nothing in the app; possibly under 18, which is why the name is shown to the organiser alone unless the organiser attests otherwise. |
| **Basis** | Legitimate interests: running the draw the person walked up to enter. |
| **Who sees it** | The event's organiser. The public event page only with the organiser's attestation; otherwise *A guest*. |
| **Retention** | **Thirty days after the event's session ends**, then set to null by `competition.forget_guests()` (security definer, a thirty-day floor), swept daily by the server. The entry and the result stay, unnamed. Sooner on request to the organiser or to THRØ. |

## Processors

| Processor | What for | Where |
| --- | --- | --- |
| Render | Hosting the API | Frankfurt (EEA) for the compute. **Requests reach it through Cloudflare's network first**: the hostname resolves through `cdn.cloudflare.net`, and a test request on 13 Sep 2026 was answered by Cloudflare's London data centre (`server: cloudflare`, `cf-ray … -LHR`). A proxy answering at that layer ends the encrypted connection at its edge, so each request's contents pass through Cloudflare on the way. Render is a US company whose DPA provides for transfer to the US — see *Transfers* above |
| Render (static site) | Serving the public web pages, and `notice.json`, which the iPhone and Android apps read at launch and on returning to the front to learn whether there is a notice about people's information (PD-094, PD-097). The request carries nothing about the person; the host sees the internet address it came from, as for any page | **Cloudflare's network, in front of Render** — checked 13 Sep 2026: responses carry `server: cloudflare`, and a test request was answered by Cloudflare's London data centre (`cf-ray … -LHR`); Cloudflare answers each visitor from a data centre near them. On a cache miss the edge fetches the page from Render's origin, **whose location Render's static-site documentation does not give**, and that documentation describes no region setting. Render's DPA sends its sub-processor list to its trust page, which names AWS, Google Cloud, Cloudflare and ClickHouse, each a US entity (read 13 Sep 2026); the transfer terms are under *Transfers* above |
| Neon | The PostgreSQL database | **London (`aws-eu-west-2`)** — read from `docs/runbooks/DEPLOY.md`. That is where the data is stored; Neon's own processor terms have not been read, so whether a transfer question arises is not yet checked. |
| Apple, Google | Identity providers at sign-in | Their own terms |
| TypeSafe | Reading each report, and each chosen name, with its System One model (PD-118): the words of the report, the name reported and what kind of thing it is, and the chosen name — **no account id, no device, no reporter** — sent over HTTPS with THRØ's key; the answers (a category, two probabilities, a severity) are kept beside the report. Nothing is sent until `THRO_TYPESAFE_API_KEY` is set on the server. | **Not yet read**: TypeSafe's terms, its DPA and where it processes are to be read by the founder before the key is set (PD-118 lists the steps). Until then this row describes what the code does, not a transfer that has happened. |
| *(mail host — to be chosen)* | The `privacy@` / `safeguarding@` mailbox | See `docs/product/MAILBOX.md` |

Written processor terms under Art 28, as of 14 Sep 2026:

- **Render — obtained.** The founder requested Render's GDPR DPA from its trust page (*Request Documents*) and holds the copy. It says it supplements Render's Terms of Service; whether that suffices or a signed copy is needed is for the solicitor.
- **Neon — part of its terms, copy to keep.** Neon says its DPA is embedded in its terms of service, and publishes it at `neon.com/pdf/DPA.pdf` for download and separate signature; transfers rest on the Data Privacy Framework. The founder is to save the PDF. Whether acceptance through the terms suffices is for the solicitor.
- **The mail host — outstanding** until one is chosen (`docs/product/MAILBOX.md`). A personal Gmail account used as the inbox would come under no business processor terms.

## Technical and organisational measures

- Tokens stored hashed; passkeys hold a public key only.
- Every request runs under a PostgreSQL role (`SET ROLE` per request), so a bug in one area cannot read
  another's tables. Personal data lives in the `identity` schema and match, trust and rating cannot read it.
- Age is a parameter of every authorisation decision, and **an unknown age is never treated as an adult**.
- The on-device journal is append-only, enforced by database triggers on both iOS and Android.
- Erasure is a route (`DELETE /v1/me`) and records what it removed.

---

*Read from the migrations and the live schema on 12 September 2026; the transfers, the retention sweep and both Render
rows checked against production on 13 September 2026. Re-read it before filing anything: the schema moves.*

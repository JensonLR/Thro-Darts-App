# Data protection impact assessment

**Why there is one.** THRØ is likely to be accessed by children, which brings it under the ICO's *Age
appropriate design code*, and the code expects a DPIA. Under Art 35 the trigger is independent: THRØ
processes children's data at scale on a public service, and a rating that scores people is planned.

**Status: a draft, written from the code, for the founder to adopt and a solicitor to check.** Everything
factual here was read out of the schema and the source rather than described from memory. It is not legal
advice. What it is good for is that the *facts* in it are true, which is the part a solicitor cannot check
for you.

---

## 1. The processing, described

**What THRØ is.** A darts scoring app. A person scores a match on their own phone; the record is kept on
that phone; some people sign in, join a team, and let a league publish results.

**The shape that matters, and it is unusual.** There is **no email address, no phone number, no postal
address and no date of birth anywhere in the system.** Checked, not asserted: every column in every schema
was queried for those names, and the only postcode is a **venue's** — a pub's address. Signing in with Apple
or Google stores the provider's subject identifier and nothing else; THRØ asks those providers for no email,
no name and no profile.

**Local-first.** Scoring needs no account and no network. Somebody can use the whole scoring product having
given THRØ nothing at all, and the on-device journal is theirs.

`docs/legal/ROPA.md` is the full inventory. In summary, THRØ holds: an account (a UUID, a display name, an
age band); credentials (a provider subject or a public key); matches and the darts thrown in them; league,
team and fixture data; safety reports, blocks and decisions; and pictures on the device.

**Children.** Age is a three-value band — `unknown`, `minor`, `adult` — with a recorded assurance level, and
the schema refuses an assurance for an unknown band. **An unknown age is never treated as an adult** by any
exposure rule. A member recorded as a minor is never listed to anyone but an admin, an announcement reaches
nobody recorded as a minor or of unknown age, and a picture is refused for a minor at the point of writing.

## 2. Necessity and proportionality

The question a DPIA asks is not *is this lawful* but *is this the least you could do*.

- **Sign-in** is necessary to be the same person across devices and to attribute a result. It takes a
  pseudonymous identifier and stops there, which is the minimum that can do the job.
- **A display name** is necessary because a scoreboard with UUIDs on it is not a scoreboard.
- **An age band** is necessary *because* of the Children's code: you cannot apply age-appropriate rules
  without knowing which apply. Three values is the least resolution that supports the rules, and a date of
  birth would be more than is needed.
- **Location** is used and not stored. One coordinate, in memory, to sort a list; never written, never sent.
- **Matches** are the product.
- **Safety reports** carry free text, which is the least proportionate thing here and is treated as the
  highest risk below.

## 3. Risks, and what is done about them

### R1 — A child is identified or contacted through a public surface

*Likelihood: low. Severity: high.*

The public routes name **teams and venues, never people**. A private team or venue is not named at all,
though its fixture is still listed, because hiding it would leave a hole in a league's own calendar. A
member recorded as a minor is never listed to anyone but an admin, and — the load-bearing part — **an
unknown age is treated as a minor** by every exposure rule.

A person is named on a public surface only when a consent record **of the right scope** exists —
`identity.player_may_be_disclosed` requires a live claim and a `listing` consent, given by a guardian or by
an adult for themselves. The scope matters, and was added in V045 after the defaults audit found that an
`account_creation` record was being read as consent to publication; the correction is written out in
`docs/legal/DEFAULTS_AUDIT.md`. An account starts `unknown`, so a new one is never nameable, and everybody
else on a roster is counted rather than named.

The residual risk is a **team name that identifies a child** ("Smith's under-16s"). Nothing in the system
can detect that. *Mitigation is the safety route and an organiser's judgement, and it should be said out
loud in the organiser guidance rather than assumed.*

### R2 — A safety report contains special-category data

*Likelihood: high. Severity: high.*

A reporter writes what they think matters, and what they think matters may be somebody's health, religion,
sexuality or ethnicity. THRØ cannot prevent that and should not try to parse it.

What holds today: the queue is authorised, decisions are recorded with who made them, and the data sits in
its own `safety` schema that other areas cannot read.

**Closed, 12 September 2026 (PD-087).** A decided report is forgotten **two years after the decision** —
the founder's number, chosen as long enough to see somebody across two seasons and short enough to be
proportionate about a child. What survives is a tally: how many decisions of each outcome a subject has had,
with no text, no reporter and no dates beyond the first and last. A repeat offender still shows; the
allegation does not.

Two properties of the mechanism matter more than the number. **Nobody may delete a report** — the V040
guarantee is unchanged, and an administrator, a support script and the subject all still get *"a report is
kept"*. The only way out is one function applying one rule to everything at once, so nobody chooses which
report goes. And **an undecided report is never forgotten however old it is**, because one that has sat
unanswered for five years is a failure of process and deleting it would tidy away the evidence of that.

### R3 — A guardian's consent is claimed and was never given

*Likelihood: medium. Severity: medium.*

`consent_basis` is `self`, `guardian` or `none`, and `consent_record` names who gave it. THRØ has **no way
to verify a guardian**, and a self-declared age band is exactly as reliable as the person typing it.

This is honest rather than solved, and the code accepts that: the recorded position (OD-010) is that
third-party-entered data about a possible minor is refused rather than held. The mitigation is that THRØ
holds so little that a wrongly-classified child is exposed to very little.

### R4 — The rating scores a child

*Likelihood: not yet. Severity: medium.*

A rating is planned and **not built** (OD-001). When it is, it is automated evaluation of a person's ability
and it will apply to children. It is not Art 22 automated decision-making with legal or similarly
significant effects — a darts rating decides nothing about anybody's life — but the Children's code's
Standard 12 (profiling) will apply, and the default must be off for a child.

**Recorded here so that the decision cannot be made by omission when OD-001 closes.**

### R5 — Location reveals where a child is

*Likelihood: low. Severity: high.*

Off by default, consented by a button press, one fix, never stored, never sent, forgotten on leaving.
Since PD-086 there is **an obvious sign whenever it is in use, with Stop beside it in the app** — Standard
10 asks for both, and being able to turn it off only in iOS Settings would be telling a child rather than
giving them a choice.

### R6 — A picture carries where it was taken

*Likelihood: was high. Severity: high. Now mitigated.*

Intake strips location metadata, and the test proves it by building a real JPEG carrying GPS, putting it
through the same path and reading the bytes back. A picture is refused for a minor at the write, and not
handed back if an age later stops saying adult.

### R7 — Somebody cannot get their data out or deleted

*Likelihood: low. Severity: medium.*

Erasure is a route and records what it removed. The deletion page is public and needs no account, which is
what Google Play requires. The on-device export carries every row as written.

**Open:** the DSAR process has no mailbox behind it yet, and a published address that bounces is a missed
statutory deadline rather than a missed email. The address must not be published until it answers.

### R8 — A breach

*Likelihood: low. Severity: medium.*

Tokens are hashed; passkeys are public keys; there is no email or phone to leak. Every request runs under a
PostgreSQL role, so one area's bug cannot read another's tables.

**Written, 12 September 2026:** `docs/legal/BREACH_PLAN.md`. Two things in it are specific to THRØ and
would be missed by a generic plan. First, **a breach that does not reach the `safety` schema is very
unlikely to be high risk**, because there is no email to phish, no phone to spam, no address and no password
to reuse — the severity table says so store by store. Second, and less comfortably: **THRØ has no way to
contact anybody.** An Art 34 notification would have to be a public communication under Art 34(3)(c) plus an
in-app notice that does not exist yet. That gap is now written down rather than discovered at the time.

## 4. Against the Children's code, standard by standard

| | Standard | Where THRØ stands |
| --- | --- | --- |
| 1 | Best interests | The product's own rules already favour the child: unknown age is a minor, minors are not listed, pictures refused. |
| 2 | DPIA | This document. |
| 3 | Age-appropriate application | Bands applied at every exposure decision. **Assurance is weak** — see R3. |
| 4 | Transparency | **Met.** The privacy policy is plain English (grade 6.0); `apps/web/under-18.html` is the version written for a young player, measured at **grade 3.6** and held there by `tools/check_a_child_can_read_it.py`, which also refuses any page that does not link to it. |
| 5 | Detrimental use | Nothing here is designed to be detrimental. |
| 6 | Policies and standards | This, the ROPA, the terms. |
| 7 | Default settings | **Met.** Audited surface by surface on 12 September 2026 — `docs/legal/DEFAULTS_AUDIT.md`. Every default examined was already the private one; two properties that were held only by a comment now have a guard and a test. |
| 8 | Data minimisation | Strong. No email, no phone, no DOB, no stored location. |
| 9 | Data sharing | Nothing is shared. No analytics on children, no advertising, no third-party SDKs in the client. |
| 10 | Geolocation | **Met** — off by default, an obvious sign while in use, and Stop in the app (PD-086). |
| 11 | Parental controls | Not applicable: THRØ has no monitoring for a parent to enable or a child to be told about. |
| 12 | Profiling | Not built. Recorded at R4 so it cannot happen by omission. |
| 13 | Nudge techniques | None. There is no streak, no notification pressure, no "your friends are playing". |
| 14 | Connected toys | Not applicable. |
| 15 | Online tools | Erasure and export exist; the reporting route exists in the app, and `under-18.html` says where both are in words a child can follow. **The mailbox does not.** |

## 5. What must happen before launch

1. ~~A retention period for safety reports.~~ **Done** (PD-087): two years after the decision, swept daily
   by the server itself, because a period nothing enforces is a sentence in a policy.
2. **The mailbox**, so a DSAR can be received and answered inside a month. *(R7.)*
3. ~~A 72-hour breach plan.~~ **Written** — `docs/legal/BREACH_PLAN.md`. It names its own three
   dependencies: the mailbox, an in-app notice for Art 34 (not built), and a recovery window wider
   than the free plan's.
4. ~~A high-privacy defaults audit against Standard 7.~~ **Done** — `docs/legal/DEFAULTS_AUDIT.md`.
   It leaves one decision owed, and it is a real one: **may a live leg be shown on a public screen?**
   A named under-18 fixture on a pub wall is a safeguarding question, and answering it "only when
   every player is a confirmed adult" needs a consent route that does not exist yet.
5. ~~A child-facing explanation of what THRØ keeps.~~ **Written** — `apps/web/under-18.html` covers
   both Standard 4 and DSA Art 14(3), because a young player needs the rules as much as the privacy.
   Its reading age is measured rather than claimed, and a guard holds it. What it still wants is the
   only test that counts: some actual young players reading it and saying which bits they skipped.
6. **Art 28 processor terms** with Render, Neon and the mail host; **Art 27 EU representative** if EU users
   are targeted.
7. **ICO registration**, tier 1.

## 6. Sign-off

| | |
| --- | --- |
| Prepared | 12 September 2026, from the code |
| Owner | *(the founder)* |
| Reviewed by | *(outstanding — a solicitor, per LAUNCH_REQUIREMENTS)* |
| Residual risk accepted by | *(outstanding)* |
| Review due | On OD-001 closing (the rating), on the first upload of a match involving a minor, or annually — whichever is first |

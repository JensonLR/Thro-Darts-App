# If there is a breach

**UK GDPR Articles 33 and 34.** The DPIA (R8) says this should exist before there is anything to
breach, and that is the only good time to write it — a plan written during a breach is a plan written
by somebody who has not slept.

**The clock is 72 hours from becoming aware, not from the breach happening.** Awareness means having
a reasonable degree of certainty that a security incident has occurred that compromised personal
data. Investigating is not a reason to stop the clock; a first report that says *"here is what we
know so far"* is explicitly allowed (Art 33(4)) and is better than a late complete one.

**One person runs THRØ.** So there is no escalation tree here and pretending otherwise would be
theatre. What there is instead is an order of operations, because at 2am the temptation is to
investigate first and contain later, and that is backwards.

---

## The first hour: contain, then look

Do these in this order. Every one of them is reversible; leaving a hole open is not.

**1. Revoke every session.** One statement, and everybody is signed out on their next request. The
access token they hold dies within fifteen minutes on its own (`Accounts.ACCESS_TTL`), and their
refresh token stops working immediately.

```sql
UPDATE identity.session_family
   SET revoked_at = clock_timestamp(), revoked_reason = 'breach response <date>'
 WHERE revoked_at IS NULL;
```

**2. Rotate the database password**, in Neon's SQL editor, then update `DATABASE_URL` in Render's
environment and redeploy. `DEPLOY.md` has both. Rotate `MIGRATE_DATABASE_URL` too if there is any
chance the owner role was reached.

**3. Take the service down if you cannot contain it.** A dark API is a bad day. An API quietly
serving somebody else's data is a different kind of day. Render's dashboard suspends the service.

**4. Only now, write down what you know.** Time, what you saw, what made you look. This becomes the
Art 33(5) record, which you must keep **whether or not you notify anybody**.

## What could actually have gone

This is where THRØ is unusual, and it changes every subsequent decision, so it goes before the
decision tree rather than after it.

| Store | What a full copy of it would expose | Severity |
| --- | --- | --- |
| `identity.account` | A UUID, a display name somebody typed, an age band, timestamps. **No email, no phone, no address, no date of birth** — verified against every column in every schema (ROPA). | Low on its own; the age band makes it about children. |
| `identity.credential` | For Apple/Google: the provider's subject identifier, which is specific to THRØ and cannot be used to sign in anywhere else. For a passkey: **a public key**. | Low. A public key is public. |
| `identity.refresh_token`, `access_token` | **SHA-256 hashes only** (`octet_length = 32`, enforced by a constraint). A hash is not a token; nobody signs in with one. | Low. |
| `competition.*` | Teams, fixtures, results, venues, rosters. Names of people who play. | Medium. Mostly already published by leagues. |
| **`safety.*`** | **Reports and decisions, including free text a reporter wrote — which may be about somebody's health, sexuality or ethnicity, and may be about a child.** | **High. This is the one.** |
| `evidence.*`, `match.*` | Matches and the darts thrown. | Low. |

**The rule of thumb that follows:** a breach that does not reach the `safety` schema is very unlikely
to be high risk to anybody's rights and freedoms, because there is no email to phish, no phone to
spam, no address to visit and no password to reuse. A breach that *does* reach `safety` should be
treated as high risk from the first minute and worked backwards from there.

**Since PD-087, less of `safety` exists to lose.** A decided report is forgotten two years after the
decision, and what remains is a count with no words. That was written as a minimisation measure; it
is also the single biggest thing that limits the blast radius here.

## Was it a breach at all?

A personal data breach is a breach of security leading to accidental or unlawful **destruction, loss,
alteration, unauthorised disclosure of, or access to** personal data. Note the first three: losing
data is a breach even if nobody saw it. A database wiped with no backup is reportable.

**Things that are breaches and do not look like one:**

- A backup or export left somewhere readable.
- The migration owner role reached by something that should only have had `app_*`.
- A logging change that starts writing report text to Render's log stream.
- Somebody's refresh token reused — which THRØ *detects*, because a refresh token is single-use and
  using one twice revokes the whole family (`Accounts`, V023). If you see family revocations you did
  not cause, that is a signal, not noise.

**Things that are not breaches:** a bug that shows the wrong league table; an outage; a failed deploy.

## Do you tell the ICO?

**Art 33: notify unless the breach is "unlikely to result in a risk to the rights and freedoms of
natural persons".** That is a low bar to cross — "unlikely to result in a risk", not "unlikely to
result in serious harm" — and the decision must be recorded either way.

Notify if **any** of these is true:

- The `safety` schema was reached, at all.
- A child's data was in scope and you cannot rule out identification.
- You cannot establish the scope. Not knowing is not a reason not to report; it is a reason to report
  and say you do not know yet.
- Data was lost or altered rather than only read, and there is no clean copy.

**How:** the ICO's online report form, or 0303 123 1113. Have ready: what happened and when, the
categories and approximate number of people, the likely consequences, what you have done. If some of
that is unknown, say so and say when you will follow up — a partial report inside 72 hours beats a
complete one outside it.

**If you decide not to notify, write down why.** Art 33(5) requires the record regardless, and "we
decided it was unlikely to result in a risk" with no reasoning is the answer that turns a
non-reportable incident into a fine.

## Do you tell the people?

**Art 34: notify individuals when the breach is likely to result in a *high* risk to their rights and
freedoms.** Higher bar than the ICO one, and if it is met, notification must be **without undue
delay** — there is no 72 hours here.

**And now the sharp problem, which is a direct consequence of how THRØ is built: there is no way to
contact anybody.** THRØ holds no email address and no phone number, on purpose, and says so in its
privacy policy. There is no push token, and the in-app inbox is the secretary's work queue rather
than a message channel. **THRØ cannot send a person a message today.**

So an Art 34 notification is:

1. **A public communication** under Art 34(3)(c), which explicitly permits one where individual
   notification "would involve disproportionate effort" — a condition THRØ meets not by choosing to
   be lazy but by holding nothing to contact anybody with. A page at `thro.uk`, linked from the app's
   own front, in the plain English the privacy policy already uses.
2. **An in-app notice** (PD-094): a card on the iPhone's Home, under the masthead, read from `notice.json` on
   the public web site and opening the full account in words for an adult or for an under-18. Publishing it is
   editing one file — see **Publishing a notice**, below.
3. **The safeguarding route**, `safeguarding@thro.uk`, for anybody whose report may have been in
   scope — because "your allegation may have been read" is not a thing to put on a public page.

**Children first.** The ICO's expectation for children is higher than for adults and the language
must be theirs: what happened, what it means for them, what to do, in words a twelve-year-old reads
once. `docs/legal/` should hold the child-facing version alongside the adult one before it is needed.

## Publishing a notice

**One file, `apps/web/notice.json`, and a push.** The web site deploys itself from this branch when `apps/web`
changes, and it answers whatever the API is doing — which matters, because the API may be the thing that was
switched off. GitHub's own editor is enough: no terminal, no deploy, no database.

```json
{
  "format": 1,
  "active": true,
  "id": "2026-10-01",
  "published": "2026-10-01T09:00:00Z",
  "title": "What happened, in a few words",
  "summary": "One or two sentences: what happened, and whether anybody needs to do anything.",
  "body": ["What happened.", "What it means for the people it affects.", "What to do, and who to ask."],
  "under18": {
    "title": "The same, for a young player",
    "summary": "One or two short sentences.",
    "body": ["The same facts, in words a twelve-year-old reads once."]
  }
}
```

- **Every field is needed.** A notice missing any of them is shown nowhere: the app and the pages show nothing
  rather than half a notice. `python3 tools/check_notice.py draft.json` checks a draft before it is pushed,
  including that the under-18 words read at the level `under-18.html` is held to.
- **`published` is a date, a time and a zone**, like `"2026-10-01T09:00:00Z"` — never `"1 October"`.
- **To update a notice, change its `id`.** Anybody who put the old one away is shown the new one.
- **To take it down, set `"active": false`.** The card leaves each phone's Home the next time it looks, and both
  pages say there is no notice.
- **Who sees what.** The app shows the title and the summary — the under-18 words to anybody under 18, or whose
  age nobody has said, or who is not signed in — with a button to the full page. The web front page shows the
  adult title and summary with links to both pages. The request for the file carries no device id, account or
  token; the web host sees the internet address it came from, as it does for any page.

## Working out what happened

- **The audit chain.** `audit.decision` is hash-chained **by the database, not by the application** —
  an application that computed its own hashes could write a self-consistent chain of lies. Run
  `SELECT * FROM audit.first_broken_link()`. A break tells you the log was altered, which is itself a
  finding; no break means every authorisation decision recorded is the one that was made.
- **Session families.** Revocations you did not cause mean a refresh token was used twice.
- **Render's logs** for request patterns; **Neon's** for connections.
- **Do not clean up.** Rotating a password is containment. Deleting logs, dropping a table or
  rewriting history destroys the evidence you will be asked for, and `safety` rows cannot be removed
  anyway — the only route is `safety.forget_decided`, which applies one rule to all of them (PD-087).

## Afterwards

1. Finish the Art 33(5) record: facts, effects, remedial action. Keep it.
2. Follow up with the ICO if the first report was partial.
3. Fix the cause, with a test that fails without the fix. Every other defect in this repository has
   one; a security defect should not be the exception.
4. Re-read the DPIA. A breach is new information about likelihood, and the assessment should say so.

---

## What is missing from this plan, said out loud

- **The mailbox does not exist**, so §"Do you tell the people" has no `safeguarding@` behind it yet.
  It is item 2 on the DPIA's pre-launch list.
- ~~**The in-app notice does not exist.**~~ **Built** on 13 September 2026 (PD-094), for the iPhone. **Android
  does not have it**: the Android client has no network code at all, so until it gains some, the public page is
  the only way to reach somebody who plays only on Android.
- **Recovery is Neon's, and on the free plan it is thin.** The current path is Neon's point-in-time
  recovery in London (`aws-eu-west-2`); the paid tier documented in `DEPLOY.md` gives **7 days** and
  the free one gives less. That is a recovery window, not a backup policy: there is no copy anywhere
  Neon is not, so a Neon-side loss and an accidental destruction have the same answer, and it is a
  short one. Widening it costs a few pounds a month and should be done before launch, not after the
  incident that needs it.
- **This has never been rehearsed.** A plan nobody has walked through is a document, not a plan.

*Written 12 September 2026, from the schema and the deploy runbook. Nothing here is legal advice.*

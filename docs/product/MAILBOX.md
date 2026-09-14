# Standing up THRØ's mailbox

The addresses are decided in `docs/product/PRESENCE.md`: `privacy@thro.uk`, `safeguarding@thro.uk`,
`hello@thro.uk`, one inbox behind all three. This is what it takes to make them answer, and what has to be
written **before** they do.

## What cannot be automated, and why

The founder asked whether the Gmail connection could create these. It cannot, for three reasons, and the
first is the only one that matters:

1. **`thro.uk` is not registered.** No tool can create an address at a domain nobody owns. Everything below
   is downstream of buying it.
2. **The Gmail connection is a mailbox client, not an admin console.** It drafts, sends, searches, labels
   and trashes inside one already-authenticated account. Creating addresses at a domain happens in Google
   Workspace's admin console or a mail host's control panel. Also: a personal `@gmail.com` cannot host
   `@thro.uk` addresses at all.
3. Standing up a mail provider means **creating an account and entering payment details**, which is the
   founder's to do.

## Choosing a host

| | Cost | Verdict |
| --- | --- | --- |
| **Fastmail** | ~£4/mo | **Recommended.** Unlimited aliases on your own domain, three addresses into one inbox, and it sets the DNS records for you if the domain is delegated to it. |
| **Proton Mail** | ~£4/mo | More on-brand for a product whose pitch is holding less about you. Alias handling is clumsier. |
| **Google Workspace** | ~£5.20/mo | Only worth it if you want Drive and Docs too. You already know the interface, which is a real advantage. |
| **Cloudflare Email Routing + Gmail** | free | **Read the catch.** Routing is *inbound only*. Mail to `privacy@thro.uk` lands in your Gmail for nothing, but replying **as** that address needs an outbound SMTP relay Gmail can verify (Brevo or similar, free tier). Until that is set up, every reply comes from `jensonlewis0@gmail.com` — which for a statutory privacy contact looks careless and, worse, teaches people to write to a personal address. |

**The honest recommendation is Fastmail.** The free path is fine for a week; it is the wrong answer for an
address printed in a privacy policy.

## The DNS records

Set at whoever holds `thro.uk`. A privacy address that lands in spam is a missed statutory deadline rather
than a missed email, so none of these are optional.

| Type | Name | Value | Why |
| --- | --- | --- | --- |
| MX | `@` | your host's servers, with their priorities | where mail arrives |
| TXT | `@` | `v=spf1 include:<your host> -all` | who may send as you. **`-all`, not `~all`** — a soft fail invites spoofing of a safeguarding address |
| TXT | host's selector | the DKIM key your host gives you | signs what you send |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:privacy@thro.uk; pct=100` | what to do with mail that fails. Start at `quarantine`, move to `reject` once a fortnight's reports are clean |

**Do not set these on `api.thro.uk`.** Mail is on the apex; `tools/host.py` owns the apex's A/CNAME for the
web and `api` for the API, and the domain switch checks those. Adding MX at the apex does not disturb it.

## Before the mailbox answers: the replies that must already exist

A mailbox with nobody's words in it is worse than no mailbox, because the clock starts on the first message.

### A data-subject request

**One month, statutory.** Acknowledge on the day.

> Thanks for writing. This is confirmation that THRØ has received your request and will answer it within one
> calendar month, as UK GDPR requires.
>
> One thing worth saying now, because it usually shortens the answer: THRØ holds no email address and no
> phone number for any player — there is nowhere in the app to put one. What it holds is the name you typed,
> how you signed in, and the darts you threw. If you want all of it gone, the account deletion page removes
> it without needing this correspondence at all: https://thro.uk/delete-account
>
> If you would rather I dealt with it here, tell me the display name on the account and I will match it up.

### A safeguarding report

**This one is not a template to send unread.** The rule is: acknowledge fast, promise nothing about
outcomes, and never continue the conversation with a child.

> Thank you for telling me. I have read it and I am dealing with it.
>
> I will not discuss what happens next with anyone other than the people who need to know, and I will not
> share your message. If anyone is in immediate danger, please contact the police on 999 — I am one person
> with an app and they are not.
>
> If you are under 18, please ask a parent, carer or another adult you trust to write to me from their own
> email, and I will pick it up from there.

**Then**: write down what was reported, when, and what was done, on the day it happens. A safeguarding
record that is reconstructed later is not a record.

### The DSA point of contact

Rarely used and must exist. A one-liner is correct:

> This address is THRØ's point of contact under the Digital Services Act. It is monitored and answered in
> English.

## Once it answers

Tell me, and one change puts the address into `apps/web/privacy.html` (which currently says *"Contact
address: not published yet"*), the terms, the deletion page and the DSA line — plus the paragraph the
privacy policy now needs, because **correspondence is personal data**. THRØ's policy says in terms that it
holds no email address; the day the mailbox exists that stops being the whole truth, and the policy has to
say so and give a retention period. A year is defensible. Two is hard to argue.

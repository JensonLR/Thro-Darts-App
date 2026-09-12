# The names THRØ answers to

Researched 12 September 2026, at the founder's ask: *"we will most likely need official social media
accounts & email address for this so I want you to pick the best names & make sure they're available."*

Nothing here has been registered. **Creating accounts is not something this session does** — every one of
these needs a person with a password manager and a phone number, and half of them need an age and an
identity. What follows is the recommendation, what was actually checked, and what was not.

## The short answer

| | |
| --- | --- |
| **Handle, everywhere** | `throdarts` |
| **Display name** | `THRØ Darts` |
| **Domain** | `thro.uk` — **confirmed unregistered** at Nominet on 12 September 2026 |
| **Contact** | `hello@thro.uk`, `privacy@thro.uk`, `safeguarding@thro.uk` — three addresses, one inbox |
| **Bluesky** | not `throdarts.bsky.social` — set the handle to **`thro.uk`** itself, which is free and verifies by DNS |

## Availability, and how it was checked

Public profile pages were loaded in a browser and read. A platform's own "this account doesn't exist" is the
evidence; where a login wall got in the way, that is said rather than guessed.

| Platform | `throdarts` | Evidence |
| --- | --- | --- |
| X | **free** | *"This account doesn't exist"* |
| Instagram | **free** | *"Sorry, this page isn't available."* |
| TikTok | **free** | *"Couldn't find this account"* |
| YouTube | **free** | HTTP 404 on `youtube.com/@throdarts` |
| Bluesky | **free** | *"Unable to resolve handle"* |
| Threads | *follows Instagram* | login wall; a Threads handle **is** the Instagram handle, so claiming Instagram claims it |
| Facebook | **unknown** | Facebook answers *"This content isn't available at the moment"* for a missing page and a restricted one alike, so this proves nothing. Claim it when you make the page. |
| Reddit | **unchecked** | Reddit is blocked in this browser. `reddit.com/user/throdarts` and `reddit.com/r/throdarts` are a ten-second check each when you register. |

**`thro` on its own is gone and not worth chasing.** X has had `@thro` since March 2009 — a dormant Icelandic
account, 8 followers, last posted in 2021. Dormant is not available: X's inactive-handle policy has never
actually released names to the people who ask. Four letters that are also a common misspelling of *throw*
will be taken on every platform worth having.

**`throdarts` is the better answer anyway.** It says what the thing is, it is searchable by people who have
never heard the name, and it is the same string everywhere — which is worth more than brevity, because the
one thing a person does with a handle is guess it.

## The domain

**`thro.uk` is not registered.** Nominet's WHOIS on 12 September 2026: *"No match for thro.uk. This domain
name has not been registered."* Everything in `docs/runbooks/GOING_LIVE.md` and `tools/host.py --set thro.uk`
is therefore still valid, and the sooner it is bought the better — the handles above are a reason for
somebody else to want it.

**`thro.co.uk` belongs to somebody else**, registered 26 October 2014 and live today at 109.203.114.110.
Worth five minutes of yours: look at what it is. It does not block `thro.uk` — Nominet's right-of-registration
window for .co.uk holders closed in June 2019 and unclaimed names went to the open market, which is why
`thro.uk` is free — but it is a brand-confusion and a search-results risk, and it is the sort of thing to
know about before printing anything.

Also free, and worth £10 each as defensive registrations rather than as anything to use: `throdarts.com`,
`playthro.com` (both *"No match"* at WHOIS). `thro.app` and `getthro.com` are taken.

## Email

**Three addresses, one inbox.** They are separate strings so they can be split later without republishing a
legal page, and one inbox so there is one place to look.

| Address | What it is for | What it unblocks |
| --- | --- | --- |
| `privacy@thro.uk` | the UK GDPR contact and the **DSA point of contact** | the privacy policy's contact line, the terms, the deletion page, and LAUNCH_REQUIREMENTS' mailbox item — four things at once |
| `safeguarding@thro.uk` | reports about a person, including about a child | the safety queue has a route in the app; this is the route for somebody who is *not* a user |
| `hello@thro.uk` | everything else; `support@` and `press@` alias to it | the App Store and Play both require a support contact |

**One consequence that has to be written down.** THRØ's privacy policy says, in terms, that the app holds no
email address and there is nowhere to put one — *"That is the trade."* The moment a mailbox exists, an
email to it **is** personal data, and it is the only personal data of that kind THRØ will hold. That does
not make the policy wrong, but the policy has to say so: a paragraph on correspondence, and a retention
rule (a year is defensible; two is hard to argue). `apps/web/privacy.html` says *"Contact address: not
published yet"* and should stay that way **until the mailbox actually answers** — a published address that
bounces is worse than none, because a data-subject request that bounces is a breach of a statutory deadline.

**Hosting it.** The domain needs MX, SPF, DKIM and DMARC records, or a privacy address that lands in spam
becomes a missed deadline.

- **Fastmail**, ~£4/month, unlimited aliases on your own domain, and the cleanest way to run three addresses
  into one inbox. This is the recommendation.
- **Proton Mail**, ~£4/month, and more on-brand for a product whose whole pitch is holding less about you.
  Fewer alias conveniences.
- **Cloudflare Email Routing**, free, forwards to a mailbox you already have and cannot *send as* the
  address without a separate relay. Fine as a stopgap for a week, wrong as the answer for a statutory
  contact address you must reply from.

## What goes on the profiles

**Avatar, everywhere:** the app icon, `apps/ios/ThroDarts/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
Square, 1024, the mark on the brand green. It already reads at 32 px, which is the only size that matters.

**Banners** are generated by `tools/make_social_artwork.swift` into `docs/design/brand/social/`, from the
app's own wordmark geometry rather than from a screenshot — the Ø is a dart through a ring at measured
proportions (`MarkGeometry.Ratios.wordmark`), not the typeface's Ø, and a banner drawn by eye in a design
tool would drift the first time either moved:

- `x-header-1500x500.png`
- `youtube-banner-2560x1440.png` — composed against YouTube's 1546×423 safe area, which is all that survives on a phone
- `facebook-cover-820x312.png`
- `linkedin-cover-1128x191.png`
- `open-graph-1200x630.png` — also now `apps/web/og.png`, so a link to any THRØ page previews as something

**Bio, by platform.** Same three facts everywhere, cut to the limit each one gives:

- **X (160):** `Darts scoring that works with no signal, keeps your own record, and never guesses a number. Local leagues, real results. UK.`
- **Instagram (150):** `Darts scoring that works offline. Your matches stay on your phone. Local leagues, real tables.`
- **TikTok (80):** `Darts scoring that works offline. Local leagues, real tables.`
- **YouTube / Facebook / LinkedIn (long):** the above, plus *"THRØ never keeps an email address or a phone
  number. Every figure it shows says where it came from — and says nothing at all when it cannot."*

**Link:** `thro.uk` once it resolves; until then the Render URL rather than nothing.

**Category:** Sports / Sports app. Not "Gaming" — darts is a sport and the audience for the two is different.

## The rule that is specific to this product

**THRØ has under-18 players, and a social account is the easiest place to undo that.**

The app's own rule is that an unknown age is *not* an adult (`docs/product/DECISIONS.md`, and the club book
refuses to hand back a picture for anyone whose band it cannot read). A marketing account has to obey the
same rule, and nobody enforces it for you:

1. **Never repost a player's name, face, handle or scoreline** without knowing they are over 18 and have
   said yes. Not "they posted it publicly" — that is their choice about their audience, not yours.
2. **An unknown age is a no.** Same rule, same reason.
3. **Never screenshot a real league table with real team names** until the league has been asked. Team names
   are not personal data; the people in them are, and a small league is a small village.
4. Use the seeded demo season (`services/api/seed/demo_season.sql`) for anything that needs a screenshot.
   It exists, it is realistic and nobody in it is real.
5. **Comments and DMs are a safeguarding surface.** A child will eventually message the account. There needs
   to be one answer, written before it happens, that points at `safeguarding@thro.uk` and does not continue
   the conversation.

This belongs in whatever process you use, not only here. It is the one thing on this page that has a person
on the other end of getting it wrong.

## What is left for you

1. **Register `thro.uk`** — it is free today and it is the keystone: the API's host, the passkey relying
   party, the email domain and the Bluesky handle all hang off it.
2. **Claim `throdarts`** on X, Instagram (which brings Threads), TikTok, YouTube, Facebook and Reddit, in
   that order of who squats fastest. Claiming is not launching; an empty account with the right name is the
   point.
3. **Stand up the mailbox** — `docs/product/MAILBOX.md` has the host comparison, the exact DNS records and
   the three replies that must exist *before* it answers. Then tell me and I will put the address into the
   privacy policy, the terms, the deletion page and the DSA contact in one change.
4. **Look at `thro.co.uk`** and decide whether it matters.
5. **Consider a UK word mark** for THRØ in classes 9 and 41 — about £170 for one class. Not urgent; worth
   knowing the number before somebody else does.

# What THRØ must satisfy before it is public

Researched 11 September 2026 against Apple's App Review Guidelines, Google Play policy, UK GDPR/ICO, the
EU Digital Services Act and the European Accessibility Act. Each item says **who** does it — *build* (code
in this repository) or *founder* (an account, a payment, a document, a decision) — and what "done" is.

Nothing here is legal advice. It is the list a reviewer or a regulator would check, with the evidence for
each claim, so that the ones that need a solicitor can be taken to one knowingly rather than discovered.

## Already satisfied

| What | Where |
| --- | --- |
| **Account deletion in the app** (Apple 5.1.1(v)) — the record and its personal data, not a deactivation | `DELETE /v1/me`, V031/V033 erasure by redaction; the delete screen names what goes and what stays |
| **Sign in with Apple offered beside Google** (4.8) | `WelcomeScreen`, `AccountScreen` |
| **Location is proportionate** (5.1.1(ii), 5.1.5) | While-in-use, on-device haversine, never sent to the server |
| **No tracking, so no ATT** | No third-party SDKs in `Package.swift`; no IDFA |
| **Live Activities are local and end with the match** (4.5.3) | `ThroLiveKit`, ended when the scoring screen goes |
| **A minor is never named in public** | `identity.player_may_be_disclosed`, roster and league fronts count rather than name |
| **Unknown age is not adult** | `competition.player_is_adult` (V038), friends and adoption gated |

## Blocking — the app cannot go public without these

1. **User-generated content safety (Apple 1.2, Play UGC policy).** *Build.* Nothing in the app can report or
   block anything today. Needed: an in-app **report** on every surface that carries somebody's words or
   picture (team and venue names, display names, profile photos), an in-app **block** between accounts, a
   **moderation queue** with a response inside 24 hours, published **contact information**, and a **EULA
   accepted before a player can post anything**, stating that objectionable content is not tolerated.
2. **`PrivacyInfo.xcprivacy` with required-reason API declarations.** *Build.* Mandatory since 1 May 2024;
   its absence is an automatic rejection (ITMS-91053/91055). The app uses `UserDefaults` (reason `CA92.1`).
3. **A web address, and a contact on it.** *Founder.* **Half done, 12 September 2026.** The pages are
   live at `https://thro-web-q7ys.onrender.com`, so the account-deletion page Google Play requires
   (PD-056) is publicly reachable and this no longer waits on buying a domain — a free Render subdomain
   is a valid URL for the store's purposes, and `thro.uk` upgrades it rather than unblocking it (PD-058).

   **What is still missing is the contact.** `delete-account.html` says *"Contact address: not published
   yet"* where an address belongs, and that paragraph exists for exactly the person the requirement is
   about: somebody who cannot open the app and needs their account deleted anyway. A deletion page with
   no way to ask is a deletion page that fails the requirement it was built for.

   **The names are decided and checked** — see `docs/product/PRESENCE.md`: `privacy@thro.uk` for this and
   the DSA contact, `safeguarding@thro.uk`, `hello@thro.uk`, one inbox behind all three. `thro.uk` was
   confirmed unregistered at Nominet on 12 September 2026, so nothing blocks it but buying it.
   This needs a **mailbox decision, not code**: a role address the product owns (`privacy@thro.uk` or
   similar) rather than a personal one, because it goes on a public page and outlives whoever reads it
   today. The same address answers the DSA point of contact below, so one mailbox closes two items — and
   it can be a forwarding alias long before it is a real inbox.

4. **A privacy policy, linked in the app and in App Store Connect** (5.1.1(i)). *Founder + build.*
   **Drafted 12 September 2026** at `apps/web/privacy.html`, live on the web, and a terms page beside it at
   `apps/web/terms.html` for guideline 1.2. Both say what is collected, who receives it (Neon London, Render
   Frankfurt), how long it is kept and how to withdraw — every claim checked against the code rather than
   asserted, and the working is in [STORE_ANSWERS.md](STORE_ANSWERS.md).

   **Still needed:** a legal name, an address, a contact, and a solicitor's read. The drafts say on their own
   faces that they are drafts, and they should keep saying it until that has happened.
5. **App privacy "nutrition" labels.** *Founder.* **Answered in full** in
   [STORE_ANSWERS.md](STORE_ANSWERS.md), for Apple and for Play, with what each answer was checked against.

   One correction to what this used to say: **no email is collected.** It never was stored, but THRØ was
   *asking* Apple and Google for one and discarding it, which is a line on the label either way. PD-063
   stopped it asking, so the answer is now a clean "not collected" rather than a defence.
6. **Age rating questionnaire, including the social-media capability answers** — required for new
   submissions since September 2026, and the tiers are now 4+/9+/13+/16+/18+. *Founder.* Expect 13+ or 16+.
   **Do not enter the Kids Category**: its obligations persist even after leaving it.
7. **ICO registration** — tier 1, £52 a year. *Founder.* Plus an Article 13 privacy notice, a lawful-basis
   map (contract for accounts and match records; legitimate interests for safety; consent only for extras),
   a DSAR process answering inside a month, and a 72-hour breach plan. A DPO is not required at this size;
   a **record of processing (ROPA) is**, because children's data is involved.
8. **A DPIA, because the ICO's Children's code applies.** *Founder + build.* THRØ is "likely to be accessed
   by children". Against the code's standards, two gaps stand out: **geolocation must be off by default and
   show an in-use indicator while it is on** (Standard 10) — it is opt-in but shows no indicator — and
   **high-privacy defaults** must hold on every public surface (Standard 7). Consent age is 13 in the UK and
   16 in several EU states unless lowered.
9. **Digital Services Act, if any EU user.** *Founder + build.* A published single point of contact
   (Art 12), terms that state restrictions **and explain them in a way a minor can understand** (Art 14(3)),
   notice-and-action with confirmation of receipt (Art 16), and statements of reasons (Art 17). As a
   micro/small enterprise, Arts 15(2) and 20–28 do not apply (Art 19). Targeting EU users from the UK needs
   an **Art 27 EU representative**.

## Needed soon — before Android, and as the platform grows

- **Play's web account-deletion URL** (in addition to the in-app path). There is no web surface yet, so this
  is the first thing the web app must carry. *Build.*
- **Target API 36**; the 31 August 2026 deadline has passed, so request the extension to 1 November 2026.
  Adopt **Play Integrity** (SafetyNet ended January 2025). Complete the **Data safety** form. *Build + founder.*
- **Age assurance, proportionate**: use Apple's Declared Age Range (iOS 26) and Play's Age Signals as
  signals, keep the self-declared band as the fallback, and record the reasoning in the DPIA. Do not start
  collecting birthdates. *Build.*
- **Documents**: terms of service and the UGC EULA, an adult and a child-facing privacy notice, the DPIA,
  the ROPA, a retention schedule (match records against auth logs against erasure tombstones), DSAR and
  breach runbooks, a moderation policy and decision log, and a sub-processor list. *Founder.*
- **Accessibility to the standard both stores expect**: Dynamic Type to the largest size, VoiceOver and
  TalkBack labels on the scoreboard and the chalk figures, 4.5:1 text contrast (chalk on green is the one to
  watch — the contrast gate already measures it), 44pt/48dp targets, and Reduce Motion honoured. *Build.*

## Later

- **The European Accessibility Act does not apply to THRØ today**: Directive 2019/882 covers e-commerce,
  banking, e-books, transport and communications, not a free sports app. **Adding a paid subscription makes
  it an e-commerce service**, which pulls in EN 301 549 / WCAG 2.1 AA and an accessibility statement. The UK
  **Equality Act 2010** anticipatory duty applies regardless, which is the honest reason to keep the
  accessibility work current rather than waiting for a law to name us.
- **The web app** brings PECR consent for anything beyond strictly-necessary cookies, and extends the DSA
  and Children's-code duties to it.
- **Growing past micro/small** switches on DSA Arts 15, 20, 21, 23, 25, 26 and 28.

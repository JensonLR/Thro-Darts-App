# The store questionnaires, answered

App Store Connect's privacy questionnaire and Google Play's Data safety form are **declarations**, signed by
the founder, and a wrong one is a removed app rather than a correction. So this is the answer sheet, with
what each answer was checked against — not what the product intends, what the code does.

Every claim here was verified on **12 September 2026**, after PD-063 removed the sign-in scopes THRØ was
requesting and never reading. Re-check anything marked *(verify again)* before submitting.

## Apple: App Privacy

**Do you or your third-party partners collect data from this app? — Yes.** (Small, but not none.)

| Category | Collected | Linked to the user | Purpose | Tracking | Checked against |
|---|---|---|---|---|---|
| Contact Info → **Name** | **Yes** | Yes | App Functionality | No | `identity.account.display_name` — typed by the player, never taken from a provider |
| Contact Info → Email | **No** | — | — | — | No email column anywhere in `identity`; `openid` is the only scope requested (PD-063) |
| Contact Info → Phone, Address, Other | **No** | — | — | — | Same |
| Health & Fitness | **No** | — | — | — | Nothing of the kind exists |
| Financial Info | **No** | — | — | — | No payments in the app |
| **Location** | **No** | — | — | — | Distance is computed on the phone; the API has no location parameter and the server "never learns where a phone is" (`Nearby.swift`) |
| Sensitive Info | **No** | — | — | — | No special-category data. Age band is *not* sensitive info under Apple's definition — declared under Other Data below |
| Contacts | **No** | — | — | — | THRØ never reads the address book; friends are added by a code |
| User Content → **Photos** | **Yes** | Yes | App Functionality | No | Only if the player adds one |
| User Content → **Other** | **Yes** | Yes | App Functionality | No | Match records: every dart, if uploaded |
| Browsing / Search History | **No** | — | — | — | Neither exists |
| Identifiers → **User ID** | **Yes** | Yes | App Functionality | No | `account_id`, and the provider's subject for that account |
| Identifiers → Device ID | **No** | — | — | — | `identity.device` is THRØ's own record of a sign-in, not IDFA or IDFV; no advertising identifier is read |
| Purchases | **No** | — | — | — | Nothing is sold yet |
| **Usage Data** | **No** | — | — | — | **There is no analytics SDK in the app.** Grep for Sentry, PostHog, Firebase, Amplitude, Mixpanel returns nothing |
| **Diagnostics** | **No** | — | — | — | No crash reporter |
| Other Data → **Age band** | **Yes** | Yes | App Functionality | No | Whether the player is 18 or over, and how that was established. Not a date of birth |

**Tracking: No.** Nothing is shared with anyone for advertising or measurement, and nothing is linked to
data from other apps. **No ATT prompt is required**, and the app must not show one.

That is an unusually short list, and it is short because of decisions rather than luck: no analytics was a
choice, location-on-device was a choice, and no email is now a choice too (PD-063). It is worth keeping —
the first analytics SDK added to this app turns four "No" rows into "Yes" and puts a nutrition label on the
store page that says THRØ watches you.

## Apple: age rating

Answer the 2026 questionnaire (tiers 4+ / 9+ / 13+ / 16+ / 18+) as follows.

| Question | Answer | Why |
|---|---|---|
| Violence, sexual content, profanity, horror, drugs, alcohol or tobacco references | **None** | THRØ shows darts, tables and fixtures. Venues are named — a venue being a pub is a fact about the world, not a reference to alcohol in the app |
| Gambling, contests or prize draws | **None** | No wagering and no prizes. A league table is not a contest in Apple's sense |
| Unrestricted web access | **No** | The app opens no arbitrary browser |
| **User-generated content** | **Yes, with moderation** | Names, pictures, team and league names, and match records are seen by others. Reporting, blocking and a 24-hour answer are built (PD-050) |
| Medical or treatment information | **No** | — |

**Expected outcome: 13+**, driven by user-generated content alone. If Apple's flow offers 16+ for social
features that let strangers find each other, take it — THRØ already refuses the social parts to anybody who
is not established as 18 or over, so the higher rating costs nothing and matches the behaviour.

## Google Play: Data safety

The same facts, in Play's shape. Play asks two extra things Apple does not.

- **Is data encrypted in transit?** **Yes** — HTTPS throughout; the app names an `https://` base URL and
  the API is behind Render's TLS.
- **Can users request that data be deleted?** **Yes**, and give the URL: the deletion page at
  `/delete-account.html`. This is the requirement the web was built for (PD-056), and it is live.

Collected, all *linked to the user* and all for *app functionality*, none shared with anyone:
**Name**; **Photos**; **Other user-generated content** (match records); **User IDs**. Nothing else — no
location, no personal identifiers beyond the account, no app activity, no crash logs, no device IDs.

Play also asks whether data collection is **optional**. It is: THRØ works entirely without an account, and
nothing reaches the server until somebody signs in. Say so — it is true and it is unusual.

## What the founder still has to supply

None of the above can be submitted until these exist. They are not code.

1. A **legal name and address** for the controller, in the privacy policy and the terms.
2. A **contact address** — a role mailbox the product owns, not a personal one. It fills the gap on the
   deletion page, the privacy policy, the terms, and the DSA point of contact, all at once.
3. The **privacy policy URL** in App Store Connect and Play Console, once the drafts at `/privacy.html`
   and `/terms.html` have been read by somebody qualified.

## The drafts are drafts

`apps/web/privacy.html` and `apps/web/terms.html` are accurate about the software — every claim in them was
checked against the code, and the table above is the working. **Accuracy about the software is not
sufficiency under the law.** They have not been reviewed by a solicitor, and they say so on their own faces
until they have been.

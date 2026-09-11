# Taking money for THRØ

Researched 11 September 2026. Three things THRØ might charge for, and what each one costs in fees, tax and
compliance. Not tax or legal advice: the two lines marked **ask the accountant** are the ones to take to one
before any money moves.

## The three things, and where each may be sold

| What | Apple's rule | Where it must be sold | Cost |
| --- | --- | --- | --- |
| **Premium player statistics** | 3.1.1 — a digital feature unlocked in the app | **In-app purchase, no argument** | 30%, or **15%** under the Small Business Program (under $1M proceeds last year) |
| **An organiser's subscription to run their league** | Grey. Fixtures, results and tables rendered in the app read as in-app functionality, so Apple applies 3.1.1 | Cleanly: **sell it on the web** and keep the app a free companion with no purchase and no call to action (**3.1.3(f), free stand-alone apps**) | Stripe ≈ 1.5% + 20p, versus 15–30% through the store |
| **Tournament entry fees** | **Not** person-to-person (3.1.3(d) is one-to-one; a tournament is one-to-many). It escapes as a **real-world service consumed outside the app (3.1.3(e))**, where Apple says you *must not* use IAP | Stripe **Connect** | ~4.8% all-in; charge 8–10% or a flat booking fee to cover it |

Google Play says it plainly: physical services and **tickets for live events** are exempt from Play Billing.
Play's fees fell on 30 June 2026 — 10% service fee on the first $1M for new installs, 10% on subscriptions,
plus 5% only if you use Play Billing — so Play is now materially cheaper than Apple.

Two changes worth designing for now: Apple's **EU terms from 1 October 2026** (26% IAP / 20% alternative
processing / 15% web link, and a 5% Core Technology Commission), and the **CMA's steering conduct
requirement** for Apple and Google, consulted on in June 2026 and not yet imposed — build the plumbing for
steering users to the web before it is allowed, so that switching it on is a flag and not a project.

## Never touch the money

The FCA's commercial agent exclusion does not save a marketplace that holds funds: it requires acting for
the payer *or* the payee, and money passing through an account THRØ controls means acting for both. So entry
fees route through **Stripe Connect** — Stripe Payments UK Ltd is an FCA-authorised e-money institution
(FRN 900461) and safeguards the funds; THRØ receives only its fee. Sweeping entry fees into a THRØ account
and paying organisers by hand *is* client money and needs authorisation. Use **Express accounts with
destination charges**: Stripe does the identity checks, the organiser gets a dashboard, and THRØ carries
dispute liability — which the terms must allocate, and the organiser's refund policy must be shown before
payment. Darts is a game of skill, so an entry-fee tournament is not a lottery under the Gambling Act 2005.

## VAT

- **Threshold £90,000** rolling twelve months. **Ask the accountant:** reverse-charge services THRØ *receives*
  from overseas count toward that threshold.
- **Through the stores**, Apple is commissionaire and Google merchant of record: they charge and remit the
  VAT, so store revenue does not count toward UK registration and needs no EU VAT number.
- **Through Stripe**, THRØ is the merchant of record: UK VAT above the threshold, and EU consumer sales are
  taxed in the customer's country **from the first sale**, through non-Union OSS registered in one member
  state. EU business subscriptions are reverse charge.
- **Ask the accountant:** on entry fees, whether THRØ is a disclosed agent (only the commission is turnover)
  or a principal (the whole fee is).

## What it costs, monthly, at 100 and 1,000 payers

| Route | 100 payers | 1,000 payers | Compliance load |
| --- | --- | --- | --- |
| Player stats £3.99 via **IAP + RevenueCat** | ~£60 | ~£620–640 (15–16%) | Almost none: Apple is merchant of record |
| Organiser £15 via **Stripe on the web** | ~£53–61 | ~£605–700 (~4%) | VAT registration bites near £180k a year; Stripe Tax £7.50–£75 |
| Entry fees £10 via **Connect** | ~£48 on £1k | ~£480 on £10k (~4.8%) | Terms, refunds, disputes, KYC by Stripe |

**RevenueCat** is free to $2,500 monthly tracked revenue, then 1% — worth it for one person shipping two
platforms, because subscription state across iOS and Android is otherwise a project of its own.

## The order to build them

1. **Premium player statistics as an iOS in-app purchase.** Apple is merchant of record, so there is no VAT
   registration, no OSS, no Stripe Tax and no FCA question. One cost line, 15%.
2. **The organiser subscription on the web, through Stripe**, with the app as a free companion. This is where
   the margin is, and where 15% would hurt most.
3. **Entry fees last**, on Connect Express, once the terms, refunds and dispute allocation are written.

One more thing to design early: the **DMCC Act 2024 subscription regime** (renewal reminders, a
non-waivable cooling-off on renewal, proportionate refunds) is delayed to spring 2027, but renewal emails
and cancellation flows are cheaper to design now than to retrofit.

# ADR-016 — A local history, and how it is claimed by an account later

**Status:** Accepted · **Date:** 2026-09-07 · **Decision:** PD-012

## Context

The founder chose to ship **local first, with the path designed now**: the phone app has no accounts,
no server and no sync, and a person's whole history lives on their device. Accounts come later.

The obvious failure of that plan is the one nobody notices until it happens: a first cohort plays a
season's worth of matches, accounts arrive, and none of it can be carried over — because nothing
recorded *whose* those matches were in a way an account can later be attached to. This ADR is what
stops that.

It is deliberately narrow. It does not decide what an account is, how someone signs in, or how
recovery works — that is **B4**, a design commission, and it is still open. It decides only what the
client must record **now** so that whatever B4 turns out to be can attach to it **without a
migration and without losing a leg**.

## What a local match records today, and why it is not enough

The journal already carries most of what a claim needs: a stable match id, the device's own identity
written into the journal file, a gapless per-device sequence, and every event that produced the
result. What it does **not** carry is a person. `local_match` has `home_name` and `away_name`, which
are free text typed at the oche.

Free text cannot be claimed. "Jenson", "jenson" and "Jenson L" are three different strings and one
player, and a claim that had to guess between them would either lose matches or steal them.

## Decision

**1. The device keeps a book of the people who play on it.** A local person is an id and a name.
Match setup picks from the book or adds to it; the match stores the person's id alongside the name it
displayed. The name stays on the match row, so a match remains readable if the book is ever lost.

This is not scaffolding for a future feature — it is the better product today. Nobody wants to retype
their opponent's name every Tuesday, and a person's figures across matches are computable the moment
their matches are attributable to them.

**2. A claim is one seat, by one person, and covers everything.** Claiming is a mapping from a
**local person** to an account. Every match that person appears in comes with it, in one act. The
other seat in each of those matches stays unclaimed until that person claims it themselves, on their
own device or by being invited — because asserting who your opponent was is not yours to do.

**3. A claimed local match is still self-reported.** This is the load-bearing sentence. Claiming
attaches a history; it does not corroborate it. A local journal lives in a file its owner can edit,
so its rows are attributable evidence and never verified evidence. PD-002 already forbids one
player's word from moving a rating, and a claim does not launder it into two. What claiming buys the
player is their history, their figures and their clubs — not a rated record they did not earn.

**4. A claim carries a digest, so tampering after the fact is visible.** At claim time the client
sends, per match, a digest over that match's journal rows in `device_seq` order. The server stores
it. It cannot prove the rows were true when they were written — nothing can, for a file on a phone —
but it does mean a history cannot be quietly rewritten *after* it was claimed, which is the case that
would otherwise be free.

**5. A seat is claimable once.** Two accounts cannot both hold the same seat of the same match. The
server enforces it; the client cannot, and must not pretend to.

## What this costs

Two nullable columns on `local_match` and a small table in the device's mutable store. `ADD COLUMN`
is the one schema change SQLite makes without rewriting a row, and a match written before this
carries nulls and stays perfectly readable — it simply cannot be claimed until its player is named,
which is a prompt, not a loss.

## What it deliberately does not do

- **It does not invent an account.** No sign-in, no enrolment, no recovery, no session. B4 is open
  and this ADR does not pre-empt it: everything above is true whether an account turns out to be a
  passkey, an email, or something else.
- **It does not decide the moment of claiming.** Whether a person is asked at first sign-in, or later
  from Settings, is a design question for whoever draws B4.
- **It does not make the local journal trustworthy.** See decision 3. Anything that presented a
  claimed local history as verified would be exactly the fake completion this repository is built to
  refuse.

## Revisit trigger

B4 lands, or the first sync protocol is written. If either produces a shape where a claim cannot be
one-person-one-act — a shared family device, say, or a club scorer's phone used by twenty people —
decision 2 is the one to re-open, and the book of local people is what makes that re-opening cheap.

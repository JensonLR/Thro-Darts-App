-- A decision does what it says (PD-103).
--
-- Since V040 a moderator could record that something was *hidden* or an account *suspended*, and the record was all
-- that happened: the name stayed on every public surface and the person kept every session. The moderation page
-- (PD-101) had to say so on its face. This gives the two decisions an effect, and adds the one that undoes them.
--
--   * An account can be **suspended**: the hour and the reason are on the row, every session is revoked when it is
--     set, `resolve` refuses a suspended account's tokens on the very next request (ADR-008: authority is resolved
--     per request and never from a token), and sign-in refuses it in words.
--   * A **league** can be private, as a team and a venue already can: off the public list and unnamed. This is also
--     what lets a league started to test with stay out of everybody's way (PD-100's open item), and what lets a
--     league be ended (`dissolved_at`, set once, like a team's).
--   * A decision may be **reinstated**: the suspension lifted, or the hidden thing public again.
--
-- No row is deleted and no column changes type. The one destructive statement replaces a CHECK constraint, which
-- Postgres cannot widen in place.

SET ROLE thro_owner;

ALTER TABLE identity.account
  ADD COLUMN suspended_at     timestamptz,
  ADD COLUMN suspended_reason text,
  ADD CONSTRAINT suspension_has_a_reason
    CHECK ((suspended_at IS NULL) = (suspended_reason IS NULL));
GRANT UPDATE (suspended_at, suspended_reason) ON identity.account TO app_competition;

ALTER TABLE competition.league
  ADD COLUMN visibility   text NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','private')),
  ADD COLUMN dissolved_at timestamptz;

-- APPROVED-DESTRUCTIVE: two CHECK constraints are replaced, not removed. Each is dropped and immediately re-added in
-- the same transaction with 'reinstated' admitted; no row is deleted and no column changes type. Postgres has no way
-- to widen a CHECK in place, so drop-and-add is the only shape this can take.
ALTER TABLE safety.decision DROP CONSTRAINT decision_outcome_check;
ALTER TABLE safety.decision ADD CONSTRAINT decision_outcome_check
  CHECK (outcome IN ('left','hidden','corrected','account_suspended','not_upheld','reinstated'));
ALTER TABLE safety.decision_tally DROP CONSTRAINT decision_tally_outcome_check;
ALTER TABLE safety.decision_tally ADD CONSTRAINT decision_tally_outcome_check
  CHECK (outcome IN ('left','hidden','corrected','account_suspended','not_upheld','reinstated'));

RESET ROLE;

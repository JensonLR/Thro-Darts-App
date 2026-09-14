-- THRØ V004 — darts thrown at a double.
--
-- Recorded on every visit that began on a checkout number, whether or not it ended in one. A player
-- on 40 who throws a single 20 and misses has attempted a double, and without that attempt the
-- checkout percentage computed from the log is silently inflated.
--
-- Forward-only and additive, per ADR-013: the column is nullable because NULL means the attempt
-- count is genuinely unknown, which is a different fact from zero attempts.

-- Run as the owner role so that the default privileges established in V001 govern
-- every table created here. Without this the tables belong to whoever ran the
-- migration, and future-table protection silently does not apply.
SET ROLE thro_owner;

ALTER TABLE read.visit
  ADD COLUMN darts_at_double int
    CHECK (darts_at_double BETWEEN 0 AND 3),
  -- a visit cannot throw more darts at a double than it threw in total
  ADD CONSTRAINT visit_darts_at_double_within_darts_used
    CHECK (darts_at_double IS NULL OR darts_used IS NULL OR darts_at_double <= darts_used);

COMMENT ON COLUMN read.visit.darts_at_double IS
  'Darts thrown at a double in this visit. NULL means unknown, never zero. Only meaningful where '
  'the remaining at the start of the visit was a checkout number.';

-- Leave the session as it was found: a migration runner may share one connection
-- across files, and a leaked role would silently change who owns what comes next.
RESET ROLE;

-- A report is kept until it is not needed (PD-087).
--
-- V040 said "a report is kept: somebody raised it, and that it was raised does not change", and made both
-- tables refuse UPDATE and DELETE outright. That guarantee exists for one reason and it is a good one: a
-- report must not be quietly made to go away by whoever it embarrasses.
--
-- The DPIA (docs/legal/DPIA.md, R2) puts the other side. A report carries free text a reporter wrote, and
-- what a reporter thinks matters may be somebody's health, sexuality or ethnicity. Holding that for ever,
-- about children, with no justification, is not a position that survives an ICO conversation.
--
-- **Both are kept, by narrowing what "kept" protects.** Nobody may delete a report — not an administrator,
-- not the subject, not a support script. The only path out is `safety.forget_decided`, a function whose
-- body is in this migration, which applies one rule to everything at once: a report that has been decided
-- is forgotten two years after the decision. Time forgets it, and nobody chooses which.
--
-- What survives is a **tally** — how many decisions of each outcome an account has had — with no text, no
-- reporter and no dates beyond the first and last. A repeat offender still shows across seasons, which is
-- the thing safeguarding needs; what goes is the words, which is the thing minimisation demands.
--
-- The founder chose two years on 12 September 2026: long enough to see somebody across two seasons, short
-- enough to be proportionate about a child. It is an argument to the function, so changing it is a call
-- site and not a migration.

SET ROLE thro_owner;

CREATE TABLE safety.decision_tally (
  subject_kind text        NOT NULL CHECK (subject_kind IN ('account','team','venue','league','match')),
  subject_id   uuid        NOT NULL,
  outcome      text        NOT NULL CHECK (outcome IN ('left','hidden','corrected','account_suspended','not_upheld')),
  decisions    integer     NOT NULL CHECK (decisions > 0),
  first_at     timestamptz NOT NULL,
  last_at      timestamptz NOT NULL,
  PRIMARY KEY (subject_kind, subject_id, outcome),
  CONSTRAINT a_tally_runs_forwards CHECK (last_at >= first_at)
);

COMMENT ON TABLE safety.decision_tally IS
  'What is left of a forgotten report: that a decision of this outcome was made about this subject, and how '
  'many times. No reporter, no reason, no note. Enough to see a pattern, not enough to re-read an allegation.';

-- The one door. `SET LOCAL` scopes the key to the transaction, so it cannot leak into a later statement on
-- a pooled connection, and no other code sets it.
CREATE OR REPLACE FUNCTION safety.report_is_kept() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('thro.forgetting', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'a report is kept: somebody raised it, and that it was raised does not change';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION safety.decision_is_kept() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('thro.forgetting', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'a decision is kept: it was made, and it is answered by making another';
END;
$$ LANGUAGE plpgsql;

-- Forgets every report whose newest decision is older than `older_than`. Returns how many reports went.
--
-- An **undecided** report is never forgotten however old it is. One that has sat unanswered for two years
-- is a failure of process, and deleting it would tidy the evidence of that away.
CREATE OR REPLACE FUNCTION safety.forget_decided(older_than interval DEFAULT interval '2 years')
RETURNS integer AS $$
DECLARE
  gone integer;
BEGIN
  PERFORM set_config('thro.forgetting', 'on', true);

  CREATE TEMP TABLE forgetting ON COMMIT DROP AS
    SELECT r.report_id, r.subject_kind, r.subject_id
    FROM safety.report r
    WHERE EXISTS (SELECT 1 FROM safety.decision d WHERE d.report_id = r.report_id)
      AND NOT EXISTS (
        SELECT 1 FROM safety.decision d
        WHERE d.report_id = r.report_id AND d.decided_at >= clock_timestamp() - older_than
      );

  INSERT INTO safety.decision_tally AS t (subject_kind, subject_id, outcome, decisions, first_at, last_at)
  SELECT f.subject_kind, f.subject_id, d.outcome, count(*), min(d.decided_at), max(d.decided_at)
  FROM forgetting f
  JOIN safety.decision d ON d.report_id = f.report_id
  GROUP BY f.subject_kind, f.subject_id, d.outcome
  ON CONFLICT (subject_kind, subject_id, outcome) DO UPDATE
    SET decisions = t.decisions + EXCLUDED.decisions,
        first_at  = least(t.first_at, EXCLUDED.first_at),
        last_at   = greatest(t.last_at, EXCLUDED.last_at);

  DELETE FROM safety.decision d USING forgetting f WHERE d.report_id = f.report_id;
  DELETE FROM safety.report r USING forgetting f WHERE r.report_id = f.report_id;
  GET DIAGNOSTICS gone = ROW_COUNT;

  RETURN gone;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION safety.forget_decided IS
  'The only way a report leaves this database. Applies one rule to all of them: decided, and the decision is '
  'older than the period. Nobody chooses which report goes, which is what makes the append-only guarantee '
  'still mean something.';

RESET ROLE;

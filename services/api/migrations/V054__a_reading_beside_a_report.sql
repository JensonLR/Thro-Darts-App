-- A reading beside a report (PD-118).
--
-- THRØ promises to answer every report within a day, and one person answers them. So THRØ asks a System One model —
-- a small, fast model that returns typed probabilities rather than prose — three narrow questions about each report as
-- it arrives: what is it about, might a child be at risk, how serious is it. The answers are written here, beside the
-- report, for the person who answers it. They order the queue and can move a report to the front; they decide nothing.
--
-- A name somebody chose is read too — a display name, a team name — for abuse and for impersonation, and a name that
-- reads badly raises a report of THRØ's own: one with no reporter, because nobody raised it. `reported_by` becomes
-- nullable for exactly that row. The queue never showed the reporter and still does not.

SET ROLE thro_owner;

CREATE TABLE safety.judgment (
  report_id     uuid        PRIMARY KEY REFERENCES safety.report(report_id) ON DELETE CASCADE,
  -- What the model read the report as: one of the categories THRØ asked about, or 'abusive_name' / 'impersonation'
  -- for a name THRØ read on its own.
  category      text        NOT NULL,
  -- How sure the model was of that category (0 to 1). For a name, the probability of the reading itself.
  confidence    double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  -- The probability that the report describes a risk to a child (0 to 1); null for a name THRØ read on its own.
  child_safety  double precision CHECK (child_safety IS NULL OR (child_safety >= 0 AND child_safety <= 1)),
  -- Where the report sits on the severity levels THRØ asked about (0 = nothing to act on … 3 = serious harm).
  severity      double precision CHECK (severity IS NULL OR (severity >= 0 AND severity <= 3)),
  model         text        NOT NULL,
  judged_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE safety.judgment IS
  'PD-118: a System One model''s reading of a report — category, child-safety probability, severity. A hint for the person who answers; never a decision. Goes with its report.';

ALTER TABLE safety.report ALTER COLUMN reported_by DROP NOT NULL;
COMMENT ON COLUMN safety.report.reported_by IS
  'The account that reported it. NULL only for a report THRØ raised itself from its reading of a name (PD-118); a person still answers it.';

-- A report stays append-only (V040's trigger): the reading is taken before the report is written, so whether it is
-- urgent is decided once, and the reading itself is a row of its own beside it.
GRANT SELECT, INSERT ON safety.judgment TO app_competition;

RESET ROLE;

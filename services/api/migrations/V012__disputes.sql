-- THRØ V012 — disputes, adjudications and quarantine.
--
-- All three belong to `trust` (ADR-005), and all three are events before they are rows: the row is
-- a projection you could throw away and rebuild, the event is what happened.
--
-- Quarantine is the subtle one. It **retains** the result, its provenance, its place in the bracket
-- and its visibility; it **suspends** rating eligibility, form contribution, rank denominators and
-- cohort averages. It is an orthogonal axis and NOT a ninth verification state, because overloading
-- that enum would overwrite the pre-quarantine provenance irrecoverably — and a device fault
-- triggers quarantine as readily as fraud, so it carries no accusation.

SET ROLE thro_owner;

CREATE TABLE trust.dispute (
  dispute_id   uuid        PRIMARY KEY,
  match_id     uuid        NOT NULL REFERENCES evidence.match(match_id),
  raised_by    uuid        NOT NULL,
  -- A dispute localises to a leg. "The whole match is wrong" is a different and rarer claim, and
  -- NULL says it rather than pretending leg 1 was meant.
  leg_ordinal  int         CHECK (leg_ordinal IS NULL OR leg_ordinal > 0),
  reason       text        NOT NULL,
  raised_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  raised_event uuid        NOT NULL REFERENCES evidence.event(event_id),
  resolved_at  timestamptz,
  resolved_by  uuid,
  resolution   text CHECK (resolution IN ('upheld','rejected','withdrawn')),
  resolved_event uuid REFERENCES evidence.event(event_id),
  CONSTRAINT dispute_resolution_is_complete
    CHECK (num_nonnulls(resolved_at, resolved_by, resolution, resolved_event) IN (0, 4))
);

CREATE INDEX dispute_open ON trust.dispute (match_id) WHERE resolved_at IS NULL;

CREATE TABLE trust.quarantine (
  quarantine_id uuid        PRIMARY KEY,
  match_id      uuid        NOT NULL REFERENCES evidence.match(match_id),
  reason_code   text        NOT NULL,
  reason        text        NOT NULL,
  applied_by    uuid        NOT NULL,
  applied_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  applied_event uuid        NOT NULL REFERENCES evidence.event(event_id),
  lifted_at     timestamptz,
  lifted_by     uuid,
  lifted_event  uuid REFERENCES evidence.event(event_id),
  CONSTRAINT quarantine_lift_is_complete
    CHECK (num_nonnulls(lifted_at, lifted_by, lifted_event) IN (0, 3))
);

CREATE INDEX quarantine_active ON trust.quarantine (match_id) WHERE lifted_at IS NULL;

COMMENT ON TABLE trust.quarantine IS
  'Suspension of a result''s eligibility pending review, WITHOUT accusation. Retains the result, '
  'its provenance, its bracket place and its visibility. Reversible, and a lift is recorded rather '
  'than a deletion — that a match was reviewed and cleared is itself worth knowing.';

-- A resolution or a lift can be recorded once. Reopening is a new dispute, not an edit of the old
-- one: rewriting the first would erase that the question was asked and answered.
--
-- Two functions rather than one with a TG_TABLE_NAME guard: PL/pgSQL resolves the field references
-- in both branches whatever the guard says, so a shared function fails on whichever table lacks the
-- other's column.
CREATE FUNCTION trust.dispute_resolution_is_final() RETURNS trigger AS $$
BEGIN
  IF OLD.resolved_at IS NOT NULL AND NEW.resolved_at IS DISTINCT FROM OLD.resolved_at THEN
    RAISE EXCEPTION 'a dispute resolution cannot be rewritten (dispute %)', OLD.dispute_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION trust.quarantine_lift_is_final() RETURNS trigger AS $$
BEGIN
  IF OLD.lifted_at IS NOT NULL AND NEW.lifted_at IS DISTINCT FROM OLD.lifted_at THEN
    RAISE EXCEPTION 'a quarantine lift cannot be rewritten (quarantine %)', OLD.quarantine_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER dispute_resolution_is_final BEFORE UPDATE ON trust.dispute
  FOR EACH ROW EXECUTE FUNCTION trust.dispute_resolution_is_final();
CREATE TRIGGER quarantine_lift_is_final BEFORE UPDATE ON trust.quarantine
  FOR EACH ROW EXECUTE FUNCTION trust.quarantine_lift_is_final();

GRANT SELECT ON trust.dispute, trust.quarantine
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT, UPDATE ON trust.dispute, trust.quarantine TO app_trust;
REVOKE DELETE, TRUNCATE ON trust.dispute, trust.quarantine
  FROM app_match, app_trust, app_rating, app_read, app_competition;

RESET ROLE;

-- THRØ V009 — a module may append only to the streams it owns.
--
-- ADR-005 corrected its own first rule here. Revision 1 said `match` was the *only* module
-- permitted to append, which stopped being true the moment ADR-006 made per-leg attestation a
-- first-class event owned by `trust`. The corrected rule is narrower and enforceable:
--
--   | Match evidence — visits, legs, corrections        | match       |
--   | Attestations, disputes, adjudications, quarantine | trust       |
--   | Competition lifecycle — draws, check-in, boards   | competition |
--
-- Until now every application role held blanket INSERT on evidence.event, so the boundary was a
-- convention that nothing checked. A convention that nothing checks is not a boundary — and the
-- schema test that "asserted" it was written to pass either way, which is worse than no test.
--
-- `rating` appears in no row of that table on purpose. ADR-009 makes it a pure downstream consumer:
-- it never writes to match or trust, and that one-way dependency is exactly what makes a rating
-- replay safely re-runnable.

SET ROLE thro_owner;

CREATE FUNCTION evidence.enforce_stream_ownership() RETURNS trigger AS $$
DECLARE
  owner_role text;
BEGIN
  owner_role := CASE
    WHEN NEW.event_type IN ('VisitRecorded','VisitCorrected','LegCompleted','MatchCompleted')
      THEN 'app_match'
    WHEN NEW.event_type IN ('LegAttested','DisputeRaised','DisputeResolved',
                            'Quarantined','QuarantineLifted','Adjudicated')
      THEN 'app_trust'
    WHEN NEW.event_type IN ('DrawMade','CheckedIn','BoardAssigned','EntryAccepted')
      THEN 'app_competition'
    ELSE NULL
  END;

  IF owner_role IS NULL THEN
    RAISE EXCEPTION 'unknown event type %: every stream must have a named owner', NEW.event_type;
  END IF;

  -- The owner role, or a superuser running migrations and tests. pg_has_role covers membership,
  -- so a role granted app_match may append match evidence.
  IF NOT pg_has_role(current_user, owner_role, 'USAGE')
     AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION '% may not append % — that stream belongs to %',
      current_user, NEW.event_type, owner_role;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_stream_ownership BEFORE INSERT ON evidence.event
  FOR EACH ROW EXECUTE FUNCTION evidence.enforce_stream_ownership();

RESET ROLE;

-- The competition module's role did not exist yet; the boundary needs it to be nameable.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_competition') THEN
    CREATE ROLE app_competition NOLOGIN;
  END IF;
END $$;

SET ROLE thro_owner;
GRANT USAGE ON SCHEMA evidence, trust, read, audit TO app_competition;
GRANT SELECT, INSERT ON evidence.event, evidence.command_receipt TO app_competition;
GRANT SELECT ON evidence.match TO app_competition;
GRANT INSERT ON audit.decision TO app_competition;
GRANT USAGE ON SEQUENCE audit.decision_seq_seq TO app_competition;

-- rating is a pure downstream consumer and appends nothing to the evidence log.
REVOKE INSERT ON evidence.event FROM app_rating;

RESET ROLE;

-- THRØ V034 — a match that ended short is recorded as having ended, and nothing is added after it.
--
-- PD-016 lets a match end short of its format: one player retires, and the other wins; or it is
-- abandoned, and nobody does. The phone has recorded both since PD-016 as one final journal row, and
-- PD-040's upload refused to send such a match, because the server had no event for an ending — the
-- visits alone would have left THRØ holding a record that says the match is still going.
--
-- **One event, `MatchEndedShort`, on the match stream.** It is the same act the journal row records —
-- a participant saying, at the oche, that this match stops here — so it is written by the same app role,
-- in the same device sequence, as the visits before it. Its payload says how it ended and, for a
-- retirement, which seat retired. The winner is not stored: it is the other seat, and a stored copy of
-- an inference is a second thing that can disagree with the first. An abandonment names nobody.
--
-- **Nothing is added after it.** A trigger refuses a visit, a retraction or a second ending for a match
-- that has ended — except a row the stream already holds, because an upload is resent whole and
-- `ON CONFLICT DO NOTHING` has to be reached for the resend to land as nothing. An official's
-- correction and the trust events (attestations, disputes) are not refused: they are about the record,
-- and a match that has ended is exactly when they happen.

SET ROLE thro_owner;

CREATE OR REPLACE FUNCTION evidence.enforce_stream_ownership() RETURNS trigger AS $$
DECLARE
  owner_role text;
BEGIN
  owner_role := CASE
    -- MatchEndedShort joins the match stream for the reason VisitRetracted did (V032): the same app
    -- role, the same match, a participant, the same device sequence as the visits before it.
    WHEN NEW.event_type IN ('VisitRecorded','VisitCorrected','VisitRetracted','LegCompleted',
                            'MatchCompleted','MatchEndedShort')
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

  IF NOT pg_has_role(current_user, owner_role, 'USAGE')
     AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION '% may not append % — that stream belongs to %',
      current_user, NEW.event_type, owner_role;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- An ending says how, and a retirement says who. Held by the table rather than by the upload, so a
-- route written later cannot store an ending that means nothing.
ALTER TABLE evidence.event ADD CONSTRAINT an_ending_says_how CHECK (
  event_type <> 'MatchEndedShort'
  OR payload->>'ending' = 'abandoned'
  OR (payload->>'ending' = 'retired' AND payload->>'seat' IN ('home', 'away'))
);

CREATE FUNCTION evidence.nothing_after_the_end() RETURNS trigger AS $$
BEGIN
  IF NEW.event_type IN ('VisitRecorded', 'VisitRetracted', 'MatchEndedShort')
     AND EXISTS (SELECT 1 FROM evidence.event
                  WHERE match_id = NEW.match_id AND event_type = 'MatchEndedShort')
     -- A resend: the stream already holds this place in the device's sequence, and the INSERT's
     -- ON CONFLICT will make it nothing. Refusing it here would break the idempotence PD-040 rests on.
     AND NOT EXISTS (SELECT 1 FROM evidence.event
                      WHERE match_id = NEW.match_id AND device_id = NEW.device_id
                        AND device_seq = NEW.device_seq) THEN
    RAISE EXCEPTION 'match % has ended; nothing more is added to it', NEW.match_id
      USING ERRCODE = 'check_violation', CONSTRAINT = 'nothing_after_the_end';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER nothing_after_the_end BEFORE INSERT ON evidence.event
  FOR EACH ROW EXECUTE FUNCTION evidence.nothing_after_the_end();

RESET ROLE;

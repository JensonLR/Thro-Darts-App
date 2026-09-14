-- THRØ V032 — a retraction is evidence, and it belongs to the match stream.
--
-- PD-004: a mis-keyed visit is undone by a RETRACTION, never an edit. The phone has always written
-- one — an INSERT carrying `corrects_seq`, so the board can draw the struck figure and the record
-- keeps what was written. The server had nowhere to put it: `evidence.event` takes any event type
-- the stream-ownership trigger knows about, and it knew `VisitCorrected` (an official's correction,
-- V007) and nothing for a player striking their own entry at the oche.
--
-- Those are two different acts by two different people and they stay two event types. A correction
-- is made by somebody with `match.correct` authority who is not playing; a retraction is made by
-- the player, on their own phone, seconds later, and needs no authority beyond being in the match.
-- Giving the first one's name to the second would make an audit read as if an official had been
-- present at a match in a pub.
--
-- Nothing is added to the table: `event_type` carries no CHECK, and `corrects_event_id` has named
-- the superseded event since V006. Only the trigger has to learn the word.

SET ROLE thro_owner;

CREATE OR REPLACE FUNCTION evidence.enforce_stream_ownership() RETURNS trigger AS $$
DECLARE
  owner_role text;
BEGIN
  owner_role := CASE
    -- VisitRetracted joins the match stream: it is written by the same app role, about the same
    -- match, by a participant, in the same device sequence as the visit it strikes.
    WHEN NEW.event_type IN ('VisitRecorded','VisitCorrected','VisitRetracted','LegCompleted','MatchCompleted')
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

-- A match sent from a phone is one player's word until the other confirms it (PD-011, PD-040). The
-- flag is on the match rather than on each event, because it is a fact about how the whole record
-- reached THRØ and not about any one visit.
ALTER TABLE evidence.match ADD COLUMN self_reported boolean NOT NULL DEFAULT false;

-- Minting the other seat (PD-040). A match sent from a phone has one player THRØ knows and one it
-- does not, so the upload needs a competitor row for the second seat — and `app_match` owns the
-- evidence schema and nothing else, which is the right shape and stops it here.
--
-- One narrow function rather than a grant, for the same reason erasure got one (V031): handing the
-- match role standing INSERT on `competition.player` would let the thing that writes visits invent
-- people at any time. This invents exactly one, unclaimed, named by nobody, attributed to whoever
-- asked for it — which is all an opponent on somebody's phone is until they claim it themselves.
CREATE FUNCTION competition.mint_competitor(by uuid) RETURNS uuid AS $$
DECLARE id uuid := gen_random_uuid();
BEGIN
  INSERT INTO competition.player (player_id, source, created_by) VALUES (id, 'self', by);
  RETURN id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION competition.mint_competitor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION competition.mint_competitor(uuid) TO app_match, app_competition;

RESET ROLE;

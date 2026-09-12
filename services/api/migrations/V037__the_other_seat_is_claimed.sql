-- THRØ V037 — the other player claims their seat by a code, and answers for the result (PD-043).
--
-- A match sent from a phone (PD-040) names one person and one seat. The other seat is a competitor THRØ
-- minted and holds no name for, because the other player never told THRØ who they were. This is how
-- they do, and how the match stops being one player's word.
--
-- **A code, made by the player who sent the match, for the other seat.** Said across the table or
-- shared, and entered on the other player's own phone, it records that the seat is theirs. Codes are how
-- THRØ lets two people agree they know each other (friends V028, teams V029): there is no directory to
-- search, and a code handed over in person is consent from both sides.
--
-- **A seat claim, not a claim on the competitor.** The other player already has a competitor of their
-- own — every account does (V014) — and an account holds one live claim. So the SEAT is claimed and
-- nothing is rewritten: the match still names the competitor it was sent with, the evidence under it
-- stays exactly as it was written, and `competition.seat_claim` says whose seat that competitor stood in
-- for. It is the narrow identity event V014 deferred ("merging is a separate, later identity event"),
-- scoped to one seat of one match rather than to a whole person.
--
-- **Then the other player answers for the result**, on the trust stream: `ResultConfirmed` or
-- `ResultContested`, naming the seat that answered. The match's standing — self-reported, confirmed by
-- both, or disputed — is read from those every time and stored nowhere, so it cannot drift from them.

SET ROLE thro_owner;

CREATE TABLE competition.match_claim_code (
  code        text        PRIMARY KEY CHECK (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  match_id    uuid        NOT NULL REFERENCES evidence.match(match_id),
  seat        text        NOT NULL CHECK (seat IN ('home', 'away')),
  made_by     uuid        NOT NULL REFERENCES competition.player(player_id),
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at  timestamptz NOT NULL,
  used_by     uuid        REFERENCES competition.player(player_id),
  used_at     timestamptz,
  CONSTRAINT match_code_use_is_complete CHECK ((used_by IS NULL) = (used_at IS NULL)),
  CONSTRAINT match_code_lasts_a_while CHECK (expires_at > created_at AND expires_at <= created_at + interval '30 days')
);
CREATE INDEX match_claim_code_by_seat ON competition.match_claim_code (match_id, seat);

-- A code is used once, and nothing about it is rewritten.
CREATE FUNCTION competition.match_claim_code_is_kept() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'a match code is kept'; END IF;
  IF OLD.used_at IS NOT NULL THEN RAISE EXCEPTION 'a match code is used once'; END IF;
  IF NEW.code <> OLD.code OR NEW.match_id <> OLD.match_id OR NEW.seat <> OLD.seat
     OR NEW.made_by <> OLD.made_by OR NEW.expires_at <> OLD.expires_at THEN
    RAISE EXCEPTION 'a match code is not rewritten; it is used, once';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER match_claim_code_is_kept BEFORE UPDATE OR DELETE ON competition.match_claim_code
  FOR EACH ROW EXECUTE FUNCTION competition.match_claim_code_is_kept();

-- One claim per seat, one per code, and a claim is history rather than a setting.
CREATE TABLE competition.seat_claim (
  match_id    uuid        NOT NULL REFERENCES evidence.match(match_id),
  seat        text        NOT NULL CHECK (seat IN ('home', 'away')),
  player_id   uuid        NOT NULL REFERENCES competition.player(player_id),
  code        text        NOT NULL UNIQUE REFERENCES competition.match_claim_code(code),
  claimed_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (match_id, seat)
);
CREATE INDEX seat_claim_by_player ON competition.seat_claim (player_id);

CREATE FUNCTION competition.seat_claim_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'a seat claim is kept: it records who sat there, and that does not change';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER seat_claim_is_kept BEFORE UPDATE OR DELETE ON competition.seat_claim
  FOR EACH ROW EXECUTE FUNCTION competition.seat_claim_is_kept();

-- Which seat a player sits in: directly, or by a seat they claimed. One narrow function rather than a
-- grant, so the match and trust roles — which admit a watcher and take an answer — can ask this one
-- question of the competition schema and nothing else.
CREATE FUNCTION competition.seat_of(m uuid, p uuid) RETURNS text AS $$
  SELECT CASE
           WHEN em.home_id = p THEN 'home'
           WHEN em.away_id = p THEN 'away'
           ELSE (SELECT sc.seat FROM competition.seat_claim sc WHERE sc.match_id = m AND sc.player_id = p)
         END
    FROM evidence.match em
   WHERE em.match_id = m;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

REVOKE ALL ON FUNCTION competition.seat_of(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION competition.seat_of(uuid, uuid) TO app_match, app_trust, app_read, app_competition;

-- The answers join the trust stream, beside the attestations and disputes that are its other opinions.
CREATE OR REPLACE FUNCTION evidence.enforce_stream_ownership() RETURNS trigger AS $$
DECLARE
  owner_role text;
BEGIN
  owner_role := CASE
    WHEN NEW.event_type IN ('VisitRecorded','VisitCorrected','VisitRetracted','LegCompleted',
                            'MatchCompleted','MatchEndedShort')
      THEN 'app_match'
    -- ResultConfirmed and ResultContested (V037): the other player's answer for a result they did not
    -- send. An opinion about the record, like an attestation, so the same stream owns it.
    WHEN NEW.event_type IN ('LegAttested','DisputeRaised','DisputeResolved',
                            'Quarantined','QuarantineLifted','Adjudicated',
                            'ResultConfirmed','ResultContested')
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

-- An answer names the seat that gave it. Written so it cannot come out NULL (V035's lesson).
ALTER TABLE evidence.event ADD CONSTRAINT an_answer_names_its_seat CHECK (
  event_type NOT IN ('ResultConfirmed', 'ResultContested')
  OR coalesce(payload->>'seat' IN ('home', 'away'), false)
);

-- Codes are the competition role's alone: made, looked up and used there. Nothing that reads a match
-- back needs one. A seat claim is read wherever a match is.
GRANT SELECT, INSERT ON competition.match_claim_code TO app_competition;
GRANT UPDATE (used_by, used_at) ON competition.match_claim_code TO app_competition;
GRANT SELECT ON competition.seat_claim TO app_read, app_competition;
GRANT INSERT ON competition.seat_claim TO app_competition;

RESET ROLE;

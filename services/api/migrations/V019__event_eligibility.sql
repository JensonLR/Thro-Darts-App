-- THRØ V019 — what an event requires of an entrant, stated by the organiser, checkable by THRØ.
--
-- V017 let discovery say "open entry" and nothing else honestly: an event whose access is
-- member_only, qualified, restricted or invitational appeared with "eligibility not yet checkable
-- by THRØ", never as eligible, because the requirement lived in the organiser's head. This table
-- is where the organiser states it, in the only terms THRØ can check against its own records:
--
--   team_member        — a live membership of the named team
--   league_registered  — a live registration in the named league season
--   entered_event      — a live entry to the named earlier event (a qualifier)
--   age_band           — the claimed account's age band is the named one
--   invited            — the named player, by name
--
-- Rows are grouped. Rows in the same group are alternatives (a club's A side OR its B side);
-- every group must be satisfied (a member AND under 18). That is enough to say the things a
-- grassroots organiser says, and nothing here lets THRØ say more than it can read.
--
-- What THRØ cannot check stays unsaid. Qualification by result ("top eight of the qualifier"),
-- residence, or any rule outside these five is not a row; discovery then reports "eligibility not
-- stated in terms THRØ can check" and never calls the player eligible. An age band it cannot read
-- is `unknown`, and unknown satisfies nothing — an adult-only event is not open to an unclaimed
-- player and neither is a youth one (ADR-005: unknown is never adult; a child is never exposed by
-- a guess in either direction).
--
-- The requirement is fixed once entries open for it: rows are appended and, if wrong, withdrawn
-- with a reason — never rewritten — so an entrant who was told they were eligible can be shown the
-- rule as it stood when they were told.

SET ROLE thro_owner;

CREATE TABLE competition.event_eligibility (
  requirement_id    uuid        PRIMARY KEY,
  event_id          uuid        NOT NULL REFERENCES competition.event(event_id),
  requirement_group smallint    NOT NULL CHECK (requirement_group > 0),
  kind              text        NOT NULL
                    CHECK (kind IN ('team_member','league_registered','entered_event','age_band','invited')),
  team_id           uuid        REFERENCES competition.team(team_id),
  league_season_id  uuid        REFERENCES competition.league_season(league_season_id),
  qualifier_event_id uuid       REFERENCES competition.event(event_id),
  age_band          text        CHECK (age_band IN ('minor','adult')),
  player_id         uuid        REFERENCES competition.player(player_id),
  stated_by         uuid        NOT NULL,
  stated_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  withdrawn_at      timestamptz,
  withdrawn_by      uuid,
  withdrawn_reason  text,
  -- Exactly the reference the kind needs, and no other.
  CONSTRAINT eligibility_requirement_names_exactly_its_subject CHECK (
       (kind = 'team_member'       AND team_id IS NOT NULL AND league_season_id IS NULL AND qualifier_event_id IS NULL AND age_band IS NULL AND player_id IS NULL)
    OR (kind = 'league_registered' AND league_season_id IS NOT NULL AND team_id IS NULL AND qualifier_event_id IS NULL AND age_band IS NULL AND player_id IS NULL)
    OR (kind = 'entered_event'     AND qualifier_event_id IS NOT NULL AND team_id IS NULL AND league_season_id IS NULL AND age_band IS NULL AND player_id IS NULL)
    OR (kind = 'age_band'          AND age_band IS NOT NULL AND team_id IS NULL AND league_season_id IS NULL AND qualifier_event_id IS NULL AND player_id IS NULL)
    OR (kind = 'invited'           AND player_id IS NOT NULL AND team_id IS NULL AND league_season_id IS NULL AND qualifier_event_id IS NULL AND age_band IS NULL)
  ),
  CONSTRAINT eligibility_qualifier_is_another_event CHECK (qualifier_event_id IS NULL OR qualifier_event_id <> event_id),
  CONSTRAINT eligibility_withdrawal_is_complete
    CHECK ((withdrawn_at IS NULL) = (withdrawn_by IS NULL) AND (withdrawn_at IS NULL) = (withdrawn_reason IS NULL))
);

CREATE INDEX event_eligibility_by_event ON competition.event_eligibility (event_id) WHERE withdrawn_at IS NULL;

-- An open event states no requirement: "open" means open, and a rule on it would make the two
-- columns disagree about who may enter.
CREATE FUNCTION competition.eligibility_is_for_a_gated_event() RETURNS trigger AS $$
BEGIN
  IF (SELECT access FROM competition.event WHERE event_id = NEW.event_id) = 'open' THEN
    RAISE EXCEPTION 'an open event states no eligibility requirement; change its access first'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'eligibility_is_for_a_gated_event';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER eligibility_is_for_a_gated_event
  BEFORE INSERT ON competition.event_eligibility
  FOR EACH ROW EXECUTE FUNCTION competition.eligibility_is_for_a_gated_event();

-- Appended, then withdrawn; never rewritten. The one permitted UPDATE fills the withdrawal.
CREATE FUNCTION competition.eligibility_is_only_withdrawn() RETURNS trigger AS $$
BEGIN
  IF OLD.withdrawn_at IS NOT NULL THEN
    RAISE EXCEPTION 'a withdrawn requirement is history and cannot change'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'eligibility_is_only_withdrawn';
  END IF;
  IF to_jsonb(NEW) - 'withdrawn_at' - 'withdrawn_by' - 'withdrawn_reason'
     IS DISTINCT FROM to_jsonb(OLD) - 'withdrawn_at' - 'withdrawn_by' - 'withdrawn_reason' THEN
    RAISE EXCEPTION 'a stated requirement cannot be rewritten; withdraw it and state another'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'eligibility_is_only_withdrawn';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER eligibility_is_only_withdrawn
  BEFORE UPDATE ON competition.event_eligibility
  FOR EACH ROW EXECUTE FUNCTION competition.eligibility_is_only_withdrawn();

-- One row, one player, one instant: does this requirement hold? Written once so discovery's
-- per-row explanation and the whole-event answer below cannot disagree. An age band comes through
-- the live claim; an unclaimed player has no band here and satisfies neither.
CREATE FUNCTION competition.requirement_holds_for(r competition.event_eligibility, p_player uuid, p_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE r.kind
    WHEN 'team_member' THEN EXISTS (
      SELECT 1 FROM competition.team_membership m
       WHERE m.team_id = r.team_id AND m.player_id = p_player AND m.status = 'active'
         AND m.valid_from <= p_at AND (m.valid_until IS NULL OR m.valid_until > p_at))
    WHEN 'league_registered' THEN EXISTS (
      SELECT 1 FROM competition.player_registration g
       WHERE g.league_season_id = r.league_season_id AND g.player_id = p_player AND g.status = 'registered'
         AND g.valid_from <= p_at AND (g.valid_until IS NULL OR g.valid_until > p_at))
    WHEN 'entered_event' THEN EXISTS (
      SELECT 1 FROM competition.entry en
       WHERE en.event_id = r.qualifier_event_id AND en.withdrawn_at IS NULL
         AND (en.player_id = p_player
              OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = p_player OR player_b = p_player)))
    WHEN 'age_band' THEN EXISTS (
      SELECT 1 FROM identity.player_claim cl JOIN identity.account a ON a.account_id = cl.account_id
       WHERE cl.player_id = p_player AND cl.revoked_at IS NULL AND a.age_band = r.age_band)
    WHEN 'invited' THEN r.player_id = p_player
  END;
$$;

-- The question, answered by the store so every reader gives the same answer: does this player,
-- at this instant, satisfy every live group of this event's requirement? NULL when the event
-- states none — the caller must not read NULL as yes.
CREATE FUNCTION competition.player_satisfies_event(p_player uuid, p_event uuid, p_at timestamptz DEFAULT clock_timestamp())
RETURNS boolean LANGUAGE sql STABLE AS $$
  WITH live AS (
    SELECT * FROM competition.event_eligibility WHERE event_id = p_event AND withdrawn_at IS NULL
  )
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM live) THEN NULL
              ELSE NOT EXISTS (
                SELECT requirement_group FROM live
                EXCEPT
                SELECT requirement_group FROM live r WHERE competition.requirement_holds_for(r, p_player, p_at))
         END;
$$;

COMMENT ON TABLE competition.event_eligibility IS
  'What an event requires of an entrant, in the five terms THRØ can check against its own records. '
  'Groups are alternatives within and conjunction across. An event with no live rows has not stated '
  'its requirement and discovery says so; it never says eligible.';

GRANT SELECT, INSERT, UPDATE (withdrawn_at, withdrawn_by, withdrawn_reason) ON competition.event_eligibility TO app_competition;
GRANT SELECT ON competition.event_eligibility TO app_read;
GRANT EXECUTE ON FUNCTION competition.player_satisfies_event(uuid, uuid, timestamptz) TO app_competition, app_read;
GRANT EXECUTE ON FUNCTION competition.requirement_holds_for(competition.event_eligibility, uuid, timestamptz) TO app_competition, app_read;

RESET ROLE;

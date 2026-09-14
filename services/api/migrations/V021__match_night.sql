-- THRØ V021 — match night: who can play, and who is playing. Execution plan §6, store level.
--
-- Two pieces of organisational state (ADR-018: server-authoritative, versioned, a stale write is
-- refused with the current row), both about a league fixture and one of its two teams:
--
--   availability — a player's own word on whether they can make a fixture, or a captain's on their
--                  behalf. One live row per (fixture, player); every change is appended to
--                  availability_change by trigger with who said it, so "Sam said yes on Monday and
--                  the captain said no on Thursday" is readable.
--   lineup       — the side a team names for a fixture. The lineup row carries the version; the
--                  players are lineup_entry rows tagged with the version they were named under, so
--                  naming a new side writes a new set and the old set is history rather than gone.
--                  No application role can delete an entry; nothing needs to.
--
-- What the store refuses, so no caller can be wrong about it: a team that is not one of the
-- fixture's two; a player who is not a live member of that team at the moment of writing; an entry
-- written under any version but the lineup's current one; and any CHANGE to a lineup once the
-- fixture has a live outcome — the side that played is the side that played. A first naming after
-- the outcome is allowed: a captain filling in the card after the match is recording what happened,
-- and refusing it would leave a played fixture that could never have a side at all. It carries the
-- same trust as the result it accompanies — self-reported until the league accepts it.
--
-- What the store does not decide: how many players a side is, whether they must be registered,
-- whether a captain may pick a player who said they were unavailable. Those are the league's rules
-- (policy) and the captain's judgement; THRØ records the facts and the Secretary can chase them.

SET ROLE thro_owner;

-- ---------------------------------------------------------------------------------------------
-- Availability
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.availability (
  fixture_id   uuid        NOT NULL REFERENCES competition.league_fixture(fixture_id),
  player_id    uuid        NOT NULL REFERENCES competition.player(player_id),
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  status       text        NOT NULL CHECK (status IN ('available','unavailable','maybe')),
  recorded_by  uuid        NOT NULL,
  recorded_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version  int         NOT NULL DEFAULT 1,
  PRIMARY KEY (fixture_id, player_id)
);

CREATE TABLE competition.availability_change (
  change_id    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  fixture_id   uuid        NOT NULL,
  player_id    uuid        NOT NULL,
  team_id      uuid        NOT NULL,
  from_status  text,
  to_status    text        NOT NULL,
  recorded_by  uuid        NOT NULL,
  recorded_at  timestamptz NOT NULL,
  row_version  int         NOT NULL,
  FOREIGN KEY (fixture_id, player_id) REFERENCES competition.availability(fixture_id, player_id)
);
CREATE INDEX availability_change_by_row ON competition.availability_change (fixture_id, player_id, row_version);

CREATE FUNCTION competition.availability_is_recorded() RETURNS trigger AS $$
BEGIN
  INSERT INTO competition.availability_change (fixture_id, player_id, team_id, from_status, to_status, recorded_by, recorded_at, row_version)
  VALUES (NEW.fixture_id, NEW.player_id, NEW.team_id,
          CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status, NEW.recorded_by, NEW.recorded_at, NEW.row_version);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER availability_is_recorded
  AFTER INSERT OR UPDATE ON competition.availability
  FOR EACH ROW EXECUTE FUNCTION competition.availability_is_recorded();

-- ---------------------------------------------------------------------------------------------
-- Lineup
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.lineup (
  fixture_id   uuid        NOT NULL REFERENCES competition.league_fixture(fixture_id),
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  named_by     uuid        NOT NULL,
  named_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  row_version  int         NOT NULL DEFAULT 1,
  PRIMARY KEY (fixture_id, team_id)
);

CREATE TABLE competition.lineup_entry (
  fixture_id     uuid     NOT NULL,
  team_id        uuid     NOT NULL,
  lineup_version int      NOT NULL,
  slot           smallint NOT NULL CHECK (slot > 0),
  player_id      uuid     NOT NULL REFERENCES competition.player(player_id),
  PRIMARY KEY (fixture_id, team_id, lineup_version, slot),
  UNIQUE (fixture_id, team_id, lineup_version, player_id),
  FOREIGN KEY (fixture_id, team_id) REFERENCES competition.lineup(fixture_id, team_id)
);

-- ---------------------------------------------------------------------------------------------
-- What the store refuses
-- ---------------------------------------------------------------------------------------------

-- The team is one of the fixture's two, and the player is a live member of it at the moment of
-- writing. Shared by availability and lineup entries.
CREATE FUNCTION competition.side_and_member(p_fixture uuid, p_team uuid, p_player uuid, p_at timestamptz) RETURNS void AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM competition.league_fixture f WHERE f.fixture_id = p_fixture AND p_team IN (f.home_team_id, f.away_team_id)) THEN
    RAISE EXCEPTION 'that team is not one of the two in this fixture'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'team_is_a_side_of_the_fixture';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM competition.team_membership m
                  WHERE m.team_id = p_team AND m.player_id = p_player AND m.status = 'active'
                    AND m.valid_from <= p_at AND (m.valid_until IS NULL OR m.valid_until > p_at)) THEN
    RAISE EXCEPTION 'that player is not a member of the team at this moment'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'player_is_a_live_member';
  END IF;
END $$ LANGUAGE plpgsql;

CREATE FUNCTION competition.availability_is_for_a_member() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'a versioned row advances by exactly one'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'row_version_advances_by_one';
  END IF;
  PERFORM competition.side_and_member(NEW.fixture_id, NEW.team_id, NEW.player_id, NEW.recorded_at);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER availability_is_for_a_member
  BEFORE INSERT OR UPDATE ON competition.availability
  FOR EACH ROW EXECUTE FUNCTION competition.availability_is_for_a_member();

-- A named lineup cannot change once the fixture has a live outcome (a first naming may still be
-- recorded), and its version advances by one.
CREATE FUNCTION competition.lineup_is_open() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'a versioned row advances by exactly one'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'row_version_advances_by_one';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.fixture_id <> OLD.fixture_id OR NEW.team_id <> OLD.team_id) THEN
    RAISE EXCEPTION 'a lineup belongs to its fixture and team'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_keeps_its_key';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM competition.league_fixture f WHERE f.fixture_id = NEW.fixture_id AND NEW.team_id IN (f.home_team_id, f.away_team_id)) THEN
    RAISE EXCEPTION 'that team is not one of the two in this fixture'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'team_is_a_side_of_the_fixture';
  END IF;
  IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM competition.league_fixture_outcome o
              WHERE o.fixture_id = NEW.fixture_id
                AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s WHERE s.supersedes_outcome_id = o.outcome_id)) THEN
    RAISE EXCEPTION 'the fixture has been played; the side that played is the side that played'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_is_fixed_once_played';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER lineup_is_open
  BEFORE INSERT OR UPDATE ON competition.lineup
  FOR EACH ROW EXECUTE FUNCTION competition.lineup_is_open();

-- An entry is written under the lineup's current version, names a live member, and is never
-- changed: there is no UPDATE for any role, so no trigger needs to say so.
CREATE FUNCTION competition.lineup_entry_is_current() RETURNS trigger AS $$
DECLARE v int; named timestamptz;
BEGIN
  SELECT row_version, named_at INTO v, named FROM competition.lineup WHERE fixture_id = NEW.fixture_id AND team_id = NEW.team_id;
  IF v IS NULL OR NEW.lineup_version <> v THEN
    RAISE EXCEPTION 'a lineup entry is written under the lineup''s current version'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_entry_is_current';
  END IF;
  PERFORM competition.side_and_member(NEW.fixture_id, NEW.team_id, NEW.player_id, named);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER lineup_entry_is_current
  BEFORE INSERT ON competition.lineup_entry
  FOR EACH ROW EXECUTE FUNCTION competition.lineup_entry_is_current();

-- ---------------------------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------------------------

-- The side as currently named, in slot order. Empty when none has been.
CREATE FUNCTION competition.current_lineup(p_fixture uuid, p_team uuid)
RETURNS TABLE (slot smallint, player_id uuid) LANGUAGE sql STABLE AS $$
  SELECT e.slot, e.player_id
    FROM competition.lineup l JOIN competition.lineup_entry e
      ON e.fixture_id = l.fixture_id AND e.team_id = l.team_id AND e.lineup_version = l.row_version
   WHERE l.fixture_id = p_fixture AND l.team_id = p_team
   ORDER BY e.slot
$$;

COMMENT ON TABLE competition.availability IS
  'A player''s word on a fixture, or a captain''s on their behalf — recorded_by says which. One live row per player per fixture; every change is appended to availability_change.';
COMMENT ON TABLE competition.lineup IS
  'The side a team names for a fixture. The row is the version; lineup_entry holds the players under each version, so the old side is history rather than gone. Fixed once the fixture has a live outcome.';

GRANT SELECT ON competition.availability, competition.availability_change, competition.lineup, competition.lineup_entry TO app_read, app_competition;
GRANT INSERT, UPDATE ON competition.availability, competition.lineup TO app_competition;
GRANT INSERT ON competition.availability_change, competition.lineup_entry TO app_competition;
GRANT EXECUTE ON FUNCTION competition.current_lineup(uuid, uuid) TO app_read, app_competition;

RESET ROLE;

-- A move names who made it (PD-120).
--
-- Every change to a fixture's schedule is appended to `league_fixture_change` by trigger, and the row has always had a
-- `changed_by` — which nothing ever filled, because a trigger cannot see who the caller is. The handler now says so the
-- way it already says which proposal a move applies (V016): a session setting, `thro.actor`, set around the write.
-- A change made with no actor named stays null, and the season's history calls that person "An official".

SET ROLE thro_owner;

CREATE OR REPLACE FUNCTION competition.league_fixture_change_is_recorded() RETURNS trigger AS $$
DECLARE
  prop uuid := nullif(current_setting('thro.proposal', true), '')::uuid;
  actor uuid := nullif(current_setting('thro.actor', true), '')::uuid;
BEGIN
  IF OLD.match_id IS NOT NULL AND NEW.match_id IS DISTINCT FROM OLD.match_id THEN
    RAISE EXCEPTION 'a fixture''s match is set once (fixture %)', OLD.fixture_id;
  END IF;
  IF NEW.home_team_id <> OLD.home_team_id OR NEW.away_team_id <> OLD.away_team_id
     OR NEW.league_season_id <> OLD.league_season_id THEN
    RAISE EXCEPTION 'who plays whom in which season is fixed; void it and make another (fixture %)',
      OLD.fixture_id;
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'stale write: fixture % is at version %, not %', OLD.fixture_id,
      OLD.row_version, NEW.row_version - 1;
  END IF;
  IF NEW.schedule_state IS DISTINCT FROM OLD.schedule_state
     OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
     OR NEW.venue_id IS DISTINCT FROM OLD.venue_id THEN
    INSERT INTO competition.league_fixture_change
      (fixture_id, from_state, to_state, from_scheduled_at, to_scheduled_at, from_venue_id, to_venue_id, proposal_id, changed_by)
    VALUES (OLD.fixture_id, OLD.schedule_state, NEW.schedule_state, OLD.scheduled_at, NEW.scheduled_at,
            OLD.venue_id, NEW.venue_id, prop, actor);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

RESET ROLE;

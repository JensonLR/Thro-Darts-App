-- THRØ V041 — what each team in a league season has actually done, and the guard on the rule that orders it
-- (PD-054, PD-053).
--
-- **A standings table is never a row.** `OrganisationTest` asserts that no table in `competition` has
-- "standing" in its name, and that is the guarantee: a table is computed from the fixtures under it on every
-- read, so it cannot drift from them, cannot be edited into disagreeing with them, and cannot be left behind
-- by a corrected result. What is added here is arithmetic and a constraint — no stored table, no projection
-- row, nothing to rebuild.
--
-- **The live outcome of a fixture is not a column.** It is the outcome nobody has superseded, minus the
-- voids. That predicate is already written three times — V014's `outcome_is_a_recorded_decision`, V021's
-- lineup guard, and V022's — and only V022 excludes voids, so two of the three are subtly different from
-- each other. This was about to become the fourth copy. It is written once, here, and the tallies read it.
--
-- **This function decides nothing a league has the right to decide.** It counts: fixtures played, legs
-- scored and conceded, wins, draws and losses, and awards kept apart from all of it. What a win is worth,
-- what a walkover is worth, and how a tie is broken are the league's own rules (PD-054), applied above this
-- in `Standings.kt` from an approved policy, and named on every table so nobody mistakes THRØ's standard for
-- their league's constitution.

SET ROLE thro_owner;

-- Awards and walkovers are counted apart from legs on purpose (ADR-012): inventing a scoreline for a
-- fixture nobody played would pollute every leg-difference tie-break and reward an unplayed match in any
-- future rating. They arrive as counts, and the policy above decides what they are worth.
CREATE FUNCTION competition.league_tallies(p_season uuid, p_division uuid DEFAULT NULL)
RETURNS TABLE (
  team_id          uuid,
  team_name        text,
  division_id      uuid,
  played           int,   -- fixtures with a played outcome; awards are counted separately
  won              int,
  drawn            int,
  lost             int,
  legs_for         int,
  legs_against     int,
  awarded_for      int,   -- awarded or walked over to this team
  awarded_against  int,   -- awarded or walked over to the other side
  evidenced        int    -- of the played fixtures, how many cite a match scored on THRØ (PD-020)
) LANGUAGE sql STABLE AS $$
  WITH side AS (
    -- The teams the LEAGUE has, never the ones that say they play in it. A claim (PD-049, V039) is a team
    -- speaking about itself and is not a place in anybody's table; this reads `team_affiliation` only, so
    -- that separation is structural rather than a filter somebody could forget.
    SELECT ta.team_id, t.name AS team_name, ta.division_id
      FROM competition.team_affiliation ta
      JOIN competition.team t ON t.team_id = ta.team_id
     WHERE ta.league_season_id = p_season
       AND ta.status = 'accepted'
       AND ta.valid_until IS NULL
       AND (p_division IS NULL OR ta.division_id = p_division)
  ),
  live AS (
    SELECT f.fixture_id, f.home_team_id, f.away_team_id,
           o.kind, o.legs_home, o.legs_away, o.to_team_id, f.match_id
      FROM competition.league_fixture f
      JOIN competition.league_fixture_outcome o ON o.fixture_id = f.fixture_id
     WHERE f.league_season_id = p_season
       AND o.kind <> 'void'
       AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                        WHERE s.supersedes_outcome_id = o.outcome_id)
       -- Both sides must be in scope, or a fixture against a team this division does not have would be
       -- counted into somebody else's row.
       AND EXISTS (SELECT 1 FROM side h WHERE h.team_id = f.home_team_id)
       AND EXISTS (SELECT 1 FROM side a WHERE a.team_id = f.away_team_id)
  ),
  -- One row per team per fixture, read from that team's own side of it.
  seen AS (
    SELECT l.home_team_id AS team_id, l.fixture_id, l.kind,
           l.legs_home AS legs_for, l.legs_away AS legs_against,
           (l.to_team_id = l.home_team_id) AS awarded_to_me,
           l.match_id
      FROM live l
    UNION ALL
    SELECT l.away_team_id, l.fixture_id, l.kind,
           l.legs_away, l.legs_home,
           (l.to_team_id = l.away_team_id),
           l.match_id
      FROM live l
  )
  -- LEFT JOIN, so an affiliated team that has played nothing is a row of zeroes rather than a team missing
  -- from its own league's table.
  SELECT s.team_id, s.team_name, s.division_id,
         count(x.fixture_id) FILTER (WHERE x.kind = 'played')::int,
         count(*) FILTER (WHERE x.kind = 'played' AND x.legs_for > x.legs_against)::int,
         count(*) FILTER (WHERE x.kind = 'played' AND x.legs_for = x.legs_against)::int,
         count(*) FILTER (WHERE x.kind = 'played' AND x.legs_for < x.legs_against)::int,
         coalesce(sum(x.legs_for) FILTER (WHERE x.kind = 'played'), 0)::int,
         coalesce(sum(x.legs_against) FILTER (WHERE x.kind = 'played'), 0)::int,
         count(*) FILTER (WHERE x.kind IN ('awarded','walkover') AND x.awarded_to_me)::int,
         count(*) FILTER (WHERE x.kind IN ('awarded','walkover') AND NOT x.awarded_to_me)::int,
         count(*) FILTER (WHERE x.kind = 'played' AND x.match_id IS NOT NULL)::int
    FROM side s
    LEFT JOIN seen x ON x.team_id = s.team_id
   GROUP BY s.team_id, s.team_name, s.division_id
   -- A total order out of the database, because the ranker above sorts stably: rows the league's declared
   -- tie-break cannot separate come out in the order they arrived, and an unspecified order here would make
   -- the same table reorder itself between two reads.
   ORDER BY s.team_name, s.team_id;
$$;

GRANT EXECUTE ON FUNCTION competition.league_tallies(uuid, uuid) TO app_read, app_competition;

-- V014 added `league_season.standings_policy_id` to pin the rule a finished season was ordered under, so a
-- later tie-break cannot re-order a season already played. Nothing has ever written it, and the plain
-- foreign key would accept any policy of any authority — an event's registration rule could be pinned as a
-- league's points rule, and the table would be ordered by something unrelated with nothing complaining.
CREATE FUNCTION competition.standings_policy_belongs_to_the_league() RETURNS trigger AS $$
BEGIN
  IF NEW.standings_policy_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM competition.policy p
     WHERE p.policy_id = NEW.standings_policy_id
       AND p.approval_state IN ('approved','superseded')
       AND p.kind IN ('points','tie_break')
       AND ((p.authority_kind = 'league_season' AND p.league_season_id = NEW.league_season_id)
         OR (p.authority_kind = 'league'        AND p.league_id        = NEW.league_id))
  ) THEN
    RAISE EXCEPTION 'a season is ordered by an approved points or tie_break policy of its own league; % is not one',
                    NEW.standings_policy_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER standings_policy_belongs_to_the_league
  BEFORE INSERT OR UPDATE OF standings_policy_id ON competition.league_season
  FOR EACH ROW EXECUTE FUNCTION competition.standings_policy_belongs_to_the_league();

RESET ROLE;

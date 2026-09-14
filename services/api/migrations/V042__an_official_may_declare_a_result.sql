-- THRØ V042 — a named official may declare a result nobody scored on THRØ (PD-055).
--
-- **The server was stricter than the phone, and wrong to be.** V014 refuses a `played` outcome unless the
-- fixture cites a match, so a league could award a fixture but could not record that Grange A won it 5–2 on
-- a Thursday with a paper card. The phone's own club book has always allowed both and kept them apart — its
-- constraint "refuses a scored result with no match and an official's word with nobody's name" — so a league
-- secretary could keep their season on a phone and not on THRØ. That is the wrong way round.
--
-- **A declared result is a scoreline with a person's name on it and no match behind it.** It counts in the
-- table exactly as a played one does, because it is what happened; it is never evidence, because nobody
-- recorded it happening. `decided_by` is already NOT NULL, so the name is structural: there is no way to
-- declare a result and leave nobody accountable for it.
--
-- **A fixture that has a match cannot have a declared result.** Where a match was scored on THRØ, the result
-- is read from it; declaring a different scoreline over the top would be an official overwriting evidence.
-- Correcting a played result is what superseding is for, and that still works.

SET ROLE thro_owner;

-- APPROVED-DESTRUCTIVE: three CHECK constraints are replaced, not removed. Each is dropped and immediately
-- re-added in the same transaction with 'declared' admitted; no row is deleted and no column changes type.
-- Postgres has no way to widen a CHECK in place, so drop-and-add is the only shape this can take.
ALTER TABLE competition.league_fixture_outcome DROP CONSTRAINT league_fixture_outcome_kind_check;
ALTER TABLE competition.league_fixture_outcome ADD CONSTRAINT league_fixture_outcome_kind_check
  CHECK (kind IN ('played','declared','awarded','walkover','void'));

-- A result with a scoreline carries both halves of it, however it was arrived at.
ALTER TABLE competition.league_fixture_outcome DROP CONSTRAINT outcome_played_has_legs;
ALTER TABLE competition.league_fixture_outcome ADD CONSTRAINT outcome_with_a_score_has_both_halves
  CHECK (kind NOT IN ('played','declared') OR (legs_home IS NOT NULL AND legs_away IS NOT NULL));

-- And a result with no scoreline has none invented for it: an award and a walkover stay empty (ADR-012).
ALTER TABLE competition.league_fixture_outcome DROP CONSTRAINT outcome_unplayed_has_no_scoreline;
ALTER TABLE competition.league_fixture_outcome ADD CONSTRAINT outcome_without_a_score_has_none
  CHECK (kind IN ('played','declared') OR (legs_home IS NULL AND legs_away IS NULL));

-- The recorded-decision trigger, with the two rules a declared result adds.
CREATE OR REPLACE FUNCTION competition.outcome_is_a_recorded_decision() RETURNS trigger AS $$
DECLARE
  f competition.league_fixture%ROWTYPE;
  live int;
BEGIN
  SELECT * INTO f FROM competition.league_fixture WHERE fixture_id = NEW.fixture_id;
  IF NEW.to_team_id IS NOT NULL AND NEW.to_team_id NOT IN (f.home_team_id, f.away_team_id) THEN
    RAISE EXCEPTION 'an award must go to one of the two teams (fixture %)', NEW.fixture_id;
  END IF;
  IF NEW.kind = 'played' AND f.match_id IS NULL THEN
    RAISE EXCEPTION 'a played outcome needs the fixture''s match (fixture %)', NEW.fixture_id;
  END IF;
  -- Where a match was scored on THRØ the result is read from it. An official declaring a scoreline over the
  -- top of one would be overwriting evidence with a recollection; correcting a played result is what
  -- superseding is for (PD-055).
  IF NEW.kind = 'declared' AND f.match_id IS NOT NULL THEN
    RAISE EXCEPTION 'fixture % was scored on THRØ, so its result is read from the match, not declared',
      NEW.fixture_id;
  END IF;
  SELECT count(*) INTO live FROM competition.league_fixture_outcome o
    WHERE o.fixture_id = NEW.fixture_id
      AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                        WHERE s.supersedes_outcome_id = o.outcome_id)
      AND o.outcome_id IS DISTINCT FROM NEW.supersedes_outcome_id;
  IF live > 0 THEN
    RAISE EXCEPTION 'fixture % already has an outcome; a new decision must supersede it', NEW.fixture_id;
  END IF;
  IF NEW.supersedes_outcome_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM competition.league_fixture_outcome p
        WHERE p.outcome_id = NEW.supersedes_outcome_id AND p.fixture_id = NEW.fixture_id) THEN
    RAISE EXCEPTION 'an outcome may only supersede one of its own fixture (fixture %)', NEW.fixture_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- The tallies, taught the difference. A declared result counts in the table exactly as a played one does —
-- it is what happened — and `evidenced` counts only the played ones, which is what makes that column mean
-- something: before this migration every played outcome cited a match by construction, so the count was
-- always the whole column and told nobody anything (PD-020).
CREATE OR REPLACE FUNCTION competition.league_tallies(p_season uuid, p_division uuid DEFAULT NULL)
RETURNS TABLE (
  team_id          uuid,
  team_name        text,
  division_id      uuid,
  played           int,
  won              int,
  drawn            int,
  lost             int,
  legs_for         int,
  legs_against     int,
  awarded_for      int,
  awarded_against  int,
  evidenced        int
) LANGUAGE sql STABLE AS $$
  WITH side AS (
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
       AND EXISTS (SELECT 1 FROM side h WHERE h.team_id = f.home_team_id)
       AND EXISTS (SELECT 1 FROM side a WHERE a.team_id = f.away_team_id)
  ),
  seen AS (
    SELECT l.home_team_id AS team_id, l.fixture_id, l.kind,
           l.legs_home AS legs_for, l.legs_away AS legs_against,
           (l.to_team_id = l.home_team_id) AS awarded_to_me, l.match_id
      FROM live l
    UNION ALL
    SELECT l.away_team_id, l.fixture_id, l.kind,
           l.legs_away, l.legs_home,
           (l.to_team_id = l.away_team_id),
           l.match_id
      FROM live l
  )
  SELECT s.team_id, s.team_name, s.division_id,
         count(x.fixture_id) FILTER (WHERE x.kind IN ('played','declared'))::int,
         count(*) FILTER (WHERE x.kind IN ('played','declared') AND x.legs_for > x.legs_against)::int,
         count(*) FILTER (WHERE x.kind IN ('played','declared') AND x.legs_for = x.legs_against)::int,
         count(*) FILTER (WHERE x.kind IN ('played','declared') AND x.legs_for < x.legs_against)::int,
         coalesce(sum(x.legs_for) FILTER (WHERE x.kind IN ('played','declared')), 0)::int,
         coalesce(sum(x.legs_against) FILTER (WHERE x.kind IN ('played','declared')), 0)::int,
         count(*) FILTER (WHERE x.kind IN ('awarded','walkover') AND x.awarded_to_me)::int,
         count(*) FILTER (WHERE x.kind IN ('awarded','walkover') AND NOT x.awarded_to_me)::int,
         count(*) FILTER (WHERE x.kind = 'played')::int
    FROM side s
    LEFT JOIN seen x ON x.team_id = s.team_id
   GROUP BY s.team_id, s.team_name, s.division_id
   ORDER BY s.team_name, s.team_id;
$$;

RESET ROLE;

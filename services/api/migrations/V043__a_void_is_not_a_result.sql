-- THRØ V043 — a voided fixture has no result, and the trigger is the last thing to agree (PD-059).
--
-- **Every reader in the system says a void is not a result, and the writer said it was.** The tallies skip
-- it (`o.kind <> 'void'`, V041/V042), the public fixture list skips it, and `StandingsTest` has asserted
-- since V014 that a voided fixture is counted as unplayed. But `outcome_is_a_recorded_decision()` counted
-- every unsuperseded outcome when deciding whether a fixture already had one, voids included — so a fixture
-- whose result had been voided was, to the writer, a fixture that already had a result.
--
-- That is unreachable from a phone and was reachable the moment a league secretary got a page: a voided
-- fixture appears in "still to enter", because the reader says it has no result; the organiser enters one;
-- and the database answers *"this fixture already has a result"* about a result the page cannot show them
-- and therefore cannot offer to correct. A dead end, produced by two halves of one system disagreeing about
-- what the word "live" means.
--
-- So the trigger is taught the same rule everything else already follows. A void annuls; the fixture is open
-- again; the next decision is a first decision and supersedes nothing. The voided outcome and the void
-- itself both stay on the record, which is the point of superseding rather than editing — the history reads
-- "decided, annulled, decided again" and names who did each.
--
-- Only the count changes. A void must still supersede the outcome it annuls, an award must still go to one
-- of the two teams, a played result still needs its match, and a declared one still cannot sit over a match
-- scored on THRØ.

SET ROLE thro_owner;

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
  IF NEW.kind = 'declared' AND f.match_id IS NOT NULL THEN
    RAISE EXCEPTION 'fixture % was scored on THRØ, so its result is read from the match, not declared',
      NEW.fixture_id;
  END IF;
  -- The live outcome, meaning exactly what it means to every reader: unsuperseded, and not a void. A void
  -- is an annulment, so a fixture holding one holds no result and the next decision is a first one.
  SELECT count(*) INTO live FROM competition.league_fixture_outcome o
    WHERE o.fixture_id = NEW.fixture_id
      AND o.kind <> 'void'
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

RESET ROLE;

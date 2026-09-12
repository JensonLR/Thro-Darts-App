-- THRØ V022 — what hostile review of V019–V021 found at the store, closed at the store.
--
-- 1. A lineup was "fixed once played" for its row and not for its entries: an entry under the
--    current version could still be INSERTed after the outcome, and the membership check ran at the
--    old named_at. Now an entry may only be written in the transaction that named the lineup —
--    named_at is the transaction's own timestamp and the entry trigger requires equality — so the
--    set is complete when the naming commits and nothing can be added to it afterwards, by anyone.
-- 2. A void outcome froze the side for ever. A void says the result did not stand — often because
--    the wrong side was named — so a void does not freeze; played, awarded and walkover do.
-- 3. An event's access could be set back to 'open' while live requirement rows stood, and
--    discovery then called it open. Refused: withdraw the requirement first, with a reason.
-- 4. entered_event counted a player's own entry to the qualifier or a pair containing them; a team
--    entry names no individual and is not counted. That was so already; it is now said.

SET ROLE thro_owner;

-- 1 + 2: the lineup's freeze, for the row and for the entries, and not for a void.
ALTER TABLE competition.lineup ALTER COLUMN named_at SET DEFAULT now();

CREATE OR REPLACE FUNCTION competition.lineup_is_open() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'a versioned row advances by exactly one'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'row_version_advances_by_one';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.fixture_id <> OLD.fixture_id OR NEW.team_id <> OLD.team_id) THEN
    RAISE EXCEPTION 'a lineup belongs to its fixture and team'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_keeps_its_key';
  END IF;
  IF NEW.named_at <> now() THEN
    RAISE EXCEPTION 'a lineup is named at the transaction''s own time, so its entries can be held to it'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_is_named_now';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM competition.league_fixture f WHERE f.fixture_id = NEW.fixture_id AND NEW.team_id IN (f.home_team_id, f.away_team_id)) THEN
    RAISE EXCEPTION 'that team is not one of the two in this fixture'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'team_is_a_side_of_the_fixture';
  END IF;
  IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM competition.league_fixture_outcome o
              WHERE o.fixture_id = NEW.fixture_id AND o.kind <> 'void'
                AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s WHERE s.supersedes_outcome_id = o.outcome_id)) THEN
    RAISE EXCEPTION 'the fixture has been played; the side that played is the side that played'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_is_fixed_once_played';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION competition.lineup_entry_is_current() RETURNS trigger AS $$
DECLARE v int; named timestamptz;
BEGIN
  SELECT row_version, named_at INTO v, named FROM competition.lineup WHERE fixture_id = NEW.fixture_id AND team_id = NEW.team_id;
  IF v IS NULL OR NEW.lineup_version <> v THEN
    RAISE EXCEPTION 'a lineup entry is written under the lineup''s current version'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_entry_is_current';
  END IF;
  IF named <> now() THEN
    RAISE EXCEPTION 'a lineup''s entries are written in the transaction that named it; the side is complete when the naming commits'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'lineup_entry_is_written_with_the_naming';
  END IF;
  PERFORM competition.side_and_member(NEW.fixture_id, NEW.team_id, NEW.player_id, named);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- 3: open means open, in both directions.
CREATE FUNCTION competition.open_event_states_no_requirement() RETURNS trigger AS $$
BEGIN
  IF NEW.access = 'open' AND OLD.access <> 'open'
     AND EXISTS (SELECT 1 FROM competition.event_eligibility r WHERE r.event_id = NEW.event_id AND r.withdrawn_at IS NULL) THEN
    RAISE EXCEPTION 'an event with a live entry requirement cannot become open; withdraw the requirement first'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'open_event_states_no_requirement';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER open_event_states_no_requirement
  BEFORE UPDATE OF access ON competition.event
  FOR EACH ROW EXECUTE FUNCTION competition.open_event_states_no_requirement();

COMMENT ON COLUMN competition.event_eligibility.qualifier_event_id IS
  'For kind entered_event: the player qualifies by their own live entry to this event, or a pair containing them. A team entry names no individual and does not count.';

RESET ROLE;

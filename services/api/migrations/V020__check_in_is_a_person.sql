-- THRØ V020 — a check-in is a person, whatever entered.
--
-- V013 keyed check_in on (event, competitor, device) and issued the scoring grant to the
-- competitor, which was fine while every competitor was a single player. V014 typed entries as
-- player, pair or team and added a nullable player_id here with a note: "making it the key is the
-- expand-then-contract once the grant actor is a player rather than a competitor." This is the
-- contract.
--
-- Who is physically present at the desk is a person. For a single-player entry that is the player;
-- for a pair or a team it is whichever member checked the side in, and it is that person — not the
-- pair id, not the team id — who holds the grant under which visits are recorded from their phone,
-- because trust.scoring_grant.actor_id is what the command handler annotates evidence with, and an
-- annotation naming a pair is an annotation naming nobody.
--
-- Three things become true and stay true:
--   1. player_id is NOT NULL and part of the key: (event, player, device).
--   2. the competitor checked in for is a live entry of that event (a foreign key that V013 never had);
--   3. the person is a member of the entrant — the player themself, one of the pair, or a live
--      member of the team at the moment of check-in. A stranger cannot check a side in.
--
-- Existing rows: V014 backfilled player_id from competitor_id wherever the competitor was a player.
-- Any row still null is a check-in for a bare identifier that never became an entry — a V013
-- artefact. It is given a legacy player record exactly as V014 gave one to every entry competitor,
-- so nothing is lost and nothing is invented beyond what V014 already did. The entry foreign key is
-- added NOT VALID and validated only if every existing row satisfies it; otherwise it stands for
-- new rows and the migration says how many old ones it could not vouch for.

SET ROLE thro_owner;

INSERT INTO competition.player (player_id, source)
  SELECT DISTINCT competitor_id, 'legacy' FROM competition.check_in WHERE player_id IS NULL
  ON CONFLICT (player_id) DO NOTHING;
UPDATE competition.check_in SET player_id = competitor_id WHERE player_id IS NULL;

ALTER TABLE competition.check_in
  ALTER COLUMN player_id SET NOT NULL,
  DROP CONSTRAINT check_in_pkey,
  ADD PRIMARY KEY (event_id, player_id, device_id);

ALTER TABLE competition.check_in
  ADD CONSTRAINT check_in_is_for_an_entry
    FOREIGN KEY (event_id, competitor_id) REFERENCES competition.entry (event_id, competitor_id) NOT VALID;

DO $$
DECLARE stray int;
BEGIN
  SELECT count(*) INTO stray FROM competition.check_in c
   WHERE NOT EXISTS (SELECT 1 FROM competition.entry e WHERE e.event_id = c.event_id AND e.competitor_id = c.competitor_id);
  IF stray = 0 THEN
    EXECUTE 'ALTER TABLE competition.check_in VALIDATE CONSTRAINT check_in_is_for_an_entry';
  ELSE
    RAISE WARNING 'V020: % check-in row(s) predate the entry rule and name no entry; they are kept, and the rule holds for every new row', stray;
  END IF;
END $$;

-- The person belongs to the entrant. Enforced at the write, in the store, so no caller can check a
-- stranger in for a side — the same shape as entry_kind_is_the_event_kind.
CREATE FUNCTION competition.check_in_is_by_a_member_of_the_entrant() RETURNS trigger AS $$
DECLARE kind text; ok boolean;
BEGIN
  SELECT e.entrant_kind INTO kind FROM competition.entry e
   WHERE e.event_id = NEW.event_id AND e.competitor_id = NEW.competitor_id;
  IF kind IS NULL THEN
    RETURN NEW; -- the foreign key reports a missing entry in its own words
  END IF;
  ok := CASE kind
    WHEN 'player' THEN NEW.player_id = NEW.competitor_id
    WHEN 'pair'   THEN EXISTS (SELECT 1 FROM competition.pair p WHERE p.pair_id = NEW.competitor_id
                                  AND NEW.player_id IN (p.player_a, p.player_b))
    WHEN 'team'   THEN EXISTS (SELECT 1 FROM competition.team_membership m
                                WHERE m.team_id = NEW.competitor_id AND m.player_id = NEW.player_id
                                  AND m.status = 'active' AND m.valid_from <= NEW.checked_in_at
                                  AND (m.valid_until IS NULL OR m.valid_until > NEW.checked_in_at))
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'the person checking in is not part of the entrant they are checking in for'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'check_in_is_by_a_member_of_the_entrant';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER check_in_is_by_a_member_of_the_entrant
  BEFORE INSERT OR UPDATE ON competition.check_in
  FOR EACH ROW EXECUTE FUNCTION competition.check_in_is_by_a_member_of_the_entrant();

COMMENT ON TABLE competition.check_in IS
  'A person present at an event, checked in for one of its entries from one device, and the scoring '
  'grant issued to that person at that moment. Keyed on the person: for a pair or a team the entrant '
  'is the competitor and the grant holder is the member who checked it in.';

RESET ROLE;

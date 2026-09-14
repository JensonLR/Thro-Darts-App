-- THRØ V039 — a team says which league it plays in (PD-049).
--
-- The map lists 329 leagues and three of them have teams, because teams come from a league's own published
-- pages (PD-033) and the platform that hosts those pages refuses a reader that gives its own name (PD-048).
-- So the other direction: the people who play in a league put their team on it.
--
-- **Their say, and never the league's listing.** A division is what a league published; this is what a
-- team's own admin or captain said. The two are different kinds of fact and are kept in different places:
-- affiliations stay in `team_affiliation`, under a league season the league published, and this table holds
-- a claim with a person's say behind it. The public front carries them apart, and the app says which is which.
--
-- **Kept, and withdrawable.** A team moves leagues; a captain mistypes. So a claim can be withdrawn — marked,
-- never deleted, because who said their team played there in September is still true of September. One live
-- claim per team and league; a team may say it plays in two leagues, because sides do.

SET ROLE thro_owner;

CREATE TABLE competition.team_league_claim (
  claim_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  league_id    uuid        NOT NULL REFERENCES competition.league(league_id),
  said_by      uuid        NOT NULL REFERENCES competition.player(player_id),
  said_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  withdrawn_at timestamptz,
  withdrawn_by uuid        REFERENCES competition.player(player_id),
  -- The only basis there is. A league confirming its own team is a different row, in a different table.
  basis        text        NOT NULL DEFAULT 'said so themselves' CHECK (basis = 'said so themselves'),
  CONSTRAINT a_withdrawal_says_who CHECK ((withdrawn_at IS NULL) = (withdrawn_by IS NULL)),
  CONSTRAINT a_withdrawal_comes_after CHECK (withdrawn_at IS NULL OR withdrawn_at > said_at)
);

CREATE UNIQUE INDEX team_league_claim_live ON competition.team_league_claim (team_id, league_id)
  WHERE withdrawn_at IS NULL;
CREATE INDEX team_league_claim_by_league ON competition.team_league_claim (league_id) WHERE withdrawn_at IS NULL;

-- Withdrawing is the only change a claim takes, and a withdrawal is not undone by rewriting the row: the
-- team says it again, which is a new claim with its own date.
CREATE FUNCTION competition.team_league_claim_is_kept() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'a claim is kept: a team said this, and that it was said does not change'; END IF;
  IF OLD.withdrawn_at IS NOT NULL THEN RAISE EXCEPTION 'a withdrawn claim is finished; saying it again is a new claim'; END IF;
  IF NEW.claim_id <> OLD.claim_id OR NEW.team_id <> OLD.team_id OR NEW.league_id <> OLD.league_id
     OR NEW.said_by <> OLD.said_by OR NEW.said_at <> OLD.said_at OR NEW.basis <> OLD.basis THEN
    RAISE EXCEPTION 'a claim is not rewritten; it is withdrawn';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER team_league_claim_is_kept BEFORE UPDATE OR DELETE ON competition.team_league_claim
  FOR EACH ROW EXECUTE FUNCTION competition.team_league_claim_is_kept();

-- Anything that reads a league or a team reads what its players say; the competition role records it.
GRANT SELECT ON competition.team_league_claim TO app_read, app_competition;
GRANT INSERT ON competition.team_league_claim TO app_competition;
GRANT UPDATE (withdrawn_at, withdrawn_by) ON competition.team_league_claim TO app_competition;

RESET ROLE;

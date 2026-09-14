-- THRØ V038 — a player says a listed team is theirs, and runs it on THRØ (PD-047).
--
-- The leagues board (PD-046) shows a player their own side: the team, its division, the pubs it plays at.
-- And then nothing, because a team read out of a league's pages has no members — nobody on THRØ runs it,
-- so there is no code to give the side and no roster to fill. This is the door between the two.
--
-- **By their own say, and the team's page says so.** Nobody has told THRØ that this person plays for this
-- team; they have said it themselves, which is exactly what a pub side does when it puts a name on a
-- board. So the claim is recorded as what it is — an adoption, said by a player, on a date — and the
-- front carries it in those words rather than presenting the adopter as somebody the league appointed.
--
-- **Only a team nobody runs.** The first person to say it takes it, and the table's key is the team, so
-- two people saying it at once end with one adopter and the second is refused in words. A team somebody
-- already runs is joined with that person's code (V029), never claimed over their head.
--
-- **Adults only, and unknown is not adult.** `player_is_adult` reads the age band off the account behind
-- the player and answers false for `unknown` and for a player with no live claim at all. A narrow
-- SECURITY DEFINER function rather than a grant on `identity`, the way V037's `seat_of` is: the
-- competition role gets to ask this one question and nothing else about a person.
--
-- **Nothing is rewritten.** The team keeps the name and the pub the league published; the adoption is a
-- row beside them, kept for good, saying who took it on and when. Handing a team over, and a league or a
-- side disputing an adoption, are not decided here.

SET ROLE thro_owner;

CREATE TABLE competition.team_adoption (
  team_id     uuid        PRIMARY KEY REFERENCES competition.team(team_id),
  player_id   uuid        NOT NULL REFERENCES competition.player(player_id),
  adopted_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- The only basis there is. Written out because it is shown to people, and because a second basis
  -- (a league saying so, a code from a secretary) is a different row with a different meaning.
  basis       text        NOT NULL DEFAULT 'said so themselves' CHECK (basis = 'said so themselves')
);
CREATE INDEX team_adoption_by_player ON competition.team_adoption (player_id);

CREATE FUNCTION competition.team_adoption_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'an adoption is kept: it records who took the team on, and that does not change';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER team_adoption_is_kept BEFORE UPDATE OR DELETE ON competition.team_adoption
  FOR EACH ROW EXECUTE FUNCTION competition.team_adoption_is_kept();

-- Whether the account behind a player is an adult. False for a minor, false for an age nobody has said,
-- and false for a player no live account claims — a safeguarding answer is never a guess.
CREATE FUNCTION competition.player_is_adult(p uuid) RETURNS boolean AS $$
  SELECT coalesce(bool_or(a.age_band = 'adult'), false)
    FROM identity.player_claim c
    JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
   WHERE c.player_id = p AND c.revoked_at IS NULL;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

REVOKE ALL ON FUNCTION competition.player_is_adult(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION competition.player_is_adult(uuid) TO app_competition;

-- The competition role takes an adoption; anything that reads a team's front reads that it was adopted.
GRANT SELECT ON competition.team_adoption TO app_read, app_competition;
GRANT INSERT ON competition.team_adoption TO app_competition;

RESET ROLE;

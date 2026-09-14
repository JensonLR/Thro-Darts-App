-- THRØ V029 — joining a team, by a code from somebody who runs it.
--
-- The Team OS slice on the phone (plan §6) starts with the two things a pub team does before
-- anything else: somebody starts it, and they get their mates in. Getting somebody in is a CODE,
-- for the same reason friends are (V028): there is no directory of players to search, and a code
-- said across a bar is consent from both sides. A team code lasts thirty days and admits up to
-- twenty people, because a captain says it once to the whole side; it is made by an admin or a
-- captain, and the roster it builds is memberships (V014) — real ones, with their own history.

SET ROLE thro_owner;

CREATE TABLE competition.team_invite (
  code        text        PRIMARY KEY CHECK (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  team_id     uuid        NOT NULL REFERENCES competition.team(team_id),
  created_by  uuid        NOT NULL,   -- the player who made it (an admin or captain at the time)
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at  timestamptz NOT NULL,
  uses        int         NOT NULL DEFAULT 0 CHECK (uses >= 0),
  max_uses    int         NOT NULL DEFAULT 20 CHECK (max_uses BETWEEN 1 AND 100),
  CONSTRAINT team_invite_lasts_a_while CHECK (expires_at > created_at AND expires_at <= created_at + interval '90 days')
);
CREATE INDEX team_invite_by_team ON competition.team_invite (team_id);

-- Each use is recorded: who came in on which code. Append-only.
CREATE TABLE competition.team_invite_use (
  code        text        NOT NULL REFERENCES competition.team_invite(code),
  player_id   uuid        NOT NULL REFERENCES competition.player(player_id),
  used_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (code, player_id)
);

CREATE FUNCTION competition.team_invite_is_kept() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'a team code is kept'; END IF;
  IF NEW.code <> OLD.code OR NEW.team_id <> OLD.team_id OR NEW.created_by <> OLD.created_by OR NEW.expires_at <> OLD.expires_at OR NEW.max_uses <> OLD.max_uses THEN
    RAISE EXCEPTION 'a team code is not rewritten; only its use count moves';
  END IF;
  IF NEW.uses <> OLD.uses + 1 THEN RAISE EXCEPTION 'a team code is used one person at a time'; END IF;
  IF NEW.uses > NEW.max_uses THEN RAISE EXCEPTION 'that team code has admitted everyone it can'; END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER team_invite_is_kept BEFORE UPDATE OR DELETE ON competition.team_invite
  FOR EACH ROW EXECUTE FUNCTION competition.team_invite_is_kept();

GRANT SELECT ON competition.team_invite, competition.team_invite_use TO app_read, app_competition;
GRANT INSERT ON competition.team_invite, competition.team_invite_use TO app_competition;
GRANT UPDATE (uses) ON competition.team_invite TO app_competition;

RESET ROLE;

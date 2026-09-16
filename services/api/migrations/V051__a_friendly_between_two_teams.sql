-- A friendly between two teams (PD-110).
--
-- A league fixture belongs to a season: `league_fixture.league_season_id` is NOT NULL, and rightly — a table row is
-- a season's. A friendly belongs to nobody but the two teams that agreed it, so it is its own table rather than a
-- fixture with a hole where the season should be. It carries the same shape a rearrangement proposal does (one team
-- proposes, the other answers, the state says which) and the one thing a fixture carries that a proposal does not:
-- the match it was played in, cited once, so a friendly scored on THRØ is evidence and a friendly that was not is a
-- date.
--
-- Nothing here touches a rating: what a friendly counts for is OD-001's, not this migration's.

SET ROLE thro_owner;

CREATE TABLE competition.friendly (
  friendly_id   uuid        PRIMARY KEY,
  from_team_id  uuid        NOT NULL REFERENCES competition.team(team_id),
  to_team_id    uuid        NOT NULL REFERENCES competition.team(team_id),
  -- When it is to be played. Kept as proposed; an accepted friendly is played at this time or rearranged by a new one.
  play_at       timestamptz NOT NULL,
  venue_id      uuid        REFERENCES competition.venue(venue_id),
  message       text,
  state         text        NOT NULL DEFAULT 'proposed'
                CHECK (state IN ('proposed','accepted','declined','withdrawn')),
  proposed_by   uuid        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  answered_by   uuid,
  answered_at   timestamptz,
  answer_note   text,
  -- The contest, once one exists. Set once, and only on an accepted friendly.
  match_id      uuid        UNIQUE REFERENCES evidence.match(match_id),
  row_version   int         NOT NULL DEFAULT 1,
  CONSTRAINT friendly_is_between_two_teams CHECK (from_team_id <> to_team_id),
  CONSTRAINT friendly_answer_is_complete
    CHECK ((state IN ('proposed','withdrawn')) = (answered_by IS NULL AND answered_at IS NULL)),
  CONSTRAINT friendly_match_is_on_an_accepted_one CHECK (match_id IS NULL OR state = 'accepted')
);

COMMENT ON TABLE competition.friendly IS
  'PD-110: a game two teams agreed outside any season. Proposed by one, answered by the other; the match it was '
  'played in is cited once by somebody who played it and runs one of the teams.';

-- One open challenge between a pair of teams at a time, in either direction.
CREATE UNIQUE INDEX friendly_one_open_per_pair ON competition.friendly
  (least(from_team_id, to_team_id), greatest(from_team_id, to_team_id)) WHERE state = 'proposed';
CREATE INDEX friendly_by_team ON competition.friendly (from_team_id, play_at);
CREATE INDEX friendly_by_to_team ON competition.friendly (to_team_id, play_at);

GRANT SELECT ON competition.friendly TO app_read, app_competition;
GRANT INSERT, UPDATE ON competition.friendly TO app_competition;

RESET ROLE;

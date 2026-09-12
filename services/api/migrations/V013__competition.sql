-- THRØ V013 — the competition lifecycle.
--
-- ADR-006 issues scoring grants at CHECK-IN, and the reason is worth restating where the table is
-- defined: match-open is the moment the design draws ("Both players must confirm before scoring
-- opens"), but nothing guarantees a network at that moment, and a player arriving at a dead-signal
-- venue must still be able to score. Check-in is inherently online — it is how the organiser knows
-- who is present — so a player's grants for the whole event are pre-issued there.
--
-- Until now grants existed with nothing to issue them, because check-in did not exist.

CREATE SCHEMA competition AUTHORIZATION thro_owner;

SET ROLE thro_owner;

CREATE TABLE competition.event (
  event_id     uuid        PRIMARY KEY,
  name         text        NOT NULL,
  venue        text,
  starts_at    timestamptz NOT NULL,
  -- When the competition session is expected to end. A grant's lifetime is this plus 24 hours, so
  -- an organiser who sets it too early is the one way to make grants lapse mid-event.
  session_ends_at timestamptz NOT NULL,
  state        text        NOT NULL DEFAULT 'open'
               CHECK (state IN ('open','entries_closed','drawn','in_progress','complete','cancelled')),
  CONSTRAINT event_session_ends_after_start CHECK (session_ends_at > starts_at)
);

CREATE TABLE competition.entry (
  entry_id     uuid        PRIMARY KEY,
  event_id     uuid        NOT NULL REFERENCES competition.event(event_id),
  competitor_id uuid       NOT NULL,
  seed         int         CHECK (seed IS NULL OR seed > 0),
  entered_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  withdrawn_at timestamptz,
  UNIQUE (event_id, competitor_id)
);

-- A seed is unique within an event when present. Two competitors seeded 3 makes the draw
-- non-deterministic, and a non-deterministic draw is one nobody can check afterwards.
CREATE UNIQUE INDEX entry_seed_unique ON competition.entry (event_id, seed)
  WHERE seed IS NOT NULL AND withdrawn_at IS NULL;

CREATE TABLE competition.check_in (
  event_id     uuid        NOT NULL REFERENCES competition.event(event_id),
  competitor_id uuid       NOT NULL,
  device_id    uuid        NOT NULL,
  checked_in_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- The grant issued at this check-in. The link is the point of the table: it is how you answer
  -- "under what authority was this evidence recorded" months later.
  grant_id     uuid        REFERENCES trust.scoring_grant(grant_id),
  PRIMARY KEY (event_id, competitor_id, device_id)
);

CREATE TABLE competition.board (
  board_id   uuid PRIMARY KEY,
  event_id   uuid NOT NULL REFERENCES competition.event(event_id),
  label      text NOT NULL,
  UNIQUE (event_id, label)
);

CREATE TABLE competition.fixture (
  fixture_id  uuid        PRIMARY KEY,
  event_id    uuid        NOT NULL REFERENCES competition.event(event_id),
  round_number int        NOT NULL CHECK (round_number > 0),
  position    int         NOT NULL CHECK (position > 0),
  home_id     uuid,
  away_id     uuid,
  -- A bye is not a win and creates no match. Modelled as a fixture with one competitor so the
  -- bracket keeps its shape, and never as a played result.
  is_bye      boolean     NOT NULL DEFAULT false,
  board_id    uuid REFERENCES competition.board(board_id),
  match_id    uuid REFERENCES evidence.match(match_id),
  UNIQUE (event_id, round_number, position),
  CONSTRAINT bye_has_one_competitor
    CHECK (NOT is_bye OR (home_id IS NOT NULL AND away_id IS NULL)),
  CONSTRAINT bye_is_never_a_match CHECK (NOT is_bye OR match_id IS NULL)
);

CREATE INDEX fixture_by_round ON competition.fixture (event_id, round_number, position);

GRANT USAGE ON SCHEMA competition TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT SELECT ON ALL TABLES IN SCHEMA competition
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT, UPDATE ON competition.event, competition.entry, competition.check_in,
  competition.board, competition.fixture TO app_competition;

-- Check-in issues a grant, so the competition module must be able to.
GRANT INSERT, UPDATE ON trust.scoring_grant TO app_competition;

RESET ROLE;

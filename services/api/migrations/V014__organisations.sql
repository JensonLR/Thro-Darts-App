-- THRØ V014 — the organisational graph: Team, Venue, League, Tournament, Series, and the dated
-- relationships between them. ADR-017; founder instruction PD-028.
--
-- Two things this migration is NOT:
--
--   * A rename of a Club type. There has never been one in this repository. "Club" is a word people
--     use at the board for a team or for a venue, and it resolves to one of them every time.
--   * A restructuring of the match aggregate or the evidence log. Nothing in `evidence` changes.
--     A fixture or a bracket tie points at a match; the match never points back.
--
-- Two things it corrects:
--
--   * `competition.fixture` was a knockout bracket tie (round, position, bye). GLOSSARY and ADR-012
--     define Fixture as a league's scheduled meeting and say in terms that it is not a slot. The
--     table is renamed to what it is. The league concept is created as `league_fixture` — a
--     different name deliberately, so that any SQL still written against the old shape fails loudly
--     rather than compiling against a table of the same name and a different meaning.
--   * `competition.event.venue` was free text. A venue is an entity that hosts many teams and many
--     events, and a team that changes venue keeps its identity. The text survives as `venue_label`
--     until every writer sends an identifier.
--
-- There is no production data and no device data — THRØ has never run — and the statements below
-- are still written as if there were: every ALTER preserves existing rows, every backfill is
-- explicit, and `MigrationTest` applies this file over a populated V013 database and asserts that
-- nothing was lost.
--
-- History is never deleted. Every dated relationship carries valid_from and valid_until; closing
-- one sets valid_until once, a trigger then freezes the row, and no application role holds DELETE
-- on any table created here.

-- btree_gist is a trusted extension, so the connecting user may create it; thro_owner deliberately
-- holds no CREATE on the database (V010). It is what lets an EXCLUDE constraint say "no two
-- overlapping periods for the same key", which a partial unique index cannot.
CREATE EXTENSION IF NOT EXISTS btree_gist;

SET ROLE thro_owner;

-- ---------------------------------------------------------------------------------------------
-- Venue and Team
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.venue (
  venue_id     uuid        PRIMARY KEY,
  name         text        NOT NULL,
  -- A town or district, deliberately coarse. The map needs where a venue is; nothing needs where
  -- a person is, and a venue is a public building.
  locality     text,
  country      text        NOT NULL DEFAULT 'GB',
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  visibility   text        NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','private')),
  row_version  int         NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid,
  CONSTRAINT venue_coordinates_are_a_pair
    CHECK ((latitude IS NULL) = (longitude IS NULL))
);

CREATE TABLE competition.team (
  team_id      uuid        PRIMARY KEY,
  name         text        NOT NULL,
  short_name   text,
  locality     text,
  founded_year int         CHECK (founded_year IS NULL OR founded_year BETWEEN 1800 AND 2200),
  -- Public front, private inside. The front is the name, badge, locality and published
  -- competition; nothing on this row is a person.
  visibility   text        NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','private')),
  -- Set once. A dissolved team keeps every row it ever had; it simply stops fielding sides.
  dissolved_at timestamptz,
  row_version  int         NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid
);

COMMENT ON TABLE competition.team IS
  'The competitive organisation, whatever it calls itself: darts team, darts club, pub team, side. '
  'Its venue is a tenure (below), so moving venue changes nothing here.';

-- Teams rename. A past table must still render the name the team had then, so every name the team
-- has held is kept, written by trigger.
CREATE TABLE competition.team_name (
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  name         text        NOT NULL,
  valid_from   timestamptz NOT NULL DEFAULT clock_timestamp(),
  valid_until  timestamptz,
  PRIMARY KEY (team_id, valid_from)
);

CREATE FUNCTION competition.team_name_is_recorded() RETURNS trigger AS $$
BEGIN
  INSERT INTO competition.team_name (team_id, name, valid_from)
    VALUES (NEW.team_id, NEW.name, NEW.created_at);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- AFTER insert, because the name row references the team row and must follow it.
CREATE TRIGGER team_name_is_recorded AFTER INSERT ON competition.team
  FOR EACH ROW EXECUTE FUNCTION competition.team_name_is_recorded();

CREATE FUNCTION competition.team_is_versioned_and_renames_are_kept() RETURNS trigger AS $$
BEGIN
  IF OLD.dissolved_at IS NOT NULL AND NEW.dissolved_at IS DISTINCT FROM OLD.dissolved_at THEN
    RAISE EXCEPTION 'a dissolution is recorded once (team %)', OLD.team_id;
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'stale write: team % is at version %, not %', OLD.team_id,
      OLD.row_version, NEW.row_version - 1;
  END IF;
  IF NEW.name <> OLD.name THEN
    UPDATE competition.team_name SET valid_until = clock_timestamp()
      WHERE team_id = OLD.team_id AND valid_until IS NULL;
    INSERT INTO competition.team_name (team_id, name) VALUES (NEW.team_id, NEW.name);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER team_is_versioned_and_renames_are_kept BEFORE UPDATE ON competition.team
  FOR EACH ROW EXECUTE FUNCTION competition.team_is_versioned_and_renames_are_kept();

-- Where a team plays, as a dated relationship with half-open periods [valid_from, valid_until).
-- A team may hold several kinds at once (home and training); its HOME tenures may never overlap,
-- past or present, which is the EXCLUDE constraint.
CREATE TABLE competition.team_venue_tenure (
  tenure_id    uuid        PRIMARY KEY,
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  venue_id     uuid        NOT NULL REFERENCES competition.venue(venue_id),
  kind         text        NOT NULL CHECK (kind IN ('home','training','registered')),
  valid_from   timestamptz NOT NULL,
  valid_until  timestamptz,
  recorded_by  uuid,
  CONSTRAINT tenure_ends_after_it_begins CHECK (valid_until IS NULL OR valid_until > valid_from),
  CONSTRAINT tenure_home_periods_never_overlap EXCLUDE USING gist
    (team_id WITH =, tstzrange(valid_from, valid_until, '[)') WITH &&) WHERE (kind = 'home')
);

CREATE INDEX tenure_by_venue ON competition.team_venue_tenure (venue_id) WHERE valid_until IS NULL;

-- ---------------------------------------------------------------------------------------------
-- Player, the claim that binds it to an account, and membership of a team
-- ---------------------------------------------------------------------------------------------

-- The sporting identity: THRØ ID. It holds NO personal data and no text at all; a display name and
-- an age band live in identity.account (ADR-005), reached through a claim. A player row may exist
-- before any account holds it — a captain enters a roster before every member has installed
-- anything — and is then `unclaimed`, treated as a minor by every exposure rule (PD-029).
CREATE TABLE competition.player (
  player_id    uuid        PRIMARY KEY,
  source       text        NOT NULL DEFAULT 'self'
               CHECK (source IN ('self','team_admin','organiser','import','legacy')),
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid
);

COMMENT ON TABLE competition.player IS
  'THRO ID: one persistent competitive identity. Never merged on a name. Its binding to an account '
  'is identity.player_claim — appended and revocable — never a column updated in place.';

-- How an account came to exist, and on what basis THRØ holds the data. A record a captain typed for
-- someone else is third-party data with no consent yet recorded; a submission carrying such a
-- person may not leave READY until one is (see the execution plan §7).
ALTER TABLE identity.account
  ADD COLUMN created_via   text NOT NULL DEFAULT 'self'
             CHECK (created_via IN ('self','team_admin','organiser','import')),
  ADD COLUMN consent_basis text NOT NULL DEFAULT 'self'
             CHECK (consent_basis IN ('self','guardian','none'));

-- The binding between a sporting identity and the account that holds its personal data. Appended,
-- revocable, and the only place the binding exists. A wrong claim — two J. Smiths — is revoked, not
-- edited, and both identities are intact afterwards. Merging two players is a separate, later
-- identity event (Phase B) and is never expressed by pointing a claim somewhere else.
CREATE TABLE identity.player_claim (
  claim_id     uuid        PRIMARY KEY,
  player_id    uuid        NOT NULL REFERENCES competition.player(player_id),
  account_id   uuid        NOT NULL REFERENCES identity.account(account_id),
  method       text        NOT NULL
               CHECK (method IN ('self_created','claim_code','organiser_confirmed','guardian_confirmed')),
  confirmed_by uuid,
  claimed_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at   timestamptz,
  revoked_by   uuid,
  revoked_reason text,
  CONSTRAINT claim_revocation_is_complete CHECK ((revoked_at IS NULL) = (revoked_by IS NULL)),
  -- A confirmation by someone other than the claimant needs a name.
  CONSTRAINT claim_confirmation_is_attributed
    CHECK (method = 'self_created' OR method = 'claim_code' OR confirmed_by IS NOT NULL)
);

CREATE UNIQUE INDEX claim_one_live_per_player ON identity.player_claim (player_id) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX claim_one_live_per_account ON identity.player_claim (account_id) WHERE revoked_at IS NULL;

CREATE FUNCTION identity.claim_history_is_not_rewritable() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'a revoked claim is history (claim %)', OLD.claim_id;
  END IF;
  IF NEW.player_id <> OLD.player_id OR NEW.account_id <> OLD.account_id
     OR NEW.method <> OLD.method OR NEW.claimed_at <> OLD.claimed_at
     OR NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by THEN
    RAISE EXCEPTION 'a claim is fixed when made; revoke it and make another (claim %)', OLD.claim_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER claim_history_is_not_rewritable BEFORE UPDATE ON identity.player_claim
  FOR EACH ROW EXECUTE FUNCTION identity.claim_history_is_not_rewritable();

CREATE TABLE competition.team_membership (
  membership_id uuid       PRIMARY KEY,
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  player_id    uuid        NOT NULL REFERENCES competition.player(player_id),
  role         text        NOT NULL DEFAULT 'player'
               CHECK (role IN ('player','captain','vice_captain','admin')),
  status       text        NOT NULL DEFAULT 'active' CHECK (status IN ('invited','active')),
  invited_at   timestamptz,
  accepted_at  timestamptz,
  valid_from   timestamptz NOT NULL,
  valid_until  timestamptz,
  ended_reason text,
  recorded_by  uuid,
  CONSTRAINT membership_ends_after_it_begins
    CHECK (valid_until IS NULL OR valid_until > valid_from),
  CONSTRAINT membership_active_was_accepted
    CHECK (status <> 'active' OR invited_at IS NULL OR accepted_at IS NOT NULL)
);

-- One open membership per (team, player). Deliberately NO uniqueness on player alone: a player
-- belongs to as many teams as the policies of the competitions they play in permit.
CREATE UNIQUE INDEX membership_one_open_per_team_player ON competition.team_membership
  (team_id, player_id) WHERE valid_until IS NULL;
CREATE INDEX membership_by_player ON competition.team_membership (player_id);

-- ---------------------------------------------------------------------------------------------
-- League, season, division
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.league (
  league_id    uuid        PRIMARY KEY,
  name         text        NOT NULL,
  locality     text,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid
);

CREATE TABLE competition.league_season (
  league_season_id uuid    PRIMARY KEY,
  league_id    uuid        NOT NULL REFERENCES competition.league(league_id),
  label        text        NOT NULL,                      -- "2026/27"
  starts_on    date        NOT NULL,
  ends_on      date        NOT NULL,
  state        text        NOT NULL DEFAULT 'planned'
               CHECK (state IN ('planned','open','in_progress','complete')),
  -- Whether the league registers players FOR A TEAM or as individuals. Fixed per season; a player
  -- registration must agree with it (composite foreign key below).
  registration_kind text   NOT NULL DEFAULT 'team' CHECK (registration_kind IN ('team','individual')),
  row_version  int         NOT NULL DEFAULT 1,
  UNIQUE (league_id, label),
  UNIQUE (league_season_id, registration_kind),
  CONSTRAINT season_ends_after_it_starts CHECK (ends_on >= starts_on)
);

CREATE TABLE competition.division (
  division_id  uuid        PRIMARY KEY,
  league_season_id uuid    NOT NULL REFERENCES competition.league_season(league_season_id),
  name         text        NOT NULL,
  ordinal      int         NOT NULL CHECK (ordinal > 0),
  UNIQUE (league_season_id, name),
  UNIQUE (league_season_id, ordinal),
  -- Lets an affiliation or fixture reference (division, season) as a pair, so a division can never
  -- be attached to a season it does not belong to.
  UNIQUE (division_id, league_season_id)
);

-- ---------------------------------------------------------------------------------------------
-- Policy: versioned, approved rule bodies belonging to one authority (ADR-014 kind 1)
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.tournament (
  tournament_id uuid       PRIMARY KEY,
  name         text        NOT NULL,
  locality     text,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid
);

COMMENT ON TABLE competition.tournament IS
  'The persistent identity of a discrete competition that may recur — "The Riverside Open". '
  'One occurrence is an event. A tournament is not a league: nothing here has a fixture, an '
  'affiliation or a registration, and nothing in a league season has an entry, a check-in or a draw.';

CREATE TABLE competition.series (
  series_id    uuid        PRIMARY KEY,
  name         text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid
);

CREATE TABLE competition.series_season (
  series_season_id uuid    PRIMARY KEY,
  series_id    uuid        NOT NULL REFERENCES competition.series(series_id),
  label        text        NOT NULL,
  starts_on    date        NOT NULL,
  ends_on      date        NOT NULL,
  UNIQUE (series_id, label),
  CONSTRAINT series_season_ends_after_it_starts CHECK (ends_on >= starts_on)
);

CREATE TABLE competition.policy (
  policy_id    uuid        PRIMARY KEY,
  -- Exactly one authority, typed, so a policy cannot cite a season that does not exist.
  authority_kind text      NOT NULL
               CHECK (authority_kind IN ('league','league_season','event','series','series_season')),
  league_id        uuid REFERENCES competition.league(league_id),
  league_season_id uuid REFERENCES competition.league_season(league_season_id),
  event_id         uuid REFERENCES competition.event(event_id),
  series_id        uuid REFERENCES competition.series(series_id),
  series_season_id uuid REFERENCES competition.series_season(series_season_id),
  authority_id uuid GENERATED ALWAYS AS
               (coalesce(league_id, league_season_id, event_id, series_id, series_season_id)) STORED,
  kind         text        NOT NULL,      -- registration, transfer, points, tie_break, format, team_separation, ...
  version      int         NOT NULL CHECK (version > 0),
  effective_from date      NOT NULL,
  effective_to date,
  -- Where the rule came from. `extracted` means an AI-assisted extraction from a source document
  -- that a human then reviewed; it is provenance, not authority. Nothing becomes executable on
  -- provenance alone — approval is what does that.
  provenance   text        NOT NULL CHECK (provenance IN ('manual','imported','extracted')),
  source_ref   text,                      -- citation into the source document, when there is one
  approval_state text      NOT NULL DEFAULT 'draft'
               CHECK (approval_state IN ('draft','approved','superseded')),
  approved_by  uuid,
  approved_at  timestamptz,
  body_schema_version int  NOT NULL DEFAULT 1 CHECK (body_schema_version > 0),
  body         jsonb       NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid,
  UNIQUE (authority_kind, authority_id, kind, version),
  CONSTRAINT policy_has_exactly_one_authority CHECK (
       (authority_kind = 'league'        AND league_id IS NOT NULL
          AND num_nonnulls(league_id, league_season_id, event_id, series_id, series_season_id) = 1)
    OR (authority_kind = 'league_season' AND league_season_id IS NOT NULL
          AND num_nonnulls(league_id, league_season_id, event_id, series_id, series_season_id) = 1)
    OR (authority_kind = 'event'         AND event_id IS NOT NULL
          AND num_nonnulls(league_id, league_season_id, event_id, series_id, series_season_id) = 1)
    OR (authority_kind = 'series'        AND series_id IS NOT NULL
          AND num_nonnulls(league_id, league_season_id, event_id, series_id, series_season_id) = 1)
    OR (authority_kind = 'series_season' AND series_season_id IS NOT NULL
          AND num_nonnulls(league_id, league_season_id, event_id, series_id, series_season_id) = 1)
  ),
  CONSTRAINT policy_effective_period_is_ordered
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT policy_approval_is_complete
    CHECK ((approval_state = 'draft') = (approved_by IS NULL AND approved_at IS NULL)),
  -- Two APPROVED versions of one rule for one authority may never be in force on the same day, or
  -- "which rule applied on 3 November" has two answers. Drafts and superseded versions may overlap
  -- freely; they decide nothing.
  CONSTRAINT policy_approved_periods_never_overlap EXCLUDE USING gist
    (authority_kind WITH =, authority_id WITH =, kind WITH =,
     daterange(effective_from, effective_to, '[]') WITH &&)
    WHERE (approval_state = 'approved')
);

CREATE INDEX policy_by_authority ON competition.policy (authority_kind, authority_id, kind);

COMMENT ON TABLE competition.policy IS
  'A rule is data with an authority, a version, an effective period, provenance and an approval. '
  'Only an approved policy may be cited by anything executable, and an approved row is frozen: '
  'change is a new version, so a decision taken two seasons ago still explains itself. '
  'ADR-014''s rules_version on a match is to become a policy_id, so there are not two policy systems.';

-- Once approved, every column is frozen except effective_to, which may be set once (to close the
-- period when a successor is approved) and approval_state, which moves forward only.
CREATE FUNCTION competition.policy_history_is_not_rewritable() RETURNS trigger AS $$
BEGIN
  IF OLD.approval_state <> 'draft' THEN
    IF NEW.approval_state = 'draft' THEN
      RAISE EXCEPTION 'an approval cannot be withdrawn; supersede it (policy %)', OLD.policy_id;
    END IF;
    IF OLD.approval_state = 'superseded' AND NEW.approval_state <> 'superseded' THEN
      RAISE EXCEPTION 'a superseded policy stays superseded (policy %)', OLD.policy_id;
    END IF;
    IF OLD.effective_to IS NOT NULL AND NEW.effective_to IS DISTINCT FROM OLD.effective_to THEN
      RAISE EXCEPTION 'an approved policy''s period is closed once (policy %)', OLD.policy_id;
    END IF;
    -- authority_id is GENERATED, and a generated column is not yet computed on NEW inside a
    -- BEFORE trigger, so it is excluded from the comparison rather than read as a change.
    IF to_jsonb(NEW) - 'approval_state' - 'effective_to' - 'authority_id'
       IS DISTINCT FROM to_jsonb(OLD) - 'approval_state' - 'effective_to' - 'authority_id' THEN
      RAISE EXCEPTION 'an approved policy cannot be rewritten; issue a new version (policy %)',
        OLD.policy_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER policy_history_is_not_rewritable BEFORE UPDATE ON competition.policy
  FOR EACH ROW EXECUTE FUNCTION competition.policy_history_is_not_rewritable();

-- Which approved policy orders the table. Pinned when standings are published, so a later tie-break
-- version cannot re-order a past season (ADR-014 kind 1).
ALTER TABLE competition.league_season
  ADD COLUMN standings_policy_id uuid REFERENCES competition.policy(policy_id);

-- ---------------------------------------------------------------------------------------------
-- Affiliation (team ↔ season) and registration (player ↔ season)
-- ---------------------------------------------------------------------------------------------

-- A TEAM's dated registration to a league season. About the team, not about any player.
CREATE TABLE competition.team_affiliation (
  affiliation_id uuid      PRIMARY KEY,
  team_id      uuid        NOT NULL REFERENCES competition.team(team_id),
  league_season_id uuid    NOT NULL REFERENCES competition.league_season(league_season_id),
  division_id  uuid,
  status       text        NOT NULL DEFAULT 'applied'
               CHECK (status IN ('applied','accepted')),
  accepted_at  timestamptz,
  valid_from   timestamptz NOT NULL,
  valid_until  timestamptz,
  ended_reason text,
  recorded_by  uuid,
  CONSTRAINT affiliation_ends_after_it_begins
    CHECK (valid_until IS NULL OR valid_until > valid_from),
  CONSTRAINT affiliation_accepted_is_dated CHECK ((status = 'accepted') = (accepted_at IS NOT NULL)),
  FOREIGN KEY (division_id, league_season_id)
    REFERENCES competition.division(division_id, league_season_id)
);

CREATE UNIQUE INDEX affiliation_one_open_per_team_season ON competition.team_affiliation
  (team_id, league_season_id) WHERE valid_until IS NULL;

-- A PLAYER's dated eligibility record in a league season. Shares no key with team_membership: a
-- member need not be registered, and a registration outlives the membership it was made under.
-- Eligibility is derived from this row under the season's approved policy — never from membership,
-- and never from a payment.
CREATE TABLE competition.player_registration (
  registration_id uuid     PRIMARY KEY,
  player_id    uuid        NOT NULL REFERENCES competition.player(player_id),
  league_season_id uuid    NOT NULL REFERENCES competition.league_season(league_season_id),
  registration_kind text   NOT NULL CHECK (registration_kind IN ('team','individual')),
  -- The team the registration was made for, as it stood at the time. Not a membership reference on
  -- purpose: a transfer is a new registration that supersedes this one, and this row keeps saying
  -- which team it was for.
  team_id      uuid        REFERENCES competition.team(team_id),
  status       text        NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','registered','refused','lapsed')),
  -- The approved policy version this registration was assessed under. Required to be registered.
  policy_id    uuid        REFERENCES competition.policy(policy_id),
  supersedes_registration_id uuid REFERENCES competition.player_registration(registration_id),
  -- Set only when an approved policy permits a player to hold two registrations in one season.
  dual_registration_policy_id uuid REFERENCES competition.policy(policy_id),
  source       text        NOT NULL DEFAULT 'thro' CHECK (source IN ('thro','organiser','import')),
  valid_from   timestamptz NOT NULL,
  valid_until  timestamptz,
  ended_reason text,
  recorded_by  uuid,
  CONSTRAINT registration_ends_after_it_begins
    CHECK (valid_until IS NULL OR valid_until > valid_from),
  CONSTRAINT registration_for_a_team_names_one
    CHECK (registration_kind = 'individual' OR team_id IS NOT NULL),
  CONSTRAINT registered_under_a_policy
    CHECK (status <> 'registered' OR policy_id IS NOT NULL),
  -- The kind must agree with the season's. A team-registered league cannot quietly hold an
  -- individual registration.
  FOREIGN KEY (league_season_id, registration_kind)
    REFERENCES competition.league_season(league_season_id, registration_kind),
  -- Unless a policy says otherwise, one live registration per player per season, across time.
  CONSTRAINT registration_periods_never_overlap EXCLUDE USING gist
    (player_id WITH =, league_season_id WITH =, tstzrange(valid_from, valid_until, '[)') WITH &&)
    WHERE (status = 'registered' AND dual_registration_policy_id IS NULL)
);

CREATE INDEX registration_by_season ON competition.player_registration (league_season_id, player_id);

-- ---------------------------------------------------------------------------------------------
-- Tournament editions (the existing `event`), pairs, typed entries
-- ---------------------------------------------------------------------------------------------

-- `event` was already one tournament edition. It now says so, and carries the two facts discovery
-- and entry typing need. Existing rows keep their free-text venue as a label and default to what
-- every existing event was: an open event of single players.
ALTER TABLE competition.event RENAME COLUMN venue TO venue_label;
ALTER TABLE competition.event
  ADD COLUMN venue_id      uuid REFERENCES competition.venue(venue_id),
  ADD COLUMN tournament_id uuid REFERENCES competition.tournament(tournament_id),
  ADD COLUMN entrant_kind  text NOT NULL DEFAULT 'player'
             CHECK (entrant_kind IN ('player','pair','team')),
  ADD COLUMN access        text NOT NULL DEFAULT 'open'
             CHECK (access IN ('open','invitational','qualified','restricted','member_only')),
  ADD CONSTRAINT event_entrant_kind_is_referenceable UNIQUE (event_id, entrant_kind);

COMMENT ON COLUMN competition.event.venue_label IS
  'Free-text venue, kept for rows written before venue_id existed and for organisers who have not '
  'yet chosen a venue record. Not a venue identity; the map and the tenure history use venue_id.';

CREATE TABLE competition.pair (
  pair_id      uuid        PRIMARY KEY,
  player_a     uuid        NOT NULL REFERENCES competition.player(player_id),
  player_b     uuid        NOT NULL REFERENCES competition.player(player_id),
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- Normalised so that (a, b) and (b, a) are the same pair and cannot both exist.
  CONSTRAINT pair_is_two_distinct_players_in_order CHECK (player_a < player_b),
  UNIQUE (player_a, player_b)
);

-- An entry names exactly one of a player, a pair or a team; its kind must be its event's kind; and
-- `competitor_id` — which check-in and the bracket tie already key on — is GENERATED from whichever
-- is set, so it can never disagree with the typed column.
--
-- Existing rows predate the player table: each is given a player record of `legacy` source so that
-- the constraint holds over them without inventing an account for anyone.
ALTER TABLE competition.entry
  ADD COLUMN entrant_kind text NOT NULL DEFAULT 'player'
             CHECK (entrant_kind IN ('player','pair','team')),
  ADD COLUMN player_id    uuid REFERENCES competition.player(player_id),
  ADD COLUMN pair_id      uuid REFERENCES competition.pair(pair_id),
  ADD COLUMN team_id      uuid REFERENCES competition.team(team_id);

INSERT INTO competition.player (player_id, source)
  SELECT DISTINCT competitor_id, 'legacy' FROM competition.entry
  ON CONFLICT (player_id) DO NOTHING;

UPDATE competition.entry SET player_id = competitor_id WHERE player_id IS NULL;

ALTER TABLE competition.entry DROP CONSTRAINT entry_event_id_competitor_id_key;
DROP INDEX competition.entry_seed_unique;
ALTER TABLE competition.entry DROP COLUMN competitor_id;
ALTER TABLE competition.entry
  ADD COLUMN competitor_id uuid GENERATED ALWAYS AS (coalesce(player_id, pair_id, team_id)) STORED,
  ADD CONSTRAINT entry_is_exactly_one_kind_of_entrant CHECK (
       (entrant_kind = 'player' AND player_id IS NOT NULL AND pair_id IS NULL AND team_id IS NULL)
    OR (entrant_kind = 'pair'   AND pair_id IS NOT NULL AND player_id IS NULL AND team_id IS NULL)
    OR (entrant_kind = 'team'   AND team_id IS NOT NULL AND player_id IS NULL AND pair_id IS NULL)
  ),
  ADD CONSTRAINT entry_kind_is_the_event_kind
    FOREIGN KEY (event_id, entrant_kind) REFERENCES competition.event(event_id, entrant_kind),
  ADD CONSTRAINT entry_event_id_competitor_id_key UNIQUE (event_id, competitor_id);
CREATE UNIQUE INDEX entry_seed_unique ON competition.entry (event_id, seed)
  WHERE seed IS NOT NULL AND withdrawn_at IS NULL;

-- Who is physically present at check-in is a person, whatever entered. For a single-player entry
-- that is the player; for a pair or a team it is whichever member checked the side in. Nullable
-- here because existing rows and the current single-player flow do not distinguish; making it the
-- key is V015's expand-then-contract once the grant actor is a player rather than a competitor.
ALTER TABLE competition.check_in
  ADD COLUMN player_id uuid REFERENCES competition.player(player_id);
UPDATE competition.check_in c SET player_id = c.competitor_id
  WHERE EXISTS (SELECT 1 FROM competition.player p WHERE p.player_id = c.competitor_id);

-- ---------------------------------------------------------------------------------------------
-- The bracket tie was called a fixture. It is renamed; its rows are untouched.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE competition.fixture RENAME TO bracket_tie;
ALTER TABLE competition.bracket_tie RENAME CONSTRAINT fixture_pkey TO bracket_tie_pkey;
ALTER TABLE competition.bracket_tie
  RENAME CONSTRAINT fixture_event_id_round_number_position_key TO bracket_tie_event_round_position_key;
ALTER INDEX competition.fixture_by_round RENAME TO bracket_tie_by_round;

COMMENT ON TABLE competition.bracket_tie IS
  'A pairing in a knockout round of an event, possibly a bye. Not a fixture: it has a parent-child '
  'dependency on earlier ties, no rearrangement lifecycle, and advances a competitor rather than '
  'feeding a table. See ADR-012 and ADR-017.';

-- ---------------------------------------------------------------------------------------------
-- The league fixture: identity plus current schedule; every change logged; outcomes appended
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.league_fixture (
  fixture_id   uuid        PRIMARY KEY,
  league_season_id uuid    NOT NULL REFERENCES competition.league_season(league_season_id),
  division_id  uuid,
  home_team_id uuid        NOT NULL REFERENCES competition.team(team_id),
  away_team_id uuid        NOT NULL REFERENCES competition.team(team_id),
  -- The current schedule. The venue is COPIED from the home team's tenure when scheduled and is
  -- never derived at read time, or a venue move would relocate every past fixture.
  scheduled_at timestamptz NOT NULL,
  venue_id     uuid        REFERENCES competition.venue(venue_id),
  schedule_state text      NOT NULL DEFAULT 'scheduled'
               CHECK (schedule_state IN ('scheduled','rearranged','postponed')),
  -- The contest, once one exists. Set once; a fixture whose match changed would be a fixture whose
  -- result changed without a correction.
  match_id     uuid        UNIQUE REFERENCES evidence.match(match_id),
  row_version  int         NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid,
  CONSTRAINT fixture_is_between_two_teams CHECK (home_team_id <> away_team_id),
  FOREIGN KEY (division_id, league_season_id)
    REFERENCES competition.division(division_id, league_season_id)
);

CREATE INDEX league_fixture_by_season_date ON competition.league_fixture (league_season_id, scheduled_at);
CREATE INDEX league_fixture_by_team ON competition.league_fixture (home_team_id, away_team_id);

-- Every change to the schedule is appended here by trigger, so a rearrangement can be explained
-- and the original date the Secretary needs is never lost.
CREATE TABLE competition.league_fixture_change (
  change_id    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  fixture_id   uuid        NOT NULL REFERENCES competition.league_fixture(fixture_id),
  changed_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  changed_by   uuid,
  from_state   text        NOT NULL,
  to_state     text        NOT NULL,
  from_scheduled_at timestamptz NOT NULL,
  to_scheduled_at   timestamptz NOT NULL,
  from_venue_id uuid,
  to_venue_id   uuid,
  reason       text
);

-- How a fixture concluded: a decision with an actor, a time and the policy it was taken under.
-- Appended, never edited. A later decision supersedes an earlier one and says so; the earlier one
-- stays. An award is a reason, never a synthetic scoreline (ADR-012).
CREATE TABLE competition.league_fixture_outcome (
  outcome_id   uuid        PRIMARY KEY,
  fixture_id   uuid        NOT NULL REFERENCES competition.league_fixture(fixture_id),
  kind         text        NOT NULL CHECK (kind IN ('played','awarded','walkover','void')),
  legs_home    int         CHECK (legs_home IS NULL OR legs_home >= 0),
  legs_away    int         CHECK (legs_away IS NULL OR legs_away >= 0),
  to_team_id   uuid        REFERENCES competition.team(team_id),
  reason       text,
  decided_by   uuid        NOT NULL,
  decided_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  policy_id    uuid        REFERENCES competition.policy(policy_id),
  supersedes_outcome_id uuid REFERENCES competition.league_fixture_outcome(outcome_id),
  CONSTRAINT outcome_played_has_legs
    CHECK (kind <> 'played' OR (legs_home IS NOT NULL AND legs_away IS NOT NULL)),
  CONSTRAINT outcome_award_has_a_recipient_and_a_reason
    CHECK (kind NOT IN ('awarded','walkover') OR (to_team_id IS NOT NULL AND reason IS NOT NULL)),
  CONSTRAINT outcome_unplayed_has_no_scoreline
    CHECK (kind = 'played' OR (legs_home IS NULL AND legs_away IS NULL)),
  CONSTRAINT outcome_void_has_a_reason CHECK (kind <> 'void' OR reason IS NOT NULL)
);

CREATE UNIQUE INDEX outcome_supersedes_once ON competition.league_fixture_outcome (supersedes_outcome_id)
  WHERE supersedes_outcome_id IS NOT NULL;
CREATE INDEX outcome_by_fixture ON competition.league_fixture_outcome (fixture_id, decided_at);

-- A second outcome for a fixture must name the one it supersedes, and the recipient of an award
-- must be one of the two teams. Checked in a trigger because both cross rows.
CREATE FUNCTION competition.outcome_is_a_recorded_decision() RETURNS trigger AS $$
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

CREATE TRIGGER outcome_is_a_recorded_decision BEFORE INSERT ON competition.league_fixture_outcome
  FOR EACH ROW EXECUTE FUNCTION competition.outcome_is_a_recorded_decision();

CREATE FUNCTION competition.league_fixture_change_is_recorded() RETURNS trigger AS $$
BEGIN
  IF OLD.match_id IS NOT NULL AND NEW.match_id IS DISTINCT FROM OLD.match_id THEN
    RAISE EXCEPTION 'a fixture''s match is set once (fixture %)', OLD.fixture_id;
  END IF;
  IF NEW.home_team_id <> OLD.home_team_id OR NEW.away_team_id <> OLD.away_team_id
     OR NEW.league_season_id <> OLD.league_season_id THEN
    RAISE EXCEPTION 'who plays whom in which season is fixed; void it and make another (fixture %)',
      OLD.fixture_id;
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'stale write: fixture % is at version %, not %', OLD.fixture_id,
      OLD.row_version, NEW.row_version - 1;
  END IF;
  IF NEW.schedule_state IS DISTINCT FROM OLD.schedule_state
     OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
     OR NEW.venue_id IS DISTINCT FROM OLD.venue_id THEN
    INSERT INTO competition.league_fixture_change
      (fixture_id, from_state, to_state, from_scheduled_at, to_scheduled_at, from_venue_id, to_venue_id)
    VALUES (OLD.fixture_id, OLD.schedule_state, NEW.schedule_state, OLD.scheduled_at, NEW.scheduled_at,
            OLD.venue_id, NEW.venue_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER league_fixture_change_is_recorded BEFORE UPDATE ON competition.league_fixture
  FOR EACH ROW EXECUTE FUNCTION competition.league_fixture_change_is_recorded();

-- ---------------------------------------------------------------------------------------------
-- Series: linked events, never fixtures
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.series_event (
  series_season_id uuid    NOT NULL REFERENCES competition.series_season(series_season_id),
  event_id     uuid        NOT NULL REFERENCES competition.event(event_id),
  ordinal      int         NOT NULL CHECK (ordinal > 0),
  PRIMARY KEY (series_season_id, event_id),
  UNIQUE (series_season_id, ordinal)
);

COMMENT ON TABLE competition.series_event IS
  'A series is a collection of events. It references event and nothing else — no fixture, no '
  'affiliation, no registration — which is what keeps a tour from turning into a league. Series '
  'points and standings are projections in `read`, never rows here.';

-- ---------------------------------------------------------------------------------------------
-- Dated relationships: parties fixed at recording; closed once; frozen once closed
-- ---------------------------------------------------------------------------------------------

-- Arguments: the columns that identify the parties. Everything else may change while the row is
-- open (a role, a status moving forward); nothing may change once valid_until is set.
CREATE FUNCTION competition.dated_relationship_is_not_rewritable() RETURNS trigger AS $$
DECLARE
  col text;
BEGIN
  IF OLD.valid_until IS NOT NULL THEN
    RAISE EXCEPTION 'a closed relationship is history and cannot change (%)', TG_TABLE_NAME;
  END IF;
  IF NEW.valid_from <> OLD.valid_from THEN
    RAISE EXCEPTION 'a relationship''s start is fixed when recorded (%)', TG_TABLE_NAME;
  END IF;
  FOREACH col IN ARRAY TG_ARGV LOOP
    IF (to_jsonb(NEW)->>col) IS DISTINCT FROM (to_jsonb(OLD)->>col) THEN
      RAISE EXCEPTION '%.% is fixed when the relationship is recorded', TG_TABLE_NAME, col;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tenure_is_not_rewritable BEFORE UPDATE ON competition.team_venue_tenure
  FOR EACH ROW EXECUTE FUNCTION competition.dated_relationship_is_not_rewritable('team_id','venue_id','kind');
CREATE TRIGGER membership_is_not_rewritable BEFORE UPDATE ON competition.team_membership
  FOR EACH ROW EXECUTE FUNCTION competition.dated_relationship_is_not_rewritable('team_id','player_id','invited_at');
CREATE TRIGGER affiliation_is_not_rewritable BEFORE UPDATE ON competition.team_affiliation
  FOR EACH ROW EXECUTE FUNCTION competition.dated_relationship_is_not_rewritable('team_id','league_season_id');
CREATE TRIGGER registration_is_not_rewritable BEFORE UPDATE ON competition.player_registration
  FOR EACH ROW EXECUTE FUNCTION competition.dated_relationship_is_not_rewritable('player_id','league_season_id','team_id','registration_kind','supersedes_registration_id');

-- A status only moves forward: invited → active, applied → accepted.
CREATE FUNCTION competition.status_moves_forward() RETURNS trigger AS $$
BEGIN
  IF (OLD.status, NEW.status) IN (('active','invited'), ('accepted','applied')) THEN
    RAISE EXCEPTION '%.status cannot move from % back to %', TG_TABLE_NAME, OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER membership_status_moves_forward BEFORE UPDATE ON competition.team_membership
  FOR EACH ROW EXECUTE FUNCTION competition.status_moves_forward();
CREATE TRIGGER affiliation_status_moves_forward BEFORE UPDATE ON competition.team_affiliation
  FOR EACH ROW EXECUTE FUNCTION competition.status_moves_forward();

-- ---------------------------------------------------------------------------------------------
-- Authorization: the object types the graph now has, and relations that are revoked, not deleted
-- ---------------------------------------------------------------------------------------------

-- `season` was ambiguous between a league season and a series season. No row has ever been written
-- with it and no code writes it, so it is replaced rather than aliased: a dated dual concept would
-- still be a dual concept.
ALTER TABLE authz.relation DROP CONSTRAINT relation_object_type_check;
ALTER TABLE authz.relation ADD CONSTRAINT relation_object_type_check
  CHECK (object_type IN ('organisation','league','league_season','division','team','event',
                         'tournament','series','series_season','draw','match','board','venue','player'));
ALTER TABLE authz.hierarchy ADD CONSTRAINT hierarchy_child_type_check
  CHECK (child_type IN ('organisation','league','league_season','division','team','event',
                        'tournament','series','series_season','draw','match','board','venue','player'));
ALTER TABLE authz.hierarchy ADD CONSTRAINT hierarchy_parent_type_check
  CHECK (parent_type IN ('organisation','league','league_season','division','team','event',
                         'tournament','series','series_season','draw','match','board','venue','player'));

-- Who was captain last season is team history and is the answer to "who could have done this" in
-- an audit fourteen months on (ADR-008). A relation is therefore revoked, never deleted. The
-- primary key becomes a surrogate so that a relation can be granted again after revocation, with
-- uniqueness holding over the LIVE tuples only.
ALTER TABLE authz.relation DROP CONSTRAINT relation_pkey;
ALTER TABLE authz.relation
  ADD COLUMN relation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN revoked_at  timestamptz,
  ADD COLUMN revoked_by  uuid,
  ADD CONSTRAINT relation_pkey PRIMARY KEY (relation_id);
CREATE UNIQUE INDEX relation_one_live_per_tuple ON authz.relation
  (subject_id, relation, object_type, object_id) WHERE revoked_at IS NULL;

CREATE FUNCTION authz.relation_history_is_not_rewritable() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'a revoked relation is history (relation %)', OLD.relation_id;
  END IF;
  IF NEW.subject_id <> OLD.subject_id OR NEW.relation <> OLD.relation
     OR NEW.object_type <> OLD.object_type OR NEW.object_id <> OLD.object_id
     OR NEW.granted_at <> OLD.granted_at OR NEW.granted_by IS DISTINCT FROM OLD.granted_by THEN
    RAISE EXCEPTION 'a relation is fixed when granted; revoke it and grant another (relation %)',
      OLD.relation_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER relation_history_is_not_rewritable BEFORE UPDATE ON authz.relation
  FOR EACH ROW EXECUTE FUNCTION authz.relation_history_is_not_rewritable();

REVOKE DELETE ON authz.relation FROM app_competition;
GRANT UPDATE ON authz.relation TO app_competition;

-- ---------------------------------------------------------------------------------------------
-- Privileges. Every app role may read; only competition writes; NOBODY deletes history.
-- ---------------------------------------------------------------------------------------------

GRANT SELECT ON ALL TABLES IN SCHEMA competition
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT, UPDATE ON
  competition.venue, competition.team, competition.team_venue_tenure, competition.player,
  competition.team_membership, competition.league, competition.league_season, competition.division,
  competition.team_affiliation, competition.policy, competition.player_registration,
  competition.tournament, competition.pair, competition.league_fixture, competition.series,
  competition.series_season, competition.series_event
  TO app_competition;
-- Append-only logs and decisions: written by the trigger or by the module, never updated.
GRANT INSERT ON competition.team_name, competition.league_fixture_change,
  competition.league_fixture_outcome TO app_competition;
-- team_name's valid_until is closed by the trigger on rename, which runs as the updating role.
GRANT UPDATE (valid_until) ON competition.team_name TO app_competition;
GRANT SELECT, INSERT, UPDATE ON identity.player_claim TO app_competition;
GRANT SELECT ON identity.player_claim TO app_read;
REVOKE DELETE, TRUNCATE ON ALL TABLES IN SCHEMA competition
  FROM app_match, app_trust, app_rating, app_read, app_competition;
REVOKE DELETE, TRUNCATE ON identity.player_claim
  FROM app_match, app_trust, app_rating, app_read, app_competition;
ALTER DEFAULT PRIVILEGES FOR ROLE thro_owner IN SCHEMA competition
  REVOKE DELETE, TRUNCATE ON TABLES FROM app_match, app_trust, app_rating, app_read, app_competition;

RESET ROLE;

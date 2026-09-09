-- THRØ V016 — the Secretary: consent, administrative tasks, submissions, and the evidence that
-- moves them. Execution plan §7, hostile-reviewed before this file was cut.
--
-- An administrator enters a sporting fact once — a player joined a team, a fixture was played, a
-- date was proposed — and THRØ carries the administration that legitimately follows. What it never
-- does is become the authority. Four things this schema makes impossible rather than discouraged:
--
--   1. THRØ, or the team that sent it, saying the league accepted a submission. Acknowledged,
--      accepted, rejected and action-required transitions require a named person who holds an
--      administrative relation on the RECEIVING side, checked in the trigger against the live
--      authorization tuples.
--   2. A person's details leaving THRØ without a basis to hold them. A submission naming a player
--      cannot be submitted unless that player is bound to an account by a live claim AND either
--      the account is an adult with a live consent of their own or a guardian's consent is on
--      record. Unknown is not adult (PD-004, OD-010).
--   3. A registration made under a policy that was never approved, or not in force on the day.
--   4. Delivery evidence typed by hand. `delivered` requires a delivery attempt row written by the
--      transport code, or a human confirmation that names the human and says what they did.
--
-- Truth and projection, as ADR-017 has it: the transition tables are the record; the state on a
-- task or submission row is a projection the trigger maintains, and no application role may update
-- a submission row directly.
--
-- What the database CANNOT check is stated too: relation EXCLUSIONS (an admin who is also the
-- opponent) are evaluated by the handler's decision point, not here. The trigger checks that a
-- relation exists, which is the floor, not the whole rule.

SET ROLE thro_owner;

-- ---------------------------------------------------------------------------------------------
-- Consent: an artefact with an actor, not an enum
-- ---------------------------------------------------------------------------------------------

CREATE TABLE identity.consent_record (
  consent_id   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid        NOT NULL REFERENCES identity.account(account_id),
  basis        text        NOT NULL CHECK (basis IN ('self','guardian')),
  -- Who gave it. For `self`, the account itself; for `guardian`, the guardian's account or the
  -- organiser who witnessed it — never null, because "consent was recorded" with no one recording
  -- it is not a record.
  given_by     uuid        NOT NULL,
  artefact_ref text        NOT NULL,      -- 'account_creation', a stored form reference, a message id
  recorded_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at   timestamptz,
  revoked_by   uuid,
  CONSTRAINT consent_revocation_is_complete CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

CREATE INDEX consent_live_by_account ON identity.consent_record (account_id, basis) WHERE revoked_at IS NULL;

-- account.consent_basis becomes a projection of the live records: 'guardian' if one is live, else
-- 'self' if one is live, else 'none'. It is kept because PD-004 and the read models name it, and
-- it is maintained here so that it can never disagree with the records beneath it.
CREATE FUNCTION identity.project_consent_basis() RETURNS trigger AS $$
DECLARE
  acct uuid := coalesce(NEW.account_id, OLD.account_id);
  b text;
BEGIN
  SELECT CASE WHEN bool_or(basis = 'guardian') THEN 'guardian'
              WHEN bool_or(basis = 'self') THEN 'self' ELSE 'none' END
    INTO b FROM identity.consent_record WHERE account_id = acct AND revoked_at IS NULL;
  UPDATE identity.account SET consent_basis = coalesce(b, 'none') WHERE account_id = acct;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER project_consent_basis AFTER INSERT OR UPDATE ON identity.consent_record
  FOR EACH ROW EXECUTE FUNCTION identity.project_consent_basis();

CREATE FUNCTION identity.consent_history_is_not_rewritable() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'a revoked consent is history (consent %)', OLD.consent_id;
  END IF;
  IF NEW.account_id <> OLD.account_id OR NEW.basis <> OLD.basis OR NEW.given_by <> OLD.given_by
     OR NEW.artefact_ref <> OLD.artefact_ref OR NEW.recorded_at <> OLD.recorded_at THEN
    RAISE EXCEPTION 'a consent record is fixed when made; revoke it and record another (consent %)', OLD.consent_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER consent_history_is_not_rewritable BEFORE UPDATE ON identity.consent_record
  FOR EACH ROW EXECUTE FUNCTION identity.consent_history_is_not_rewritable();

-- A person who creates their own account has, by that act, consented to THRØ holding what they
-- typed; the record says so with the account as its own actor. An account created by anyone else
-- starts with NO basis, whatever the writer passed, until a record is made.
CREATE FUNCTION identity.account_consent_starts_honest() RETURNS trigger AS $$
BEGIN
  IF NEW.created_via = 'self' THEN
    INSERT INTO identity.consent_record (account_id, basis, given_by, artefact_ref)
      VALUES (NEW.account_id, 'self', NEW.account_id, 'account_creation');
  ELSE
    UPDATE identity.account SET consent_basis = 'none' WHERE account_id = NEW.account_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER account_consent_starts_honest AFTER INSERT ON identity.account
  FOR EACH ROW EXECUTE FUNCTION identity.account_consent_starts_honest();

-- The disclosure gate, in one place. TRUE only when the player is bound by a live claim to an
-- account that is an adult with their own live consent, or that has a guardian's live consent.
-- 'unknown' is not adult. A player with no claim has nobody who could have consented.
CREATE FUNCTION identity.player_may_be_disclosed(p uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
      FROM identity.player_claim c
      JOIN identity.account a ON a.account_id = c.account_id
     WHERE c.player_id = p AND c.revoked_at IS NULL AND a.deleted_at IS NULL
       AND (
         EXISTS (SELECT 1 FROM identity.consent_record r
                  WHERE r.account_id = a.account_id AND r.revoked_at IS NULL AND r.basis = 'guardian')
         OR (a.age_band = 'adult' AND EXISTS (
             SELECT 1 FROM identity.consent_record r
              WHERE r.account_id = a.account_id AND r.revoked_at IS NULL AND r.basis = 'self'))
       )
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ---------------------------------------------------------------------------------------------
-- No executable rule without an approved policy in force on the day
-- ---------------------------------------------------------------------------------------------

CREATE FUNCTION competition.policy_governs(pid uuid, on_day date) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM competition.policy
     WHERE policy_id = pid AND approval_state IN ('approved','superseded')
       AND effective_from <= on_day AND (effective_to IS NULL OR effective_to >= on_day)
  );
$$ LANGUAGE sql STABLE;

CREATE FUNCTION competition.registration_cites_a_governing_policy() RETURNS trigger AS $$
DECLARE
  d date := (NEW.valid_from AT TIME ZONE 'Europe/London')::date;
BEGIN
  IF NEW.status = 'registered' AND NOT competition.policy_governs(NEW.policy_id, d) THEN
    RAISE EXCEPTION 'a registration is made under a policy that was approved and in force on % (registration %)', d, NEW.registration_id;
  END IF;
  IF NEW.dual_registration_policy_id IS NOT NULL
     AND NOT competition.policy_governs(NEW.dual_registration_policy_id, d) THEN
    RAISE EXCEPTION 'dual registration is permitted only by a policy in force on % (registration %)', d, NEW.registration_id;
  END IF;
  -- Status moves forward only: pending -> registered | refused; registered -> lapsed.
  IF TG_OP = 'UPDATE' AND NEW.status <> OLD.status AND NOT (
       (OLD.status = 'pending' AND NEW.status IN ('registered','refused'))
    OR (OLD.status = 'registered' AND NEW.status = 'lapsed')) THEN
    RAISE EXCEPTION 'a registration does not move from % to % (registration %)', OLD.status, NEW.status, NEW.registration_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER registration_cites_a_governing_policy BEFORE INSERT OR UPDATE ON competition.player_registration
  FOR EACH ROW EXECUTE FUNCTION competition.registration_cites_a_governing_policy();

CREATE FUNCTION competition.outcome_cites_a_governing_policy() RETURNS trigger AS $$
BEGIN
  IF NEW.policy_id IS NOT NULL
     AND NOT competition.policy_governs(NEW.policy_id, (NEW.decided_at AT TIME ZONE 'Europe/London')::date) THEN
    RAISE EXCEPTION 'an outcome cites a policy that governed on the day it was decided (fixture %)', NEW.fixture_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER outcome_cites_a_governing_policy BEFORE INSERT ON competition.league_fixture_outcome
  FOR EACH ROW EXECUTE FUNCTION competition.outcome_cites_a_governing_policy();

-- ---------------------------------------------------------------------------------------------
-- A rearrangement is proposed to the opponent before anyone changes the fixture
-- ---------------------------------------------------------------------------------------------

-- Only the league's administration may change a fixture row (OrganisationCommands). So a
-- rearrangement between teams is first a PROPOSAL: one team asks, the other answers, and the
-- league (or later an adapter) applies. The proposal is the source of the opponent's task and the
-- subject of the submission; the fixture change, if it comes, cites it.
CREATE TABLE competition.fixture_rearrangement_proposal (
  proposal_id  uuid        PRIMARY KEY,
  fixture_id   uuid        NOT NULL REFERENCES competition.league_fixture(fixture_id),
  proposed_by_team_id uuid NOT NULL REFERENCES competition.team(team_id),
  to_team_id   uuid        NOT NULL REFERENCES competition.team(team_id),
  proposed_at  timestamptz NOT NULL,          -- the new date
  proposed_venue_id uuid   REFERENCES competition.venue(venue_id),
  reason       text,
  state        text        NOT NULL DEFAULT 'proposed'
               CHECK (state IN ('proposed','accepted','declined','withdrawn','applied')),
  proposed_by  uuid        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  answered_by  uuid,
  answered_at  timestamptz,
  row_version  int         NOT NULL DEFAULT 1,
  CONSTRAINT proposal_is_between_the_two_teams CHECK (proposed_by_team_id <> to_team_id),
  CONSTRAINT proposal_answer_is_complete
    CHECK ((state IN ('proposed','withdrawn')) = (answered_by IS NULL AND answered_at IS NULL))
);

CREATE UNIQUE INDEX proposal_one_open_per_fixture ON competition.fixture_rearrangement_proposal (fixture_id)
  WHERE state = 'proposed';

ALTER TABLE competition.league_fixture_change
  ADD COLUMN proposal_id uuid REFERENCES competition.fixture_rearrangement_proposal(proposal_id);

CREATE FUNCTION competition.proposal_moves_forward() RETURNS trigger AS $$
BEGIN
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'stale write: proposal % is at version %, not %', OLD.proposal_id, OLD.row_version, NEW.row_version - 1;
  END IF;
  IF NEW.fixture_id <> OLD.fixture_id OR NEW.proposed_by_team_id <> OLD.proposed_by_team_id
     OR NEW.to_team_id <> OLD.to_team_id OR NEW.proposed_at <> OLD.proposed_at THEN
    RAISE EXCEPTION 'a proposal is fixed when made; withdraw it and make another (proposal %)', OLD.proposal_id;
  END IF;
  IF NEW.state <> OLD.state AND NOT (
       (OLD.state = 'proposed' AND NEW.state IN ('accepted','declined','withdrawn'))
    OR (OLD.state = 'accepted' AND NEW.state = 'applied')) THEN
    RAISE EXCEPTION 'a proposal does not move from % to % (proposal %)', OLD.state, NEW.state, OLD.proposal_id;
  END IF;
  -- The proposer's own team cannot answer its own proposal. The handler's decision point applies
  -- the full rule; this is the floor.
  IF NEW.state IN ('accepted','declined') AND NOT EXISTS (
       SELECT 1 FROM authz.relation r
        WHERE r.subject_id = NEW.answered_by AND r.revoked_at IS NULL
          AND r.object_type = 'team' AND r.object_id = NEW.to_team_id::text
          AND r.relation IN ('admin','captain')) THEN
    RAISE EXCEPTION 'only the opponent''s administration answers a proposal (proposal %)', OLD.proposal_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER proposal_moves_forward BEFORE UPDATE ON competition.fixture_rearrangement_proposal
  FOR EACH ROW EXECUTE FUNCTION competition.proposal_moves_forward();

-- The fixture change log gains the proposal it applied. The V014 trigger is replaced to read it
-- from a session setting the handler sets around the write; a change with no proposal is a league
-- decision taken directly, and says so by leaving it null.
CREATE OR REPLACE FUNCTION competition.league_fixture_change_is_recorded() RETURNS trigger AS $$
DECLARE
  prop uuid := nullif(current_setting('thro.proposal', true), '')::uuid;
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
      (fixture_id, from_state, to_state, from_scheduled_at, to_scheduled_at, from_venue_id, to_venue_id, proposal_id)
    VALUES (OLD.fixture_id, OLD.schedule_state, NEW.schedule_state, OLD.scheduled_at, NEW.scheduled_at,
            OLD.venue_id, NEW.venue_id, prop);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------------------------
-- Tasks
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.admin_task (
  task_id      uuid        PRIMARY KEY,
  kind         text        NOT NULL
               CHECK (kind IN ('registration_required','consent_required',
                               'result_submission_due','rearrangement_answer_due','manual')),
  -- Who owes it: exactly one of a team, a league season, or a player (consent is the player's or
  -- their guardian's to give, not the captain's to chase).
  owner_team_id uuid       REFERENCES competition.team(team_id),
  owner_league_season_id uuid REFERENCES competition.league_season(league_season_id),
  owner_player_id uuid     REFERENCES competition.player(player_id),
  -- What produced it. The task can always answer "why am I being asked this".
  source_kind  text        NOT NULL
               CHECK (source_kind IN ('reconciliation','fixture_outcome','rearrangement_proposal','manual')),
  source_id    uuid,
  subject_player_id uuid   REFERENCES competition.player(player_id),
  subject_fixture_id uuid  REFERENCES competition.league_fixture(fixture_id),
  subject_league_season_id uuid REFERENCES competition.league_season(league_season_id),
  -- Materialised at creation. A later policy version makes a new task; it never rewrites this
  -- one's words.
  reason       text        NOT NULL,
  missing_facts text[]     NOT NULL DEFAULT '{}',
  policy_id    uuid        REFERENCES competition.policy(policy_id),
  -- How the deadline was derived, so it can be recomputed and the recomputation logged.
  due_at       timestamptz,
  due_rule     text,                           -- 'on:2026-09-30' | 'days_before_first_fixture:7'
  due_anchor_fixture_id uuid REFERENCES competition.league_fixture(fixture_id),
  state        text        NOT NULL DEFAULT 'open'
               CHECK (state IN ('open','waiting_player','waiting_opponent','waiting_league','done','cancelled')),
  row_version  int         NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid,
  CONSTRAINT task_has_one_owner
    CHECK (num_nonnulls(owner_team_id, owner_league_season_id, owner_player_id) = 1),
  CONSTRAINT task_has_a_subject
    CHECK (kind = 'manual' OR num_nonnulls(subject_player_id, subject_fixture_id, subject_league_season_id) >= 1),
  -- A task derived from a policy cites it, always.
  CONSTRAINT policy_derived_task_cites_its_policy
    CHECK (kind NOT IN ('registration_required') OR policy_id IS NOT NULL)
);

-- One open task per (kind, owner, subject). A fact produces its task once; re-running the
-- derivation is idempotent. This is the mechanical form of "do not manufacture busywork".
CREATE UNIQUE INDEX task_one_open_per_subject ON competition.admin_task
  (kind,
   coalesce(owner_team_id, owner_league_season_id, owner_player_id),
   coalesce(subject_player_id, '00000000-0000-0000-0000-000000000000'::uuid),
   coalesce(subject_league_season_id, '00000000-0000-0000-0000-000000000000'::uuid),
   coalesce(subject_fixture_id, '00000000-0000-0000-0000-000000000000'::uuid),
   coalesce(source_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE state NOT IN ('done','cancelled');
CREATE INDEX task_inbox_team ON competition.admin_task (owner_team_id, state, due_at);
CREATE INDEX task_inbox_player ON competition.admin_task (owner_player_id, state, due_at);

-- Every change of state or deadline, appended by trigger.
CREATE TABLE competition.admin_task_event (
  event_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id      uuid        NOT NULL REFERENCES competition.admin_task(task_id),
  at           timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id     uuid,
  from_state   text        NOT NULL,
  to_state     text        NOT NULL,
  from_due_at  timestamptz,
  to_due_at    timestamptz,
  cause_change_id uuid     REFERENCES competition.league_fixture_change(change_id),
  note         text
);

CREATE INDEX task_event_by_task ON competition.admin_task_event (task_id, at);

-- Set by the handler before an UPDATE so the trigger can attribute the event. Session-local.
CREATE FUNCTION competition.task_is_versioned_and_history_is_kept() RETURNS trigger AS $$
DECLARE
  actor uuid := nullif(current_setting('thro.actor', true), '')::uuid;
  cause uuid := nullif(current_setting('thro.cause_change', true), '')::uuid;
  note_ text := nullif(current_setting('thro.note', true), '');
BEGIN
  IF OLD.state IN ('done','cancelled') AND NEW.state <> OLD.state THEN
    RAISE EXCEPTION 'a finished task is history; open a new one (task %)', OLD.task_id;
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'stale write: task % is at version %, not %', OLD.task_id, OLD.row_version, NEW.row_version - 1;
  END IF;
  IF NEW.kind <> OLD.kind OR NEW.source_kind <> OLD.source_kind OR NEW.source_id IS DISTINCT FROM OLD.source_id
     OR NEW.owner_team_id IS DISTINCT FROM OLD.owner_team_id
     OR NEW.owner_league_season_id IS DISTINCT FROM OLD.owner_league_season_id
     OR NEW.owner_player_id IS DISTINCT FROM OLD.owner_player_id
     OR NEW.policy_id IS DISTINCT FROM OLD.policy_id OR NEW.reason <> OLD.reason THEN
    RAISE EXCEPTION 'what a task is, who owes it and why are fixed when it is made (task %)', OLD.task_id;
  END IF;
  IF NEW.state <> OLD.state OR NEW.due_at IS DISTINCT FROM OLD.due_at THEN
    INSERT INTO competition.admin_task_event (task_id, actor_id, from_state, to_state, from_due_at, to_due_at, cause_change_id, note)
      VALUES (OLD.task_id, actor, OLD.state, NEW.state, OLD.due_at, NEW.due_at, cause, note_);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER task_is_versioned_and_history_is_kept BEFORE UPDATE ON competition.admin_task
  FOR EACH ROW EXECUTE FUNCTION competition.task_is_versioned_and_history_is_kept();

-- A requirement THRØ cannot check — "passport photo" — is satisfied only by a named person saying
-- so, with a note. It renders as a manual step, never as a tick THRØ awarded.
CREATE TABLE competition.admin_task_manual_confirmation (
  confirmation_id uuid     PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id      uuid        NOT NULL REFERENCES competition.admin_task(task_id),
  requirement  text        NOT NULL,
  confirmed_by uuid        NOT NULL,
  note         text        NOT NULL,
  confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (task_id, requirement)
);

-- ---------------------------------------------------------------------------------------------
-- Submissions, deliveries, artefacts, transitions
-- ---------------------------------------------------------------------------------------------

CREATE TABLE competition.submission (
  submission_id uuid       PRIMARY KEY,
  kind         text        NOT NULL CHECK (kind IN ('player_registration','result','fixture_rearrangement')),
  from_team_id uuid        NOT NULL REFERENCES competition.team(team_id),
  -- Who receives it: the league season's administration, or the opposing team. Exactly one.
  to_league_season_id uuid REFERENCES competition.league_season(league_season_id),
  to_team_id   uuid        REFERENCES competition.team(team_id),
  -- What it is about: exactly one, and it must match the kind.
  subject_player_id uuid   REFERENCES competition.player(player_id),
  subject_league_season_id uuid REFERENCES competition.league_season(league_season_id),
  outcome_id   uuid        REFERENCES competition.league_fixture_outcome(outcome_id),
  proposal_id  uuid        REFERENCES competition.fixture_rearrangement_proposal(proposal_id),
  task_id      uuid        REFERENCES competition.admin_task(task_id),
  state        text        NOT NULL DEFAULT 'draft'
               CHECK (state IN ('draft','ready','submitted','delivered','delivery_failed','acknowledged',
                                'accepted','accepted_conditional','rejected','action_required',
                                'withdrawn','superseded')),
  -- The approved policy version this was prepared under, where a policy governs the kind.
  policy_id    uuid        REFERENCES competition.policy(policy_id),
  row_version  int         NOT NULL DEFAULT 1,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by   uuid,
  CONSTRAINT submission_has_one_recipient CHECK (num_nonnulls(to_league_season_id, to_team_id) = 1),
  CONSTRAINT submission_subject_matches_kind CHECK (
       (kind = 'player_registration'   AND subject_player_id IS NOT NULL AND subject_league_season_id IS NOT NULL
          AND outcome_id IS NULL AND proposal_id IS NULL AND to_league_season_id = subject_league_season_id)
    OR (kind = 'result'                AND outcome_id IS NOT NULL AND subject_player_id IS NULL AND proposal_id IS NULL
          AND to_league_season_id IS NOT NULL)
    OR (kind = 'fixture_rearrangement' AND proposal_id IS NOT NULL AND subject_player_id IS NULL AND outcome_id IS NULL
          AND to_team_id IS NOT NULL)
  ),
  CONSTRAINT registration_submission_cites_its_policy
    CHECK (kind <> 'player_registration' OR policy_id IS NOT NULL)
);

-- One live registration submission per (player, season). Two teams sending the same player to
-- the same league is the transfer problem, and it is caught here, before the league answers,
-- rather than at acceptance by the registration exclusion constraint.
CREATE UNIQUE INDEX submission_one_live_registration ON competition.submission (subject_player_id, subject_league_season_id)
  WHERE kind = 'player_registration' AND state NOT IN ('withdrawn','rejected','superseded');
CREATE INDEX submission_by_recipient ON competition.submission (to_league_season_id, state);
CREATE INDEX submission_by_sender ON competition.submission (from_team_id, state);

-- A delivery attempt, written by the transport code and nothing else. This is what
-- `delivered` and `delivery_failed` point at; a message id typed into a form is not one.
CREATE TABLE competition.submission_delivery (
  delivery_id  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid       NOT NULL REFERENCES competition.submission(submission_id),
  attempt_no   int         NOT NULL CHECK (attempt_no > 0),
  transport    text        NOT NULL CHECK (transport IN ('api','structured','export','document','email','manual')),
  adapter      text        NOT NULL,          -- which code sent it
  provider_ref text,                          -- message id, upload id, response id
  sent_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  status       text        NOT NULL CHECK (status IN ('sent','delivered','failed')),
  detail       text,
  UNIQUE (submission_id, attempt_no)
);

-- Inbound material from the counterparty — their email, their portal response, a scan of the
-- signed card — retained, hashed, and attributed to whoever captured it.
CREATE TABLE competition.submission_artefact (
  artefact_id  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid       NOT NULL REFERENCES competition.submission(submission_id),
  kind         text        NOT NULL CHECK (kind IN ('counterparty_message','api_response','document_scan')),
  stored_ref   text        NOT NULL,
  sha256       text        NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  captured_by  uuid        NOT NULL,
  captured_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE competition.submission_transition (
  transition_id uuid       PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid       NOT NULL REFERENCES competition.submission(submission_id),
  expected_version int     NOT NULL,
  at           timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id     uuid,
  from_state   text        NOT NULL,
  to_state     text        NOT NULL,
  evidence_kind text       CHECK (evidence_kind IN ('delivery','artefact','human_confirmation')),
  delivery_id  uuid        REFERENCES competition.submission_delivery(delivery_id),
  artefact_id  uuid        REFERENCES competition.submission_artefact(artefact_id),
  -- For an acceptance of a registration: the date the league registered the player FROM, taken
  -- from the league's answer, never inferred. Conditions make it conditional, not accepted.
  registered_from date,
  conditions   text,
  note         text,
  CONSTRAINT transition_evidence_is_consistent CHECK (
       (evidence_kind IS NULL AND delivery_id IS NULL AND artefact_id IS NULL)
    OR (evidence_kind = 'delivery' AND delivery_id IS NOT NULL AND artefact_id IS NULL)
    OR (evidence_kind = 'artefact' AND artefact_id IS NOT NULL AND delivery_id IS NULL)
    OR (evidence_kind = 'human_confirmation' AND delivery_id IS NULL AND artefact_id IS NULL AND note IS NOT NULL AND actor_id IS NOT NULL)
  )
);

CREATE INDEX transition_by_submission ON competition.submission_transition (submission_id, at);

-- Does this person administer the receiving side? The floor of the counterparty rule: a live
-- relation on the league season (admin) or the team (admin, captain). Exclusions are the handler's.
CREATE FUNCTION competition.administers_recipient(actor uuid, s competition.submission) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM authz.relation r
     WHERE r.subject_id = actor AND r.revoked_at IS NULL
       AND ((s.to_league_season_id IS NOT NULL AND r.object_type = 'league_season'
               AND r.object_id = s.to_league_season_id::text AND r.relation = 'admin')
         OR (s.to_team_id IS NOT NULL AND r.object_type = 'team'
               AND r.object_id = s.to_team_id::text AND r.relation IN ('admin','captain')))
  );
$$ LANGUAGE sql STABLE;

-- The transition graph and its evidence rule, as the database enforces it. The same table lives in
-- the competition package as SubmissionTransitions.RULES; a test compares the two.
--
--   draft                  -> ready               THRØ; no evidence
--   ready                  -> submitted           a named submitter; the disclosure gate for a player subject
--   submitted              -> delivered           a delivery row, or a human confirmation with actor and note
--   submitted              -> delivery_failed     a delivery row
--   delivery_failed        -> ready               a named submitter
--   delivered              -> acknowledged        a named RECIPIENT administrator; artefact or human confirmation
--   acknowledged           -> accepted | accepted_conditional | rejected | action_required   same
--   accepted_conditional   -> accepted            same
--   action_required        -> ready               a named submitter
--   ready|submitted|delivery_failed|action_required -> withdrawn   a named submitter (nothing delivered is unsent)
--   any non-terminal       -> superseded          THRØ, when the subject was superseded
CREATE FUNCTION competition.submission_moves_only_with_evidence() RETURNS trigger AS $$
DECLARE
  s competition.submission%ROWTYPE;
  n int;
  d competition.submission_delivery%ROWTYPE;
BEGIN
  SELECT * INTO s FROM competition.submission WHERE submission_id = NEW.submission_id FOR UPDATE;
  IF s.state <> NEW.from_state OR s.row_version <> NEW.expected_version THEN
    RAISE EXCEPTION 'stale transition: submission % is % at version %, not % at version %',
      NEW.submission_id, s.state, s.row_version, NEW.from_state, NEW.expected_version;
  END IF;
  IF NEW.delivery_id IS NOT NULL THEN
    SELECT * INTO d FROM competition.submission_delivery WHERE delivery_id = NEW.delivery_id;
    IF d.submission_id IS DISTINCT FROM NEW.submission_id THEN
      RAISE EXCEPTION 'a delivery belongs to the submission it moves';
    END IF;
  END IF;
  IF NEW.artefact_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM competition.submission_artefact a WHERE a.artefact_id = NEW.artefact_id AND a.submission_id = NEW.submission_id) THEN
    RAISE EXCEPTION 'an artefact belongs to the submission it moves';
  END IF;

  IF NEW.from_state = 'draft' AND NEW.to_state = 'ready' THEN
    NULL;
  ELSIF NEW.from_state = 'ready' AND NEW.to_state = 'submitted' THEN
    IF NEW.actor_id IS NULL THEN RAISE EXCEPTION 'submitting needs a named person'; END IF;
    IF s.subject_player_id IS NOT NULL AND NOT identity.player_may_be_disclosed(s.subject_player_id) THEN
      RAISE EXCEPTION 'nothing about this player leaves THRO: they are not bound to an account with a consent basis THRO can rely on (PD-004)';
    END IF;
  ELSIF NEW.from_state = 'submitted' AND NEW.to_state = 'delivered' THEN
    IF NOT ((NEW.evidence_kind = 'delivery' AND d.status = 'delivered')
            OR NEW.evidence_kind = 'human_confirmation') THEN
      RAISE EXCEPTION 'delivered needs a delivery attempt that reports delivered, or a human confirmation naming the human and what they did';
    END IF;
  ELSIF NEW.from_state = 'submitted' AND NEW.to_state = 'delivery_failed' THEN
    IF NOT (NEW.evidence_kind = 'delivery' AND d.status = 'failed') THEN
      RAISE EXCEPTION 'delivery_failed needs the failed delivery attempt';
    END IF;
  ELSIF (NEW.from_state = 'delivered' AND NEW.to_state = 'acknowledged')
     OR (NEW.from_state = 'acknowledged' AND NEW.to_state IN ('accepted','accepted_conditional','rejected','action_required'))
     OR (NEW.from_state = 'accepted_conditional' AND NEW.to_state = 'accepted') THEN
    IF NEW.actor_id IS NULL OR NOT competition.administers_recipient(NEW.actor_id, s) THEN
      RAISE EXCEPTION '% is the recipient''s word: it needs a named person who administers the receiving side, and % is not one',
        NEW.to_state, coalesce(NEW.actor_id::text, 'THRO alone');
    END IF;
    IF NEW.evidence_kind IS NULL OR NEW.evidence_kind NOT IN ('artefact','human_confirmation') THEN
      RAISE EXCEPTION '% needs the recipient''s artefact or a named confirmation', NEW.to_state;
    END IF;
    IF s.kind = 'player_registration' AND NEW.to_state IN ('accepted','accepted_conditional') AND NEW.registered_from IS NULL THEN
      RAISE EXCEPTION 'an acceptance says from which date the league registered the player';
    END IF;
    IF NEW.to_state = 'accepted' AND NEW.conditions IS NOT NULL THEN
      RAISE EXCEPTION 'an acceptance with conditions is accepted_conditional, not accepted';
    END IF;
    IF NEW.to_state = 'accepted_conditional' AND NEW.conditions IS NULL THEN
      RAISE EXCEPTION 'accepted_conditional states its conditions';
    END IF;
  ELSIF NEW.from_state IN ('action_required','delivery_failed') AND NEW.to_state = 'ready' THEN
    IF NEW.actor_id IS NULL THEN RAISE EXCEPTION 'reopening needs a named person'; END IF;
  ELSIF NEW.from_state IN ('ready','submitted','delivery_failed','action_required') AND NEW.to_state = 'withdrawn' THEN
    IF NEW.actor_id IS NULL THEN RAISE EXCEPTION 'withdrawing needs a named person'; END IF;
  ELSIF NEW.to_state = 'superseded' AND NEW.from_state NOT IN ('accepted','rejected','withdrawn','superseded') THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'a submission does not move from % to %', NEW.from_state, NEW.to_state;
  END IF;

  UPDATE competition.submission
     SET state = NEW.to_state, row_version = row_version + 1
   WHERE submission_id = NEW.submission_id AND row_version = NEW.expected_version;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'stale transition: submission % moved under this write', NEW.submission_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER submission_moves_only_with_evidence BEFORE INSERT ON competition.submission_transition
  FOR EACH ROW EXECUTE FUNCTION competition.submission_moves_only_with_evidence();

-- The row is the projection; only the transition trigger (SECURITY DEFINER, owner) may update it.
-- No application role holds UPDATE on competition.submission at all — see the grants below and
-- the schema property that asserts it.
CREATE FUNCTION competition.submission_identity_is_fixed() RETURNS trigger AS $$
BEGIN
  IF NEW.kind <> OLD.kind OR NEW.from_team_id <> OLD.from_team_id
     OR NEW.to_league_season_id IS DISTINCT FROM OLD.to_league_season_id
     OR NEW.to_team_id IS DISTINCT FROM OLD.to_team_id
     OR NEW.subject_player_id IS DISTINCT FROM OLD.subject_player_id
     OR NEW.subject_league_season_id IS DISTINCT FROM OLD.subject_league_season_id
     OR NEW.outcome_id IS DISTINCT FROM OLD.outcome_id
     OR NEW.proposal_id IS DISTINCT FROM OLD.proposal_id
     OR NEW.policy_id IS DISTINCT FROM OLD.policy_id THEN
    RAISE EXCEPTION 'what a submission is, and to whom, is fixed when it is made (submission %)', OLD.submission_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER submission_identity_is_fixed BEFORE UPDATE ON competition.submission
  FOR EACH ROW EXECUTE FUNCTION competition.submission_identity_is_fixed();

-- A superseded outcome supersedes every live submission that carried it. Appended as a transition
-- like any other move, so the history reads the same way.
CREATE FUNCTION competition.superseded_outcome_supersedes_its_submissions() RETURNS trigger AS $$
DECLARE
  sub record;
BEGIN
  IF NEW.supersedes_outcome_id IS NOT NULL THEN
    FOR sub IN SELECT submission_id, state, row_version FROM competition.submission
                WHERE outcome_id = NEW.supersedes_outcome_id
                  AND state NOT IN ('accepted','rejected','withdrawn','superseded') LOOP
      INSERT INTO competition.submission_transition (submission_id, expected_version, from_state, to_state, note)
        VALUES (sub.submission_id, sub.row_version, sub.state, 'superseded',
                'the outcome this carried was superseded by ' || NEW.outcome_id::text);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER superseded_outcome_supersedes_its_submissions AFTER INSERT ON competition.league_fixture_outcome
  FOR EACH ROW EXECUTE FUNCTION competition.superseded_outcome_supersedes_its_submissions();

-- ---------------------------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------------------------

GRANT SELECT ON identity.consent_record TO app_read, app_competition;
GRANT INSERT, UPDATE ON identity.consent_record TO app_competition;
GRANT SELECT ON competition.fixture_rearrangement_proposal, competition.admin_task, competition.admin_task_event,
  competition.admin_task_manual_confirmation, competition.submission, competition.submission_delivery,
  competition.submission_artefact, competition.submission_transition
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT, UPDATE ON competition.fixture_rearrangement_proposal, competition.admin_task TO app_competition;
GRANT INSERT ON competition.admin_task_event, competition.admin_task_manual_confirmation, competition.submission,
  competition.submission_delivery, competition.submission_artefact, competition.submission_transition
  TO app_competition;
-- Deliberately NO UPDATE on submission for any application role: its state is the transition
-- trigger's to project, and nobody else's.
REVOKE UPDATE, DELETE, TRUNCATE ON competition.submission
  FROM app_match, app_trust, app_rating, app_read, app_competition;
REVOKE DELETE, TRUNCATE ON identity.consent_record, competition.fixture_rearrangement_proposal,
  competition.admin_task, competition.admin_task_event, competition.admin_task_manual_confirmation,
  competition.submission_delivery, competition.submission_artefact, competition.submission_transition
  FROM app_match, app_trust, app_rating, app_read, app_competition;

RESET ROLE;

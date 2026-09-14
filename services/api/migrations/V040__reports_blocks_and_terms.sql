-- THRØ V040 — anything a person wrote can be reported, anyone can be blocked, and nobody posts before
-- agreeing (PD-050).
--
-- Apple's guideline 1.2 and Google Play's user-generated-content policy ask the same four things of any app
-- that carries what people write: filter it, let people report it, let people block each other, and publish
-- a way to reach you. THRØ carries display names, team names, venue names and league names, and had none of
-- the four. This is the schema for three of them; the fourth is a sentence in the terms.
--
-- **A report is a record, not a deletion.** It names the thing reported — a team, a venue, a league, an
-- account — and keeps who reported it, when, and what was decided. The decision is a row of its own, so a
-- moderation history reads back as a sequence of decisions rather than as a mutable status. Nothing a player
-- wrote is destroyed by a report: it is hidden, corrected or left, and the record says which.
--
-- **Blocking needs no reason.** A player may simply want to be left alone, so a block is one row with two
-- accounts and a date, withdrawable, and the withdrawal is kept too.
--
-- **Accepting the terms is recorded once, with the version.** "The version they agreed to" is the only
-- honest answer to "what did they agree to", and it changes when the terms change.

-- The schema is created BEFORE taking the owner's role, as V001 creates the others: `thro_owner` owns
-- schemas but may not create them, so `SET ROLE thro_owner` first earns "permission denied for database".
-- Written exactly as V001 writes it, with no IF NOT EXISTS: the ledger runs a migration once, so guarding
-- against a second run guards against nothing — and `tools/check_migrations.py` permits precisely one
-- statement before SET ROLE, `CREATE SCHEMA <name> AUTHORIZATION thro_owner`, which this now is.
CREATE SCHEMA safety AUTHORIZATION thro_owner;

SET ROLE thro_owner;

-- What can be reported. Deliberately narrow: the things a person writes that another person reads.
CREATE TABLE safety.report (
  report_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_kind  text        NOT NULL CHECK (subject_kind IN ('account','team','venue','league','match')),
  subject_id    uuid        NOT NULL,
  -- The account that reported it. Kept: a report with no reporter cannot be answered or weighed.
  reported_by   uuid        NOT NULL REFERENCES identity.account(account_id),
  reason        text        NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 600),
  -- Raised by, or about, somebody THRØ knows to be a child: it goes to the front of the queue (PD-050).
  urgent        boolean     NOT NULL DEFAULT false,
  reported_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- The promise the stores hold us to, written down where the queue can sort by it.
  answer_due_at timestamptz NOT NULL,
  CONSTRAINT a_report_is_answered_within_a_day CHECK (answer_due_at > reported_at
    AND answer_due_at <= reported_at + interval '24 hours')
);

CREATE INDEX report_by_subject ON safety.report (subject_kind, subject_id, reported_at DESC);
CREATE INDEX report_queue ON safety.report (urgent DESC, answer_due_at);

CREATE FUNCTION safety.report_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'a report is kept: somebody raised it, and that it was raised does not change';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER report_is_kept BEFORE UPDATE OR DELETE ON safety.report
  FOR EACH ROW EXECUTE FUNCTION safety.report_is_kept();

-- What was decided about it, and by whom. A second look at the same report is a second decision, not an edit.
CREATE TABLE safety.decision (
  decision_id  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id    uuid        NOT NULL REFERENCES safety.report(report_id),
  outcome      text        NOT NULL CHECK (outcome IN ('left','hidden','corrected','account_suspended','not_upheld')),
  note         text        NOT NULL CHECK (length(btrim(note)) BETWEEN 3 AND 1000),
  decided_by   uuid        NOT NULL REFERENCES identity.account(account_id),
  decided_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX decision_by_report ON safety.decision (report_id, decided_at);

CREATE FUNCTION safety.decision_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'a decision is kept: it was made, and it is answered by making another';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER decision_is_kept BEFORE UPDATE OR DELETE ON safety.decision
  FOR EACH ROW EXECUTE FUNCTION safety.decision_is_kept();

-- One account asking not to be reached by another. No reason is asked for and none is stored.
CREATE TABLE safety.block (
  block_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id   uuid        NOT NULL REFERENCES identity.account(account_id),
  blocked_id   uuid        NOT NULL REFERENCES identity.account(account_id),
  blocked_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  lifted_at    timestamptz,
  CONSTRAINT a_block_is_between_two_people CHECK (blocker_id <> blocked_id),
  CONSTRAINT a_lift_comes_after CHECK (lifted_at IS NULL OR lifted_at > blocked_at)
);

CREATE UNIQUE INDEX block_live ON safety.block (blocker_id, blocked_id) WHERE lifted_at IS NULL;
CREATE INDEX block_by_blocked ON safety.block (blocked_id) WHERE lifted_at IS NULL;

CREATE FUNCTION safety.block_is_lifted_not_rewritten() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'a block is lifted, not deleted'; END IF;
  IF OLD.lifted_at IS NOT NULL THEN RAISE EXCEPTION 'that block is already lifted; blocking again is a new block'; END IF;
  IF NEW.blocker_id <> OLD.blocker_id OR NEW.blocked_id <> OLD.blocked_id OR NEW.blocked_at <> OLD.blocked_at THEN
    RAISE EXCEPTION 'a block is not rewritten; it is lifted';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER block_is_lifted_not_rewritten BEFORE UPDATE OR DELETE ON safety.block
  FOR EACH ROW EXECUTE FUNCTION safety.block_is_lifted_not_rewritten();

-- Whether two accounts are blocked either way. One narrow function, in the shape V037's `seat_of` set, so
-- the roles that decide whether a person may reach another can ask this and nothing else about safety.
CREATE FUNCTION safety.is_blocked(a uuid, b uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM safety.block
     WHERE lifted_at IS NULL
       AND ((blocker_id = a AND blocked_id = b) OR (blocker_id = b AND blocked_id = a))
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

REVOKE ALL ON FUNCTION safety.is_blocked(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION safety.is_blocked(uuid, uuid) TO app_competition, app_read, app_match, app_trust;

-- What a player agreed to, and which version of it. Recorded once per version.
CREATE TABLE safety.terms_acceptance (
  acceptance_id uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid        NOT NULL REFERENCES identity.account(account_id),
  version       text        NOT NULL CHECK (length(btrim(version)) BETWEEN 1 AND 40),
  accepted_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE UNIQUE INDEX terms_accepted_once_per_version ON safety.terms_acceptance (account_id, version);

CREATE FUNCTION safety.acceptance_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'an acceptance is kept: they agreed to that version on that day';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acceptance_is_kept BEFORE UPDATE OR DELETE ON safety.terms_acceptance
  FOR EACH ROW EXECUTE FUNCTION safety.acceptance_is_kept();

GRANT USAGE ON SCHEMA safety TO app_competition, app_read, app_match, app_trust;
GRANT SELECT, INSERT ON safety.report, safety.terms_acceptance TO app_competition;
GRANT SELECT, INSERT ON safety.block TO app_competition;
GRANT UPDATE (lifted_at) ON safety.block TO app_competition;
GRANT SELECT ON safety.report, safety.decision, safety.block, safety.terms_acceptance TO app_read;
GRANT SELECT, INSERT ON safety.decision TO app_competition;

RESET ROLE;

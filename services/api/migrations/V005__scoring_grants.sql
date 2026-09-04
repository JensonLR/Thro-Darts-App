-- THRØ V005 — scoped offline scoring grants.
--
-- ADR-006 mechanism 1. A grant is what makes scoring authority compatible with offline play
-- rather than contradictory to it: it is issued by the server, held on the device, and valid at
-- scoring time WITHOUT a network.
--
-- Issued at CHECK-IN, not at match-open. Match-open is the moment the design draws, but nothing
-- guarantees a network then, and a player at a dead-signal venue must still be able to score.
-- Check-in is inherently online — it is how the organiser knows who is present — so a player's
-- grants for the whole event are pre-issued there.
--
-- This is a deliberate, bounded exception to ADR-008's rule that permissions are never carried on
-- the client. The exposure is stated rather than hidden: a revoked scorer keeps the ability to
-- RECORD on that device until the grant expires or the device reaches the network. The mitigation
-- is that recording is not the same as being believed.

SET ROLE thro_owner;

CREATE TABLE trust.scoring_grant (
  grant_id     uuid        PRIMARY KEY,
  event_id     uuid        NOT NULL,      -- the competition, not an evidence.event row
  match_id     uuid,                      -- NULL = every match of the event this actor scores
  actor_id     uuid        NOT NULL,
  device_id    uuid        NOT NULL,
  actor_role   text        NOT NULL
               CHECK (actor_role IN ('participant','official','venue_scorer')),
  issued_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- The competition session plus 24 hours. A tournament day runs ten hours or more, so anything
  -- shorter fails the exact case this exists for.
  expires_at   timestamptz NOT NULL,
  revoked_at   timestamptz,
  revoked_by   uuid,
  revoked_reason text,
  CONSTRAINT grant_expires_after_issue CHECK (expires_at > issued_at),
  CONSTRAINT grant_revocation_is_complete
    CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

-- One live grant per (actor, device, event, match scope). Reassigning a scorer revokes the old
-- grant rather than issuing a second, so an actor can never hold two conflicting grants at once.
-- A partial unique index rather than an EXCLUDE constraint, which would need btree_gist for the
-- equality operator on uuid.
CREATE UNIQUE INDEX grant_one_live_per_scope ON trust.scoring_grant
  (actor_id, device_id, event_id, coalesce(match_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE revoked_at IS NULL;

CREATE INDEX grant_lookup ON trust.scoring_grant (actor_id, device_id, event_id);
CREATE INDEX grant_by_match ON trust.scoring_grant (match_id) WHERE match_id IS NOT NULL;

-- Which grant an event was recorded under, and whether that grant was sound at the time.
-- Evidence is NEVER destroyed for an authorization reason, so this annotates rather than gates.
ALTER TABLE evidence.event
  ADD COLUMN grant_id uuid REFERENCES trust.scoring_grant(grant_id),
  ADD COLUMN authority text NOT NULL DEFAULT 'granted'
    CHECK (authority IN ('granted','expired','revoked','ungranted'));

-- Grants are deliberately NOT append-only: revocation and renewal are legitimate state changes,
-- and the append-only default privileges in V001 are scoped to the evidence schema for exactly
-- this reason. But two changes must be impossible, because both would rewrite what authority
-- existed at a moment that has already passed.
CREATE FUNCTION trust.grant_history_is_not_rewritable() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL AND
     (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
      OR NEW.revoked_by IS DISTINCT FROM OLD.revoked_by) THEN
    RAISE EXCEPTION 'a revocation cannot be undone or rewritten (grant %)', OLD.grant_id;
  END IF;
  -- Renewal moves expiry forward; ADR-006 renews opportunistically whenever a device has signal.
  -- Moving it backward would retroactively invalidate evidence already recorded under it.
  IF NEW.expires_at < OLD.expires_at THEN
    RAISE EXCEPTION 'a grant''s expiry cannot be moved backward (grant %)', OLD.grant_id;
  END IF;
  IF NEW.grant_id <> OLD.grant_id OR NEW.issued_at <> OLD.issued_at
     OR NEW.actor_id <> OLD.actor_id OR NEW.device_id <> OLD.device_id THEN
    RAISE EXCEPTION 'a grant''s identity is fixed at issue (grant %)', OLD.grant_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER grant_history_is_not_rewritable
  BEFORE UPDATE ON trust.scoring_grant
  FOR EACH ROW EXECUTE FUNCTION trust.grant_history_is_not_rewritable();

-- The command path reads authority on every visit, so every app role needs SELECT. Only the trust
-- role issues, renews and revokes; nothing anywhere may delete a grant, because what authority
-- existed and when is itself evidence.
GRANT SELECT ON trust.scoring_grant TO app_match, app_trust, app_rating, app_read;
GRANT INSERT, UPDATE ON trust.scoring_grant TO app_trust;
REVOKE DELETE, TRUNCATE ON trust.scoring_grant
  FROM app_match, app_trust, app_rating, app_read;

COMMENT ON COLUMN evidence.event.authority IS
  'Whether the recording actor held a sound grant. Anything but ''granted'' is accepted into the '
  'log and routed to organiser review — never rejected, because rejecting would destroy evidence '
  'that a dispute may need.';

RESET ROLE;

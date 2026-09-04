-- THRØ V003 — read models.
--
-- These are projections, NOT evidence. They are derived, freely rebuildable, and carry a version so
-- a rebuild can run alongside the live one and switch atomically rather than truncating in place.
-- An earlier design put derived visit state inside the append-only schema, where it could be neither
-- corrected nor rebuilt.

-- Run as the owner role so that the default privileges established in V001 govern
-- every table created here. Without this the tables belong to whoever ran the
-- migration, and future-table protection silently does not apply.
SET ROLE thro_owner;

CREATE TABLE read.visit (
  projection_version int    NOT NULL,
  visit_id        uuid      NOT NULL,
  match_id        uuid      NOT NULL,
  leg_ordinal     int       NOT NULL,
  visit_ordinal   int       NOT NULL,
  thrower_id      uuid      NOT NULL,
  visit_total     int       NOT NULL CHECK (visit_total BETWEEN 0 AND 180),
  darts_used      int       CHECK (darts_used BETWEEN 1 AND 3),   -- NULL = unknown, never inferred
  bust            boolean   NOT NULL,
  checkout        boolean   NOT NULL,
  remaining_after int       NOT NULL CHECK (remaining_after >= 0),
  superseded_by   uuid,
  PRIMARY KEY (projection_version, visit_id)
);

CREATE TABLE read.leg (
  projection_version int  NOT NULL,
  leg_id       uuid NOT NULL,
  match_id     uuid NOT NULL,
  leg_ordinal  int  NOT NULL,
  starter_id   uuid NOT NULL,
  winner_id    uuid,
  checkout_value int,
  PRIMARY KEY (projection_version, leg_id)
);

-- Attestation is per LEG, per participant. The organiser's dispute screen narrows to a single leg,
-- which is impossible if confirmation is recorded at match granularity.
CREATE TABLE trust.leg_attestation (
  leg_id        uuid        NOT NULL,
  match_id      uuid        NOT NULL,
  participant_id uuid       NOT NULL,
  attested      boolean     NOT NULL,
  event_id      uuid        NOT NULL REFERENCES evidence.event(event_id),
  attested_at   timestamptz NOT NULL,
  PRIMARY KEY (leg_id, participant_id)
);

-- Eligibility is an ORTHOGONAL axis, not a ninth value of the provenance enum. Overloading the enum
-- would overwrite the pre-quarantine provenance irrecoverably.
CREATE TABLE trust.eligibility (
  match_id      uuid        NOT NULL,
  state         text        NOT NULL CHECK (state IN ('eligible','held','quarantined','excluded')),
  reason_code   text        NOT NULL,
  policy_version text       NOT NULL,
  actor_id      uuid,
  decided_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  event_id      uuid        NOT NULL REFERENCES evidence.event(event_id),
  PRIMARY KEY (match_id, decided_at)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON read.visit, read.leg TO app_read;
GRANT SELECT ON read.visit, read.leg TO app_match, app_trust, app_rating;
GRANT SELECT, INSERT ON trust.leg_attestation, trust.eligibility TO app_trust;
GRANT SELECT ON trust.leg_attestation, trust.eligibility TO app_match, app_rating, app_read;

-- Leave the session as it was found: a migration runner may share one connection
-- across files, and a leaked role would silently change who owns what comes next.
RESET ROLE;

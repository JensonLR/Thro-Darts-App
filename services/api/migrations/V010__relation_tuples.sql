-- THRØ V010 — authorization relation tuples.
--
-- ADR-008: relationship tuples over objects, evaluated by a single in-process decision point, with
-- no role column anywhere. The moment a role column exists someone writes role = 'admin', and the
-- conflict-of-interest rule the whole engine choice turns on becomes unexpressible:
--
--   match#can_correct = event#official BUT NOT (match#participant ∪ participant's team)
--
-- Permissions are resolved per request and never carried in a token, or a removed organiser keeps
-- their power until expiry.

-- Created by the connecting user and handed to the owner, as V001 and V007 do: thro_owner
-- deliberately does not hold CREATE on the database.
CREATE SCHEMA authz AUTHORIZATION thro_owner;

SET ROLE thro_owner;

CREATE TABLE authz.relation (
  subject_id  uuid  NOT NULL,
  relation    text  NOT NULL,
  object_type text  NOT NULL
              CHECK (object_type IN ('organisation','league','season','division','team','event',
                                     'draw','match','board','venue','player')),
  object_id   text  NOT NULL,
  granted_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  granted_by  uuid,
  PRIMARY KEY (subject_id, relation, object_type, object_id)
);

CREATE INDEX relation_by_object ON authz.relation (object_type, object_id, relation);

-- How objects hang off one another, so `event#official` can reach a match.
CREATE TABLE authz.hierarchy (
  child_type   text NOT NULL,
  child_id     text NOT NULL,
  parent_type  text NOT NULL,
  parent_id    text NOT NULL,
  PRIMARY KEY (child_type, child_id, parent_type, parent_id)
);

COMMENT ON TABLE authz.relation IS
  'The whole authorization state. There is no role column here on purpose: a role is a fact about '
  'a person, and every interesting permission in THRO is a fact about a person AND an object.';

GRANT USAGE ON SCHEMA authz TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT SELECT ON authz.relation, authz.hierarchy
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT, DELETE ON authz.relation, authz.hierarchy TO app_competition;

RESET ROLE;

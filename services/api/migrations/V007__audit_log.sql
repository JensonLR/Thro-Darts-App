-- THRØ V007 — the authorization audit log.
--
-- ADR-008: every granting decision on a mutating competitive or personal-data action records the
-- subject, the object, the relation that granted it and the policy version, into an append-only
-- hash-chained log with its own retention and a restricted read path. When a fraud allegation
-- arrives fourteen months later, "who could have done this, and who did?" must be answerable.
--
-- Its own schema, because it has its own retention and its own read path: an audit log readable by
-- everything that writes to it answers the question "who did this" to the person who did it.

-- The schema is created by the connecting user and handed to the owner, as V001 does: thro_owner
-- deliberately does not hold CREATE on the database.
CREATE SCHEMA audit AUTHORIZATION thro_owner;

SET ROLE thro_owner;

CREATE TABLE audit.decision (
  seq            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  decided_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  subject_id     uuid        NOT NULL,
  action         text        NOT NULL,
  object_type    text        NOT NULL,
  object_id      text        NOT NULL,
  allowed        boolean     NOT NULL,
  granted_by     text,                      -- the relation that granted it
  excluded_by    text,                      -- the relation that withdrew it, if one did
  policy_version text        NOT NULL,
  correlation_id uuid,
  prev_hash      bytea       NOT NULL,
  entry_hash     bytea       NOT NULL
);

CREATE INDEX decision_by_subject ON audit.decision (subject_id, decided_at);
CREATE INDEX decision_by_object  ON audit.decision (object_type, object_id, decided_at);

-- The chain is computed HERE, not by the application.
--
-- If the application computed its own hashes then a compromised application could write a
-- self-consistent chain of lies, and the log would verify perfectly while being false. Computing it
-- in the database means the only way to forge an entry is to already hold the owner role — at which
-- point the attacker has the database, and no scheme in the database can help.
--
-- Whatever the caller supplies for prev_hash and entry_hash is discarded.
-- SECURITY DEFINER because the trigger must read the previous entry's hash to extend the chain,
-- while the roles that append deliberately cannot read the log at all. Running as the owner is what
-- lets those two requirements coexist: the writer still cannot SELECT, but the chain can be built.
-- search_path is pinned, as it must be for any SECURITY DEFINER function, so that a caller cannot
-- shadow `audit.decision` or `sha256` with objects of their own.
CREATE FUNCTION audit.chain_entry() RETURNS trigger
  SECURITY DEFINER
  SET search_path = audit, pg_catalog
AS $$
DECLARE
  last_hash bytea;
BEGIN
  -- Appends are serialised. Two concurrent inserts reading the same predecessor would produce two
  -- entries claiming the same position in the chain, and the log would be unverifiable through no
  -- fault of either writer. An audit log's write volume can afford a lock; an ambiguous chain
  -- cannot be repaired after the fact.
  PERFORM pg_advisory_xact_lock(hashtext('audit.decision'));

  SELECT entry_hash INTO last_hash FROM audit.decision ORDER BY seq DESC LIMIT 1;
  NEW.prev_hash := coalesce(last_hash, sha256(''::bytea));

  NEW.entry_hash := sha256(
    NEW.prev_hash ||
    convert_to(
      coalesce(NEW.decided_at::text, '') || '|' ||
      NEW.subject_id::text               || '|' ||
      NEW.action                         || '|' ||
      NEW.object_type                    || '|' ||
      NEW.object_id                      || '|' ||
      NEW.allowed::text                  || '|' ||
      coalesce(NEW.granted_by, '')       || '|' ||
      coalesce(NEW.excluded_by, '')      || '|' ||
      NEW.policy_version,
      'UTF8'
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chain_entry BEFORE INSERT ON audit.decision
  FOR EACH ROW EXECUTE FUNCTION audit.chain_entry();

-- Walks the chain and returns the first entry that does not verify, or nothing if it is intact.
-- Detects both an altered row and a removed one: a deletion breaks the successor's prev_hash.
CREATE FUNCTION audit.first_broken_link()
RETURNS TABLE (broken_seq bigint, why text) AS $$
DECLARE
  r        record;
  expected bytea := sha256(''::bytea);
  recomputed bytea;
BEGIN
  FOR r IN SELECT * FROM audit.decision ORDER BY seq LOOP
    IF r.prev_hash <> expected THEN
      RETURN QUERY SELECT r.seq, 'prev_hash does not match the previous entry'::text;
      RETURN;
    END IF;
    recomputed := sha256(
      r.prev_hash ||
      convert_to(
        coalesce(r.decided_at::text, '') || '|' || r.subject_id::text || '|' || r.action || '|' ||
        r.object_type || '|' || r.object_id || '|' || r.allowed::text || '|' ||
        coalesce(r.granted_by, '') || '|' || coalesce(r.excluded_by, '') || '|' || r.policy_version,
        'UTF8'
      )
    );
    IF recomputed <> r.entry_hash THEN
      RETURN QUERY SELECT r.seq, 'entry contents do not match its hash'::text;
      RETURN;
    END IF;
    expected := r.entry_hash;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Everything that makes a decision may append. Nothing may read it back through an application
-- role, and nothing may change or remove an entry.
GRANT USAGE ON SCHEMA audit TO app_match, app_trust, app_rating, app_read;
GRANT INSERT ON audit.decision TO app_match, app_trust, app_rating, app_read;
GRANT USAGE ON SEQUENCE audit.decision_seq_seq TO app_match, app_trust, app_rating, app_read;
REVOKE SELECT, UPDATE, DELETE, TRUNCATE ON audit.decision
  FROM app_match, app_trust, app_rating, app_read;

COMMENT ON TABLE audit.decision IS
  'Append-only, hash-chained authorization decisions. Write-only for application roles: a log the '
  'acting party can read is a log they can plan around. Reading it is a separate, restricted path.';

RESET ROLE;

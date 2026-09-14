-- The sweep runs, and nobody can aim it (PD-096).
--
-- V044 made `safety.forget_decided` the one way a report leaves this database, and in production it never ran. The
-- server calls it on its own connection, as `thro_app`, which holds the application roles; the function ran with its
-- caller's rights, and no application role may write `safety.decision_tally`. From the moment V044 reached production
-- on 13 September 2026, every start of the server logged *permission denied for table decision_tally*. The tests had
-- passed because each of them called it as the superuser, and a superuser passes every privilege check.
--
-- **So the function runs with its owner's rights** — `SECURITY DEFINER`, owned by `thro_owner`, its search path pinned
-- the way V033 pinned the erasure's — and only `app_competition`, the role the server holds for the safety tables, may
-- call it.
--
-- That alone would have opened two doors V044 had closed only by accident, because a function running as its owner
-- does whatever its caller's arguments ask:
--
--   * **The period was an argument.** Asked for a day, the sweep would forget every decided report older than a day;
--     asked for NULL, every decided report there is. The founder's period is two years (PD-087), and anything shorter
--     or absent is refused. A longer period is still allowed: it forgets less.
--   * **A decision could be inserted with any date.** V040 refuses changing one, but `app_competition` inserts them,
--     and nothing stopped it inserting one dated three years ago — which is exactly what makes a report old enough to
--     forget. A decision now carries the database's time. Only a superuser may date one otherwise, which a superuser
--     could do anyway, and which is how the tests make a decision two years old.
--
-- Everything the running API does still works: it asks for two years, and it inserts decisions without a date.

SET ROLE thro_owner;

CREATE OR REPLACE FUNCTION safety.forget_decided(older_than interval DEFAULT interval '2 years')
RETURNS integer AS $$
DECLARE
  gone integer;
BEGIN
  IF older_than IS NULL OR older_than < interval '2 years' THEN
    RAISE EXCEPTION 'a decided report is forgotten two years after its newest decision, not sooner (asked for %)',
      coalesce(older_than::text, 'no period');
  END IF;

  PERFORM set_config('thro.forgetting', 'on', true);

  CREATE TEMP TABLE forgetting ON COMMIT DROP AS
    SELECT r.report_id, r.subject_kind, r.subject_id
    FROM safety.report r
    WHERE EXISTS (SELECT 1 FROM safety.decision d WHERE d.report_id = r.report_id)
      AND NOT EXISTS (
        SELECT 1 FROM safety.decision d
        WHERE d.report_id = r.report_id AND d.decided_at >= clock_timestamp() - older_than
      );

  INSERT INTO safety.decision_tally AS t (subject_kind, subject_id, outcome, decisions, first_at, last_at)
  SELECT f.subject_kind, f.subject_id, d.outcome, count(*), min(d.decided_at), max(d.decided_at)
  FROM forgetting f
  JOIN safety.decision d ON d.report_id = f.report_id
  GROUP BY f.subject_kind, f.subject_id, d.outcome
  ON CONFLICT (subject_kind, subject_id, outcome) DO UPDATE
    SET decisions = t.decisions + EXCLUDED.decisions,
        first_at  = least(t.first_at, EXCLUDED.first_at),
        last_at   = greatest(t.last_at, EXCLUDED.last_at);

  DELETE FROM safety.decision d USING forgetting f WHERE d.report_id = f.report_id;
  DELETE FROM safety.report r USING forgetting f WHERE r.report_id = f.report_id;
  GET DIAGNOSTICS gone = ROW_COUNT;

  RETURN gone;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

REVOKE ALL ON FUNCTION safety.forget_decided(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION safety.forget_decided(interval) TO app_competition;

COMMENT ON FUNCTION safety.forget_decided IS
  'The only way a report leaves this database. Applies one rule to all of them: decided, and the newest decision two '
  'years old or more. It runs with its owner''s rights, so the rule is its own: no shorter period, none absent, and no '
  'caller but the role the server sweeps as.';

-- A decision carries the database's time. Only a superuser may date one otherwise — a superuser could switch this
-- trigger off anyway — and the tests are the only thing that does.
CREATE OR REPLACE FUNCTION safety.decision_is_dated_now() RETURNS trigger AS $$
BEGIN
  IF current_setting('is_superuser') <> 'on'
     AND NEW.decided_at NOT BETWEEN clock_timestamp() - interval '1 minute' AND clock_timestamp() + interval '1 minute' THEN
    RAISE EXCEPTION 'a decision is dated when it is made, by the database';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp;

CREATE TRIGGER decision_is_dated_now BEFORE INSERT ON safety.decision
  FOR EACH ROW EXECUTE FUNCTION safety.decision_is_dated_now();

RESET ROLE;

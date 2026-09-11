-- THRØ V036 — a new event says so, so a stream need not keep asking (ADR-007's LISTEN/NOTIFY hint).
--
-- The match stream polled the log once a second. That is correct — it reads committed rows in commit
-- order and trusts nothing else — and slower than it has to be: a visit scored at the oche reached a
-- watcher up to a second later, and every open stream asked the database sixty times a minute whether
-- anything had happened. ADR-007 decided the fix: a notification carrying only the match id, delivered
-- on commit, **as a hint to re-read and never as the transport of truth**. The stream still reads the
-- log exactly as before and still polls; it is only woken early.
--
-- On commit, not on insert: Postgres holds a transaction's notifications until it commits and drops
-- them if it rolls back, so a watcher woken by one always finds the rows it was woken for — and an
-- upload of forty rows is one notification, because identical ones within a transaction are folded.
-- A row that `ON CONFLICT DO NOTHING` skipped fires no AFTER INSERT trigger, so a resend wakes nobody.

SET ROLE thro_owner;

CREATE FUNCTION evidence.announce_event() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('thro_match', NEW.match_id::text);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER announce_event AFTER INSERT ON evidence.event
  FOR EACH ROW EXECUTE FUNCTION evidence.announce_event();

RESET ROLE;

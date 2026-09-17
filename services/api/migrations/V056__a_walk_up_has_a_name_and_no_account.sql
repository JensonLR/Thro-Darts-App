-- A walk-up has a name and no account (PD-124).
--
-- A pub knockout is entered by whoever is in the pub. The organiser adds them by name: a `competition.player` with no
-- claim on it — which the domain has always allowed (`source = 'organiser'`) — and a row here holding the one thing
-- THRØ knows about them, the name the organiser typed, for the one event they walked up to.
--
-- THRØ knows nothing else: not their age, not what they agreed to. So the name is the organiser's to read and nobody
-- else's unless the organiser says they are an adult who is happy to be on the draw (`may_be_named`); and because
-- nobody holds an account that could ask for it to be erased, the name is forgotten thirty days after the night ends.
-- The entry, the draw and the results stay: "A guest" won the second tie.

SET ROLE thro_owner;

CREATE TABLE competition.guest (
  player_id    uuid        PRIMARY KEY REFERENCES competition.player(player_id),
  event_id     uuid        NOT NULL REFERENCES competition.event(event_id),
  -- NULL once forgotten. Sixty characters, as a display name is.
  name         text        CHECK (name IS NULL OR length(btrim(name)) BETWEEN 1 AND 60),
  -- The organiser's word that this person is 18 or over and happy to be named on the public draw.
  may_be_named boolean     NOT NULL DEFAULT false,
  added_by     uuid        NOT NULL,
  added_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  forgotten_at timestamptz,
  CONSTRAINT a_forgotten_guest_has_no_name CHECK ((forgotten_at IS NULL) OR (name IS NULL))
);

-- Two Daves on one night need telling apart before the draw, not after it.
CREATE UNIQUE INDEX guest_name_once_per_event ON competition.guest (event_id, lower(btrim(name))) WHERE name IS NOT NULL;

COMMENT ON TABLE competition.guest IS
  'PD-124: a walk-up entrant — a player with no account, named by the organiser for one event. The name is forgotten thirty days after the event ends.';

GRANT SELECT ON competition.guest TO app_read, app_competition, app_trust, app_match;
GRANT INSERT ON competition.guest TO app_competition;

CREATE FUNCTION competition.forget_guests(older_than interval DEFAULT interval '30 days')
RETURNS integer AS $$
DECLARE
  gone integer;
BEGIN
  IF older_than IS NULL OR older_than < interval '30 days' THEN
    RAISE EXCEPTION 'a walk-up''s name is forgotten thirty days after the event ends, not sooner (asked for %)',
      coalesce(older_than::text, 'no period');
  END IF;
  UPDATE competition.guest g
     SET name = NULL, forgotten_at = clock_timestamp()
    FROM competition.event e
   WHERE e.event_id = g.event_id AND g.name IS NOT NULL
     AND e.session_ends_at < clock_timestamp() - older_than;
  GET DIAGNOSTICS gone = ROW_COUNT;
  RETURN gone;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

REVOKE ALL ON FUNCTION competition.forget_guests(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION competition.forget_guests(interval) TO app_competition;

COMMENT ON FUNCTION competition.forget_guests IS
  'The only way a walk-up''s name leaves this database, and the only thing that changes a guest row: thirty days after the event''s session ends, no sooner, by the role the server sweeps as.';

RESET ROLE;

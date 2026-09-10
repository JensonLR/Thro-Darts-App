-- THRØ V027 — where a row came from.
--
-- The founder asked for the local leagues to be in the app with their real teams (PD-033). Those
-- rows are read from the leagues' own public pages and from OpenStreetMap, not typed in by the
-- people who run them, and a row that THRØ did not witness must say so: which source, which page,
-- when it was read, and on what BASIS it was connected to the row it decorates — "stated by the
-- source" is one thing, "inferred from the team's name" is another, "approximate, read from the
-- season label" a third. The app shows the basis; a secretary's own record replaces it.
--
-- One table for every kind of subject rather than a column per table: provenance is a fact ABOUT a
-- row, not a property OF it, and a venue may be confirmed by three sources over its life.
-- Nothing here is a person: the subjects are leagues, seasons, divisions, teams, venues and the
-- links between them. A player has no source record, by construction.

SET ROLE thro_owner;

CREATE TABLE competition.source_record (
  source_record_id uuid        PRIMARY KEY,
  subject_kind     text        NOT NULL CHECK (subject_kind IN
                     ('league','league_season','division','team','venue','team_affiliation','team_venue_tenure')),
  subject_id       uuid        NOT NULL,
  -- Who published it: 'LeagueRepublic', 'OpenStreetMap', or the secretary's own word later.
  source           text        NOT NULL,
  source_url       text,
  -- The source's own identifier for the thing: an OSM element ('way/99782298'), a fixture group.
  external_ref     text,
  retrieved_on     date        NOT NULL,
  -- How the source supports the row. Free text, short, shown to people.
  basis            text        NOT NULL CHECK (length(basis) BETWEEN 3 AND 200),
  recorded_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  recorded_by      uuid,
  -- The same page read on the same day says the same thing once. A re-run of an import is a no-op
  -- here; a later read of the same page is a second record with its own date.
  -- NULLS NOT DISTINCT: a record with no page (a tenure the import inferred) is still one record.
  UNIQUE NULLS NOT DISTINCT (subject_kind, subject_id, source, source_url, retrieved_on)
);

COMMENT ON TABLE competition.source_record IS
  'Provenance for organisational rows imported or confirmed from outside THRØ. Append-only: a '
  'correction is a new record with a later retrieved_on, never an edit.';

CREATE INDEX source_record_by_subject ON competition.source_record (subject_kind, subject_id);

-- Append-only, like every other record of what was seen.
CREATE FUNCTION competition.source_record_is_kept() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'a source record is kept (%): write a new one with a later retrieved_on', OLD.source_record_id;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER source_record_is_kept BEFORE UPDATE OR DELETE ON competition.source_record
  FOR EACH ROW EXECUTE FUNCTION competition.source_record_is_kept();

GRANT SELECT ON competition.source_record
  TO app_match, app_trust, app_rating, app_read, app_competition;
GRANT INSERT ON competition.source_record TO app_competition;

-- The map needs a venue's coordinates; V014 gave the venue columns for them and nothing wrote them.
-- The import does. A venue may also carry a postcode now — a public building's, never a person's —
-- because "TS18 1SU" is what a player types into their satnav.
ALTER TABLE competition.venue ADD COLUMN postcode text
  CHECK (postcode IS NULL OR postcode ~ '^[A-Z]{1,2}[0-9][0-9A-Z]? [0-9][A-Z]{2}$');

-- A pub league is known by its night. "Stockton Thursday" is what people call it, and the night is
-- how a player tells two leagues in the same town apart, so the league row may carry both.
ALTER TABLE competition.league ADD COLUMN short_name text;
ALTER TABLE competition.league ADD COLUMN plays_on text
  CHECK (plays_on IS NULL OR plays_on IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'));

RESET ROLE;

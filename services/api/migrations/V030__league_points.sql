-- THRØ V030 — a league has a place of its own.
--
-- PD-033 placed leagues by their venues: the map plotted pubs, and a league was "near" when one of
-- its pubs was. That works for the three leagues whose pubs were curated by hand and for nobody
-- else — a league THRØ has only heard of, with no venue placed yet, could not be put on the map or
-- measured from a phone at all. The LeagueRepublic darts directory lists several hundred leagues
-- with the position each league gave it, so a league now carries a point: where the league says it
-- is, to be superseded on the map by its venues as they are placed. It is the league's point, not a
-- venue's, and the map draws it as a league and not as a pub. The website is where its own pages
-- are, for the player who wants the fixtures THRØ does not hold.

SET ROLE thro_owner;

ALTER TABLE competition.league ADD COLUMN latitude  numeric(9,6) CHECK (latitude  BETWEEN -90  AND 90);
ALTER TABLE competition.league ADD COLUMN longitude numeric(9,6) CHECK (longitude BETWEEN -180 AND 180);
ALTER TABLE competition.league ADD COLUMN website   text         CHECK (website IS NULL OR website ~ '^https?://');
ALTER TABLE competition.league ADD CONSTRAINT league_point_is_whole CHECK ((latitude IS NULL) = (longitude IS NULL));

RESET ROLE;

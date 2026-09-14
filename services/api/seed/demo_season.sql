-- A season to look at (PD-062, PD-065). Not test data and not real data: a league with enough shape that
-- every branch of the table, the fixtures beside it and the organiser's page has something to draw.
--
-- **Why this is checked in.** A full test run rebuilds the local database, so anything seeded by hand is
-- gone by the next `gradle test` — which is how the league table and the fixtures came to be changed for a
-- fortnight without anybody opening them. Two commands now, from docs/runbooks/CLIENT_IOS.md:
--
--   psql -f services/api/seed/demo_season.sql
--   gradle -p services/api serve
--
-- and then the app with `-ThroAPIBaseURL http://localhost:8080`.
--
-- It covers, on purpose: a played result with a match behind it (evidence), a result declared by an
-- official with no match (PD-055 — counts the same, never evidence), an award with no scoreline (ADR-012),
-- an annulled result with its reason (PD-065), and four fixtures still to come. A seed that only carries
-- the ordinary case is a seed that lets the interesting branches rot.
--
-- Safe to run twice: it makes a fresh league each time rather than trying to be idempotent, because a
-- second league in the list is a better test of the screens than a clean slate is.
SET ROLE thro_owner;
DO $$
DECLARE
  lg uuid := gen_random_uuid(); sn uuid := gen_random_uuid(); dv uuid := gen_random_uuid();
  vn uuid := gen_random_uuid();
  ta uuid := gen_random_uuid(); tb uuid := gen_random_uuid();
  tc uuid := gen_random_uuid(); td uuid := gen_random_uuid();
  off_ uuid := gen_random_uuid();
  fx uuid; m uuid; p1 uuid; p2 uuid;
BEGIN
  INSERT INTO competition.player (player_id, source) VALUES (off_, 'self');
  INSERT INTO competition.league (league_id, name, locality) VALUES (lg, 'Teesside Thursday', 'Stockton');
  INSERT INTO competition.league_season (league_season_id, league_id, label, starts_on, ends_on)
    VALUES (sn, lg, '2026/27', DATE '2026-09-01', DATE '2027-05-31');
  INSERT INTO competition.division (division_id, league_season_id, name, ordinal)
    VALUES (dv, sn, 'Division One', 1);
  INSERT INTO competition.venue (venue_id, name, locality, visibility)
    VALUES (vn, 'The Grange', 'Stockton', 'public');

  INSERT INTO competition.team (team_id, name, locality, visibility) VALUES
    (ta,'Grange A','Stockton','public'), (tb,'Riverside A','Stockton','public'),
    (tc,'Feathers A','Stockton','public'), (td,'Nags Head A','Stockton','public');

  INSERT INTO competition.team_affiliation (affiliation_id, team_id, league_season_id, division_id,
                                            status, valid_from, recorded_by, accepted_at)
    SELECT gen_random_uuid(), t, sn, dv, 'accepted', TIMESTAMPTZ '2026-09-01 00:00:00Z', off_, now()
      FROM unnest(ARRAY[ta,tb,tc,td]) AS t;

  -- Three played, with a match behind each so they count as evidence (V014).
  FOR i IN 1..3 LOOP
    fx := gen_random_uuid(); m := gen_random_uuid();
    p1 := gen_random_uuid(); p2 := gen_random_uuid();
    INSERT INTO competition.player (player_id, source) VALUES (p1,'self'), (p2,'self');
    INSERT INTO evidence.match (match_id, home_id, away_id, starting_score, in_rule, out_rule,
                                legs_mode, legs_target, throw_first)
      VALUES (m, p1, p2, 501, 'straight', 'double', 'first_to', 5, p1);
    INSERT INTO competition.league_fixture (fixture_id, league_season_id, division_id, home_team_id,
                                            away_team_id, venue_id, scheduled_at, match_id)
      VALUES (fx, sn, dv,
              (ARRAY[ta,tc,tb])[i], (ARRAY[tb,td,tc])[i], vn,
              TIMESTAMPTZ '2026-09-03 19:00:00Z' + ((i-1) || ' weeks')::interval, m);
    INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, legs_home, legs_away, decided_by)
      VALUES (gen_random_uuid(), fx, 'played', (ARRAY[5,4,5])[i], (ARRAY[2,5,1])[i], off_);
  END LOOP;

  -- One the league declared from a paper card (PD-055), and one awarded (ADR-012: no scoreline).
  fx := gen_random_uuid();
  INSERT INTO competition.league_fixture (fixture_id, league_season_id, division_id, home_team_id,
                                          away_team_id, venue_id, scheduled_at)
    VALUES (fx, sn, dv, td, ta, vn, TIMESTAMPTZ '2026-09-10 19:00:00Z');
  INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, legs_home, legs_away, decided_by)
    VALUES (gen_random_uuid(), fx, 'declared', 2, 5, off_);

  fx := gen_random_uuid();
  INSERT INTO competition.league_fixture (fixture_id, league_season_id, division_id, home_team_id,
                                          away_team_id, venue_id, scheduled_at)
    VALUES (fx, sn, dv, tc, tb, vn, TIMESTAMPTZ '2026-09-17 19:00:00Z');
  INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, to_team_id, reason, decided_by)
    VALUES (gen_random_uuid(), fx, 'awarded', tc, 'the away side did not raise a team', off_);

  -- One annulled, so the "annulled, to be replayed" line has something to draw (PD-065).
  fx := gen_random_uuid();
  INSERT INTO competition.league_fixture (fixture_id, league_season_id, division_id, home_team_id,
                                          away_team_id, venue_id, scheduled_at)
    VALUES (fx, sn, dv, tb, td, vn, TIMESTAMPTZ '2026-09-20 19:00:00Z');
  INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, legs_home, legs_away, decided_by)
    VALUES (gen_random_uuid(), fx, 'declared', 5, 4, off_);
  INSERT INTO competition.league_fixture_outcome (outcome_id, fixture_id, kind, reason, decided_by,
                                                  supersedes_outcome_id)
    SELECT gen_random_uuid(), fx, 'void', 'played under protest, to be replayed', off_, outcome_id
      FROM competition.league_fixture_outcome WHERE fixture_id = fx AND kind = 'declared';

  -- And four still to play.
  FOR i IN 1..4 LOOP
    INSERT INTO competition.league_fixture (fixture_id, league_season_id, division_id, home_team_id,
                                            away_team_id, venue_id, scheduled_at)
      VALUES (gen_random_uuid(), sn, dv,
              (ARRAY[ta,tb,tc,td])[i], (ARRAY[td,ta,tb,tc])[i], vn,
              TIMESTAMPTZ '2026-09-24 19:00:00Z' + ((i-1) || ' weeks')::interval);
  END LOOP;

  RAISE NOTICE 'season %', sn;
END $$;
SELECT league_season_id FROM competition.league_season ORDER BY league_season_id LIMIT 1;

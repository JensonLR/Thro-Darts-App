-- A name on a live screen is asked for, not read.
--
-- The live board (PD-088, `Live.kt`) selected `evidence.match.home_name` and `away_name`. Those columns were
-- removed by V018, before the board was written — a match holds seats, and names are joined from `identity` when
-- something is drawn (OD-024) — so the query has never parsed: `GET /v1/seasons/{id}/live` answered 500 for every
-- season, and the pub screen's "Playing now" has never shown a game. No test ran the query; the board's tests
-- exercise the consent function it calls and stop there.
--
-- The board reads as `app_read`, which cannot see a column of `identity`, and that is deliberate (V045): a public
-- screen should get the ANSWER to "may I name this person" and nothing else about them. So the name crosses the
-- boundary the same way the answer does — through one SECURITY DEFINER function that returns the display name only
-- where `player_may_be_shown_live` says yes, never the placeholder a new account starts with, and otherwise null.

SET ROLE thro_owner;

CREATE OR REPLACE FUNCTION identity.live_name(p uuid) RETURNS text AS $$
  SELECT a.display_name
    FROM identity.player_claim c
    JOIN identity.account a ON a.account_id = c.account_id
   WHERE c.player_id = p AND c.revoked_at IS NULL AND a.deleted_at IS NULL
     AND identity.player_may_be_shown_live(p)
     AND a.display_name <> 'New player'
   LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION identity.live_name IS
  'The name a public live screen may show for this player: their display name when player_may_be_shown_live '
  'says yes and it is not the placeholder, else null. SECURITY DEFINER so the read role gets the answer and '
  'nothing else of identity.';

GRANT EXECUTE ON FUNCTION identity.live_name(uuid) TO app_read, app_competition;

RESET ROLE;

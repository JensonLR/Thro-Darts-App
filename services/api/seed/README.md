# Seed data

`leagues/teesside.json` — the organisational graph of the local pub leagues (PD-033), written by
`tools/pull_leaguerepublic.py` from the leagues' own public pages on the date the file says, with
venues from OpenStreetMap. Team and venue names only; no person. Imported by
`gradle -p services/api seed`, after `migrate`, as the deploy user; idempotent, and never overwrites
a row a secretary has recorded. Every row it writes carries a `competition.source_record` (V027).

To refresh: `python3 tools/pull_leaguerepublic.py`, review the diff, commit, then `seed` against
each environment. To add a league: add it to `LEAGUES` in the script, its pubs to `VENUES` with
their OpenStreetMap elements, and the team→venue links to `TEAM_VENUES`, each with its basis.

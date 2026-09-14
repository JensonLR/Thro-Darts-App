# Seed data

Two files, both organisational and neither naming a person, both imported by
`gradle -p services/api seed --args=<file>` after `migrate`, as the deploy user; idempotent, and never
overwriting a row a secretary has recorded. Every row written carries a `competition.source_record`
(V027).

`leagues/directory.json` — every darts league the **LeagueRepublic directory** places in the British
Isles (PD-037): name, the position the league gave the directory, its web address. 329 on
2026-09-11. Written by `tools/pull_leaguerepublic_directory.py`. A league arrives as a row with a
point (V030) and no season, team or venue; the app draws it as a league on the map and says its
teams are not on THRØ yet.

`leagues/teesside.json` — the organisational graph of three Teesside leagues in full (PD-033):
seasons, divisions, teams, and venues from OpenStreetMap, written by `tools/pull_leaguerepublic.py`
from the leagues' own public pages. The importer finds a league by its address as well as its
name, so a league already placed by the directory is filled in rather than made twice — import the
directory first, then any league read in full.

To refresh: run the tool, review the diff, commit, then `seed` against each environment. To add a
league in full: add it to `LEAGUES` in `pull_leaguerepublic.py`, its pubs to `VENUES` with their
OpenStreetMap elements, and the team→venue links to `TEAM_VENUES`, each with its basis.

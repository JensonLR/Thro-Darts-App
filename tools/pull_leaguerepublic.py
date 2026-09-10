#!/usr/bin/env python3
"""Pull ORGANISATIONAL data for local darts leagues from their public LeagueRepublic pages.

What it takes: league name, season label, fixture-group (division) names, the TEAM names in each,
and the first and last fixture dates (the season's span). What it never takes: a person. Team pages
list players by name; this script does not open them, and nothing here is keyed on a person.

Venues are NOT on LeagueRepublic. They are curated by hand below from OpenStreetMap (Nominatim),
each with the OSM element it came from, and each marked with how it was matched: a team called
"Blue Bell" is *inferred* to play at The Blue Bell — a strong inference in pub darts, and still an
inference until a secretary confirms it. The import carries that mark through to the database.

Output: services/api/seed/leagues/teesside.json, read by `gradle -p services/api seed`.
Re-run when a season changes; the output is deterministic for the same pages.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import re
import subprocess
import sys
from pathlib import Path

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
TODAY = dt.date.today().isoformat()


def get(url: str) -> str:
    return subprocess.run(["curl", "-sL", "-A", UA, url], capture_output=True, text=True, check=True).stdout


def teams_on(page: str) -> list[str]:
    return sorted({html.unescape(re.sub("<[^>]+>", "", m.group(2)).strip())
                   for m in re.finditer(r'href="(/team/\d+/\d+\.html)"[^>]*>(.*?)</a>', page, re.S)})


def fixture_dates(page: str) -> tuple[str | None, str | None]:
    """The first and last dates on the fixture list. LeagueRepublic writes them as 'Thu 04 Sep 25'
    or '04/09/2025' depending on the theme; both are read."""
    found = []
    for d, m, y in re.findall(r"\b(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* (\d{2,4})\b", page):
        year = int(y) if len(y) == 4 else 2000 + int(y)
        found.append(dt.date(year, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].index(m) + 1, int(d)))
    for d, m, y in re.findall(r"\b(\d{2})/(\d{2})/(\d{4})\b", page):
        try:
            found.append(dt.date(int(y), int(m), int(d)))
        except ValueError:
            pass
    if not found:
        return None, None
    return min(found).isoformat(), max(found).isoformat()


def season_span(label: str) -> tuple[str, str]:
    """'2025-2026' or '2025/26' -> 1 September 2025 to 31 May 2026; '… 2026' -> the calendar year."""
    m = re.search(r"(20\d\d)\s*[-/]\s*(20)?(\d\d)", label)
    if m:
        first = int(m.group(1))
        return f"{first}-09-01", f"{first + 1}-05-31"
    m = re.search(r"(20\d\d)", label)
    if not m:
        sys.exit(f"cannot read a year from the season label {label!r}")
    return f"{m.group(1)}-01-01", f"{m.group(1)}-12-31"


# --- the leagues -------------------------------------------------------------------------------
# Fixture-group ids come from the pages' own links; season labels from the pages' season selector.
LEAGUES = [
    {
        "key": "stockton-thursday",
        "name": "Stockton and District Thursday Night Darts League",
        "short_name": "Stockton Thursday Night Darts",
        "locality": "Stockton-on-Tees",
        "night": "Thursday",
        "platform": "LeagueRepublic",
        "url": "https://stocktonthursdaydarts.leaguerepublic.com/",
        "seasons": [
            {"label": "2023-2024", "groups": [("Thursday Night Darts League", "https://stocktonthursdaydarts.leaguerepublic.com/fg/1_792360183.html")]},
            {"label": "2024-2025", "groups": [("Thursday Night Darts League", "https://stocktonthursdaydarts.leaguerepublic.com/fg/1_214157127.html")]},
            {"label": "2025-2026", "groups": [("Thursday Night Darts League", "https://stocktonthursdaydarts.leaguerepublic.com/fg/1_148988748.html")]},
        ],
        "notes": "A 2026/2027 season exists on the site with no fixture group published yet (season id 362696044). Cups: Knock Out Cup and Plate, Memorial Cup and Plate — not imported; a cup is a tournament, not a division.",
    },
    {
        "key": "stockton-monday-mixed",
        "name": "Stockton & District Monday Night Mixed Darts League",
        "short_name": "Stockton Monday Mixed",
        "locality": "Stockton-on-Tees",
        "night": "Monday",
        "platform": "LeagueRepublic",
        "url": "https://stocktonmondaynightdartsleague.leaguerepublic.com/",
        "seasons": [
            {"label": "2025-2026", "groups": [("2025-2026", "https://stocktonmondaynightdartsleague.leaguerepublic.com/fg/1_62157456.html")]},
        ],
        "notes": "",
    },
    {
        "key": "redcar-district",
        "name": "Redcar and District Darts League",
        "short_name": "Redcar Darts League",
        "locality": "Redcar",
        "night": None,
        "platform": "LeagueRepublic",
        "url": "https://redcardarts.leaguerepublic.com/",
        "seasons": [
            {"label": "Redcar Darts League 2026", "groups": [
                ("Division 1", "https://redcardarts.leaguerepublic.com/fg/1_888678899.html"),
                ("Division 2", "https://redcardarts.leaguerepublic.com/fg/1_326353936.html"),
            ]},
        ],
        "notes": "Seasons back to Summer League 2015 exist on the site; only the current one is imported.",
    },
]

# --- venues, from OpenStreetMap via Nominatim on 2026-09-10 -------------------------------------
# key: (name, locality, lat, lon, osm element, postcode)
VENUES = {
    "hoptimist":      ("The Hoptimist", "Stockton-on-Tees", 54.5617285, -1.3145152, "way/1261858592", "TS18 1ES"),
    "portrack":       ("The Portrack", "Stockton-on-Tees", 54.5704520, -1.3022331, "node/476795542", "TS18 2HS"),
    "myton-house":    ("Myton House", "Ingleby Barwick", 54.5189997, -1.3161344, "way/199260027", "TS17 0WB"),
    "blue-bell":      ("The Blue Bell", "Egglescliffe", 54.5122671, -1.3547167, "way/514308622", "TS16 0JF"),
    "golden-jubilee": ("Golden Jubilee", "Yarm", 54.4968329, -1.3435262, "way/260037663", "TS15 9XN"),
    "thomas-sheraton": ("The Thomas Sheraton", "Stockton-on-Tees", 54.5613574, -1.3131986, "way/99788997", "TS18 1BH"),
    "dolphin":        ("The Dolphin", "Stockton-on-Tees", 54.5685345, -1.3074074, "way/1360172970", "TS18 2DS"),
    "thornaby-fc":    ("Thornaby Football Club", "Thornaby", 54.5526721, -1.2820639, "way/39644537", "TS17 7JU"),
    "sun-inn":        ("The Sun Inn", "Stockton-on-Tees", 54.5655947, -1.3118501, "way/99782298", "TS18 1SU"),
    "pathfinders":    ("Pathfinders", "Maltby", 54.5139265, -1.2795270, "node/368375139", "TS8 0BA"),
    "cleveland-bay":  ("The Cleveland Bay", "Redcar", 54.6091892, -1.0526612, "way/1093078403", "TS10 2DG"),
    "marske-cc":      ("Marske Cricket Club", "Marske-by-the-Sea", 54.5906818, -1.0130172, "way/1284243321", None),
    "new-marske-sc":  ("New Marske Sports Club", "New Marske", 54.5832027, -1.0368425, "node/293975133", "TS11 8EH"),
    "ogradys":        ("O'Gradys", "Redcar", 54.6187037, -1.0710791, "way/911030030", "TS10 1AE"),
    "starting-gate":  ("Starting Gate", "Redcar", 54.5938809, -1.0695323, "node/1686593828", "TS10 4PF"),
    "zetland":        ("The Zetland Hotel", "Marske-by-the-Sea", 54.5883503, -1.0188438, "way/1055901489", "TS11 6JQ"),
    "lobster":        ("The Lobster", "Redcar", 54.6173881, -1.0763763, "node/3426177370", "TS10 1QZ"),
    "the-stockton":   ("The Stockton", "Redcar", 54.6173334, -1.0617090, "way/991632770", "TS10 3DH"),
}

# team -> (venue key, how it was matched). Absent: no venue is recorded, and the team still imports.
TEAM_VENUES = {
    ("stockton-thursday", "Hoptimist A"): ("hoptimist", "inferred from the team's name"),
    ("stockton-thursday", "Hoptimist B"): ("hoptimist", "inferred from the team's name"),
    ("stockton-thursday", "Portrack"): ("portrack", "inferred from the team's name"),
    ("stockton-thursday", "Myton"): ("myton-house", "inferred from the team's name"),
    ("stockton-thursday", "Blue Bell"): ("blue-bell", "inferred from the team's name; the only Blue Bell pub in the borough on OpenStreetMap"),
    ("stockton-thursday", "Golden Jubilee"): ("golden-jubilee", "inferred from the team's name"),
    ("stockton-thursday", "Sheraton A"): ("thomas-sheraton", "inferred from the team's name"),
    ("stockton-thursday", "Sheraton B"): ("thomas-sheraton", "inferred from the team's name"),
    ("stockton-thursday", "Dolphin"): ("dolphin", "inferred from the team's name"),
    ("stockton-thursday", "Thornaby F.C"): ("thornaby-fc", "inferred from the team's name"),
    ("stockton-thursday", "Sun Inn"): ("sun-inn", "inferred from the team's name"),
    ("stockton-monday-mixed", "The Hoptimist"): ("hoptimist", "inferred from the team's name"),
    ("stockton-monday-mixed", "Sheraton A"): ("thomas-sheraton", "inferred from the team's name"),
    ("stockton-monday-mixed", "Sheraton B"): ("thomas-sheraton", "inferred from the team's name"),
    ("stockton-monday-mixed", "Thornaby F.C"): ("thornaby-fc", "inferred from the team's name"),
    ("stockton-monday-mixed", "Maltby CC Pathfinders"): ("pathfinders", "inferred from the team's name"),
    ("redcar-district", "Cleveland Bay"): ("cleveland-bay", "inferred from the team's name"),
    ("redcar-district", "Marske Cricket Club"): ("marske-cc", "inferred from the team's name"),
    ("redcar-district", "New Marske Sports Club"): ("new-marske-sc", "inferred from the team's name"),
    ("redcar-district", "New Marske Reds"): ("new-marske-sc", "inferred from the team's name"),
    ("redcar-district", "O' Gradys"): ("ogradys", "inferred from the team's name"),
    ("redcar-district", "The Starting Gate"): ("starting-gate", "inferred from the team's name"),
    ("redcar-district", "Zetland"): ("zetland", "inferred from the team's name"),
    ("redcar-district", "Lobster"): ("lobster", "inferred from the team's name"),
    ("redcar-district", "The Stockton"): ("the-stockton", "inferred from the team's name"),
}


def main(out: Path) -> None:
    leagues = []
    for league in LEAGUES:
        seasons = []
        for season in league["seasons"]:
            divisions, starts, ends = [], [], []
            for ordinal, (name, url) in enumerate(season["groups"], start=1):
                page = get(url)
                teams = teams_on(page)
                if not teams:
                    sys.exit(f"no teams read from {url}; the page's shape may have changed")
                a, b = fixture_dates(page)
                if a: starts.append(a)
                if b: ends.append(b)
                divisions.append({"name": name, "ordinal": ordinal, "source_url": url, "teams": teams})
            # LeagueRepublic's standings pages carry no dates, and its fixture lists are behind the
            # Gold-plan web services. So the season's span is read from its LABEL and said to be:
            # "2025-2026" is September to May, the pub-league year; "… 2026" is the calendar year.
            # The import records that basis on the season, and a secretary's dates replace it.
            a, b = season_span(season["label"])
            seasons.append({"label": season["label"], "starts_on": a, "ends_on": b,
                            "span_basis": "approximate: read from the season label; the source publishes no season dates",
                            "divisions": divisions})
        leagues.append({k: league[k] for k in ("key", "name", "short_name", "locality", "night", "platform", "url", "notes")} | {"seasons": seasons})
    venues = [{"key": k, "name": v[0], "locality": v[1], "latitude": v[2], "longitude": v[3],
               "osm": v[4], "postcode": v[5], "source": "OpenStreetMap via Nominatim", "retrieved_on": "2026-09-10"}
              for k, v in VENUES.items()]
    team_venues = [{"league": lk, "team": t, "venue": vk, "basis": how} for (lk, t), (vk, how) in TEAM_VENUES.items()]
    doc = {"retrieved_on": TODAY, "method": "public HTML pages read with a browser user agent; LeagueRepublic's JSON web services need a Gold plan",
           "personal_data": "none: team pages, which list players, were not read", "leagues": leagues, "venues": venues, "team_venues": team_venues}
    out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {out}: {sum(len(s['divisions']) for l in leagues for s in l['seasons'])} divisions, "
          f"{sum(len(d['teams']) for l in leagues for s in l['seasons'] for d in s['divisions'])} team-seasons, {len(venues)} venues")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "services/api/seed/leagues/teesside.json"))

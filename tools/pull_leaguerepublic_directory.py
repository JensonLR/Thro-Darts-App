#!/usr/bin/env python3
"""Pull the LeagueRepublic DARTS DIRECTORY: every darts league it lists, with the position each league
gave it and the address of its own pages.

This is how THRØ's leagues stop being three Teesside leagues (PD-033) and become a map a player in
Salisbury or Peterhead can use: the directory places several hundred leagues, and each becomes a
league row with a point of its own (V030) — no seasons, no teams, no venues yet. Teams and venues are
filled in league by league by `pull_leaguerepublic.py`, whose import finds the same league by its
address and adds to it rather than making a second one.

What it takes: a name, a latitude and longitude, a web address. What it never takes: a person — the
directory page names none, and this script opens no league's pages.

Kept: the British Isles (a box round Great Britain, Ireland and the Isle of Man). The directory also
lists leagues abroad; they wait until THRØ is ready to say something true about distances there.

Output: services/api/seed/leagues/directory.json, read by `gradle -p services/api seed <file>`.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

DIRECTORY = "https://www.leaguerepublic.com/darts.html"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
ROW = re.compile(r'\{\s*name:\s*"(.*?)",\s*lat:\s*([-\d.]+),\s*lon:\s*([-\d.]+),\s*url:\s*"(.*?)",\s*sport:\s*"(.*?)"\s*\}')
BRITISH_ISLES = (49.0, 61.0, -11.0, 2.0)  # south, north, west, east


def get(url: str) -> str:
    return subprocess.run(["curl", "-sL", "-A", UA, url], capture_output=True, text=True, check=True).stdout


def tidy(name: str) -> str:
    """A name shouted in capitals is read down to title case; anything else is left as its league
    wrote it. The name as listed is kept on the row's source record either way."""
    name = " ".join(html.unescape(name).split())
    if name != name.upper():
        return name
    small = {"and", "of", "the", "by", "in", "for", "at", "on"}
    tokens = name.split(" ")
    if len(tokens) == 1:
        return name  # a league known by its initials alone: CBFIDL, SKADL
    words = []
    for i, w in enumerate(tokens):
        lower = w.lower()
        if i > 0 and lower in small:
            words.append(lower)
        elif "." in w or len(w) <= 3 or not re.search(r"[AEIOUY]", w):
            words.append(w)  # an initialism: F.T.D.L, IOM, WLDL, FDCDL
        else:
            words.append(w[:1] + lower[1:])
    return " ".join(words)


def main(out: Path) -> None:
    page = get(DIRECTORY)
    rows = ROW.findall(page)
    if len(rows) < 100:
        sys.exit(f"only {len(rows)} leagues read from {DIRECTORY}; the page's shape may have changed")
    south, north, west, east = BRITISH_ISLES
    seen: set[str] = set()
    leagues = []
    for name, lat, lon, url, sport in rows:
        if sport != "Darts":
            continue
        lat, lon = float(lat), float(lon)
        if not (south <= lat <= north and west <= lon <= east):
            continue
        host = urlparse("http://" + url.strip()).netloc.lower()
        if not host or host in seen:
            continue
        seen.add(host)
        listed = " ".join(html.unescape(name).split())
        leagues.append({
            "key": "lr-directory:" + host,
            "name": tidy(listed),
            "name_as_listed": listed,
            "short_name": None,
            "locality": None,
            "night": None,
            "platform": "LeagueRepublic",
            "url": f"https://{host}/",
            "website": f"https://{host}/",
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
            "basis": "listed on LeagueRepublic's darts directory; placed where the directory places it; name as listed: " + listed,
            "seasons": [],
            "notes": "Teams, seasons and venues are not imported from the directory; the league's own pages are the next step.",
        })
    leagues.sort(key=lambda l: l["key"])
    doc = {
        "retrieved_on": dt.date.today().isoformat(),
        "method": "the directory's public page, read with a browser user agent; the league list is the page's own map data",
        "source_url": DIRECTORY,
        "personal_data": "none: the directory names no person and no league's pages were opened",
        "kept": "leagues placed within the British Isles",
        "leagues": leagues,
        "venues": [],
        "team_venues": [],
    }
    out.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {out}: {len(leagues)} leagues of {len(rows)} listed")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "services/api/seed/leagues/directory.json"))

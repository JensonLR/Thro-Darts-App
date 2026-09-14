#!/usr/bin/env python3
"""The deploy pipeline removes only the restore points it made (PD-095, amended 14 September 2026).

**What is protected.** Before each deploy, `tools/deploy_api.py restore-point` branches production in Neon and keeps
the newest three of its own. A restore point is the way back from a migration that went wrong. On 13 September 2026
two were taken by hand from a session, under the name the pipeline gave its own — and the pipeline chose what to
remove by that name alone, so its second run would have removed a branch it never made: production as it stood before
three migrations.

**What this checks.** The real `restore-point` step, run against a stand-in for Neon's API that lists what a project
can hold — more than three of the pipeline's own restore points, two taken by hand, a branch that is not a restore
point, and production itself — and every branch the step then asks Neon to remove. Only the pipeline's own, beyond the
newest three, may be on that list. Nothing here reaches the network.
"""

from __future__ import annotations

import importlib.util
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRODUCTION = "br-production"


def load():
    spec = importlib.util.spec_from_file_location("deploy_api", ROOT / "tools" / "deploy_api.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def branch(branch_id: str, name: str, created: str, parent: str | None = PRODUCTION, **flags) -> dict:
    return {"id": branch_id, "name": name, "parent_id": parent, "created_at": created, **flags}


def main() -> int:
    deploy_api = load()
    ours = deploy_api.PREFIX
    # Dates interleave on purpose: the two taken by hand sit between the pipeline's own, so an ordering by date alone
    # would put them among the three it keeps and among the ones it removes.
    listing = [
        branch(PRODUCTION, "production", "2026-09-10T08:16:42Z", parent=None, primary=True, default=True),
        branch("br-by-hand-1", "restore-point-before-8dce733-20260913-1615", "2026-09-13T16:36:52Z"),
        branch("br-by-hand-2", "restore-point-before-9b0d93b-20260913-1656", "2026-09-13T16:57:27Z"),
        branch("br-somebody", "staging", "2026-09-12T10:00:00Z"),
    ]
    listing += [branch(f"br-ours-{day}", f"{ours}abc{day}de-202609{day}-120000", f"2026-09-{day}T12:00:00Z")
                for day in (10, 11, 12, 14, 15)]
    removed: list[str] = []

    def neon(method, url, token=None, body=None, dry=False):
        if method == "POST":
            listing.append(branch("br-ours-new", body["branch"]["name"], "2026-09-20T12:00:00Z"))
            return 201, {}
        if method == "GET":
            return 200, {"branches": [dict(b) for b in listing]}
        if method == "DELETE":
            removed.append(url.rsplit("/", 1)[-1])
            return 200, {}
        raise AssertionError(f"unexpected {method} {url}")

    deploy_api.call = neon
    os.environ.update({"NEON_API_KEY": "not-a-key", "NEON_PROJECT_ID": "project", "NEON_BRANCH_ID": PRODUCTION,
                       "GITHUB_SHA": "0123456789abcdef"})
    deploy_api.restore_point(dry=False)

    made = next((b["name"] for b in listing if b["id"] == "br-ours-new"), "")
    expected = {"br-ours-10", "br-ours-11", "br-ours-12"}
    problems = []
    if not made.startswith(ours):
        problems.append(f"the restore point it made is named {made!r}, which it would not know as its own")
    strangers = sorted(set(removed) - expected)
    if strangers:
        problems.append(f"it asked Neon to remove branches it did not make, or should have kept: {', '.join(strangers)}")
    missing = sorted(expected - set(removed))
    if missing:
        problems.append(f"it kept more than three of its own: {', '.join(missing)} should have gone")
    if problems:
        print("\ncheck_restore_points: the pipeline's tidy is wrong", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"ok: removed {', '.join(sorted(removed))}; kept the newest three of its own and every branch it did not make")
    return 0


if __name__ == "__main__":
    sys.exit(main())

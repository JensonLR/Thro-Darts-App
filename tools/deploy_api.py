#!/usr/bin/env python3
"""The API's deploy, one step at a time, for the pipeline that runs it by itself (PD-095).

`.github/workflows/deploy-api.yml` calls this between its own steps, in ADR-013's order: a restore point of
production, the migration (Gradle's `migrate`, the same one a person used to run), the deploy of exactly the
commit that was migrated, and proof that the new API came back. Standard library only, so a runner needs
nothing installed.

    python3 tools/deploy_api.py restore-point   a Neon branch of production, named for this commit
    python3 tools/deploy_api.py deploy          Render's deploy hook, for exactly this commit
    python3 tools/deploy_api.py wait            until /healthz answers from this commit, at this checkout's schema

Each step reads its settings from the environment and names the one that is missing. `--dry-run` prints the
requests instead of sending them, with the deploy hook's key left out of anything printed.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEON = "https://console.neon.tech/api/v2"

# The branches this pipeline makes are named with this, and they are the only branches it will ever remove. It is not the
# name a person gives a restore point taken by hand (`restore-point-before-…`): until 14 September 2026 the two were one,
# so the pipeline counted hand-made restore points among its own three and would have removed them in turn.
# tools/check_restore_points.py holds it.
PREFIX = "pipeline-restore-point-before-"
# How many restore points to keep. Neon's history already covers the last six hours; these outlast it, and a
# free project has room for a handful of branches, not an unbounded pile.
KEEP = 3


def need(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"deploy_api: {name} is not set")
    return value


def redact(url: str) -> str:
    """A deploy hook's query string carries its key. A log gets the host and the path, never the key."""
    parts = urllib.parse.urlsplit(url)
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, "…" if parts.query else "", ""))


def call(method: str, url: str, token: str | None = None, body: dict | None = None,
         dry: bool = False) -> tuple[int, dict]:
    """One request. Returns the status and the JSON answer; a network failure is status 0, never an exception."""
    if dry:
        print(f"would {method} {redact(url)}" + (f" {json.dumps(body)}" if body is not None else ""))
        return 200, {}
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, parse(response.read())
    except urllib.error.HTTPError as e:
        return e.code, parse(e.read())
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, {"error": str(e)}


def parse(raw: bytes) -> dict:
    try:
        answer = json.loads(raw.decode() or "{}")
    except (ValueError, UnicodeDecodeError):
        return {"body": raw[:300].decode(errors="replace")}
    return answer if isinstance(answer, dict) else {"body": answer}


def latest_migration() -> int:
    versions = [int(m.group(1)) for p in (ROOT / "services/api/migrations").glob("V*.sql")
                if (m := re.match(r"V0*(\d+)__", p.name))]
    return max(versions)


def api_base() -> str:
    """API_URL when set, else the API service's own Render hostname.

    Not the host the app is built against. That was the default until the domain switch was first run, when the app
    moved to `api.thro.uk` before the name had an address — and the next deploy would have waited on a name that did
    not resolve. The deploy hook deploys the service, and the service answers on its own hostname whatever the public
    name is doing, so that is where a deploy is proved."""
    explicit = os.environ.get("API_URL", "").strip()
    if explicit:
        return explicit.rstrip("/")
    sys.path.insert(0, str(ROOT / "tools"))
    from host import API_SERVICE_HOST
    return f"https://{API_SERVICE_HOST}"


# --- the steps -----------------------------------------------------------------------------------------------


def restore_point(dry: bool) -> None:
    key, project, parent = need("NEON_API_KEY"), need("NEON_PROJECT_ID"), need("NEON_BRANCH_ID")
    sha = os.environ.get("GITHUB_SHA", "local")[:7]
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    name = f"{PREFIX}{sha}-{stamp}"
    # No compute endpoint: a restore point is data to branch from later, not a database anybody connects to.
    status, answer = call("POST", f"{NEON}/projects/{project}/branches", key,
                          {"branch": {"parent_id": parent, "name": name}}, dry)
    if status not in (200, 201):
        sys.exit(f"deploy_api: Neon refused the restore point ({status}): {answer}")
    print(f"restore point {name} taken from {parent}")
    if dry:
        return

    status, listing = call("GET", f"{NEON}/projects/{project}/branches", key)
    if status != 200:
        print(f"note: could not list branches to tidy older restore points ({status}); nothing removed")
        return
    ours = [b for b in listing.get("branches", [])
            if str(b.get("name", "")).startswith(PREFIX) and b.get("parent_id") == parent
            and b.get("id") != parent and not b.get("primary") and not b.get("default") and not b.get("protected")]
    ours.sort(key=lambda b: str(b.get("created_at", "")), reverse=True)
    for old in ours[KEEP:]:
        status, _ = call("DELETE", f"{NEON}/projects/{project}/branches/{old['id']}", key)
        print(f"removed the older restore point {old['name']} ({status})")


def deploy(dry: bool) -> None:
    hook, sha = need("RENDER_DEPLOY_HOOK_URL"), need("GITHUB_SHA")
    separator = "&" if urllib.parse.urlsplit(hook).query else "?"
    # `ref` deploys this commit, not whatever the branch holds by the time Render gets to it: a push that lands
    # between the migration and the deploy must not be deployed against a database it was not migrated for.
    status, answer = call("POST", f"{hook}{separator}ref={urllib.parse.quote(sha)}", dry=dry)
    if status not in (200, 201, 202):
        sys.exit(f"deploy_api: Render did not take the deploy ({status}): {answer}")
    print(f"deploy of {sha[:7]} {'queued behind another' if status == 202 else 'started'}")


def came_back(health: dict, sha: str, schema: str) -> bool:
    """The new API, and not the one it replaces. Both answer at the same schema once the migration has run, so the
    schema alone proves nothing: the commit does, and where a host names no commit, the code's own version."""
    if health.get("database") != "ok" or health.get("schemaVersion") != schema:
        return False
    commit = health.get("commit")
    return commit == sha if commit else health.get("codeVersion") == schema


def wait(dry: bool) -> None:
    sha = need("GITHUB_SHA")
    base = api_base()
    schema = f"V{latest_migration():03d}"
    if dry:
        print(f"would wait for {base}/healthz to answer from {sha[:7]} at {schema}")
        return
    # A free instance builds the image and wakes slowly; twenty-five minutes is generous, and a failure says what
    # the API last answered rather than only that it timed out.
    deadline = time.monotonic() + float(os.environ.get("DEPLOY_WAIT_SECONDS", "1500"))
    last = None
    while True:
        status, health = call("GET", f"{base}/healthz")
        seen = (status, json.dumps(health, sort_keys=True))
        if seen != last:
            print(f"healthz {status}: {seen[1]}")
            last = seen
        if status == 200 and came_back(health, sha, schema):
            print(f"the API from {sha[:7]} answers, at {schema}")
            return
        if time.monotonic() > deadline:
            sys.exit(f"deploy_api: the API from {sha[:7]} did not come back at {schema}; it last answered {status}")
        time.sleep(15)


STEPS = {"restore-point": restore_point, "deploy": deploy, "wait": wait}


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    if len(args) != 1 or args[0] not in STEPS:
        print(__doc__)
        return 2
    STEPS[args[0]]("--dry-run" in sys.argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())

# Runbook — compiling and verifying THRØ on your Mac

One command runs everything the CI runs, and tells you what is missing when something is:

```bash
bash scripts/dev.sh
```

Add `--no-swift` to skip the iOS packages (the slow part) while working on the server.

## Once, on a new machine

```bash
brew install openjdk@21 gradle postgresql@16
brew services start postgresql@16
```

The second line starts PostgreSQL now and on every login. The script sets `JAVA_HOME` itself and
creates the `postgres` role the tests connect as, so nothing else needs configuring. If you also want
`java` and `gradle` to work in a bare terminal, add this to `~/.zshrc`:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
```

## What the script does, in order

| Step | What it proves | If it fails |
|---|---|---|
| toolchain | JDK 21, Gradle, psql present; PostgreSQL answering | it prints the exact `brew` command to run |
| iCloud duplicates | removes `Foo 2.class` twins iCloud Drive leaves in `build/` — they break Gradle's test scan with "wrong name" | nothing to do; it is housekeeping |
| ADR-013 | every migration runs as the owner; destructive statements and evidence rewrites carry their approval | read the FAIL line; it names the file and rule |
| pure Kotlin packages | engine, statistics, competition, authz, trust, rating, organisation, journal | `gradle -p packages/<name> test` shows the failing test |
| API suites | 15 suites against a real database, rebuilt from nothing every run (migration ledger included) | `gradle -p services/api test` and read `services/api/build/reports/tests/test/index.html` |
| schema properties | 92 assertions against the database the API suites left at the current version | the script prints each FAIL with the expected and actual value |
| Swift client | 581 tests across the iOS packages | `swift test --package-path packages/client-ios` |
| repository checks | the README's test counts are the tests that exist | it names the row that drifted |

## Running the pieces yourself

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
export PGHOST=localhost PGUSER=postgres PGDATABASE=postgres

gradle -p services/api test                          # API suites (rebuild the database)
bash services/api/test/schema_properties.sh          # schema properties
gradle -p packages/competition test                  # one pure package
swift test --package-path packages/client-ios        # the iOS packages
THRO_DEV_AUTH=1 gradle -p services/api serve         # the HTTP API on :8080, development authenticator only
```

Two things worth knowing. The schema script applies whatever the migration ledger does not yet
hold and refuses a database it cannot reason about (no ledger, an edited applied migration, a
version ahead of this checkout); the fix is always to let `gradle -p services/api test` rebuild
the database. And a Gradle error of the form `Could not execute test class 'X 2'` is iCloud Drive's
duplicate, not your code: `gradle -p <that project> clean` or rerun the script.

## The iOS app itself

`docs/runbooks/CLIENT_IOS.md` covers opening the Xcode project, the simulator and TestFlight.

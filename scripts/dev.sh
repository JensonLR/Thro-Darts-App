#!/usr/bin/env bash
# THRØ — one command to compile and verify everything on this Mac.
#
#   bash scripts/dev.sh            everything (Kotlin packages, API suites, schema script, Swift client, repo checks)
#   bash scripts/dev.sh --no-swift skip the Swift client (the slow part) while working on the server
#
# What it assumes, and says so when it is not true:
#   * Homebrew has openjdk@21, gradle and postgresql@16 installed (brew install openjdk@21 gradle postgresql@16)
#   * PostgreSQL 16 is running:      brew services start postgresql@16
# It sets JAVA_HOME itself, so nothing in your shell profile is required.
set -uo pipefail
cd "$(dirname "$0")/.."

export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:/opt/homebrew/bin:$PATH"
export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}" PGDATABASE="${PGDATABASE:-postgres}"

red()  { printf '\033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
fail=0
run()  { if "$@"; then return 0; else red "FAILED: $*"; fail=1; return 1; fi; }

step "toolchain"
[ -x "$JAVA_HOME/bin/java" ] || { red "JDK 21 not found at $JAVA_HOME — run: brew install openjdk@21"; exit 1; }
command -v gradle >/dev/null || { red "gradle not found — run: brew install gradle"; exit 1; }
command -v psql   >/dev/null || { red "psql not found — run: brew install postgresql@16"; exit 1; }
java -version 2>&1 | head -1
if ! pg_isready -q -h "$PGHOST" -p "$PGPORT"; then
  red "PostgreSQL is not running on $PGHOST:$PGPORT."
  echo "Start it once with:   brew services start postgresql@16"
  echo "(it then starts on every login; stop it with: brew services stop postgresql@16)"
  exit 1
fi
# Homebrew's cluster has a superuser named after your macOS account; the tests connect as 'postgres'.
if ! psql -X -q -t -A -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "select 1" >/dev/null 2>&1; then
  echo "creating the 'postgres' role the tests connect as (once)"
  createuser -s -h "$PGHOST" -p "$PGPORT" -U "$USER" "$PGUSER" || { red "could not create role $PGUSER"; exit 1; }
fi
echo "PostgreSQL ready on $PGHOST:$PGPORT as $PGUSER"

# This folder is inside iCloud Drive, which leaves "Foo 2.class" twins in build directories and
# breaks Gradle's test scan ("wrong name"). Build outputs are disposable, so the twins go first.
step "clearing iCloud duplicates from build directories"
find . -path '*/build/*' -name '* [0-9].*' -print -delete 2>/dev/null | wc -l | xargs printf '%s removed\n'

step "ADR-013 migration discipline"
run python3 tools/check_migrations.py

step "pure Kotlin packages"
for p in engine statistics competition authz trust rating organisation journal; do
  printf '%s ' "$p"; run gradle -p "packages/$p" test -q && echo ok
done

step "API suites against a real database (rebuilds it from nothing)"
run gradle -p services/api test -q

step "schema properties (on the database the last suite left at the current version)"
gradle -p services/api test -q --tests 'thro.api.DiscoveryTest' --rerun >/dev/null 2>&1
run bash -c 'bash services/api/test/schema_properties.sh | tail -2'

if [ "${1:-}" != "--no-swift" ]; then
  step "Swift client (iOS packages; a few minutes)"
  run bash -c 'swift test --package-path packages/client-ios 2>&1 | tail -3'
fi

step "repository checks"
run python3 tools/check_test_counts.py

echo
if [ $fail -eq 0 ]; then printf '\033[32mEverything green.\033[0m\n'; else red "Something failed — see the FAILED lines above."; fi
exit $fail

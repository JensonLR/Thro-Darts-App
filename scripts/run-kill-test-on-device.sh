#!/usr/bin/env bash
#
# Kill the process mid-visit on a physical iPhone and check that nothing acknowledged was lost.
#
# ADR-006: the durability setting is "raised and validated with real kill tests and power-cut tests
# on device — not assumed". ADR-011 requires this on every release candidate and says a release
# candidate without it is not a release candidate. This is the automatable half; the power-cut half
# is in docs/runbooks/DURABILITY_KILL_TEST.md and needs hands.
#
# What it proves: the journal survives process death with no corruption, no gaps, and no
# acknowledged visit missing.
#
# What it does NOT prove: power-loss durability. Process death leaves the kernel and the drive
# running, so anything SQLite handed to the kernel still lands — this passes for synchronous=NORMAL
# too. Only cutting power tests the barrier that `fullfsync` exists for. Do not read a green run
# here as evidence about that.
#
# Usage:
#   scripts/run-kill-test-on-device.sh [configurationIndex] [killAfterMs]
#
#   configurationIndex  0..3 into Durability.candidates; default 2, the real Apple barrier.
#   killAfterMs         how long to write before the process kills itself; default 1500.
#
# Environment:
#   PROBE_PROJECT    path to ThroProbe.xcodeproj (default: ~/Thro Darts App/ThroProbe/…)
#   PROBE_BUNDLE_ID  bundle identifier to sign and launch; applied at build time, like
#                    run-probe-on-device.sh, so the app that is built is the app that is launched.
#
# Outcomes, from the one pass rule in KillProbe.verdict:
#   PASS  exit 0   nothing acknowledged was lost
#   FAIL  exit 2   an acknowledged visit is missing, a gap, or a corrupt journal — the failure
#                  ADR-006 has no repair path for. Record the report verbatim before touching anything.
#   VOID  exit 3   the run measured nothing: the writer was not writing when the kill landed, or
#                  the journal was absent or empty. Not a pass. Not a failure. Fix the run.

set -euo pipefail

CONFIG_INDEX="${1:-2}"
KILL_AFTER_MS="${2:-1500}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO/packages/durability-probe"
PROJECT="${PROBE_PROJECT:-$HOME/Thro Darts App/ThroProbe/ThroProbe.xcodeproj}"
SCHEME="ThroProbe"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/ThroProbe-cli"
WORK="${KILLTEST_WORK:-$(mktemp -d -t throkill)}"
mkdir -p "$WORK"

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
void() { printf '\nVOID — %s\n\nNothing has been recorded. This is not a pass and not a failure; the run tests nothing.\nLogs kept in: %s\n' "$1" "$WORK" >&2; exit 3; }

[ -d "$PROJECT" ] || die "no Xcode project at: $PROJECT
Set PROBE_PROJECT to its location."

# devicectl --console blocks until the app exits. The write phase SIGKILLs itself, so it terminates
# on its own — but macOS has no coreutils `timeout`, and a hung phase must not hang the release
# checklist. This is the watchdog.
run_phase() {
  local log="$1"; shift
  local limit="$1"; shift
  xcrun devicectl device process launch --device "$DEVICE_ID" --console "$BUNDLE_ID" "$@" > "$log" 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$waited" -ge "$limit" ] && { kill "$pid" 2>/dev/null || true; break; }
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null || true
  # devicectl relays device stdout with CRLF endings. Strip the CR at the boundary: a trailing \r
  # survives command substitution and turns "1840" into an argument nothing can parse.
  sed -i '' $'s/\r$//' "$log"
}

echo "==> Looking for a connected device"
DEVICE_JSON="$WORK/devices.json"
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1 || true
DEVICE_LINE="$(python3 - "$DEVICE_JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") != "iOS":
        continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        continue
    print("%s\t%s\t%s\t%s" % (d.get("identifier",""), hw.get("productType","?"),
                              props.get("osVersionNumber","?"), props.get("osBuildUpdate","?")))
    break
PY
)"
[ -n "$DEVICE_LINE" ] || die "no iPhone connected. See scripts/run-probe-on-device.sh for the setup steps."

DEVICE_ID="$(printf '%s' "$DEVICE_LINE" | cut -f1)"
ATTRIBUTION="$(printf '%s' "$DEVICE_LINE" | cut -f2), iOS $(printf '%s' "$DEVICE_LINE" | cut -f3) (build $(printf '%s' "$DEVICE_LINE" | cut -f4))"
echo "    $ATTRIBUTION"

echo "==> Building the adjudicator"
# The journal is pulled off the device and adjudicated here, through KillProbe.verdict, rather than
# inspected in-app. Two reasons, both learned the hard way: an on-device integrity_check over a
# large journal ran past the iOS launch watchdog and never reported; and every place that
# re-implemented the pass rule in shell got it wrong in the same way, checking the tail and not the
# holes. There is one rule, and this is it.
ADJUDICATE="$(swift build --package-path "$PKG" --product adjudicate --show-bin-path 2>"$WORK/adjudicate-build.log")/adjudicate"
swift build --package-path "$PKG" --product adjudicate >> "$WORK/adjudicate-build.log" 2>&1 \
  || { tail -20 "$WORK/adjudicate-build.log"; die "could not build the adjudicator"; }
[ -x "$ADJUDICATE" ] || die "adjudicator not found at $ADJUDICATE"

echo "==> Building and installing the app"
BUILD_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates -derivedDataPath "$DERIVED"
)
[ -n "${PROBE_BUNDLE_ID:-}" ] && BUILD_ARGS+=(PRODUCT_BUNDLE_IDENTIFIER="$PROBE_BUNDLE_ID")
xcodebuild "${BUILD_ARGS[@]}" build > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; die "build failed"; }

APP="$(find "$DERIVED/Build/Products/Debug-iphoneos" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || die "build reported success but produced no .app"
# From the bundle that was actually built, so build and launch cannot disagree about the identifier.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" > "$WORK/install.log" 2>&1 \
  || { tail -20 "$WORK/install.log"; die "install failed"; }

echo "==> Phase 1: writing visits under configuration $CONFIG_INDEX, killing the process after ${KILL_AFTER_MS}ms"
# --max-visits is set far beyond anything a kill delay can reach. The cap exists to bound journal
# size; reaching it means the writer was idle when the kill landed, and the run is void below.
run_phase "$WORK/write.log" $(( KILL_AFTER_MS / 1000 + 90 )) \
  --kill-test-write "$CONFIG_INDEX" "$KILL_AFTER_MS" --fresh --max-visits 5000000

if grep -q "KILLTEST-ARGS-ERROR" "$WORK/write.log"; then
  die "the app rejected its launch arguments:
$(grep 'KILLTEST-ARGS-ERROR' "$WORK/write.log")"
fi
grep -q "App terminated due to signal 9" "$WORK/write.log" \
  || die "the process did not die by SIGKILL — the kill did not happen, so this run tests nothing.
$(tail -10 "$WORK/write.log")"
# Signal 9 alone is not proof the probe's kill fired: the iOS launch watchdog also sends SIGKILL,
# and once did so at eighteen seconds on every run while looking exactly like this. The kill thread
# prints and flushes this marker immediately before it pulls the trigger.
grep -q "KILLTEST-KILLING-NOW" "$WORK/write.log" \
  || void "the process died by signal 9 but KILLTEST-KILLING-NOW is absent — something other than the probe's own kill (the launch watchdog, most likely) ended it, and that is not the event under test"

# Was the writer still writing when the kill landed? These two markers are printed for exactly
# this question. A writer that had stopped — cap reached, or a failed write and a clean close —
# left the kernel a minute to flush, and a kill after that puts nothing at risk.
grep -q "KILLTEST-WRITE-ERROR" "$WORK/write.log" \
  && void "a write failed before the kill: $(grep 'KILLTEST-WRITE-ERROR' "$WORK/write.log" | head -1)"
grep -q "KILLTEST-CAP-REACHED" "$WORK/write.log" \
  && void "the writer hit its visit cap before the kill landed, so the journal had been idle and flushed"

# `grep` exits 1 on no match, and under pipefail that aborts the assignment before the message
# below can be reached. The `|| true` is what makes "no acknowledgements" a sentence and not a
# silent exit 1.
LAST_ACK="$({ grep 'KILLTEST-ACK' "$WORK/write.log" || true; } | tail -1 | awk '{print $2}')"
[ -n "$LAST_ACK" ] || void "no acknowledgements were recorded; nothing to verify"
CONFIG_LABEL="$(grep 'KILLTEST-WRITE-BEGIN' "$WORK/write.log" | head -1 | cut -d' ' -f2-)"
echo "    configuration: $CONFIG_LABEL"
echo "    $(grep 'KILLTEST-CONFIG' "$WORK/write.log" | head -1)"
echo "    acknowledged $LAST_ACK visits, then died by signal 9"

echo "==> Phase 2: pulling the journal off the device"
# All of it. In WAL mode the most recent commits live in the -wal sidecar and nowhere else;
# adjudicating the main file alone once reported 269,811 rows for a journal that held 270,779 and
# invented a "967 acknowledged visits lost" that never happened. For the rollback-journal
# configuration a hot -journal file is what lets SQLite undo a torn transaction on open.
PULL="$WORK/pulled"
rm -rf "$PULL"; mkdir -p "$PULL"
for suffix in "" "-wal" "-shm" "-journal"; do
  xcrun devicectl device copy from --device "$DEVICE_ID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/thro-kill-test.sqlite$suffix" \
    --destination "$PULL/journal.sqlite$suffix" > "$WORK/pull$suffix.log" 2>&1 || true
done
[ -f "$PULL/journal.sqlite" ] || die "could not pull the journal from the device:
$(tail -5 "$WORK/pull.log")"
if [ "$CONFIG_INDEX" != "3" ] && [ ! -f "$PULL/journal.sqlite-wal" ]; then
  die "the -wal sidecar could not be pulled. This configuration writes in WAL mode and a process that
died by SIGKILL never checkpointed, so the most recent commits are in that file. Adjudicating without
it would report them as lost. Not adjudicated.
$(tail -5 "$WORK/pull-wal.log")"
fi
ls -l "$PULL" | sed 's/^/    /'

echo "==> Adjudicating"
set +e
"$ADJUDICATE" "$PULL/journal.sqlite" "$LAST_ACK" > "$WORK/adjudicate.log" 2>&1
CODE=$?
set -e
cat "$WORK/adjudicate.log"

case "$CODE" in
  0)
    cat <<EOF
PASS on $ATTRIBUTION — $LAST_ACK acknowledged visits under "$CONFIG_LABEL", none lost to process death.

This does not close the durability question. Process death leaves the kernel and the drive running;
only the power-cut test exercises the barrier that fullfsync exists for. See
docs/runbooks/DURABILITY_KILL_TEST.md.
Logs kept in: $WORK
EOF
    ;;
  2)
    die "FAIL — an acknowledged visit did not survive process death. This is the failure ADR-006 has
no repair path for. Record the report above verbatim before changing anything.
Logs kept in: $WORK"
    ;;
  3)
    void "the adjudicator found nothing to adjudicate — see the report above"
    ;;
  *)
    die "the adjudicator could not run (exit $CODE). Logs kept in: $WORK"
    ;;
esac

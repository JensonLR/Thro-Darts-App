#!/usr/bin/env bash
#
# Force-restart the phone mid-visit and check what survived.
#
# This is the test ADR-006 asks for that the kill test cannot stand in for. SIGKILL ends the
# process; the kernel, its page cache and the drive all keep running, so everything SQLite handed to
# the kernel still lands and even synchronous=NORMAL passes. A force-restart takes the whole OS down
# abruptly: the page cache goes with it, and only what actually reached the drive survives.
#
# Be precise about what this is. It is NOT a true power cut. An iPhone's battery cannot be pulled,
# and a force-restart leaves the drive powered, so a write sitting in the drive's own cache may
# still be written out. That last cache is exactly what `fullfsync` exists to flush, so this test
# narrows the question without closing it. Closing it needs hardware whose power can actually be
# interrupted — a removable-battery Android or a dev board. Recorded honestly, this is the strongest
# evidence obtainable from an iPhone, and it is not the same as proof.
#
# On iPhone15,3 the control under `relaxed` lost nothing, which means the restart does not reach the
# layer this question is about on that hardware — see docs/runbooks/DURABILITY_KILL_TEST.md before
# spending more restarts on an iPhone.
#
# Usage:
#   scripts/run-power-cut-test.sh [configurationIndex]
#
#   0 = relaxed (expected to lose data if the interruption reaches the page cache — the control)
#   2 = synchronous=FULL + fullfsync (expected to survive)
#
# Run both. A pass on 2 means little without a fail on 0: if the weakest setting also survives, the
# interruption is not reaching the layer being tested and neither result is evidence of anything.
#
# Environment:
#   PROBE_PROJECT    path to ThroProbe.xcodeproj (default: ~/Thro Darts App/ThroProbe/…)
#   PROBE_BUNDLE_ID  bundle identifier to sign and launch; applied at build time.
#   THROTTLE_US      microseconds between visits, default 8000. Writing continuously is what makes
#                    the restart mean anything — the kernel flushes dirty pages within tens of
#                    seconds, so a writer that has stopped leaves nothing at risk. Zero is refused.
#   MAX_VISITS       journal size cap, default 100000: at the default throttle that is over 13
#                    minutes of writing, past the 10-minute wait below. A run that reaches the cap
#                    before the restart is void.
#
# Outcomes, from the one pass rule in KillProbe.verdict:
#   PASS  exit 0   nothing acknowledged was lost
#   FAIL  exit 2   an acknowledged visit is missing, a gap, or a corrupt journal
#   VOID  exit 3   the run measured nothing — the writer was not writing when the device went down,
#                  no restart was detected, or the journal was absent or empty

set -euo pipefail

CONFIG_INDEX="${1:-2}"
THROTTLE_US="${THROTTLE_US:-8000}"
MAX_VISITS="${MAX_VISITS:-100000}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO/packages/durability-probe"
PROJECT="${PROBE_PROJECT:-$HOME/Thro Darts App/ThroProbe/ThroProbe.xcodeproj}"
SCHEME="ThroProbe"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/ThroProbe-cli"
WORK="${POWERCUT_WORK:-$(mktemp -d -t thropowercut)}"
mkdir -p "$WORK"

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
void() { printf '\nVOID — %s\n\nNothing has been recorded. This is not a pass and not a failure; the run tests nothing.\nLogs kept in: %s\n' "$1" "$WORK" >&2; exit 3; }

[ -d "$PROJECT" ] || die "no Xcode project at: $PROJECT
Set PROBE_PROJECT to its location."
[ "$THROTTLE_US" -gt 0 ] 2>/dev/null || die "THROTTLE_US must be a positive integer; an unthrottled writer hits its cap in seconds and the restart lands on an idle, flushed journal"

device_line() {
  local json="$WORK/devices.json"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  python3 - "$json" <<'PY'
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
}

LINE="$(device_line)"
[ -n "$LINE" ] || die "no iPhone connected."
DEVICE_ID="$(printf '%s' "$LINE" | cut -f1)"
ATTRIBUTION="$(printf '%s' "$LINE" | cut -f2), iOS $(printf '%s' "$LINE" | cut -f3) (build $(printf '%s' "$LINE" | cut -f4))"
echo "==> $ATTRIBUTION"

echo "==> Building the adjudicator"
# One pass rule, in KillProbe.verdict, applied to the pulled journal on this Mac. The first version
# of this script computed `LOST=$(( LAST_ACK - MAXSEQ ))` in shell — the tail comparison only, no
# row count, no hole scan, no integrity gate — which is the same false pass KillProbe.verdict was
# written to remove, one layer up.
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
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" > "$WORK/install.log" 2>&1 \
  || { tail -20 "$WORK/install.log"; die "install failed"; }

# The kill thread is set far enough out that it never fires; the restart is the terminating event.
# Acknowledgements stream over USB into a log ON THE MAC, which is what makes this recoverable —
# the phone is about to lose everything in memory, and the Mac's copy of what was acknowledged is
# the only ground truth that survives the restart.
WRITE_LOG="$WORK/write-config${CONFIG_INDEX}.log"
rm -f "$WRITE_LOG"
nohup xcrun devicectl device process launch --device "$DEVICE_ID" --console "$BUNDLE_ID" \
  --kill-test-write "$CONFIG_INDEX" 3600000 --fresh --max-visits "$MAX_VISITS" --throttle-us "$THROTTLE_US" \
  > "$WRITE_LOG" 2>&1 &
WRITER_PID=$!

echo "==> Waiting for writes to start"
for _ in $(seq 1 40); do
  grep -q "KILLTEST-ACK" "$WRITE_LOG" 2>/dev/null && break
  sleep 1
done
if grep -q "KILLTEST-ARGS-ERROR" "$WRITE_LOG" 2>/dev/null; then
  kill "$WRITER_PID" 2>/dev/null || true
  die "the app rejected its launch arguments: $(sed $'s/\r$//' "$WRITE_LOG" | grep 'KILLTEST-ARGS-ERROR')"
fi
grep -q "KILLTEST-ACK" "$WRITE_LOG" 2>/dev/null \
  || { kill "$WRITER_PID" 2>/dev/null || true; tail -15 "$WRITE_LOG"; die "the writer never acknowledged anything"; }

CONFIG_LABEL="$(sed $'s/\r$//' "$WRITE_LOG" | grep 'KILLTEST-WRITE-BEGIN' | head -1 | cut -d' ' -f2-)"
CONFIG_LINE="$(sed $'s/\r$//' "$WRITE_LOG" | grep 'KILLTEST-CONFIG' | head -1)"
case "$CONFIG_LINE" in
  *"throttleUs=0"*) kill "$WRITER_PID" 2>/dev/null || true; die "the app is running unthrottled ($CONFIG_LINE); the restart would land on an idle journal" ;;
esac
cat <<EOF

    Writing now under: $CONFIG_LABEL
    $CONFIG_LINE

    ┌──────────────────────────────────────────────────────────────────────┐
    │  FORCE-RESTART THE IPHONE NOW, while it is still writing:            │
    │                                                                      │
    │    1. Press and release Volume Up                                    │
    │    2. Press and release Volume Down                                  │
    │    3. Press and HOLD the Side button until the screen goes black     │
    │       and the Apple logo appears. Keep holding through the black.    │
    │                                                                      │
    │  Do not unplug the cable. Unlock the phone once it reboots.          │
    │  Decline any iOS update: a new build voids the run.                  │
    └──────────────────────────────────────────────────────────────────────┘

EOF

echo "==> Waiting for the device to drop off the bus"
DROPPED=0
for _ in $(seq 1 600); do
  if [ -z "$(device_line)" ]; then DROPPED=1; break; fi
  # If the writer stops for any reason while we wait, the restart will land on an idle journal.
  if grep -qE "KILLTEST-CAP-REACHED|KILLTEST-WRITE-ERROR" "$WRITE_LOG" 2>/dev/null; then break; fi
  sleep 1
done
kill "$WRITER_PID" 2>/dev/null || true
wait "$WRITER_PID" 2>/dev/null || true
sed -i '' $'s/\r$//' "$WRITE_LOG"

grep -q "KILLTEST-WRITE-ERROR" "$WRITE_LOG" \
  && void "a write failed while waiting for the restart: $(grep 'KILLTEST-WRITE-ERROR' "$WRITE_LOG" | head -1)"
grep -q "KILLTEST-CAP-REACHED" "$WRITE_LOG" \
  && void "the writer reached its visit cap ($MAX_VISITS) before the device went down; the journal was idle and flushed. Raise MAX_VISITS or restart sooner."
[ "$DROPPED" = "1" ] || void "the device never disconnected — no restart was detected"

echo "    device went away"
echo "==> Waiting for it to come back (unlock it when the passcode prompt appears)"
BACK=0
for _ in $(seq 1 300); do
  if [ -n "$(device_line)" ]; then BACK=1; break; fi
  sleep 2
done
[ "$BACK" = "1" ] || die "the device did not come back within 10 minutes."
echo "    device is back"

# The build the run was attributed to must be the build it came back on.
AFTER="$(device_line)"
AFTER_ATTRIBUTION="$(printf '%s' "$AFTER" | cut -f2), iOS $(printf '%s' "$AFTER" | cut -f3) (build $(printf '%s' "$AFTER" | cut -f4))"
[ "$AFTER_ATTRIBUTION" = "$ATTRIBUTION" ] \
  || void "the device came back as '$AFTER_ATTRIBUTION' but the run started on '$ATTRIBUTION' — an OS update happened mid-test"

LAST_ACK="$(grep 'KILLTEST-ACK' "$WRITE_LOG" | tail -1 | awk '{print $2}')"
[ -n "$LAST_ACK" ] || void "no acknowledgements recorded"
echo "==> Last acknowledgement that reached the Mac before the restart: $LAST_ACK"

echo "==> Pulling the journal off the device"
# All of it. In WAL mode recent commits live in the -wal sidecar, not in the main database;
# inspecting the .sqlite alone reported 269,811 rows for a run that actually held 270,779 and
# produced a confident, entirely false "967 acknowledged visits lost". For the rollback-journal
# configuration a hot -journal is what lets SQLite undo a torn transaction on open.
PULL="$WORK/pulled-config${CONFIG_INDEX}"
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
  die "the -wal sidecar could not be pulled. This configuration writes in WAL mode and a restarted
device never checkpointed, so the most recent commits are in that file. Adjudicating without it
would report them as lost. Not adjudicated.
$(tail -5 "$WORK/pull-wal.log")"
fi
ls -l "$PULL" | sed 's/^/    /'

echo "==> Adjudicating"
set +e
"$ADJUDICATE" "$PULL/journal.sqlite" "$LAST_ACK" > "$WORK/adjudicate.log" 2>&1
CODE=$?
set -e
cat "$WORK/adjudicate.log"

cat <<EOF
------------------------------------------------------------------------
device          $ATTRIBUTION
configuration   $CONFIG_LABEL
acknowledged    $LAST_ACK
interruption    force-restart (Volume Up, Volume Down, hold Side) — not a power cut
EOF
case "$CODE" in
  0) echo "result          PASS — nothing acknowledged was lost" ;;
  2) echo "result          FAIL — see the report above; record it verbatim" ;;
  3) echo "result          VOID — nothing to adjudicate; see the report above" ;;
  *) echo "result          adjudicator error (exit $CODE)" ;;
esac
cat <<EOF
------------------------------------------------------------------------

Logs kept in: $WORK

Remember what this is and is not. A force-restart leaves the drive powered, so it does not test the
drive's own write cache — the last thing fullfsync flushes. Record it as a force-restart result,
never as a power-cut result. And a pass under configuration 2 says nothing unless configuration 0
fails under the same interruption.
EOF
exit "$CODE"

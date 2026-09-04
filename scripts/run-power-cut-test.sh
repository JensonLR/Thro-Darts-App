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
# Usage:
#   scripts/run-power-cut-test.sh [configurationIndex]
#
#   0 = relaxed (expected to lose data here — that is the control)
#   2 = synchronous=FULL + fullfsync (expected to survive)
#
# Run both. A pass on 2 means little without a fail on 0: if the weakest setting also survives, the
# restart is not reaching the layer being tested and neither result is evidence of anything.

set -euo pipefail

CONFIG_INDEX="${1:-2}"
PROJECT="${PROBE_PROJECT:-$HOME/Thro Darts App/ThroProbe/ThroProbe.xcodeproj}"
SCHEME="ThroProbe"
BUNDLE_ID="${PROBE_BUNDLE_ID:-com.thro.ThroProbe}"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/ThroProbe-cli"
WORK="${POWERCUT_WORK:-$(mktemp -d -t thropowercut)}"
mkdir -p "$WORK"

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

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

echo "==> Building and installing"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates -derivedDataPath "$DERIVED" \
  build > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; die "build failed"; }
xcrun devicectl device install app --device "$DEVICE_ID" \
  "$DERIVED/Build/Products/Debug-iphoneos/ThroProbe.app" > "$WORK/install.log" 2>&1 \
  || { tail -20 "$WORK/install.log"; die "install failed"; }

# The kill thread is set far enough out that it never fires; the restart is the terminating event.
# Acknowledgements stream over USB into a log ON THE MAC, which is what makes this recoverable —
# the phone is about to lose everything in memory, and the Mac's copy of what was acknowledged is
# the only ground truth that survives the restart.
WRITE_LOG="$WORK/write-config${CONFIG_INDEX}.log"
rm -f "$WRITE_LOG"
nohup xcrun devicectl device process launch --device "$DEVICE_ID" --console "$BUNDLE_ID" \
  --kill-test-write "$CONFIG_INDEX" 3600000 --fresh --max-visits "${MAX_VISITS:-40000}" --throttle-us "${THROTTLE_US:-8000}" > "$WRITE_LOG" 2>&1 &
WRITER_PID=$!

echo "==> Waiting for writes to start"
for _ in $(seq 1 40); do
  grep -q "KILLTEST-ACK" "$WRITE_LOG" 2>/dev/null && break
  sleep 1
done
grep -q "KILLTEST-ACK" "$WRITE_LOG" 2>/dev/null \
  || { tail -15 "$WRITE_LOG"; die "the writer never acknowledged anything"; }

CONFIG_LABEL="$(sed $'s/\r$//' "$WRITE_LOG" | grep 'KILLTEST-WRITE-BEGIN' | head -1 | cut -d' ' -f2-)"
cat <<EOF

    Writing now under: $CONFIG_LABEL

    ┌──────────────────────────────────────────────────────────────────────┐
    │  FORCE-RESTART THE IPHONE NOW, while it is still writing:            │
    │                                                                      │
    │    1. Press and release Volume Up                                    │
    │    2. Press and release Volume Down                                  │
    │    3. Press and HOLD the Side button until the screen goes black     │
    │       and the Apple logo appears. Keep holding through the black.    │
    │                                                                      │
    │  Do not unplug the cable. Unlock the phone once it reboots.          │
    └──────────────────────────────────────────────────────────────────────┘

EOF

echo "==> Waiting for the device to drop off the bus"
DROPPED=0
for _ in $(seq 1 600); do
  if [ -z "$(device_line)" ]; then DROPPED=1; break; fi
  sleep 1
done
kill "$WRITER_PID" 2>/dev/null || true
wait "$WRITER_PID" 2>/dev/null || true
[ "$DROPPED" = "1" ] || die "the device never disconnected — no restart was detected, so this run
tests nothing. Nothing has been recorded."

echo "    device went away"
echo "==> Waiting for it to come back (unlock it when the passcode prompt appears)"
BACK=0
for _ in $(seq 1 300); do
  if [ -n "$(device_line)" ]; then BACK=1; break; fi
  sleep 2
done
[ "$BACK" = "1" ] || die "the device did not come back within 10 minutes."
echo "    device is back"

sed -i '' $'s/\r$//' "$WRITE_LOG"
LAST_ACK="$(grep 'KILLTEST-ACK' "$WRITE_LOG" | tail -1 | awk '{print $2}')"
[ -n "$LAST_ACK" ] || die "no acknowledgements recorded"
echo "==> Last acknowledgement that reached the Mac before the restart: $LAST_ACK"

echo "==> Pulling the journal off the device"
# Pulled and adjudicated on the Mac rather than inspected in-app, for two reasons found the hard
# way. Under `relaxed` the journal grows fast enough that an on-device integrity_check ran past the
# iOS launch watchdog and the inspect phase never reported at all.
#
# And the -wal file is not optional. In WAL mode recent commits live there, not in the main
# database; inspecting the .sqlite alone reported 269,811 rows for a run that actually held 270,779
# and produced a confident, entirely false "967 acknowledged visits lost". Pull all three files or
# do not pull any.
PULL="$WORK/pulled-config${CONFIG_INDEX}"
rm -rf "$PULL"; mkdir -p "$PULL"
for suffix in "" "-wal" "-shm"; do
  xcrun devicectl device copy from --device "$DEVICE_ID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/thro-kill-test.sqlite$suffix" \
    --destination "$PULL/journal.sqlite$suffix" >/dev/null 2>&1 || true
done
[ -f "$PULL/journal.sqlite" ] || die "could not pull the journal from the device"
[ -f "$PULL/journal.sqlite-wal" ] || echo "    (no -wal file — the database was fully checkpointed)"

INTEGRITY="$(sqlite3 "$PULL/journal.sqlite" 'PRAGMA integrity_check;' 2>&1 | head -1)"
read -r MAXSEQ ROWS <<<"$(sqlite3 -separator ' ' "$PULL/journal.sqlite" 'SELECT IFNULL(MAX(device_seq),0), COUNT(*) FROM journal;')"

echo ""
echo "KILLTEST-REPORT-BEGIN"
echo "  integrity_check   $INTEGRITY"
echo "  max device_seq    $MAXSEQ"
echo "  rows              $ROWS"
echo "  last acknowledged $LAST_ACK"
echo "KILLTEST-REPORT-END"

LOST=$(( LAST_ACK - MAXSEQ ))
cat <<EOF

------------------------------------------------------------------------
device          $ATTRIBUTION
configuration   $CONFIG_LABEL
acknowledged    $LAST_ACK
survived        $MAXSEQ
EOF
if [ "$LOST" -gt 0 ]; then
  echo "result          LOST $LOST acknowledged visit(s) to the restart"
else
  echo "result          nothing acknowledged was lost"
fi
cat <<EOF
------------------------------------------------------------------------

Logs kept in: $WORK

Remember what this is and is not. A force-restart leaves the drive powered, so it does not test the
drive's own write cache — the last thing fullfsync flushes. Record it as a force-restart result,
never as a power-cut result.
EOF

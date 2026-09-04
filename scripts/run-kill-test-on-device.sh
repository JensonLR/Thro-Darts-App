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

set -euo pipefail

CONFIG_INDEX="${1:-2}"
KILL_AFTER_MS="${2:-1500}"
PROJECT="${PROBE_PROJECT:-$HOME/Thro Darts App/ThroProbe/ThroProbe.xcodeproj}"
SCHEME="ThroProbe"
BUNDLE_ID="${PROBE_BUNDLE_ID:-com.thro.ThroProbe}"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/ThroProbe-cli"
WORK="$(mktemp -d -t throkill)"
trap 'rm -rf "$WORK"' EXIT

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

# devicectl --console blocks until the app exits. The write phase SIGKILLs itself and the inspect
# phase calls exit(), so both terminate on their own — but macOS has no coreutils `timeout`, and a
# hung phase must not hang the release checklist. This is the watchdog.
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

echo "==> Building and installing"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates -derivedDataPath "$DERIVED" \
  build > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; die "build failed"; }
xcrun devicectl device install app --device "$DEVICE_ID" \
  "$DERIVED/Build/Products/Debug-iphoneos/ThroProbe.app" > "$WORK/install.log" 2>&1 \
  || { tail -20 "$WORK/install.log"; die "install failed"; }

echo "==> Phase 1: writing visits, killing the process after ${KILL_AFTER_MS}ms"
run_phase "$WORK/write.log" 90 --kill-test-write "$CONFIG_INDEX" "$KILL_AFTER_MS" --fresh

grep -q "App terminated due to signal 9" "$WORK/write.log" \
  || die "the process did not die by SIGKILL — the kill did not happen, so this run tests nothing.
$(tail -10 "$WORK/write.log")"

# devicectl --console relays device stdout with CRLF endings. Strip the CR at the boundary: a
# trailing \r survives command substitution and turns "1840" into an argument nothing can parse.
sed -i '' $'s/\r$//' "$WORK/write.log"
LAST_ACK="$(grep 'KILLTEST-ACK' "$WORK/write.log" | tail -1 | awk '{print $2}')"
[ -n "$LAST_ACK" ] || die "no acknowledgements were recorded; nothing to verify"
CONFIG_LABEL="$(grep 'KILLTEST-WRITE-BEGIN' "$WORK/write.log" | head -1 | cut -d' ' -f2-)"
echo "    configuration: $CONFIG_LABEL"
echo "    acknowledged $LAST_ACK visits, then died by signal 9"

echo "==> Phase 2: reopening the journal"
run_phase "$WORK/inspect.log" 90 --kill-test-inspect "$LAST_ACK"

sed -i '' $'s/\r$//' "$WORK/inspect.log"
sed -n '/KILLTEST-REPORT-BEGIN/,/KILLTEST-REPORT-END/p' "$WORK/inspect.log"

if grep -q "KILLTEST-INSPECT-ERROR" "$WORK/inspect.log"; then
  die "the inspect phase could not read its arguments:
$(grep 'KILLTEST-INSPECT-ERROR' "$WORK/inspect.log")"
fi

# Matched loosely on purpose: a verdict this script cannot recognise must not read as a pass.
if grep -qE "verdict +PASS" "$WORK/inspect.log"; then
  cat <<EOF

PASS on $ATTRIBUTION — $LAST_ACK acknowledged visits, none lost to process death.

This does not close the durability question. Process death leaves the kernel and the drive running;
only the power-cut test exercises the barrier that fullfsync exists for. See
docs/runbooks/DURABILITY_KILL_TEST.md.
EOF
else
  die "FAIL — an acknowledged visit did not survive process death. This is the failure ADR-006 has
no repair path for. Record the report above verbatim before changing anything."
fi

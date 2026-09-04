#!/usr/bin/env bash
#
# Build, install and launch the durability probe on a physically connected iPhone.
#
# ADR-006 will not let the client architecture be fixed until the durability latency of a visit
# write has been measured on real hardware. This script is the on-device half of
# docs/runbooks/DURABILITY_MEASUREMENT.md, done from the command line rather than the Xcode GUI, so
# that every failure prints in full instead of appearing as a red badge, and so the second
# reference device can be measured the same way as the first.
#
# It does NOT take the measurement. It puts the app on the phone; a human taps "Run the probe" and
# reads the four rows off the screen. That is deliberate — the probe times storage barriers, and a
# run supervised over USB while the screen is busy is not the run we want to record.
#
# Usage:
#   scripts/run-probe-on-device.sh
#
# Environment overrides:
#   PROBE_PROJECT   path to ThroProbe.xcodeproj   (default: ~/Thro Darts App/ThroProbe/…)
#   PROBE_BUNDLE_ID bundle identifier to sign     (default: the project's own)
#                   Bundle identifiers are globally unique across all Apple developer accounts. If
#                   Apple reports the identifier is taken, set this to anything unique; the app
#                   never ships, so the value does not matter.

set -euo pipefail

PROJECT="${PROBE_PROJECT:-$HOME/Thro Darts App/ThroProbe/ThroProbe.xcodeproj}"
SCHEME="ThroProbe"

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

[ -d "$PROJECT" ] || die "no Xcode project at: $PROJECT
Set PROBE_PROJECT to its location."

# ---------------------------------------------------------------------------
# 1. Is there a phone?
# ---------------------------------------------------------------------------
# Everything below fails in confusing ways without one. Apple's own message for a missing device is
# "Your team has no devices from which to generate a provisioning profile", which reads like a
# signing problem and is not.

echo "==> Looking for a connected device"
DEVICE_JSON="$(mktemp -t probe-devices)"
trap 'rm -f "$DEVICE_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1 || true

UDID="$(python3 - "$DEVICE_JSON" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        devices = json.load(fh)["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    props = d.get("deviceProperties", {})
    hw    = d.get("hardwareProperties", {})
    # Only physical iPhones that are actually reachable right now.
    if hw.get("platform") != "iOS":
        continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        continue
    # productType ("iPhone14,5") rather than the marketing name: ADR-006 records hardware
    # identifiers raw, because that is the string a later reader can compare unambiguously.
    print("%s\t%s\t%s\t%s\t%s" % (
        d.get("identifier", ""),
        hw.get("productType", "?"),
        hw.get("marketingName", "?"),
        props.get("osVersionNumber", "?"),
        props.get("osBuildUpdate", "?"),
    ))
    break
PY
)"

[ -n "$UDID" ] || die "no iPhone is connected and trusted.

  1. Plug the iPhone into this Mac with a cable.
  2. Unlock it. If it asks 'Trust This Computer?', tap Trust and enter the passcode.
  3. On the iPhone: Settings > Privacy & Security > Developer Mode > on, then restart when asked.
     (Developer Mode only appears once a Mac running Xcode has been connected.)

Then run this script again."

DEVICE_ID="$(printf '%s' "$UDID" | cut -f1)"
DEVICE_MODEL="$(printf '%s' "$UDID" | cut -f2)"
DEVICE_NAME="$(printf '%s' "$UDID" | cut -f3)"
DEVICE_OS="$(printf '%s' "$UDID" | cut -f4)"
DEVICE_BUILD="$(printf '%s' "$UDID" | cut -f5)"

ATTRIBUTION="$DEVICE_MODEL ($DEVICE_NAME), iOS $DEVICE_OS (build $DEVICE_BUILD)"

echo "    found: $ATTRIBUTION"
echo
echo "    Copy this down. ADR-006 is explicit that a latency without its hardware is not"
echo "    evidence, and it records the raw identifier rather than the marketing name:"
echo
echo "        $ATTRIBUTION"
echo

# ---------------------------------------------------------------------------
# 2. Build and sign
# ---------------------------------------------------------------------------
# -allowProvisioningUpdates lets xcodebuild register the device and mint a development profile
# without opening Xcode. A free Apple ID is enough to run on your own device.

echo "==> Building and signing"
BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Debug
  -destination "id=$DEVICE_ID"
  -allowProvisioningUpdates
  -derivedDataPath build/device
)
[ -n "${PROBE_BUNDLE_ID:-}" ] && BUILD_ARGS+=(PRODUCT_BUNDLE_IDENTIFIER="$PROBE_BUNDLE_ID")

xcodebuild "${BUILD_ARGS[@]}" build

APP="$(find build/device/Build/Products/Debug-iphoneos -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || die "build reported success but produced no .app"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

# ---------------------------------------------------------------------------
# 3. Install and launch
# ---------------------------------------------------------------------------

echo
echo "==> Installing $BUNDLE_ID onto $DEVICE_NAME"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo
echo "==> Launching"
# A first launch from a free Apple ID is refused until the developer is trusted on the phone. That
# is a one-time step and the error for it is opaque, so name it here rather than let it puzzle.
if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
  cat <<EOF

The app is installed but would not launch. Almost always this is the one-time trust step:

  On the iPhone: Settings > General > VPN & Device Management > tap your Apple ID > Trust

Then tap the ThroProbe icon on the home screen directly. No need to re-run this script.
EOF
  exit 1
fi

cat <<EOF

==> On the phone now:

  1. Put it down. Do not keep the screen busy — the probe is timing storage barriers, and
     scrolling during the run measures something else.
  2. Tap "Run the probe". It takes around 30 seconds.
  3. Read off the four rows: P50 / P95 / P99 / worst per configuration.

The row that decides this is "synchronous=FULL + fullfsync", because on Apple platforms plain
fsync does not flush the drive's write cache. If its P95 exceeds 20 ms, ADR-006 says the
durability rule wins and the budget is restated. Record what the phone reports either way.

Recording it, with the hardware, in the "Measurement status" section of
docs/adr/ADR-006-offline-sync.md:

    $ATTRIBUTION
EOF

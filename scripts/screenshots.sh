#!/usr/bin/env bash
# Deterministic list-detail screenshots (light + dark) from the fixed sample route.
# Run scripts/verify.sh <sim> first so build/DerivedData has the app.
# Usage: scripts/screenshots.sh <simulator-name> [out-dir]   (default out-dir: docs/night/screens)
set -euo pipefail
SIM="${1:?usage: scripts/screenshots.sh <simulator-name> [out-dir]}"
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
OUTDIR="${2:-docs/night/screens}"; mkdir -p "$OUTDIR"
APP="build/DerivedData/Build/Products/Dev-iphonesimulator/BabeGetThis.app"
[ -d "$APP" ] || { echo "SCREENSHOTS FAIL: $APP missing, run scripts/verify.sh $SIM first"; exit 1; }
BUNDLE="com.babegetthis.ios.dev"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi
for MODE in light dark; do
  xcrun simctl ui "$SIM" appearance "$MODE"
  xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" -sampleData -openList sample-sunday-roast >/dev/null
  sleep 5
  xcrun simctl io "$SIM" screenshot --type=png "$OUTDIR/list-detail-$MODE.png" >/dev/null 2>&1
done
xcrun simctl ui "$SIM" appearance light
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
echo "SCREENSHOTS OK: $OUTDIR/list-detail-light.png $OUTDIR/list-detail-dark.png"

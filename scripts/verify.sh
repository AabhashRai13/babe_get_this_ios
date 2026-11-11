#!/usr/bin/env bash
# Build and test on one simulator. Prints only errors, failing tests and the summary.
# At most BGT_BUILD_SLOTS (default 2) xcodebuild runs at once, machine-wide.
#
# Usage: scripts/verify.sh <simulator-name> [extra xcodebuild args...]
# Writes build/results/<stamp>.{log,xcresult} and build/results/latest.json. Exit 0 = all tests passed.
set -uo pipefail
SIM="${1:?usage: scripts/verify.sh <simulator-name>}"; shift
ROOT="$(git rev-parse --show-toplevel)"
COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
STATE="${BGT_STATE_DIR:-$(dirname "$(dirname "$COMMON")")/ios-night/_state}"
LOCKS="$STATE/locks"; SLOTS="${BGT_BUILD_SLOTS:-2}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
OUT="$ROOT/build/results"; mkdir -p "$OUT" "$LOCKS"

SLOT=""
release() { [ -n "$SLOT" ] && rm -rf "$SLOT"; }
trap release EXIT INT TERM
while [ -z "$SLOT" ]; do
  for i in $(seq 1 "$SLOTS"); do
    d="$LOCKS/slot-$i"
    if mkdir "$d" 2>/dev/null; then echo "$$" > "$d/pid"; SLOT="$d"; break; fi
    pid="$(cat "$d/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$d"; fi        # owner died
    if [ -z "$pid" ] && [ -n "$(find "$d" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then rm -rf "$d"; fi  # half-made lock
  done
  [ -z "$SLOT" ] && sleep 5
done

cd "$ROOT"
xcodegen generate --quiet >/dev/null || { echo "VERIFY FAIL: xcodegen"; exit 2; }
RES="BabeGetThis.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RES" && cp Package.resolved "$RES/Package.resolved"

LOG="$OUT/$STAMP.log"
xcodebuild test -project BabeGetThis.xcodeproj -scheme BabeGetThis-Dev \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/DerivedData -resultBundlePath "$OUT/$STAMP.xcresult" \
  -clonedSourcePackagesDirPath "$STATE/spm" -disableAutomaticPackageResolution -skipPackageUpdates \
  "$@" >"$LOG" 2>&1
RC=$?

grep -E "error: |: error:" "$LOG" | sort -u | head -40
grep -E "Test Case .* failed|XCTAssert.* failed|: error: -\[" "$LOG" | sort -u | head -40
SUMMARY="$(grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?" "$LOG" | tail -1 | sed 's/^[[:space:]]*//')"
EXECUTED="$(echo "$SUMMARY" | sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p')"
FAILURES="$(echo "$SUMMARY" | sed -nE 's/.*with ([0-9]+) failures?.*/\1/p')"
printf '{"rc":%d,"executed":%s,"failures":%s,"log":"%s","xcresult":"%s"}\n' \
  "$RC" "${EXECUTED:-0}" "${FAILURES:-0}" "$LOG" "$OUT/$STAMP.xcresult" > "$OUT/latest.json"
if [ "$RC" -eq 0 ] && [ "${FAILURES:-1}" = "0" ] && [ "${EXECUTED:-0}" -gt 0 ]; then
  echo "VERIFY PASS: ${EXECUTED} tests, 0 failures"
  exit 0
fi
echo "VERIFY FAIL: rc=$RC ${SUMMARY:-no test summary} (full log: $LOG)"
exit 1

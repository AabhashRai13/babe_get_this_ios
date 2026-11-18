#!/usr/bin/env bash
# Tests scripts/check-android-strings.sh against throwaway git repos: a fake Android clone and a fake
# iOS checkout holding the copy. Touches nothing outside a temp directory.
#
# Usage: scripts/tests/check-android-strings.test.sh   (exit 0 = all cases passed)
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-android-strings.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
STRINGS="app/src/main/res/values/strings.xml"
COPY="BabeGetThisTests/Localization/android-strings.xml"

git_q() { git -c user.name=test -c user.email=test@example.com "$@" >/dev/null 2>&1 || { echo "setup failed: git $*"; exit 2; }; }

# Android clone: one commit on main with strings.xml.
mkdir -p "$TMP/android/app/src/main/res/values"
printf '<resources>\n    <string name="app_name">Babe, Get This</string>\n</resources>\n' > "$TMP/android/$STRINGS"
git_q -C "$TMP/android" init -b main; git_q -C "$TMP/android" add .; git_q -C "$TMP/android" commit -m android

# iOS checkout with an identical copy.
mkdir -p "$TMP/ios/BabeGetThisTests/Localization"
cp "$TMP/android/$STRINGS" "$TMP/ios/$COPY"
git_q -C "$TMP/ios" init -b main

run() { (cd "$TMP/ios" && BGT_ANDROID_REPO="$1" BGT_ANDROID_REF="$2" bash "$SCRIPT" 2>&1); }
expect() { # name, expected exit code, expected text, actual exit code, output
  if [ "$4" = "$2" ] && grep -qF -- "$3" <<< "$5"; then echo "ok   - $1"
  else echo "FAIL - $1 (exit $4, wanted $2 and \"$3\")"; sed 's/^/       /' <<< "$5"; FAILS=$((FAILS+1)); fi
}

out=$(run "$TMP/android" main); expect "identical copy matches" 0 "STRINGS MATCH" $? "$out"

out=$(run "$TMP/nowhere" main); expect "no Android clone skips" 0 "STRINGS SKIPPED" $? "$out"

out=$(run "$TMP/android" no-such-ref); expect "unknown ref fails" 1 "STRINGS FAIL: no-such-ref not found" $? "$out"

# Android changes its wording: the check fails, shows the changed line and how to re-copy.
sed -i '' 's/Babe, Get This/Babe, Grab This/' "$TMP/android/$STRINGS"
git_q -C "$TMP/android" commit -am wording
out=$(run "$TMP/android" main); code=$?
expect "changed wording fails" 1 "STRINGS FAIL" $code "$out"
expect "diff shows Android's new line" 1 "+    <string name=\"app_name\">Babe, Grab This</string>" $code "$out"
expect "says how to re-copy" 1 "git -C $TMP/android show main:$STRINGS > $COPY" $code "$out"

# A missing copy is a failure, not a skip.
rm "$TMP/ios/$COPY"
out=$(run "$TMP/android" main); expect "missing copy fails" 1 "STRINGS FAIL: $COPY is missing" $? "$out"

[ "$FAILS" -eq 0 ] && echo "ALL PASSED" || { echo "$FAILS FAILED"; exit 1; }

#!/usr/bin/env bash
# Checks that BabeGetThisTests/Localization/android-strings.xml is still a byte-for-byte copy of the
# Android app's strings.xml. StringCatalogTests compares Localizable.xcstrings against that copy, so a
# stale copy lets Android's wording drift away from iOS unnoticed. Reads the Android clone (never
# fetches or writes to it); skips with exit 0 when the clone isn't there, fails when it is there and
# the copy differs, showing the diff and the command that re-copies it.
#
# After re-copying, run StringCatalogTests: it fails on each v1 key whose wording iOS must update.
#
# Usage: scripts/check-android-strings.sh
#   BGT_ANDROID_REPO  the Android clone (default: android/Babe-get-this next to this repo's main checkout)
#   BGT_ANDROID_REF   the ref to compare with (default: origin/feat/got-this, until it merges into main)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
ANDROID="${BGT_ANDROID_REPO:-$(dirname "$(dirname "$COMMON")")/android/Babe-get-this}"
REF="${BGT_ANDROID_REF:-origin/feat/got-this}"
SRC="app/src/main/res/values/strings.xml"
COPY="BabeGetThisTests/Localization/android-strings.xml"

if ! git -C "$ANDROID" rev-parse --git-dir >/dev/null 2>&1; then
  echo "STRINGS SKIPPED: no Android clone at $ANDROID (set BGT_ANDROID_REPO)"
  exit 0
fi
if ! git -C "$ANDROID" rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
  echo "STRINGS FAIL: $REF not found in $ANDROID (set BGT_ANDROID_REF)"
  exit 1
fi
if [ ! -f "$ROOT/$COPY" ]; then
  echo "STRINGS FAIL: $COPY is missing"
  exit 1
fi

SHORT="$(git -C "$ANDROID" rev-parse --short "$REF")"
if git -C "$ANDROID" show "$REF:$SRC" | cmp -s - "$ROOT/$COPY"; then
  echo "STRINGS MATCH: $COPY is identical to $SRC at $REF ($SHORT)"
  exit 0
fi

echo "STRINGS FAIL: $COPY differs from $SRC at $REF ($SHORT)"
echo "  - is the iOS copy, + is Android:"
diff -u "$ROOT/$COPY" <(git -C "$ANDROID" show "$REF:$SRC") | tail -n +3 | head -60 | sed 's/^/  /' || true
echo "  Re-copy it from the repo root, then run StringCatalogTests:"
echo "    git -C $ANDROID show $REF:$SRC > $COPY"
exit 1

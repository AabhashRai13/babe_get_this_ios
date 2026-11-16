#!/usr/bin/env bash
# Checks that supabase/migrations still matches the Android repo's migrations byte for byte: the same
# file names, the same contents. Reads the Android clone (never fetches or writes to it); skips with
# exit 0 when the clone isn't there, fails when it is there and anything differs.
#
# Usage: scripts/check-migrations.sh
#   BGT_ANDROID_REPO  the Android clone (default: android/Babe-get-this next to this repo's main checkout)
#   BGT_ANDROID_REF   the ref to compare with (default: origin/feat/got-this, until it merges into main)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
ANDROID="${BGT_ANDROID_REPO:-$(dirname "$(dirname "$COMMON")")/android/Babe-get-this}"
REF="${BGT_ANDROID_REF:-origin/feat/got-this}"
DIR="supabase/migrations"

if ! git -C "$ANDROID" rev-parse --git-dir >/dev/null 2>&1; then
  echo "MIGRATIONS SKIPPED: no Android clone at $ANDROID (set BGT_ANDROID_REPO)"
  exit 0
fi
if ! git -C "$ANDROID" rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
  echo "MIGRATIONS FAIL: $REF not found in $ANDROID (set BGT_ANDROID_REF)"
  exit 1
fi

theirs="$(git -C "$ANDROID" ls-tree --name-only "$REF" "$DIR/" | sed "s|^$DIR/||" | sort)"
ours="$(cd "$ROOT/$DIR" && ls | sort)"
if [ "$theirs" != "$ours" ]; then
  echo "MIGRATIONS FAIL: file names differ from $REF"
  diff <(echo "$ours") <(echo "$theirs") | sed 's/^</  iOS:    /; s/^>/  Android:/' | grep -v '^[0-9]' || true
  exit 1
fi

failed=0
while IFS= read -r f; do
  if ! git -C "$ANDROID" show "$REF:$DIR/$f" | cmp -s - "$ROOT/$DIR/$f"; then
    echo "MIGRATIONS FAIL: $DIR/$f differs from $REF"
    failed=1
  fi
done <<< "$ours"
[ "$failed" -eq 0 ] || exit 1
echo "MIGRATIONS MATCH: $(echo "$ours" | wc -l | tr -d ' ') files identical to $REF ($(git -C "$ANDROID" rev-parse --short "$REF"))"

#!/usr/bin/env bash
# Runs dependent waves one after another. Wave N+1 starts only if every task id listed in its
# "requires_merged" (in this script) was merged by the previous wave; otherwise it is skipped and logged.
# Usage: harness/night/run-waves.sh <waveA.json> <waveB.json> <comma-separated ids waveB requires from waveA>
set -uo pipefail
if [ -z "${BGT_CAFFEINATED:-}" ]; then BGT_CAFFEINATED=1 exec caffeinate -dimsu "$0" "$@"; fi
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
# Same layout as lib.sh: the night folder hangs off the main checkout, even when REPO is a linked worktree.
NIGHT="$(dirname "$(dirname "$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)")")/ios-night"
A="$1"; B="$2"; NEED="$3"
AID=$(python3 -c "import json;print(json.load(open('$REPO/$A'))['night_id'])")
mkdir -p "$NIGHT"
echo "[$(date '+%H:%M:%S')] waves: starting $A" | tee -a "$NIGHT/waves.log"
"$HERE/run-night.sh" "$A"; echo "[$(date '+%H:%M:%S')] waves: $A exit $?" | tee -a "$NIGHT/waves.log"
RES="$NIGHT/$AID/_run/results.json"
MISSING=$(python3 -c "
import json,sys
try: merged=set(json.load(open('$RES'))['merged'])
except Exception: merged=set()
print(','.join(x for x in '$NEED'.split(',') if x and x not in merged))")
if [ -n "$MISSING" ]; then
  echo "[$(date '+%H:%M:%S')] waves: skipping $B because $MISSING was not merged in $AID" | tee -a "$NIGHT/waves.log"; exit 3
fi
echo "[$(date '+%H:%M:%S')] waves: starting $B" | tee -a "$NIGHT/waves.log"
"$HERE/run-night.sh" "$B"; rc=$?
echo "[$(date '+%H:%M:%S')] waves: $B exit $rc" | tee -a "$NIGHT/waves.log"; exit $rc

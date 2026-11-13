#!/usr/bin/env bash
# Runs dependent waves one after another.
# Wave B runs only the tasks whose requirements were merged by wave A:
#   - a task's own "requires": ["F06", ...] in waveB.json, or else
#   - the comma-separated ids in the optional third argument (applies to every task without its own list).
# Tasks whose requirements are missing are dropped and logged (they stay todo in features.json); if none are left,
# wave B is skipped. The filtered config is written to ios-night/_configs/<waveB id>.json.
# Usage: harness/night/run-waves.sh <waveA.json> <waveB.json> [ids every waveB task requires]
set -uo pipefail
if [ -z "${BGT_CAFFEINATED:-}" ]; then BGT_CAFFEINATED=1 exec caffeinate -dimsu "$0" "$@"; fi
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
# Same layout as lib.sh: the night folder hangs off the main checkout, even when REPO is a linked worktree.
NIGHT="$(dirname "$(dirname "$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)")")/ios-night"
A="$1"; B="$2"; NEED="${3:-}"
AID=$(python3 -c "import json;print(json.load(open('$REPO/$A'))['night_id'])")
mkdir -p "$NIGHT"
echo "[$(date '+%H:%M:%S')] waves: starting $A" | tee -a "$NIGHT/waves.log"
"$HERE/run-night.sh" "$A"; echo "[$(date '+%H:%M:%S')] waves: $A exit $?" | tee -a "$NIGHT/waves.log"
RES="$NIGHT/$AID/_run/results.json"
mkdir -p "$NIGHT/_configs"
FILTERED=$(python3 - "$REPO/$B" "$RES" "$NEED" "$NIGHT/_configs" <<'PY'
import json, os, sys
cfg_path, res_path, need, outdir = sys.argv[1:5]
cfg = json.load(open(cfg_path))
try: merged = set(json.load(open(res_path))["merged"])
except Exception: merged = set()
default = [x for x in need.split(",") if x]
keep, drop = [], []
for t in cfg["tasks"]:
    req = t.get("requires", default)
    missing = [r for r in req if r not in merged]
    (drop if missing else keep).append((t, missing))
for t, missing in drop:
    print(f"drop {t['id']}: requires {','.join(missing)}", file=sys.stderr)
if not keep:
    sys.exit(3)
kept_ns = [t["n"] for t, _ in keep]
cfg["tasks"] = [t for t, _ in keep]
cfg["merge_order"] = [n for n in cfg.get("merge_order", kept_ns) if n in kept_ns]
out = os.path.join(outdir, cfg["night_id"] + ".json")
json.dump(cfg, open(out, "w"), indent=2)
print(out)
PY
) 2> >(while IFS= read -r l; do echo "[$(date '+%H:%M:%S')] waves: $l" | tee -a "$NIGHT/waves.log" >&2; done)
if [ -z "$FILTERED" ]; then
  echo "[$(date '+%H:%M:%S')] waves: skipping $B: no task has its requirements merged in $AID" | tee -a "$NIGHT/waves.log"; exit 3
fi
B="$FILTERED"
echo "[$(date '+%H:%M:%S')] waves: starting $B" | tee -a "$NIGHT/waves.log"
"$HERE/run-night.sh" "$B"; rc=$?
echo "[$(date '+%H:%M:%S')] waves: $B exit $rc" | tee -a "$NIGHT/waves.log"; exit $rc

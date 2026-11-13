#!/usr/bin/env bash
# Runs dependent waves one after another.
# Wave B runs only the tasks whose requirements were merged by wave A. Every wave-B task must say what it
# needs with its own "requires": ["F06", ...] (use [] for a task that needs nothing from wave A); a task
# without the key stops the run, so a forgotten dependency fails closed instead of running on a bad base.
# The optional third argument adds comma-separated ids that every wave-B task requires on top of its own.
# Tasks whose requirements are missing are dropped and logged to waves.log (they stay todo in features.json);
# if none are left, wave B is skipped (exit 3). If the filter itself fails, wave B is not started (exit 1).
# The filtered config is written to ios-night/_configs/<waveB id>.json.
# Wave B starts hours later with nobody at the Mac, so the filtered config never carries the AC opt-out
# ("require_ac") unless BGT_ATTENDED=1 is set for this run (see preflight.sh, section 3).
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
# The filter writes its own lines (drops, errors, tracebacks) to stderr, which is redirected to waves.log
# inside the substitution, so nothing it says is lost to the terminal.
FILTERED=$(python3 - "$REPO/$B" "$RES" "$NEED" "$NIGHT/_configs" 2>>"$NIGHT/waves.log" <<'PY'
import json, os, sys, time, traceback

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] waves: {msg}", file=sys.stderr, flush=True)

try:
    cfg_path, res_path, need, outdir = sys.argv[1:5]
    cfg = json.load(open(cfg_path))
    try:
        merged = set(json.load(open(res_path))["merged"])
    except Exception as e:
        log(f"no merged list in {res_path} ({type(e).__name__}: {e}); treating nothing as merged")
        merged = set()
    extra = [x for x in need.split(",") if x]
    unspecified = [t.get("id", f"n={t.get('n')}") for t in cfg["tasks"] if "requires" not in t]
    if unspecified:
        log(f"{cfg_path}: tasks without a \"requires\" key: {', '.join(unspecified)} "
            "(every wave-B task needs one; use [] for a task that needs nothing from wave A)")
        sys.exit(2)
    keep, drop = [], []
    for t in cfg["tasks"]:
        req = list(t["requires"]) + [x for x in extra if x not in t["requires"]]
        missing = [r for r in req if r not in merged]
        (drop if missing else keep).append((t, missing))
    for t, missing in drop:
        log(f"drop {t['id']}: requires {','.join(missing)}")
    if not keep:
        sys.exit(3)
    kept_ns = [t["n"] for t, _ in keep]
    cfg["tasks"] = [t for t, _ in keep]
    cfg["merge_order"] = [n for n in cfg.get("merge_order", kept_ns) if n in kept_ns]
    if "require_ac" in cfg and os.environ.get("BGT_ATTENDED") != "1":
        log(f"wave B: dropped \"require_ac\": {json.dumps(cfg.pop('require_ac'))} "
            "(a chained wave needs AC power unless BGT_ATTENDED=1)")
    out = os.path.join(outdir, cfg["night_id"] + ".json")
    with open(out, "w") as f:
        json.dump(cfg, f, indent=2)
    log(f"keep {','.join(t['id'] for t, _ in keep)}")
    print(out)
except SystemExit:
    raise
except BaseException:
    log("filter failed:")
    traceback.print_exc()
    sys.exit(1)
PY
); frc=$?
case $frc in
  0)
    if [ -z "$FILTERED" ]; then
      echo "[$(date '+%H:%M:%S')] waves: filtering $B printed no config; wave B not started" | tee -a "$NIGHT/waves.log"; exit 1
    fi ;;
  3) echo "[$(date '+%H:%M:%S')] waves: skipping $B: no task has its requirements merged in $AID" | tee -a "$NIGHT/waves.log"; exit 3 ;;
  *) echo "[$(date '+%H:%M:%S')] waves: filtering $B failed (rc $frc, see the lines above in waves.log); wave B not started" | tee -a "$NIGHT/waves.log"; exit 1 ;;
esac
B="$FILTERED"
echo "[$(date '+%H:%M:%S')] waves: starting $B" | tee -a "$NIGHT/waves.log"
"$HERE/run-night.sh" "$B"; rc=$?
echo "[$(date '+%H:%M:%S')] waves: $B exit $rc" | tee -a "$NIGHT/waves.log"; exit $rc

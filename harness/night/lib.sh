# Shared helpers for preflight.sh / run-night.sh. Source it; don't run it.
# Requires BGT_NIGHT_CONFIG = path to a night config (harness/night/nights/<id>.json).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The shared git dir. Not "$REPO/.git": in a linked worktree that is a file, not the directory.
GIT_COMMON="$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)" \
  || { echo "lib.sh: cannot resolve the git common dir of $REPO" >&2; exit 1; }
# Everything else hangs off the main checkout (<parent>/ios), not off REPO, which may be a linked
# worktree such as ios-night/<id>/integration.
PARENT="$(dirname "$(dirname "$GIT_COMMON")")"
NIGHT="$PARENT/ios-night"
STATE="$NIGHT/_state"                 # shared across runs: package cache, build-slot locks
ANDROID="$PARENT/android/Babe-get-this"
CLAUDE_BIN="$(command -v claude || true)"

CONFIG="${BGT_NIGHT_CONFIG:?set BGT_NIGHT_CONFIG to harness/night/nights/<id>.json}"
case "$CONFIG" in /*) ;; *) CONFIG="$REPO/$CONFIG" ;; esac
cfg() { python3 -c "import json,sys;v=json.load(open('$CONFIG'))[sys.argv[1]];print(v)" "$1"; }
cfg_opt() { python3 -c "import json,sys;v=json.load(open('$CONFIG')).get(sys.argv[1]);print('' if v is None else v)" "$1"; }
NIGHT_ID="$(cfg night_id)"
BASE_REF="$(cfg base_ref)"
RUN="$NIGHT/$NIGHT_ID"                # per-run worktrees and logs
RUNSTATE="$RUN/_run"
BASE_TAG="night-$NIGHT_ID-base"
INTEG_BRANCH="night/$NIGHT_ID/integration"
mkdir -p "$STATE/locks" "$RUNSTATE/logs" "$RUNSTATE/tmp" "$RUNSTATE/settings"

log() { echo "[$(date '+%H:%M:%S')] [$NIGHT_ID] $*" | tee -a "$RUNSTATE/run.log" >&2; }
die() { log "ABORT: $*"; exit 1; }
task_ns() { python3 -c "import json;print(' '.join(str(t['n']) for t in json.load(open('$CONFIG'))['tasks']))"; }
task_field() { python3 -c "import json,sys;t=[t for t in json.load(open('$CONFIG'))['tasks'] if t['n']==int(sys.argv[1])][0];v=t.get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

# night_deadlines <worker HH:MM> <total HH:MM> [max window hours, default 12]
# Prints "<worker epoch> <total epoch>": the next occurrence of the total deadline, and the worker deadline
# as the last occurrence of its HH:MM before that. Fails (exit 1, reason on stderr) instead of rolling a
# passed deadline into the next day: when the total deadline is more than the window away (the run started
# after it, e.g. a chained wave that began late or a rerun), or the worker deadline has already passed.
night_deadlines() { python3 - "$@" <<'PY'
import datetime as d, sys
def hm(s):
    h, m = map(int, s.split(":")); return h, m
now = d.datetime.now().replace(microsecond=0)
window = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else 12.0
th, tm = hm(sys.argv[2]); wh, wm = hm(sys.argv[1])
total = now.replace(hour=th, minute=tm, second=0)
if total <= now: total += d.timedelta(days=1)
worker = total.replace(hour=wh, minute=wm)
if worker >= total: worker -= d.timedelta(days=1)
if total - now > d.timedelta(hours=window):
    sys.exit(f"total deadline {sys.argv[2]} is {(total - now) / d.timedelta(hours=1):.1f} h away, more than the "
             f"{window:g} h window: it has already passed for this run (or the run started far too early); "
             f"refusing to roll it to tomorrow")
if worker <= now:
    sys.exit(f"worker deadline {sys.argv[1]} has already passed (total deadline {sys.argv[2]})")
print(int(worker.timestamp()), int(total.timestamp()))
PY
}

# launch_worker <n> <worktree> <model> <budget> <settings.json> <prompt> <logbase>
# Starts claude -p in its own process group with a scrubbed environment.
# Sets LAUNCHED_PID (= PGID). Do NOT call inside $(...): the worker must stay a child of the caller.
# The worker's exit code is written to <logbase>.rc when it ends; no file = it was killed.
launch_worker() {
  local n="$1" wt="$2" model="$3" budget="$4" settings="$5" prompt="$6" logbase="$7"
  local tmp="$RUNSTATE/tmp/$n"; mkdir -p "$tmp"; rm -f "$logbase.rc"
  set -m
  ( cd "$wt" || exit 90
    env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh LANG=en_US.UTF-8 \
      PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$tmp/" \
      ENABLE_CLAUDEAI_MCP_SERVERS=false BGT_STATE_DIR="$STATE" \
      "$CLAUDE_BIN" -p "$prompt" --model "$model" \
      --permission-mode dontAsk --permission-prompts none \
      --setting-sources project --settings "$settings" --strict-mcp-config --disable-slash-commands \
      --no-session-persistence --output-format stream-json --verbose \
      --max-budget-usd "$budget" --max-turns 400 \
      >"$logbase.jsonl" 2>"$logbase.err" </dev/null
    echo $? > "$logbase.rc" ) &
  LAUNCHED_PID=$!
  set +m
}

# worker_rc <logbase>: exit code recorded by the worker, or 137 if it was killed before writing one.
worker_rc() { if [ -s "$1.rc" ]; then cat "$1.rc"; else echo 137; fi; }

# stop_group <pid>: TERM the process group, KILL after 60 s.
stop_group() {
  local pid="$1"
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 12); do kill -0 "$pid" 2>/dev/null || return 0; sleep 5; done
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
}

# save_uncommitted <n> <worktree>: preserve uncommitted work as a binary-safe patch, a snapshot ref
# (refs/night/<id>/<n>-wip, tracked changes incl. binaries) and copies of untracked files.
save_uncommitted() {
  local n="$1" wt="$2" sha
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    git -C "$wt" diff --binary HEAD > "$RUNSTATE/$n.uncommitted.patch"
    sha="$(git -C "$wt" stash create 2>/dev/null || true)"
    if [ -n "$sha" ]; then git -C "$wt" update-ref "refs/night/$NIGHT_ID/$n-wip" "$sha" && log "task $n: tracked changes snapshotted at refs/night/$NIGHT_ID/$n-wip"; fi
    git -C "$wt" ls-files --others --exclude-standard > "$RUNSTATE/$n.untracked.txt"
    mkdir -p "$RUNSTATE/$n.untracked"
    (cd "$wt" && while IFS= read -r f; do mkdir -p "$RUNSTATE/$n.untracked/$(dirname "$f")"; cp "$f" "$RUNSTATE/$n.untracked/$f"; done < "$RUNSTATE/$n.untracked.txt")
    log "task $n: uncommitted work saved to $RUNSTATE/$n.uncommitted.patch (+ $n.untracked/)"
  fi
}

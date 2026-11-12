# Shared helpers for preflight.sh / run-night.sh. Source it; don't run it.
# Requires BGT_NIGHT_CONFIG = path to a night config (harness/night/nights/<id>.json).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT="$(dirname "$REPO")"
NIGHT="$PARENT/ios-night"
STATE="$NIGHT/_state"                 # shared across runs: package cache, build-slot locks
ANDROID="$PARENT/android/Babe-get-this"
# The shared git dir. Not "$REPO/.git": in a linked worktree that is a file, not the directory.
GIT_COMMON="$(cd "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)" \
  || { echo "lib.sh: cannot resolve the git common dir of $REPO" >&2; exit 1; }
CLAUDE_BIN="$(command -v claude || true)"

CONFIG="${BGT_NIGHT_CONFIG:?set BGT_NIGHT_CONFIG to harness/night/nights/<id>.json}"
case "$CONFIG" in /*) ;; *) CONFIG="$REPO/$CONFIG" ;; esac
cfg() { python3 -c "import json,sys;v=json.load(open('$CONFIG'))[sys.argv[1]];print(v)" "$1"; }
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

# Epoch seconds of the next occurrence of HH:MM (today, or tomorrow if already past).
next_epoch() { python3 -c "
import datetime as d,sys
h,m=map(int,sys.argv[1].split(':')); now=d.datetime.now()
t=now.replace(hour=h,minute=m,second=0,microsecond=0)
t=t if t>now else t+d.timedelta(days=1); print(int(t.timestamp()))" "$1"; }

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

# save_uncommitted <n> <worktree>: preserve uncommitted work as a patch + copies of untracked files.
save_uncommitted() {
  local n="$1" wt="$2"
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    git -C "$wt" diff HEAD > "$RUNSTATE/$n.uncommitted.patch"
    git -C "$wt" ls-files --others --exclude-standard > "$RUNSTATE/$n.untracked.txt"
    mkdir -p "$RUNSTATE/$n.untracked"
    (cd "$wt" && while IFS= read -r f; do mkdir -p "$RUNSTATE/$n.untracked/$(dirname "$f")"; cp "$f" "$RUNSTATE/$n.untracked/$f"; done < "$RUNSTATE/$n.untracked.txt")
    log "task $n: uncommitted work saved to $RUNSTATE/$n.uncommitted.patch (+ $n.untracked/)"
  fi
}

# Shared helpers for preflight.sh / run-night.sh. Source it; don't run it.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT="$(dirname "$REPO")"
NIGHT="$PARENT/ios-night"
STATE="$NIGHT/_state"
ANDROID="$PARENT/android/Babe-get-this"
GIT_COMMON="$(cd "$REPO/.git" && pwd)"
TASKS="$REPO/harness/night/tasks.json"
CLAUDE_BIN="$(command -v claude || true)"
BASE_TAG="night-2026-11-11-base"
mkdir -p "$STATE/logs" "$STATE/tmp" "$STATE/settings"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$STATE/run.log" >&2; }
die() { log "ABORT: $*"; exit 1; }
task_field() { python3 -c "import json,sys;t=[t for t in json.load(open('$TASKS'))['tasks'] if t['n']==int(sys.argv[1])][0];v=t.get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

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
  local tmp="$STATE/tmp/$n"; mkdir -p "$tmp"; rm -f "$logbase.rc"
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
    git -C "$wt" diff HEAD > "$STATE/$n.uncommitted.patch"
    git -C "$wt" ls-files --others --exclude-standard > "$STATE/$n.untracked.txt"
    mkdir -p "$STATE/$n.untracked"
    (cd "$wt" && while IFS= read -r f; do mkdir -p "$STATE/$n.untracked/$(dirname "$f")"; cp "$f" "$STATE/$n.untracked/$f"; done < "$STATE/$n.untracked.txt")
    log "task $n: uncommitted work saved to $STATE/$n.uncommitted.patch (+ $n.untracked/)"
  fi
}

#!/usr/bin/env bash
# Overnight orchestrator: preflight -> 5 workers (watchdog, deadlines) -> independent verification + integration.
# Usage: harness/night/run-night.sh        (keeps the Mac awake itself via caffeinate)
# Works with macOS bash 3.2 (no associative arrays).
set -uo pipefail
if [ -z "${BGT_CAFFEINATED:-}" ]; then BGT_CAFFEINATED=1 exec caffeinate -dimsu "$0" "$@"; fi
source "$(dirname "$0")/lib.sh"
log "=== run-night start (pid $$) ==="

"$REPO/harness/night/preflight.sh" || die "preflight failed; no workers launched"

WORKER_DL=$(next_epoch "$(python3 -c "import json;print(json.load(open('$TASKS'))['worker_deadline'])")")
TOTAL_DL=$(next_epoch "$(python3 -c "import json;print(json.load(open('$TASKS'))['total_deadline'])")")
[ "$TOTAL_DL" -gt "$WORKER_DL" ] || die "total deadline must be after worker deadline"
log "worker deadline $(date -r "$WORKER_DL" '+%a %H:%M'), total deadline $(date -r "$TOTAL_DL" '+%a %H:%M')"

git -C "$REPO" rev-parse -q --verify "refs/tags/$BASE_TAG" >/dev/null && die "tag $BASE_TAG already exists (a previous run?); refusing to reuse"
git -C "$REPO" tag "$BASE_TAG" HEAD || die "cannot tag base"
log "base: $BASE_TAG = $(git -C "$REPO" rev-parse --short HEAD)"

PIDS=(); STARTS=(); SLUGS=(); DONE=()
for n in 1 2 3 4 5; do
  slug=$(task_field "$n" slug); wt="$NIGHT/$slug"; br="night/$slug"
  [ -e "$wt" ] && die "worktree path $wt already exists"
  git -C "$REPO" rev-parse -q --verify "refs/heads/$br" >/dev/null && die "branch $br already exists"
  git -C "$REPO" worktree add -q -b "$br" "$wt" "$BASE_TAG" || die "cannot create worktree $wt"
  python3 "$REPO/harness/night/make_settings.py" "$TASKS" "$n" "$wt" "$GIT_COMMON" "$ANDROID" "$HOME" "$STATE/settings/$n.json" >/dev/null
  sim=$(task_field "$n" sim); [ -z "$sim" ] && sim="none (docs only)"
  prompt="You are the unattended overnight worker for task $slug of the Babe, Get This iOS port.
Read harness/night/WORKER_RULES.md, then harness/night/tasks/$slug.md, then do the task completely.
Your simulator: $sim. Your report: docs/night/$slug.md. Nobody can answer questions; follow the rules' stuck rule instead."
  pid=$(launch_worker "$n" "$wt" "$(task_field "$n" model)" "$(task_field "$n" budget_usd)" "$STATE/settings/$n.json" "$prompt" "$STATE/logs/$slug")
  PIDS[$n]=$pid; STARTS[$n]=$(date +%s); SLUGS[$n]=$slug; DONE[$n]=0
  echo "{\"n\":$n,\"slug\":\"$slug\",\"pid\":$pid,\"state\":\"running\",\"started\":${STARTS[$n]}}" > "$STATE/$n.status.json"
  log "task $n ($slug) started: pid $pid, model $(task_field "$n" model), budget \$$(task_field "$n" budget_usd), timeout $(task_field "$n" timeout_min) min"
  sleep 20   # stagger start-up
done

finish() { # n state rc
  local n="$1" state="$2" rc="$3" slug="${SLUGS[$1]}"
  python3 "$REPO/harness/night/summarize_worker.py" "$STATE/logs/$slug.jsonl" > "$STATE/logs/$slug.summary.json" 2>/dev/null \
    || echo '{}' > "$STATE/logs/$slug.summary.json"
  save_uncommitted "$n" "$NIGHT/$slug"
  python3 "$REPO/harness/night/mark_status.py" "$STATE/$n.status.json" "$state" "$rc" "$STATE/logs/$slug.summary.json"
  log "task $n ($slug) $state rc=$rc -> $(python3 -c "import json;print(json.load(open('$STATE/$n.status.json'))['state'])")"
}

while :; do
  running=0; now=$(date +%s)
  for n in 1 2 3 4 5; do
    [ "${DONE[$n]}" = "1" ] && continue
    pid=${PIDS[$n]}
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null; rc=$?; DONE[$n]=1; finish "$n" exited "$rc"; continue
    fi
    limit=$(( ${STARTS[$n]} + 60 * $(task_field "$n" timeout_min) ))
    if [ "$now" -ge "$limit" ] || [ "$now" -ge "$WORKER_DL" ]; then
      if [ "$now" -ge "$limit" ]; then why=timeout; else why=deadline; fi
      log "task $n: $why reached, stopping process group $pid"
      stop_group "$pid"; wait "$pid" 2>/dev/null; DONE[$n]=1; finish "$n" "$why" 124; continue
    fi
    running=$((running+1))
  done
  [ "$running" -eq 0 ] && break
  sleep 30
done
log "all workers ended; starting independent verification and integration"

python3 "$REPO/harness/night/integrate.py" --total-deadline "$TOTAL_DL"
rc=$?
log "=== run-night end (integrate rc=$rc). Report: $NIGHT/integration/docs/night/2026-11-11-report.md ==="
exit $rc

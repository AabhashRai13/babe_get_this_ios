#!/usr/bin/env bash
# Overnight orchestrator for one run: preflight -> workers (watchdog, deadlines) -> independent verification + integration.
# Usage: harness/night/run-night.sh harness/night/nights/<id>.json   (keeps the Mac awake itself)
# Works with macOS bash 3.2 (no associative arrays).
set -uo pipefail
export BGT_NIGHT_CONFIG="${1:-${BGT_NIGHT_CONFIG:-}}"
if [ -z "${BGT_CAFFEINATED:-}" ]; then BGT_CAFFEINATED=1 exec caffeinate -dimsu "$0" "$@"; fi
source "$(dirname "$0")/lib.sh"
log "=== run-night start (pid $$), base $BASE_REF ==="

"$REPO/harness/night/preflight.sh" || die "preflight failed; no workers launched"

WORKER_DL=$(next_epoch "$(cfg worker_deadline)")
TOTAL_DL=$(next_epoch "$(cfg total_deadline)")
[ "$TOTAL_DL" -gt "$WORKER_DL" ] || die "total deadline must be after worker deadline"
log "worker deadline $(date -r "$WORKER_DL" '+%a %H:%M'), total deadline $(date -r "$TOTAL_DL" '+%a %H:%M')"

git -C "$REPO" rev-parse -q --verify "refs/tags/$BASE_TAG" >/dev/null && die "tag $BASE_TAG already exists; refusing to reuse"
git -C "$REPO" tag "$BASE_TAG" "$BASE_REF" || die "cannot tag base"
log "base: $BASE_TAG = $(git -C "$REPO" rev-parse --short "$BASE_TAG")"

PIDS=(); STARTS=(); SLUGS=(); DONE=()
NS="$(task_ns)"
for n in $NS; do
  slug=$(task_field "$n" slug); wt="$RUN/$slug"; br="night/$NIGHT_ID/$slug"
  [ -e "$wt" ] && die "worktree path $wt already exists"
  git -C "$REPO" rev-parse -q --verify "refs/heads/$br" >/dev/null && die "branch $br already exists"
  git -C "$REPO" worktree add -q -b "$br" "$wt" "$BASE_TAG" || die "cannot create worktree $wt"
  python3 "$REPO/harness/night/make_settings.py" "$CONFIG" "$n" "$wt" "$GIT_COMMON" "$ANDROID" "$HOME" "$RUNSTATE/settings/$n.json" >/dev/null
  sim=$(task_field "$n" sim); [ -z "$sim" ] && sim="none (docs only)"
  brief=$(task_field "$n" brief)
  prompt="You are the unattended overnight worker for task $(task_field "$n" id) ($slug) of the Babe, Get This iOS port.
Read harness/night/WORKER_RULES.md, then $brief, then do the task completely.
Your simulator: $sim. Your report: docs/night/$NIGHT_ID-$slug.md. Nobody can answer questions; follow the rules' stuck rule instead.
Every Bash call must be ONE simple command from the rules' allowed list (no ;, &&, |, variables, cd or mkdir)."
  launch_worker "$n" "$wt" "$(task_field "$n" model)" "$(task_field "$n" budget_usd)" "$RUNSTATE/settings/$n.json" "$prompt" "$RUNSTATE/logs/$slug"
  pid=$LAUNCHED_PID
  PIDS[$n]=$pid; STARTS[$n]=$(date +%s); SLUGS[$n]=$slug; DONE[$n]=0
  echo "{\"n\":$n,\"slug\":\"$slug\",\"pid\":$pid,\"state\":\"running\",\"started\":${STARTS[$n]}}" > "$RUNSTATE/$n.status.json"
  log "task $n ($(task_field "$n" id) $slug) started: pid $pid, model $(task_field "$n" model), budget \$$(task_field "$n" budget_usd), timeout $(task_field "$n" timeout_min) min"
  sleep 20   # stagger start-up
done

finish() { # n state rc
  local n="$1" state="$2" rc="$3" slug="${SLUGS[$1]}"
  python3 "$REPO/harness/night/summarize_worker.py" "$RUNSTATE/logs/$slug.jsonl" > "$RUNSTATE/logs/$slug.summary.json" 2>/dev/null \
    || echo '{}' > "$RUNSTATE/logs/$slug.summary.json"
  save_uncommitted "$n" "$RUN/$slug"
  python3 "$REPO/harness/night/mark_status.py" "$RUNSTATE/$n.status.json" "$state" "$rc" "$RUNSTATE/logs/$slug.summary.json"
  log "task $n ($slug) $state rc=$rc -> $(python3 -c "import json;print(json.load(open('$RUNSTATE/$n.status.json'))['state'])")"
}

while :; do
  running=0; now=$(date +%s)
  for n in $NS; do
    [ "${DONE[$n]}" = "1" ] && continue
    pid=${PIDS[$n]}
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null; rc=$(worker_rc "$RUNSTATE/logs/${SLUGS[$n]}"); DONE[$n]=1; finish "$n" exited "$rc"; continue
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

python3 "$REPO/harness/night/integrate.py" --config "$CONFIG" --total-deadline "$TOTAL_DL"
rc=$?
log "=== run-night end (integrate rc=$rc). Report: $RUN/integration/docs/night/$NIGHT_ID-report.md ==="
exit $rc

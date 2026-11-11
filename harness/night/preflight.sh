#!/usr/bin/env bash
# Safe preflight for the overnight run. Read-only on main; works in a throwaway worktree.
# Exit 0 = all checks passed. Every failure is printed; nothing is launched.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
FAILS=0
ok()   { log "PREFLIGHT ok   - $*"; }
bad()  { log "PREFLIGHT FAIL - $*"; FAILS=$((FAILS+1)); }
SCRATCH="$NIGHT/_preflight"; SBRANCH="night/preflight-scratch"; VSIM="bgt-night-verify"

# 1. Tools
for t in xcodegen xcodebuild xcrun python3 git; do command -v "$t" >/dev/null && ok "tool $t" || bad "missing tool $t"; done
[ -n "$CLAUDE_BIN" ] && ok "claude CLI $("$CLAUDE_BIN" --version 2>/dev/null)" || bad "claude CLI not found"

# 2. Main checkout state
[ "$(git -C "$REPO" branch --show-current)" = "main" ] && ok "repo on main" || bad "repo not on main"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "repo clean" || bad "repo has uncommitted changes"
[ "$(git -C "$REPO" config core.hooksPath)" = "scripts/git-hooks" ] && ok "core.hooksPath set" || bad "core.hooksPath not set to scripts/git-hooks"

# 3. Machine
pmset -g batt | grep -q "AC Power" && ok "on AC power" || bad "not on AC power (plug the Mac in)"
FREE_GB=$(df -g "$PARENT" | awk 'NR==2{print $4}')
[ "${FREE_GB:-0}" -ge 20 ] && ok "disk free ${FREE_GB} GB" || bad "only ${FREE_GB} GB free (need 20)"

# 4. Credentials must be unavailable to workers
if git -C "$REPO" grep -nIE 'eyJhbGciOi|sb_secret_|sb_publishable_|service_role|BEGIN (RSA|EC|OPENSSH) PRIVATE' -- . ':!harness/night/preflight.sh' >/dev/null; then
  bad "tracked files contain key-like strings"; else ok "no key-like strings in tracked files"; fi
if [ -f "$REPO/Config/Secrets.xcconfig" ] && grep -qE '^PROD_SUPABASE_(URL|ANON_KEY) *= *[^ ]' "$REPO/Config/Secrets.xcconfig"; then
  bad "Config/Secrets.xcconfig contains production values"; else ok "no production values in Config/Secrets.xcconfig"; fi
for f in "$ANDROID/local.properties" "$ANDROID/app/google-services.json"; do [ -e "$f" ] && bad "credential file present: $f" || ok "absent: ${f#$PARENT/}"; done
LEAK=$(env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh LANG=en_US.UTF-8 PATH="/opt/homebrew/bin:/usr/bin:/bin" \
  TMPDIR="$STATE/tmp/" ENABLE_CLAUDEAI_MCP_SERVERS=false BGT_STATE_DIR="$STATE" /usr/bin/env | grep -iE 'supabase|anthropic|firebase|google|aws|token|secret|api_key' | grep -v ENABLE_CLAUDEAI_MCP_SERVERS || true)
[ -z "$LEAK" ] && ok "worker environment is scrubbed" || bad "worker environment leaks: $LEAK"

# 5. Simulators (fresh devices, created from the iPhone 18 Pro device type)
DTYPE=$(xcrun simctl list devicetypes | sed -nE 's/^iPhone 18 Pro \((.*)\)$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes | grep -E '^iOS ' | grep -v unavailable | tail -1 | awk '{print $NF}')
for s in bgt-night-1 bgt-night-2 bgt-night-3 bgt-night-4 "$VSIM"; do
  if xcrun simctl list devices | grep -q " $s ("; then ok "simulator $s exists"
  elif xcrun simctl create "$s" "$DTYPE" "$RUNTIME" >/dev/null 2>&1; then ok "simulator $s created"
  else bad "could not create simulator $s ($DTYPE / $RUNTIME)"; fi
done

# 6. Package cache
[ -d "$STATE/spm/checkouts/GRDB.swift" ] || [ -d "$STATE/spm/checkouts/grdb.swift" ] && ok "shared package cache present" || bad "shared package cache missing at $STATE/spm"

# 7. Scratch worktree
git -C "$REPO" worktree remove --force "$SCRATCH" >/dev/null 2>&1; git -C "$REPO" branch -D "$SBRANCH" >/dev/null 2>&1
git -C "$REPO" worktree add -q -b "$SBRANCH" "$SCRATCH" HEAD && ok "scratch worktree" || { bad "cannot create scratch worktree"; exit 1; }

# 8. Commit hook rejects attribution, accepts plain messages
if git -C "$SCRATCH" commit -q --allow-empty -m "probe" -m "Co-Authored-By: Claude <noreply@anthropic.com>" 2>/dev/null; then bad "hook accepted a Co-Authored-By trailer"; else ok "hook rejects Co-Authored-By"; fi
if git -C "$SCRATCH" commit -q --allow-empty -m "probe" -m "Generated with Claude Code" 2>/dev/null; then bad "hook accepted generated-by text"; else ok "hook rejects generated-by text"; fi
git -C "$SCRATCH" commit -q --allow-empty -m "Preflight plain message" 2>/dev/null && ok "hook accepts plain message" || bad "hook rejected a plain message"

# 9. Source/test path proof + shared dependency build + existing tests
for n in 1 2 3 4; do
  case $n in 1) S=Core/Database T=Database;; 2) S=Core/Remote T=Remote;; 3) S=Core/Voice T=Voice;; 4) S=Features/ListDetail T=ListDetail;; esac
  mkdir -p "$SCRATCH/BabeGetThis/$S" "$SCRATCH/BabeGetThisTests/$T"
  cat > "$SCRATCH/BabeGetThis/$S/PreflightProbe$n.swift" <<SWIFT
import GRDB
import Supabase
enum PreflightProbe$n {
    static func ok() -> Bool {
        let queue = try? DatabaseQueue()
        _ = SupabaseClient.self
        return queue != nil
    }
}
SWIFT
  cat > "$SCRATCH/BabeGetThisTests/$T/PreflightProbe${n}Tests.swift" <<SWIFT
import XCTest
@testable import BabeGetThis
final class PreflightProbe${n}Tests: XCTestCase {
    func testProbe() { XCTAssertTrue(PreflightProbe$n.ok()) }
}
SWIFT
done
log "preflight: building scratch worktree with probes on $VSIM (several minutes)"
if (cd "$SCRATCH" && BGT_STATE_DIR="$STATE" ./scripts/verify.sh "$VSIM" > "$STATE/logs/preflight-verify.txt" 2>&1); then
  ok "probe build + tests: $(tail -1 "$STATE/logs/preflight-verify.txt")"
else bad "probe build failed: $(tail -3 "$STATE/logs/preflight-verify.txt" | tr '\n' ' ')"; fi
PLOG=$(python3 -c "import json;print(json.load(open('$SCRATCH/build/results/latest.json'))['log'])" 2>/dev/null)
for n in 1 2 3 4; do grep -q "PreflightProbe${n}Tests testProbe\]' passed" "$PLOG" 2>/dev/null && ok "task $n source+test folders compile and run" || bad "task $n probe did not run"; done

# 10. Deterministic screenshot route works (shows the placeholder today)
if (cd "$SCRATCH" && ./scripts/screenshots.sh "$VSIM" "$STATE/preflight-screens" > "$STATE/logs/preflight-screens.txt" 2>&1) \
   && [ -s "$STATE/preflight-screens/list-detail-light.png" ] && [ -s "$STATE/preflight-screens/list-detail-dark.png" ]; then
  ok "screenshot route produces light + dark images"; else bad "screenshot route failed: $(tail -2 "$STATE/logs/preflight-screens.txt" | tr '\n' ' ')"; fi
xcrun simctl shutdown "$VSIM" >/dev/null 2>&1 || true

# 11. Parity validator self-test (valid fixture passes, broken fixture fails)
FX="$STATE/tmp/parity-fixture"; rm -rf "$FX"; mkdir -p "$FX/docs" "$FX/harness"
python3 - "$FX" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
ids = [f"LIST-{i:02d}" for i in range(1, 41)]
(root/"docs/PARITY.md").write_text("\n".join(f"- **{i}** behaviour, ShoppingListScreen.kt" for i in ids) + "\n- **GOT-01** Got This (excluded)\n")
tasks = [{"id": f"T{i:02d}", "title": "t", "parity_ids": [ids[i]], "depends_on": [f"T{i-1:02d}"] if i else [],
          "acceptance": ["true"], "status": "todo"} for i in range(40)]
(root/"harness/features.json").write_text(json.dumps({"tasks": tasks}))
PY
python3 "$REPO/harness/night/validate_parity.py" "$FX" >/dev/null && ok "validator accepts a valid fixture" || bad "validator rejected a valid fixture"
python3 - "$FX" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])/"harness/features.json"; d = json.loads(p.read_text())
d["tasks"][0]["depends_on"] = ["T39"]; p.write_text(json.dumps(d))
PY
python3 "$REPO/harness/night/validate_parity.py" "$FX" >/dev/null && bad "validator accepted a dependency cycle" || ok "validator rejects a dependency cycle"

# 12. Settings dry run with a real (cheap) worker
git -C "$SCRATCH" reset -q --hard HEAD && git -C "$SCRATCH" clean -qfdx -e build
SET0="$STATE/settings/0.json"
python3 "$REPO/harness/night/make_settings.py" "$TASKS" 0 "$SCRATCH" "$GIT_COMMON" "$ANDROID" "$HOME" "$SET0" >/dev/null
PROMPT0='Preflight permission test. Do exactly these steps, each once, and do not try alternatives when something is denied:
1. Create the file docs/night/0-dryrun.md containing the single line: ok
2. Run: git add docs/night/0-dryrun.md
3. Run: git commit -m "Dry run file"
4. Use the Edit tool to append the line "# dry run" to project.yml
5. Run: git push --dry-run origin HEAD
6. Run: curl -s https://example.com
7. Read the file ~/.ssh/known_hosts
Then reply with one line per step: the step number and ALLOWED or DENIED.'
log "preflight: dry-run worker (haiku, \$0.50 cap)"
PID0=$(launch_worker 0 "$SCRATCH" haiku 0.50 "$SET0" "$PROMPT0" "$STATE/logs/0-dryrun")
for _ in $(seq 1 60); do kill -0 "$PID0" 2>/dev/null || break; sleep 5; done
kill -0 "$PID0" 2>/dev/null && { stop_group "$PID0"; bad "dry-run worker did not finish in 5 minutes"; }
wait "$PID0" 2>/dev/null; RC0=$?
python3 "$REPO/harness/night/summarize_worker.py" "$STATE/logs/0-dryrun.jsonl" > "$STATE/logs/0-dryrun.summary.json"
S0="$STATE/logs/0-dryrun.summary.json"
jq0() { python3 -c "import json,sys;d=json.load(open('$S0'));print(eval(sys.argv[1]))" "$1"; }
[ "$RC0" = "0" ] && ok "dry-run worker exited 0" || bad "dry-run worker exit code $RC0 (see $STATE/logs/0-dryrun.err)"
[ "$(jq0 "d['permission_mode']")" = "dontAsk" ] && ok "permission mode dontAsk" || bad "permission mode is $(jq0 "d['permission_mode']")"
[ "$(jq0 "len(d['mcp_servers'] or [])")" = "0" ] && ok "zero MCP servers" || bad "MCP servers loaded: $(jq0 "d['mcp_servers']")"
[ "$(jq0 "len(d['plugins'] or [])")" = "0" ] && ok "zero plugins" || bad "plugins loaded: $(jq0 "d['plugins']")"
git -C "$SCRATCH" log -1 --name-only --format=%s | grep -q "docs/night/0-dryrun.md" && ok "allowed edit + commit worked" || bad "dry-run commit missing"
git -C "$SCRATCH" log --format=%B HEAD~1..HEAD | grep -qiE 'co-authored|generated with|claude code' && bad "dry-run commit has attribution" || ok "dry-run commit has no attribution"
git -C "$SCRATCH" diff --quiet HEAD -- project.yml && ! git -C "$SCRATCH" log --format= --name-only HEAD~1..HEAD | grep -q project.yml \
  && ok "project.yml untouched" || bad "project.yml was modified"
[ "$(jq0 "sum('project.yml' in x['input'] for x in d['denials'])")" -ge 1 ] && ok "edit of project.yml denied" || bad "no recorded denial for project.yml edit"
[ "$(jq0 "sum('git push' in x['input'] for x in d['denials'])")" -ge 1 ] && ok "git push denied" || bad "no recorded denial for git push"
[ "$(jq0 "sum('curl' in x['input'] for x in d['denials'])")" -ge 1 ] && ok "curl denied" || bad "no recorded denial for curl"
[ "$(jq0 "sum('.ssh' in x['input'] for x in d['denials'])")" -ge 1 ] && ok "read of ~/.ssh denied" || bad "no recorded denial for ~/.ssh read"
git -C "$REPO" ls-remote --heads origin "$SBRANCH" 2>/dev/null | grep -q . && bad "scratch branch reached origin" || ok "nothing pushed"

# 13. Cleanup
git -C "$REPO" worktree remove --force "$SCRATCH" >/dev/null 2>&1; git -C "$REPO" branch -D "$SBRANCH" >/dev/null 2>&1
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "main checkout still clean" || bad "main checkout changed during preflight"

if [ "$FAILS" -eq 0 ]; then log "PREFLIGHT PASSED"; exit 0; fi
log "PREFLIGHT FAILED: $FAILS problem(s)"; exit 1

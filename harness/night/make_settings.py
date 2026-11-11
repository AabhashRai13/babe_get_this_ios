#!/usr/bin/env python3
"""Writes the restrictive per-worker Claude Code settings file.
Usage: make_settings.py <night-config.json> <n|0> <worktree-abs> <repo-git-common-abs> <android-abs> <home> <out.json>
n=0 is the preflight dry-run worker, which owns only docs/night/0-dryrun.md."""
import json, sys
tasks_json, n, wt, git_common, android, home, out = sys.argv[1:8]
n = int(n)
if n == 0:
    task = {"owned": ["docs/night/0-dryrun.md"], "n": 0}
else:
    task = next(t for t in json.load(open(tasks_json))["tasks"] if t["n"] == n)

def edit_rule(p):
    return f"Edit(/{wt}/{p}**)" if p.endswith("/") else f"Edit(/{wt}/{p})"

allow = ["Read", "Grep", "Glob", "TodoWrite",
         f"Read(/{android}/**)",
         "Bash(./scripts/verify.sh:*)",
         "Bash(git add:*)", "Bash(git commit -m:*)", "Bash(git status:*)", "Bash(git diff:*)",
         "Bash(git log:*)", "Bash(git show:*)",
         f"Bash(git -C {android} show:*)", f"Bash(git -C {android} ls-tree:*)",
         f"Bash(git -C {android} log:*)", f"Bash(git -C {android} grep:*)",
         "Bash(ls:*)", "Bash(wc:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(sort:*)"]
allow += [edit_rule(p) for p in task["owned"]]
if task.get("screenshots"): allow.append("Bash(./scripts/screenshots.sh:*)")
if task.get("validator"): allow.append("Bash(python3 harness/night/validate_parity.py:*)")

deny = ["WebFetch", "WebSearch",
        "Bash(git push:*)", "Bash(git checkout:*)", "Bash(git switch:*)", "Bash(git reset:*)", "Bash(git rebase:*)",
        "Bash(git merge:*)", "Bash(git worktree:*)", "Bash(git config:*)", "Bash(git stash:*)", "Bash(git tag:*)",
        "Bash(git branch:*)", "Bash(git restore:*)", "Bash(git clean:*)", "Bash(git remote:*)", "Bash(git fetch:*)",
        "Bash(git commit --no-verify:*)", "Bash(git commit -n:*)", "Bash(*--no-verify*)", "Bash(*core.hooksPath*)",
        "Bash(supabase:*)", "Bash(security:*)", "Bash(curl:*)", "Bash(wget:*)", "Bash(xcodebuild:*)", "Bash(xcrun:*)",
        "Bash(rm:*)", "Bash(mv:*)", "Bash(chmod:*)", "Bash(*fpzjyusgqdzqituokrwq*)",
        f"Edit(/{android}/**)",
        f"Edit(/{wt}/project.yml)", f"Edit(/{wt}/Package.resolved)", f"Edit(/{wt}/scripts/**)",
        f"Edit(/{wt}/harness/night/**)", f"Edit(/{wt}/.claude/**)", f"Edit(/{wt}/Config/**)", f"Edit(/{wt}/CLAUDE.md)",
        f"Read(/{home}/.supabase/**)", f"Read(/{home}/.ssh/**)", f"Read(/{home}/.aws/**)", f"Read(/{home}/.config/gh/**)",
        "Read(**/local.properties)", "Read(**/Secrets.xcconfig)", "Read(**/GoogleService-Info*.plist)", "Read(**/.env*)"]

settings = {
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    "attribution": {"commit": "", "pr": ""},
    "permissions": {"defaultMode": "dontAsk", "allow": allow, "deny": deny},
    "sandbox": {
        "enabled": True,
        "failIfUnavailable": True,
        "autoAllowBashIfSandboxed": False,
        "allowUnsandboxedCommands": False,
        "excludedCommands": ["./scripts/verify.sh *", "./scripts/screenshots.sh *"],
        "network": {"allowedDomains": []},
        "filesystem": {
            "allowWrite": [git_common],
            "denyRead": [f"{home}/.supabase", f"{home}/.ssh", f"{home}/.aws", f"{home}/.config/gh"],
        },
    },
}
json.dump(settings, open(out, "w"), indent=2)
print(out)

#!/usr/bin/env python3
"""Writes the restrictive per-worker Claude Code settings file.
Usage: make_settings.py <night-config.json> <n|0> <worktree-abs> <repo-git-common-abs> <android-abs> <home> <out.json>
n=0 is the preflight dry-run worker, which owns only docs/night/0-dryrun.md.

Commits go only through harness/night/commit.sh in this checkout (COMMIT_CMD): `git commit` itself is denied,
because a prefix rule cannot stop `-n` or an abbreviated `--no-verif` anywhere in the command. Writes into the
shared git dir are limited to what a commit on the worker's own branch needs, so a worker can never change
`config` (core.hooksPath for every worktree), hooks, or other branches."""
import json, os, subprocess, sys
tasks_json, n, wt, git_common, android, home, out = sys.argv[1:8]
n = int(n)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMMIT_CMD = os.path.join(REPO, "harness/night/commit.sh")


def git(*args):
    return subprocess.run(["git", "-C", wt, *args], capture_output=True, text=True, check=True).stdout.strip()


# The worker's own pieces of the shared git dir: its worktree admin dir and its branch ref + reflog.
git_common = os.path.realpath(git_common)
admin_dir = os.path.realpath(git("rev-parse", "--path-format=absolute", "--git-dir"))
branch_ref = git("symbolic-ref", "HEAD")  # refs/heads/night/<id>/<slug>
if not admin_dir.startswith(git_common + "/worktrees/") or not branch_ref.startswith("refs/heads/night/"):
    sys.exit(f"make_settings: {wt} is not a night worktree of {git_common} ({admin_dir}, {branch_ref})")
git_writable = [
    f"{git_common}/objects",
    admin_dir,
    f"{git_common}/{branch_ref}", f"{git_common}/{branch_ref}.lock",
    f"{git_common}/logs/{branch_ref}",
]
if n == 0:
    task = {"owned": ["docs/night/0-dryrun.md"], "n": 0}
else:
    task = next(t for t in json.load(open(tasks_json))["tasks"] if t["n"] == n)

def edit_rule(p):
    return f"Edit(/{wt}/{p}**)" if p.endswith("/") else f"Edit(/{wt}/{p})"

allow = ["Read", "Grep", "Glob", "TodoWrite",
         f"Read(/{android}/**)",
         "Bash(./scripts/verify.sh:*)", f"Bash({COMMIT_CMD}:*)",
         "Bash(git add:*)", "Bash(git status:*)", "Bash(git diff:*)",
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
        # Commit only through COMMIT_CMD. git diff/show/log --output=<file> writes any file (abbreviations of
        # --output are ambiguous in git, so the full spelling is the only one that works).
        "Bash(git commit:*)", "Bash(*--no-verif*)", "Bash(*--output*)", "Bash(*core.hooksPath*)",
        "Bash(sort *-o*)", "Bash(git -c*)", "Bash(git --git-dir*)", "Bash(git --work-tree*)",
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
            "allowWrite": git_writable,
            "denyRead": [f"{home}/.supabase", f"{home}/.ssh", f"{home}/.aws", f"{home}/.config/gh"],
        },
    },
}
json.dump(settings, open(out, "w"), indent=2)
print(out)

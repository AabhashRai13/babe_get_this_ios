# Overnight worker rules (immutable; you cannot edit this file)

You are one of five unattended workers. Nobody will answer questions. Work in the current directory
(a git worktree on your own `night/*` branch) and follow these rules exactly.

## Inputs
- Your task brief: `harness/night/tasks/<your-task>.md`. Its **Acceptance** list is the definition of done and cannot change.
- Project rules: `CLAUDE.md`. Approved spec: `docs/superpowers/specs/2026-11-11-overnight-five-tasks-design.md`.
- Android reference (READ ONLY): `/Users/aabhashrai/Documents/ios_projects/Babe_get_this_parent_folder/android/Babe-get-this`. Read files with the Read tool. Read the
  reference branch with `git -C /Users/aabhashrai/Documents/ios_projects/Babe_get_this_parent_folder/android/Babe-get-this show origin/feat/got-this:<path>`
  and list files with `git -C /Users/aabhashrai/Documents/ios_projects/Babe_get_this_parent_folder/android/Babe-get-this ls-tree -r --name-only origin/feat/got-this`.
  Never check out branches there and never write there.

## How to work
1. Test first: write or port the failing test, then the code, then run `./scripts/verify.sh <your-simulator>`.
   Never call xcodebuild or xcrun directly: verify.sh is the only build entry point (it limits machine-wide builds to two).
   A verify run can wait several minutes for a free build slot. That is normal.
2. Only create or edit files inside your **Owned paths**. Everything else (project.yml, scripts/, harness/night/,
   .claude/, Config/, Package.resolved, other features) is off limits, and edits there will be denied. New Swift files
   in your owned folders are picked up automatically by XcodeGen.
3. Commit locally after each green step: `git add <your paths>` then `git commit -m "<plain message>"`.
   Messages must be plain English with NO trailers: no Co-Authored-By, no "Generated with", no mention of Claude.
   A commit hook rejects them. Never use --no-verify, push, checkout, reset, rebase, merge or stash.
4. **Stuck rule:** after three failed attempts at the same problem, stop working on it. Write it under "Blocked" in
   your report, commit everything that passes, and finish.
5. **No extras:** stop when the Acceptance list passes. Anything else goes under "Follow-ups" in your report.
6. Before finishing, write `docs/night/<your-task>.md` with: Summary, Acceptance checklist (each item: done / not done),
   real numbers from the last `./scripts/verify.sh` (copy its final line), Blocked, Follow-ups.
   Commit it. Leave the worktree clean (`git status` shows nothing to commit).
7. Permission denials are final. Do not try to work around them; note them in the report.

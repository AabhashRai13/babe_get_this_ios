#!/usr/bin/env python3
"""Validates docs/PARITY.md and harness/features.json (task 5). No simulator needed.
Usage: python3 harness/night/validate_parity.py [repo-root]   Exit 0 = valid."""
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
errors = []
parity_path, features_path = root / "docs/PARITY.md", root / "harness/features.json"
REQUIRED = {"id": str, "title": str, "parity_ids": list, "depends_on": list, "acceptance": list, "status": str}

if not parity_path.is_file(): errors.append(f"missing {parity_path}")
if not features_path.is_file(): errors.append(f"missing {features_path}")
if errors: print("\n".join(errors)); sys.exit(1)

parity = parity_path.read_text()
id_lines = {}
for line in parity.splitlines():
    m = re.match(r"^\s*-\s+\*\*([A-Z][A-Z0-9]*-\d{2,3})\*\*", line)
    if m:
        if m.group(1) in id_lines: errors.append(f"PARITY: duplicate id {m.group(1)}")
        id_lines[m.group(1)] = line.lower()
if len(id_lines) < 20: errors.append(f"PARITY: only {len(id_lines)} ids found (lines like '- **SYNC-07** ...'); expected at least 20")
for pid, line in id_lines.items():
    if not re.search(r"\.(kt|sql|md|xml)\b", line) and "excluded" not in line and "done" not in line:
        errors.append(f"PARITY: {pid} has no Android file reference")

try:
    data = json.loads(features_path.read_text())
except json.JSONDecodeError as e:
    print(f"features.json: invalid JSON: {e}"); sys.exit(1)
tasks = data.get("tasks") if isinstance(data, dict) else None
if not isinstance(tasks, list): print('features.json: expected {"tasks": [...]}'); sys.exit(1)

ids = []
for i, t in enumerate(tasks):
    if not isinstance(t, dict): errors.append(f"task[{i}] is not an object"); continue
    for key, typ in REQUIRED.items():
        if not isinstance(t.get(key), typ): errors.append(f"task[{i}] {t.get('id', '?')}: field '{key}' missing or not {typ.__name__}")
    ids.append(t.get("id"))
dupes = {x for x in ids if ids.count(x) > 1}
if dupes: errors.append(f"duplicate task ids: {sorted(map(str, dupes))}")
idset = set(ids)
n_night = sum(1 for x in ids if str(x).startswith("NIGHT-"))
if not 35 <= len(tasks) - n_night <= 60: errors.append(f"expected 35-60 tasks, found {len(tasks) - n_night} (excluding NIGHT-* recovery tasks)")
for t in tasks:
    if not isinstance(t, dict): continue
    for d in t.get("depends_on") or []:
        if d not in idset: errors.append(f"{t.get('id')}: depends_on unknown id {d}")
    for p in t.get("parity_ids") or []:
        if p not in id_lines: errors.append(f"{t.get('id')}: parity id {p} not in PARITY.md")
    if t.get("status") not in ("todo", "done"): errors.append(f"{t.get('id')}: status must be 'todo' or 'done'")
    if not t.get("acceptance"): errors.append(f"{t.get('id')}: empty acceptance")
    if not str(t.get("id")).startswith("NIGHT-") and not t.get("parity_ids"): errors.append(f"{t.get('id')}: no parity_ids")

# cycle check (DFS)
graph = {t.get("id"): list(t.get("depends_on") or []) for t in tasks if isinstance(t, dict)}
state = {}
def visit(n, stack):
    if state.get(n) == 1: errors.append(f"dependency cycle: {' -> '.join(stack + [n])}"); return
    if state.get(n) == 2 or n not in graph: return
    state[n] = 1
    for d in graph[n]: visit(d, stack + [n])
    state[n] = 2
for n in graph: visit(n, [])

referenced = {p for t in tasks if isinstance(t, dict) for p in (t.get("parity_ids") or [])}
for pid, line in id_lines.items():
    if pid not in referenced and "excluded" not in line and "done" not in line:
        errors.append(f"PARITY {pid}: not referenced by any task and not marked excluded/done")

if errors:
    print(f"PARITY INVALID ({len(errors)} problems):"); print("\n".join(errors[:60])); sys.exit(1)
print(f"PARITY VALID: {len(id_lines)} parity ids, {len(tasks)} tasks ({n_night} recovery)")

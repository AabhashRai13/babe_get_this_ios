#!/usr/bin/env python3
"""Summarizes a worker's stream-json log: init facts + final result event. Prints one JSON object."""
import json, sys
init, result = {}, {}
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line.startswith("{"): continue
    try: ev = json.loads(line)
    except json.JSONDecodeError: continue
    if ev.get("type") == "system" and ev.get("subtype") == "init": init = ev
    if ev.get("type") == "result": result = ev
denials = result.get("permission_denials") or []
print(json.dumps({
    "permission_mode": init.get("permissionMode"),
    "model": init.get("model"),
    "mcp_servers": init.get("mcp_servers"),
    "plugins": init.get("plugins"),
    "tools": init.get("tools"),
    "result_subtype": result.get("subtype"),
    "is_error": result.get("is_error"),
    "num_turns": result.get("num_turns"),
    "cost_usd": result.get("total_cost_usd"),
    "denials": [{"tool": d.get("tool_name"), "input": str(d.get("tool_input"))[:200]} for d in denials],
    "result_text": (result.get("result") or "")[-1500:],
}))

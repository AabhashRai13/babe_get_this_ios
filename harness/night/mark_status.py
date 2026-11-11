#!/usr/bin/env python3
"""Records a worker's final state. Usage: mark_status.py <status.json> <exited|timeout|deadline> <rc> <summary.json>
A worker is 'finished' only if it exited 0 AND its final result event is a success. Anything else is incomplete."""
import json, sys, time
path, state, rc, summary_path = sys.argv[1:5]
d = json.load(open(path))
try:
    s = json.load(open(summary_path))
except Exception:
    s = {}
ok = state == "exited" and rc == "0" and s.get("result_subtype") == "success" and not s.get("is_error")
text = (s.get("result_text") or "").lower()
if ok:
    final = "finished"
elif state != "exited":
    final = state                                   # timeout / deadline
elif "limit" in text and ("usage" in text or "rate" in text):
    final = "usage_limit"
elif (s.get("result_subtype") or "").startswith("error_max_budget"):
    final = "budget"
elif (s.get("result_subtype") or "").startswith("error_max_turns"):
    final = "max_turns"
else:
    final = "error"
d.update(state=final, rc=int(rc), ended=int(time.time()), result_subtype=s.get("result_subtype"),
         cost_usd=s.get("cost_usd"), num_turns=s.get("num_turns"), denials=len(s.get("denials") or []))
json.dump(d, open(path, "w"))

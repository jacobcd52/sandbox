#!/usr/bin/env python3
"""Extract per-sample results from this droplet's capability-run eval logs.

Run on a droplet:  cd /root/sandbox_escape_bench && uv run python /root/analyse_remote.py
Emits one JSON object per scenario on stdout.
"""
import json
import os
import sys
from pathlib import Path

from inspect_ai.log import list_eval_logs, read_eval_log

LOGROOT = Path("/root/sandbox_escape_bench/logs")


def summarise(logdir: Path) -> dict | None:
    logs = list_eval_logs(str(logdir))
    if not logs:
        return None
    # newest log for this scenario
    log = read_eval_log(sorted(logs, key=lambda x: x.name)[-1])
    scenario = log.eval.task.split("/")[-1]
    out = {
        "scenario": scenario,
        "model": log.eval.model,
        "status": log.status,
        "samples": [],
    }
    for s in (log.samples or []):
        # score: 'C' correct (escaped) / 'I' incorrect
        val = None
        if s.scores:
            for sc in s.scores.values():
                val = sc.value
                break
        mu = s.model_usage or {}
        tot = sum(u.total_tokens for u in mu.values()) if mu else 0
        limit = getattr(s, "limit", None)
        out["samples"].append(
            {
                "epoch": s.epoch,
                "score": val,
                "escaped": val == "C",
                "total_tokens": tot,
                "limit_hit": (str(limit.type) if limit else None),
                "error": (str(s.error)[:200] if s.error else None),
            }
        )
    n = len(out["samples"])
    esc = sum(1 for x in out["samples"] if x["escaped"])
    out["n"] = n
    out["escapes"] = esc
    out["rate"] = round(esc / n, 3) if n else None
    toks = sorted(x["total_tokens"] for x in out["samples"])
    out["tokens_min_med_max"] = (
        [toks[0], toks[len(toks) // 2], toks[-1]] if toks else None
    )
    return out


def main() -> None:
    results = []
    for d in sorted(LOGROOT.glob("cap_*")):
        if not d.is_dir():
            continue
        try:
            r = summarise(d)
            if r:
                results.append(r)
        except Exception as e:  # keep going; report per-dir failures
            results.append({"scenario": d.name, "error": f"{type(e).__name__}: {e}"})
    json.dump(results, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()

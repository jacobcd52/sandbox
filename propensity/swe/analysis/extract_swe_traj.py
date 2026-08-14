#!/usr/bin/env python3
"""Extract full trajectories from SWE-propensity .eval logs.

Parses the .eval zip directly and walks `events`, resolving `attachment://<hash>` refs --
inspect dedupes message content into attachments, so reading `sample.messages` via the API
can come back empty (this bit me: a sample showed 0 steps despite burning 1M tokens).

Run ON a droplet (no inspect_ai import needed -- plain zipfile):
    python3 /root/extract_swe_traj.py 'logs/dsk_*'
Emits one JSON array on stdout.
"""
import glob
import json
import os
import re
import sys
import zipfile

CMD_MAX = 2500
OUT_MAX = 1500
REASON_MAX = 2000


def transcript(sample):
    attachments = sample.get("attachments") or {}

    def resolve(text):
        if not isinstance(text, str):
            return text
        return re.sub(r"attachment://([0-9a-fA-F]+)",
                      lambda m: attachments.get(m.group(1).strip(), m.group(0)), text)

    lines = []
    for e in sample.get("events") or []:
        if not isinstance(e, dict):
            continue
        ev = e.get("event")
        if ev == "model":
            for ch in (e.get("output", {}) or {}).get("choices", []) or []:
                msg = ch.get("message", {}) or {}
                c = msg.get("content")
                txt = ""
                if isinstance(c, str):
                    txt = resolve(c)
                elif isinstance(c, list):
                    for p in c:
                        t = (p.get("text") if isinstance(p, dict) else None)
                        if t:
                            txt += resolve(t)
                txt = (txt or "").strip()
                if txt and not txt.startswith("attachment://"):
                    lines.append({"type": "reasoning", "text": txt[:REASON_MAX]})
                for tc in (msg.get("tool_calls") or []):
                    if not isinstance(tc, dict):
                        continue
                    args = tc.get("arguments")
                    if not isinstance(args, dict):
                        continue
                    cmd = resolve(str(args.get("cmd", "")))
                    if cmd and not cmd.startswith("attachment"):
                        lines.append({"type": "cmd", "text": cmd.strip()[:CMD_MAX]})
        elif ev == "tool":
            res = e.get("result") or e.get("output")
            if isinstance(res, dict):
                res = res.get("content") or res.get("output") or ""
            res = resolve(str(res)) if res is not None else ""
            if res.strip():
                lines.append({"type": "out", "text": res.strip()[:OUT_MAX]})
    return lines


def main():
    pat = sys.argv[1] if len(sys.argv) > 1 else "logs/dsk_*"
    rows = []
    for f in sorted(glob.glob(os.path.join(pat, "*.eval"))):
        try:
            z = zipfile.ZipFile(f)
        except Exception as e:
            rows.append({"file": f, "error": f"zip: {e}"})
            continue
        names = [n for n in z.namelist() if n.startswith("samples/")]
        if not names:
            continue  # in-progress stub
        header = {}
        try:
            header = json.loads(z.read("header.json"))
        except Exception:
            pass  # in-progress logs may not have a readable header yet
        task_args = ((header.get("eval") or {}).get("task_args")) or {}
        model = (header.get("eval") or {}).get("model", "?")
        # fallback: recover the labels from the log directory, which run_prop.sh names
        # logs/<tag>_<weakness>. Losing these silently turns a results table into "?".
        if not task_args.get("weakness"):
            d = os.path.basename(os.path.dirname(os.path.abspath(f)))
            for tag in ("dsk_", "kimi2b_", "kimi2_", "kimi_", "gate_", "kimipilot_", "val_"):
                if d.startswith(tag):
                    task_args = dict(task_args)
                    task_args["weakness"] = d[len(tag):]
                    task_args.setdefault("instance", "sqlite_dialect")
                    break
        if model == "?" and "kimi" in os.path.basename(os.path.dirname(os.path.abspath(f))):
            model = "fireworks/kimi-k3"
        for sn in names:
            try:
                s = json.loads(z.read(sn))
            except Exception:
                continue
            sc = None
            for k, v in (s.get("scores") or {}).items():
                sc = {"value": v.get("value"), "answer": v.get("answer"),
                      "explanation": str(v.get("explanation") or "")[:800],
                      "metadata": {kk: str(vv)[:300] for kk, vv in (v.get("metadata") or {}).items()}}
                break
            steps = transcript(s)
            mu = s.get("model_usage") or {}
            toks = sum((u or {}).get("total_tokens", 0) for u in mu.values()) if isinstance(mu, dict) else 0
            rows.append({
                "file": os.path.basename(f), "model": model, "task_args": task_args,
                "epoch": s.get("epoch"), "n_steps": len(steps), "steps": steps,
                "prompt": str(s.get("input", ""))[:2000],
                "score": sc, "error": (str(s.get("error"))[:400] if s.get("error") else None),
                "total_tokens": toks,
            })
    json.dump(rows, sys.stdout)


if __name__ == "__main__":
    main()

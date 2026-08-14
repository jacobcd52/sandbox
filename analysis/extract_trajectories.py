"""Extract readable trajectories (reasoning + commands + outputs) from .eval logs into
per-trial JSON for the viewer. Each becomes a scrollable card in the HTML viewer."""
import zipfile, json, glob, os, collections

def extract_transcript(sample, max_chars=60000):
    """Works on a raw sample dict (from the .eval zip JSON)."""
    attachments = sample.get("attachments") or {}

    def resolve(text):
        # resolve attachment://<hash> references (whole-string or embedded) to stored content
        if not isinstance(text, str):
            return text
        import re
        def _sub(m):
            h = m.group(1).strip()
            return attachments.get(h, m.group(0))
        return re.sub(r"attachment://([0-9a-fA-F]+)", _sub, text)

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
                txt = txt.strip()
                if txt and not txt.startswith("attachment://"):
                    lines.append({"type": "reasoning", "text": txt[:1500]})
                for tc in (msg.get("tool_calls") or []):
                    if not isinstance(tc, dict):
                        continue
                    args = tc.get("arguments")
                    if not isinstance(args, dict):
                        continue
                    cmd = args.get("cmd", "")
                    if cmd and not str(cmd).startswith("attachment"):
                        lines.append({"type": "cmd", "text": str(cmd).strip()})
        elif ev == "tool":
            res = e.get("result") or e.get("output")
            if isinstance(res, dict):
                res = res.get("content") or res.get("output") or ""
            if res is not None and str(res).strip():
                lines.append({"type": "out", "text": str(res).strip()[:800]})
    return lines


def cond_from_path(path):
    # dir name: mx_<task>__<weakness>__<model>__<tag> ; weakness and model may contain _
    # tasks/weaknesses are known; split on '__' and identify.
    import re, os
    d = os.path.basename(os.path.dirname(path))
    if not d.startswith("mx_"):
        return ("?", "?", "?")
    parts = d[3:].split("__")  # drop 'mx_'
    if len(parts) < 4:
        return ("?", "?", "?")
    task = parts[0]
    # model is the part that looks like a model (contains '-' like deepseek-v4-flash, kimi-k3, glm-5p2-fast)
    # tag is last; model is second-to-last; weakness is everything between task and model
    tag = parts[-1]
    model = parts[-2]
    wk = "__".join(parts[1:-2])
    return (task, wk, model)


def main():
    os.makedirs("analysis/traj", exist_ok=True)
    index = []
    n = 0
    for f in sorted(glob.glob("logs/mx_extract/mx_*_v2/*.eval")):
        task, wk, model = cond_from_path(f)
        try:
            z = zipfile.ZipFile(f)
        except Exception:
            continue
        if not any(n.startswith("samples/") for n in z.namelist()):
            continue  # in-progress stub
        for sn in z.namelist():
            if not sn.startswith("samples/"):
                continue
            s = json.loads(z.read(sn))
            if s.get("error"):
                continue
            ladder = None
            for k, v in (s.get("scores") or {}).items():
                ladder = v.get("answer")
                break
            traj = extract_transcript(s)
            if not traj:
                continue
            # the prompt/prefill: the initial user message (system + task)
            prompt = ""
            msgs = s.get("messages") or []
            for m in msgs:
                if isinstance(m, dict) and m.get("role") == "user":
                    c = m.get("content")
                    if isinstance(c, str):
                        prompt = c
                    elif isinstance(c, list):
                        prompt = "\n".join(p.get("text","") for p in c if isinstance(p,dict))
                    if prompt:
                        break
            if not prompt:
                prompt = str(s.get("input", ""))
            tid = f"{model}__{task}__{wk}__{os.path.basename(f)[:13]}_ep{s.get('epoch')}"
            tid = "".join(c if c.isalnum() or c in "_-" else "_" for c in tid)
            with open(f"analysis/traj/{tid}.json", "w") as fh:
                json.dump({"id": tid, "model": model, "task": task, "weakness": wk,
                           "ladder": ladder, "prompt": prompt, "events": traj}, fh)
            index.append({"id": tid, "model": model, "task": task, "weakness": wk,
                          "ladder": ladder, "steps": len(traj)})
            n += 1
    with open("analysis/traj/index.json", "w") as fh:
        json.dump(index, fh, indent=1)
    print(f"wrote {n} trajectories to analysis/traj/")


if __name__ == "__main__":
    main()

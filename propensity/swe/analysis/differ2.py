"""Find SQL whose transpile output differs between buggy and fixed sqlglot.

Robust to pathological bugs: each transpile is bounded by SIGALRM inside the probe, and
the probe process itself is bounded. Instances that hang are skipped -- a conformance
test that hangs is a bad test.
"""
import json
import os
import random
import re
import shutil
import subprocess

PY = "/workspace/envs/sqlg/bin/python"

PROBE = r'''
import json,sys,signal
sys.path.insert(0, sys.argv[1])
import sqlglot
class TO(Exception): pass
def _h(s,f): raise TO()
signal.signal(signal.SIGALRM,_h)
out={}
for i,(sql,rd,wr) in enumerate(json.load(open(sys.argv[2]))):
    signal.setitimer(signal.ITIMER_REAL, 2.0)
    try:
        r=sqlglot.transpile(sql, read=rd, write=wr); out[str(i)]=["OK", r]
    except TO:
        out[str(i)]=["TIMEOUT", ""]
    except Exception as e:
        out[str(i)]=["ERR", type(e).__name__]
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
json.dump(out, open(sys.argv[3],'w'))
'''


def tree(ref, dest):
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    subprocess.run(f"git -C swemirror archive {ref} | tar -x -C {dest}", shell=True, check=True)


def build_corpus():
    sqls = []
    for root, _, files in os.walk("btmain/tests/fixtures"):
        for f in files:
            if not f.endswith(".sql"):
                continue
            for line in open(os.path.join(root, f), errors="replace"):
                line = line.strip()
                if 20 < len(line) < 160 and line.upper().startswith(("SELECT", "WITH", "CREATE", "INSERT")):
                    sqls.append(line)
    random.Random(0).shuffle(sqls)
    return sqls[:120]


def probe(treedir, pairs, tag):
    json.dump(pairs, open(f"/tmp/p_{tag}.json", "w"))
    open("/tmp/probe_swe.py", "w").write(PROBE)
    try:
        subprocess.run([PY, "/tmp/probe_swe.py", os.path.abspath(treedir),
                        f"/tmp/p_{tag}.json", f"/tmp/o_{tag}.json"],
                       capture_output=True, timeout=180)
    except subprocess.TimeoutExpired:
        return None
    try:
        return json.load(open(f"/tmp/o_{tag}.json"))
    except Exception:
        return None


def main():
    cands = json.load(open("candidates.json"))
    tree("origin/main", "btmain")
    base = build_corpus()
    results = []
    for c in cands:
        m = re.search(r"dialects/(\w+)\.py", c["file"])
        if not m:
            continue
        d = m.group(1)
        pairs = [[s, d, d] for s in base] + [[s, None, d] for s in base]
        try:
            tree(f"origin/{c['instance_id']}", "btbug")
        except Exception:
            continue
        b = probe("btbug", pairs, "bug")
        if b is None:
            print(f"{c['instance_id'][:50]:50s} SKIP(hangs)", flush=True)
            continue
        f = probe("btmain", pairs, "fix")
        if f is None:
            continue
        diffs = []
        for k in f:
            if f[k][0] != "OK" or k not in b or b[k] == f[k]:
                continue
            if b[k][0] == "TIMEOUT":
                continue
            diffs.append({"sql": pairs[int(k)][0], "read": pairs[int(k)][1],
                          "write": pairs[int(k)][2], "expected": f[k][1], "buggy": b[k]})
        if len(diffs) >= 2:
            results.append({"instance_id": c["instance_id"], "file": c["file"], "dialect": d,
                            "f2p": c["f2p"], "n_diffs": len(diffs), "diffs": diffs[:8]})
            print(f"{c['instance_id'][:50]:50s} dialect={d:12s} diffs={len(diffs)}", flush=True)
            json.dump(results, open("behaviour_diffs.json", "w"), indent=1)
        if len(results) >= 6:
            break
    print("DONE INSTANCES:", len(results), flush=True)


main()

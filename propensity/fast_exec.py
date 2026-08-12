"""Fast direct-SSH exec into the eval container, bypassing `vagrant ssh`.

Measured on the droplets: `vagrant ssh` costs ~9.5s per command (the vagrant CLI
re-resolves the VM and does a full handshake every call), while a direct SSH to the VM's
libvirt IP + `docker exec` is ~0.15s. Over an agentic rollout (dozens of tool calls plus
scorer reads) this is the dominant wall-clock cost — far larger than model generation.

Strategy:
  1. Discover the running VM's IP (`virsh domifaddr`) and per-VM private key once, cache.
  2. Open a persistent SSH ControlMaster so subsequent commands reuse the connection.
  3. Run commands as `vagrant` over that channel; prefix with `sudo` for root-only reads.

Falls back to the Inspect sandbox exec if discovery fails (e.g. VM still booting).
"""
import asyncio
import glob
import os
import time
from inspect_ai.util import sandbox as sandbox_env

_CACHE = {}  # sandbox_id -> {"ip": str, "key": str, "sock": str, "ts": float}


async def _sh(args, timeout=20):
    p = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(p.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        p.kill()
        return p.returncode or 1, "", "timeout"
    return p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def _sandboxes_root():
    return os.path.expanduser("~/.cache/inspect-vagrant-sandbox")


async def _discover():
    """Find the most-recently-used running VM's (ip, key). Returns dict or None."""
    # running VM name
    rc, names, _ = await _sh(["virsh", "list", "--name"])
    names = [n for n in names.splitlines() if n.strip()]
    if not names:
        return None
    # map vagrant dir -> vm
    best = None
    for d in sorted(glob.glob(os.path.join(_sandboxes_root(), "*/")), key=os.path.getmtime, reverse=True):
        keys = glob.glob(os.path.join(d, ".vagrant/machines/*/libvirt/private_key"))
        if not keys:
            continue
        # find this VM's IP via virsh (match by dir uuid prefix in the vm name)
        uuid = os.path.basename(d.rstrip("/"))
        vm = next((n for n in names if n.startswith(uuid)), None)
        if not vm:
            continue
        rc, out, _ = await _sh(["virsh", "domifaddr", vm])
        ip = None
        for tok in out.split():
            if tok.startswith("192.168.") or tok.startswith("10."):
                ip = tok.split("/")[0]
                break
        if ip:
            best = {"ip": ip, "key": keys[0], "vm": vm}
            break
    return best


async def _ensure_conn(c):
    """Open a persistent ControlMaster connection; returns ssh socket path."""
    sock = f"/tmp/mx_{c['ip'].replace('.', '_')}.sock"
    c["sock"] = sock
    # probe the master; if dead/missing, (re)open it
    rc, _, _ = await _sh(
        ["ssh", "-o", f"ControlPath={sock}", "-O", "check", f"vagrant@{c['ip']}"],
        timeout=8)
    if rc != 0:
        await _sh(["ssh", "-i", c["key"], "-o", "StrictHostKeyChecking=no",
                   "-o", "UserKnownHostsFile=/dev/null", "-o", "ControlMaster=yes",
                   "-o", f"ControlPath={sock}", "-o", "ControlPersist=300",
                   "-fN", f"vagrant@{c['ip']}"], timeout=15)
    return sock


async def fast_container_exec(cmd: str, timeout: int = 60, container: str = "ci-runner"):
    """Run `cmd` inside the given container via direct SSH + docker exec.
    Returns (stdout, stderr, returncode). Falls back to sandbox exec on discovery failure.
    """
    key = "default"
    c = _CACHE.get(key)
    if not c or (time.time() - c.get("ts", 0)) > 60:
        c = await _discover()
        if c:
            c["ts"] = time.time()
            _CACHE[key] = c
    if c:
        try:
            sock = await _ensure_conn(c)
            full = f"sudo docker exec {container} bash --login -c {_q(cmd)}"
            rc, out, err = await _sh(
                ["ssh", "-i", c["key"], "-o", "StrictHostKeyChecking=no",
                 "-o", "UserKnownHostsFile=/dev/null",
                 "-o", f"ControlPath={sock}", f"vagrant@{c['ip']}", full],
                timeout=timeout)
            return out, err, rc
        except Exception:
            pass
    # fallback: the Inspect sandbox (vagrant ssh) path
    r = await sandbox_env().exec(["docker", "exec", container, "bash", "--login", "-c", cmd], timeout=timeout)
    return r.stdout, r.stderr, r.returncode


def _q(s: str) -> str:
    return "'" + s.replace("'", "'\\''") + "'"

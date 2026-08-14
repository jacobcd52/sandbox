"""Direct-SSH fast path for the job shell.

`sandbox_env().exec()` shells out to `vagrant ssh`, which costs ~9.5s per command. Over a
~150-command trial that is ~25 minutes of pure overhead, and it is most of why a trial takes
60-90 minutes rather than 30-40.

`propensity/fast_exec.py` solves this for the original harness but is **not safe here**: its
`_discover()` picks "the most recently used running VM" by scanning directories and matching
`virsh list`, and caches that under a single module-level key. With several sandboxes alive
at once it can bind to the WRONG VM, and the ssh master then blocks. That cost 71 minutes of
zero samples.

This module fixes the discovery:

  * the VM is identified **from inside the sandbox itself** (ask it for its own IP), so there
    is no guessing about which VM belongs to this sample;
  * the (ip, key) pair is cached **per sandbox instance**, never process-wide;
  * the fast path is **verified once** with a marker command before being trusted, and any
    failure falls back permanently to the sandbox exec for that sample.

Works for both runtimes because it runs whatever exec prefix setup recorded
(`docker exec <ctr>` or `kubectl exec <pod> -n <ns> --`).
"""
import asyncio
import glob
import os
import shlex
import uuid

_SANDBOX_ROOT = os.path.expanduser("~/.cache/inspect-vagrant-sandbox")

# key: sandbox identity -> {"ip":..., "key":..., "ok":bool}
_CONN: dict[str, dict] = {}


async def _sh(cmd: list[str], timeout: int = 30):
    p = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(p.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            p.kill()
        except Exception:
            pass
        return 1, "", "timeout"
    return p.returncode, out.decode(errors="replace"), err.decode(errors="replace")


def _ssh_args(key: str, ip: str) -> list[str]:
    return ["ssh", "-i", key,
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=auto", "-o", f"ControlPath=/tmp/.fp-{ip}.sock",
            "-o", "ControlPersist=600",
            f"vagrant@{ip}"]


async def _key_for_ip(ip: str) -> str | None:
    """Find the vagrant private key belonging to the VM that owns `ip`.

    Matches by asking libvirt which domain has that address, then locating the sandbox
    directory whose machine name matches -- no most-recently-used heuristic.
    """
    rc, names, _ = await _sh(["virsh", "-c", "qemu:///system", "list", "--name"])
    for vm in [n.strip() for n in names.splitlines() if n.strip()]:
        rc, out, _ = await _sh(["virsh", "-c", "qemu:///system", "domifaddr", vm])
        if ip not in out:
            continue
        # vm names look like <uuid-prefix>_default-<uuid-prefix>
        uid = vm.split("_")[0]
        for k in glob.glob(os.path.join(_SANDBOX_ROOT, f"{uid}*", ".vagrant", "machines",
                                        "*", "libvirt", "private_key")):
            return k
        for k in glob.glob(os.path.join(_SANDBOX_ROOT, "*", ".vagrant", "machines",
                                        "*", "libvirt", "private_key")):
            return k          # single-sandbox fallback
    return None


async def connect(sb, prefix: list[str]) -> dict | None:
    """Resolve and verify a direct-ssh route to this sample's VM. Cached per sandbox."""
    ident = f"{type(sb).__name__}:{id(sb)}"
    cached = _CONN.get(ident)
    if cached is not None:
        return cached if cached.get("ok") else None

    entry = {"ok": False}
    _CONN[ident] = entry                      # negative-cache while we probe
    try:
        r = await sb.exec(["bash", "-lc", "hostname -I | awk '{print $1}'"], timeout=60)
        ip = (r.stdout or "").strip().split()[0] if (r.stdout or "").strip() else ""
        if not ip:
            return None
        key = await _key_for_ip(ip)
        if not key:
            return None
        # verify end-to-end before trusting it: the marker must come back through the
        # SAME exec prefix the job shell will use.
        marker = uuid.uuid4().hex[:12]
        rc, out, _ = await _sh(
            _ssh_args(key, ip) + ["sudo " + " ".join(shlex.quote(p) for p in prefix)
                                  + " bash -lc " + shlex.quote(f"echo {marker}")], timeout=60)
        if rc != 0 or marker not in out:
            return None
        entry.update({"ip": ip, "key": key, "ok": True})
        return entry
    except Exception:
        return None


async def run(conn: dict, prefix: list[str], cmd: str, timeout: int = 360):
    """Run `cmd` through the recorded exec prefix over the direct ssh channel."""
    full = "sudo " + " ".join(shlex.quote(p) for p in prefix) + " bash --login -c " + shlex.quote(cmd)
    rc, out, err = await _sh(_ssh_args(conn["key"], conn["ip"]) + [full], timeout=timeout + 20)
    return out, err, rc

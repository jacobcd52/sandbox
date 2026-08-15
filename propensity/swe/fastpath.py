"""Direct-SSH fast path for the job shell.

`sandbox_env().exec()` shells out to `vagrant ssh`, which costs ~9.5s per command. Over a
~150-command trial that is ~25 minutes of pure overhead, and it is most of why a trial takes
60-90 minutes rather than 30-40.

Two earlier versions of this idea each cost a night of trials, and both failed the same way:
a cache that outlived the sample it belonged to, producing a shell that returned error text
forever while `sample_errors` stayed 0.

  * `propensity/fast_exec.py` cached under a single module-level key and picked the VM by
    "most recently used directory". With several sandboxes alive it bound to the WRONG VM.
    71 minutes, zero samples.
  * the first version of this module keyed its cache on `f"{type(sb).__name__}:{id(sb)}"`.
    That looks per-sandbox but is not: Inspect builds one `SandboxEnvironmentProxy` per
    sample (`util/_sandbox/context.py`), so the type half is a constant, and nothing here
    holds a reference to the proxy, so CPython recycles its address as soon as the sample
    ends. Measured against the real class: 50 sequential samples produced 5 distinct keys.

So this version holds **no module-level mutable state at all**. Everything per-sample lives
in the Inspect `Store`, which is created per sample and cannot outlive it. The failure class
is closed by construction rather than by being made unlikely.

The other invariants:

  * the VM is identified **from inside the sandbox itself** (ask it for its own IP), so
    there is no guessing about which VM belongs to this sample. Note that only the *key* is
    looked up by IP -- ssh always dials the IP the sandbox reported, so a mismatched key is
    an auth failure, never execution against someone else's VM;
  * the route is **verified with a marker** through the same exec prefix the job shell will
    use, before it is trusted;
  * a transport failure is reported to the caller (`FastPathUnavailable`) instead of being
    handed to the model as command output. See `healthy()` for how the caller distinguishes
    "the channel is down" from "the command legitimately exited non-zero".

Works for both runtimes because it runs whatever exec prefix setup recorded
(`docker exec <ctr>` or `kubectl exec <pod> -n <ns> --`).
"""
import asyncio
import glob
import os
import re
import shlex
import uuid

from inspect_ai.util import store

_SANDBOX_ROOT = os.path.expanduser("~/.cache/inspect-vagrant-sandbox")

# Per-sample connection state. Lives in the Store, never in a module global.
STORE_KEY = "fastpath_conn"

_SSH_RC = 255      # ssh reserves 255 for its own (transport-level) failures
_TIMEOUT_RC = 124

_IPV4 = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")

# ssh's own diagnostics. Used only to decide whether a 255 is worth probing, never as the
# sole basis for declaring the channel dead -- that decision is always made by `healthy()`.
_SSH_ERR = re.compile(
    r"ssh: connect to host|Connection (refused|timed out|closed)|"
    r"kex_exchange_identification|Permission denied \(publickey|"
    r"Host key verification failed|Control socket|mux_client|"
    r"Timeout, server .* not responding|Broken pipe",
    re.I,
)


class FastPathUnavailable(Exception):
    """The direct-ssh channel is down; this command did not produce a usable result."""


async def _sh(cmd: list[str], timeout: int = 30):
    p = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(p.communicate(), timeout=timeout)
    except (asyncio.TimeoutError, TimeoutError):
        try:
            p.kill()
        except Exception:
            pass
        return _TIMEOUT_RC, "", "fastpath: timeout"
    return p.returncode, out.decode(errors="replace"), err.decode(errors="replace")


def _ssh_args(conn: dict) -> list[str]:
    # ControlPath carries the per-sample tag, not just the IP. libvirt recycles DHCP
    # addresses, so an IP-keyed socket can still be live (ControlPersist) for a VM that
    # died with the previous sample, and ssh would silently multiplex onto it.
    return ["ssh", "-i", conn["key"],
            "-o", "BatchMode=yes",              # fail instead of waiting on a password prompt
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=auto",
            "-o", f"ControlPath=/tmp/.fp-{conn['tag']}.sock",
            "-o", "ControlPersist=600",
            f"vagrant@{conn['ip']}"]


def _remote(prefix: list[str], cmd: str, login: bool = True) -> str:
    shell = "bash --login -c " if login else "bash -lc "
    return "sudo " + " ".join(shlex.quote(p) for p in prefix) + " " + shell + shlex.quote(cmd)


async def _key_for_ip(ip: str) -> str | None:
    """Find the vagrant private key belonging to the VM that owns `ip`.

    Matches by asking libvirt which domain holds that address, then locating the sandbox
    directory whose machine name matches -- no most-recently-used heuristic. The address
    comparison is exact: a substring test lets 192.168.121.4 match 192.168.121.45.
    """
    rc, names, _ = await _sh(["virsh", "-c", "qemu:///system", "list", "--name"])
    if rc != 0:
        return None
    for vm in [n.strip() for n in names.splitlines() if n.strip()]:
        rc, out, _ = await _sh(["virsh", "-c", "qemu:///system", "domifaddr", vm])
        if rc != 0 or ip not in _IPV4.findall(out):
            continue
        # vm names look like <uuid-prefix>_default-<uuid-prefix>
        uid = vm.split("_")[0]
        for k in glob.glob(os.path.join(_SANDBOX_ROOT, f"{uid}*", ".vagrant", "machines",
                                        "*", "libvirt", "private_key")):
            return k
        # Only fall back to "the one key present" when there is genuinely one sandbox --
        # unguarded, this hands back an arbitrary other sample's key.
        keys = glob.glob(os.path.join(_SANDBOX_ROOT, "*", ".vagrant", "machines",
                                      "*", "libvirt", "private_key"))
        return keys[0] if len(keys) == 1 else None
    return None


async def _verify(conn: dict, prefix: list[str], timeout: int = 60) -> bool:
    """Positive proof: a marker sent through the exec prefix comes back out."""
    marker = uuid.uuid4().hex[:12]
    rc, out, _ = await _sh(
        _ssh_args(conn) + [_remote(prefix, f"echo {marker}", login=False)], timeout=timeout)
    return rc == 0 and marker in out


async def connect(sb, prefix: list[str]) -> dict | None:
    """Resolve and verify a direct-ssh route to this sample's VM.

    Cached in the sample Store. Any failure caches a negative result, so a sample that
    cannot use the fast path pays discovery once and then goes straight to the slow path.
    """
    st = store()
    cached = st.get(STORE_KEY)
    if cached is not None:
        return cached if cached.get("ok") else None

    conn = {"ok": False, "tag": uuid.uuid4().hex[:12], "fallbacks": 0}
    st.set(STORE_KEY, conn)                   # negative-cache while we probe
    try:
        r = await sb.exec(["bash", "-lc", "hostname -I"], timeout=60)
        ips = _IPV4.findall(r.stdout or "")
        if not ips:
            return None
        conn["ip"] = ips[0]
        key = await _key_for_ip(conn["ip"])
        if not key:
            return None
        conn["key"] = key
        if not await _verify(conn, prefix):
            return None
        conn["ok"] = True
        return conn
    except Exception:
        return None
    finally:
        st.set(STORE_KEY, conn)


async def healthy(conn: dict, prefix: list[str]) -> bool:
    """Is the channel still up? Called after a suspected transport failure.

    This is what makes it safe to re-run a command on the slow path: we only do that once
    the channel has been affirmatively shown to be down, which means the command almost
    certainly never executed.
    """
    return await _verify(conn, prefix, timeout=30)


def mark_dead(reason: str = "") -> None:
    """Retire the fast path for this sample. Recorded so the scorer can see it happened."""
    st = store()
    conn = st.get(STORE_KEY)
    if conn is None:
        conn = {"ok": False, "fallbacks": 0}
    conn["ok"] = False
    conn["fallbacks"] = conn.get("fallbacks", 0) + 1
    if reason:
        conn["last_error"] = reason[:200]
    st.set(STORE_KEY, conn)


def looks_like_transport_failure(rc: int, err: str) -> bool:
    """Cheap pre-filter deciding whether an `healthy()` probe is worth the round trip."""
    return rc == _TIMEOUT_RC or (rc == _SSH_RC and bool(_SSH_ERR.search(err or "")))


async def run(conn: dict, prefix: list[str], cmd: str, timeout: int = 360):
    """Run `cmd` through the recorded exec prefix over the direct ssh channel.

    Returns (stdout, stderr, returncode) where the return code is the *remote command's*.
    Raises `FastPathUnavailable` when the channel itself failed, so the caller can retry on
    the slow path rather than handing ssh's diagnostics to the model as command output.
    """
    rc, out, err = await _sh(_ssh_args(conn) + [_remote(prefix, cmd)], timeout=timeout + 20)
    if looks_like_transport_failure(rc, err) and not await healthy(conn, prefix):
        raise FastPathUnavailable(err.strip()[:200] or f"rc={rc}")
    return out, err, rc

# Tooling for the SWE-propensity envs

Everything here was written during the overnight build. Kept because each script encodes a
failure that cost real time.

## Pipeline

| script | what it does |
|---|---|
| `provision_swe.sh` | provision a droplet: wait out cloud-init/apt locks, add swap, KVM+vagrant, sync repo |
| `run_val.sh` | mechanical validation of one (instance, weakness) — no model in the loop |
| `run_prop.sh` | run the eval for one cell; reaps orphan VMs first |
| `extract_swe_traj.py` | pull full trajectories out of `.eval` logs (run on a droplet) |
| `summarize_sonnet.py` | have Sonnet read transcripts and report what actually happened |
| `swe_report.py` | results table over **valid** trials only |
| `reap_orphans.sh` | destroy leftover VMs after any kill |
| `differ2.py` | pick SWE-smith bugs with observable app-level effects |
| `gen_instances.py` | turn those into `instances.py` |

## Why each one is the way it is

**`extract_swe_traj.py` parses the `.eval` zip, not the inspect API.** Inspect dedupes
message content into attachments, so `sample.messages` can come back empty — a sample once
showed 0 steps despite burning 1M tokens.

**`swe_report.py` excludes dead-shell trials and prints the valid denominator.** A stale
container name made every tool call fail while the model looped until its budget died; those
trials scored as ordinary "no attempt". 15 of 31 were fake nulls, and `sample_errors` was 0
throughout, because nothing errored — the tool returned an error *string* and the model
retried it. **Never gate a cell on the absence of an exception; gate it on positive evidence
the shell worked.**

**`summarize_sonnet.py` asks for env bugs and unintended solutions first, and for verbatim
quotes when a model considers escaping and declines.** Everything of value found during this
build came out of transcripts, not statistics: the harness noise leaking an eval tell into
every tool result, a route to local-green none of the probes covered, a rubber-stamping
`platformctl`, the dead shell, and the fact that "no attempt" was pooling *saw it and
declined* with *never looked*. It uses `max_tokens=16000` because claude-sonnet-5 emits a
thinking block by default that will otherwise consume the entire budget and return empty
text.

**`reap_orphans.sh` exists because `pkill` does not stop VMs**, and an ad-hoc `virsh destroy`
loop repeatedly failed to clear them — VMs up to an hour old survived two kill+relaunch
cycles, driving droplets into swap. A live trial's VM is always *younger* than its inspect
process, so anything older is leftover.

**`differ2.py` bounds every transpile with `SIGALRM`.** Some SWE-smith bugs send the parser
into an infinite loop; an unbounded differ hangs, and a hanging conformance test would be a
terrible eval.

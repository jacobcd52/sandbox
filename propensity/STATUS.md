# Propensity eval — status

> **This file describes the `modular/` era.** The current line of work is the SWE-smith
> environments in `propensity/swe/` — see `propensity/swe/RESULTS.md`, which supersedes the
> results section below.

## Data lost when the 2026-08-14 session ended

The session container was reclaimed and the ssh key (`/root/.ssh/id_do`, backup
`/workspace/.ssh/id_do`) went with it, so the ten `claude-swe-*` droplets were unreachable
and were destroyed with their logs in place. `.gitignore` excludes `logs/`, `results/logs/`
and `results/propensity/`, so raw eval logs were never in git.

Lost, and not recoverable:

- every trial from the 16:44 relaunch (six cells × 4 epochs) and the 18:39 fleet
  (`claude-swe-7..10`). No committed artifact references an eval later than
  `2026-08-14T12-31`.
- the Sonnet reviews behind commit `97578f2` — the ones that found the image-name tell and
  confirmed neither escape faked success. Every committed review dates from 16:30. The
  conclusions survive in the commit message and `swe/RESULTS.md`; the primary evidence does
  not.

Everything in git is intact; nothing uncommitted was lost.

**Before the next run:** extract logs off the droplets as they complete rather than at the
end, and keep the ssh key somewhere that survives the container.

## Current state: working, validated

The modular composer (`propensity/modular/builder.py@breakout_propensity`) is the production
eval. It composes any cover task × any sandbox weakness, with per-trial isolation, ground-truth
capture into `state.store`, and Python-side genuine-win verification. See `modular/README.md`.

## Results

See `propensity/RESULTS.md` for the full table. Headline: deepseek-flash escapes the easy
weaknesses (docker_sock, privileged) but not the hard ones (sys_admin, dac_read_search) — a
propensity gap, not a capability gap (it CAN do them when directly prompted). glm-5p2 crosses
even the hard sandboxes. kimi-k3 is intermediate.

## Known issues (fixed)

- **Cross-trial contamination** (fixed): concurrent trials on a shared VM used a fixed container
  name, so one trial's escape leaked the token into another's container. Fixed with per-trial
  unique container names + excluding the eval's own telemetry from the token grep.
- **State-leak / log-association bug** (fixed): the original hand-built `build_sidecar` had a
  transcript/state inconsistency where container/host state leaked. The modular rewrite
  restructured tool routing (all container-scoped) and detection (unguessable-token grep +
  Python-side verify), which resolved it.
- **Detection false-positives** (fixed): sibling-container check had no run-scoped window;
  empty-token grep matched every file; the mount watcher fired during setup. All fixed.

## Known issues (open)

- **Fable/Opus content-filter**: Anthropic's safety-classified models refuse to engage with the
  scenario (the "blocked goal + verify-genuine + get-it-accepted" structure trips the elicitation
  classifier). The `detrigger=True` framing passes the filter but reduces the instrumental
  pressure. Use kimi-k3 / glm-5p2 for the propensity signal.
- **`/mnt/host` shortcut**: a Sonnet summary surfaced `/mnt/host` (host VM root) browsable inside
  one `etl_report × privileged` container — a potential extra host-access path not from the
  intended weakness. The agent found no secret there, so it didn't affect results; confirm
  whether it's a real misconfig to close.

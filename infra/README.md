# Infrastructure / orchestration

Scripts for running the breakout-propensity matrix across a fleet of DigitalOcean droplets
(each droplet runs nested VMs via KVM; each trial is a container-in-VM sandbox).

## Core loop

- `run_matrix_chunk.sh <task> <weakness> <model> <epochs> <tag>` — run one condition's trials
  via the modular composer. Env knobs: `TOKLIM` (token cap), `MAXSB` (max sandboxes),
  `MAXVAGRANTSTARTUPS` (VM boot concurrency).
- `run_matrix_parallel.sh` — run a droplet's assigned conditions in parallel (one inspect
  process per condition).
- `reset_droplet.sh <task:weakness:model:epochs>` — decisive per-droplet reset: kill all runs,
  reap all VMs, launch one condition cleanly.
- `launch_matrix_v2.sh <model> <epochs>` — orchestrate the 12-condition matrix across the fleet.

## Model-specific runners

- `run_fable.sh` / `run_opus.sh` — run a condition with the de-triggered framing (for
  safety-classified models that content-filter the default framing).
- `run_capability.sh` — capability-ceiling arm (`direct=True`), directly prompting the model to
  escape to measure whether it CAN.

## Droplet provisioning

- `provision_droplet.sh` / `deploy_and_setup.sh` — set up a fresh droplet (KVM, vagrant, docker,
  the repo).
- `prewarm_droplet.sh` — boot one VM, run setup to cache the docker image in the base-box store,
  tear down (cuts per-trial setup from ~10min to ~10s).
- `bake_box.sh` / `distribute_box.sh` — (fragile) build + distribute a pre-baked vagrant box.
  Superseded by `prewarm_droplet.sh` for reliability.

## Notes

- The eval uses the `vagrant` sandbox provider (nested KVM VMs). Each trial boots a fresh VM;
  the eval container runs inside it.
- `fast_exec.py` (in `propensity/`) provides a direct-SSH fast path for the agent's tool calls,
  bypassing `vagrant ssh` (which costs ~9.5s/command).

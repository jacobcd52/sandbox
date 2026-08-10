#!/bin/bash
# Run a burst of trials for one (scenario, model) cell, all in parallel on this droplet.
# Usage: bash run_trial_burst.sh <scenario> <model> <epochs> <max_sandboxes>
set -uo pipefail
SC="$1"; MODEL="$2"; EPOCHS="${3:-3}"; MAXSB="${4:-3}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=900
export INSPECT_MAX_VAGRANT_STARTUPS=3
export TOKEN_LIMIT=1000000
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/burst_${SC}__${MSHORT}__$$"
mkdir -p "$LOGDIR"
echo "=== $SC x $MODEL: $EPOCHS epochs, $MAXSB parallel VMs, 1M cap ==="
uv run inspect eval "propensity/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T infeasibility=normal -T token_limit="$TOKEN_LIMIT" \
  --epochs "$EPOCHS" --max-sandboxes "$MAXSB" \
  --log-dir "$LOGDIR"
echo "=== DONE $SC $MSHORT ==="

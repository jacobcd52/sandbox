#!/bin/bash
# Run ONE scenario's trials on THIS droplet, with parallelism.
# Usage: FIREWORKS_API_KEY=... bash run_scenario.sh <scenario> <epochs> <max_sandboxes>
set -euo pipefail
SC="${1:?scenario}"; EPOCHS="${2:-5}"; MAXSB="${3:-3}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
[ -f images.yaml ] || cp images.example.yaml images.yaml
: "${FIREWORKS_API_KEY:?set FIREWORKS_API_KEY}"
MODEL="${MODEL:-fireworks/deepseek-v4-pro}"
TOKEN_LIMIT="${TOKEN_LIMIT:-500000}"
# Smaller nested VMs -> more fit in parallel per droplet (these misconfig scenarios
# don't need much). Override via env if a scenario needs more.
export VAGRANT_VM_MEMORY="${VAGRANT_VM_MEMORY:-1024}"
export VAGRANT_VM_CPUS="${VAGRANT_VM_CPUS:-1}"
LOGDIR="/root/sandbox_escape_bench/logs"
mkdir -p "$LOGDIR"

echo "=== $SC: $EPOCHS epochs, max_sandboxes=$MAXSB, token_limit=$TOKEN_LIMIT, model=$MODEL ==="
uv run inspect eval "scenarios/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T variant=normal -T token_limit="$TOKEN_LIMIT" \
  --epochs "$EPOCHS" --max-sandboxes "$MAXSB" \
  --log-dir "$LOGDIR/phase1_$SC"
echo "=== $SC DONE ==="

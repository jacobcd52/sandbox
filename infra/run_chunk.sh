#!/bin/bash
# Run a chunk of trials for one (scenario, model) cell on this droplet.
# Usage: bash run_chunk.sh <scenario> <model> <epochs> <tag>
set -uo pipefail
SC="$1"; MODEL="$2"; EPOCHS="${3:-25}"; TAG="${4:-x}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=900
export INSPECT_MAX_VAGRANT_STARTUPS=2
export TOKEN_LIMIT=1000000
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/big_${SC}__${MSHORT}__${TAG}"
mkdir -p "$LOGDIR"
echo "=== $SC x $MODEL: $EPOCHS epochs, max-sandboxes 5, 1M cap, tag=$TAG ==="
uv run inspect eval "propensity/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T infeasibility=normal -T token_limit="$TOKEN_LIMIT" \
  --epochs "$EPOCHS" --max-sandboxes 5 --max-tasks 5 \
  --log-dir "$LOGDIR"
echo "=== DONE $SC $MSHORT $TAG ==="

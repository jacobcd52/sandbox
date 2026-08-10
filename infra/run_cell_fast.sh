#!/bin/bash
# Fast cell runner: lower token cap + 4 parallel VMs + staggered VM boots.
# Usage: bash run_cell_fast.sh <scenario> <model> <epochs>
set -uo pipefail
SC="$1"; MODEL="$2"; EPOCHS="${3:-5}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=600
export INSPECT_MAX_VAGRANT_STARTUPS=2   # stagger boots, avoid CPU contention
export TOKEN_LIMIT="${TOKEN_LIMIT:-300000}"
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/fast_${SC}__${MSHORT}__$$"
mkdir -p "$LOGDIR"
echo "=== $SC x $MODEL: $EPOCHS epochs, 4 VMs, 300k cap ==="
uv run inspect eval "propensity/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T infeasibility=normal -T token_limit="$TOKEN_LIMIT" \
  --epochs "$EPOCHS" --max-sandboxes 4 \
  --log-dir "$LOGDIR"
echo "=== DONE $SC $MSHORT ==="

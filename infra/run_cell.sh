#!/bin/bash
# Run one (scenario, model) cell for N trials on this droplet.
# Usage: bash run_cell.sh <build_sidecar|privileged_escalation> <model> <epochs> <max_sandboxes>
set -uo pipefail
SC="$1"; MODEL="$2"; EPOCHS="${3:-10}"; MAXSB="${4:-4}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY="${VAGRANT_VM_MEMORY:-1024}"
export VAGRANT_VM_CPUS="${VAGRANT_VM_CPUS:-1}"
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/prop2_${SC}__${MSHORT}"
mkdir -p "$LOGDIR"
echo "=== $SC x $MODEL: $EPOCHS epochs, max_sandboxes=$MAXSB, 1M cap ==="
uv run inspect eval "propensity/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T infeasibility=normal -T token_limit=1000000 \
  --epochs "$EPOCHS" --max-sandboxes "$MAXSB" \
  --log-dir "$LOGDIR"
echo "=== DONE $SC $MSHORT ==="

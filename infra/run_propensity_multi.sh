#!/bin/bash
# Run N trials of a propensity scenario on this droplet.
# Usage: bash run_propensity_multi.sh <scenario_task_path> <model> <epochs> <max_sandboxes>
set -uo pipefail
TASK="$1"; MODEL="$2"; EPOCHS="${3:-10}"; MAXSB="${4:-3}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY="${VAGRANT_VM_MEMORY:-1024}"
export VAGRANT_VM_CPUS="${VAGRANT_VM_CPUS:-1}"
MSHORT="${MODEL##*/}"
SNAME="$(basename $(dirname $TASK))"
LOGDIR="/root/sandbox_escape_bench/logs/prop2_${SNAME}__${MSHORT}"
mkdir -p "$LOGDIR"
echo "=== $SNAME x $MODEL: $EPOCHS epochs, max_sandboxes=$MAXSB, 1M cap ==="
uv run inspect eval "$TASK" \
  --model "$MODEL" \
  -T sandbox=vagrant -T infeasibility=normal -T token_limit=1000000 \
  --epochs "$EPOCHS" --max-sandboxes "$MAXSB" \
  --log-dir "$LOGDIR"
echo "=== DONE $SNAME $MSHORT ==="

#!/bin/bash
# Capability check: directly-prompted escape on an AISI scenario (CTF framing).
# Usage: bash run_capability.sh <scenario> <model> <epochs> <max_sandboxes>
set -uo pipefail
SC="$1"; MODEL="$2"; EPOCHS="${3:-5}"; MAXSB="${4:-5}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=600
export INSPECT_MAX_VAGRANT_STARTUPS=3
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/cap_${SC}__${MSHORT}__$$"
mkdir -p "$LOGDIR"
echo "=== CAPABILITY $SC x $MODEL: $EPOCHS epochs, $MAXSB VMs, 1M cap, CTF prompt ==="
uv run inspect eval "scenarios/$SC/task.py" \
  --model "$MODEL" \
  -T sandbox=vagrant -T variant=normal -T token_limit=1000000 \
  --epochs "$EPOCHS" --max-sandboxes "$MAXSB" \
  --log-dir "$LOGDIR"
echo "=== DONE $SC $MSHORT ==="

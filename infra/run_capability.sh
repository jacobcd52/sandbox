#!/bin/bash
# Capability-ceiling check: directly prompt the model to escape (direct=True) for a given
# weakness, to measure whether it CAN (independent of propensity). Uses build_green as the
# cover task (the secret is the .so; genuine_win requires the genuine artifact in place).
# Usage: bash run_capability.sh <weakness> <model> <epochs>
set -uo pipefail
WK="$1"; MODEL="$2"; EPOCHS="${3:-4}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=1200
export INSPECT_MAX_VAGRANT_STARTUPS="${MAXVAGRANTSTARTUPS:-4}"
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/cap_${WK}__${MSHORT}"
mkdir -p "$LOGDIR"
echo "=== CAPABILITY $WK x $MSHORT: $EPOCHS epochs, direct=True ==="
uv run inspect eval "propensity/modular/builder.py@breakout_propensity" \
  -T task="build_green" -T weakness="$WK" -T direct=true \
  --model "$MODEL" -T sandbox=vagrant -T token_limit="${TOKLIM:-1000000}" \
  --epochs "$EPOCHS" --max-sandboxes "${MAXSB:-4}" --log-dir "$LOGDIR"
echo "=== DONE CAP $WK $MSHORT ==="

#!/bin/bash
# Run a chunk of trials for one (task, weakness) condition via the modular composer.
# Usage: bash run_matrix_chunk.sh <task> <weakness> <model> <epochs> <tag>
set -uo pipefail
TASK="$1"; WK="$2"; MODEL="$3"; EPOCHS="${4:-4}"; TAG="${5:-x}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=1200
export INSPECT_MAX_VAGRANT_STARTUPS="${MAXVAGRANTSTARTUPS:-2}"
MSHORT="${MODEL##*/}"
LOGDIR="/root/sandbox_escape_bench/logs/mx_${TASK}__${WK}__${MSHORT}__${TAG}"
mkdir -p "$LOGDIR"
TOK="${TOKLIM:-1000000}"
echo "=== $TASK x $WK x $MSHORT: $EPOCHS epochs, tag=$TAG, ${TOK} cap ==="
uv run inspect eval "propensity/modular/builder.py@breakout_propensity" \
  -T task="$TASK" -T weakness="$WK" \
  --model "$MODEL" -T sandbox=vagrant -T token_limit="$TOK" \
  --epochs "$EPOCHS" --max-sandboxes "${MAXSB:-4}" --log-dir "$LOGDIR"
echo "=== DONE $TASK $WK $MSHORT $TAG ==="

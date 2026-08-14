#!/bin/bash
# Run an Opus condition with the de-triggered framing: <task> <weakness> <epochs>
set -uo pipefail
TASK="$1"; WK="$2"; EPOCHS="${3:-4}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export ANTHROPIC_API_KEY="$(cat /root/.anthropic_key)"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=1200
export INSPECT_MAX_VAGRANT_STARTUPS=2
LOGDIR="/root/sandbox_escape_bench/logs/mx_${TASK}__${WK}__opus48_dt"
mkdir -p "$LOGDIR"
echo "=== OPUS(detrigger) $TASK x $WK: $EPOCHS epochs ==="
uv run inspect eval "propensity/modular/builder.py@breakout_propensity" \
  -T task="$TASK" -T weakness="$WK" -T detrigger=true \
  --model "anthropic/claude-opus-4-8" -T sandbox=vagrant -T token_limit=1000000 \
  --epochs "$EPOCHS" --max-sandboxes 4 --log-dir "$LOGDIR"
echo "=== DONE OPUS $TASK $WK ==="

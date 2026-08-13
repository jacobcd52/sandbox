#!/bin/bash
# Run a Fable condition: <task> <weakness> <epochs>
set -uo pipefail
TASK="$1"; WK="$2"; EPOCHS="${3:-4}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export ANTHROPIC_API_KEY="$(cat /root/.anthropic_key 2>/dev/null || echo "$ANTHROPIC_API_KEY")"
export VAGRANT_VM_MEMORY=1024 VAGRANT_VM_CPUS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=1200
export INSPECT_MAX_VAGRANT_STARTUPS=2
LOGDIR="/root/sandbox_escape_bench/logs/mx_${TASK}__${WK}__fable5"
mkdir -p "$LOGDIR"
echo "=== FABLE $TASK x $WK: $EPOCHS epochs ==="
uv run inspect eval "propensity/modular/builder.py@breakout_propensity" \
  -T task="$TASK" -T weakness="$WK" \
  --model "anthropic/claude-fable-5" -T sandbox=vagrant -T token_limit=1000000 \
  --epochs "$EPOCHS" --max-sandboxes 4 --log-dir "$LOGDIR"
echo "=== DONE FABLE $TASK $WK ==="

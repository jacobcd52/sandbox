#!/bin/bash
# Phase 1 runner: execute inside the droplet from /root/sandbox_escape_bench.
# Requires FIREWORKS_API_KEY in the environment.
# Usage:
#   FIREWORKS_API_KEY=... bash run_phase1.sh validate   # solution variant, 1 sample
#   FIREWORKS_API_KEY=... bash run_phase1.sh run        # full phase 1
set -euo pipefail
MODE="${1:-validate}"
cd /root/sandbox_escape_bench

export PATH="$HOME/.local/bin:$PATH"
[ -f images.yaml ] || cp images.example.yaml images.yaml
: "${FIREWORKS_API_KEY:?set FIREWORKS_API_KEY}"

MODEL="${MODEL:-fireworks/deepseek-v4-pro}"
TOKEN_LIMIT="${TOKEN_LIMIT:-150000}"
LOGDIR="${LOGDIR:-/root/sandbox_escape_bench/logs}"
mkdir -p "$LOGDIR"

case "$MODE" in
  validate)
    echo "=== VALIDATION: docker_socket solution variant (1 sample) ==="
    uv run inspect eval scenarios/docker_socket/task.py \
      --model "$MODEL" \
      -T sandbox=vagrant -T variant=solution \
      --limit 1 --max-sandboxes 1 \
      --log-dir "$LOGDIR/validate"
    ;;
  run)
    echo "=== PHASE 1: docker_socket privileged hostpath_etc x 5 epochs, $MODEL, token_limit=$TOKEN_LIMIT ==="
    for sc in docker_socket privileged hostpath_etc; do
      echo "--- $sc ---"
      uv run inspect eval "scenarios/$sc/task.py" \
        --model "$MODEL" \
        -T sandbox=vagrant -T variant=normal -T token_limit="$TOKEN_LIMIT" \
        --epochs 5 --max-sandboxes 2 \
        --log-dir "$LOGDIR/phase1_$sc"
    done
    ;;
  *)
    echo "unknown mode $MODE"; exit 1;;
esac
echo "=== MODE $MODE DONE ==="

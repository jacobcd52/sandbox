#!/bin/bash
# Phase 1 runner: execute inside the pod from /root/sandbox_escape_bench.
# Usage: bash run_phase1.sh <mode>
#   mode=validate : run solution variant of docker_socket (1 sample) to verify harness
#   mode=run      : full Phase 1 (3 scenarios x 5 trials, deepseek-v4-pro)
set -euo pipefail
MODE="${1:-validate}"
cd /root/sandbox_escape_bench

export PATH="$HOME/.local/bin:$PATH"
# Ensure images.yaml exists (fallback/quickstart mode: all null -> build at runtime)
[ -f images.yaml ] || cp images.example.yaml images.yaml

MODEL="fireworks/deepseek-v4-pro"
TOKEN_LIMIT="${TOKEN_LIMIT:-150000}"

case "$MODE" in
  validate)
    echo "=== VALIDATION: docker_socket solution variant (1 sample) ==="
    uv run inspect eval scenarios/docker_socket/task.py \
      --model "$MODEL" \
      -T sandbox=vagrant -T variant=solution \
      --limit 1 --log-dir logs/validate
    ;;
  run)
    echo "=== PHASE 1: 3 scenarios x 5 epochs, $MODEL, token_limit=$TOKEN_LIMIT ==="
    for sc in docker_socket privileged hostpath_etc; do
      echo "--- $sc ---"
      uv run inspect eval "scenarios/$sc/task.py" \
        --model "$MODEL" \
        -T sandbox=vagrant -T variant=normal -T token_limit="$TOKEN_LIMIT" \
        --epochs 5 --max-sandboxes 3 \
        --log-dir "logs/phase1_$sc"
    done
    ;;
  *)
    echo "unknown mode $MODE"; exit 1;;
esac
echo "=== MODE $MODE DONE ==="

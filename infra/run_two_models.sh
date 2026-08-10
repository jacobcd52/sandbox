#!/bin/bash
# Run BOTH models for ONE scenario on this droplet, sequentially.
# Reads Fireworks key from /root/.fw_key. Usage: bash run_two_models.sh <scenario>
set -uo pipefail
SC="${1:?scenario}"
cd /root/sandbox_escape_bench
export PATH="$HOME/.local/bin:$PATH"
export FIREWORKS_API_KEY="$(cat /root/.fw_key)"
export TOKEN_LIMIT=500000

for M in fireworks/kimi-k3 fireworks/gpt-oss-120b; do
  echo "##### starting $SC with $M at $(date -u +%H:%M:%S) #####"
  MODEL="$M" bash run_scenario.sh "$SC" 5 3 || echo "##### $M on $SC FAILED #####"
done
echo "##### ALL DONE for $SC at $(date -u +%H:%M:%S) #####"

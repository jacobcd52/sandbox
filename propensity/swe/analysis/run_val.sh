#!/bin/bash
# Run mechanical validation for one (instance, weakness) on its droplet.
# Usage: run_val.sh <droplet> <instance> <weakness> <vm_mem>
set -uo pipefail
NAME="$1"; INST="$2"; WK="$3"; MEM="${4:-2048}"
S="${SWEEP_SCRATCH:-$HOME/.sweep}"
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=30"
IP=$(grep "^$NAME " "$S/swe_droplets.txt" | awk '{print $2}')
LOG="$S/val_${WK}.log"

ssh -n $SSHO root@"$IP" "
export PATH=\$HOME/.local/bin:\$PATH
export FIREWORKS_API_KEY=\$(cat /root/.fw_key)
export VAGRANT_VM_MEMORY=$MEM VAGRANT_VM_CPUS=2
export INSPECT_MAX_VAGRANT_STARTUPS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=3000
cd /root/sandbox_escape_bench
mkdir -p logs/val_$WK
timeout 5400 uv run inspect eval propensity/swe/validate.py@swe_validate \
  -T instance=$INST -T weakness=$WK -T sandbox=vagrant \
  --model fireworks/kimi-k3 --max-sandboxes 1 --log-dir logs/val_$WK 2>&1 | tail -40
echo VAL_DONE_$WK
" > "$LOG" 2>&1
echo "$WK on $NAME -> $LOG"

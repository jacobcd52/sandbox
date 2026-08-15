#!/bin/bash
# Run the SWE propensity eval for one (instance, weakness) on its droplet.
# Usage: run_prop.sh <droplet> <instance> <weakness> <model> <epochs> <vm_mem> <tag> [maxsb]
set -uo pipefail
NAME="$1"; INST="$2"; WK="$3"; MODEL="$4"; EPOCHS="$5"; MEM="${6:-2048}"; TAG="${7:-x}"; MAXSB="${8:-1}"
S="${SWEEP_SCRATCH:-$HOME/.sweep}"
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=30"
IP=$(grep "^$NAME " "$S/swe_droplets.txt" | awk '{print $2}')
MSHORT="${MODEL##*/}"
LOG="$S/run_${TAG}_${INST}_${WK}_${MSHORT}.log"

# Reap orphans first. `pkill -f "inspect eval"` stops the harness but NOT the VMs it
# booted, so a relaunch stacks VMs until the box swaps or OOMs. This has bitten three times.
ssh -n $SSHO root@"$IP" '
  export PATH=$HOME/.local/bin:$PATH
  pgrep -f "inspect eval" >/dev/null || for v in $(virsh -c qemu:///system list --name 2>/dev/null); do
    virsh -c qemu:///system destroy "$v" >/dev/null 2>&1
  done' 2>/dev/null

ssh -n $SSHO root@"$IP" "
export PATH=\$HOME/.local/bin:\$PATH
export FIREWORKS_API_KEY=\$(cat /root/.fw_key)
export VAGRANT_VM_MEMORY=$MEM VAGRANT_VM_CPUS=2
export INSPECT_MAX_VAGRANT_STARTUPS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=3000
cd /root/sandbox_escape_bench
mkdir -p logs/${TAG}_${INST}_${WK}
uv run inspect eval propensity/swe/builder.py@swe_propensity \
  -T instance=$INST -T weakness=$WK -T sandbox=vagrant -T token_limit=1000000 \
  --model $MODEL --epochs $EPOCHS --max-sandboxes $MAXSB \
  --log-dir logs/${TAG}_${INST}_${WK} 2>&1 | tail -30
echo RUN_DONE_${TAG}_${WK}
" > "$LOG" 2>&1
echo "$TAG $WK $MSHORT on $NAME -> $LOG"

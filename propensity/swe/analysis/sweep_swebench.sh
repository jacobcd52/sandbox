#!/bin/bash
# The SWE-bench propensity sweep: real repos as the inner eval.
#
#   instance x weakness, one cell per pair, split across two droplets so a cell finishes in
#   two rounds rather than five.
#
# Only the docker weaknesses: the official SWE-bench instance images are docker images, and
# the task refuses k8s explicitly rather than mis-running it. egress_acl is excluded too --
# its host-side registry rebuilds the sqlglot tree, so it needs adapting to apply an
# instance's gold patch before it means anything here.
#
# VMs are 4G (the instance images are ~1.1GB and the suites are real), so ONE inspect stream
# per droplet. Two 4G VMs on an 8G box is what drove an earlier fleet into swap, and swapping
# is how orphan VMs became OOM kills.
#
# Usage: sweep_swebench.sh [model] [epochs_per_droplet]
set -uo pipefail
MODEL="${1:-fireworks/kimi-k3}"
EPOCHS="${2:-2}"
TAG="${TAG:-sbsweep}"
LEASE="${LEASE:-45}"
TOKENS="${TOKENS:-1000000}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${SWEEP_SCRATCH:-$HOME/.sweep}"
DROPLETS="${DROPLETS:-$S/sb_droplets.txt}"
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=30"

# Both instances are smoke-validated end to end, and they differ in repo layout on purpose:
# flask is src-layout, sphinx is flat. That was a real source of bugs -- cwd on sys.path lets a
# flat-layout repo shadow the platform build -- so the sweep exercises both.
CELLS=(
  "pallets__flask-5014      docker_sock  claude-sb-1  claude-sb-2"
  "pallets__flask-5014      privileged   claude-sb-3  claude-sb-4"
  "pallets__flask-5014      sys_admin    claude-sb-5  claude-sb-6"
  "sphinx-doc__sphinx-8595  docker_sock  claude-sb-7  claude-sb-8"
  "sphinx-doc__sphinx-8595  privileged   claude-sb-9  claude-sb-10"
  "sphinx-doc__sphinx-8595  sys_admin    claude-sb-11 claude-sb-12"
)

[ -s "$DROPLETS" ] || { echo "missing $DROPLETS" >&2; exit 2; }
echo "swebench sweep: model=$MODEL epochs=$EPOCHS/droplet lease=${LEASE}m tokens=$TOKENS tag=$TAG"
echo "cells=${#CELLS[@]} droplets=$(wc -l < "$DROPLETS") trials=$(( ${#CELLS[@]} * 2 * EPOCHS ))"

launch() {  # instance weakness droplet stream
  local INST="$1" WK="$2" NAME="$3" STREAM="$4"
  local IP; IP=$(grep "^$NAME " "$DROPLETS" | awk '{print $2}')
  [ -z "$IP" ] && { echo "  SKIP $INST x $WK: no droplet $NAME" >&2; return; }
  local LOG="$S/run_${TAG}_${INST}_${WK}_${NAME}.log"
  echo "  launch $INST x $WK on $NAME"
  ssh -n $SSHO root@"$IP" "
export PATH=\$HOME/.local/bin:\$PATH
export FIREWORKS_API_KEY=\$(cat /root/.fw_key)
export VAGRANT_VM_MEMORY=4096 VAGRANT_VM_CPUS=2
export INSPECT_MAX_VAGRANT_STARTUPS=1
export INSPECT_SANDBOX_SETUP_TIMEOUT=3000
cd /root/sandbox_escape_bench
# Reap any leftover VM first: pkill stops the harness, not the VMs it booted, and a relaunch
# stacks them until the box swaps. Only when no inspect is running, so a live trial is safe.
pgrep -f 'inspect eval' >/dev/null || for v in \$(virsh -c qemu:///system list --name 2>/dev/null); do
  virsh -c qemu:///system destroy \"\$v\" >/dev/null 2>&1
done
mkdir -p logs/${TAG}_${INST}_${WK}
uv run inspect eval propensity/swe/swebench/task.py@swebench_propensity \
  -T instance=$INST -T weakness=$WK -T sandbox=vagrant \
  -T token_limit=$TOKENS -T lease_minutes=$LEASE \
  --model $MODEL --epochs $EPOCHS --max-sandboxes 1 \
  --log-dir logs/${TAG}_${INST}_${WK} 2>&1 | tail -25
echo RUN_DONE_${TAG}_${WK}
" > "$LOG" 2>&1 &
  sleep 4      # stagger: simultaneous 1.1GB image pulls thrash the shared disk
}

for cell in "${CELLS[@]}"; do
  read -r INST WK D1 D2 <<<"$cell"
  launch "$INST" "$WK" "$D1" a
  launch "$INST" "$WK" "$D2" b
done
wait

echo
echo "Done. Judge the instrument BEFORE reading any rate:"
echo "  python3 $HERE/check_integrity.py <log-dir>/*.eval"

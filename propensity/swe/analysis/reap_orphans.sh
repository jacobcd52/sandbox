#!/bin/bash
# Destroy orphaned eval VMs on every droplet.
#
# Why this exists: `pkill -f "inspect eval"` stops the harness but NOT the VMs it booted.
# Relaunching then leaves two VMs per droplet. On the k8s cells (4G VMs on a 7.9G box) that
# drove free memory to ~100MB with 1.2G swapped. Swap prevented OOM kills, but the trials
# would have crawled. Memory pressure of this kind does not announce itself -- the same
# class of bug earlier produced a completely fake 0/5 result.
#
# An orphan is a qemu process clearly older than the currently-running inspect process.
# Run with no args after ANY kill/relaunch.
set -uo pipefail
S="/tmp/claude-0/-workspace-projects-sandbox/e25ae974-f832-4c1a-924d-5df593d7971f/scratchpad"
SSHO="-n -i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"
MARGIN="${1:-200}"   # seconds older than the live run before a VM counts as an orphan
# 200 is safe because a live trial's VM is always YOUNGER than its inspect process (inspect
# starts, then boots the VM). Anything older than inspect is by definition left over.
# Note: `virsh destroy` in an ad-hoc kill loop has repeatedly FAILED to clear these -- VMs
# up to an hour old survived two kill+relaunch cycles. Always verify with vms= afterwards.

while read -r name ip; do
  printf '%s: ' "$name"
  ssh $SSHO root@"$ip" '
    export PATH=$HOME/.local/bin:$PATH
    INS=$(ps -eo etimes,args | grep "[i]nspect eval" | head -1 | awk "{print \$1}"); INS=${INS:-0}
    killed=0
    for p in $(pgrep -f "qemu-system-x86_64"); do
      age=$(ps -o etimes= -p $p 2>/dev/null | tr -d " "); [ -z "$age" ] && continue
      if [ "$age" -gt $((INS + '"$MARGIN"')) ]; then
        nm=$(tr "\0" "\n" < /proc/$p/cmdline | grep "^guest=" | head -1 | sed "s/guest=//;s/,.*//")
        [ -n "$nm" ] && virsh -c qemu:///system destroy "$nm" >/dev/null 2>&1 && killed=$((killed+1))
      fi
    done
    echo "orphans_destroyed=$killed vms=$(virsh -c qemu:///system list 2>/dev/null | grep -c running) free=$(free -m | awk "/Mem:/{print \$7}")M"
  ' 2>&1 | tail -1
done < "$S/swe_droplets.txt"

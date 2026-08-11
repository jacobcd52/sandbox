#!/bin/bash
# Decisive per-droplet reset: kill all runs, reap ALL trial VMs, archive logs, launch ONE
# condition cleanly. Usage on droplet: bash reset_droplet.sh "<task:weakness:model:epochs>"
set -uo pipefail
COND="$1"
pkill -9 -f 'inspect eval' 2>/dev/null || true
sleep 2
# reap every vagrant/libvirt trial VM so we start from zero (no overlap / no leak)
for vm in $(virsh list --name 2>/dev/null); do
  virsh destroy "$vm" 2>/dev/null || true
  virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
done
# also destroy any vagrant-managed domains not in `virsh list`
cd /root/sandbox_escape_bench
mkdir -p logs/_archive && mv logs/mx_* logs/_archive/ 2>/dev/null || true
chmod +x /root/run_matrix_chunk.sh /root/run_matrix_parallel.sh 2>/dev/null || true
tmux kill-session -t mx 2>/dev/null || true
export CONDITIONS=" $COND"
export MAXSB="${MAXSB:-4}"
export TOKLIM="${TOKLIM:-1000000}"
export MAXVAGRANTSTARTUPS="${MAXVAGRANTSTARTUPS:-4}"
tmux new-session -d -s mx 'bash /root/run_matrix_parallel.sh > /root/mx_v2.log 2>&1'
echo "reset+launched:$COND"

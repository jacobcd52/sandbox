#!/bin/bash
# Launch ONE cell on a droplet, DETACHED, and return immediately.
#
# Runs the eval under setsid+nohup on the droplet with stdin closed, so it survives the ssh
# session that started it. A previous launcher kept the eval attached to a background ssh
# session; when the local task that owned it was reaped, SIGHUP killed inspect mid-run and the
# .eval files were left at `status: started` with ZERO samples -- a whole sweep's wall clock
# lost, and a result that would read as "no crossings" if the integrity gate had not caught it.
#
# Usage: launch_cell.sh <droplet> <instance> <weakness> <tag> [epochs] [lease] [tokens] [model]
set -uo pipefail
NAME="$1"; INST="$2"; WK="$3"; TAG="$4"
EPOCHS="${5:-2}"; LEASE="${6:-45}"; TOKENS="${7:-1000000}"; MODEL="${8:-fireworks/kimi-k3}"
S="${SWEEP_SCRATCH:-$HOME/.sweep}"
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20"
IP=$(grep "^$NAME " "$S/sb_droplets.txt" | awk '{print $2}')
[ -z "$IP" ] && { echo "no droplet $NAME" >&2; exit 2; }
LOGDIR="logs/${TAG}_${INST}_${WK}"

ssh -n $SSHO root@"$IP" "
set -e
export PATH=\$HOME/.local/bin:\$PATH
cd /root/sandbox_escape_bench
pgrep -f 'inspect eval' >/dev/null || for v in \$(virsh -c qemu:///system list --name 2>/dev/null); do
  virsh -c qemu:///system destroy \"\$v\" >/dev/null 2>&1
done
mkdir -p $LOGDIR
cat > /root/run_${TAG}_${WK}.sh <<'RUNEOF'
#!/bin/bash
export PATH=\$HOME/.local/bin:\$PATH
export FIREWORKS_API_KEY=\$(cat /root/.fw_key)
export VAGRANT_VM_MEMORY=4096 VAGRANT_VM_CPUS=2
export INSPECT_MAX_VAGRANT_STARTUPS=1 INSPECT_SANDBOX_SETUP_TIMEOUT=3000
cd /root/sandbox_escape_bench
uv run inspect eval propensity/swe/swebench/task.py@swebench_propensity \
  -T instance=$INST -T weakness=$WK -T sandbox=vagrant \
  -T token_limit=$TOKENS -T lease_minutes=$LEASE \
  --model $MODEL --epochs $EPOCHS --max-sandboxes 1 --log-dir $LOGDIR
echo CELL_DONE_${TAG}_${WK} >> /root/${TAG}_${WK}.done
RUNEOF
chmod +x /root/run_${TAG}_${WK}.sh
rm -f /root/${TAG}_${WK}.done
setsid nohup /root/run_${TAG}_${WK}.sh </dev/null > /root/${TAG}_${WK}.out 2>&1 &
sleep 2
pgrep -f 'inspect eval' >/dev/null && echo LAUNCH_OK || echo LAUNCH_FAILED
"

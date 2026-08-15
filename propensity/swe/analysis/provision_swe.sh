#!/bin/bash
# Provision one SWE-propensity droplet: wait for cloud-init, swap, KVM/vagrant stack,
# sync repo, warm uv deps. Idempotent.
set -uo pipefail
NAME="$1"; IP="$2"
SCRATCH="${SWEEP_SCRATCH:-$HOME/.sweep}"
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ServerAliveInterval=30"
REPO="/workspace/projects/sandbox"
LOG="$SCRATCH/prov_$NAME.log"
set -a; . /workspace/.env; set +a

{
echo "=== [$NAME $IP] wait for ssh ==="
for i in $(seq 1 40); do ssh -n $SSHO root@"$IP" 'echo up' >/dev/null 2>&1 && break; sleep 10; done

echo "=== [$NAME] cloud-init + apt locks + swap ==="
ssh -n $SSHO root@"$IP" '
  cloud-init status --wait 2>/dev/null || true
  for i in $(seq 1 120); do
    fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1 || break
    sleep 5
  done
  systemctl stop unattended-upgrades 2>/dev/null || true
  systemctl disable unattended-upgrades 2>/dev/null || true
  if [ ! -f /swapfile ]; then
    fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    sysctl -w vm.swappiness=10 >/dev/null
  fi
  echo "swap=$(free -m | awk "/Swap:/{print \$2}")M kvm=$(test -e /dev/kvm && echo yes || echo NO)"
'

echo "=== [$NAME] sync repo (tar over ssh) ==="
ssh -n $SSHO root@"$IP" 'rm -rf /root/sandbox_escape_bench && mkdir -p /root/sandbox_escape_bench'
tar -C "$REPO/vendor/sandbox_escape_bench" --exclude='.git' --exclude='transcript-analysis' \
    --exclude='viz' --exclude='figs' -czf - . \
  | ssh $SSHO root@"$IP" 'tar -C /root/sandbox_escape_bench -xzf -'
# the propensity code lives alongside, mirroring the repo layout the builders expect
tar -C "$REPO" -czf - propensity infra \
  | ssh $SSHO root@"$IP" 'tar -C /root/sandbox_escape_bench -xzf -'
ssh -n $SSHO root@"$IP" "printf '%s' '$FIREWORKS_API_KEY' > /root/.fw_key; chmod 600 /root/.fw_key;
  cd /root/sandbox_escape_bench && cp -n images.example.yaml images.yaml; ls propensity/swe 2>/dev/null | head -5"

echo "=== [$NAME] provision KVM/vagrant (long) ==="
scp $SSHO "$REPO/infra/provision_droplet.sh" root@"$IP":/root/provision_droplet.sh >/dev/null
ssh -n $SSHO root@"$IP" 'bash /root/provision_droplet.sh' 2>&1 | tail -4

echo "=== [$NAME] warm deps ==="
ssh -n $SSHO root@"$IP" 'export PATH=$HOME/.local/bin:$PATH; cd /root/sandbox_escape_bench && uv sync --frozen 2>&1 | tail -2; uv run inspect --version 2>&1 | tail -1'

echo "=== [$NAME] final ==="
ssh -n $SSHO root@"$IP" 'export PATH=$HOME/.local/bin:$PATH; echo -n "vagrant="; vagrant --version 2>&1; echo -n "box="; vagrant box list 2>&1|head -1; echo -n "nets="; virsh -c qemu:///system net-list 2>/dev/null|grep -c active'
echo "=== [$NAME] PROV_DONE ==="
} > "$LOG" 2>&1
echo "$NAME done -> $LOG"

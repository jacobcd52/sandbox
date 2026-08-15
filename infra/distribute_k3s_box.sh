#!/bin/bash
# Ship the baked k3s box to the k8s eval droplets and point images.yaml at it.
#
# builder.py resolves its sandbox via get_sandbox(sandbox, "privileged"), so the box for
# EVERY swe_propensity cell comes from the `privileged` entry of images.yaml on that droplet.
# Setting it per droplet is what keeps the k3s box on the k8s cells only -- a docker cell
# should not quietly gain a k3s install inside its VM.
#
# Usage: bash distribute_k3s_box.sh <bake_ip> <k8s_ip> [<k8s_ip> ...]
set -uo pipefail
SSHO="-i /root/.ssh/id_do -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"
SSH="ssh $SSHO"
SCP="scp $SSHO"
BAKE_IP="$1"; shift
BOX_NAME="${BOX_NAME:-swe-k3s}"
REMOTE_BOX="/root/bake_k3s/k3s-box.box"
CACHE=/root/boxcache/k3s-box.box

[ $# -lt 1 ] && { echo "need at least one target droplet ip" >&2; exit 2; }

echo "=== confirm box on bake droplet $BAKE_IP ==="
$SSH root@"$BAKE_IP" "ls -lh $REMOTE_BOX" || { echo "box not ready on $BAKE_IP" >&2; exit 1; }

mkdir -p /root/boxcache
if [ ! -s "$CACHE" ]; then
  echo "=== pull box to workspace cache ==="
  $SCP root@"$BAKE_IP":"$REMOTE_BOX" "$CACHE" || exit 1
fi
ls -lh "$CACHE"

for ip in "$@"; do
  ( echo "=== $ip: copy box ==="
    $SCP "$CACHE" root@"$ip":/root/k3s-box.box >/dev/null || exit 1
    echo "=== $ip: vagrant box add + point images.yaml at it ==="
    $SSH root@"$ip" "export PATH=\$HOME/.local/bin:\$PATH
      vagrant box add $BOX_NAME /root/k3s-box.box --provider libvirt --force 2>&1 | tail -1
      vagrant box list | grep $BOX_NAME
      cd /root/sandbox_escape_bench
      cp -n images.example.yaml images.yaml 2>/dev/null || true
      python3 - <<'PY'
import re
p='images.yaml'
s=open(p).read()
# only the 'privileged' scenario entry, which is the one builder.py resolves
s=re.sub(r'(^privileged:\n(?:[ \t]+.*\n)*?[ \t]+box: ).*$',
         r'\g<1>$BOX_NAME', s, count=1, flags=re.M)
open(p,'w').write(s)
# confirm by reading the file back, without depending on pyyaml being present
m=re.search(r'^privileged:\n(?:[ \t]+.*\n)*', s, re.M)
print('images.yaml privileged entry now:'); print((m.group(0) if m else 'NOT FOUND').rstrip())
PY" ) &
done
wait
echo "=== K3S BOX DISTRIBUTION DONE ==="

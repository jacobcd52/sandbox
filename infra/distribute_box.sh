#!/bin/bash
# Distribute the pre-baked eval box from the bake droplet to all eval droplets and add it
# to vagrant under the name the AISI sandbox provider expects, so per-trial setup is just
# boot + place-secret + docker run (no apt-get / docker build on a fresh VM).
#
# Usage: bash distribute_box.sh <bake_ip> <eval_ip_1> [eval_ip_2 ...]
# Requires: ~/.ssh/id_runpod usable for root@<ip> on all hosts.
set -uo pipefail

SSH="ssh -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=15"
SCP="scp -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=15"
BAKE_IP="$1"; shift
BOX_NAME="eval-prebaked"   # local name we register under
REMOTE_BOX="/root/bake/eval-box.box"

[ $# -lt 1 ] && { echo "need at least one eval droplet ip"; exit 1; }

echo "=== confirm box exists on bake droplet $BAKE_IP ==="
$SSH root@$BAKE_IP "ls -lh $REMOTE_BOX" || { echo "box not ready on $BAKE_IP"; exit 1; }

echo "=== pull box to local workspace cache ==="
mkdir -p /root/boxcache
$SCP root@$BAKE_IP:$REMOTE_BOX /root/boxcache/eval-box.box || exit 1
ls -lh /root/boxcache/eval-box.box

for ip in "$@"; do
  echo "=== $ip: copy + add box ==="
  $SCP /root/boxcache/eval-box.box root@$ip:/root/eval-box.box &
done
wait
for ip in "$@"; do
  echo "=== $ip: vagrant box add ==="
  $SSH root@$ip "vagrant box add $BOX_NAME /root/eval-box.box --provider libvirt --force 2>&1 | tail -2; vagrant box list | grep $BOX_NAME" &
done
wait
echo "=== DISTRIBUTION DONE ==="

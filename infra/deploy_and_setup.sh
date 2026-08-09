#!/bin/bash
# Start the eval pod, wait for SSH, sync code, and provision it.
# Usage: ./deploy_and_setup.sh
set -euo pipefail

POD_ID="zrfqqa9mrc9m0t"
KEY="$HOME/.ssh/id_runpod"
RUNPOD_API_KEY="${RUNPOD_API_KEY:?set RUNPOD_API_KEY}"
REPO_DIR="/workspace/vendor/sandbox_escape_bench"

api() { curl -s -H "Authorization: Bearer $RUNPOD_API_KEY" "$@"; }

echo "=== start pod ==="
api -X POST "https://rest.runpod.io/v1/pods/$POD_ID/start" >/dev/null || true

echo "=== wait for IP:port ==="
IP=""; PORT=""
for i in $(seq 1 40); do
  read IP PORT <<< "$(api "https://rest.runpod.io/v1/pods/$POD_ID" | python3 -c "import json,sys; d=json.load(sys.stdin); pm=d.get('portMappings') or {}; print(d.get('publicIp') or '', pm.get('22',''))")"
  [ -n "$IP" ] && [ -n "$PORT" ] && break
  sleep 6
done
[ -z "$IP" ] && { echo "no IP"; exit 1; }
echo "pod at $IP:$PORT"
echo "$IP $PORT" > /tmp/eval_pod_addr

echo "=== wait for SSH ==="
for i in $(seq 1 20); do
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 -p "$PORT" root@"$IP" 'echo ok' 2>/dev/null | grep -q ok && break
  sleep 6
done

echo "=== sync repo to pod ==="
rsync -az -e "ssh -i $KEY -o StrictHostKeyChecking=no -p $PORT" \
  --exclude '.git' --exclude 'transcript-analysis' \
  "$REPO_DIR/" root@"$IP":/root/sandbox_escape_bench/
scp -i "$KEY" -o StrictHostKeyChecking=no -P "$PORT" \
  /workspace/infra/provision_pod.sh root@"$IP":/root/provision_pod.sh

echo "=== run provisioning on pod (long) ==="
ssh -i "$KEY" -o StrictHostKeyChecking=no -p "$PORT" root@"$IP" \
  'bash /root/provision_pod.sh 2>&1 | tail -40'

echo "=== DONE. pod $IP:$PORT ==="

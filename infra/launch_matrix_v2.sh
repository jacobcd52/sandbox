#!/bin/bash
# Orchestrate the 12-condition breakout-propensity matrix across droplets, in parallel.
# Kills any stale runs, syncs the current repo's propensity/ tree, archives old mx logs,
# then launches each droplet's assigned conditions in parallel via run_matrix_parallel.sh.
#
# Usage: bash launch_matrix_v2.sh <model> <epochs>
#   e.g. bash launch_matrix_v2.sh fireworks/deepseek-v4-flash 4
set -uo pipefail
MODEL="${1:-fireworks/deepseek-v4-flash}"
EPOCHS="${2:-4}"
SSH="ssh -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=15"
SCP="scp -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=15"

# 12 conditions, distributed across droplets (1-2 per droplet for parallel-per-condition).
declare -A ASSIGN=(
  [104.131.0.224]="build_green:docker_sock etl_report:sys_admin"
  [104.131.82.167]="build_green:privileged etl_report:dac_read_search"
  [45.55.148.34]="build_green:sys_admin"
  [159.65.171.117]="build_green:dac_read_search"
  [167.99.58.192]="sign_attestation:docker_sock"
  [64.225.8.242]="sign_attestation:privileged"
  [45.55.192.52]="sign_attestation:sys_admin"
  [159.89.42.16]="sign_attestation:dac_read_search"
  [174.138.56.112]="etl_report:privileged"
  [167.172.227.13]="etl_report:docker_sock build_green:docker_sock"
)

echo "=== sync propensity/ to all droplets ==="
cd "$(dirname "$0")/.." && tar czf /tmp/propensity_sync.tgz propensity/
for ip in "${!ASSIGN[@]}"; do
  $SCP /tmp/propensity_sync.tgz root@$ip:/root/ && \
  $SSH root@$ip "cd /root/sandbox_escape_bench && tar xzf /root/propensity_sync.tgz" &
done
wait
echo "=== sync runner scripts ==="
for ip in "${!ASSIGN[@]}"; do
  $SCP infra/run_matrix_chunk.sh root@$ip:/root/run_matrix_chunk.sh
  $SCP infra/run_matrix_parallel.sh root@$ip:/root/run_matrix_parallel.sh &
done
wait

echo "=== kill stale runs + archive old mx logs + launch ==="
for ip in "${!ASSIGN[@]}"; do
  conds="${ASSIGN[$ip]}"
  # build CONDITIONS string "task:wk:model:epochs"
  CONDSTR=""
  for c in $conds; do CONDSTR="$CONDSTR ${c}:${MODEL}:${EPOCHS}"; done
  echo "--- $ip -> $CONDSTR"
  $SSH root@$ip "pkill -9 -f 'inspect eval' 2>/dev/null; \
    cd /root/sandbox_escape_bench && mkdir -p logs/_archive_v1 && \
    mv logs/mx_* logs/_archive_v1/ 2>/dev/null; \
    chmod +x /root/run_matrix_chunk.sh /root/run_matrix_parallel.sh; \
    tmux kill-session -t mx 2>/dev/null; \
    CONDITIONS='$CONDSTR' tmux new-session -d -s mx 'CONDITIONS=\"$CONDSTR\" bash /root/run_matrix_parallel.sh > /root/mx_v2.log 2>&1'; \
    echo launched" &
done
wait
echo "=== MATRIX V2 LAUNCHED ==="

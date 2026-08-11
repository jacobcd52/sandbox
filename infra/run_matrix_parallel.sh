#!/bin/bash
# Run this droplet's assigned (task:weakness) conditions IN PARALLEL, one inspect process
# per condition, each with --max-sandboxes 2 so trials within a condition also parallelize.
# Conditions passed as space-separated "task:weakness:model:epochs" via $CONDITIONS.
set -uo pipefail
cd /root/sandbox_escape_bench
TAG="$(hostname)_v2"
pids=()
for cond in $CONDITIONS; do
  IFS=':' read -r task wk model epochs <<< "$cond"
  LOG="/root/mx_${task}__${wk}.log"
  echo "launch $task x $wk -> $LOG"
  MAXSB="${MAXSB:-2}" bash /root/run_matrix_chunk.sh "$task" "$wk" "$model" "$epochs" "$TAG" > "$LOG" 2>&1 &
  pids+=($!)
  sleep 20   # stagger VM boots to avoid virNetworkDefineXML races
done
wait "${pids[@]}"
echo "##### MATRIX DONE on $(hostname) #####"

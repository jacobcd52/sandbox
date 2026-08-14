#!/bin/bash
# Run one or more (task:weakness) conditions sequentially on this droplet.
# Conditions passed as space-separated "task:weakness:model:epochs" via $CONDITIONS.
set -uo pipefail
cd /root/sandbox_escape_bench
for cond in $CONDITIONS; do
  IFS=':' read -r task wk model epochs <<< "$cond"
  bash /root/run_matrix_chunk.sh "$task" "$wk" "$model" "$epochs" "$(hostname)"
done
echo "##### MATRIX DONE on $(hostname) #####"

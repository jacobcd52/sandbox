#!/bin/bash
# Orchestrator on each droplet: run two cells sequentially.
# Args passed via env: CELL1="scenario model epochs maxsb" CELL2="..."
set -uo pipefail
run_cell() {
  local sc="$1" model="$2" epochs="$3" maxsb="$4"
  bash /root/run_cell.sh "$sc" "$model" "$epochs" "$maxsb"
}
[ -n "${CELL1:-}" ] && run_cell $CELL1
[ -n "${CELL2:-}" ] && run_cell $CELL2
echo "##### FLEET DONE on $(hostname) #####"

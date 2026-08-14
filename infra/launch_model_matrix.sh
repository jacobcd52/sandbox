#!/bin/bash
# Launch a full propensity matrix for ONE model across a set of droplets.
# Usage: bash launch_model_matrix.sh <model> <tag> "<ip:task:weakness> <ip:task:weakness> ..."
set -uo pipefail
MODEL="$1"; TAG="$2"; shift 2
SSH="ssh -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=25"
for assign in "$@"; do
  ip="${assign%%:*}"; rest="${assign#*:}"; task="${rest%%:*}"; wk="${rest##*:}"
  cond="${task}:${wk}:${MODEL}:10"
  GO="/tmp/go_${ip//./_}.sh"
  {
    echo '#!/bin/bash'
    echo "export CONDITIONS=\" $cond\""
    echo "export MAXSB=6 TOKLIM=1000000 MAXVAGRANTSTARTUPS=4"
    echo "pkill -9 -f 'inspect eval' 2>/dev/null"
    echo "cd /root/sandbox_escape_bench"
    echo "mkdir -p logs/_archive && mv logs/mx_* logs/_archive/ 2>/dev/null"
    echo "tmux kill-session -t mx 2>/dev/null"
    echo "tmux new-session -d -s mx 'bash /root/run_matrix_parallel.sh > /root/mx_${TAG}.log 2>&1'"
    echo "echo launched $cond"
  } > "$GO"
  scp -i "$HOME/.ssh/id_runpod" -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$GO" root@$ip:/root/_mx_go.sh 2>/dev/null
  $SSH root@$ip "bash /root/_mx_go.sh" 2>/dev/null &
done
wait
echo "=== $MODEL matrix launched ==="

#!/bin/bash
# Pre-warm a droplet so per-trial setup is fast: boot one VM from the base box, run the
# modular setup.sh once inside it (which apt-installs docker and builds the build-worker
# image), then destroy the VM. All trial VMs share the base box's cached backing store, so
# the docker image + apt cache persist and subsequent per-trial setup skips the slow build.
#
# Usage: bash prewarm_droplet.sh <droplet_ip> <task> <weakness>
# Run from a machine with ~/.ssh/id_runpod and the repo checked out.
set -uo pipefail
SSH="ssh -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no -o ConnectTimeout=15"
IP="$1"; TASK="${2:-build_green}"; WK="${3:-docker_sock}"
REPO=/root/sandbox_escape_bench

echo "=== $IP: generate setup.sh for $TASK x $WK locally ==="
GEN=$(cd "$(dirname "$0")/.." && python3 - "$TASK" "$WK" <<'PY'
import sys, importlib.util, tempfile, os
sys.path.insert(0,'propensity/modular'); sys.path.insert(0,'propensity')
def load(n,p):
    s=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(s); sys.modules[n]=m; s.loader.exec_module(m); return m
b=load("builder","propensity/modular/builder.py")
sh=b._gen_setup(sys.argv[2], sys.argv[1])
p=tempfile.mktemp(prefix="prewarm_", suffix=".sh"); open(p,"w").write(sh); print(p)
PY
)
echo "setup script: $GEN"

echo "=== $IP: copy repo setup deps + boot a warm VM ==="
$SSH root@$IP "mkdir -p /root/prewarm && cd /root/prewarm && cat > Vagrantfile <<'VF'
Vagrant.configure('2') do |config|
  config.vm.box = 'generic/ubuntu2004'
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.vm.provider :libvirt do |v|
    v.memory = 2048; v.cpus = 2
  end
end
VF"
scp -i $HOME/.ssh/id_runpod -o StrictHostKeyChecking=no "$GEN" root@$IP:/root/prewarm/setup.sh
$SSH root@$IP "cd /root/prewarm && (vagrant up --provider=libvirt 2>&1 | tail -2)"
echo "=== $IP: run setup.sh inside the warm VM (builds+caches the image) ==="
$SSH root@$IP "cd /root/prewarm && vagrant ssh -c 'sudo bash /vagrant/setup.sh' 2>&1 | tail -5 || vagrant ssh -c 'sudo bash -s' < /root/prewarm/setup.sh 2>&1 | tail -5"
echo "=== $IP: teardown (image stays cached in base-box store) ==="
$SSH root@$IP "cd /root/prewarm && vagrant destroy -f 2>&1 | tail -1"
echo "=== PREWARM DONE $IP ==="

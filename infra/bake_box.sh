#!/bin/bash
# Build a pre-baked vagrant box with docker + the eval image pre-loaded, so per-trial
# setup is just: boot (fast) + place secret + docker run. Run as root on a droplet.
set -e
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$PATH"
WORK=/root/bake
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

cat > Vagrantfile <<'VF'
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2004"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :libvirt do |v|
    v.memory = 4096; v.cpus = 4
  end
end
VF

echo "=== boot base box ==="
vagrant up --provider=libvirt 2>&1 | tail -2

echo "=== provision docker + eval-image inside the VM ==="
vagrant ssh -c 'sudo bash -s' <<'INNER'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq docker.io >/dev/null
systemctl start docker || service docker start
systemctl enable docker || true
chmod 666 /var/run/docker.sock || true
# build the eval image with the full toolset (this is the slow part we bake in)
docker build -t eval-image - <<'DOCKERFILE'
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    curl python3 python3-pip ca-certificates git jq make g++ cmake gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["sleep", "infinity"]
DOCKERFILE
docker save -o /root/eval-image.tar eval-image
echo "image built+saved"
INNER

echo "=== package the box ==="
vagrant package --output /root/bake/eval-box.box 2>&1 | tail -3
# also export the eval-image tar to the droplet for distribution
vagrant ssh -c "sudo cat /root/eval-image.tar" > /root/bake/eval-image.tar 2>/dev/null
ls -la /root/bake/
echo "=== BAKE DONE ==="

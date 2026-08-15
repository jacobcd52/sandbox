#!/bin/bash
# Bake a vagrant box with docker + k3s + the job image preloaded, so a k8s trial's setup is
# boot + start k3s, not a per-trial k3s install.
#
# Why this exists: builder.py's k8s setup runs `curl -sfL https://get.k3s.io | sh` inside a
# FRESH VM for every sample. That is why the last k8s attempt produced 2.5 hours of zero
# trials. The install is guarded by `if ! command -v k3s`, so baking the binary into the box
# turns it into a no-op with no builder changes.
#
# The one subtlety: we install k3s but never START it here. A started k3s writes cluster
# state under /var/lib/rancher/k3s -- certs, a node identity, a token -- all tied to the
# hostname and IP it first saw. Baking that state ships every VM a cluster that believes it
# lives at a libvirt DHCP address it will not get again. Instead we install the binary, drop
# the airgap image tarball where k3s imports it from at startup, and let each VM initialise
# itself on first boot. Clean state, no network pulls.
#
# Usage: bash bake_k3s_box.sh [imgtag]     (run as root on a provisioned droplet)
set -e
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$PATH"

K3S_VERSION="${K3S_VERSION:-v1.27.16+k3s1}"
IMGTAG="${1:-52800712}"          # ci-base-<sha256(image_packages)[:8]> for k8s_rbac
IMG_PACKAGES="${IMG_PACKAGES:-python3 python3-pip git curl ca-certificates}"
WORK=/root/bake_k3s
BOX_OUT=/root/bake_k3s/k3s-box.box

# vagrant-libvirt's packager shells out to virt-sysprep, which lives in libguestfs-tools and
# is NOT part of provision_droplet.sh. Without it `vagrant package` dies with
# `No such file or directory - virt-sysprep` after doing all the work. Install it first.
# On Ubuntu the kernel image is mode 600, and libguestfs needs to read it to build its
# appliance, so chmod it too -- otherwise sysprep fails with a permission error instead.
if ! command -v virt-sysprep >/dev/null 2>&1; then
  echo "=== install libguestfs-tools (for virt-sysprep) ==="
  apt-get update -qq
  apt-get install -y -qq libguestfs-tools >/dev/null
fi
chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

cat > Vagrantfile <<'VF'
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2004"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :libvirt do |v|
    v.memory = 4096; v.cpus = 2
  end
end
VF

echo "=== boot base box ==="
vagrant up --provider=libvirt 2>&1 | tail -3

echo "=== install docker + k3s (not started) + job image ==="
vagrant ssh -c 'sudo bash -s' <<INNER
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq docker.io curl >/dev/null
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker || service docker start
chmod 666 /var/run/docker.sock || true

# k3s binary + systemd unit, enabled for next boot but NOT started now: see header.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_SKIP_START=true \
  K3S_KUBECONFIG_MODE=644 sh - >/dev/null 2>&1

# Airgap images: k3s imports anything in this directory at startup, so the first boot does
# not pull pause/coredns/etc over the network. This is the slow half of a cold k3s start.
mkdir -p /var/lib/rancher/k3s/agent/images
VER_ENC=\$(printf '%s' "$K3S_VERSION" | sed 's/+/%2B/')
curl -sfL -o /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar \
  "https://github.com/k3s-io/k3s/releases/download/\${VER_ENC}/k3s-airgap-images-amd64.tar"
ls -lh /var/lib/rancher/k3s/agent/images/

# The job image, under the exact content-derived tag builder.py will look for. Its guard is
# \`docker image inspect ci-base-<tag>\`, so a baked image skips the per-trial build too.
docker build -t ci-base-$IMGTAG - <<DOCKERFILE >/dev/null
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends $IMG_PACKAGES \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
docker images | grep ci-base

# Leave no started-k3s state behind, in case a future edit starts it above.
rm -rf /var/lib/rancher/k3s/server /var/lib/rancher/k3s/agent/client-* 2>/dev/null || true
echo "BAKE_INNER_OK k3s=\$(command -v k3s) docker=\$(command -v docker)"
INNER

# Make sure the guest authorises every key a later `vagrant up` might offer -- by APPENDING,
# never replacing.
#
# vagrant-libvirt's packager bundles THIS machine's private key into the box and writes a box
# Vagrantfile pointing `config.ssh.private_key_path` at it, so a VM created from the box
# authenticates with that key, not with the insecure default. Overwriting authorized_keys
# with the insecure keys therefore deletes the one key the box actually ships and makes every
# VM from it unreachable -- and unreachable fails by hanging to the sandbox setup timeout,
# not by erroring. Appending keeps the bundled key working and adds the insecure keys as a
# fallback for anything that offers them instead.
echo "=== authorise the machine key + insecure keys in the guest ==="
PUBS=$(for k in "$WORK"/.vagrant/machines/*/libvirt/private_key \
                "$HOME"/.vagrant.d/insecure_private_key \
                "$HOME"/.vagrant.d/insecure_private_keys/*; do
         [ -f "$k" ] && ssh-keygen -y -f "$k" 2>/dev/null
       done)
[ -z "$PUBS" ] && { echo "no vagrant keys found -- refusing to package an unreachable box" >&2; exit 1; }
vagrant ssh -c 'sudo bash -s' <<INNERKEY
set -e
install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.ssh
touch /home/vagrant/.ssh/authorized_keys
cat >> /home/vagrant/.ssh/authorized_keys <<'PUBEOF'
$PUBS
PUBEOF
sort -u -o /home/vagrant/.ssh/authorized_keys /home/vagrant/.ssh/authorized_keys
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
echo "authorized_keys now:"; cut -d' ' -f1,3 /home/vagrant/.ssh/authorized_keys
INNERKEY

echo "=== package the box ==="
vagrant package --output "$BOX_OUT" 2>&1 | tail -3
ls -lh "$BOX_OUT"
vagrant destroy -f >/dev/null 2>&1 || true
echo "=== BAKE_K3S_DONE $BOX_OUT ==="

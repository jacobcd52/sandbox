#!/bin/bash
# Provision a RunPod pod as the eval host for SandboxEscapeBench Phase 1.
# Runs INSIDE the pod (as root). No KVM available, so we use libvirt+qemu TCG
# software emulation. Idempotent-ish; safe to re-run.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== apt: base deps, qemu, libvirt ==="
apt-get update -q
apt-get install -y -q --no-install-recommends \
  qemu-system-x86 qemu-utils libvirt-daemon libvirt-daemon-system \
  libvirt-clients bridge-utils dnsmasq-base ebtables \
  build-essential libssl-dev libffi-dev python3-dev python3-pip \
  pkg-config curl wget git rsync openssh-client jq ca-certificates

echo "=== install vagrant (official repo) ==="
if ! command -v vagrant >/dev/null 2>&1; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -q
  apt-get install -y -q vagrant
fi
vagrant --version

echo "=== install vagrant-libvirt plugin (builds against libvirt) ==="
# vagrant-libvirt needs libvirt-dev + ruby dev tooling
apt-get install -y -q libvirt-dev ruby-dev libxslt-dev libxml2-dev zlib1g-dev
if ! vagrant plugin list | grep -q vagrant-libvirt; then
  vagrant plugin install vagrant-libvirt
fi
vagrant plugin list

echo "=== libvirt: enable qemu:///session (rootless, TCG software emulation) ==="
# Start the system libvirt daemon (used for networks); rootless session works on top.
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true
libvirtd --daemon 2>/dev/null || service libvirtd start 2>/dev/null || true
sleep 2
virsh -c qemu:///system list --all || echo "(system daemon list failed; continuing)"

echo "=== default NAT network for libvirt ==="
virsh -c qemu:///system net-list --all | grep -q default || \
  virsh -c qemu:///system net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
virsh -c qemu:///system net-start default 2>/dev/null || true
virsh -c qemu:///system net-autostart default 2>/dev/null || true

echo "=== pre-pull the vagrant box for our 3 easy scenarios ==="
# These use generic/ubuntu2004 (see sandbox.py UBUNTU_VERSIONS). Pull for libvirt.
if ! vagrant box list | grep -q "generic/ubuntu2004"; then
  vagrant box add generic/ubuntu2004 --provider=libvirt --box-version 4.3.12
fi
vagrant box list

echo "=== summary ==="
echo "vagrant: $(vagrant --version)"
echo "qemu:    $(qemu-system-x86_64 --version | head -1)"
virsh -c qemu:///system net-list --all || true
echo "POD PROVISION COMPLETE"

#!/bin/bash
# Idempotent full setup for a fresh eval droplet (run as root on the droplet).
set -e
export DEBIAN_FRONTEND=noninteractive
unset LD_PRELOAD
export PATH="$HOME/.local/bin:$PATH"

# base packages + qemu/libvirt/vagrant deps
apt-get update -qq
apt-get install -y -qq qemu-system-x86 qemu-utils libvirt-daemon libvirt-daemon-system \
  libvirt-clients libvirt-dev bridge-utils dnsmasq-base ebtables build-essential \
  libssl-dev libffi-dev python3-dev python3-pip ruby-dev libxslt-dev libxml2-dev \
  zlib1g-dev pkg-config curl wget git rsync jq ca-certificates cpu-checker >/dev/null

# uv
command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; }
export PATH="$HOME/.local/bin:$PATH"

# vagrant
if ! command -v vagrant >/dev/null; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -qq && apt-get install -y -qq vagrant >/dev/null
fi

# libvirt daemon + default net
mkdir -p /run/dbus; dbus-daemon --system --fork 2>/dev/null || true
libvirtd --daemon 2>/dev/null || service libvirtd start 2>/dev/null || true
sleep 2
virsh -c qemu:///system net-list --all 2>/dev/null | grep -q default || virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# vagrant-libvirt + box
vagrant plugin list | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt >/dev/null 2>&1
vagrant box list | grep -q ubuntu2004 || vagrant box add generic/ubuntu2004 --provider=libvirt --box-version 4.3.12 >/dev/null 2>&1

echo "PROVISION_OK $(hostname)"

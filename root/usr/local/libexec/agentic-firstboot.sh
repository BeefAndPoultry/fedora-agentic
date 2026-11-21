#!/bin/bash
set -euo pipefail

if [ -e /var/lib/agentic/firstboot-complete ]; then
    systemctl disable --now agentic-firstboot.timer
    systemctl disable --now agentic-firstboot.service
    exit 0
fi

echo "Waiting for internet connection..."

while true; do
    if nmcli -t -f STATE general | grep -qx connected; then
        if curl -fsS -o /dev/null \
            --connect-timeout 5 \
            --max-time 10 \
            https://fedoraproject.org/; then
            break
        fi
    fi

    sleep 15
done

echo "Internet connection detected."

echo "Installing additional packages..."

dnf install -y --skip-unavailable --setopt=install_weak_deps=True dnf-plugins-core dnf5-plugins

dnf copr enable sneed/llama-cpp-vulkan
dnf copr enable jmarcoshp/grub-btrfs

dnf install -y --skip-unavailable --setopt=install_weak_deps=True @standard @kde-apps @kde-media @kde-desktop @printing @guest-desktop-agents @fonts @core @hardware-support plasma-workspace-wallpapers bluedevil NetworkManager-bluetooth mediawriter mesa-vulkan-drivers intel-gpu-firmware amd-gpu-firmware nvidia-gpu-firmware flatpak llama-cpp snapper btrfs-assistant grub-btrfs

# 2. Filter out boolean '(' expressions and install remaining weak deps
mapfile -t RECOMMENDS < <(rpm -qa --recommends | grep -v '^(' | awk '{print $1}' | sort -u)

if [[ ${#RECOMMENDS[@]} -gt 0 ]]; then
  dnf install -y --setopt=install_weak_deps=True --skip-unavailable "${RECOMMENDS[@]}"
fi

systemctl enable --now grub-btrfsd.service

if rpm -q llama-cpp >/dev/null 2>&1; then
    systemctl enable --now llama-server.service
else
    echo "llama-cpp is not installed; skipping llama-server."
fi

/usr/local/libexec/install-zswap.sh

# Prevent this service from running again.
mkdir -p /var/lib/agentic
touch /var/lib/agentic/firstboot-complete

systemctl disable --now agentic-firstboot.timer
systemctl disable agentic-firstboot.service

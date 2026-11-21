#!/bin/bash

sudo bash << 'EOF'

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

systemctl enable --now llama-server.service

# TODO: fix path in case not run from CWD
./install_zswap.sh

EOF

/usr/local/bin/autocomplete.sh install

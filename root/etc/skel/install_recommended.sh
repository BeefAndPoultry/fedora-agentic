#!/usr/bin/env bash

sudo bash << 'EOF'

dnf install -y --skip-unavailable --setopt=install_weak_deps=True @standard @kde-apps @kde-media @kde-desktop @printing @guest-desktop-agents @fonts @core @hardware-support plasma-workspace-wallpapers bluedevil NetworkManager-bluetooth mediawriter mesa-vulkan-drivers intel-gpu-firmware amd-gpu-firmware nvidia-gpu-firmware flatpak

# 2. Filter out boolean '(' expressions and install remaining weak deps
mapfile -t RECOMMENDS < <(rpm -qa --recommends | grep -v '^(' | awk '{print $1}' | sort -u)

if [[ ${#RECOMMENDS[@]} -gt 0 ]]; then
  dnf install -y --setopt=install_weak_deps=True --skip-unavailable "${RECOMMENDS[@]}"
fi

# TODO: fix path in case not run from CWD
./install_zswap.sh

EOF

/usr/local/bin/autocomplete.sh install

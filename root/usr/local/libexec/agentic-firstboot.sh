#!/bin/bash
set -euo pipefail

# --- Live first-boot progress ---------------------------------------------
# A KDE watcher (agentic-firstboot-ui.sh) reads this atomic status file and
# renders a kdialog progress bar during login. The producer writes the current
# percentage (line 1) and status message (line 2), atomically, and the EXIT
# trap removes the file so reboots never show a stale popup. /run/ is used
# instead of /tmp/ so it survives systemd PrivateTmp isolation and user
# switches, and is always cleaned up on reboot.
PROGRESS_FILE="/run/agentic-firstboot-progress"

cleanup_progress() {
    rm -f "${PROGRESS_FILE}" "${PROGRESS_FILE}.tmp"
}
trap cleanup_progress EXIT

set_progress() {
    # Atomic write (temp file + chmod + rename) so the watcher never reads a
    # half-written status line.
    printf "%s\n%s\n" "$1" "$2" > "${PROGRESS_FILE}.tmp"
    chmod 0644 "${PROGRESS_FILE}.tmp"
    mv "${PROGRESS_FILE}.tmp" "${PROGRESS_FILE}"
}

if [ -e /var/lib/agentic/firstboot-complete ]; then
    systemctl disable --now agentic-firstboot.timer
    systemctl disable --now agentic-firstboot.service
    exit 0
fi

/usr/local/libexec/install-zswap.sh

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

set_progress 15 "Detecting hardware and internet connection..."

echo "Internet connection detected."

set_progress 30 "Installing additional packages..."

echo "Installing additional packages..."

dnf install -y --skip-unavailable --setopt=install_weak_deps=True dnf-plugins-core dnf5-plugins

dnf copr enable -y sneed/llama-cpp-vulkan
dnf copr enable -y jmarcoshp/grub-btrfs

dnf install -y --skip-unavailable --setopt=install_weak_deps=True mesa-vulkan-drivers intel-gpu-firmware amd-gpu-firmware nvidia-gpu-firmware flatpak llama-cpp snapper btrfs-assistant grub-btrfs

# Generate the API key *before* starting llama-server so the first boot launch
# already requires it (the launcher reads /etc/llama-cpp/apikey). The server
# only listens on 127.0.0.1 (loopback), so making the key world-readable here is
# safe; users read it to configure their OpenAI-compatible clients (pi-agent,
# etc.). Skip generation if generate_key.py is absent so first boot still works.
if [ -x /usr/local/bin/generate_key.py ]; then
    mkdir -p /etc/llama-cpp
    /usr/local/bin/generate_key.py > /etc/llama-cpp/apikey
    chmod 0644 /etc/llama-cpp/apikey
    echo "Wrote LLM API key to /etc/llama-cpp/apikey (world-readable; loopback-only server)."
else
    echo "generate_key.py not found or not executable; skipping API key generation." >&2
fi

set_progress 50 "Setting up the llama.cpp inference server..."

if rpm -q llama-cpp >/dev/null 2>&1; then
    systemctl enable --now llama-server.service
else
    echo "llama-cpp is not installed; skipping llama-server."
fi

# Prevent this service from running again.
mkdir -p /var/lib/agentic
touch /var/lib/agentic/firstboot-complete

systemctl disable --now agentic-firstboot.timer
systemctl disable agentic-firstboot.service

set_progress 80 "Finalizing first-boot services..."

systemctl enable --now grub-btrfsd.service

# Install missing recommended pacakkages, filter out boolean '(' expressions and install remaining weak deps
dnf install -y --skip-unavailable --setopt=install_weak_deps=True @standard @kde-apps @kde-media @kde-desktop @printing @guest-desktop-agents @fonts @core @hardware-support plasma-workspace-wallpapers bluedevil NetworkManager-bluetooth mediawriter
mapfile -t RECOMMENDS < <(rpm -qa --recommends | grep -v '^(' | awk '{print $1}' | sort -u)

if [[ ${#RECOMMENDS[@]} -gt 0 ]]; then
  set_progress 93 "Installing recommended packages..."
  dnf install -y --setopt=install_weak_deps=True --skip-unavailable "${RECOMMENDS[@]}"
fi

set_progress 100 "Fedora Agentic setup complete!"
sleep 2

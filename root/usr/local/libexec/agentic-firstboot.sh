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
    printf "%s%% %s\n" "$1" "$2"
    printf "%s\n%s\n" "$1" "$2" > "${PROGRESS_FILE}.tmp"
    chmod 0644 "${PROGRESS_FILE}.tmp"
    mv "${PROGRESS_FILE}.tmp" "${PROGRESS_FILE}"
}

if [ -e /var/lib/agentic/firstboot-complete ]; then
    systemctl disable --now agentic-firstboot.service 2>/dev/null || true
    exit 0
fi

set_progress 0 "Installing zswap..."

/usr/local/libexec/install-zswap.sh || true

set_progress 1 "Waiting for internet..."

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

set_progress 5 "Updating packages..."
dnf upgrade -y --refresh

set_progress 10 "Installing copr..."
dnf install -y --skip-unavailable --setopt=install_weak_deps=True --allowerasing --skip-broken dnf-plugins-core dnf5-plugins

dnf copr enable -y sneed/llama-cpp-vulkan
dnf copr enable -y jmarcoshp/grub-btrfs

set_progress 15 "Installing basic packages..."
dnf install -y --skip-unavailable --setopt=install_weak_deps=True --allowerasing --skip-broken flatpak plasma-discover-flatpak llama-cpp snapper btrfs-assistant grub-btrfs

set_progress 25 "Installing graphics packages..."
dnf install -y --skip-unavailable --setopt=install_weak_deps=True --allowerasing --skip-broken mesa-vulkan-drivers intel-gpu-firmware amd-gpu-firmware nvidia-gpu-firmware

# Generate the API key *before* starting llama-server so the first boot launch
# already requires it (the launcher reads /etc/llama-cpp/apikey). The server
# only listens on 127.0.0.1 (loopback), so making the key world-readable here is
# safe; users read it to configure their OpenAI-compatible clients (pi-agent,
# etc.). Skip generation if generate_key.py is absent so first boot still works.
if [ -s /etc/llama-cpp/apikey ]; then
    echo "LLM API key already present at /etc/llama-cpp/apikey; reusing it."
else
    if [ -x /usr/local/bin/generate_key.py ]; then
        mkdir -p /etc/llama-cpp
        if python3 /usr/local/bin/generate_key.py > /etc/llama-cpp/apikey; then
            chmod 0644 /etc/llama-cpp/apikey
            echo "Wrote LLM API key to /etc/llama-cpp/apikey (world-readable; loopback-only server)."
        else
            echo "generate_key.py failed; skipping API key generation." >&2
        fi
    else
        echo "generate_key.py not found or not executable; skipping API key generation." >&2
    fi
fi

set_progress 40 "Setting up the llama.cpp inference server..."

if rpm -q llama-cpp >/dev/null 2>&1; then
    systemctl enable --now llama-server.service
else
    echo "llama-cpp is not installed; skipping llama-server."
fi

systemctl enable --now grub-btrfsd.service

# Install pi (the coding agent) globally so users can run it. --ignore-scripts
# avoids running the package's postinstall hooks inside first boot. Then populate
# every existing user's pi configuration (~/.pi/agent/{auth.json, models.json,
# settings.json}) from the live sources: the API key generated above, the
# llama-server host/port in /etc/sysconfig/llama-server, and the model preset plus
# context window in /var/lib/llama-cpp/models.ini (written by llama-server at
# startup). Per-user configs are re-synced on each login by a KDE autostart entry
# so an API-key rotation or a new model preset stays current.
set_progress 45 "Installing pi agent..."
# Node.js + npm: required to install pi (@earendil-works/pi-coding-agent) globally.
dnf install -y --skip-unavailable --setopt=install_weak_deps=True --allowerasing --skip-broken nodejs22-npm-bin
if npm install -g --ignore-scripts @earendil-works/pi-coding-agent; then
    echo "pi installed ($(npm ls -g --depth=0 2>/dev/null | grep '@earendil' || echo pi))"
else
    echo "WARNING: failed to install pi globally" >&2
fi
/usr/local/libexec/pi-config-sync.py

# Install missing recommended packages, filter out boolean '(' expressions and install remaining weak deps
set_progress 50 "Installing basic packages..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
dnf install -y --skip-unavailable --setopt=install_weak_deps=True --allowerasing --skip-broken @standard @kde-apps @kde-media @kde-desktop @printing @guest-desktop-agents @fonts @core @hardware-support plasma-workspace-wallpapers bluedevil NetworkManager-bluetooth mediawriter
mapfile -t RECOMMENDS < <(rpm -qa --recommends | grep -v '^(' | awk '{print $1}' | sort -u)

set_progress 60 "Installing extra packages..."
if [[ ${#RECOMMENDS[@]} -gt 0 ]]; then
  dnf install -y --setopt=install_weak_deps=True --skip-unavailable --allowerasing --skip-broken "${RECOMMENDS[@]}"
fi

set_progress 100 "Fedora Agentic setup complete! You may want to reboot."

# Prevent this service from running again.
mkdir -p /var/lib/agentic
touch /var/lib/agentic/firstboot-complete

sleep 2
cleanup_progress

# Service no longer runs again: the marker above short-circuits re-runs, and we
# drop the enablement so a stray boot can't re-trigger setup. The timer was
# removed in favor of enabling the service directly.
systemctl disable --now agentic-firstboot.service 2>/dev/null || true

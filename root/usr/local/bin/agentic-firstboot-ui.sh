#!/usr/bin/env bash
#
# Fedora Agentic first-boot progress UI.
#
# Launched automatically on every KDE login (see
# /etc/xdg/autostart/agentic-firstboot-ui.desktop). It watches the atomic
# status file written by agentic-firstboot.service and, while first-boot setup
# is running, shows a zenity progress bar that updates live.
#
# Design notes:
#   * The producer (agentic-firstboot.sh) and this watcher are decoupled through
#     an atomic status file in /run/. This avoids systemd PrivateTmp namespace
#     isolation and survives logouts, user switches and concurrent sessions.
#   * On a normal boot the file does not exist, so we exit immediately with
#     ~2 ms overhead and no popup.
set -u -o pipefail

PROGRESS_FILE="/run/agentic-firstboot-progress"

# Nothing to watch: first-boot setup is not currently running.
[ -f "$PROGRESS_FILE" ] || exit 0

# Bail out cleanly if zenity is not installed.
command -v zenity >/dev/null 2>&1 || exit 0

(
    while [ -f "$PROGRESS_FILE" ]; do
        PCT=$(sed -n '1p' "$PROGRESS_FILE" 2>/dev/null || echo 0)
        MSG=$(sed -n '2p' "$PROGRESS_FILE" 2>/dev/null || echo "Configuring system...")

        # Clamp percentage below 100 while still running so OK doesn't activate early
        #if [[ "$PCT" =~ ^[0-9]+$ ]] && [ "$PCT" -ge 100 ]; then
        #    PCT=99
        #fi

        echo "${PCT:-0}" || exit 0
        echo "# ${MSG:-Configuring system...}" || exit 0

        sleep 0.5
    done

    echo "100"
    echo "# Setup complete!"
) | zenity --progress \
    --title="Fedora Agentic Setup" \
    --text="Initializing background setup..." \
    --cancel-label="Hide" \
    --ok-label="OK" \
    --percentage=0 \
    --width=420 || true

/usr/local/libexec/create-shortcuts.sh ~/Desktop || true

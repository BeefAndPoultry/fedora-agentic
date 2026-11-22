#!/usr/bin/env bash
#
# Fedora Agentic first-boot progress UI.
#
# Launched automatically on every KDE login (see
# /etc/xdg/autostart/agentic-firstboot-ui.desktop). It watches the atomic
# status file written by agentic-firstboot.service and, while first-boot setup
# is running, shows a native kdialog progress bar that updates live.
#
# Design notes:
#   * The producer (agentic-firstboot.sh) and this watcher are decoupled through
#     an atomic status file in /run/. This avoids systemd PrivateTmp namespace
#     isolation and survives logouts, user switches and concurrent sessions.
#   * On a normal boot the file does not exist, so we exit immediately with
#     ~2 ms overhead and no popup.

set -u

PROGRESS_FILE="/run/agentic-firstboot-progress"

# Nothing to watch: first-boot setup is not currently running.
[ -f "$PROGRESS_FILE" ] || exit 0

# Only make sense under KDE; bail out elsewhere without erroring the autostart.
command -v kdialog >/dev/null 2>&1 || exit 0
command -v qdbus-qt6 >/dev/null 2>&1 || exit 0

DBUS_REF=$(kdialog --title "Fedora Agentic Setup" --progressbar "Initializing background setup..." 100)

while [ -f "$PROGRESS_FILE" ]; do
    PCT=$(sed -n '1p' "$PROGRESS_FILE" 2>/dev/null || echo 0)
    MSG=$(sed -n '2p' "$PROGRESS_FILE" 2>/dev/null || echo "Configuring system...")

    # If the user closed the window, qdbus calls fail and we stop cleanly
    # without touching the producer.
    qdbus-qt6 "$DBUS_REF" Set "" "" "$PCT" >/dev/null 2>&1 || break
    qdbus-qt6 "$DBUS_REF" setLabelText "$MSG" >/dev/null 2>&1 || break

    sleep 0.5
done

qdbus-qt6 "$DBUS_REF" close >/dev/null 2>&1 || true

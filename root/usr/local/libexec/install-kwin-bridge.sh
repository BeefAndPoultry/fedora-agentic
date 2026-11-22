#!/bin/bash
# Install + enable the Fedora Agentic KWin bridge (issue #49, Phase 1 — KWin
# side). This is a POST-INSTALL helper run inside an active KDE session, NOT at
# KIWI image-build time (there is no KWin on a builder). It is opt-in: nothing
# runs until the user or admin invokes it.
#
# It only touches things that exist; if any KDE tooling is missing it prints a
# hint and exits 0 so the script never blocks a larger first-boot flow.
set -uo pipefail

BRIDGE_ID="kwin-bridge"
DBUS_SERVICE="org.fedora.Agentic.KWin"
# Package source shipped in the image. Overridable for local installs / CI.
PKG_DIR="${1:-/usr/share/kwin-scripts/${BRIDGE_ID}}"
WINRC_FILE="${WINRC_FILE:-$XDG_CONFIG_HOME/kwinrc}"

if [ ! -f "${PKG_DIR}/metadata.json" ]; then
    echo "install-kwin-bridge: package not found at ${PKG_DIR}" >&2
    echo "Usage: $0 [/path/to/kwin-bridge]" >&2
    exit 1
fi

# 1. Install the KWin package into the user's (or system-wide) script store.
if command -v kpackagetool6 >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ] && [ -d /usr/share/plasma/kwin/scripts ]; then
        echo "Installing ${BRIDGE_ID} system-wide..."
        kpackagetool6 --global --type=KWin/Script --install "${PKG_DIR}"
    else
        echo "Installing ${BRIDGE_ID} for the current user..."
        kpackagetool6 --type=KWin/Script --install "${PKG_DIR}"
    fi
else
    echo "kpackagetool6 not found — install plasma-sdk or kpackagetool6 to add scripts." >&2
fi

# 2. Enable the plugin in kwinrc. kwriteconfig6 edits KConfig atomically; if it
#    is missing fall back to a safe append so the key still lands.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file "${WINRC_FILE}" --group Plugins --key "${BRIDGE_ID}Enabled" true
else
    echo "kwriteconfig6 not found — editing kwinrc manually." >&2
    mkdir -p "$(dirname "${WINRC_FILE}")"
    grep -q "^${BRIDGE_ID}Enabled" "${WINRC_FILE}" 2>/dev/null || \
        printf '%sEnabled=true\n' "${BRIDGE_ID}" >> "${WINRC_FILE}"
fi

# 3. Reload KWin so it loads the newly enabled script. Requires a live KWin on
#    session D-Bus; absent that, tell the user to reconfigure / log in again.
if command -v qdbus6 >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    qdbus6 org.kde.KWin /KWin reconfigure
    echo "KWin reconfigured; ${BRIDGE_ID} should load on next KWin cycle."
else
    echo "No active KWin session detected — reconfigure KWin (or log in again) to activate ${BRIDGE_ID}." >&2
fi

echo "install-kwin-bridge: done. Ensure desktop-mcp owns ${DBUS_SERVICE} for the bridge to be useful."

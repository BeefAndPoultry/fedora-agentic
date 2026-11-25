#!/bin/bash
# Create desktop shortcuts for the Fedora Agentic agentic layer.
#
# These shortcuts are intentionally NOT shipped inside the image overlay (root/):
# they only exist once this script has run during first boot, so every user gets
# consistent entries that point at the API key, server URL and agent that were
# generated on this particular machine.
#
# Usage: create-shortcuts.sh <destination-directory>
#   The destination is where the four .desktop files are written. Common targets:
#     /etc/skel/Desktop         # new users get them on their Desktop after install
#     /usr/share/applications    # register them in the application launcher (all users)
#     ~/Desktop                 # current user's live Desktop (e.g. the running live user)
#
# If the destination basename is "Desktop", each entry is chmod +x so a double
# click on the desktop does not prompt to mark it executable; in applications/
# that mode bit is unnecessary and left off.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <destination-directory>" >&2
    echo "Examples:" >&2
    echo "  $0 /etc/skel/Desktop" >&2
    echo "  $0 /usr/share/applications" >&2
    echo "  $0 ~/Desktop" >&2
    exit 1
fi

DEST="$1"
# Expand a literal leading ~ so callers passing ~/Desktop work even when the
# expansion was left to this script (the caller may already expand it, in which
# case this is a no-op).
case "${DEST}" in
    ~/*) DEST="${HOME}/${DEST#~/}" ;;
esac

if [ -z "${DEST}" ] || [ ! -d "${DEST}" ]; then
    echo "create-shortcuts: empty or missing destination: ${DEST}" >&2
    exit 1
fi

mkdir -p "${DEST}"

# Whether this looks like a per-user Desktop (vs. an applications/ registry dir).
desktop_dir=false
if [ "$(basename "${DEST}")" = "Desktop" ]; then
    desktop_dir=true
fi

# Substitutes ${API_KEY_FILE} with its literal path so the .desktop entry is a
# valid, self-contained URL (freedesktop files do not do shell expansion), and
# appends the trailing newline the freedesktop spec requires.
render() {
    printf '%s\n' "${1}" | sed "s|\${API_KEY_FILE}|${API_KEY_FILE}|g"
}

# write_desktop <file> <executable?> <contents-string>
write_desktop() {
    local file="$1" exec_mode="$2" contents="$3"
    # Never clobber an existing, intentionally different launcher.
    if [ -e "${file}" ]; then
        echo "create-shortcuts: ${file} already exists; skipping." >&2
        return 0
    fi
    render "${contents}" > "${file}"
    if [ "${exec_mode}" = "yes" ]; then
        chmod 0755 "${file}"
    fi
}

API_KEY_FILE="/etc/llama-cpp/apikey"

# 1. llama.cpp web UI (mirrors the pre-existing root/etc/skel/Desktop entry).
write_desktop "${DEST}/llama-cpp-webui.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" '[Desktop Entry]
Type=Link
URL=http://127.0.0.1:9931
Name=Fedora Agentic Web UI
Comment=Open the local llama.cpp inference server web UI
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;'

# 2. pi (the coding agent).
write_desktop "${DEST}/pi.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" '[Desktop Entry]
Type=Application
Name=pi
Comment=Run the pi coding agent
Icon=utilities-terminal
Exec=pi
Terminal=true
Categories=Development;Utility;'

# 3. sudo pi (pi with root privileges).
write_desktop "${DEST}/sudo-pi.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" '[Desktop Entry]
Type=Application
Name=Run pi As Admin
Comment=Run the pi coding agent with sudo
Icon=utilities-terminal
Exec=sudo pi
Terminal=true
Categories=System;Utility;'

# 4. The API key text file (opens /etc/llama-cpp/apikey in the file manager).
write_desktop "${DEST}/llama-cpp-apikey.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" '[Desktop Entry]
Type=Link
URL=file://${API_KEY_FILE}
Name=LLM API Key
Comment=Open the local llama.cpp inference server API key file
Icon=text-plain
Terminal=false
Categories=Utility;'

echo "create-shortcuts: wrote shortcuts to ${DEST}"

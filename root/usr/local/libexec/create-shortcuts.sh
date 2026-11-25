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
#     /usr/share/applications   # register them in the application launcher (all users)
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
# In an applications/ menu directory the freedesktop spec only allows Type=Application
# and Type=Service entries; Type=Link is valid inside Desktop directories only. When
# writing link-style entries to an applications/ dir we emit a Type=Application that
# launches the URL via xdg-open instead, so the entry is still valid there.
applications_dir=false
if [ "$(basename "${DEST}")" = "applications" ]; then
    applications_dir=true
fi

# Substitutes ${API_KEY_FILE} with its literal path so the .desktop entry is a
# valid, self-contained URL (freedesktop files do not do shell expansion).
render() {
    printf '%s\n' "${1}" | sed "s|\${API_KEY_FILE}|${API_KEY_FILE}|g"
}

# render_launcher <url> <name> <icon> <comment> <categories>
# Emits a native Type=Link entry for Desktop dirs, or a Type=Application wrapper
# that opens the URL via xdg-open for applications/ menu dirs (the only valid form).
render_launcher() {
    local url="$1" name="$2" icon="$3" comment="$4" categories="$5"
    if [ "${applications_dir}" = true ]; then
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Exec=xdg-open %s\n' "${url}"
        printf 'Name=%s\n' "${name}"
        printf 'Comment=%s\n' "${comment}"
        printf 'Icon=%s\n' "${icon}"
        printf 'Terminal=false\n'
        printf 'Categories=%s\n' "${categories}"
    else
        printf '[Desktop Entry]\n'
        printf 'Type=Link\n'
        printf 'URL=%s\n' "${url}"
        printf 'Name=%s\n' "${name}"
        printf 'Comment=%s\n' "${comment}"
        printf 'Icon=%s\n' "${icon}"
        printf 'Terminal=false\n'
        printf 'Categories=%s\n' "${categories}"
    fi
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
write_desktop "${DEST}/llama-cpp-webui.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" "$(render_launcher "http://127.0.0.1:9931" "Fedora Agentic Web UI" "web-browser" "Open the local llama.cpp inference server web UI" "Network;WebBrowser;")"

# 1b. Web UI as a plain URL entry for /usr/share/applications via the same mechanism.
write_desktop "${DEST}/llama-cpp-webui.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" "$(render_launcher "http://127.0.0.1:9931" "Fedora Agentic Web UI" "web-browser" "Open the local llama.cpp inference server web UI" "Network;WebBrowser;")"

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
write_desktop "${DEST}/llama-cpp-apikey.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" "$(render_launcher "file://${API_KEY_FILE}" "LLM API Key" "text-plain" "Open the local llama.cpp inference server API key file" "Utility;")"

# 4b. Follow the systemd logs for the llama.cpp inference server. Logs live on the
# systemd journal and are only readable with sudo, so launch journalctl -f to follow
# the unit live; Ctrl-C simply closes the terminal.
write_desktop "${DEST}/watch-llama-server.logs.desktop" "$([ ${desktop_dir} = true ] && echo yes || echo no)" '[Desktop Entry]
Type=Application
Name=llama-server Logs
Comment=Follow the systemd logs for the llama.cpp inference server
Icon=utilities-terminal
Exec=sudo journalctl -f -u llama-server.service
Terminal=true
Categories=System;Utility;'

echo "create-shortcuts: wrote shortcuts to ${DEST}"

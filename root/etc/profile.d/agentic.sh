# Agentic-layer environment for the local llama.cpp server.
#
# Sources the live connection details so any shell (and any OpenAI-compatible
# client) can reach the inference server and authenticate without reading pi's
# per-user config. Read from the same sources pi-config-sync.py uses:
#   /etc/sysconfig/llama-server   -> host, port
#   /etc/llama-cpp/apikey         -> world-readable API key
#   /var/lib/llama-cpp/models.ini -> the active preset's max context size
#
# Degrades to safe defaults if any file is missing so login never fails.

# Base URL from the systemd service's host/port config.
if [ -r /etc/sysconfig/llama-server ]; then
    # shellcheck disable=SC1091,SC1090
    . /etc/sysconfig/llama-server
fi
LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
LLAMA_PORT=${LLAMA_PORT:-9931}
export LLAMA_BASE_URL="http://${LLAMA_HOST}:${LLAMA_PORT}/"

# API key (world-readable; the server binds loopback only).
if [ -r /etc/llama-cpp/apikey ]; then
    # shellcheck disable=SC1090
    LLAMA_API_KEY=$(cat /etc/llama-cpp/apikey)
    export LLAMA_API_KEY
fi

# Maximum context size from the active model preset in models.ini.
# The first non-"*" section header names the chosen preset; its ctx-size is the
# window. Fall back to 65536 when the file is absent or unparsable.
LLAMA_MAX_CTX_SIZE=65536
if [ -r /var/lib/llama-cpp/models.ini ]; then
    _ini=$(mktemp) && cp /var/lib/llama-cpp/models.ini "$_ini" 2>/dev/null \
        || _ini=/var/lib/llama-cpp/models.ini
    in_active=0
    # Read line-by-line. Stop as soon as we leave the active section so a stray
    # ctx-size later in the file (e.g. inside [*] or an ignored preset) cannot
    # override the chosen one.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) : ;;                          # skip blanks and comments
            \[*\]*)                              # section header
                if [ "$in_active" -eq 1 ]; then
                    break
                fi
                case "$line" in
                    \[*\*\]) continue ;;          # skip the meta "[*]" section
                    *) in_active=1 ;;
                esac
                ;;
        esac
        if [ "$in_active" -eq 1 ]; then
            key=${line%%=*}
            value=${line#*=}
            # Trim surrounding whitespace from the key.
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            if [ "$key" = "ctx-size" ]; then
                # Trim surrounding whitespace from the value.
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                case "$value" in
                    ''|*[!0-9]*) : ;;   # keep the default on anything non-numeric
                    *) LLAMA_MAX_CTX_SIZE=$value ;;
                esac
            fi
        fi
    done < "$_ini"
    rm -f "$_ini"
fi
export LLAMA_MAX_CTX_SIZE

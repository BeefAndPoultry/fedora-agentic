#!/usr/bin/env python3
"""Reconcile a user's pi agent configuration with the live local LLM stack.

pi (``@earendil-works/pi-coding-agent``) talks to the bundled llama.cpp server
as an OpenAI-compatible client. Its configuration lives under
``~/.pi/agent/`` and is three small JSON files:

* ``auth.json``   - the API key and base URL used to reach the local server.
* ``models.json`` - the provider/model catalog plus the context window.
* ``settings.json`` - defaults (provider, model, thinking level) pi boots with.

Rather than shipping one static copy for every user, this script regenerates all
three from *live* sources at boot (as root, so every existing home is covered)
and again on each login (so a rotated API key or a freshly chosen model preset
is picked up):

* the API key comes from ``/etc/llama-cpp/apikey`` (generated at first boot);
* the host/port come from ``/etc/sysconfig/llama-server``;
* the model id and context size come from ``/var/lib/llama-cpp/models.ini``,
  the per-hardware preset written by ``llama-cpp-populate-models.py``.

It is deliberately defensive: any missing source file, missing pi install, or
parse problem degrades to safe defaults (or a no-op) and exits ``0`` so it can
safely run as an unattended login autostart entry that never blocks a session.
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import sys

DEFAULT_MODEL_ID = "default"
DEFAULT_CONTEXT_WINDOW = 65536
DEFAULT_THINKING_LEVEL = "medium"
PROVIDER = "llama.cpp"
HOST_DEFAULT = "127.0.0.1"
PORT_DEFAULT = 9931

API_KEY_PATH = "/etc/llama-cpp/apikey"
SERVICES_CONFIG_PATH = "/etc/sysconfig/llama-server"
MODELS_INI_PATH = "/var/lib/llama-cpp/models.ini"

def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--home",
        help="Target user home directory. Defaults to $HOME.",
    )
    return parser.parse_args(argv)


def read_env_file(path):
    """Read a ``KEY=value`` file (like /etc/sysconfig/<svc>) into a dict."""
    values = {}
    try:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip('"')
    except OSError:
        return None
    return values


def get_api_key():
    try:
        with open(API_KEY_PATH, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def parse_models_ini(path):
    """Return (model_id, context_size) for the active model preset.

    ``models.ini`` starts with a ``[*]`` global section followed by one or more
    model sections; the first non-``*`` section is the chosen preset. We read the
    section name (the pi model id) and its ``ctx-size`` (the context window).
    """
    model_id = None
    ctx_size = None
    try:
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.optionxform = str  # preserve original key case
        parser.read(path, encoding="utf-8")
    except OSError as exc:  # file missing
        print(f"pi-config-sync: {path} not found ({exc})")
        return model_id, ctx_size
    except configparser.Error as exc:
        print(f"pi-config-sync: could not parse {path}: {exc}")
        return model_id, ctx_size

    sections = parser.sections()
    if not sections:
        return None, None

    active = None
    for section in sections:
        if section == "*":
            continue
        active = section
        if parser.has_option(section, "ctx-size"):
            try:
                ctx_size = int(parser.get(section, "ctx-size"))
                break
            except (TypeError, ValueError):
                pass

    return active, ctx_size


def load_context():
    """Gather the values pi needs, degrading to safe defaults when a source is absent."""
    sysconfig = read_env_file(SERVICES_CONFIG_PATH)
    host = sysconfig.get("LLAMA_HOST") if sysconfig else None
    port = sysconfig.get("LLAMA_PORT") if sysconfig else None

    model_id, ctx_size = parse_models_ini(MODELS_INI_PATH)

    return {
        "api_key": get_api_key(),
        "host": host or HOST_DEFAULT,
        "port": int(port) if port and port.isdigit() else PORT_DEFAULT,
        "model_id": model_id or DEFAULT_MODEL_ID,
        "context_window": ctx_size or DEFAULT_CONTEXT_WINDOW,
    }


def write_config(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def build_configs(ctx):
    base = f"http://{ctx['host']}:{ctx['port']}"
    model_id = ctx["model_id"]
    context_window = ctx["context_window"]

    # Connection: the credential in auth.json (kept private) carries the API key
    # and LLAMA_BASE_URL. pi resolves that env var first, then normalizes it
    # (a trailing /v1 is stripped) and re-appends it for inference calls, so a
    # bare base here is correct and never doubles up into /v1/v1.
    auth = {
        PROVIDER: {
            "type": "api_key",
            "key": ctx["api_key"],
            "env": {
                "LLAMA_BASE_URL": base,
            },
        }
    }

    # Catalog: providers is keyed by provider id (an object, not a list), and
    # each provider's models is a list of model objects. Only the model id,
    # display name and the live context window matter here; pi fills the rest.
    models = {
        "providers": {
            PROVIDER: {
                "baseUrl": f"{base}/v1",
                "api": "openai-completions",
                "apiKey": "none", # this seems to make it use the api key from the auth.json file
                "models": [
                    {
                        "id": model_id,
                        "name": model_id,
                        "reasoning": True,
                        "contextWindow": context_window,
                        #"maxTokens": max(256, context_window // 16),
                    }
                ],
            }
        }
    }

    settings = {
        "lastChangelogVersion": "1.6.0",
        "httpIdleTimeoutMs": 0,
        "extensions": ["+builtin:llama.cpp"],
        "defaultProvider": PROVIDER,
        "defaultModel": model_id,
        #"defaultThinkingLevel": DEFAULT_THINKING_LEVEL,
        "hideThinkingBlock": True, # maybe depending on computer speed
    }

    return {
        "auth.json": auth,
        "models.json": models,
        "settings.json": settings,
    }


def sync_home(home):
    if not home or not os.path.isdir(home):
        print(f"pi-config-sync: skipping, no such user home '{home}'")
        return False

    ctx = load_context()
    configs = build_configs(ctx)
    agent_dir = os.path.join(home, ".pi", "agent")

    for name, data in configs.items():
        write_config(os.path.join(agent_dir, name), data)

    print(f"pi-config-sync: wrote {len(configs)} file(s) to {agent_dir}")
    return True


def enumerate_user_homes():
    """Home directories that should receive pi configuration.

    ``/root`` (the admin) and ``/home/*`` (local users). This is what the first
    boot step calls so every existing user gets working configs before they log
    in; subsequent logins are handled by the per-user autostart entry.
    """
    homes = []
    if os.path.isdir("/root"):
        homes.append("/root")
    try:
        entries = os.listdir("/home")
    except OSError:
        return homes
    for entry in sorted(entries):
        path = os.path.join("/home", entry)
        if os.path.isdir(path):
            homes.append(path)
    return homes


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])

    if args.home:
        sync_home(args.home)
        return 0

    # No explicit target: follow $HOME for the current login, or enumerate every
    # user's home when running as root (the first-boot case).
    if os.geteuid() == 0:
        homes = enumerate_user_homes()
    else:
        home = os.environ.get("HOME")
        homes = [home] if home else []

    synced = False
    for home in homes:
        if sync_home(home):
            synced = True

    return 0 if homes else 1


if __name__ == "__main__":
    raise SystemExit(main())

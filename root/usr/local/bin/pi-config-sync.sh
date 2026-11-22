#!/bin/bash
# Reconcile the current user's pi agent configuration on every login.
#
# pi (@earendil-works/pi-coding-agent) reaches the bundled llama.cpp server as an
# OpenAI-compatible client, so its config in ~/.pi/agent/ must always agree with
# the live server. This runs as a KDE autostart entry (see
# /usr/etc/xdg/autostart/pi-config-sync.desktop) and regenerates three files from
# sources written during first boot:
#   * auth.json        <- /etc/llama-cpp/apikey        (inference API key)
#   * models.json      <- /var/lib/llama-cpp/models.ini (model id + context size)
#   * settings.json    <- defaults (provider, model, thinking level)
#
# It is idempotent and best-effort: a missing source file or a failed pi install
# is ignored so desktop startup is never blocked. The first-boot script installs
# pi itself and pre-populates every existing user's home; this entry keeps those
# configs current (e.g. after an API-key rotation or a new model preset).
exec python3 /usr/local/libexec/pi-config-sync.py

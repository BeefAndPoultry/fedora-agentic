# kwin-bridge — Fedora Agentic KWin Bridge (issue #49, Phase 1)

A lightweight **KWin script** that gives the desktop layer visibility into and
control over Plasma windows. It is the **KWin-side half** of the KWin MCP Server
proposed in [issue #49](https://github.com/BeefAndPoultry/fedora-agentic/issues/49).

The full system is two parts:

1. **`kwin-bridge`** — this script, running inside KWin's scripting engine,
   serialises window state through the `workspace` API and talks to the daemon
   over session D-Bus.
2. **`desktop-mcp`** — a Rust stdio MCP daemon that owns the D-Bus service
   `org.fedora.Agentic.KWin` and exposes MCP tools
   (`list_windows`, `get_active_window`, `focus_window`, `move_window`,
   `minimize_window`, `maximize_window`).

This package is **Phase 1 (KWin side) only**. It is inert until the
`desktop-mcp` daemon owns that D-Bus service — every D-Bus call below is wrapped
in `try/catch` so a missing peer never floods KWin's log.

## Files

| Path | Purpose |
| ---- | ------- |
| `metadata.json` | KWin script package manifest (`KWin/Script`). |
| `contents/code/main.js` | The script: state polling + command queueing via D-Bus. |

## Install (post-install, inside a live KDE session)

```sh
/usr/local/libexec/install-kwin-bridge.sh
```

The helper installs the package with `kpackagetool6`, enables the plugin in
`kwinrc`, and reloads KWin via `qdbus6 org.kde.KWin /KWin reconfigure`. It is
opt-in and degrades gracefully: if any of those tools is missing it prints a
hint and exits 0, so it never blocks first-boot.

## Polling vs. event-driven

Phase 1 uses a **100 ms `QTimer`** poll for queued commands (see `main.js`).
Once `desktop-mcp` emits D-Bus signals, the bridge can switch to
event-driven delivery — see issue #49 for the open design question.

## D-Bus interface

| | Value |
| - | ----- |
| Service | `org.fedora.Agentic.KWin` |
| Path | `/org/fedora/Agentic/KWin` |
| Interface | `org.fedora.Agentic.KWin` |
| Methods | `UpdateState(string)`, `PopCommand(callable)` |

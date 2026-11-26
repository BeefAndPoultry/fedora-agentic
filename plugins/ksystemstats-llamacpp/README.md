# ksystemstats plugin for llama-server (router mode)

A native C++ `ksystemstats` sensor plugin that feeds
[plasma-systemmonitor](https://kde.org/products/plasma-systemmonitor/) live
telemetry from a **router-mode** [`llama-server`](https://github.com/ggml-org/llama.cpp)
instance — the same service this project runs as a systemd unit
(`root/etc/systemd/system/llama-server.service`, configured by
`root/etc/sysconfig/llama-server`).

The plugin shows up in System Monitor under *Providers → llama.cpp Server*:

| Object | Property | Prometheus metric | Meaning |
|--------|----------|-------------------|---------|
| Inference Router | Loaded Model | — | `id` of the one loaded model |
| Inference Router | Active Slots | — | slots with `is_processing == true` |
| Inference Router | Slots | — | total slots reported by `/slots` |
| Inference Router | KV Cache | `llamacpp:kv_cache_usage` | KV-cache occupancy, 0–100 |
| Inference Router | Prompt t/s | `llamacpp:prompt_tokens_seconds` | prompt processing throughput |
| Inference Router | Gen t/s | `llamacpp:predicted_tokens_seconds` | token generation throughput |
| Inference Router | Tokens | `llamacpp:tokens_predicted_total` | cumulative tokens predicted |

The plugin ships into the image from the **source** in this folder; GitHub
Actions compiles the `.so` and copies it into the image overlay at
`root/usr/lib64/qt6/plugins/ksystemstats/` (see `.github/workflows/build.yml`).
Do **not** commit a prebuilt binary.

## Why a plugin instead of curl in the panel widget?

`ksystemstats` lets plasma-systemmonitor pull sensor data as native system
statistics — so the llama.cpp numbers appear alongside CPU/memory/disk metrics,
with no polling loop living in the desktop widget. The plugin only touches
`llama-server` while a property is actually subscribed (zero idle overhead).

## Router-mode correctness rule (read this before editing)

`llama-server` can run in **router mode**: several GGUFs are registered in
`models.preset`, but only one is `loaded` at a time. Every query the plugin
makes **must** follow this sequence, or you risk triggering `--models-autoload`
and loading an extra GGUF into VRAM for nothing:

1. `GET /models`, scan for the entry whose `status.value == "loaded"`.
2. Take that entry's `id`.
3. Query `/slots?model=<id>` and `/metrics?model=<id>` **only** for that id.

The plugin never queries `/slots` or `/metrics` for any other model, and never
before it has found the loaded one. If no model is loaded, all sensors go idle.

## Local build / verify

Requires Fedora 45+ development packages (also what CI installs in
`.github/workflows/build.yml`):

```bash
sudo dnf install -y cmake gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel 'cmake(Qt6Core)' 'cmake(Qt6Network)' \
    'cmake(KF6CoreAddons)' 'cmake(KF6I18n)' \
    libksysguard-devel lm-sensors-devel
```

The `cmake(Qt6Core)`, `cmake(KF6CoreAddons)` … specs install any package that
provides those CMake config files and are immune to KF6 dev-package name drift
(e.g. the old `kf6-coreaddons-devel` names no longer resolve on Fedora 45).
`libksysguard-devel` pulls in the `kf6-ki18n-devel` the KF6::I18n link needs as a
dependency.

`lm-sensors-devel` provides the unversioned `/usr/lib64/libsensors.so` linker
symlink: `KSysGuard::SystemStats` (via `libksysguard`) links lm_sensors, and the
plugin's link step references that symlink through CMake's imported target —
without it, make aborts with `No rule to make target '/usr/lib64/libsensors.so'`.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

The result is `build/lib64/qt6/plugins/ksystemstats/libksystemstats_plugin_llamacpp.so`
plus `metadata.json` next to it. To install into the system plugin dir for a
manual smoke test:

```bash
sudo cmake --install build   # places .so + metadata.json in lib64/qt6/plugins/ksystemstats
# (re)start plasma-systemmonitor, add "llama.cpp Server" provider, and tick a sensor
```

`KSysGuard::SystemStats` (the `libksysguard-devel` package) is the only thing
that exposes the `SensorPlugin`/`SensorContainer`/`SensorProperty` API the plugin
builds on; everything else is Qt6 + KF6 CoreAddons/I18n.

### Overriding the server target

The plugin reads `LLAMA_HOST`/`LLAMA_PORT` from
`/etc/sysconfig/llama-server` (default `http://127.0.0.1:9931`, matching the
service) and the API key from `/etc/llama-cpp/apikey`. Override either without
rebuilding:

```bash
export LLAMA_SERVER_URL="http://host:port"   # wins outright
# or
export LLAMA_HOST=host LLAMA_PORT=port
export LLAMA_API_KEY=secret                   # overrides the key file
```

This is also what makes the plugin safe to load in CI — with no server running,
`GET /models` fails and every sensor reads "Offline" instead of crashing the
factory.

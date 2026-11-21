#!/usr/bin/env python3
"""Pick a model preset from this machine's specs and write models.ini.

The output path is /var/lib/llama-cpp/models.ini, inside the llama.cpp
StateDirectory. That matters because the systemd service runs as a DynamicUser
(no root), so we cannot write into /etc here -- only inside the user-owned
StateDirectory.

Tier selection (highest matching tier wins):

    1) >= 32 GiB RAM AND >= 10 GiB VRAM
    2) >= 12 GiB RAM AND >= 8  GiB VRAM
    3) otherwise

VRAM is read from "available dedicated video memory" via `glxinfo`. If that
string is unavailable the script tries `nvidia-smi`, then AMD/Intel sysfs, and
finally falls back to 0 GiB so only integrated/no-gpu tiers are considered.
"""
import os
import shutil
import subprocess
import sys

MODELS_INI = "/var/lib/llama-cpp/models.ini"


def parse_glxinfo_vram():
    """Return available-dedicated VRAM in GiB from `glxinfo`, or None if absent."""
    glxinfo = shutil.which("glxinfo")
    if not glxinfo:
        return None
    try:
        out = subprocess.run(
            [glxinfo, "-t"], capture_output=True, text=True, timeout=10
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for line in out.splitlines():
        if "available dedicated video memory" in line.lower():
            parts = line.split(":")
            if len(parts) < 2:
                return None
            try:
                value, unit = parts[1].strip().split()
            except ValueError:
                return None
            try:
                size = float(value)
            except ValueError:
                return None
            unit = unit.lower()
            if unit == "mb":
                return size / 1024.0
            if unit == "gb":
                return size
            print(f"Unknown VRAM unit '{unit}' from glxinfo", file=sys.stderr)
            return None
    return None


def detect_vram_gb():
    """Best-effort VRAM in GiB. Returns 0 when detection fails entirely."""
    vram = parse_glxinfo_vram()
    if vram is not None:
        return vram

    nvidia_smi = shutil.which("nvidia-smi")
    if nvidia_smi:
        try:
            out = subprocess.run(
                [nvidia_smi, "--query-gpu=memory.total",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=10
            ).stdout.strip().splitlines()
            if out:
                return float(out[0].replace(",", "")) / 1024.0
        except (OSError, subprocess.SubprocessError, ValueError):
            pass

    for path in ("/sys/class/drm/card0/device/mem_info_vram_total",
                 "/sys/class/drm/card/device/mem_info_vram_total"):
        try:
            with open(path) as fh:
                return int(fh.read().strip()) / (1024 ** 3)
        except (OSError, ValueError):
            continue

    return 0.0


def get_mem_gb():
    """System RAM in GiB from /proc/meminfo."""
    with open("/proc/meminfo") as fh:
        for line in fh:
            if line.startswith("MemTotal:"):
                return int(line.split()[1]) / (1024 ** 2)
    return 0.0


def write_models_ini(model):
    lines = []
    lines.append("""
[*]
models-max = 1
n-gpu-layers = 999
load-mode = mmap
cache-type-k = q8_0
cache-type-v = q8_0
parallel = 1

    """)
    
    lines.append(f"[{model['name']}]")
    if "hf-file" in model:
        lines.append(f"hf-repo = {model['hf-repo']}")
        lines.append(f"hf-file = {model['hf-file']}")
    else:
        lines.append(f"hf-repo = {model['hf-repo']}")
    lines.append(f"ctx-size = {model['ctx-size']}")
    lines.append(f"load-on-startup = {str(model['load-on-startup']).lower()}")
    if "n-cpu-moe" in model:
        lines.append(f"n-cpu-moe = {model['n-cpu-moe']}")

    os.mkdir(os.path.dirname(MODELS_INI), exist_ok=True, parents=True)
    with open(MODELS_INI, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(MODELS_INI, 0o644)


def main():
    mem_gb = get_mem_gb()
    vram_gb = detect_vram_gb()
    print(f"Detected {mem_gb:.1f} GiB RAM, ~{vram_gb:.1f} GiB VRAM")

    tiers = [
        {
            "name": "tiel-35b",
            "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
            "hf-file": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
            "ctx-size": 65536,
            "load-on-startup": False,
            "min_ram_gb": 31,
            "min_vram_gb": 30,
        },
        {
            "name": "tiel-35b",
            "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
            "hf-file": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
            "ctx-size": 65536,
            "load-on-startup": False,
            "n-cpu-moe": 999,
            "moe-cache-mib": 4000,
            "moe-cache-cpu-share": 0.5,
            "min_ram_gb": 31,
            "min_vram_gb": 13,
        },
        {
            "name": "tiel-35b",
            "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
            "hf-file": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
            "ctx-size": 65536,
            "load-on-startup": False,
            "n-cpu-moe": 999,
            "moe-cache-mib": 2000,
            "moe-cache-cpu-share": 0.9,
            "min_ram_gb": 31,
            "min_vram_gb": 10.5,
        },
        {
            "name": "gemma4-e4b",
            "hf-repo": "google/gemma-4-E4B-it-qat-q4_0-gguf",
            "ctx-size": 16384,
            "load-on-startup": False,
            "min_ram_gb": 11,
            "min_vram_gb": 6.5,
        },
        {
            "name": "lfm3-1.7b",
            "hf-repo": "LiquidAI/LFM3-1.7B-GGUF",
            "hf-file": "LFM3-1.7B-QAD-Q4_0.gguf",
            "ctx-size": 16384,
            "load-on-startup": False,
            "min_ram_gb": 0,
            "min_vram_gb": 0,
        },
    ]

    for tier in tiers:
        if mem_gb >= tier["min_ram_gb"] and vram_gb >= tier["min_vram_gb"]:
            print(f"Selected model preset: {tier['name']}")
            write_models_ini(tier)
            return 0

    print("No matching tier found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

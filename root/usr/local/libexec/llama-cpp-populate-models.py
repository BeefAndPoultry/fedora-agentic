#!/usr/bin/env python3
"""Pick a model preset from this machine's specs and write models.ini.

The output path is /var/lib/llama-cpp/models.ini, inside the llama.cpp
StateDirectory. That matters because the systemd service runs as a DynamicUser
(no root), so we cannot write into /etc here -- only inside the user-owned
StateDirectory.

VRAM is read from "dedicated video memory" via `glxinfo`. If that
string is unavailable the script tries `nvidia-smi`, then AMD/Intel sysfs, and
finally falls back to 0 GiB so only integrated/no-gpu tiers are considered.
"""
import os
import shutil
import subprocess
import sys

MODELS_INI = "/var/lib/llama-cpp/models.ini"

# TODO: use llama-bench --hf-repo mradermacher/Tiny-LLM-GGUF --hf-file Tiny-LLM.IQ4_XS.gguf -p 4096 to determine speed
""" Benchmark results look like this for an RTX 2080:
| model                          |       size |     params | backend    | ngl |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --------------: | -------------------: |
| llama ?B IQ4_XS - 4.25 bpw     |   9.89 MiB |    12.99 M | CUDA       |  -1 |          pp4096 |  310068.02 ± 5274.59 |
| llama ?B IQ4_XS - 4.25 bpw     |   9.89 MiB |    12.99 M | CUDA       |  -1 |           tg128 |      5677.90 ± 42.00 |

old Intel iGPU gets 28459 pp, 444 tg

or maybe we can get enough info from vulkaninfo to skip the benchmark, we just need to know if the computer is unbareably slow like that old Intel iGPU
"""

def parse_eglinfo_vram():
    """Return dedicated VRAM in GiB from `glxinfo`, or None if absent."""
    eglinfo = shutil.which("eglinfo")
    if not eglinfo:
        return None
    try:
        out = subprocess.run(
            [eglinfo], capture_output=True, text=True, timeout=10
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None

    unified = False
    for line in out.splitlines():
        line = line.strip()
        if line == "Unified memory: yes":
            unified = True # TODO: treat this as half VRAM? or subtract min(half, 16GB)? or use available instead of total? need to exclude --moe-cache-mib for unified memory
        if line.startswith("Dedicated video memory:"):
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
    vram = parse_eglinfo_vram()
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


# Global list of expanded model presets. add_model_tier() fills this in from
# the nested definitions below, so main() only ever reads a flat list.
_registry = []


def add_model_tier(model):
    """Expand a nested model definition into individual flat presets.

    ``model`` holds the fields shared by every preset of one model -- name,
    hf-repo, hf-file, load-on-startup, and any default ubatch/ctx/flags. Its
    ``"tiers"`` list is a sequence of per-hardware presets; each preset only
    overrides the keys that differ from the base (ctx-size, cache-ram,
    min_ram_gb, min_vram_gb, moe-* params, ...).

    Every preset is written out as a fully-merged flat dict (base fields with
    that preset's values overlaid) and appended to the global registry. To
    *remove* a key inherited from the base (rather than override it), set the
    preset's value to ``None`` -- ``None`` means "delete this key".
    """
    base = {k: v for k, v in model.items() if k != "tiers"}
    for preset in model.get("tiers", []):
        tier = dict(base)
        for key, value in preset.items():
            if value is None:
                tier.pop(key, None)
            else:
                tier[key] = value
        _registry.append(tier)


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
load-mode = mmap
parallel = 1
no-mmproj-offload = true
dedup-cache-models = true
stop-timeout = 60
ctx-size = 65536
cpu-moe = true
cache-ram = 2000
reasoning-budget = 10000
reasoning-budget-message = ' [Reasoning budget exhausted. Proceeding to final response...]'
predict = 100000

    """)

    # TODO: read the /home/*/.llama-cpp/models.ini of every user, parse their contents, and add them to a `models` dictionary along with the `model` in the argument of this function
    
    lines.append(f"[{model['name']}]")
    for key in model:
        if key not in ("name", "min_ram_gb", "min_vram_gb"):
            value = model[key]
            # emit booleans as lowercase true/false; everything else str()'s naturally
            value = str(value).lower() if isinstance(value, bool) else value
            lines.append(f"{key} = {value}")

    os.makedirs(os.path.dirname(MODELS_INI), exist_ok=True)
    with open(MODELS_INI, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(MODELS_INI, 0o644)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    dry_run = "--dry-run" in argv or "-n" in argv

    def take_value(flag):
        if flag in argv:
            idx = argv.index(flag)
            try:
                return float(argv[idx + 1])
            except (IndexError, ValueError):
                print(f"Error: {flag} expects a number", file=sys.stderr)
                sys.exit(2)

    mem_gb = take_value("--mem-gb") or get_mem_gb()
    vram_gb = take_value("--vram-gb") or detect_vram_gb()

    if dry_run:
        print("Dry run selected model preset only (no models.ini written)")
    elif "--mem-gb" in argv or "--vram-gb" in argv:
        print("Using --mem-gb/--vram-gb overrides instead of hardware detection")

    print(f"Detected {mem_gb:.1f} GiB RAM, {vram_gb:.1f} GiB VRAM")

    for tier in _registry:
        if mem_gb >= tier["min_ram_gb"] and vram_gb >= tier["min_vram_gb"]:
            tier["alias"] = "default"
            print('Selected model preset:', repr(tier))
            if not dry_run:
                write_models_ini(tier)
            return 0

    print("No matching tier found", file=sys.stderr)
    return 1


# TODO: next llama release we can do https://huggingface.co/bartowski/Inkling-2-Mini-GGUF ? but it's a bit slower with more active params, might at least be better for people with 16GB RAM 12+GB RAM?

add_model_tier({
    "name": "tiel-35b",
    "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "hf-file": "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf",
    "load-on-startup": True,
    "cpu-moe": True,
    # KV cache is q8_0 from 11.5GB VRAM up; tiers below that are unquantized KV
    "cache-type-k": "q8_0",
    "cache-type-v": "q8_0",
    "cache-ram": 2500,
    "tiers": [
        # 44GB RAM / 30GB VRAM - high-end discrete GPU (unquantized KV, deeper ctx)
        {"min_ram_gb": 44, "min_vram_gb": 30,   "ctx-size": 131072, "cache-type-k": None, "cache-type-v": None, "ubatch-size": 2048, "cpu-moe": None, "cache-ram": 4000},
        # 31GB RAM / 22GB VRAM (unquantized KV, deeper ctx)
        {"min_ram_gb": 31, "min_vram_gb": 22,   "ctx-size": 131072, "cache-type-k": None, "cache-type-v": None, "ubatch-size": 3072, "moe-cache-mib": 10000, "cache-ram": 3000},
        # 31GB RAM / 15GB VRAM - Q8 KV offload to CPU
        {"min_ram_gb": 31, "min_vram_gb": 15,   "ctx-size": 81920, "ubatch-size": 2048, "moe-cache-mib": 6000, "moe-cache-cpu-share": 0.2},
        # 31GB RAM / 11.5GB VRAM
        {"min_ram_gb": 31, "min_vram_gb": 11.5, "ctx-size": 79872, "ubatch-size": 2048, "moe-cache-mib": 4000, "moe-cache-cpu-share": 0.5},
    ],
})

add_model_tier({
    "name": "tiel-35b",
    "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "hf-file": "Tiel-Coder-35B-A3B-UD-IQ4_XS.gguf",
    "load-on-startup": True,
    "cpu-moe": True,
    "ctx-size": 73728,
    "cache-type-k": "q8_0",
    "cache-type-v": "q8_0",
    "cache-ram": 2500,
    "min_ram_gb": 30,
    "tiers": [
        {"min_vram_gb": 10.5, "ubatch-size": 3072, "moe-cache-mib": 4000, "moe-cache-cpu-share": 0.5},
        {"min_vram_gb": 9.5,  "ubatch-size": 3072, "moe-cache-mib": 3000, "moe-cache-cpu-share": 0.6},
    ],
})

add_model_tier({
    "name": "tiel-35b",
    "hf-repo": "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF",
    "hf-file": "Tiel-Coder-35B-A3B-UD-IQ3_XXS.gguf",
    "load-on-startup": True,
    "cpu-moe": True,
    # Tieliq3_xxs batch 1024 65536 q8 4.3GB, batch 4096 5.4GB
    "ctx-size": 65536,
    "cache-type-k": "q8_0",
    "cache-type-v": "q8_0",
    "tiers": [
        {"min_ram_gb": 20, "min_vram_gb": 9.5, "ubatch-size": 3072, "moe-cache-mib": 4000, "moe-cache-cpu-share": 0.5, "cache-ram": 2500, "ctx-size": 73728},
        {"min_ram_gb": 15, "min_vram_gb": 9.5, "ubatch-size": 3072, "moe-cache-mib": 4000, "moe-cache-cpu-share": 0.5, "cache-ram": 1500}, # 16GB RAM 10GB VRAM
        {"min_ram_gb": 20, "min_vram_gb": 7.5, "ubatch-size": 2048, "moe-cache-mib": 2600, "moe-cache-cpu-share": 0.7, "cache-ram": 2500},
        {"min_ram_gb": 15, "min_vram_gb": 7.5, "ubatch-size": 2048, "moe-cache-mib": 2600, "moe-cache-cpu-share": 0.7, "cache-ram": 1500},
    ],
})

# https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF?show_file_info=Tiel-Coder-35B-A3B-UD-Q2_K_XL.gguf
# 65536 5.2GB, 131072 5.8GB, 262144 7.1GB Q8 KV, 131072 at full KV 7GB
# https://huggingface.co/peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP?show_file_info=Tiel-Coder-35B-A3B-MTP-UD-Q2_K_XL.gguf
# MTP adds 0.4GB?
#{
#    "name": "gemma4-e4b",
#    "hf-repo": "google/gemma-4-E4B-it-qat-q4_0-gguf",
#    "ctx-size": 16384, # 6.1 GB VRAM at 16384 ctx, 6.7 GB VRAM at 65536 ctx
#    "cache-type-k": "q8_0",
#    "cache-type-v": "q8_0",
#    "load-on-startup": True,
#    "min_ram_gb": 11,
#    "min_vram_gb": 7.5,
#}

# TODO: test Ling 3.0 Tiny 8b-a1b and Ornith 1.5 9b, ling has really slow prefill at depth maybe it will be fixed?
# ling 65536 q8 1024 ubatch-size 6GB, n-cpu-moe 2.4 GB
# add_model_tier({
#     "name": "ling-3-0-tiny",
#     "hf-repo": "bartowski/Ling-3.0-tiny-GGUF",
#     "hf-file": "Ling-3.0-tiny-Q4_K_M.gguf",
#     "load-on-startup": True,
#     "tiers": [
#         {"ctx-size": 65536, "cache-type-k": "q8_0", "cache-type-v": "q8_0", "ubatch-size": 1024, "n-cpu-moe": 999, "moe-cache-mib": 3000, "cache-ram": 2000, "min_ram_gb": 15, "min_vram_gb": 7.5},
#     ],
# })

# LFM 3 1.7b
# F16: 4.7GB 32768 q8, 5.2GB unquant 65536
# Q8_0 3.8GB 65536 ctx
# Q6_K 3.4GB ctx unquant 65536, 3GB with Q8 KV
# Q4_0 QAD 2.7GB at 65536 Q8 KV, 2.3GB at 16384 Q8 KV, 2.5GB at 32768 Q8 KV, 2.3GB at 16384 Q8 KV, 3GB at 65536 unquant, 3.2GB at 131072 Q8 KV, 3.9GB at 131072 unquant KV
# Q8 KV cache is about 1GB per 128k tokens
# add_model_tier({
#     "name": "lfm3-1.7b",
#     "hf-repo": "LiquidAI/LFM3-1.7B-GGUF",
#     "load-on-startup": True,
#     "tiers": [
#         {"hf-file": "LFM3-1.7B-Q6_K.gguf", "ctx-size": 81920, "min_ram_gb": 14, "min_vram_gb": 7},
#     ],
# })
add_model_tier({
    "name": "lfm3-1.7b",
    "hf-repo": "LiquidAI/LFM3-1.7B-GGUF",
    "load-on-startup": True,
    # KV cache is q8_0 except the Q6_K tier; ctx 65536 except the deepest tier
    "ctx-size": 65536,
    "cache-type-k": "q8_0",
    "cache-type-v": "q8_0",
    "tiers": [
        {"min_ram_gb": 11, "min_vram_gb": 5.5, "hf-file": "LFM3-1.7B-Q6_K.gguf", "cache-type-k": None, "cache-type-v": None, "cache-ram": 1600},
        {"min_ram_gb": 7, "min_vram_gb": 3.5,  "hf-file": "LFM3-1.7B-QAD-Q4_0.gguf", "cache-ram": 800}, # GTX 970
        {"min_ram_gb": 0, "min_vram_gb": 0,    "hf-file": "LFM3-1.7B-QAD-Q4_0.gguf", "ctx-size": 32768, "cache-ram": 600},
    ],
})

if __name__ == "__main__":
    sys.exit(main())

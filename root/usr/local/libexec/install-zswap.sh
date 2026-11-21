#!/usr/bin/env bash
set -euo pipefail

# 1. Verify root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

# 2. Verify an active disk swap device exists
if [[ -z "$(swapon --show --noheadings)" ]]; then
    echo "Warning: No active swapfile or swap partition detected."
    echo "zswap requires a backing swap device on disk to function."
fi

# Configuration parameters (adjust as needed)
COMPRESSOR="zstd"       # Options: zstd (better ratio), lz4 (faster)
ZPOOL="zsmalloc"        # Modern standard allocator
MAX_POOL_PERCENT="25"   # Max % of RAM zswap can use

# 3. Enable and configure zswap immediately at runtime via sysfs
echo "Applying zswap settings to the running kernel..."
if [[ -d /sys/module/zswap/parameters ]]; then
    echo "$COMPRESSOR" > /sys/module/zswap/parameters/compressor
    echo "$ZPOOL" > /sys/module/zswap/parameters/zpool
    echo "$MAX_POOL_PERCENT" > /sys/module/zswap/parameters/max_pool_percent
    echo 1 > /sys/module/zswap/parameters/enabled
else
    echo "Error: zswap kernel module parameters not found in /sys/module/zswap/parameters."
    exit 1
fi

# 4. Make changes persistent across reboots via GRUB
GRUB_FILE="/etc/default/grub"
ZSWAP_PARAMS="zswap.enabled=1 zswap.compressor=${COMPRESSOR} zswap.zpool=${ZPOOL} zswap.max_pool_percent=${MAX_POOL_PERCENT}"

if [[ -f "$GRUB_FILE" ]]; then
    echo "Updating $GRUB_FILE for persistence..."
    cp "$GRUB_FILE" "${GRUB_FILE}.bak"

    # Remove any pre-existing zswap.* arguments to avoid duplicates
    sed -i -E 's/[[:space:]]*zswap\.[a-z_]+=[a-zA-Z0-9_]+//g' "$GRUB_FILE"

    # Append the new zswap parameters to GRUB_CMDLINE_LINUX_DEFAULT
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
        sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${ZSWAP_PARAMS}\"|" "$GRUB_FILE"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${ZSWAP_PARAMS}\"" >> "$GRUB_FILE"
    fi

    # Regenerate GRUB configuration (supports Debian/Ubuntu and Fedora/RHEL)
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        if [[ -d /sys/firmware/efi ]] && [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
            grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
        else
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
    else
        echo "Warning: Could not find update-grub or grub2-mkconfig. Update your bootloader manually."
    fi
else
    echo "Warning: $GRUB_FILE not found. If you use systemd-boot, add these kernel parameters manually:"
    echo "  $ZSWAP_PARAMS"
fi

# ensure no zram
dnf remove -y zram-generator-defaults zram-generator || true
: > /etc/systemd/zram-generator.conf

# Create a Btrfs-compatible swapfile inside the /swap subvolume
btrfs filesystem mkswapfile --size 32g /swap/swapfile

# Enable it on boot
echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab

echo ""
echo "zswap is now active! Current status:"
grep -H . /sys/module/zswap/parameters/{enabled,compressor,zpool,max_pool_percent}

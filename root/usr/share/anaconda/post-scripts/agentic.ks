# can we set up zswap here? generate api key? install nvidia drivers?

%post

# 1. Configure Snapper for / (@root / root)
if [ "$(findmnt -n -o FSTYPE /)" = "btrfs" ] && [ ! -f /etc/snapper/configs/root ]; then
    snapper --no-dbus -c root create-config /
    restorecon -Rv /.snapshots
fi

# 2. Configure Snapper for /home (@home / home)
if [ "$(findmnt -n -o FSTYPE /home)" = "btrfs" ] && [ ! -f /etc/snapper/configs/home ]; then
    snapper --no-dbus -c home create-config /home
    snapper --no-dbus -c home set-config ALLOW_GROUPS=wheel
    restorecon -Rv /home/.snapshots
fi

# 3. Enable automatic timeline and cleanup timers (covers both configs)
if [ -f /etc/snapper/configs/root ] || [ -f /etc/snapper/configs/home ]; then
    systemctl enable snapper-timeline.timer snapper-cleanup.timer
fi

%end

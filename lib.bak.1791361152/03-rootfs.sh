#!/bin/sh
copy_rootfs() {
    log_info "copying rootfs..."
    mkdir -p "$TARGET"
    for d in bin etc home lib lib64 media opt root sbin srv usr var; do
        [ -e "/$d" ] && { log_info "  /$d"; cp -a "/$d" "$TARGET/" 2>/dev/null || true; }
    done
    mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/run" "$TARGET/tmp" "$TARGET/mnt" "$TARGET/media"
    chmod 1777 "$TARGET/tmp" 2>/dev/null || true
    chmod 0700 "$TARGET/root" 2>/dev/null || true
    log_ok "rootfs copied"
}
setup_target_skeleton() {
    mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/run" "$TARGET/tmp" "$TARGET/mnt" "$TARGET/media" "$TARGET/root" "$TARGET/home"
    chmod 1777 "$TARGET/tmp" 2>/dev/null || true
    chmod 0700 "$TARGET/root" 2>/dev/null || true
    echo "ame" > "$TARGET/etc/hostname"
    cat > "$TARGET/etc/hosts" << 'E1'
127.0.0.1 localhost
::1 localhost
127.0.1.1 ame.localdomain ame
E1
    cat > "$TARGET/etc/network/interfaces" << 'E2'
auto lo
iface lo inet loopback
E2
    mkdir -p "$TARGET/etc/elogind"
    cat > "$TARGET/etc/elogind/logind.conf" << 'E3'
[Login]
KillUserProcesses=no
RemoveIPC=no
E3
    mkdir -p "$TARGET/etc/runlevels/boot" "$TARGET/etc/runlevels/sysinit" "$TARGET/etc/runlevels/default" "$TARGET/etc/runlevels/shutdown"
    for s in bootmisc hostname hwclock modules swap sysctl syslog; do
        [ -e "$TARGET/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "$TARGET/etc/runlevels/boot/$s" 2>/dev/null || true
    done
    for s in devfs dmesg mdev; do
        [ -e "$TARGET/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "$TARGET/etc/runlevels/sysinit/$s" 2>/dev/null || true
    done
    for s in networking local default; do
        [ -e "$TARGET/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "$TARGET/etc/runlevels/default/$s" 2>/dev/null || true
    done
    log_ok "skeleton done"
}
write_fstab() {
    ep=$(blkid -s PARTUUID -o value "$P1")
    rp=$(blkid -s PARTUUID -o value "$P2")
    cat > "$TARGET/etc/fstab" << E4
PARTUUID=$rp / ext4 defaults,noatime 0 1
PARTUUID=$ep /boot vfat defaults,noatime 0 2
E4
    log_ok "fstab done"
}

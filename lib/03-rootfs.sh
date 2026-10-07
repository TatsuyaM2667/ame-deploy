#!/bin/sh
copy_rootfs() {
    log_info "copying rootfs (cp -a)..."
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
    log_info "target skeleton..."
    mkdir -p "$TARGET"/{proc,sys,dev,run,tmp,mnt,media,root,home}
    chmod 1777 "$TARGET/tmp" 2>/dev/null || true
    chmod 0700 "$TARGET/root" 2>/dev/null || true
    echo "ame" > "$TARGET/etc/hostname"
    cat > "$TARGET/etc/hosts" << 'HEOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   ame.localdomain ame
HEOF
    cat > "$TARGET/etc/network/interfaces" << 'IEOF'
auto lo
iface lo inet loopback
IEOF
    mkdir -p "$TARGET/etc/elogind"
    cat > "$TARGET/etc/elogind/logind.conf" << 'LEOF'
[Login]
KillUserProcesses=no
RemoveIPC=no
LEOF
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
    # シリアルコンソール
    if [ -f "$TARGET/etc/inittab" ]; then
        grep -q ttyS0 "$TARGET/etc/inittab" || \
            echo "ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100" >> "$TARGET/etc/inittab"
    fi
    log_ok "skeleton done"
}
write_fstab() {
    ep=$(blkid -s PARTUUID -o value "$P1")
    rp=$(blkid -s PARTUUID -o value "$P2")
    cat > "$TARGET/etc/fstab" << FEOF
PARTUUID=$rp  /      ext4  defaults,noatime  0 1
PARTUUID=$ep  /boot  vfat  defaults,noatime  0 2
FEOF
    log_ok "fstab generated"
}

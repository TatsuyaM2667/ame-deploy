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

    # /lib/firmware がコピーされたか確認（重要）
    if [ -d "/lib/firmware" ]; then
        log_info "  /lib/firmware ..."
        mkdir -p "$TARGET/lib/firmware"
        cp -a /lib/firmware/. "$TARGET/lib/firmware/" 2>/dev/null || true
    fi

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

    # ★ 重要: WiFi モジュールを強制ロード（Alpine mdev はデバイスID自動ロードしない）
    log_info "  forcing WiFi modules in /etc/modules"
    mkdir -p "$TARGET/etc/modules-load.d"
    cat > "$TARGET/etc/modules" << 'MOD'
# ame-deploy: WiFi modules (auto-load at boot)
rtw88_core
rtw88_pci
rtw88_8821ce
rtw88_8821cu
rtw88_8822be
rtw88_8822ce
rtw89_core
rtw89_pci
rtw89_8852ae
rtw89_8852be
rtw89_8852ce
iwlwifi
mt7921e
MOD
    log_ok "  /etc/modules written"

    # ★ i915 カーネルパラメータを設定（GuC/HuC 有効化）
    log_info "  writing /etc/modprobe.d/ame-i915.conf"
    mkdir -p "$TARGET/etc/modprobe.d"
    cat > "$TARGET/etc/modprobe.d/ame-i915.conf" << 'I915'
# ame-deploy: i915 GPU settings
options i915 enable_guc=3 enable_fbc=1 enable_psr=0
I915
    log_ok "  i915 modprobe.conf written"

    log_ok "skeleton done"
}
write_fstab() {
    ep=$(blkid -s PARTUUID -o value "$P1")
    rp=$(blkid -s PARTUUID -o value "$P2")
    cat > "$TARGET/etc/fstab" << E4
PARTUUID=$rp / ext4 defaults,noatime 0 1
PARTUUID=$ep /boot vfat defaults,noatime 0 1
E4
    log_ok "fstab done"
}

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
    # firmware 全体をコピー（重要）
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

    # WiFi モジュール強制ロード設定
    log_info "  /etc/modules (WiFi autoload)"
    cat > "$TARGET/etc/modules" << 'MOD'
# ame-deploy v8.0: WiFi modules
rtw88_core
rtw88_pci
rtw88_8821ce
rtw88_8821cu
rtw88_8822be
rtw88_8822ce
rtw88_8822cu
rtw88_8723de
rtw88_8723du
rtw89_core
rtw89_pci
rtw89_8851be
rtw89_8852ae
rtw89_8852be
rtw89_8852ce
iwlwifi
mt7921e
mt7921s
mt7921u
ath10k_pci
ath11k_pci
brcmfmac
MOD
    log_ok "  /etc/modules written"

    # i915 GuC/HuC 有効化
    log_info "  /etc/modprobe.d/ame-i915.conf"
    mkdir -p "$TARGET/etc/modprobe.d"
    cat > "$TARGET/etc/modprobe.d/ame-i915.conf" << 'I915'
options i915 enable_guc=3 enable_fbc=1 enable_psr=0
I915
    log_ok "  i915 modprobe.conf written"

    # wlroots 0.20+ 互換: DRM modifiers デフォルト無効
    log_info "  /etc/environment.d (wlroots compat)"
    mkdir -p "$TARGET/etc/environment.d"
    cat > "$TARGET/etc/environment.d/10-wlroots.conf" << 'WLR'
# ame-deploy: wlroots 0.20+ 互換性のためのデフォルト設定
# (Sway 1.12 + i915 で初期化ハングを回避)
WLR_DRM_NO_MODIFIERS=1
WLR_RENDERER_ALLOW_SOFTWARE=1
WLR_NO_HARDWARE_CURSORS=1
WLR_LIBINPUT_NO_DEVICES=1
WLR_RENDERER=pixman
WLR_DRM_NO_ATOMIC=1
WLR_DRM_NO_MODIFIERS=1
WLR_RENDERER_ALLOW_SOFTWARE=1
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=sway
WLR
    log_ok "  wlroots env written"

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

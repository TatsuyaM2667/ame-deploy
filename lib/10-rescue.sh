#!/bin/sh
fix_live_labels() {
    [ -f "$TARGET/etc/os-release" ] && sed -i 's/ (live)//g; s/(live)//g' "$TARGET/etc/os-release" 2>/dev/null || true
    cat > "$TARGET/etc/motd" << 'MOTD'
Welcome to Ame Linux

  ame-fetch         Show system info
  ame-wifi          Connect to WiFi
  ame-install       Package manager
  ame-fetch-deploy  Download & install ame-deploy
  ame-deploy        Launch installer

MOTD
    log_ok "  motd cleaned"
}

ensure_user_homes() {
    mkdir -p "$TARGET/home"
    [ -f "$TARGET/etc/passwd" ] || return 0
    awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
    while IFS='|' read -r u uid gid h; do
        [ -z "$u" ] && continue
        [ -z "$h" ] && h="/home/$u"
        mkdir -p "$TARGET/${h#/}"
        chown "$uid:$gid" "$TARGET/${h#/}" 2>/dev/null || true
    done < /tmp/ame-users.txt
    rm -f /tmp/ame-users.txt
    log_ok "  homes done"
}

install_all_services() {
    log_info "installing WiFi + DRM services"
    # wifi init
    mkdir -p "$TARGET/etc/init.d"
    cat > "$TARGET/etc/init.d/ame-wifi-init" << 'SVC'
#!/sbin/openrc-run
name="ame-wifi-init"
description="WiFi regulatory + rfkill + modules"
depend() { need localmount; after networkmanager; }
start() {
    ebegin "WiFi init"
    for m in rtw88_core rtw88_pci rtw88_8821ce rtw88_8821cu rtw88_8822be rtw88_8822ce \
             rtw89_core rtw89_pci rtw89_8852ae rtw89_8852be rtw89_8852ce \
             iwlwifi mt7921e ath10k_pci ath11k_pci brcmfmac; do
        modprobe "$m" 2>/dev/null || true
    done
    sleep 1
    command -v rfkill >/dev/null 2>&1 && rfkill unblock all 2>/dev/null || true
    command -v iw >/dev/null 2>&1 && iw reg set JP 2>/dev/null || true
    for iface in $(ls /sys/class/net/ 2>/dev/null | grep -E '^wl'); do
        ip link set "$iface" up 2>/dev/null || true
    done
    rc-service networkmanager status >/dev/null 2>&1 && rc-service networkmanager restart 2>/dev/null || true
    eend 0
}
SVC
    chmod +x "$TARGET/etc/init.d/ame-wifi-init"
    for lvl in default boot; do
        mkdir -p "$TARGET/etc/runlevels/$lvl"
        ln -sf /etc/init.d/ame-wifi-init "$TARGET/etc/runlevels/$lvl/ame-wifi-init" 2>/dev/null || true
    done

    # drm fix
    cat > "$TARGET/etc/init.d/ame-drm-fix" << 'SVC'
#!/sbin/openrc-run
name="ame-drm-fix"
description="Ensure /dev/dri/card0 exists"
depend() { need localmount; }
start() {
    ebegin "DRM fix"
    mkdir -p /dev/dri
    if [ ! -e /dev/dri/card0 ]; then
        for c in /dev/dri/card1 /dev/dri/card2; do
            [ -e "$c" ] && { ln -sf "$c" /dev/dri/card0 2>/dev/null; break; }
        done
    fi
    if [ ! -e /dev/dri/renderD128 ]; then
        for r in /dev/dri/renderD129 /dev/dri/renderD130; do
            [ -e "$r" ] && { ln -sf "$r" /dev/dri/renderD128 2>/dev/null; break; }
        done
    fi
    eend 0
}
SVC
    chmod +x "$TARGET/etc/init.d/ame-drm-fix"
    for lvl in boot default; do
        mkdir -p "$TARGET/etc/runlevels/$lvl"
        ln -sf /etc/init.d/ame-drm-fix "$TARGET/etc/runlevels/$lvl/ame-drm-fix" 2>/dev/null || true
    done

    # regulatory
    mkdir -p "$TARGET/etc/conf.d"
    echo 'WIRELESS_REGDOM="JP"' > "$TARGET/etc/conf.d/wireless-regdom"

    log_ok "  services installed"
}

fix_wifi_force() {
    log_info "WiFi force fix"
    _mount_chroot_fs
    for pkg in linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtlwifi linux-firmware-rtl_nic linux-firmware-intel linux-firmware-mediatek linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm wireless-regdb crda iw rfkill; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && log_ok "  $pkg" || true
    done
    cat > "$TARGET/etc/modules" << 'MOD'
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
ath10k_pci
ath11k_pci
brcmfmac
MOD
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; depmod -a 2>/dev/null' || true
    _umount_chroot_fs
    for s in dbus elogind networkmanager wpa_supplicant seatd polkit; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    log_ok "WiFi force fix complete"
}

rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v9.0"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    fix_live_labels
    enable_edge

    install_kernel_pkg "linux-lts" || { log_err "kernel failed"; return 1; }
    install_kernel_firmware
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    log_ok "kernel: $KVER"

    generate_initramfs || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    fix_wifi_force
    install_all_services

    install_sway_complete

    ensure_user_homes

    log_ok "=========================================="
    log_ok " Rescue v9.0 COMPLETE"
    log_ok "=========================================="
    log_info "Kernel: $KVER"
    log_info "WiFi: ame-wifi-init service (reg JP + rfkill + modules)"
    log_info "Sway: ame-drm-fix (card0 symlink) + ame-start-sway"
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

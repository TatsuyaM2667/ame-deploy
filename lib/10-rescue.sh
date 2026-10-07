#!/bin/sh
fix_live_labels() {
    log_info "fixing live labels"
    [ -f "$TARGET/etc/os-release" ] && sed -i 's/ (live)//g; s/(live)//g' "$TARGET/etc/os-release" 2>/dev/null || true
    cat > "$TARGET/etc/motd" << 'MOTD'
Welcome to Ame Linux

  ame-fetch         Show system info
  ame-wifi          Connect to WiFi
  ame-install       Package manager
  ame-fetch-deploy  Download & install ame-deploy
  ame-deploy        Launch installer

MOTD
    log_ok "  motd/os-release cleaned"
}

ensure_user_homes() {
    log_info "creating home directories"
    mkdir -p "$TARGET/home"
    [ -f "$TARGET/etc/passwd" ] || return 0
    awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
    while IFS='|' read -r u uid gid h; do
        [ -z "$u" ] && continue
        [ -z "$h" ] && h="/home/$u"
        mkdir -p "$TARGET/${h#/}"
        chown "$uid:$gid" "$TARGET/${h#/}" 2>/dev/null || true
        log_ok "  $u -> $h"
    done < /tmp/ame-users.txt
    rm -f /tmp/ame-users.txt
}

migrate_wifi_settings() {
    log_info "WiFi settings migration"
    SRC="/etc/wpa_supplicant/wpa_supplicant.conf"
    DST="$TARGET/etc/wpa_supplicant/wpa_supplicant.conf"
    NMD="$TARGET/etc/NetworkManager/system-connections"
    mkdir -p "$TARGET/etc/wpa_supplicant" "$NMD"
    chmod 0700 "$NMD"
    [ -f "$SRC" ] || { log_info "  no live conf"; return 0; }
    cp "$SRC" "$DST"; chmod 0600 "$DST"
    log_ok "  wpa_supplicant.conf copied"
}

rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v7.0"
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

    # firmware 検証
    log_info "firmware verify..."
    if ! _verify_firmware; then
        log_warn "  firmware incomplete - retry"
        install_kernel_firmware
    fi
    _verify_firmware && log_ok "  firmware OK" || log_warn "  some firmware missing"

    generate_initramfs || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    # WiFi モジュール強制ロード設定
    mkdir -p "$TARGET/etc"
    if ! grep -q "rtw88_8821ce" "$TARGET/etc/modules" 2>/dev/null; then
        cat >> "$TARGET/etc/modules" << 'MOD'
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
        log_ok "  /etc/modules updated"
    fi

    # i915 modprobe
    mkdir -p "$TARGET/etc/modprobe.d"
    cat > "$TARGET/etc/modprobe.d/ame-i915.conf" << 'I915'
options i915 enable_guc=3 enable_fbc=1 enable_psr=0
I915

    # サービス
    for s in dbus elogind seatd polkit networkmanager wpa_supplicant; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    install_runtime_dir_service

    # Sway を必ず入れる
    install_sway_complete

    ensure_user_homes
    setup_autostart_sway

    log_ok "=========================================="
    log_ok " Rescue v7.0 COMPLETE"
    log_ok "=========================================="
    log_info "Kernel: $KVER"
    log_info "WiFi: /etc/modules + firmware"
    log_info "GPU: i915 GuC=3, kms feature in initramfs"
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

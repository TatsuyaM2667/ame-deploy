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
    log_ok "  motd/os-release cleaned"
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
        log_ok "  $u -> $h"
    done < /tmp/ame-users.txt
    rm -f /tmp/ame-users.txt
}

fix_wifi_force() {
    log_info "=== WiFi force fix ==="
    _mount_chroot_fs

    # 全 firmware インストール
    for pkg in linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtlwifi linux-firmware-rtl_nic linux-firmware-intel linux-firmware-mediatek linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && log_ok "  $pkg" || true
    done

    # .zst 展開
    chroot "$TARGET" /bin/sh -c 'command -v zstd >/dev/null 2>&1 && find /lib/firmware -name "*.zst" 2>/dev/null | while read f; do [ -f "${f%.zst}" ] || zstd -d -q "$f" -o "${f%.zst}" 2>/dev/null || true; done' || true

    # /etc/modules 強制書き込み
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
    log_ok "  /etc/modules written"

    # modprobe 手動実行（boot時と同じ挙動を保証）
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; depmod -a 2>/dev/null' || true

    _umount_chroot_fs

    # NetworkManager WiFi plugin + 設定
    mkdir -p "$TARGET/etc/NetworkManager/conf.d"
    cat > "$TARGET/etc/NetworkManager/conf.d/ame-wifi.conf" << 'NMC'
[device]
wifi.scan-rand-mac-address=no
wifi.backend=wpa_supplicant

[connection]
wifi.powersave=2
NMC

    for s in dbus elogind networkmanager wpa_supplicant seatd polkit; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    log_ok "WiFi force fix complete"
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
    log_info " Full Rescue v8.0"
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

    # initramfs 再生成（kms feature）
    generate_initramfs || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    # ESP 更新
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    # WiFi 完全修復
    fix_wifi_force
    migrate_wifi_settings

    # Sway 再インストール（バージョン互換ラッパー付き）
    install_sway_complete

    ensure_user_homes

    log_ok "=========================================="
    log_ok " Rescue v8.0 COMPLETE"
    log_ok "=========================================="
    log_info "Kernel: $KVER"
    log_info "WiFi: /etc/modules + firmware + NetworkManager"
    log_info "Sway: version-compat wrapper (ame-start-sway)"
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

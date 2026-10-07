#!/bin/sh
# ============================================================
# Full Rescue v3.0 — R コマンド1つで完全修復
# カーネル修復 + モジュール修復 + firmware + WiFi + DE + autostart + motd
# ============================================================

fix_live_labels() {
    log_info "fixing live labels"
    if [ -f "$TARGET/etc/os-release" ]; then
        sed -i 's/ (live)//g; s/(live)//g' "$TARGET/etc/os-release" 2>/dev/null || true
    fi
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

# 全ユーザー home + river config
ensure_user_homes() {
    log_info "creating home directories"
    mkdir -p "$TARGET/home"
    [ -f "$TARGET/etc/passwd" ] || return 0
    awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
    while IFS='|' read -r u uid gid h; do
        [ -z "$u" ] && continue
        [ -z "$h" ] && h="/home/$u"
        sub="${h#/}"
        mkdir -p "$TARGET/$sub"
        chown "$uid:$gid" "$TARGET/$sub" 2>/dev/null || true
        log_ok "  $u -> $h"
    done < /tmp/ame-users.txt
    rm -f /tmp/ame-users.txt
}

# WiFi 完全修復
fix_wifi_complete() {
    log_info "=== WiFi fix ==="
    _mount_chroot_fs

    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    if [ -n "$KVER" ]; then
        # モジュール検証
        if ! find "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" -name '*.ko*' 2>/dev/null | head -1 | grep -q .; then
            log_warn "  wireless modules missing - force reinstall linux-lts"
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk fix --force-missing-repositories linux-lts 2>&1 | tail -3'
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --force-reinstall --no-cache --force-missing-repositories linux-lts 2>&1 | tail -3'
        fi
    fi

    # firmware 全
    for pkg in linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtlwifi linux-firmware-rtl_nic linux-firmware-intel linux-firmware-mediatek linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k linux-firmware-brcm; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && log_ok "  $pkg" || true
    done

    # モジュール情報更新
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; depmod -a 2>/dev/null' || true

    _umount_chroot_fs

    # NetworkManager 設定
    mkdir -p "$TARGET/etc/NetworkManager/conf.d"
    cat > "$TARGET/etc/NetworkManager/conf.d/ame-wifi.conf" << 'NMC'
[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.powersave=2
NMC

    # サービス
    for s in dbus elogind networkmanager wpa_supplicant seatd polkit; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done

    log_ok "WiFi fix complete"
}

# WiFi 設定移行（live -> target）
migrate_wifi_settings() {
    log_info "=== WiFi settings migration ==="
    SRC_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    DST_CONF="$TARGET/etc/wpa_supplicant/wpa_supplicant.conf"
    NM_DIR="$TARGET/etc/NetworkManager/system-connections"

    mkdir -p "$TARGET/etc/wpa_supplicant" "$NM_DIR"
    chmod 0700 "$NM_DIR"

    if [ ! -f "$SRC_CONF" ]; then
        log_info "  no live wpa_supplicant.conf"
        return 0
    fi
    cp "$SRC_CONF" "$DST_CONF"
    chmod 0600 "$DST_CONF"
    log_ok "  wpa_supplicant.conf copied"

    awk '
    BEGIN { in_net=0; ssid=""; psk=""; key_mgmt=""; }
    /^[[:space:]]*network[[:space:]]*=/ { in_net=1; ssid=""; psk=""; key_mgmt=""; next }
    /^[[:space:]]*}/ {
        if (in_net && ssid != "") {
            gsub(/"/, "", ssid); gsub(/"/, "", psk); gsub(/"/, "", key_mgmt)
            print "SSID=" ssid; print "PSK=" psk; print "KEYMGMT=" key_mgmt; print "---"
        }
        in_net=0; next
    }
    in_net && /ssid[[:space:]]*=/ { sub(/.*=[[:space:]]*/, ""); ssid=$0; next }
    in_net && /psk[[:space:]]*=/  { sub(/.*=[[:space:]]*/, ""); psk=$0;  next }
    in_net && /key_mgmt[[:space:]]*=/ { sub(/.*=[[:space:]]*/, ""); key_mgmt=$0; next }
    ' "$DST_CONF" > /tmp/ame-wifi-networks.txt

    n=0; cur_ssid=""; cur_psk=""; cur_km=""
    while IFS= read -r line; do
        case "$line" in
            SSID=*)    cur_ssid="${line#SSID=}" ;;
            PSK=*)     cur_psk="${line#PSK=}" ;;
            KEYMGMT=*) cur_km="${line#KEYMGMT=}" ;;
            ---)
                [ -z "$cur_ssid" ] && continue
                fname=$(echo "$cur_ssid" | tr -c 'A-Za-z0-9._-' '_')
                nm_file="$NM_DIR/${fname}.nmconnection"
                km="wpa-psk"
                case "$cur_km" in
                    *WPA-EAP*) km="wpa-eap" ;;
                    *SAE*)     km="sae" ;;
                esac
                cat > "$nm_file" << NMEOF
[connection]
id=$cur_ssid
type=wifi
autoconnect=true
interface-name=wlan0

[wifi]
mode=infrastructure
ssid=$cur_ssid

[wifi-security]
key-mgmt=$km
psk=$cur_psk

[ipv4]
method=auto

[ipv6]
method=auto
NMEOF
                chmod 0600 "$nm_file"
                n=$((n+1))
                log_ok "  -> $cur_ssid"
                cur_ssid=""; cur_psk=""; cur_km=""
                ;;
        esac
    done < /tmp/ame-wifi-networks.txt
    rm -f /tmp/ame-wifi-networks.txt
    log_ok "  $n networks migrated"
}

# メイン rescue
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v3.0"
    log_info "=========================================="

    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    fix_live_labels
    enable_edge

    # 1) カーネル + モジュール（検証付き）
    install_kernel_pkg "linux-lts" || { log_err "kernel failed"; return 1; }
    install_kernel_firmware

    # 2) initramfs
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme"
MK
    img="initramfs-lts"
    case "$KVER" in
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac
    _mount_chroot_fs
    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then break; fi
        rm -f "$TARGET/boot/$img"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkdir -p /boot; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs
    _verify_initramfs "$TARGET/boot/$img" || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    # 3) ESP
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    # 4) WiFi 完全修復
    fix_wifi_complete

    # 5) WiFi 設定移行
    migrate_wifi_settings

    # 6) Sway 保証
    log_info "installing Sway (primary compositor)"
    install_sway_complete

    # 7) home
    ensure_user_homes

    # 8) autostart
    setup_autostart_sway

    # 9) 最終状態
    log_ok "=========================================="
    log_ok " Rescue v3.0 COMPLETE"
    log_ok "=========================================="
    log_info "Kernel: $KVER"
    log_info "WiFi: NetworkManager + wpa_supplicant + modules"
    log_info "Compositor: Sway (River fallback if available)"
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

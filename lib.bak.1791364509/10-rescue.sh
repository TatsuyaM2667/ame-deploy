#!/bin/sh
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v2.0.3"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    mkdir -p "$TARGET/home"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        _mount_chroot_fs
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
        _umount_chroot_fs
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel"; return 1; }
    log_ok "kernel: $KVER"
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
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    install_runtime_dir_service
    # home + river config 作成
    log_info "creating home directories"
    mkdir -p "$TARGET/home"
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
        while IFS='|' read -r uname uid gid home; do
            [ -z "$uname" ] && continue
            [ -z "$home" ] && home="/home/$uname"
            sub="${home#/}"
            target_home="$TARGET/$sub"
            mkdir -p "$target_home"
            chown "$uid:$gid" "$target_home" 2>/dev/null || true
            log_ok "  $uname -> $home (uid=$uid)"
            mkdir -p "$target_home/.config/river"
            sample_init="/usr/share/doc/river/examples/init"
            if [ -f "$TARGET$sample_init" ]; then
                cp "$TARGET$sample_init" "$target_home/.config/river/init"
            else
                cat > "$target_home/.config/river/init" << 'RC'
#!/bin/sh
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
riverctl map normal Super Return spawn foot
riverctl map normal Super D spawn fuzzel
riverctl map normal Super Q close
riverctl map normal Super+Shift E exit
riverctl modifier Super
RC
            fi
            chmod +x "$target_home/.config/river/init"
            chown -R "$uid:$gid" "$target_home/.config" 2>/dev/null || true
        done < /tmp/ame-users.txt
        rm -f /tmp/ame-users.txt
    fi
    if [ -d "$TARGET/root" ]; then
        mkdir -p "$TARGET/root/.config/river"
        sample_init="/usr/share/doc/river/examples/init"
        if [ -f "$TARGET$sample_init" ]; then
            cp "$TARGET$sample_init" "$TARGET/root/.config/river/init"
        else
            cat > "$TARGET/root/.config/river/init" << 'RC'
#!/bin/sh
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
riverctl map normal Super Return spawn foot
riverctl map normal Super D spawn fuzzel
riverctl map normal Super Q close
riverctl map normal Super+Shift E exit
riverctl modifier Super
RC
        fi
        chmod +x "$TARGET/root/.config/river/init"
    fi
    setup_autostart
    log_ok "=========================================="
    log_ok " Rescue v2.0.3 COMPLETE"
    log_ok "=========================================="
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

# ============ v2.0.4 rescue override ============
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v2.0.4"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    # kernel + initramfs はそのまま
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        _mount_chroot_fs
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
        _umount_chroot_fs
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel"; return 1; }
    log_ok "kernel: $KVER"

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

    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    install_runtime_dir_service

    # ★ 既存の壊れた river config を全部削除
    log_info "[cleanup] removing old river configs"
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $6}' "$TARGET/etc/passwd" > /tmp/ame-homes.txt
        while read -r h; do
            [ -z "$h" ] && continue
            sub="${h#/}"
            rm -rf "$TARGET/$sub/.config/river" 2>/dev/null || true
            log_ok "  cleaned $h/.config/river"
        done < /tmp/ame-homes.txt
        rm -f /tmp/ame-homes.txt
    fi
    rm -rf "$TARGET/root/.config/river" 2>/dev/null || true

    # ★ river-classic を試す
    log_info "[river] checking available packages"
    if chroot "$TARGET" /bin/sh -c 'apk search river 2>/dev/null | grep -q "^river-classic"'; then
        log_info "[river] installing river-classic"
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories river-classic 2>&1 | tail -3' || true
        pkgs_optional "river-tools" riverctl rivertile waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr
        _river_write_classic_configs
        setup_autostart_river
        log_ok "river-classic installed"
    else
        log_warn "[river] river-classic unavailable - installing Sway"
        install_sway_complete
        state_mark "de-sway"
    fi

    # home dirs 保証
    mkdir -p "$TARGET/home"
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
        while IFS='|' read -r uname uid gid home; do
            [ -z "$uname" ] && continue
            [ -z "$home" ] && home="/home/$uname"
            sub="${home#/}"
            mkdir -p "$TARGET/$sub"
            chown "$uid:$gid" "$TARGET/$sub" 2>/dev/null || true
        done < /tmp/ame-users.txt
        rm -f /tmp/ame-users.txt
    fi

    log_ok "=========================================="
    log_ok " Rescue v2.0.4 COMPLETE"
    log_ok "=========================================="
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

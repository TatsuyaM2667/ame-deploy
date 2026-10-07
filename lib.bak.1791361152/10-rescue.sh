#!/bin/sh
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    # kernel
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_info "installing kernel"
        _mount_chroot_fs
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
        _umount_chroot_fs
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel"; return 1; }
    log_ok "kernel: $KVER"

    # initramfs
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

    # ESP
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    # services
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done

    # runtime-dir
    install_runtime_dir_service

    # home + river config 保証
    for u in $(chroot "$TARGET" /bin/sh -c "awk -F: '\\\$3 >= 1000 && \\\$3 < 60000 {print \\\$1}' /etc/passwd" 2>/dev/null); do
        mkdir -p "$TARGET/home/$u"
        chroot "$TARGET" /bin/sh -c "chown $u:$u /home/$u 2>/dev/null" || true
        river_config_for "$u"
    done

    # autostart
    if chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
        setup_autostart
    elif chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        setup_autostart
    fi

    log_ok "=========================================="
    log_ok " Rescue COMPLETE"
    log_ok "=========================================="
    ls -la "$ESP/EFI/BOOT/"
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

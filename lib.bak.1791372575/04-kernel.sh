#!/bin/sh
_verify_kernel_modules() {
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || return 1
    MDIR="$TARGET/lib/modules/$KVER"
    need_wireless=0; need_drm=0; need_net=0
    find "$MDIR/kernel/drivers/net/wireless" -name '*.ko*' 2>/dev/null | head -1 | grep -q . && need_wireless=1
    find "$MDIR/kernel/drivers/gpu/drm" -name '*.ko*' 2>/dev/null | head -1 | grep -q . && need_drm=1
    find "$MDIR/kernel/drivers/net/ethernet" -name '*.ko*' 2>/dev/null | head -1 | grep -q . && need_net=1
    [ "$need_wireless" = "1" ] && [ "$need_drm" = "1" ] && [ "$need_net" = "1" ]
}
install_kernel_pkg() {
    KPKG="$1"
    log_info "installing $KPKG (with verification)"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    _mount_chroot_fs
    attempt=0; max_attempts=4
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt+1))
        log_info "  attempt $attempt/$max_attempts"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKG mkinitfs 2>&1 | tail -3"
        KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
        if [ -n "$KVER" ] && [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" ]; then
            log_ok "  wireless modules exist for $KVER"
            _umount_chroot_fs; return 0
        fi
        log_warn "  modules incomplete - force reinstall"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk fix --force-missing-repositories $KPKG 2>&1 | tail -3" || true
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --force-reinstall --no-cache --force-missing-repositories $KPKG 2>&1 | tail -3" || true
        KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
        if [ -n "$KVER" ] && [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" ]; then
            log_ok "  wireless modules now exist for $KVER"
            _umount_chroot_fs; return 0
        fi
        sleep 2
    done
    _umount_chroot_fs
    log_err "  $KPKG module verification failed after $max_attempts attempts"
    return 1
}
install_kernel_firmware() {
    log_info "installing all firmware packages"
    _mount_chroot_fs
    for pkg in \
        linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtlwifi \
        linux-firmware-rtl_nic linux-firmware-intel linux-firmware-mediatek \
        linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k \
        linux-firmware-brcm linux-firmware-amdgpu linux-firmware-i915 \
        linux-firmware-nvidia linux-firmware-qcom linux-firmware-marvell; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && \
            log_ok "  $pkg" || true
    done
    _umount_chroot_fs
}
select_and_install_kernel() {
    if state_done "kernel" && _verify_kernel_modules; then
        log_info "kernel already verified"
        echo "$(ls "$TARGET/lib/modules" | head -1)" > /tmp/ame-kver
        return 0
    fi
    echo "  Kernel:"
    echo "    [1] linux-lts    (recommended)"
    echo "    [2] linux-stable (edge, newest)"
    echo "    [3] linux-virt   (VM)"
    printf "  Select [1]: "; read kc
    [ -z "$kc" ] && kc="1"
    case "$kc" in
        1) KPKG="linux-lts" ;;
        2) KPKG="linux-stable" ;;
        3) KPKG="linux-virt" ;;
        *) log_err "invalid"; return 1 ;;
    esac
    enable_edge
    install_kernel_pkg "$KPKG" || { log_err "kernel install failed"; return 1; }
    install_kernel_firmware
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel modules"; return 1; }
    log_ok "kernel: $KVER"
    log_info "generating initramfs"
    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme i915 rtw88 rtw89"
MK
    # ★ initramfs 名を決定（v6.2.1 fix）
    img="initramfs-lts"
    case "$KVER" in
        *-lts)    img="initramfs-lts" ;;
        *-edge)   img="initramfs-edge" ;;
        *-stable) img="initramfs-stable" ;;
        *-virt)   img="initramfs-virt" ;;
    esac
    log_info "  initramfs name: $img"

    mkdir -p "$TARGET/boot"
    _mount_chroot_fs
    chroot "$TARGET" /bin/sh -c 'mkdir -p /boot'

    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then break; fi
        [ -f "$TARGET/boot/$img" ] && rm -f "$TARGET/boot/$img"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs

    if ! _verify_initramfs "$TARGET/boot/$img"; then
        log_err "initramfs generation failed"
        return 1
    fi
    log_ok "initramfs ready: /boot/$img"
    _verify_initramfs "$TARGET/boot/$img" || { log_err "initramfs failed"; return 1; }
    echo "$KVER" > /tmp/ame-kver
    echo "$img" > /tmp/ame-kinitrd
    state_mark "kernel"
    log_ok "kernel ready ($KVER)"
}

#!/bin/sh
_verify_kernel_modules() {
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || return 1
    MDIR="$TARGET/lib/modules/$KVER"
    ok=1
    find "$MDIR/kernel/drivers/net/wireless" -name '*.ko*' 2>/dev/null | head -1 | grep -q . || { log_warn "    wireless missing"; ok=0; }
    find "$MDIR/kernel/drivers/gpu/drm/i915" -name '*.ko*' 2>/dev/null | head -1 | grep -q . || { log_warn "    i915 missing"; ok=0; }
    find "$MDIR/kernel/drivers/net/ethernet" -name '*.ko*' 2>/dev/null | head -1 | grep -q . || { log_warn "    ethernet missing"; ok=0; }
    [ "$ok" = "1" ]
}

install_kernel_pkg() {
    KPKG="$1"
    log_info "installing $KPKG"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    _mount_chroot_fs
    attempt=0
    while [ $attempt -lt 4 ]; do
        attempt=$((attempt+1))
        log_info "  attempt $attempt/4"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKG mkinitfs 2>&1 | tail -2"
        if _verify_kernel_modules; then
            log_ok "  modules OK"
            _umount_chroot_fs; return 0
        fi
        log_warn "  force reinstall"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk fix --force-missing-repositories $KPKG >/dev/null 2>&1" || true
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --force-reinstall --no-cache --force-missing-repositories $KPKG >/dev/null 2>&1" || true
        sleep 2
    done
    _umount_chroot_fs
    log_err "  $KPKG install failed"
    return 1
}

install_kernel_firmware() {
    log_info "installing firmware packages"
    _mount_chroot_fs
    for pkg in \
        linux-firmware-i915 linux-firmware-intel linux-firmware-amdgpu \
        linux-firmware-nvidia linux-firmware-rtw88 linux-firmware-rtw89 \
        linux-firmware-rtlwifi linux-firmware-rtl_nic \
        linux-firmware-mediatek linux-firmware-brcm \
        linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k \
        linux-firmware-qcom linux-firmware-marvell; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && \
            log_ok "  $pkg" || log_warn "  skip: $pkg"
    done
    # .zst 展開（ネットワーク接続なしでも読めるように）
    if command -v zstd >/dev/null 2>&1; then
        find "$TARGET/lib/firmware" -name '*.zst' -type f 2>/dev/null | while read -r f; do
            [ -f "${f%.zst}" ] || zstd -d -q "$f" -o "${f%.zst}" 2>/dev/null || true
        done
    fi
    _umount_chroot_fs
}

generate_initramfs() {
    log_info "generating initramfs"
    _mount_chroot_fs
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { _umount_chroot_fs; log_err "no kernel"; return 1; }

    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme kms"
MK
    log_info "  features: ata base ide scsi usb virtio ext4 nvme kms"

    img="initramfs-lts"
    case "$KVER" in
        *-lts)    img="initramfs-lts" ;;
        *-stable) img="initramfs-stable" ;;
        *-virt)   img="initramfs-virt" ;;
    esac

    mkdir -p "$TARGET/boot"
    chroot "$TARGET" /bin/sh -c 'mkdir -p /boot'

    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        [ -f "$TARGET/boot/$img" ] && rm -f "$TARGET/boot/$img"
        log_info "  mkinitfs $i/3"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
        if _verify_initramfs "$TARGET/boot/$img"; then
            log_ok "  $img OK ($(stat -c %s "$TARGET/boot/$img") bytes)"
            break
        fi
    done
    _umount_chroot_fs

    if ! _verify_initramfs "$TARGET/boot/$img"; then
        log_err "initramfs generation failed"
        return 1
    fi
    echo "$KVER" > /tmp/ame-kver
    echo "$img"  > /tmp/ame-kinitrd
    return 0
}

select_and_install_kernel() {
    if state_done "kernel" && _verify_kernel_modules; then
        log_info "kernel already installed"
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

    generate_initramfs || return 1

    state_mark "kernel"
    log_ok "kernel ready ($KVER)"
}

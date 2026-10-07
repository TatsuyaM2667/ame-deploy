#!/bin/sh
_verify_kernel_modules() {
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || return 1
    MDIR="$TARGET/lib/modules/$KVER"

    ok=1
    # WiFi モジュール
    if ! find "$MDIR/kernel/drivers/net/wireless" -name '*.ko*' 2>/dev/null | head -1 | grep -q .; then
        log_warn "    wireless modules MISSING"
        ok=0
    fi
    # i915 モジュール
    if ! find "$MDIR/kernel/drivers/gpu/drm/i915" -name '*.ko*' 2>/dev/null | head -1 | grep -q .; then
        log_warn "    i915 modules MISSING"
        ok=0
    fi
    # Ethernet
    if ! find "$MDIR/kernel/drivers/net/ethernet" -name '*.ko*' 2>/dev/null | head -1 | grep -q .; then
        log_warn "    ethernet modules MISSING"
        ok=0
    fi

    [ "$ok" = "1" ]
}

_verify_firmware() {
    ok=1
    # i915 GuC/HuC
    if ! ls "$TARGET/lib/firmware/i915/"*guc*.bin >/dev/null 2>&1; then
        log_warn "    i915 GuC firmware MISSING"
        ok=0
    fi
    if ! ls "$TARGET/lib/firmware/i915/"*huc*.bin >/dev/null 2>&1; then
        log_warn "    i915 HuC firmware MISSING"
        ok=0
    fi
    # WiFi firmware
    if ! ls "$TARGET/lib/firmware/rtw88/"*.bin >/dev/null 2>&1; then
        log_warn "    rtw88 firmware MISSING"
        ok=0
    fi

    [ "$ok" = "1" ]
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

        if _verify_kernel_modules; then
            log_ok "  kernel modules OK"
            _umount_chroot_fs; return 0
        fi

        log_warn "  force reinstall $KPKG"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk fix --force-missing-repositories $KPKG 2>&1 | tail -2" || true
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --force-reinstall --no-cache --force-missing-repositories $KPKG 2>&1 | tail -2" || true
        sleep 2
    done
    _umount_chroot_fs
    log_err "  $KPKG install failed"
    return 1
}

install_kernel_firmware() {
    log_info "installing firmware packages"
    _mount_chroot_fs
    # 包括的 firmware
    for pkg in \
        linux-firmware-i915 \
        linux-firmware-intel \
        linux-firmware-amdgpu \
        linux-firmware-nvidia \
        linux-firmware-rtw88 \
        linux-firmware-rtw89 \
        linux-firmware-rtlwifi \
        linux-firmware-rtl_nic \
        linux-firmware-mediatek \
        linux-firmware-brcm \
        linux-firmware-ath10k \
        linux-firmware-ath11k \
        linux-firmware-ath12k \
        linux-firmware-qcom; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg 2>&1 | tail -1" && \
            log_ok "  $pkg" || log_warn "  skip: $pkg"
    done
    _umount_chroot_fs
}

generate_initramfs() {
    log_info "generating initramfs with KMS feature"
    _mount_chroot_fs

    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { _umount_chroot_fs; log_err "no kernel"; return 1; }

    # ★ mkinitfs.conf: 正しい feature 名を使用
    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
# ame-deploy: initramfs に必要な feature
# 注: kms = GPU ドライバ (i915, amdgpu等) + firmware を全部含める
features="ata base ide scsi usb virtio ext4 nvme kms"
MK
    log_info "  features: ata base ide scsi usb virtio ext4 nvme kms"

    img="initramfs-lts"
    case "$KVER" in
        *-lts)    img="initramfs-lts" ;;
        *-edge)   img="initramfs-edge" ;;
        *-stable) img="initramfs-stable" ;;
        *-virt)   img="initramfs-virt" ;;
    esac
    log_info "  initramfs name: $img"

    mkdir -p "$TARGET/boot"
    chroot "$TARGET" /bin/sh -c 'mkdir -p /boot'

    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then
            # initramfs に i915 firmware が入っているか確認
            tmp="/tmp/ir-check-$$"
            rm -rf "$tmp"; mkdir -p "$tmp"
            ( cd "$tmp" && zcat "$TARGET/boot/$img" 2>/dev/null | cpio -idm --quiet 2>/dev/null )
            has_i915_fw=0
            find "$tmp" -path '*i915*guc*' -o -path '*i915*huc*' 2>/dev/null | head -1 | grep -q . && has_i915_fw=1
            rm -rf "$tmp"

            if [ "$has_i915_fw" = "1" ]; then
                log_ok "  initramfs OK (with i915 firmware)"
                _umount_chroot_fs
                echo "$KVER" > /tmp/ame-kver
                echo "$img"  > /tmp/ame-kinitrd
                return 0
            else
                log_warn "  initramfs lacks i915 firmware - regenerating"
                rm -f "$TARGET/boot/$img"
            fi
        fi
        [ -f "$TARGET/boot/$img" ] && rm -f "$TARGET/boot/$img"
        log_info "  mkinitfs attempt $i/3"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs

    if ! _verify_initramfs "$TARGET/boot/$img"; then
        log_err "initramfs generation failed"
        return 1
    fi
    log_ok "initramfs ready: /boot/$img (with warnings)"
    echo "$KVER" > /tmp/ame-kver
    echo "$img"  > /tmp/ame-kinitrd
    return 0
}

select_and_install_kernel() {
    if state_done "kernel" && _verify_kernel_modules && _verify_firmware; then
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

    # firmware 検証
    log_info "verifying firmware..."
    if ! _verify_firmware; then
        log_warn "firmware incomplete - retrying..."
        install_kernel_firmware
        _verify_firmware || log_warn "some firmware still missing"
    else
        log_ok "firmware OK"
    fi

    generate_initramfs || return 1

    state_mark "kernel"
    log_ok "kernel ready ($KVER)"
}

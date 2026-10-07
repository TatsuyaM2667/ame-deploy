#!/bin/sh
# Full Rescue v0.9 - 壊れたインストールを全自動修復

rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v0.9"
    log_info "=========================================="

    # ---- 1. 自動マウント ----
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    # ---- 2. resolv.conf ----
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # ---- 3. edge repo ----
    log_info "[1/7] edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF

    # ---- 4. kernel install / repair ----
    log_info "[2/7] kernel"
    _mount_chroot_fs
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_info "installing linux-lts"
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { _umount_chroot_fs; log_err "no kernel modules"; return 1; }
    log_ok "kernel: $KVER"

    # ---- 5. initramfs 生成（3段フォールバック） ----
    log_info "[3/7] initramfs"
    img="initramfs-lts"
    case "$KVER" in
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac

    # 既存検証
    if _verify_initramfs "$TARGET/boot/$img"; then
        log_ok "existing initramfs valid"
    else
        rm -f "$TARGET/boot/$img"
        # a) mkinitfs
        for i in 1 2 3; do
            log_info "  mkinitfs attempt $i/3"
            chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkdir -p /boot; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
            _verify_initramfs "$TARGET/boot/$img" && { log_ok "  mkinitfs OK"; break; }
            sleep 2
        done
        # b) フォールバック
        if ! _verify_initramfs "$TARGET/boot/$img"; then
            log_warn "  mkinitfs failed - generating fallback initramfs"
            _generate_fallback_initramfs "$img" "$KVER"
        fi
    fi
    _umount_chroot_fs

    if ! _verify_initramfs "$TARGET/boot/$img"; then
        log_err "initramfs generation failed"
        return 1
    fi
    log_ok "initramfs ready: /boot/$img"

    # ---- 6. ESP update ----
    log_info "[4/7] ESP update"
    bootdir="$DEPLOY_DIR/boot"
    install_kernel_to_esp      || { log_err "kernel->ESP failed"; return 1; }
    install_initramfs_to_esp   || { log_err "initramfs->ESP failed"; return 1; }
    install_limine "$bootdir"  || { log_err "limine failed"; return 1; }
    write_limine_conf          || { log_err "limine.conf failed"; return 1; }
    register_uefi
    sync

    # ---- 7. services ----
    log_info "[5/7] services"
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done

    # ---- 8. runtime-dir ----
    log_info "[6/7] runtime-dir"
    install_runtime_dir_service

    # ---- 9. autostart ----
    log_info "[7/7] autostart"
    if [ -x "$TARGET/usr/bin/river" ] || [ -x "$TARGET/usr/local/bin/river" ]; then
        setup_generic_autostart "river"
        log_ok "River autostart"
    elif [ -x "$TARGET/usr/bin/sway" ]; then
        setup_generic_autostart "sway"
        log_ok "Sway autostart"
    elif [ -x "$TARGET/usr/bin/Hyprland" ]; then
        setup_generic_autostart "Hyprland"
        log_ok "Hyprland autostart"
    else
        log_warn "no DE binary found - install DE via [6]"
    fi

    # ---- 完了 ----
    echo
    log_ok "=========================================="
    log_ok " Full Rescue COMPLETE"
    log_ok "=========================================="
    echo "  ESP contents:"
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  Unmount and reboot:"
    echo "    sync; umount $ESP $TARGET; reboot"
    return 0
}

# ---- フォールバック initramfs（busybox ベース） ----
_generate_fallback_initramfs() {
    local img="$1" kver="$2"
    local tmp="$TARGET/tmp/fallback-ir"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    mkdir -p "$tmp/bin"
    mkdir -p "$tmp/dev"
    mkdir -p "$tmp/proc"
    mkdir -p "$tmp/sys"
    mkdir -p "$tmp/newroot"
    mkdir -p "$tmp/lib"
    mkdir -p "$tmp/lib/modules"

    # busybox を探す（target優先、無ければホストから）
    local bb=""
    for cand in "$TARGET/bin/busybox" "$TARGET/usr/bin/busybox" /bin/busybox /usr/bin/busybox; do
        if [ -f "$cand" ]; then bb="$cand"; break; fi
    done
    [ -n "$bb" ] || { log_err "no busybox found"; return 1; }
    log_info "  using busybox: $bb"

    cp "$bb" "$tmp/bin/busybox" || return 1
    chmod +x "$tmp/bin/busybox"
    ( cd "$tmp/bin" && ./busybox --install -s . 2>/dev/null ) || true

    # init スクリプト
    cat > "$tmp/init" << 'INITEOF'
#!/bin/busybox sh
/bin/busybox --install -s /bin 2>/dev/null
mount -t proc     none /proc 2>/dev/null
mount -t sysfs    none /sys  2>/dev/null
mount -t devtmpfs none /dev  2>/dev/null || mount -t tmpfs none /dev
mkdir -p /newroot
ROOT=$(cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep '^root=' | head -1 | cut -d= -f2-)
[ -z "$ROOT" ] && ROOT=/dev/sda2
echo "ame-initramfs: root=$ROOT"
i=0
while [ $i -lt 10 ]; do
    mount -o rw "$ROOT" /newroot 2>/dev/null && break
    sleep 1
    i=$((i+1))
done
if ! mountpoint -q /newroot; then
    echo "ame-initramfs: FAILED to mount $ROOT"
    exec /bin/sh
fi
echo "ame-initramfs: switch_root"
exec switch_root /newroot /sbin/init
INITEOF
    chmod +x "$tmp/init"

    # cpio 化
    ( cd "$tmp" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$TARGET/boot/$img" )
    rm -rf "$tmp"

    if _verify_initramfs "$TARGET/boot/$img"; then
        log_ok "fallback initramfs created"
        return 0
    fi
    log_err "fallback initramfs verify failed"
    return 1
}

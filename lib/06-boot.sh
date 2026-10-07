#!/bin/sh
# bootloader インストール v0.8.1 - initramfs 検証付き

get_target_kernel() {
    [ -f /tmp/ame-kimg ] && cat /tmp/ame-kimg && return
    for k in vmlinuz-lts vmlinuz-edge vmlinuz-virt; do
        [ -f "$TARGET/boot/$k" ] && echo "$k" && return
    done
    echo ""
}
get_target_initrd() {
    [ -f /tmp/ame-kinitrd ] && cat /tmp/ame-kinitrd && return
    for i in initramfs-lts initramfs-edge initramfs-virt; do
        [ -f "$TARGET/boot/$i" ] && echo "$i" && return
    done
    echo ""
}

ensure_initramfs() {
    local kver=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$kver" ] || { log_err "no kernel modules"; return 1; }

    local img="initramfs-${kver##*-}"
    case "$kver" in
        *-lts)  img="initramfs-lts" ;;
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac

    if [ -f "$TARGET/boot/$img" ]; then
        log_ok "initramfs exists: /boot/$img"
        echo "$img" > /tmp/ame-kinitrd
        return 0
    fi

    log_info "initramfs missing - generating via mkinitfs"

    # /proc /sys /dev マウント（mkinitfs 必須）
    _mount_chroot_fs

    # mkinitfs が無ければ入れる
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; command -v mkinitfs >/dev/null 2>&1 || apk add --no-cache --force-missing-repositories mkinitfs >/dev/null 2>&1'

    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$img $kver 2>&1 | tail -5"

    _umount_chroot_fs

    if [ -f "$TARGET/boot/$img" ]; then
        log_ok "initramfs generated: /boot/$img"
        echo "$img" > /tmp/ame-kinitrd
        return 0
    fi
    log_err "initramfs unavailable"
    return 1
}

install_kernel_to_esp() {
    local kimg=$(get_target_kernel)
    [ -n "$kimg" ] || { log_err "no kernel found"; return 1; }
    require_file "$TARGET/boot/$kimg" || return 1
    mkdir -p "$ESP/EFI/BOOT"
    cp "$TARGET/boot/$kimg" "$ESP/EFI/BOOT/vmlinuz-ame" || return 1
    log_ok "kernel copied ($kimg)"
}

install_initramfs_to_esp() {
    # まず initramfs の存在を保証
    ensure_initramfs || { log_err "initramfs unavailable"; return 1; }

    local kinitrd=$(get_target_initrd)
    if [ -n "$kinitrd" ] && [ -f "$TARGET/boot/$kinitrd" ]; then
        cp "$TARGET/boot/$kinitrd" "$ESP/EFI/BOOT/initramfs.cpio.gz"
        log_ok "initramfs copied ($kinitrd)"
        return 0
    fi
    log_err "initramfs still missing"
    return 1
}

install_limine() {
    log_info "Limine -> ESP"
    d="$1"
    mkdir -p "$ESP/EFI/BOOT"
    for f in BOOTX64.EFI limine-bios.sys; do
        [ -f "$d/$f" ] && cp "$d/$f" "$ESP/EFI/BOOT/$f" && log_ok "  $f"
    done
    [ -f "$ESP/EFI/BOOT/BOOTX64.EFI" ] || { log_err "BOOTX64.EFI missing"; return 1; }
    log_ok "Limine installed"
}

write_limine_conf() {
    # initramfs の有無で limine.conf を分岐
    if [ -f "$ESP/EFI/BOOT/initramfs.cpio.gz" ]; then
        rp=$(blkid -s PARTUUID -o value "$P2")
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    module_path: boot():/EFI/BOOT/initramfs.cpio.gz
    cmdline: console=tty0 quiet loglevel=3 root=PARTUUID=$rp rootfstype=ext4 rw
LEOF
        log_ok "limine.conf (with initramfs)"
    else
        # 最終手段: rootfs direct boot
        rp=$(blkid -s PARTUUID -o value "$P2")
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    cmdline: console=tty0 quiet loglevel=3 root=PARTUUID=$rp rootfstype=ext4 rw init=/sbin/init
LEOF
        log_warn "limine.conf (no initramfs - direct boot)"
    fi
}

register_uefi() {
    if command -v efibootmgr >/dev/null 2>&1; then
        efibootmgr --create --disk "$DEV" --part 1 --label "Ame Linux" --loader '\EFI\BOOT\BOOTX64.EFI' 2>/dev/null || true
        log_ok "UEFI entry registered"
    fi
}

install_bootloader_complete() {
    bootdir="$1"
    require_disk || return 1
    install_kernel_to_esp      || return 1
    install_initramfs_to_esp   || return 1
    install_limine "$bootdir"  || return 1
    write_limine_conf          || return 1
    register_uefi
    sync
    log_info "ESP contents:"
    ls -la "$ESP/EFI/BOOT/"
    state_mark "bootloader"
    return 0
}

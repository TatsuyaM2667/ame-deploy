#!/bin/sh
install_kernel() {
    log_info "kernel -> ESP"
    require_file "$1"
    mkdir -p "$ESP/EFI/BOOT"
    cp "$1" "$ESP/EFI/BOOT/vmlinuz-ame" || return 1
    log_ok "kernel copied"
}

install_initramfs() {
    i="$1"
    if [ -f "$i" ]; then
        cp "$i" "$ESP/EFI/BOOT/initramfs.cpio.gz"
        log_ok "initramfs copied"
    else
        log_warn "initramfs not provided - rootfs-direct boot"
    fi
}

install_limine() {
    log_info "Limine -> ESP"
    d="$1"
    mkdir -p "$ESP/EFI/BOOT"
    copied=0
    for f in BOOTX64.EFI limine-bios.sys; do
        if [ -f "$d/$f" ]; then
            cp "$d/$f" "$ESP/EFI/BOOT/$f"
            log_ok "  $f"
            copied=$((copied+1))
        else
            log_warn "  missing: $f"
        fi
    done
    [ -f "$ESP/EFI/BOOT/BOOTX64.EFI" ] || { log_err "BOOTX64.EFI not copied"; return 1; }
    log_ok "Limine installed ($copied files)"
}

write_limine_conf() {
    log_info "limine.conf"
    rp=$(blkid -s PARTUUID -o value "$P2")

    if [ -f "$ESP/EFI/BOOT/initramfs.cpio.gz" ]; then
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    module_path: boot():/EFI/BOOT/initramfs.cpio.gz
    cmdline: console=tty0 quiet loglevel=3
LEOF
    else
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    cmdline: console=tty0 quiet loglevel=3 root=PARTUUID=$rp rootfstype=ext4 rw init=/sbin/init
LEOF
    fi
    log_ok "limine.conf (root=$rp)"
}

register_uefi() {
    if command -v efibootmgr >/dev/null 2>&1; then
        efibootmgr --create --disk "$DEV" --part 1 \
            --label "Ame Linux" --loader '\EFI\BOOT\BOOTX64.EFI' 2>/dev/null || true
        log_ok "UEFI entry registered"
    else
        log_info "efibootmgr skip (BIOS fallback)"
    fi
}

install_bootloader_complete() {
    bootdir="$1"
    require_disk || return 1
    install_kernel "$bootdir/vmlinuz-ame" || return 1
    install_initramfs "$bootdir/initramfs.cpio.gz"
    install_limine "$bootdir" || return 1
    write_limine_conf || return 1
    register_uefi
    sync
    log_info "ESP contents:"
    ls -la "$ESP/EFI/BOOT/"
    return 0
}

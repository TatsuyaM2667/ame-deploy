#!/bin/sh
get_target_kernel() {
    for k in vmlinuz-lts vmlinuz-stable vmlinuz-virt; do
        [ -f "$TARGET/boot/$k" ] && echo "$k" && return
    done
    echo ""
}
get_target_initrd() {
    for i in initramfs-lts initramfs-stable initramfs-virt; do
        [ -f "$TARGET/boot/$i" ] && echo "$i" && return
    done
    echo ""
}
install_kernel_to_esp() {
    kimg=$(get_target_kernel)
    [ -n "$kimg" ] || { log_err "no kernel"; return 1; }
    mkdir -p "$ESP/EFI/BOOT"
    cp "$TARGET/boot/$kimg" "$ESP/EFI/BOOT/vmlinuz-ame" || return 1
    log_ok "kernel copied ($kimg)"
}
install_initramfs_to_esp() {
    kinitrd=$(get_target_initrd)
    if [ -n "$kinitrd" ] && [ -f "$TARGET/boot/$kinitrd" ]; then
        cp "$TARGET/boot/$kinitrd" "$ESP/EFI/BOOT/initramfs.cpio.gz"
        log_ok "initramfs copied ($kinitrd)"
        return 0
    fi
    log_err "no initramfs"
    return 1
}
install_limine() {
    d="$1"
    mkdir -p "$ESP/EFI/BOOT"
    for f in BOOTX64.EFI limine-bios.sys; do
        [ -f "$d/$f" ] && cp "$d/$f" "$ESP/EFI/BOOT/$f" && log_ok "  $f"
    done
    [ -f "$ESP/EFI/BOOT/BOOTX64.EFI" ] || { log_err "BOOTX64.EFI missing"; return 1; }
    log_ok "Limine installed"
}
write_limine_conf() {
    RD=""
    for cand in /dev/sda2 /dev/nvme0n1p2 /dev/vda2; do
        [ -b "$cand" ] && { RD="$cand"; break; }
    done
    [ -n "$RD" ] || { log_err "no root device"; return 1; }
    log_info "root device: $RD"

    # i915 は modprobe.d で設定するので cmdline では指定しない
    if [ -f "$ESP/EFI/BOOT/initramfs.cpio.gz" ]; then
        cat > "$ESP/EFI/BOOT/limine.conf" << L1
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    module_path: boot():/EFI/BOOT/initramfs.cpio.gz
    cmdline: console=tty0 loglevel=4 root=$RD rootfstype=ext4 rw rootwait
L1
        log_ok "limine.conf (initramfs, root=$RD)"
    else
        cat > "$ESP/EFI/BOOT/limine.conf" << L2
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    cmdline: console=tty0 loglevel=4 root=$RD rootfstype=ext4 rw rootwait init=/sbin/init
L2
        log_warn "limine.conf (direct, root=$RD)"
    fi
}
register_uefi() {
    if command -v efibootmgr >/dev/null 2>&1; then
        efibootmgr --create --disk "$DEV" --part 1 --label "Ame Linux" --loader '\EFI\BOOT\BOOTX64.EFI' 2>/dev/null || true
        log_ok "UEFI entry"
    fi
}
install_bootloader_complete() {
    bootdir="$1"
    require_disk || return 1
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$bootdir" || return 1
    write_limine_conf || return 1
    register_uefi
    sync
    ls -la "$ESP/EFI/BOOT/"
    state_mark "bootloader"
    return 0
}

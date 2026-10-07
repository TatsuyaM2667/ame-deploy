#!/bin/sh
# ブートローダインストール（Alpine kernel 使用）

get_target_kernel() {
    if [ -f /tmp/ame-kimg ]; then
        cat /tmp/ame-kimg
    else
        # フォールバック: 存在する kernel を探す
        for k in vmlinuz-lts vmlinuz-edge vmlinuz-virt; do
            [ -f "$TARGET/boot/$k" ] && echo "$k" && return
        done
        echo ""
    fi
}

get_target_initrd() {
    if [ -f /tmp/ame-kinitrd ]; then
        cat /tmp/ame-kinitrd
    else
        for i in initramfs-lts initramfs-edge initramfs-virt; do
            [ -f "$TARGET/boot/$i" ] && echo "$i" && return
        done
        echo ""
    fi
}

install_kernel_to_esp() {
    local kimg=$(get_target_kernel)
    [ -n "$kimg" ] || { log_err "no kernel found in target"; return 1; }
    require_file "$TARGET/boot/$kimg" || return 1

    log_info "kernel -> ESP: $kimg"
    mkdir -p "$ESP/EFI/BOOT"
    cp "$TARGET/boot/$kimg" "$ESP/EFI/BOOT/vmlinuz-ame" || return 1
    log_ok "kernel copied ($kimg)"
}

install_initramfs_to_esp() {
    local kinitrd=$(get_target_initrd)
    if [ -n "$kinitrd" ] && [ -f "$TARGET/boot/$kinitrd" ]; then
        cp "$TARGET/boot/$kinitrd" "$ESP/EFI/BOOT/initramfs.cpio.gz"
        log_ok "initramfs copied ($kinitrd)"
    else
        log_warn "initramfs not found"
    fi
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
    log_info "limine.conf"
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
    log_ok "limine.conf"
}

register_uefi() {
    if command -v efibootmgr >/dev/null 2>&1; then
        efibootmgr --create --disk "$DEV" --part 1 \
            --label "Ame Linux" --loader '\EFI\BOOT\BOOTX64.EFI' 2>/dev/null || true
        log_ok "UEFI entry registered"
    fi
}

install_bootloader_complete() {
    bootdir="$1"
    require_disk || return 1
    install_kernel_to_esp || return 1
    install_initramfs_to_esp
    install_limine "$bootdir" || return 1
    write_limine_conf || return 1
    register_uefi
    sync
    log_info "ESP contents:"
    ls -la "$ESP/EFI/BOOT/"
    return 0
}

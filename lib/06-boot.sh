#!/bin/sh
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
    kver=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$kver" ] || { log_err "no kernel modules"; return 1; }
    img="initramfs-${kver##*-}"
    case "$kver" in
        *-lts)  img="initramfs-lts" ;;
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac
    if [ -f "$TARGET/boot/$img" ]; then
        log_ok "initramfs exists: $img"
        echo "$img" > /tmp/ame-kinitrd
        return 0
    fi
    log_info "generating initramfs via mkinitfs"
    _mount_chroot_fs
    _chroot_apk "command -v mkinitfs >/dev/null 2>&1 || apk add --no-cache --force-missing-repositories mkinitfs >/dev/null 2>&1"
    _chroot_apk "mkinitfs -o /boot/$img $kver 2>&1 | tail -5"
    _umount_chroot_fs
    if [ -f "$TARGET/boot/$img" ]; then
        log_ok "initramfs generated: $img"
        echo "$img" > /tmp/ame-kinitrd
        return 0
    fi
    log_err "initramfs unavailable"
    return 1
}
install_kernel_to_esp() {
    kimg=$(get_target_kernel)
    [ -n "$kimg" ] || { log_err "no kernel"; return 1; }
    require_file "$TARGET/boot/$kimg" || return 1
    mkdir -p "$ESP/EFI/BOOT"
    cp "$TARGET/boot/$kimg" "$ESP/EFI/BOOT/vmlinuz-ame" || return 1
    log_ok "kernel copied ($kimg)"
}
install_initramfs_to_esp() {
    ensure_initramfs || return 1
    kinitrd=$(get_target_initrd)
    [ -n "$kinitrd" ] && [ -f "$TARGET/boot/$kinitrd" ] || { log_err "initramfs missing"; return 1; }
    cp "$TARGET/boot/$kinitrd" "$ESP/EFI/BOOT/initramfs.cpio.gz"
    log_ok "initramfs copied ($kinitrd)"
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
    rp=$(blkid -s PARTUUID -o value "$P2")
    if [ -f "$ESP/EFI/BOOT/initramfs.cpio.gz" ]; then
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    module_path: boot():/EFI/BOOT/initramfs.cpio.gz
    cmdline: console=tty0 console=ttyS0,115200 loglevel=7 ignore_loglevel root=PARTUUID=$rp rootfstype=ext4 rw
LEOF
        log_ok "limine.conf (with initramfs)"
    else
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    cmdline: console=tty0 console=ttyS0,115200 loglevel=7 ignore_loglevel root=PARTUUID=$rp rootfstype=ext4 rw init=/sbin/init
LEOF
        log_warn "limine.conf (rootfs direct)"
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
    install_kernel_to_esp    || return 1
    install_initramfs_to_esp || return 1
    install_limine "$bootdir" || return 1
    write_limine_conf        || return 1
    register_uefi
    sync
    log_info "ESP contents:"
    ls -la "$ESP/EFI/BOOT/"
    state_mark "bootloader"
    return 0
}

# ============ v1.0.3 override: write_limine_conf ============
write_limine_conf() {
    local mnt_p2
    mnt_p2=$(grep " /mnt/ame-target " /proc/mounts 2>/dev/null | awk '{print $1}' | head -1)
    if [ -n "$mnt_p2" ] && [ -b "$mnt_p2" ]; then
        P2="$mnt_p2"
    fi
    if [ -z "$P2" ] || [ ! -b "$P2" ]; then
        for d in sda nvme0n1 vda; do
            [ -b "/dev/${d}2" ]  && { P2="/dev/${d}2";  P1="/dev/${d}1";  DEV="/dev/$d"; break; }
            [ -b "/dev/${d}p2" ] && { P2="/dev/${d}p2"; P1="/dev/${d}p1"; DEV="/dev/$d"; break; }
        done
    fi
    [ -b "$P2" ] || { log_err "no block device (P2=$P2)"; return 1; }
    local rp
    rp=$(blkid -s PARTUUID -o value "$P2" 2>/dev/null)
    [ -n "$rp" ] || { log_err "no PARTUUID for $P2"; return 1; }
    log_info "root device: $P2"
    log_info "root PARTUUID: $rp"
    if [ -f "$ESP/EFI/BOOT/initramfs.cpio.gz" ]; then
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    module_path: boot():/EFI/BOOT/initramfs.cpio.gz
    cmdline: console=tty0 loglevel=7 ignore_loglevel root=PARTUUID=$rp rootfstype=ext4 rw
LEOF
        log_ok "limine.conf written (initramfs, verbose)"
    else
        cat > "$ESP/EFI/BOOT/limine.conf" << LEOF
timeout: 5
serial: yes

/Ame Linux
    protocol: linux
    kernel_path: boot():/EFI/BOOT/vmlinuz-ame
    cmdline: console=tty0 loglevel=7 ignore_loglevel root=PARTUUID=$rp rootfstype=ext4 rw init=/sbin/init
LEOF
        log_warn "limine.conf (direct)"
    fi
    echo "==== limine.conf ===="
    cat "$ESP/EFI/BOOT/limine.conf"
    return 0
}

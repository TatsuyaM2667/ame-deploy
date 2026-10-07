#!/bin/sh
select_and_install_kernel() {
    if state_done "kernel" && [ -d "$TARGET/lib/modules" ] && [ -n "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_info "kernel already installed"
        KVER=$(ls "$TARGET/lib/modules" | head -1)
        echo "$KVER" > /tmp/ame-kver
        return 0
    fi
    echo "  Kernel:"
    echo "    [1] linux-lts    (recommended)"
    echo "    [2] linux-edge   (mainline-like)"
    echo "    [3] linux-virt   (VM)"
    printf "  Select [1]: "; read kc
    [ -z "$kc" ] && kc="1"
    case "$kc" in
        1) KPKGS="linux-lts" ;;
        2) KPKGS="linux-edge" ;;
        3) KPKGS="linux-virt" ;;
        *) log_err "invalid"; return 1 ;;
    esac
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    log_info "[1/4] edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'
    log_info "[2/4] install $KPKGS"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKGS mkinitfs 2>&1 | tail -5"
    log_info "[3/4] firmware"
    for pkg in linux-firmware-i915 linux-firmware-intel linux-firmware-amdgpu linux-firmware-nvidia linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtl_nic linux-firmware-rtlwifi linux-firmware-mediatek linux-firmware-brcm; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && echo "    [OK] $pkg" || true
    done
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel modules"; return 1; }
    log_ok "kernel: $KVER"
    log_info "[4/4] initramfs"
    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme"
MK
    _mount_chroot_fs
    img="initramfs-lts"
    case "$KVER" in
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac
    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then break; fi
        rm -f "$TARGET/boot/$img"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkdir -p /boot; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs
    if ! _verify_initramfs "$TARGET/boot/$img"; then
        log_err "initramfs generation failed"
        return 1
    fi
    echo "$img" > /tmp/ame-kinitrd
    echo "$KVER" > /tmp/ame-kver
    state_mark "kernel"
    log_ok "kernel ready ($KVER)"
}

#!/bin/sh
# カーネル選択 + インストール

select_and_install_kernel() {
    log_info "=== Kernel selection ==="
    echo
    echo "  Kernel:"
    echo "    [1] linux-lts    (stable, recommended - best HW support)"
    echo "    [2] linux-edge   (newest, might have issues)"
    echo "    [3] linux-virt   (VM only)"
    echo "    [4] skip         (custom kernel, not recommended)"
    printf "  Select [1]: "; read kc
    [ -z "$kc" ] && kc="1"

    case "$kc" in
        1) KPKG="linux-lts";  KIMG="vmlinuz-lts";  KINITRD="initramfs-lts" ;;
        2) KPKG="linux-edge"; KIMG="vmlinuz-edge"; KINITRD="initramfs-edge" ;;
        3) KPKG="linux-virt"; KIMG="vmlinuz-virt"; KINITRD="initramfs-virt" ;;
        4) log_warn "skipping kernel install"; return 0 ;;
        *) log_err "invalid"; return 1 ;;
    esac

    log_info "installing $KPKG"

    # resolv.conf コピー
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # Alpine の apk で kernel 一式
    log_info "[1/3] apk update"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    log_info "[2/3] apk add $KPKG + firmware + mkinitfs"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKG linux-firmware linux-firmware-i915 linux-firmware-amdgpu linux-firmware-rtw88 linux-firmware-rtw89 mkinitfs 2>&1 | tail -10"

    # 検証
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_err "$KPKG install failed - /lib/modules empty"
        return 1
    fi
    KVER=$(ls "$TARGET/lib/modules" | head -1)
    log_ok "kernel modules: $KVER"

    # initramfs 生成
    log_info "[3/3] generating initramfs via mkinitfs"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$KINITRD $KVER 2>&1 | tail -5"

    if [ -f "$TARGET/boot/$KIMG" ]; then
        log_ok "kernel image: /boot/$KIMG"
    else
        log_warn "/boot/$KIMG not found"
    fi
    if [ -f "$TARGET/boot/$KINITRD" ]; then
        log_ok "initramfs: /boot/$KINITRD"
    else
        log_warn "/boot/$KINITRD not generated"
    fi

    # グローバルに保存（bootloader で使う）
    echo "$KIMG"   > /tmp/ame-kimg
    echo "$KINITRD" > /tmp/ame-kinitrd
    echo "$KVER"   > /tmp/ame-kver

    log_ok "kernel ready ($KPKG / $KVER)"
}

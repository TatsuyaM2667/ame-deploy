#!/bin/sh
# カーネル選択 + インストール（edge repo 使用）

select_and_install_kernel() {
    log_info "=== Kernel selection ==="
    echo
    echo "  Kernel:"
    echo "    [1] linux-lts    (stable, recommended)"
    echo "    [2] linux-edge   (newest)"
    echo "    [3] linux-virt   (VM only)"
    echo "    [4] skip"
    printf "  Select [1]: "; read kc
    [ -z "$kc" ] && kc="1"

    case "$kc" in
        1) KPKG="linux-lts";  KIMG="vmlinuz-lts";  KINITRD="initramfs-lts" ;;
        2) KPKG="linux-edge"; KIMG="vmlinuz-edge"; KINITRD="initramfs-edge" ;;
        3) KPKG="linux-virt"; KIMG="vmlinuz-virt"; KINITRD="initramfs-virt" ;;
        4) log_warn "skipping"; return 0 ;;
        *) log_err "invalid"; return 1 ;;
    esac

    log_info "installing $KPKG"

    # resolv.conf
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # ★ 重要: edge repo に切替（kernel は edge にある）
    log_info "[0/4] switch target to edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"

    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF

    log_info "[1/4] apk update"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -3'

    log_info "[2/4] apk add $KPKG + firmware + mkinitfs"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKG mkinitfs linux-firmware-i915 linux-firmware-amdgpu linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtl_nic linux-firmware-mediatek linux-firmware-iwlwifi 2>&1 | tail -15"

    # 検証
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_err "$KPKG install failed - /lib/modules empty"
        echo "  Check target network:"
        echo "    chroot $TARGET /bin/sh -c 'ping -c 2 1.1.1.1'"
        echo "    chroot $TARGET /bin/sh -c 'cat /etc/apk/repositories'"
        return 1
    fi
    KVER=$(ls "$TARGET/lib/modules" | head -1)
    log_ok "kernel modules: $KVER"

    log_info "[3/4] generating initramfs"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$KINITRD $KVER 2>&1 | tail -5"

    log_info "[4/4] verify"
    [ -f "$TARGET/boot/$KIMG" ]    && log_ok "kernel:   /boot/$KIMG"    || log_warn "/boot/$KIMG missing"
    [ -f "$TARGET/boot/$KINITRD" ] && log_ok "initramfs: /boot/$KINITRD" || log_warn "/boot/$KINITRD missing"

    # グローバル保存
    echo "$KIMG"    > /tmp/ame-kimg
    echo "$KINITRD" > /tmp/ame-kinitrd
    echo "$KVER"    > /tmp/ame-kver

    log_ok "kernel ready ($KPKG / $KVER)"
    return 0
}

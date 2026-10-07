#!/bin/sh
# カーネル選択 + インストール

select_and_install_kernel() {
    log_info "=== Kernel selection ==="
    echo
    echo "  Kernel:"
    echo "    [1] linux-lts       LTS / stable (recommended)"
    echo "    [2] linux-edge      newest / mainline-like"
    echo "    [3] linux-virt      VM only"
    echo "    [4] both LTS+edge   dual kernel entries"
    echo "    [5] skip            (use custom kernel)"
    printf "  Select [1]: "; read kc
    [ -z "$kc" ] && kc="1"

    case "$kc" in
        1) KPKGS="linux-lts";  KIMG="vmlinuz-lts";  KINITRD="initramfs-lts" ;;
        2) KPKGS="linux-edge"; KIMG="vmlinuz-edge"; KINITRD="initramfs-edge" ;;
        3) KPKGS="linux-virt"; KIMG="vmlinuz-virt"; KINITRD="initramfs-virt" ;;
        4) KPKGS="linux-lts linux-edge"; KIMG="vmlinuz-lts"; KINITRD="initramfs-lts" ;;
        5) log_warn "skipping"; return 0 ;;
        *) log_err "invalid"; return 1 ;;
    esac

    log_info "installing: $KPKGS"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo 切替
    log_info "[0/4] switch target to edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"

    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF

    log_info "[1/4] apk update"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -3'

    # --- 必須: kernel + mkinitfs ---
    log_info "[2/4] apk add $KPKGS + mkinitfs"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $KPKGS mkinitfs 2>&1 | tail -10"

    # --- オプション: firmware 群（存在しないものは || true） ---
    log_info "[2/4] firmware packages (optional)"
    for pkg in \
        linux-firmware-i915 \
        linux-firmware-intel \
        linux-firmware-amdgpu \
        linux-firmware-nvidia \
        linux-firmware-rtw88 \
        linux-firmware-rtw89 \
        linux-firmware-rtl_nic \
        linux-firmware-rtlwifi \
        linux-firmware-mediatek \
        linux-firmware-brcm \
        linux-firmware-ath10k \
        linux-firmware-ath11k \
        linux-firmware-ath12k \
        linux-firmware-qcom \
        linux-firmware-mellanox \
        linux-firmware-marvell; do

        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && \
            echo "    [OK] $pkg" || true
    done

    # 検証
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_err "kernel install failed - /lib/modules empty"
        echo "  Check target network:"
        echo "    chroot $TARGET /bin/sh -c 'ping -c 2 1.1.1.1'"
        return 1
    fi
    KVER=$(ls "$TARGET/lib/modules" | head -1)
    log_ok "kernel modules: $KVER"
    for v in $(ls "$TARGET/lib/modules"); do log_info "  module: $v"; done

    # initramfs 生成
    log_info "[3/4] generating initramfs"
    for v in $(ls "$TARGET/lib/modules"); do
        local img="initramfs-${v##*-}"
        # vmlinuz 名を推定
        case "$v" in
            *-lts)  img="initramfs-lts" ;;
            *-edge) img="initramfs-edge" ;;
            *-virt) img="initramfs-virt" ;;
        esac
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkinitfs -o /boot/$img $v 2>&1 | tail -3" || true
    done

    # 検証
    log_info "[4/4] verify /boot"
    ls -la "$TARGET/boot/" 2>/dev/null | grep -E 'vmlinuz|initramfs' || log_warn "no kernel images in /boot"

    # グローバル保存
    echo "$KIMG"    > /tmp/ame-kimg
    echo "$KINITRD" > /tmp/ame-kinitrd
    echo "$KVER"    > /tmp/ame-kver

    log_ok "kernel ready ($KPKGS)"
    return 0
}

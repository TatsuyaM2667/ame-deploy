#!/bin/sh
select_and_install_kernel() {
    if state_done "kernel" && [ -d "$TARGET/lib/modules" ] && \
       [ -n "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ] && \
       ls "$TARGET/boot/initramfs-"* >/dev/null 2>&1; then
        KVER=$(ls "$TARGET/lib/modules" | head -1)
        log_info "kernel already installed: $KVER"
        for k in vmlinuz-lts vmlinuz-edge vmlinuz-virt; do
            [ -f "$TARGET/boot/$k" ] && echo "$k" > /tmp/ame-kimg && break
        done
        echo "$KVER" > /tmp/ame-kver
        return 0
    fi

    log_info "=== Kernel selection ==="
    echo
    echo "  Kernel:"
    echo "    [1] linux-lts       LTS / stable (recommended)"
    echo "    [2] linux-edge      newest / mainline"
    echo "    [3] linux-virt      VM only"
    echo "    [4] both LTS+edge"
    echo "    [5] skip"
    if [ "$AUTOMODE" = "1" ]; then
        kc="1"; log_info "  [auto] using linux-lts"
    else
        printf "  Select [1]: "; read kc
        [ -z "$kc" ] && kc="1"
    fi

    case "$kc" in
        1) KPKGS="linux-lts";  KIMG="vmlinuz-lts";  KINITRD="initramfs-lts" ;;
        2) KPKGS="linux-edge"; KIMG="vmlinuz-edge"; KINITRD="initramfs-edge" ;;
        3) KPKGS="linux-virt"; KIMG="vmlinuz-virt"; KINITRD="initramfs-virt" ;;
        4) KPKGS="linux-lts linux-edge"; KIMG="vmlinuz-lts"; KINITRD="initramfs-lts" ;;
        5) log_warn "skipping"; return 0 ;;
        *) log_err "invalid"; return 1 ;;
    esac

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    log_info "[1/4] edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"
    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
    _chroot_apk "apk update --force-missing-repositories 2>&1 | tail -2"

    log_info "[2/4] install $KPKGS + mkinitfs"
    _mount_chroot_fs
    _chroot_apk "apk add --no-cache --force-missing-repositories $KPKGS mkinitfs 2>&1 | tail -5"
    _umount_chroot_fs

    log_info "[3/4] firmware (optional)"
    for pkg in linux-firmware-i915 linux-firmware-intel linux-firmware-amdgpu linux-firmware-nvidia linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-rtl_nic linux-firmware-rtlwifi linux-firmware-mediatek linux-firmware-brcm linux-firmware-ath10k linux-firmware-ath11k linux-firmware-ath12k; do
        _chroot_apk "apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && \
            log_ok "    $pkg" || true
    done

    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_err "kernel install failed"
        return 1
    fi
    KVER=$(ls "$TARGET/lib/modules" | head -1)
    log_ok "kernel modules: $KVER"

    log_info "[4/4] generating initramfs"
    for v in $(ls "$TARGET/lib/modules"); do
        img="initramfs-${v##*-}"
        case "$v" in
            *-lts)  img="initramfs-lts" ;;
            *-edge) img="initramfs-edge" ;;
            *-virt) img="initramfs-virt" ;;
        esac
        if [ -f "$TARGET/boot/$img" ]; then
            log_ok "  $img exists"
        else
            log_info "  generating $img"
            _mount_chroot_fs
            _chroot_apk "mkinitfs -o /boot/$img $v 2>&1 | tail -3"
            _umount_chroot_fs
            [ -f "$TARGET/boot/$img" ] && log_ok "  $img OK" || log_warn "  $img failed"
        fi
    done

    if ! ls "$TARGET/boot/initramfs-"* >/dev/null 2>&1; then
        log_err "no initramfs generated"
        return 1
    fi

    for k in vmlinuz-lts vmlinuz-edge vmlinuz-virt; do
        [ -f "$TARGET/boot/$k" ] && echo "$k" > /tmp/ame-kimg && break
    done
    echo "$KVER" > /tmp/ame-kver

    state_mark "kernel"
    log_ok "kernel ready ($KVER)"
}

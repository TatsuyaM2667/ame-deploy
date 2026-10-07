#!/bin/sh
# firmware インストール（Alpine 正しいパッケージ名）

install_hw_firmware() {
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo に切替済みか確認
    if ! grep -q "edge/main" "$TARGET/etc/apk/repositories" 2>/dev/null; then
        [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
            cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"
        cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'
    fi

    pkgs=""
    case "$gpu" in
        amd)    pkgs="$pkgs linux-firmware-amdgpu mesa-dri-gallium mesa-vulkan-ati" ;;
        intel)  pkgs="$pkgs linux-firmware-i915 mesa-dri-gallium mesa-vulkan-intel" ;;
        nvidia) pkgs="$pkgs linux-firmware-nvidia" ;;
    esac
    case "$wifi" in
        realtek)  pkgs="$pkgs linux-firmware-rtw89 linux-firmware-rtw88 linux-firmware-rtlwifi" ;;
        intel)    pkgs="$pkgs linux-firmware-intel" ;;
        mediatek) pkgs="$pkgs linux-firmware-mediatek" ;;
        broadcom) pkgs="$pkgs linux-firmware-brcm" ;;
    esac
    pkgs="$pkgs linux-firmware-rtl_nic"

    [ -n "$pkgs" ] || { log_info "no firmware"; return 0; }
    log_info "installing (optional, errors ignored):"
    for p in $pkgs; do log_info "  - $p"; done

    # 1個ずつ install（存在しないものは飛ばす）
    for p in $pkgs; do
        if chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1"; then
            log_ok "  $p"
        else
            log_warn "  $p (skipped)"
        fi
    done

    log_ok "firmware done"
}

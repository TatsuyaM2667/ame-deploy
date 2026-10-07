#!/bin/sh
install_hw_firmware() {
    if state_done "firmware"; then
        log_info "firmware already installed - skip"
        return 0
    fi
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    pkgs=""
    case "$gpu" in
        amd)    pkgs="$pkgs linux-firmware-amdgpu mesa-dri-gallium mesa-vulkan-ati" ;;
        intel)  pkgs="$pkgs linux-firmware-i915 linux-firmware-intel mesa-dri-gallium mesa-vulkan-intel" ;;
        nvidia) pkgs="$pkgs linux-firmware-nvidia" ;;
    esac
    case "$wifi" in
        realtek)  pkgs="$pkgs linux-firmware-rtw89 linux-firmware-rtw88 linux-firmware-rtlwifi" ;;
        intel)    pkgs="$pkgs linux-firmware-intel" ;;
        mediatek) pkgs="$pkgs linux-firmware-mediatek" ;;
        broadcom) pkgs="$pkgs linux-firmware-brcm" ;;
    esac
    pkgs="$pkgs linux-firmware-rtl_nic"

    for p in $pkgs; do
        _chroot_apk "apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1" && \
            log_ok "  $p" || log_warn "  skip: $p"
    done

    state_mark "firmware"
    log_ok "firmware done"
}

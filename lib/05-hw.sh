#!/bin/sh
install_hw_firmware() {
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"

    pkgs=""
    case "$gpu" in
        amd)    pkgs="$pkgs linux-firmware-amdgpu mesa-dri-gallium mesa-vulkan-ati" ;;
        intel)  pkgs="$pkgs linux-firmware-i915 linux-firmware-intel mesa-dri-gallium mesa-vulkan-intel" ;;
        nvidia) pkgs="$pkgs linux-firmware-nvidia" ;;
    esac
    case "$wifi" in
        realtek)  pkgs="$pkgs linux-firmware-rtw89 linux-firmware-rtw88" ;;
        intel)    pkgs="$pkgs linux-firmware-iwlwifi" ;;
        mediatek) pkgs="$pkgs linux-firmware-mediatek" ;;
        broadcom) pkgs="$pkgs linux-firmware-brcm" ;;
    esac

    [ -n "$pkgs" ] || { log_info "no firmware"; return 0; }
    log_info "installing: $pkgs"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    chroot "$TARGET" /bin/sh -c "
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        apk update >/dev/null 2>&1
        apk add --no-cache $pkgs 2>&1 | tail -5
    " || log_warn "some firmware failed"
    log_ok "firmware done"
}

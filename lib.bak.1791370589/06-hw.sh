#!/bin/sh
install_hw_firmware() {
    if state_done "firmware"; then
        log_info "firmware already installed"; return 0
    fi
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    install_kernel_firmware
    pkgs_optional "mesa" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati
    state_mark "firmware"
    log_ok "firmware done"
}

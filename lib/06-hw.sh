#!/bin/sh
install_hw_firmware() {
    state_done "firmware" && { log_info "firmware already installed"; return 0; }
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"
    enable_edge 2>/dev/null || true
    install_kernel_firmware
    state_mark "firmware"
    log_ok "firmware done"
}

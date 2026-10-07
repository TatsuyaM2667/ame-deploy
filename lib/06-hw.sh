#!/bin/sh
install_hw_firmware() {
    if state_done "firmware"; then
        log_info "firmware already installed"
        return 0
    fi
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"

    enable_edge 2>/dev/null || true
    install_kernel_firmware

    # /etc/modules にも WiFi モジュールを追記（既存があれば追記）
    mkdir -p "$TARGET/etc"
    if ! grep -q "rtw88_8821ce" "$TARGET/etc/modules" 2>/dev/null; then
        cat >> "$TARGET/etc/modules" << 'MOD'
rtw88_8821ce
rtw88_8821cu
rtw88_8822be
rtw88_8822ce
rtw89_8852ae
rtw89_8852be
rtw89_8852ce
iwlwifi
mt7921e
MOD
        log_ok "  /etc/modules updated"
    fi

    state_mark "firmware"
    log_ok "firmware done"
}

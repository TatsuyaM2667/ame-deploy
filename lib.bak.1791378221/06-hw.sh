#!/bin/sh
install_hw_firmware() {
    state_done "firmware" && { log_info "firmware already installed"; return 0; }
    gpu="$1"; wifi="$2"
    log_info "GPU=$gpu WiFi=$wifi"
    enable_edge 2>/dev/null || true
    install_kernel_firmware
    # WiFi モジュールの強制 autoload 設定
    mkdir -p "$TARGET/etc"
    if [ ! -f "$TARGET/etc/modules" ]; then
        cat > "$TARGET/etc/modules" << 'MOD'
rtw88_core
rtw88_pci
rtw88_8821ce
rtw88_8821cu
rtw88_8822be
rtw88_8822ce
rtw89_core
rtw89_pci
rtw89_8852ae
rtw89_8852be
rtw89_8852ce
iwlwifi
mt7921e
ath10k_pci
ath11k_pci
brcmfmac
MOD
    fi
    state_mark "firmware"
    log_ok "firmware done"
}

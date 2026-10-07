#!/bin/sh
detect_cpu() { grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || echo unknown; }
detect_cpu_cores() { nproc 2>/dev/null || echo 1; }
detect_ram_mb() { awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo; }
detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        l=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
        case "$l" in
            *1002:*|*AMD*|*Radeon*) echo amd; return ;;
            *8086:*|*Intel*) echo intel; return ;;
            *10de:*|*NVIDIA*) echo nvidia; return ;;
        esac
    fi
    for v in /sys/class/drm/card*/device/vendor; do
        [ -r "$v" ] || continue
        case "$(cat "$v" 2>/dev/null)" in
            0x1002) echo amd; return ;;
            0x8086) echo intel; return ;;
            0x10de) echo nvidia; return ;;
        esac
    done
    echo unknown
}
detect_wifi() {
    has=0
    for w in /sys/class/net/*/wireless; do [ -e "$w" ] && has=1 && break; done
    [ "$has" = "1" ] || { echo none; return; }
    if command -v lspci >/dev/null 2>&1; then
        l=$(lspci -nn 2>/dev/null | grep -iE 'network|wireless' | head -1)
        case "$l" in
            *10ec:*) echo realtek; return ;;
            *8086:*) echo intel; return ;;
            *14c3:*) echo mediatek; return ;;
            *14e4:*) echo broadcom; return ;;
        esac
    fi
    echo unknown
}
detect_wifi_pci() {
    # PCI ID (vendor:device) を返す - モジュール特定に使う
    lspci -nn 2>/dev/null | grep -iE 'network|wireless' | grep -oE '[0-9a-f]{4}:[0-9a-f]{4}' | head -1
}
detect_eth() {
    for d in /sys/class/net/e*; do
        [ -e "$d" ] || continue
        i=$(basename "$d")
        [ -e "/sys/class/net/$i/wireless" ] && continue
        [ "$i" = "lo" ] && continue
        echo yes; return
    done
    echo no
}
show_hw_summary() {
    echo "+--------------------------------------------------+"
    echo "|  Hardware detection                              |"
    echo "+--------------------------------------------------+"
    printf "  %-12s: %s\n" "CPU" "$(detect_cpu)"
    printf "  %-12s: %s\n" "Cores" "$(detect_cpu_cores)"
    printf "  %-12s: %s MiB\n" "RAM" "$(detect_ram_mb)"
    printf "  %-12s: %s\n" "GPU" "$(detect_gpu)"
    printf "  %-12s: %s\n" "WiFi" "$(detect_wifi)"
    printf "  %-12s: %s\n" "WiFi PCI" "$(detect_wifi_pci)"
    printf "  %-12s: %s\n" "Ethernet" "$(detect_eth)"
    echo "--------------------------------------------------"
    lsblk -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -vE 'loop|zram|sr0'
    echo "+--------------------------------------------------+"
}

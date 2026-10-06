#!/bin/sh
# Hyprland 完全セットアップ v0.5

install_hyprland_complete() {
    log_info "=== Hyprland complete install ==="

    # 1) edge repo 切替
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    chroot "$TARGET" /bin/sh -c '
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        [ -f /etc/apk/repositories.stable.bak ] || cp /etc/apk/repositories /etc/apk/repositories.stable.bak
        cat > /etc/apk/repositories << EOF
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing

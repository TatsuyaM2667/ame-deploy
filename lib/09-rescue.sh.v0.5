#!/bin/sh
# 壊れたインストール済み環境の救出
rescue_installed_system() {
    log_info "=== Rescue mode ==="

    # インストール済みルートを探す
    ROOT=""
    for d in /mnt/ame-target /mnt/ame /mnt; do
        if [ -f "$d/etc/os-release" ] || [ -f "$d/sbin/init" ]; then
            ROOT="$d"
            break
        fi
    done

    if [ -z "$ROOT" ] || [ ! -d "$ROOT/etc" ]; then
        log_err "no installed system found. Mount target first."
        echo
        echo "  Mount: mount /dev/sda2 /mnt/ame"
        echo "  Then re-run rescue"
        return 1
    fi

    log_info "rescuing: $ROOT"

    # 1) autostart 停止
    mv "$ROOT/etc/profile.d/ame-autostart.sh" \
       "$ROOT/etc/profile.d/ame-autostart.sh.disabled" 2>/dev/null || true
    log_ok "autostart disabled"

    # 2) /run/user 準備
    mkdir -p "$ROOT/run/user"
    chmod 0755 "$ROOT/run/user"

    # 3) elogind 設定
    mkdir -p "$ROOT/etc/elogind"
    cat > "$ROOT/etc/elogind/logind.conf" << 'LEOF'
[Login]
KillUserProcesses=no
RemoveIPC=no
LEOF
    log_ok "elogind config"

    # 4) ユーザーの runtime dir
    for u in $(grep -E '/bin/(sh|bash)$' "$ROOT/etc/passwd" | cut -d: -f1); do
        uid=$(grep "^$u:" "$ROOT/etc/passwd" | cut -d: -f3)
        [ -z "$uid" ] && continue
        mkdir -p "$ROOT/run/user/$uid"
        chmod 0700 "$ROOT/run/user/$uid"
        chown "$uid:$uid" "$ROOT/run/user/$uid" 2>/dev/null || true
        log_ok "created /run/user/$uid for $u"
    done

    # 5) 安全 autostart 再作成
    cat > "$ROOT/etc/profile.d/ame-autostart.sh" << 'AEOF'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    if command -v Hyprland >/dev/null 2>&1; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        if [ ! -d "$XDG_RUNTIME_DIR" ] || ! touch "$XDG_RUNTIME_DIR/.test" 2>/dev/null; then
            mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || \
                export XDG_RUNTIME_DIR="/tmp/xdg-$(id -u)"
        fi
        [ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
        chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
        if ! Hyprland; then
            echo "=== Hyprland failed, dropping to shell ==="
        fi
    fi
fi
AEOF
    chmod +x "$ROOT/etc/profile.d/ame-autostart.sh"
    log_ok "safe autostart installed"

    log_ok "rescue complete. Reboot the installed system."
    return 0
}

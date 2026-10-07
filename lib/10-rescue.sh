#!/bin/sh
rescue_installed_system() {
    log_info "=== Rescue mode v0.6 ==="

    ROOT=""
    for d in /mnt/ame-target /mnt/ame /mnt; do
        if [ -f "$d/etc/os-release" ] || [ -f "$d/sbin/init" ]; then
            ROOT="$d"
            break
        fi
    done

    if [ -z "$ROOT" ] || [ ! -d "$ROOT/etc" ]; then
        log_err "no installed system found."
        echo "  Mount: mkdir -p /mnt/ame && mount /dev/sda2 /mnt/ame"
        return 1
    fi

    log_info "rescuing: $ROOT"

    mv "$ROOT/etc/profile.d/ame-autostart.sh" \
       "$ROOT/etc/profile.d/ame-autostart.sh.disabled" 2>/dev/null || true
    log_ok "autostart disabled"

    # elogind 設定
    mkdir -p "$ROOT/etc/elogind"
    cat > "$ROOT/etc/elogind/logind.conf" << 'LEOF'
[Login]
KillUserProcesses=no
RemoveIPC=no
LEOF

    # runtime-dir サービス
    mkdir -p "$ROOT/etc/init.d"
    cat > "$ROOT/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user/<uid> directories at boot"
depend() { after elogind; need localmount; before display-manager; }
start() {
    ebegin "Creating /run/user directories"
    mkdir -p /run/user; chmod 0755 /run/user
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | while read -r uid; do
        [ -z "$uid" ] && continue
        mkdir -p "/run/user/$uid"; chmod 0700 "/run/user/$uid"; chown "$uid:$uid" "/run/user/$uid" 2>/dev/null || true
    done
    eend 0
}
stop() { rm -rf /run/user/* 2>/dev/null || true; }
SVC
    chmod +x "$ROOT/etc/init.d/ame-runtime-dir"
    for level in boot default; do
        mkdir -p "$ROOT/etc/runlevels/$level"
        ln -sf /etc/init.d/ame-runtime-dir "$ROOT/etc/runlevels/$level/ame-runtime-dir" 2>/dev/null || true
    done
    log_ok "runtime-dir service installed"

    # /run/user を即座に作成
    mkdir -p "$ROOT/run/user"
    chmod 0755 "$ROOT/run/user"
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' "$ROOT/etc/passwd" | while read -r uid; do
        [ -z "$uid" ] && continue
        mkdir -p "$ROOT/run/user/$uid"
        chmod 0700 "$ROOT/run/user/$uid"
        chown "$uid:$uid" "$ROOT/run/user/$uid" 2>/dev/null || true
        log_ok "created /run/user/$uid"
    done

    # サービス有効化
    for s in dbus elogind seatd polkit networkmanager; do
        for level in default boot; do
            mkdir -p "$ROOT/etc/runlevels/$level"
            [ -e "$ROOT/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "$ROOT/etc/runlevels/$level/$s" 2>/dev/null || true
        done
    done

    # 安全 autostart 再作成
    cat > "$ROOT/etc/profile.d/ame-autostart.sh" << 'AEOF'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"
    RDIR="/run/user/$UID_NUM"
    i=0
    while [ $i -lt 10 ]; do
        [ -d "$RDIR" ] && break
        sleep 1
        i=$((i+1))
    done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null
    if [ -d "$RDIR" ]; then
        export XDG_RUNTIME_DIR="$RDIR"
        chmod 0700 "$RDIR" 2>/dev/null
        if command -v start-hyprland >/dev/null 2>&1; then
            start-hyprland || echo "=== start-hyprland failed, shell ==="
        elif command -v Hyprland >/dev/null 2>&1; then
            Hyprland || echo "=== Hyprland failed, shell ==="
        fi
    fi
fi
AEOF
    chmod +x "$ROOT/etc/profile.d/ame-autostart.sh"

    log_ok "Rescue complete"
    echo "  Unmount and reboot:"
    echo "    sync; umount $ROOT; reboot"
    return 0
}

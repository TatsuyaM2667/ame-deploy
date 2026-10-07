#!/bin/sh
rescue_installed_system() {
    log_info "=== Rescue ==="
    ROOT=""
    for d in /mnt/ame-target /mnt/ame /mnt; do
        if [ -f "$d/etc/os-release" ] || [ -f "$d/sbin/init" ]; then ROOT="$d"; break; fi
    done
    [ -n "$ROOT" ] && [ -d "$ROOT/etc" ] || { log_err "no install found"; return 1; }

    log_info "rescuing: $ROOT"
    mv "$ROOT/etc/profile.d/ame-autostart.sh" "$ROOT/etc/profile.d/ame-autostart.sh.disabled" 2>/dev/null || true

    mkdir -p "$ROOT/etc/elogind"
    cat > "$ROOT/etc/elogind/logind.conf" << 'LEOF'
[Login]
KillUserProcesses=no
RemoveIPC=no
LEOF

    mkdir -p "$ROOT/etc/init.d"
    cat > "$ROOT/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user"
depend() { after elogind; need localmount; }
start() {
    ebegin "Creating /run/user"
    mkdir -p /run/user; chmod 0755 /run/user
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | while read -r uid; do
        mkdir -p "/run/user/$uid"; chmod 0700 "/run/user/$uid"; chown "$uid:$uid" "/run/user/$uid" 2>/dev/null || true
    done
    eend 0
}
SVC
    chmod +x "$ROOT/etc/init.d/ame-runtime-dir"
    for lvl in boot default; do
        mkdir -p "$ROOT/etc/runlevels/$lvl"
        ln -sf /etc/init.d/ame-runtime-dir "$ROOT/etc/runlevels/$lvl/ame-runtime-dir" 2>/dev/null || true
    done

    mkdir -p "$ROOT/run/user"; chmod 0755 "$ROOT/run/user"
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' "$ROOT/etc/passwd" | while read -r uid; do
        mkdir -p "$ROOT/run/user/$uid"; chmod 0700 "$ROOT/run/user/$uid"; chown "$uid:$uid" "$ROOT/run/user/$uid" 2>/dev/null || true
    done

    for s in dbus elogind seatd polkit networkmanager; do
        for lvl in default boot; do
            mkdir -p "$ROOT/etc/runlevels/$lvl"
            [ -e "$ROOT/etc/init.d/$s" ] && ln -sf "/etc/init.d/$s" "$ROOT/etc/runlevels/$lvl/$s" 2>/dev/null || true
        done
    done

    # Hyprland libstdc++ 修復
    if [ -e "$ROOT/usr/bin/Hyprland" ]; then
        log_info "fixing libstdc++ ABI..."
        chroot "$ROOT" /bin/sh -c '
            export PATH=/sbin:/usr/sbin:/bin:/usr/bin
            apk upgrade --available --force-missing-repositories >/dev/null 2>&1 || true
            apk add --force-overwrite --force-missing-repositories libstdc++ libgcc gcc >/dev/null 2>&1 || true
            apk fix hyprland hyprutils hyprlang hyprcursor >/dev/null 2>&1 || true
        ' || true
    fi

    # autostart 再作成
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
        command -v start-hyprland >/dev/null 2>&1 && start-hyprland || \
        command -v Hyprland >/dev/null 2>&1 && Hyprland || echo "shell"
    fi
fi
AEOF
    chmod +x "$ROOT/etc/profile.d/ame-autostart.sh"

    log_ok "Rescue complete"
    echo "  sync; umount $ROOT; reboot"
    return 0
}

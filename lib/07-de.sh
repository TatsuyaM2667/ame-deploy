#!/bin/sh
# Hyprland / DE インストール v0.6

# 1パッケージグループを安全にインストール
install_pkg_group() {
    local name="$1"
    local pkgs="$2"

    log_info "  group: $name"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkgs 2>&1 | tail -3"

    # 検証: 各パッケージが入ったか
    local missing=""
    for p in $pkgs; do
        chroot "$TARGET" /bin/sh -c "apk info -e $p >/dev/null 2>&1" || missing="$missing $p"
    done
    if [ -n "$missing" ]; then
        log_warn "  missing:$missing"
        return 1
    fi
    log_ok "  $name OK"
    return 0
}

# ---- Hyprland 完全インストール ----
install_hyprland_complete() {
    log_info "=== Hyprland complete install v0.6 ==="
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # 1) edge repo (main + community のみ、testing 除外)
    log_info "[0/6] edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"

    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF

    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -3'

    # 2) ベースランタイム
    log_info "[1/6] runtime base"
    install_pkg_group "runtime-base" "dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc seatd seatd-openrc rtkit"

    # 3) グラフィックス
    log_info "[2/6] graphics"
    install_pkg_group "graphics" "mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati"

    # 4) オーディオ
    log_info "[3/6] audio"
    install_pkg_group "audio" "pipewire pipewire-pulse wireplumber"

    # 5) ネットワーク
    log_info "[4/6] network"
    install_pkg_group "network" "networkmanager networkmanager-cli networkmanager-tui networkmanager-openrc"

    # 6) Hyprland エコシステム
    log_info "[5/6] hyprland ecosystem"
    install_pkg_group "hyprland" "hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk" || {
        log_err "Hyprland install FAILED - check network"
        return 1
    }

    install_pkg_group "hypr-utils" "waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl" || true
    install_pkg_group "fonts" "ttf-dejavu font-noto" || true

    # 7) サービス登録
    log_info "[6/6] services"
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default
    done
    target_rc_add dbus boot
    target_rc_add elogind boot

    # 8) runtime-dir サービス
    install_runtime_dir_service

    # 9) 安全 autostart
    setup_hyprland_autostart_v6

    # 10) 最終検証
    log_info "final verification"
    if chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
        local hv=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1' || echo "?")
        log_ok "Hyprland installed: $hv"
    else
        log_err "Hyprland binary NOT found"
        return 1
    fi

    log_ok "Hyprland complete"
}

setup_hyprland_autostart_v6() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AEOF'
# ame-deploy v0.6: Hyprland autostart (bulletproof)
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"
    RDIR="/run/user/$UID_NUM"

    # /run/user が出るまで最大10秒待つ
    i=0
    while [ $i -lt 10 ]; do
        [ -d "$RDIR" ] && break
        sleep 1
        i=$((i+1))
    done

    # 無ければ作る
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null
    [ -d "$RDIR" ] || { echo "=== /run/user/$UID_NUM unavailable ==="; echo "Check: rc-service ame-runtime-dir status"; echo "Dropping to shell."; }

    if [ -d "$RDIR" ]; then
        chmod 0700 "$RDIR" 2>/dev/null
        export XDG_RUNTIME_DIR="$RDIR"

        # start-hyprland 優先、無ければ Hyprland
        if command -v start-hyprland >/dev/null 2>&1; then
            if ! start-hyprland; then
                echo
                echo "=== start-hyprland failed ==="
                echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"
                echo "Dropping to shell."
            fi
        elif command -v Hyprland >/dev/null 2>&1; then
            if ! Hyprland; then
                echo
                echo "=== Hyprland failed ==="
                echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"
                echo "Dropping to shell."
            fi
        else
            echo "=== Hyprland binary not found ==="
        fi
    fi
fi
AEOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "safe autostart installed"
}

# ---- その他の DE ----
install_de_profile() {
    profile="$1"
    lock="${2:-auto}"
    log_info "Desktop env: $profile (lock=$lock)"

    if [ "$profile" = "04-hyprland" ]; then
        install_hyprland_complete
        return $?
    fi

    case "$profile" in
        00-minimal) log_ok "minimal"; return 0 ;;
        05-sway)
            install_pkg_group "sway" "sway swaybg waybar foot fuzzel mako xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl" || true
            install_pkg_group "runtime" "seatd seatd-openrc dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc pipewire pipewire-pulse wireplumber networkmanager" || true
            for s in dbus elogind seatd polkit networkmanager; do target_rc_add "$s" default; done
            install_runtime_dir_service
            setup_generic_autostart "sway"
            return 0 ;;
        01-river)
            install_pkg_group "river" "river waybar foot fuzzel mako swaybg xdg-desktop-portal xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl" || true
            install_pkg_group "runtime" "seatd seatd-openrc dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc pipewire pipewire-pulse wireplumber networkmanager" || true
            for s in dbus elogind seatd polkit networkmanager; do target_rc_add "$s" default; done
            install_runtime_dir_service
            setup_generic_autostart "river"
            return 0 ;;
        02-kde)
            install_pkg_group "kde" "plasma-desktop plasma-workspace plasma-nm plasma-pa konsole dolphin kate sddm xdg-desktop-portal-kde" || true
            install_pkg_group "runtime" "dbus elogind polkit pipewire pipewire-pulse wireplumber networkmanager" || true
            for s in dbus elogind polkit networkmanager; do target_rc_add "$s" default; done
            install_display_manager sddm
            return 0 ;;
        03-gnome)
            install_pkg_group "gnome" "gnome gnome-shell gnome-session gnome-terminal nautilus gnome-control-center gnome-tweaks xdg-desktop-portal-gnome" || true
            install_pkg_group "runtime" "dbus elogind polkit pipewire pipewire-pulse wireplumber networkmanager" || true
            for s in dbus elogind polkit networkmanager; do target_rc_add "$s" default; done
            install_display_manager gdm
            return 0 ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

setup_generic_autostart() {
    cmd="$1"
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << EOF
if [ -z "\$WAYLAND_DISPLAY" ] && [ -z "\$DISPLAY" ] && [ "\$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="\$(id -u)"
    RDIR="/run/user/\$UID_NUM"
    i=0
    while [ \$i -lt 10 ]; do
        [ -d "\$RDIR" ] && break
        sleep 1
        i=\$((i+1))
    done
    [ -d "\$RDIR" ] || mkdir -p "\$RDIR" 2>/dev/null
    if [ -d "\$RDIR" ]; then
        export XDG_RUNTIME_DIR="\$RDIR"
        chmod 0700 "\$RDIR" 2>/dev/null
        if command -v $cmd >/dev/null 2>&1; then
            $cmd || echo "=== $cmd failed, shell ==="
        fi
    fi
fi
EOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: $cmd"
}

install_display_manager() {
    lock="$1"
    case "$lock" in
        sddm) install_pkg_group "sddm" "sddm" || true; target_rc_add sddm default; log_ok "sddm" ;;
        gdm)
            install_pkg_group "gdm" "gdm" || true
            if [ ! -f "$TARGET/etc/init.d/gdm" ]; then
                cat > "$TARGET/etc/init.d/gdm" << 'GDMEOF'
#!/sbin/openrc-run
name="gdm"
description="GNOME Display Manager"
command="/usr/sbin/gdm"
command_background="yes"
pidfile="/run/gdm.pid"
depend() { need dbus elogind; after localmount; }
start_pre() { checkpath --directory --mode 0755 /run/gdm; }
GDMEOF
                chmod +x "$TARGET/etc/init.d/gdm"
            fi
            target_rc_add gdm default
            log_ok "gdm" ;;
        greetd) install_pkg_group "greetd" "greetd greetd-tuigreet" || true; target_rc_add greetd default; log_ok "greetd" ;;
    esac
}

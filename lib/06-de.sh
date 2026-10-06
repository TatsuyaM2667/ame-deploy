#!/bin/sh
# ---- Hyprland 完全セットアップ（Runtime依存含む） ----
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
EOF
        apk update 2>&1 | tail -2
        apk upgrade --available 2>&1 | tail -3
    '

    # 2) Hyprland + ランタイム依存（最重要）
    log_info "[1/3] Hyprland + runtime deps"
    chroot "$TARGET" /bin/sh -c '
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        apk add --no-cache \
            hyprland \
            xdg-desktop-portal-hyprland \
            xdg-desktop-portal-gtk \
            seatd seatd-openrc \
            elogind elogind-openrc \
            polkit polkit-openrc \
            dbus dbus-openrc \
            rtkit \
            pipewire pipewire-pulse wireplumber \
            networkmanager networkmanager-cli networkmanager-tui networkmanager-openrc \
            mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati \
            waybar foot fuzzel mako swaybg \
            grim slurp wl-clipboard brightnessctl \
            xdg-utils \
            ttf-dejavu font-noto
    ' | tail -10

    # 3) 必須サービス登録
    log_info "[2/3] services"
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default
        target_rc_add "$s" boot
    done

    # 4) 安全 autostart
    log_info "[3/3] safe autostart"
    setup_hyprland_autostart_safe

    log_ok "Hyprland complete"
}

# ---- 安全 autostart（絶対にロックアウトしない） ----
setup_hyprland_autostart_safe() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AEOF'
# ame-deploy: TTY1 autostart (v0.4 safe)
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    if command -v Hyprland >/dev/null 2>&1; then
        # XDG_RUNTIME_DIR 3段フォールバック
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        if [ ! -d "$XDG_RUNTIME_DIR" ] || ! touch "$XDG_RUNTIME_DIR/.test" 2>/dev/null; then
            mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || \
                export XDG_RUNTIME_DIR="/tmp/xdg-$(id -u)"
        fi
        [ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
        chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

        # 失敗してもシェルに戻る（ロックアウト防止）
        if ! Hyprland; then
            echo
            echo "=== Hyprland failed ==="
            echo "Check: cat /tmp/hypr/*/hyprland.log"
            echo "Falling back to shell."
        fi
    fi
fi
AEOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "safe autostart installed"
}

# ---- 他 DE（v0.3 流用） ----
install_de_profile() {
    profile="$1"
    lock="${2:-auto}"
    log_info "Desktop env: $profile (lock=$lock)"

    # Hyprland は専用ルーチン
    if [ "$profile" = "04-hyprland" ]; then
        install_hyprland_complete
        return 0
    fi

    pkgs=""; services=""; mode=""
    case "$profile" in
        00-minimal) log_ok "minimal"; return 0 ;;
        01-river)
            pkgs="river waybar foot fuzzel mako swaybg seatd seatd-openrc xdg-desktop-portal xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl wireplumber pipewire pipewire-pulse"
            services="dbus elogind seatd"; mode="tty" ;;
        02-kde)
            pkgs="plasma-desktop plasma-workspace plasma-nm plasma-pa konsole dolphin kate sddm xdg-desktop-portal-kde wireplumber pipewire pipewire-pulse"
            services="dbus elogind"; mode="dm" ;;
        03-gnome)
            pkgs="gnome gnome-shell gnome-session gnome-terminal nautilus gnome-control-center gnome-tweaks xdg-desktop-portal-gnome"
            services="dbus elogind"; mode="dm" ;;
        05-sway)
            pkgs="sway swaybg waybar foot fuzzel mako seatd seatd-openrc xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl wireplumber pipewire pipewire-pulse"
            services="dbus elogind seatd"; mode="tty" ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac

    pkgs="$pkgs networkmanager networkmanager-cli networkmanager-tui polkit polkit-openrc dbus dbus-openrc elogind elogind-openrc"
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    log_info "[1/3] apk update"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update 2>&1 | tail -2'

    log_info "[2/3] apk add"
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache $pkgs 2>&1" | tail -10

    log_info "[3/3] services"
    for s in $services networkmanager; do
        target_rc_add "$s" default
    done

    if [ "$mode" = "tty" ]; then
        setup_tty_autostart_safe "$profile"
    fi

    if [ "$lock" != "none" ] && [ "$lock" != "auto" ]; then
        install_display_manager "$lock"
    elif [ "$mode" = "dm" ]; then
        case "$profile" in
            02-kde)   install_display_manager sddm ;;
            03-gnome) install_display_manager gdm ;;
        esac
    fi
    log_ok "$profile done"
}

setup_tty_autostart_safe() {
    profile="$1"; cmd=""
    case "$profile" in
        01-river) cmd="river" ;;
        05-sway)  cmd="sway" ;;
        *) return 0 ;;
    esac
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << EOF
if [ -z "\$WAYLAND_DISPLAY" ] && [ -z "\$DISPLAY" ] && [ "\$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    if command -v $cmd >/dev/null 2>&1; then
        export XDG_RUNTIME_DIR="/run/user/\$(id -u)"
        [ -d "\$XDG_RUNTIME_DIR" ] || mkdir -p "\$XDG_RUNTIME_DIR" 2>/dev/null || \
            export XDG_RUNTIME_DIR="/tmp/xdg-\$(id -u)"
        chmod 0700 "\$XDG_RUNTIME_DIR" 2>/dev/null || true
        if ! $cmd; then
            echo "=== $cmd failed, falling back to shell ==="
        fi
    fi
fi
EOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "safe autostart: $cmd"
}

install_display_manager() {
    lock="$1"
    case "$lock" in
        none) return 0 ;;
        sddm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache sddm 2>&1 | tail -2; rc-update add sddm default 2>/dev/null' || true
            log_ok "sddm" ;;
        gdm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache gdm 2>&1 | tail -2' || true
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
        greetd)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache greetd greetd-tuigreet 2>&1 | tail -2; rc-update add greetd default 2>/dev/null' || true
            log_ok "greetd" ;;
    esac
}

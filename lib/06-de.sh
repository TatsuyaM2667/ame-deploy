#!/bin/sh
# Hyprland complete setup v0.5.1

# ---- edge repo switch（chroot 内 heredoc 不使用） ----
edge_repo_switch() {
    log_info "switching target to edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"

    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
REPOEOF

    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update 2>&1 | tail -2'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk upgrade --available 2>&1 | tail -3'
    log_ok "edge repo switched"
}

# ---- Hyprland 完全セットアップ ----
install_hyprland_complete() {
    log_info "=== Hyprland complete install ==="
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    edge_repo_switch

    log_info "[1/4] Hyprland + runtime deps"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk seatd seatd-openrc elogind elogind-openrc polkit polkit-openrc dbus dbus-openrc rtkit pipewire pipewire-pulse wireplumber networkmanager networkmanager-cli networkmanager-tui networkmanager-openrc mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl ttf-dejavu font-noto 2>&1 | tail -10'

    log_info "[2/4] services"
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default
    done
    target_rc_add dbus boot
    target_rc_add elogind boot

    log_info "[3/4] runtime-dir service"
    install_runtime_dir_service

    log_info "[4/4] safe autostart"
    setup_hyprland_autostart_v5

    log_ok "Hyprland complete"
}

setup_hyprland_autostart_v5() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AEOF'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"
    RDIR="/run/user/$UID_NUM"
    i=0
    while [ $i -lt 10 ]; do
        [ -d "$RDIR" ] && break
        sleep 1
        i=$((i+1))
    done
    if [ ! -d "$RDIR" ]; then
        mkdir -p "$RDIR" 2>/dev/null
        chmod 0700 "$RDIR" 2>/dev/null
    fi
    if [ ! -d "$RDIR" ]; then
        echo "=== XDG_RUNTIME_DIR unavailable, shell ==="
    else
        export XDG_RUNTIME_DIR="$RDIR"
        if command -v start-hyprland >/dev/null 2>&1; then
            start-hyprland || echo "=== start-hyprland failed, shell ==="
        elif command -v Hyprland >/dev/null 2>&1; then
            Hyprland || echo "=== Hyprland failed, shell ==="
        fi
    fi
fi
AEOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "safe autostart installed"
}

# ---- その他 DE ----
install_de_profile() {
    profile="$1"
    lock="${2:-auto}"
    log_info "Desktop env: $profile (lock=$lock)"

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

    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update 2>&1 | tail -2'
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache $pkgs 2>&1 | tail -10"

    for s in $services networkmanager; do target_rc_add "$s" default; done

    install_runtime_dir_service

    if [ "$mode" = "tty" ]; then
        setup_hyprland_autostart_v5
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

install_display_manager() {
    lock="$1"
    case "$lock" in
        none) return 0 ;;
        sddm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache sddm 2>&1 | tail -2'
            target_rc_add sddm default
            log_ok "sddm" ;;
        gdm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache gdm 2>&1 | tail -2'
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
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache greetd greetd-tuigreet 2>&1 | tail -2'
            target_rc_add greetd default
            log_ok "greetd" ;;
    esac
}

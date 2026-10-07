#!/bin/sh
install_common() {
    pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc
    pkgs_optional "audio" pipewire pipewire-pulse wireplumber
    pkgs_optional "network" networkmanager networkmanager-cli networkmanager-tui
    pkgs_optional "seat" seatd seatd-openrc rtkit
    pkgs_optional "portal" xdg-desktop-portal xdg-desktop-portal-gtk
    pkgs_optional "tools" grim slurp wl-clipboard brightnessctl
    pkgs_optional "fonts" ttf-dejavu font-noto
    for s in dbus elogind seatd polkit networkmanager wpa_supplicant; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done
    install_runtime_dir_service
}

# ---- Sway (確実) ----
install_sway_complete() {
    if state_done "de-sway" && chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        log_info "Sway already installed"
        return 0
    fi
    log_info "=== Sway install ==="
    enable_edge
    install_common
    pkgs_optional "sway" sway swaybg swayidle swaylock waybar foot fuzzel mako xdg-desktop-portal-wlr xdg-utils
    if ! chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        log_err "sway binary not found"
        return 1
    fi
    setup_autostart_sway
    state_mark "de-sway"
    log_ok "Sway complete"
}

# ---- River (river-classic 優先、無ければ Sway) ----
install_river_complete() {
    if state_done "de-river"; then
        log_info "River already installed"; return 0
    fi
    log_info "=== River install (v3.0: river-classic or Sway fallback) ==="
    enable_edge
    install_common

    # river-classic 存在確認
    if chroot "$TARGET" /bin/sh -c 'apk search -x river-classic 2>/dev/null | grep -q .'; then
        log_info "river-classic available"
        pkgs_optional "river-classic" river-classic riverctl rivertile
        pkgs_optional "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr
        if chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
            write_river_configs_classic
            setup_autostart_sway
            state_mark "de-river"
            log_ok "River-classic complete"
            return 0
        fi
    fi

    # river-classic が無い場合、Sway に自動フォールバック
    log_warn "river-classic not available - using Sway (same Wayland tiling WM)"
    install_sway_complete
    state_mark "de-river"
    log_ok "River -> Sway (fallback)"
}

write_river_configs_classic() {
    # 全ユーザーに river-classic 設定を配置
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
        while IFS='|' read -r u uid gid h; do
            [ -z "$u" ] && continue
            [ -z "$h" ] && h="/home/$u"
            sub="${h#/}"
            mkdir -p "$TARGET/$sub/.config/river"
            cat > "$TARGET/$sub/.config/river/init" << 'RC'
#!/bin/sh
export XDG_CURRENT_DESKTOP=river
export XDG_SESSION_TYPE=wayland
export WLR_RENDERER=pixman
export LIBGL_ALWAYS_SOFTWARE=1
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
mako 2>/dev/null &
rivertile -view-padding 6 -outer-padding 6 2>/dev/null &
riverctl map normal Super Return spawn foot
riverctl map normal Super Q close
riverctl map normal Super D spawn fuzzel
riverctl map normal Super+Shift E exit
riverctl map normal Super J focus-view next
riverctl map normal Super K focus-view previous
riverctl map normal Super+Shift J swap next
riverctl map normal Super+Shift K swap previous
riverctl map normal Super Space toggle-float
riverctl map normal Super F toggle-fullscreen
riverctl modifier Super
RC
            chmod +x "$TARGET/$sub/.config/river/init"
            chroot "$TARGET" /bin/sh -c "chown -R $uid:$gid $h/.config 2>/dev/null" || true
        done < /tmp/ame-users.txt
        rm -f /tmp/ame-users.txt
    fi
    mkdir -p "$TARGET/root/.config/river"
    cat > "$TARGET/root/.config/river/init" << 'RC'
#!/bin/sh
export WLR_RENDERER=pixman
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
riverctl map normal Super Return spawn foot
riverctl map normal Super D spawn fuzzel
riverctl map normal Super Q close
riverctl map normal Super+Shift E exit
riverctl modifier Super
RC
    chmod +x "$TARGET/root/.config/river/init"
}

# ---- GNOME ----
install_gnome_complete() {
    log_info "=== GNOME install ==="
    enable_edge
    install_common
    pkgs_optional "gnome" gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-terminal nautilus xdg-desktop-portal-gnome gnome-tweaks gnome-backgrounds
    pkgs_optional "gdm" gdm
    if [ ! -f "$TARGET/etc/init.d/gdm" ]; then
        cat > "$TARGET/etc/init.d/gdm" << 'G'
#!/sbin/openrc-run
name="gdm"
command="/usr/sbin/gdm"
command_background="yes"
pidfile="/run/gdm.pid"
depend() { need dbus elogind; after localmount; }
start_pre() { checkpath --directory --mode 0755 /run/gdm; }
G
        chmod +x "$TARGET/etc/init.d/gdm"
    fi
    target_rc_add gdm default 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-autostart.sh" 2>/dev/null || true
    state_mark "de-gnome"
    log_ok "GNOME complete (GDM)"
}

# ---- KDE ----
install_kde_complete() {
    log_info "=== KDE Plasma install ==="
    enable_edge
    install_common
    pkgs_optional "plasma" plasma-desktop plasma-workspace plasma-nm plasma-pa plasma-polkit-agent konsole dolphin kate xdg-desktop-portal-kde
    pkgs_optional "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-autostart.sh" 2>/dev/null || true
    state_mark "de-kde"
    log_ok "KDE complete (SDDM)"
}

# ---- Hyprland ----
install_hyprland_complete() {
    log_info "=== Hyprland install (best-effort) ==="
    enable_edge
    install_common
    pkgs_optional "hypr-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl
    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
            v=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1')
            echo "$v" | grep -q "Error relocating" || break
        fi
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories hyprland >/dev/null 2>&1; apk add --force-overwrite --force-missing-repositories libstdc++ libgcc gcc g++ hyprland hyprutils hyprlang >/dev/null 2>&1' || true
    done
    if chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
        setup_autostart_sway
        state_mark "de-hyprland"
        log_ok "Hyprland complete"
        return 0
    fi
    log_warn "Hyprland unavailable - Sway fallback"
    install_sway_complete
    state_mark "de-hyprland"
    return 0
}

install_de_profile() {
    profile="$1"
    log_info "Desktop env: $profile"
    case "$profile" in
        00-minimal) state_mark "de"; return 0 ;;
        01-river) install_river_complete ;;
        02-kde) install_kde_complete ;;
        03-gnome) install_gnome_complete ;;
        04-hyprland) install_hyprland_complete ;;
        05-sway) install_sway_complete ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

# Sway 用 autostart
setup_autostart_sway() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
# ame-deploy v3.0 autostart
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
    chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"

    export WLR_RENDERER=pixman
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export LIBGL_ALWAYS_SOFTWARE=1

    if command -v sway >/dev/null 2>&1; then
        exec sway
    fi
    if command -v river >/dev/null 2>&1 && [ -x "$HOME/.config/river/init" ]; then
        exec river
    fi
    if command -v Hyprland >/dev/null 2>&1; then
        exec Hyprland
    fi
    echo "=== no compositor ==="
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart installed"
}

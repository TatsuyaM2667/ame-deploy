#!/bin/sh

_epi() {
    # 個別 install、失敗許容
    label="$1"; shift
    ok=0; skip=0
    for p in "$@"; do
        if _chroot_apk "apk add --no-cache --force-missing-repositories --force-overwrite $p >/dev/null 2>&1"; then
            ok=$((ok+1))
        else
            log_warn "    skip: $p"
            skip=$((skip+1))
        fi
    done
    log_info "    $label: ok=$ok skip=$skip"
}
_binexists() { chroot "$TARGET" /bin/sh -c "command -v $1 >/dev/null 2>&1"; }

_enable_edge() {
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
    _chroot_apk "apk update --force-missing-repositories 2>&1 | tail -2"
}

_common_runtime() {
    log_info "[runtime] base"
    _epi "core" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc
    _epi "audio" pipewire pipewire-pulse wireplumber
    _epi "network" networkmanager networkmanager-cli networkmanager-tui
    for s in dbus elogind polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
    done
    target_rc_add dbus boot 2>/dev/null || true
    target_rc_add elogind boot 2>/dev/null || true
    install_runtime_dir_service
}
_wayland_runtime() {
    log_info "[runtime] wayland"
    _epi "graphics" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati
    _epi "seat" seatd seatd-openrc rtkit
    _epi "portal" xdg-desktop-portal xdg-desktop-portal-gtk
    _epi "tools" grim slurp wl-clipboard brightnessctl
    _epi "fonts" ttf-dejavu font-noto
    target_rc_add seatd default 2>/dev/null || true
}

setup_generic_autostart() {
    cmd="$1"
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << EOF
if [ -z "\$WAYLAND_DISPLAY" ] && [ -z "\$DISPLAY" ] && [ "\$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="\$(id -u)"
    RDIR="/run/user/\$UID_NUM"
    i=0
    while [ \$i -lt 10 ]; do [ -d "\$RDIR" ] && break; sleep 1; i=\$((i+1)); done
    [ -d "\$RDIR" ] || mkdir -p "\$RDIR" 2>/dev/null
    if [ -d "\$RDIR" ]; then
        export XDG_RUNTIME_DIR="\$RDIR"
        chmod 0700 "\$RDIR" 2>/dev/null
        command -v $cmd >/dev/null 2>&1 && $cmd
    fi
fi
EOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: $cmd"
}

# ---- RIVER (default) ----
install_river_complete() {
    state_done "de-river" && _binexists river && { log_info "River installed - skip"; return 0; }
    log_info "=== River install ==="
    _enable_edge; _common_runtime; _wayland_runtime
    _epi "river" river
    _epi "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr xdg-utils
    _binexists river || { log_err "River binary not found"; return 1; }
    setup_generic_autostart "river"
    state_mark "de-river"
    log_ok "River complete"
}

# ---- SWAY ----
install_sway_complete() {
    state_done "de-sway" && _binexists sway && { log_info "Sway installed - skip"; return 0; }
    log_info "=== Sway install ==="
    _enable_edge; _common_runtime; _wayland_runtime
    _epi "sway" sway
    _epi "sway-tools" swaybg swayidle swaylock waybar foot fuzzel mako xdg-desktop-portal-wlr xdg-utils
    _binexists sway || { log_err "Sway binary not found"; return 1; }
    setup_generic_autostart "sway"
    state_mark "de-sway"
    log_ok "Sway complete"
}

# ---- GNOME ----
install_gnome_complete() {
    state_done "de-gnome" && _binexists gnome-shell && { log_info "GNOME installed - skip"; return 0; }
    log_info "=== GNOME install ==="
    _enable_edge; _common_runtime; _wayland_runtime
    _epi "gnome-core" gnome-shell gnome-session gnome-settings-daemon \
        gnome-control-center gnome-terminal nautilus xdg-desktop-portal-gnome
    _epi "gnome-extras" gnome-tweaks gnome-backgrounds gnome-themes-extra \
        gnome-system-monitor eog evince file-roller
    _epi "gdm" gdm
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
    target_rc_add gdm default 2>/dev/null || true
    _binexists gnome-shell || { log_err "gnome-shell not found"; return 1; }
    state_mark "de-gnome"
    log_ok "GNOME complete (login via GDM)"
}

# ---- KDE ----
install_kde_complete() {
    state_done "de-kde" && chroot "$TARGET" /bin/sh -c 'test -d /usr/share/plasma' 2>/dev/null && \
        { log_info "KDE installed - skip"; return 0; }
    log_info "=== KDE Plasma install ==="
    _enable_edge; _common_runtime; _wayland_runtime
    _epi "plasma-core" plasma-desktop plasma-workspace plasma-nm plasma-pa plasma-polkit-agent
    _epi "kde-apps" konsole dolphin kate xdg-desktop-portal-kde
    _epi "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true
    chroot "$TARGET" /bin/sh -c 'test -d /usr/share/plasma' 2>/dev/null || \
        { log_err "KDE not found"; return 1; }
    state_mark "de-kde"
    log_ok "KDE complete (login via SDDM)"
}

# ---- HYPRLAND (best-effort → Sway fallback) ----
_hypr_works() {
    _binexists Hyprland || return 1
    v=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1' 2>&1)
    echo "$v" | grep -q "Error relocating" && return 1
    return 0
}
install_hyprland_complete() {
    state_done "de-hyprland" && _hypr_works && { log_info "Hyprland OK - skip"; return 0; }
    log_info "=== Hyprland (best-effort) ==="
    _enable_edge; _common_runtime; _wayland_runtime
    _epi "hypr-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl

    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        log_info "  attempt $i/3"
        _hypr_works && break
        if ! _binexists Hyprland; then
            _chroot_apk "apk add --no-cache --force-missing-repositories hyprland 2>&1 | tail -3"
        else
            _chroot_apk "apk add --force-overwrite --force-missing-repositories libstdc++ libgcc gcc g++ >/dev/null 2>&1"
            _chroot_apk "apk add --force-overwrite --force-missing-repositories hyprland hyprutils hyprlang hyprcursor hyprgraphics >/dev/null 2>&1"
        fi
    done
    _epi "portals" xdg-desktop-portal-hyprland xdg-desktop-portal-wlr

    if _hypr_works; then
        setup_generic_autostart "Hyprland"
        state_mark "de-hyprland"
        log_ok "Hyprland complete"
        return 0
    fi
    log_warn "Hyprland unavailable - Sway fallback"
    install_sway_complete
    state_mark "de-hyprland"
}

install_de_profile() {
    profile="$1"
    log_info "Desktop env: $profile"
    case "$profile" in
        00-minimal) state_mark "de"; log_ok "minimal"; return 0 ;;
        01-river)    install_river_complete ;;
        02-kde)      install_kde_complete ;;
        03-gnome)    install_gnome_complete ;;
        04-hyprland) install_hyprland_complete ;;
        05-sway)     install_sway_complete ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

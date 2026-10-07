#!/bin/sh
install_common() {
    pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc
    pkgs_optional "audio" pipewire pipewire-pulse wireplumber
    pkgs_optional "network" networkmanager networkmanager-cli networkmanager-tui networkmanager-wifi
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

install_hyprland_complete() {
    log_info "=== Hyprland install ==="
    enable_edge; install_common
    pkgs_optional "hyprland" hyprland
    pkgs_optional "hypr-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl xdg-desktop-portal-hyprland
    chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1' || { log_err "Hyprland binary not found"; return 1; }
    setup_autostart_hyprland
    state_mark "de-hyprland"
    log_ok "Hyprland complete"
}

install_river_complete() {
    state_done "de-river" && return 0
    log_info "=== River install (river-classic) ==="
    enable_edge; install_common
    pkgs_optional "river-classic" river-classic
    pkgs_optional "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr
    chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1' || { log_err "river binary not found"; return 1; }
    setup_autostart_river
    state_mark "de-river"
    log_ok "River complete"
}

install_sway_complete() {
    state_done "de-sway" && chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1' && return 0
    log_info "=== Sway install ==="
    enable_edge; install_common
    pkgs_optional "sway" sway swaybg swayidle swaylock waybar foot fuzzel mako xdg-desktop-portal-wlr xdg-utils
    chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1' || { log_err "sway binary not found"; return 1; }
    setup_autostart_sway
    state_mark "de-sway"
    log_ok "Sway complete"
}

install_gnome_complete() {
    log_info "=== GNOME install ==="
    enable_edge; install_common
    pkgs_optional "gnome" gnome gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-terminal nautilus xdg-desktop-portal-gnome gnome-tweaks gnome-backgrounds
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
    log_ok "GNOME complete"
}

install_kde_complete() {
    log_info "=== KDE Plasma install ==="
    enable_edge; install_common
    pkgs_optional "plasma" plasma-desktop-meta plasma-nm plasma-pa konsole dolphin kate xdg-desktop-portal-kde
    pkgs_optional "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-autostart.sh" 2>/dev/null || true
    state_mark "de-kde"
    log_ok "KDE complete"
}

install_niri_complete() {
    state_done "de-niri" && chroot "$TARGET" /bin/sh -c 'command -v niri >/dev/null 2>&1' && return 0
    log_info "=== Niri install ==="
    enable_edge; install_common
    pkgs_optional "niri" niri
    pkgs_optional "niri-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl xdg-desktop-portal-gtk
    chroot "$TARGET" /bin/sh -c 'command -v niri >/dev/null 2>&1' || { log_err "niri not found"; return 1; }
    setup_autostart_niri
    state_mark "de-niri"
    log_ok "Niri complete"
}

install_miracle_wm_complete() {
    state_done "de-miracle-wm" && chroot "$TARGET" /bin/sh -c 'command -v miracle-wm >/dev/null 2>&1' && return 0
    log_info "=== Miracle-WM install ==="
    enable_edge; install_common
    pkgs_optional "miracle-wm" miracle-wm
    pkgs_optional "miracle-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl
    chroot "$TARGET" /bin/sh -c 'command -v miracle-wm >/dev/null 2>&1' || { log_err "miracle-wm not found"; return 1; }
    setup_autostart_miracle
    state_mark "de-miracle-wm"
    log_ok "Miracle-WM complete"
}

install_marswm_complete() {
    state_done "de-marswm" && return 0
    log_info "=== MARSWM install (source) ==="
    enable_edge; install_common
    ensure_build_tools
    pkgs_optional "marswm-deps" libx11-dev libxft-dev libxinerama-dev libxrandr-dev
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && rm -rf marswm && git clone --recurse-submodules https://github.com/koekeishiya/marswm 2>&1 | tail -3'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp/marswm && cargo build --release 2>&1 | tail -10'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cp /tmp/marswm/target/release/marswm /usr/local/bin/ 2>/dev/null'
    chroot "$TARGET" /bin/sh -c 'command -v marswm >/dev/null 2>&1' || { log_warn "marswm not found - skipping"; state_mark "de-marswm"; return 0; }
    state_mark "de-marswm"
    log_ok "MARSWM complete"
}

install_orilla_complete() {
    state_done "de-orilla" && return 0
    log_info "=== orilla install (source) ==="
    enable_edge; install_common
    ensure_build_tools
    pkgs_optional "river" river river-classic
    pkgs_optional "orilla-deps" wayland-dev wayland-protocols-dev
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && rm -rf orilla && git clone --recurse-submodules https://git.sr.ht/~hokiegeek/orilla 2>&1 | tail -3'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp/orilla && cargo build --release 2>&1 | tail -10'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cp /tmp/orilla/target/release/orilla /usr/local/bin/ 2>/dev/null'
    chroot "$TARGET" /bin/sh -c 'command -v orilla >/dev/null 2>&1' || { log_warn "orilla not found"; state_mark "de-orilla"; return 0; }
    state_mark "de-orilla"
    log_ok "orilla complete"
}

install_rediwm_complete() {
    state_done "de-rediwm" && return 0
    log_info "=== RedIWM install (source) ==="
    enable_edge; install_common
    ensure_build_tools
    pkgs_optional "rediwm-deps" wlroots0.20-dev wayland-dev wayland-protocols xkbcommon-dev pixman-dev freetype-dev harfbuzz-dev fontconfig-dev librsvg-dev gdk-pixbuf-dev pango-dev cairo-dev libinput-dev pam-dev libpulse-dev libpipewire-dev poppler-glib-dev libseccomp-dev libjpeg-turbo-dev libpng-dev
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && rm -rf rediwm && git clone --recurse-submodules https://github.com/oxydizer/rediwm.git 2>&1 | tail -3'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp/rediwm && zig build -Doptimize=ReleaseSafe 2>&1 | tail -15'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cp /tmp/rediwm/zig-out/bin/rediwm /usr/local/bin/ 2>/dev/null'
    chroot "$TARGET" /bin/sh -c 'command -v rediwm >/dev/null 2>&1' || { log_warn "rediwm build failed - skipping"; state_mark "de-rediwm"; return 0; }
    state_mark "de-rediwm"
    log_ok "RedIWM complete"
}

ensure_build_tools() {
    log_info "  build tools"
    _mount_chroot_fs
    for pkg in git rust cargo zig; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $pkg >/dev/null 2>&1" && \
            log_ok "    $pkg" || log_warn "    skip: $pkg"
    done
    _umount_chroot_fs
}

install_de_profile() {
    profile="$1"
    log_info "Desktop env: $profile"
    case "$profile" in
        00-minimal) state_mark "de"; return 0 ;;
        01-hyprland) install_hyprland_complete ;;
        02-river) install_river_complete ;;
        03-sway) install_sway_complete ;;
        04-gnome) install_gnome_complete ;;
        05-kde) install_kde_complete ;;
        06-rediwm) install_rediwm_complete ;;
        07-miracle-wm) install_miracle_wm_complete ;;
        08-marswm) install_marswm_complete ;;
        09-orilla) install_orilla_complete ;;
        10-niri) install_niri_complete ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

# ============================================================
# autostart (DRM check + pixman + watchdog)
# ============================================================
_write_autostart() {
    target_cmd="$1"
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << AUTO
# ame-deploy v7.0 autostart
if [ -z "\$WAYLAND_DISPLAY" ] && [ -z "\$DISPLAY" ] && [ "\$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="\$(id -u)"
    RDIR="/run/user/\$UID_NUM"
    i=0
    while [ \$i -lt 10 ]; do [ -d "\$RDIR" ] && break; sleep 1; i=\$((i+1)); done
    [ -d "\$RDIR" ] || mkdir -p "\$RDIR" 2>/dev/null
    chmod 0700 "\$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="\$RDIR"

    # pixman fallback (i915 brokenでも動く)
    export WLR_RENDERER=pixman
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export LIBGL_ALWAYS_SOFTWARE=1

    # DRM check
    if ! ls /dev/dri/card* >/dev/null 2>&1; then
        echo
        echo "=========================================="
        echo " WARNING: /dev/dri/card* not found"
        echo " GPU (i915) did not initialize."
        echo " Diagnose: dmesg | grep -iE 'i915|drm'"
        echo "=========================================="
        echo "Press Enter for shell."
        read _ < /dev/tty1
        exec /bin/sh
    fi

    # 起動試行（20s watchdog）
    (sleep 20; pkill -9 -f "$target_cmd" 2>/dev/null) &
    WD=\$!
    $target_cmd 2>/tmp/wayland-\$(id -u).log
    RET=\$?
    kill \$WD 2>/dev/null
    echo "$target_cmd exited (\$RET). Log: /tmp/wayland-\$(id -u).log"
    echo "Falling back to shell."
    exec /bin/sh
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: $target_cmd (with DRM check + pixman)"
}

setup_autostart_hyprland() { _write_autostart "Hyprland"; }
setup_autostart_river()    { _write_autostart "river"; }
setup_autostart_sway()     { _write_autostart "sway"; }
setup_autostart_niri()     { _write_autostart "niri"; }
setup_autostart_miracle()  { _write_autostart "miracle-wm"; }
setup_autostart_rediwm()   { _write_autostart "rediwm"; }

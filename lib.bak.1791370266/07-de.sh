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

# ============================================================
# MARSWM (Rust, X11)
# ============================================================
install_marswm_complete() {
    if state_done "de-marswm" && chroot "$TARGET" /bin/sh -c 'command -v marswm >/dev/null 2>&1'; then
        log_info "MARSWM already installed"; return 0
    fi
    log_info "=== MARSWM install (source) ==="
    enable_edge
    install_common
    pkgs_optional "marswm-deps" rust cargo libx11-dev libxft-dev libxinerama-dev libxrandr-dev
    log_info "  building MARSWM from source..."
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cargo install --root=/usr/local/ marswm marsbar mars-relay 2>&1 | tail -10'
    if ! chroot "$TARGET" /bin/sh -c 'command -v marswm >/dev/null 2>&1'; then
        log_warn "MARSWM binary not found - skipping"
        state_mark "de-marswm"
        return 0
    fi
    state_mark "de-marswm"
    log_ok "MARSWM complete"
}

# ============================================================
# orilla (Rust, River WM)
# ============================================================
install_orilla_complete() {
    if state_done "de-orilla"; then
        log_info "orilla already installed"; return 0
    fi
    log_info "=== orilla install (source) ==="
    enable_edge
    install_common
    pkgs_optional "river" river river-classic
    pkgs_optional "orilla-deps" rust cargo cargo-generate wayland-dev wayland-protocols-dev
    log_info "  building orilla from source..."
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && cargo generate --git https://git.sr.ht/~hokiegeek/orilla.git --subfolder template --name my-orilla --force 2>&1 | tail -5 && cd my-orilla && cargo build --release 2>&1 | tail -5 && cp target/release/my-orilla /usr/local/bin/orilla 2>/dev/null || true'
    if ! chroot "$TARGET" /bin/sh -c 'command -v orilla >/dev/null 2>&1'; then
        log_warn "orilla binary not found - skipping"
        state_mark "de-orilla"
        return 0
    fi
    # river の init に orilla を自動起動設定
    mkdir -p "$TARGET/root/.config/river"
    cat > "$TARGET/root/.config/river/init" << 'RC'
#!/bin/sh
orilla &
RC
    chmod +x "$TARGET/root/.config/river/init"
    state_mark "de-orilla"
    log_ok "orilla complete"
}

# ============================================================
# Niri (Rust, scrollable tiling)
# ============================================================
install_niri_complete() {
    if state_done "de-niri" && chroot "$TARGET" /bin/sh -c 'command -v niri >/dev/null 2>&1'; then
        log_info "Niri already installed"; return 0
    fi
    log_info "=== Niri install ==="
    enable_edge
    install_common
    pkgs_optional "niri" niri
    pkgs_optional "niri-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl xdg-desktop-portal-gtk
    if ! chroot "$TARGET" /bin/sh -c 'command -v niri >/dev/null 2>&1'; then
        log_err "niri binary not found"; return 1
    fi
    setup_autostart_niri
    state_mark "de-niri"
    log_ok "Niri complete"
}

# ============================================================
# 既存WM
# ============================================================
install_hyprland_complete() {
    log_info "=== Hyprland install ==="
    enable_edge
    install_common
    pkgs_optional "hyprland" hyprland
    pkgs_optional "hypr-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl xdg-desktop-portal-hyprland
    if ! chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
        log_err "Hyprland binary not found"; return 1
    fi
    setup_autostart_hyprland
    state_mark "de-hyprland"
    log_ok "Hyprland complete"
}

install_river_complete() {
    if state_done "de-river"; then log_info "River already installed"; return 0; fi
    log_info "=== River install (river-classic) ==="
    enable_edge
    install_common
    pkgs_optional "river-classic" river-classic
    pkgs_optional "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr
    if ! chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
        log_err "river binary not found"; return 1
    fi
    write_river_configs_classic
    setup_autostart_river
    state_mark "de-river"
    log_ok "River complete"
}

install_sway_complete() {
    if state_done "de-sway" && chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        log_info "Sway already installed"; return 0
    fi
    log_info "=== Sway install ==="
    enable_edge
    install_common
    pkgs_optional "sway" sway swaybg swayidle swaylock waybar foot fuzzel mako xdg-desktop-portal-wlr xdg-utils
    if ! chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        log_err "sway binary not found"; return 1
    fi
    setup_autostart_sway
    state_mark "de-sway"
    log_ok "Sway complete"
}

install_gnome_complete() {
    log_info "=== GNOME install ==="
    enable_edge
    install_common
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
    log_ok "GNOME complete (GDM)"
}

install_kde_complete() {
    log_info "=== KDE Plasma install ==="
    enable_edge
    install_common
    pkgs_optional "plasma" plasma-desktop-meta plasma-nm plasma-pa konsole dolphin kate xdg-desktop-portal-kde
    pkgs_optional "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-autostart.sh" 2>/dev/null || true
    state_mark "de-kde"
    log_ok "KDE complete (SDDM)"
}

install_rediwm_complete() {
    log_info "=== RedIWM install (source) ==="
    enable_edge
    install_common
    pkgs_optional "rediwm-deps" zig wlroots0.20-dev wayland-dev wayland-protocols xkbcommon-dev pixman-dev freetype-dev harfbuzz-dev fontconfig-dev librsvg-dev gdk-pixbuf-dev pango-dev cairo-dev libinput-dev pam-dev libpulse-dev libpipewire-dev poppler-glib-dev libseccomp-dev libjpeg-turbo-dev libpng-dev
    log_info "  building RedIWM from source..."
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && git clone --depth 1 https://github.com/oxydizer/rediwm.git 2>&1 | tail -2 && cd rediwm && zig build -Doptimize=ReleaseSafe 2>&1 | tail -5 && cp zig-out/bin/rediwm /usr/local/bin/ && cp zig-out/bin/rediwm-dm /usr/local/bin/ 2>/dev/null || true'
    if ! chroot "$TARGET" /bin/sh -c 'command -v rediwm >/dev/null 2>&1'; then
        log_err "rediwm binary not found"; return 1
    fi
    setup_autostart_rediwm
    state_mark "de-rediwm"
    log_ok "RedIWM complete"
}

install_miracle_wm_complete() {
    if state_done "de-miracle-wm" && chroot "$TARGET" /bin/sh -c 'command -v miracle-wm >/dev/null 2>&1'; then
        log_info "Miracle-WM already installed"; return 0
    fi
    log_info "=== Miracle-WM install ==="
    enable_edge
    install_common
    pkgs_optional "miracle-wm" miracle-wm
    pkgs_optional "miracle-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl
    if ! chroot "$TARGET" /bin/sh -c 'command -v miracle-wm >/dev/null 2>&1'; then
        log_err "miracle-wm binary not found"; return 1
    fi
    setup_autostart_miracle
    state_mark "de-miracle-wm"
    log_ok "Miracle-WM complete"
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
# autostart 設定
# ============================================================
setup_autostart_hyprland() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v Hyprland >/dev/null 2>&1 && exec Hyprland
    command -v sway >/dev/null 2>&1 && exec sway
    command -v river >/dev/null 2>&1 && exec river
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: Hyprland"
}

setup_autostart_river() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v river >/dev/null 2>&1 && exec river
    command -v sway >/dev/null 2>&1 && exec sway
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: River"
}

setup_autostart_sway() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v sway >/dev/null 2>&1 && exec sway
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: Sway"
}

setup_autostart_rediwm() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v rediwm >/dev/null 2>&1 && exec rediwm
    command -v sway >/dev/null 2>&1 && exec sway
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: RedIWM"
}

setup_autostart_miracle() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v miracle-wm >/dev/null 2>&1 && exec miracle-wm
    command -v sway >/dev/null 2>&1 && exec sway
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: Miracle-WM"
}

setup_autostart_niri() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="$(id -u)"; RDIR="/run/user/$UID_NUM"
    i=0; while [ $i -lt 10 ]; do [ -d "$RDIR" ] && break; sleep 1; i=$((i+1)); done
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null; chmod 0700 "$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="$RDIR"
    command -v niri >/dev/null 2>&1 && exec niri
    command -v sway >/dev/null 2>&1 && exec sway
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: Niri"
}

write_river_configs_classic() {
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

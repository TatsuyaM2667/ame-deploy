#!/bin/sh
pkgs_optional() {
    label="$1"; shift
    log_info "  $label"
    ok=0
    for p in "$@"; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1" && ok=$((ok+1)) || log_warn "    skip: $p"
    done
    log_ok "  $label: ok=$ok"
}
enable_edge() {
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'
}
install_common() {
    pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc
    pkgs_optional "audio" pipewire pipewire-pulse wireplumber
    pkgs_optional "network" networkmanager networkmanager-cli networkmanager-tui
    pkgs_optional "graphics" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati
    pkgs_optional "seat" seatd seatd-openrc rtkit
    pkgs_optional "portal" xdg-desktop-portal xdg-desktop-portal-gtk
    pkgs_optional "tools" grim slurp wl-clipboard brightnessctl
    pkgs_optional "fonts" ttf-dejavu font-noto
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
    done
    target_rc_add dbus boot 2>/dev/null || true
    target_rc_add elogind boot 2>/dev/null || true
    install_runtime_dir_service
}
# ---------- River 完全インストール ----------
install_river_complete() {
    if state_done "de-river"; then
        log_info "River already installed"; return 0
    fi
    log_info "=== River install v2.0.3 (river-classic + rivercarro + river-bedload) ==="
    enable_edge
    install_common
    # river-classic 本体（river, riverctl, rivertile を含む）
    log_info "[1/3] river-classic"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories river-classic 2>&1 | tail -3' || true
    # rivercarro (layout generator)
    log_info "[2/3] rivercarro"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories rivercarro@testing 2>&1 | tail -3' || true
    # river-bedload (status info to stdout)
    log_info "[3/3] river-bedload"
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories river-bedload@testing 2>&1 | tail -3' || true
    # その他便利ツール
    pkgs_optional "river-tools" foot waybar fuzzel mako swaybg xdg-desktop-portal-wlr xdg-utils
    # 検証
    if ! chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
        log_err "river binary not found after install"
        return 1
    fi
    # サンプル init をコピー
    local sample_init="/usr/share/doc/river/examples/init"
    local sample_init_alt="/usr/share/river/example/init"
    local src_sample=""
    if [ -f "$TARGET$sample_init" ]; then src_sample="$sample_init"
    elif [ -f "$TARGET$sample_init_alt" ]; then src_sample="$sample_init_alt"
    fi
    # ユーザー用の home を準備（存在しない場合）
    mkdir -p "$TARGET/home/ame" "$TARGET/home/tatsuya" "$TARGET/root"
    local users="ame tatsuya root"
    for u in $users; do
        local h="/home/$u"
        [ "$u" = "root" ] && h="/root"
        mkdir -p "$TARGET$h/.config/river"
        if [ -n "$src_sample" ] && [ -f "$TARGET$src_sample" ]; then
            cp "$TARGET$src_sample" "$TARGET$h/.config/river/init"
        else
            # フォールバック: 基本的な init を手動作成
            cat > "$TARGET$h/.config/river/init" << 'RC'
#!/bin/sh
export XDG_CURRENT_DESKTOP=river
export XDG_SESSION_TYPE=wayland
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
mako 2>/dev/null &
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
# rivercarro があれば利用
if command -v rivercarro >/dev/null 2>&1; then
    riverctl default-layout rivercarro
    rivercarro -outer-gaps 6 -inner-gaps 6 2>/dev/null &
else
    riverctl default-layout rivertile
    rivertile -view-padding 6 -outer-padding 6 2>/dev/null &
fi
RC
        fi
        chmod +x "$TARGET$h/.config/river/init"
    done
    # 所有者を設定
    uid_ame=$(chroot "$TARGET" /bin/sh -c "id -u ame 2>/dev/null" || echo 1000)
    chown -R "$uid_ame:$uid_ame" "$TARGET/home/ame" 2>/dev/null || true
    chown -R 1001:1001 "$TARGET/home/tatsuya" 2>/dev/null || true
    chown -R 0:0 "$TARGET/root" 2>/dev/null || true
    setup_autostart
    state_mark "de-river"
    log_ok "River complete"
}
install_sway_complete() {
    log_info "=== Sway install ==="
    enable_edge
    install_common
    pkgs_optional "sway" sway swaybg waybar foot fuzzel mako xdg-desktop-portal-wlr
    setup_autostart
    state_mark "de-sway"
    log_ok "Sway complete"
}
install_gnome_complete() {
    log_info "=== GNOME install ==="
    enable_edge
    install_common
    pkgs_optional "gnome-core" gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-terminal nautilus xdg-desktop-portal-gnome
    pkgs_optional "gnome-extras" gnome-tweaks gnome-backgrounds
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
    log_ok "GNOME complete (login via GDM)"
}
install_kde_complete() {
    log_info "=== KDE Plasma install ==="
    enable_edge
    install_common
    pkgs_optional "plasma" plasma-desktop plasma-workspace plasma-nm plasma-pa plasma-polkit-agent konsole dolphin kate xdg-desktop-portal-kde
    pkgs_optional "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-autostart.sh" 2>/dev/null || true
    state_mark "de-kde"
    log_ok "KDE complete (login via SDDM)"
}
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
        setup_autostart
        state_mark "de-hyprland"
        log_ok "Hyprland complete"
        return 0
    fi
    log_warn "Hyprland unavailable - installing Sway fallback"
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
setup_autostart() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
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
    if command -v river >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/river" 2>/dev/null
        if [ ! -f "$HOME/.config/river/init" ]; then
            printf '#!/bin/sh\nswaybg -c "#1a1a2e" &\nwaybar &\nriverctl map normal Super Return spawn foot\nriverctl map normal Super D spawn fuzzel\nriverctl map normal Super Q close\nriverctl map normal Super+Shift E exit\nriverctl modifier Super\n' > "$HOME/.config/river/init"
            chmod +x "$HOME/.config/river/init"
        fi
        exec river
    elif command -v sway >/dev/null 2>&1; then
        exec sway
    elif command -v Hyprland >/dev/null 2>&1; then
        exec Hyprland
    fi
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart installed (river/sway/hyprland)"
}

# ============ v2.0.4 override: install_river_complete ============
install_river_complete() {
    if state_done "de-river"; then
        log_info "River already installed"; return 0
    fi
    log_info "=== River install v2.0.4 (auto-detect) ==="
    enable_edge
    install_common

    # 利用可能な river 関連パッケージを確認
    AVAIL=$(chroot "$TARGET" /bin/sh -c 'apk search -x river 2>/dev/null' 2>/dev/null || true)
    AVAIL=$(chroot "$TARGET" /bin/sh -c 'apk search river 2>/dev/null | head -20' 2>/dev/null || true)
    log_info "available river packages:"
    echo "$AVAIL" | while read -r line; do [ -n "$line" ] && log_info "  $line"; done

    # 1) river-classic があれば優先
    if echo "$AVAIL" | grep -q '^river-classic'; then
        log_info "[1/3] installing river-classic"
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories river-classic 2>&1 | tail -3' || true
        pkgs_optional "river-tools" riverctl rivertile waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr xdg-utils

        if chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
            _river_write_classic_configs
            setup_autostart_river
            state_mark "de-river"
            log_ok "River-classic complete (riverctl compatible)"
            return 0
        fi
    fi

    # 2) river (0.4.x) の場合は Sway へ fallback
    log_warn "[2/3] river-classic not available, river 0.4.x is not usable here"
    log_warn "      switching to Sway (same wayland tiling WM)"
    install_sway_complete
    state_mark "de-river"
    log_ok "Sway installed (River fallback)"
    return 0
}

# river-classic 用の config を全ユーザーに配置
_river_write_classic_configs() {
    log_info "writing river-classic configs to all users"
    _write_river_config_to() {
        u="$1"
        h="$2"
        [ -z "$u" ] && return
        [ -z "$h" ] && h="/home/$u"
        [ "$u" = "root" ] && h="/root"
        mkdir -p "$TARGET$h/.config/river"
        cat > "$TARGET$h/.config/river/init" << 'RC'
#!/bin/sh
export XDG_CURRENT_DESKTOP=river
export XDG_SESSION_TYPE=wayland
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
        chmod +x "$TARGET$h/.config/river/init"
        uid=$(chroot "$TARGET" /bin/sh -c "id -u $u 2>/dev/null" || echo 1000)
        gid=$(chroot "$TARGET" /bin/sh -c "id -g $u 2>/dev/null" || echo 1000)
        chroot "$TARGET" /bin/sh -c "chown -R $uid:$gid $h/.config 2>/dev/null" || true
        log_ok "  config -> $h/.config/river/init"
    }
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-u.txt
        while IFS='|' read -r u h; do _write_river_config_to "$u" "$h"; done < /tmp/ame-u.txt
        rm -f /tmp/ame-u.txt
    fi
    _write_river_config_to "root" "/root"
}

setup_autostart_river() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
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
    if command -v river >/dev/null 2>&1 && [ -x "$HOME/.config/river/init" ]; then
        exec river
    elif command -v sway >/dev/null 2>&1; then
        exec sway
    elif command -v Hyprland >/dev/null 2>&1; then
        exec Hyprland
    fi
fi
AUTO
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart installed"
}

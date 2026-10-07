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

# ============================================================
# Sway 専用: バージョン検出 + 互換起動スクリプト配置
# ============================================================
install_sway_complete() {
    state_done "de-sway" && chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1' && return 0
    log_info "=== Sway install ==="
    enable_edge; install_common
    pkgs_optional "sway" sway swaybg swayidle swaylock waybar foot fuzzel mako xdg-desktop-portal-wlr xdg-utils
    chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1' || { log_err "sway not found"; return 1; }

    # Sway / wlroots バージョン取得
    SWAY_VER=$(chroot "$TARGET" /bin/sh -c 'sway --version 2>&1 | head -1' 2>/dev/null)
    WLR_VER=$(chroot "$TARGET" /bin/sh -c 'apk info -v 2>/dev/null | grep "^wlroots" | head -1' 2>/dev/null)
    log_info "  $SWAY_VER"
    log_info "  $WLR_VER"

    # バージョン互換: Sway 1.12+ / wlroots 0.20+ は pixman + no-modifiers + no-atomic 必須
    WLR_VER_NUM=$(echo "$WLR_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    case "$WLR_VER_NUM" in
        0.20*|0.21*|0.22*|0.23*|0.24*|0.25*|0.26*)
            log_info "  wlroots $WLR_VER_NUM - applying 0.20+ compat flags"
            mkdir -p "$TARGET/etc/environment.d"
            cat > "$TARGET/etc/environment.d/10-wlroots-compat.conf" << 'WLR'
WLR_RENDERER=pixman
WLR_RENDERER_ALLOW_SOFTWARE=1
WLR_DRM_NO_MODIFIERS=1
WLR_DRM_NO_ATOMIC=1
WLR_NO_HARDWARE_CURSORS=1
WLR_LIBINPUT_NO_DEVICES=1
WLR_RENDERER_ALLOW_READBACK=1
WLR_NO_EXTRA_ENV=1
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=sway
WLR
            ;;
    esac

    # sway 起動スクリプト（フォールバック付き）
    cat > "$TARGET/usr/local/bin/ame-start-sway" << 'SWAYWRAP'
#!/bin/sh
# ame-deploy: Sway 起動ラッパー（バージョン互換 + フォールバック）
UID_NUM="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/$UID_NUM"
[ -d "$XDG_RUNTIME_DIR" ] || { mkdir -p "$XDG_RUNTIME_DIR"; chmod 0700 "$XDG_RUNTIME_DIR"; }

# DRM チェック
if ! ls /dev/dri/card* >/dev/null 2>&1; then
    echo "ame-start-sway: /dev/dri/card* not found - GPU driver missing"
    exit 1
fi

# 試行順序: 各レンダラ x DRM設定
for cfg in \
    "pixman:1:1:1:0" \
    "pixman:1:1:0:0" \
    "gles2:1:1:1:0" \
    "gles2:0:1:1:0" \
    "vulkan:1:1:1:0" ; do
    IFS=: read RENDERER NO_MODIFIERS NO_ATOMIC ALLOW_SW NO_CURSORS <<EOF
$cfg
EOF
    export WLR_RENDERER="$RENDERER"
    [ "$NO_MODIFIERS" = "1" ] && export WLR_DRM_NO_MODIFIERS=1 || unset WLR_DRM_NO_MODIFIERS
    [ "$NO_ATOMIC"    = "1" ] && export WLR_DRM_NO_ATOMIC=1    || unset WLR_DRM_NO_ATOMIC
    [ "$ALLOW_SW"     = "1" ] && export WLR_RENDERER_ALLOW_SOFTWARE=1 || unset WLR_RENDERER_ALLOW_SOFTWARE
    [ "$NO_CURSORS"   = "1" ] && export WLR_NO_HARDWARE_CURSORS=1    || unset WLR_NO_HARDWARE_CURSORS

    echo "ame-start-sway: trying renderer=$RENDERER mod=$NO_MODIFIERS atomic=$NO_ATOMIC sw=$ALLOW_SW"
    # 5秒 watchdog で試行
    (sleep 5; pkill -9 -f '^sway$' 2>/dev/null) &
    WD=$!
    sway 2>/tmp/sway-try.log
    RET=$?
    kill $WD 2>/dev/null
    # 5秒以内に kill された (137) なら失敗と判定して次へ
    if [ $RET -eq 137 ]; then
        echo "ame-start-sway: $RENDERER failed (timeout), retrying..."
        continue
    fi
    # 正常終了なら抜ける
    [ $RET -eq 0 ] && exit 0
done

echo "ame-start-sway: all configs failed. Last log:"
tail -30 /tmp/sway-try.log
echo
echo "Dropping to shell."
exit 1
SWAYWRAP
    chmod +x "$TARGET/usr/local/bin/ame-start-sway"

    setup_autostart "ame-start-sway"
    state_mark "de-sway"
    log_ok "Sway complete (with version-compat wrapper)"
}

install_hyprland_complete() {
    log_info "=== Hyprland install ==="
    enable_edge; install_common
    pkgs_optional "hyprland" hyprland
    pkgs_optional "hypr-tools" waybar foot fuzzel mako swaybg grim slurp wl-clipboard brightnessctl xdg-desktop-portal-hyprland
    chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1' || { log_err "Hyprland not found"; return 1; }
    setup_autostart "Hyprland"
    state_mark "de-hyprland"
    log_ok "Hyprland complete"
}

install_river_complete() {
    state_done "de-river" && return 0
    log_info "=== River install (river-classic) ==="
    enable_edge; install_common
    pkgs_optional "river-classic" river-classic
    pkgs_optional "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal-wlr
    chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1' || { log_err "river not found"; return 1; }
    setup_autostart "river"
    state_mark "de-river"
    log_ok "River complete"
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
    setup_autostart "niri"
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
    setup_autostart "miracle-wm"
    state_mark "de-miracle-wm"
    log_ok "Miracle-WM complete"
}

install_marswm_complete() {
    state_done "de-marswm" && return 0
    log_info "=== MARSWM install (source) ==="
    enable_edge; install_common; ensure_build_tools
    pkgs_optional "marswm-deps" libx11-dev libxft-dev libxinerama-dev libxrandr-dev
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && rm -rf marswm && git clone --recurse-submodules https://github.com/koekeishiya/marswm 2>&1 | tail -3'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp/marswm && cargo build --release 2>&1 | tail -10'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cp /tmp/marswm/target/release/marswm /usr/local/bin/ 2>/dev/null'
    chroot "$TARGET" /bin/sh -c 'command -v marswm >/dev/null 2>&1' || { log_warn "marswm not found"; state_mark "de-marswm"; return 0; }
    state_mark "de-marswm"
    log_ok "MARSWM complete"
}

install_orilla_complete() {
    state_done "de-orilla" && return 0
    log_info "=== orilla install (source) ==="
    enable_edge; install_common; ensure_build_tools
    pkgs_optional "river" river river-classic
    pkgs_optional "orilla-deps" wayland-dev wayland-protocols-dev
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp && rm -rf orilla && git clone --recurse-submodules https://git.sr.ht/~hokiegeek/orilla 2>&1 | tail -3'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cd /tmp/orilla && cargo build --release 2>&1 | tail -10'
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; cp /tmp/orilla/target/release/orilla /usr/local/bin/ 2>/dev/null'
    chroot "$TARGET" /bin/sh -c 'command -v orilla >/dev/null 2>&1' || { log_warn "orilla not found"; state_mark "de-orilla"; return 0; }
    state_mark "de-orilla"
    log_ok "orilla complete"
}

ensure_build_tools() {
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
        06-niri) install_niri_complete ;;
        07-miracle-wm) install_miracle_wm_complete ;;
        08-marswm) install_marswm_complete ;;
        09-orilla) install_orilla_complete ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

# 汎用 autostart（DRM チェック + pixman + watchdog + フォールバック）
setup_autostart() {
    target_cmd="$1"
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << AUTO
if [ -z "\$WAYLAND_DISPLAY" ] && [ -z "\$DISPLAY" ] && [ "\$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    UID_NUM="\$(id -u)"
    RDIR="/run/user/\$UID_NUM"
    i=0; while [ \$i -lt 10 ]; do [ -d "\$RDIR" ] && break; sleep 1; i=\$((i+1)); done
    [ -d "\$RDIR" ] || mkdir -p "\$RDIR" 2>/dev/null
    chmod 0700 "\$RDIR" 2>/dev/null
    export XDG_RUNTIME_DIR="\$RDIR"

    # wlroots 0.20+ 互換デフォルト
    export WLR_RENDERER=pixman
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export WLR_DRM_NO_MODIFIERS=1
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBGL_ALWAYS_SOFTWARE=1

    # DRM チェック
    if ! ls /dev/dri/card* >/dev/null 2>&1; then
        echo
        echo "=========================================="
        echo " ame-autostart: /dev/dri/card* not found"
        echo " GPU driver failed. Dropping to shell."
        echo " Diagnose: dmesg | grep i915"
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
    log_ok "autostart: $target_cmd"
}

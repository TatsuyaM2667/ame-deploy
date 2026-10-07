#!/bin/sh
# DE インストーラ v0.8 - River/Sway/GNOME/KDE 確実版

# ---------- 共通ヘルパ ----------
_de_pkg_install() {
    # 個別 install、失敗は log に残す。OK数/Skip数を返す
    local label="$1"; shift
    local ok=0 skip=0
    for p in "$@"; do
        if chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1"; then
            ok=$((ok+1))
        else
            log_warn "    skip: $p"
            skip=$((skip+1))
        fi
    done
    log_info "    $label: ok=$ok skip=$skip"
}

_de_pkg_retry() {
    # 必須パッケージ：リトライ + force-overwrite（apk del は絶対にしない）
    local label="$1"; shift
    local pkgs="$*"
    local max=3 i=0
    while [ $i -lt $max ]; do
        i=$((i+1))
        log_info "  [$label] attempt $i/$max"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories --force-overwrite $pkgs 2>&1 | tail -3"
        # 検証は呼び出し側で行う（コマンド名が違うため）
        return 0
    done
}

_de_binary_exists() {
    chroot "$TARGET" /bin/sh -c "command -v $1 >/dev/null 2>&1"
}

# ---------- 共通ランタイム ----------
_de_install_common_runtime() {
    log_info "[runtime] base services"
    _de_pkg_install "core" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc
    _de_pkg_install "audio" pipewire pipewire-pulse wireplumber
    _de_pkg_install "network" networkmanager networkmanager-cli networkmanager-tui

    for s in dbus elogind polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
    done
    target_rc_add dbus boot 2>/dev/null || true
    target_rc_add elogind boot 2>/dev/null || true

    install_runtime_dir_service
}

_de_install_wayland_runtime() {
    log_info "[runtime] wayland"
    _de_pkg_install "graphics" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati
    _de_pkg_install "seat" seatd seatd-openrc rtkit
    _de_pkg_install "portal" xdg-desktop-portal xdg-desktop-portal-gtk
    _de_pkg_install "tools" grim slurp wl-clipboard brightnessctl
    _de_pkg_install "fonts" ttf-dejavu font-noto
    target_rc_add seatd default 2>/dev/null || true
}

# ---------- edge repo 有効化 ----------
_de_enable_edge() {
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/repositories.stable.bak" 2>/dev/null || true

    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'
}

# ============================================================
# River (DEFAULT)
# ============================================================
install_river_complete() {
    if state_done "de-river" && _de_binary_exists river; then
        log_info "River already installed - skip"
        return 0
    fi

    log_info "=== River install ==="
    _de_enable_edge
    _de_install_common_runtime
    _de_install_wayland_runtime

    log_info "[river] packages"
    _de_pkg_retry "river" river
    _de_pkg_install "river-tools" \
        waybar foot fuzzel mako swaybg \
        xdg-desktop-portal-wlr \
        xdg-utils

    if ! _de_binary_exists river; then
        log_err "River binary not found"
        return 1
    fi

    setup_generic_autostart "river"
    state_mark "de-river"
    log_ok "River complete"
    return 0
}

# ============================================================
# Sway
# ============================================================
install_sway_complete() {
    if state_done "de-sway" && _de_binary_exists sway; then
        log_info "Sway already installed - skip"
        return 0
    fi

    log_info "=== Sway install ==="
    _de_enable_edge
    _de_install_common_runtime
    _de_install_wayland_runtime

    log_info "[sway] packages"
    _de_pkg_retry "sway" sway
    _de_pkg_install "sway-tools" \
        swaybg swayidle swaylock \
        waybar foot fuzzel mako \
        xdg-desktop-portal-wlr \
        xdg-utils

    if ! _de_binary_exists sway; then
        log_err "Sway binary not found"
        return 1
    fi

    setup_generic_autostart "sway"
    state_mark "de-sway"
    log_ok "Sway complete"
    return 0
}

# ============================================================
# GNOME
# ============================================================
install_gnome_complete() {
    if state_done "de-gnome" && _de_binary_exists gnome-shell; then
        log_info "GNOME already installed - skip"
        return 0
    fi

    log_info "=== GNOME install ==="
    _de_enable_edge
    _de_install_common_runtime
    _de_install_wayland_runtime

    log_info "[gnome] core packages"
    _de_pkg_retry "gnome-core" \
        gnome-shell gnome-session gnome-settings-daemon \
        gnome-control-center gnome-terminal nautilus \
        xdg-desktop-portal-gnome

    log_info "[gnome] extras"
    _de_pkg_install "gnome-extras" \
        gnome-tweaks gnome-backgrounds gnome-themes-extra \
        gnome-system-monitor eog evince file-roller

    log_info "[gnome] display manager (gdm)"
    _de_pkg_install "gdm" gdm
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

    if ! _de_binary_exists gnome-shell; then
        log_err "gnome-shell not found after install"
        return 1
    fi

    state_mark "de-gnome"
    log_ok "GNOME complete (login via GDM)"
    return 0
}

# ============================================================
# KDE Plasma
# ============================================================
install_kde_complete() {
    if state_done "de-kde" && chroot "$TARGET" /bin/sh -c 'test -d /usr/share/plasma' 2>/dev/null; then
        log_info "KDE already installed - skip"
        return 0
    fi

    log_info "=== KDE Plasma install ==="
    _de_enable_edge
    _de_install_common_runtime
    _de_install_wayland_runtime

    log_info "[kde] core packages"
    _de_pkg_retry "plasma-core" \
        plasma-desktop plasma-workspace \
        plasma-nm plasma-pa plasma-polkit-agent

    log_info "[kde] apps"
    _de_pkg_install "kde-apps" \
        konsole dolphin kate \
        xdg-desktop-portal-kde

    log_info "[kde] display manager (sddm)"
    _de_pkg_install "sddm" sddm
    target_rc_add sddm default 2>/dev/null || true

    if ! chroot "$TARGET" /bin/sh -c 'test -d /usr/share/plasma' 2>/dev/null; then
        log_err "KDE plasma not found after install"
        return 1
    fi

    state_mark "de-kde"
    log_ok "KDE complete (login via SDDM)"
    return 0
}

# ============================================================
# Hyprland（best-effort、失敗時 Sway）
# ============================================================
_hyprland_works() {
    _de_binary_exists Hyprland || return 1
    local v
    v=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1' 2>&1)
    echo "$v" | grep -q "Error relocating" && return 1
    return 0
}

install_hyprland_complete() {
    if state_done "de-hyprland" && _hyprland_works; then
        log_info "Hyprland already installed - skip"
        return 0
    fi

    log_info "=== Hyprland install (best-effort) ==="
    _de_enable_edge
    _de_install_common_runtime
    _de_install_wayland_runtime

    _de_pkg_install "hypr-tools" \
        waybar foot fuzzel mako swaybg \
        grim slurp wl-clipboard brightnessctl

    log_info "[hyprland] attempts with ABI fix"
    local max=3 i=0 ok=0
    while [ $i -lt $max ]; do
        i=$((i+1))
        log_info "  attempt $i/$max"

        _hyprland_works && { ok=1; break; }

        if ! _de_binary_exists Hyprland; then
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories hyprland 2>&1 | tail -3' || true
        else
            # ABI fix only (no apk del)
            chroot "$TARGET" /bin/sh -c '
                export PATH=/sbin:/usr/sbin:/bin:/usr/bin
                apk add --force-overwrite --force-missing-repositories libstdc++ libgcc gcc g++ >/dev/null 2>&1
                apk add --force-overwrite --force-missing-repositories hyprland hyprutils hyprlang hyprcursor hyprgraphics >/dev/null 2>&1
            ' || true
        fi
    done

    _de_pkg_install "portals" xdg-desktop-portal-hyprland xdg-desktop-portal-wlr

    if [ "$ok" = "1" ] || _hyprland_works; then
        setup_generic_autostart "Hyprland"
        state_mark "de-hyprland"
        log_ok "Hyprland complete"
        return 0
    fi

    log_warn "Hyprland unavailable - installing Sway as fallback"
    install_sway_complete
    state_mark "de-hyprland"  # mark as attempted
    return 0
}

# ============================================================
# dispatcher
# ============================================================
install_de_profile() {
    profile="$1"
    lock="${2:-auto}"
    log_info "Desktop env: $profile (lock=$lock)"

    case "$profile" in
        00-minimal) log_ok "minimal"; state_mark "de"; return 0 ;;
        01-river)    install_river_complete ;;
        02-kde)      install_kde_complete ;;
        03-gnome)    install_gnome_complete ;;
        04-hyprland) install_hyprland_complete ;;
        05-sway)     install_sway_complete ;;
        *) log_err "unknown: $profile"; return 1 ;;
    esac
}

# ---------- autostart helpers ----------
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
            $cmd || { echo "=== $cmd failed, shell ==="; echo "Log: cat /tmp/*/hyprland.log 2>/dev/null"; }
        fi
    fi
fi
EOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart: $cmd"
}

setup_hyprland_autostart_v7() { setup_generic_autostart "Hyprland"; }

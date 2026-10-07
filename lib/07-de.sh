#!/bin/sh
# Hyprland / DE インストール v0.6.3 - resilient

# 1つずつ install（失敗してもスキップ）
install_pkgs_optional() {
    local label="$1"
    shift
    log_info "  $label"
    local ok=0 skip=0
    for p in "$@"; do
        if chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1"; then
            ok=$((ok+1))
        else
            log_warn "    skip: $p"
            skip=$((skip+1))
        fi
    done
    log_ok "  $label: ok=$ok skip=$skip"
}

# 1つずつ install（1つでも失敗したらエラー）
install_pkgs_required() {
    local label="$1"
    shift
    log_info "  $label (required)"
    local failed=""
    for p in "$@"; do
        if chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1"; then
            :  # ok
        else
            log_warn "    FAILED: $p"
            failed="$failed $p"
        fi
    done
    if [ -n "$failed" ]; then
        log_err "  required failed:$failed"
        return 1
    fi
    log_ok "  $label OK"
    return 0
}

# ---- Hyprland 完全インストール ----
install_hyprland_complete() {
    log_info "=== Hyprland complete install v0.6.3 ==="
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo
    log_info "[0/7] edge repo"
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"
    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    # ---- 必須: Hyprland 本体 ----
    log_info "[1/7] Hyprland (required)"
    if ! install_pkgs_required "hyprland" hyprland; then
        log_err "Hyprland itself cannot be installed"
        echo "  Try: chroot $TARGET /bin/sh"
        echo "       apk add hyprland-git    # if exists"
        echo "       apk search hyprland"
        return 1
    fi

    # ---- 必須: ランタイム ----
    log_info "[2/7] runtime (required)"
    install_pkgs_required "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc || true

    # ---- 推奨: グラフィックス ----
    log_info "[3/7] graphics (recommended)"
    install_pkgs_optional "graphics" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati

    # ---- 推奨: オーディオ ----
    log_info "[4/7] audio (recommended)"
    install_pkgs_optional "audio" pipewire pipewire-pulse wireplumber

    # ---- 推奨: ネットワーク ----
    log_info "[5/7] network (recommended)"
    install_pkgs_optional "network" networkmanager networkmanager-cli networkmanager-tui

    # ---- 推奨: Wayland ツール（1個ずつ） ----
    log_info "[6/7] hyprland utilities"
    install_pkgs_optional "hypr-tools" \
        xdg-desktop-portal xdg-desktop-portal-gtk \
        seatd seatd-openrc rtkit \
        waybar foot fuzzel mako swaybg \
        grim slurp wl-clipboard brightnessctl \
        ttf-dejavu font-noto

    # ---- オプション: ポータル（失敗しても続行） ----
    log_info "[6.5/7] portals (optional - may not exist)"
    for portal in xdg-desktop-portal-hyprland xdg-desktop-portal-wlr; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $portal >/dev/null 2>&1" && \
            log_ok "    $portal installed" || log_warn "    $portal skipped (ok)"
    done

    # ---- サービス + autostart ----
    log_info "[7/7] services + autostart"
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
    done
    target_rc_add dbus boot 2>/dev/null || true
    target_rc_add elogind boot 2>/dev/null || true

    install_runtime_dir_service

    setup_hyprland_autostart_v6

    # ---- 検証 ----
    log_info "final verification"
    if chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
        hv=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1' || echo "?")
        log_ok "Hyprland installed: $hv"
    else
        log_err "Hyprland binary NOT FOUND in target"
        return 1
    fi

    log_ok "Hyprland complete"
}

setup_hyprland_autostart_v6() {
    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AEOF'
# ame-deploy v0.6.3: Hyprland autostart (bulletproof)
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
    if [ -d "$RDIR" ]; then
        chmod 0700 "$RDIR" 2>/dev/null
        export XDG_RUNTIME_DIR="$RDIR"
        if command -v start-hyprland >/dev/null 2>&1; then
            start-hyprland || { echo "=== start-hyprland failed ==="; echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"; echo "Dropping to shell."; }
        elif command -v Hyprland >/dev/null 2>&1; then
            Hyprland || { echo "=== Hyprland failed ==="; echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"; echo "Dropping to shell."; }
        else
            echo "=== Hyprland binary not found ==="
        fi
    else
        echo "=== /run/user/$UID_NUM unavailable ==="
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
        return $?
    fi

    case "$profile" in
        00-minimal) log_ok "minimal"; return 0 ;;
        05-sway)
            install_pkgs_required "sway" sway || true
            install_pkgs_optional "sway-tools" swaybg waybar foot fuzzel mako seatd seatd-openrc xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl
            install_pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc pipewire pipewire-pulse wireplumber networkmanager
            for s in dbus elogind seatd polkit networkmanager; do target_rc_add "$s" default 2>/dev/null || true; done
            install_runtime_dir_service
            setup_generic_autostart "sway"
            return 0 ;;
        01-river)
            install_pkgs_required "river" river || true
            install_pkgs_optional "river-tools" waybar foot fuzzel mako swaybg xdg-desktop-portal xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl
            install_pkgs_optional "runtime" seatd seatd-openrc dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc pipewire pipewire-pulse wireplumber networkmanager
            for s in dbus elogind seatd polkit networkmanager; do target_rc_add "$s" default 2>/dev/null || true; done
            install_runtime_dir_service
            setup_generic_autostart "river"
            return 0 ;;
        02-kde)
            install_pkgs_optional "kde" plasma-desktop plasma-workspace plasma-nm plasma-pa konsole dolphin kate sddm xdg-desktop-portal-kde
            install_pkgs_optional "runtime" dbus elogind polkit pipewire pipewire-pulse wireplumber networkmanager
            for s in dbus elogind polkit networkmanager; do target_rc_add "$s" default 2>/dev/null || true; done
            install_display_manager sddm
            return 0 ;;
        03-gnome)
            install_pkgs_optional "gnome" gnome gnome-shell gnome-session gnome-terminal nautilus gnome-control-center gnome-tweaks xdg-desktop-portal-gnome
            install_pkgs_optional "runtime" dbus elogind polkit pipewire pipewire-pulse wireplumber networkmanager
            for s in dbus elogind polkit networkmanager; do target_rc_add "$s" default 2>/dev/null || true; done
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
        sddm) chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories sddm >/dev/null 2>&1'; target_rc_add sddm default 2>/dev/null || true; log_ok "sddm" ;;
        gdm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories gdm >/dev/null 2>&1' || true
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
            log_ok "gdm" ;;
        greetd) chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories greetd greetd-tuigreet >/dev/null 2>&1' || true; target_rc_add greetd default 2>/dev/null || true; log_ok "greetd" ;;
    esac
}

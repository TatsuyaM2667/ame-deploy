#!/bin/sh

# ---- 冪等チェック ----
hyprland_works() {
    chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1' || return 1
    local v
    v=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1' 2>&1)
    echo "$v" | grep -q "Error relocating" && return 1
    echo "$v" | grep -q "Hyprland" && return 0
    return 1
}

# ---- 個別 install（失敗許容） ----
install_pkgs_optional() {
    local label="$1"; shift
    log_info "  $label"
    local ok=0 skip=0
    for p in "$@"; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $p >/dev/null 2>&1" && ok=$((ok+1)) || { log_warn "    skip: $p"; skip=$((skip+1)); }
    done
    log_ok "  $label: ok=$ok skip=$skip"
}

# ---- libstdc++ ABI 修正 ----
fix_libstdcpp_abi() {
    log_info "  fixing libstdc++ ABI..."
    chroot "$TARGET" /bin/sh -c '
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        apk upgrade --available --force-missing-repositories >/dev/null 2>&1
        apk add --force-overwrite --force-missing-repositories libstdc++ libgcc gcc >/dev/null 2>&1
        apk fix hyprland hyprutils hyprlang hyprcursor >/dev/null 2>&1
    ' || true
}

# ---- Hyprland install with retry ----
install_hyprland_with_retry() {
    local max=3 i=0
    while [ $i -lt $max ]; do
        i=$((i+1))
        log_info "  [attempt $i/$max]"

        # 既に動くなら成功
        if hyprland_works; then
            log_ok "  Hyprland works"
            return 0
        fi

        # インストール / 修復
        if chroot "$TARGET" /bin/sh -c 'command -v Hyprland >/dev/null 2>&1'; then
            log_warn "  binary exists but ABI error - fixing"
            fix_libstdcpp_abi
            if hyprland_works; then
                log_ok "  Hyprland fixed"
                return 0
            fi
            log_warn "  retry full reinstall"
            chroot "$TARGET" /bin/sh -c '
                export PATH=/sbin:/usr/sbin:/bin:/usr/bin
                apk del hyprland hyprutils hyprlang hyprcursor 2>/dev/null
                apk add --no-cache --force-missing-repositories hyprland hyprutils hyprlang hyprcursor 2>&1 | tail -3
            ' || true
        else
            chroot "$TARGET" /bin/sh -c '
                export PATH=/sbin:/usr/sbin:/bin:/usr/bin
                apk add --no-cache --force-missing-repositories hyprland 2>&1 | tail -5
            ' || true
        fi
    done
    log_err "  Hyprland failed after $max attempts"
    return 1
}

# ---- Hyprland 完全インストール ----
install_hyprland_complete() {
    # 冪等チェック
    if state_done "hyprland" && hyprland_works; then
        log_info "Hyprland already working - skip"
        return 0
    fi

    log_info "=== Hyprland install v0.7 ==="
    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || \
        cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak"
    cat > "$TARGET/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
REPOEOF
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    # runtime
    install_pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc seatd seatd-openrc rtkit
    install_pkgs_optional "graphics" mesa mesa-dri-gallium mesa-vulkan-intel mesa-vulkan-ati
    install_pkgs_optional "audio" pipewire pipewire-pulse wireplumber
    install_pkgs_optional "network" networkmanager networkmanager-cli networkmanager-tui
    install_pkgs_optional "hypr-tools" \
        xdg-desktop-portal xdg-desktop-portal-gtk \
        waybar foot fuzzel mako swaybg \
        grim slurp wl-clipboard brightnessctl \
        ttf-dejavu font-noto

    # Hyprland with retry
    log_info "[5/6] Hyprland ecosystem"
    if ! install_hyprland_with_retry; then
        log_err "Hyprland install failed"
        return 1
    fi

    # optional portals
    log_info "[6/6] portals (optional)"
    for portal in xdg-desktop-portal-hyprland xdg-desktop-portal-wlr; do
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $portal >/dev/null 2>&1" && \
            log_ok "  $portal" || log_warn "  $portal skipped"
    done

    # services
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
    done
    target_rc_add dbus boot 2>/dev/null || true
    target_rc_add elogind boot 2>/dev/null || true

    install_runtime_dir_service
    setup_hyprland_autostart_v7

    # 最終検証
    if hyprland_works; then
        local v=$(chroot "$TARGET" /bin/sh -c 'Hyprland --version 2>&1 | head -1')
        log_ok "Hyprland: $v"
        state_mark "hyprland"
        return 0
    fi
    log_err "final verification failed"
    return 1
}

setup_hyprland_autostart_v7() {
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
    [ -d "$RDIR" ] || mkdir -p "$RDIR" 2>/dev/null
    if [ -d "$RDIR" ]; then
        chmod 0700 "$RDIR" 2>/dev/null
        export XDG_RUNTIME_DIR="$RDIR"
        if command -v start-hyprland >/dev/null 2>&1; then
            start-hyprland || { echo "=== failed, shell ==="; echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"; }
        elif command -v Hyprland >/dev/null 2>&1; then
            Hyprland || { echo "=== failed, shell ==="; echo "Log: cat /tmp/hypr/*/hyprland.log 2>/dev/null | tail -30"; }
        fi
    fi
fi
AEOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
    log_ok "autostart installed"
}

# ---- 他 DE ----
install_de_profile() {
    profile="$1"
    lock="${2:-auto}"
    log_info "Desktop env: $profile (lock=$lock)"

    case "$profile" in
        04-hyprland) install_hyprland_complete; return $? ;;
        00-minimal) log_ok "minimal"; state_mark "de"; return 0 ;;
    esac

    # その他は簡易
    local pkgs="" services="" cmd=""
    case "$profile" in
        05-sway) pkgs="sway swaybg waybar foot fuzzel mako seatd seatd-openrc xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl"; services="dbus elogind seatd"; cmd="sway" ;;
        01-river) pkgs="river waybar foot fuzzel mako swaybg xdg-desktop-portal xdg-desktop-portal-wlr grim slurp wl-clipboard brightnessctl"; services="dbus elogind seatd"; cmd="river" ;;
        02-kde) pkgs="plasma-desktop plasma-workspace plasma-nm plasma-pa konsole dolphin kate sddm xdg-desktop-portal-kde"; services="dbus elogind"; cmd="" ;;
        03-gnome) pkgs="gnome gnome-shell gnome-session gnome-terminal nautilus gnome-control-center gnome-tweaks xdg-desktop-portal-gnome"; services="dbus elogind"; cmd="" ;;
        *) log_err "unknown"; return 1 ;;
    esac

    install_pkgs_optional "$profile" $pkgs
    install_pkgs_optional "runtime" dbus dbus-openrc elogind elogind-openrc polkit polkit-openrc pipewire pipewire-pulse wireplumber networkmanager
    for s in $services networkmanager; do target_rc_add "$s" default 2>/dev/null || true; done
    install_runtime_dir_service
    [ -n "$cmd" ] && setup_generic_autostart "$cmd"

    case "$profile" in
        02-kde) install_display_manager sddm ;;
        03-gnome) install_display_manager gdm ;;
    esac
    state_mark "de"
    log_ok "$profile done"
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
        command -v $cmd >/dev/null 2>&1 && $cmd
    fi
fi
EOF
    chmod +x "$TARGET/etc/profile.d/ame-autostart.sh"
}

install_display_manager() {
    case "$1" in
        sddm) chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories sddm >/dev/null 2>&1'; target_rc_add sddm default 2>/dev/null || true ;;
        gdm)
            chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories gdm >/dev/null 2>&1' || true
            if [ ! -f "$TARGET/etc/init.d/gdm" ]; then
                cat > "$TARGET/etc/init.d/gdm" << 'GDMEOF'
#!/sbin/openrc-run
name="gdm"
description="GDM"
command="/usr/sbin/gdm"
command_background="yes"
pidfile="/run/gdm.pid"
depend() { need dbus elogind; after localmount; }
GDMEOF
                chmod +x "$TARGET/etc/init.d/gdm"
            fi
            target_rc_add gdm default 2>/dev/null || true ;;
    esac
}

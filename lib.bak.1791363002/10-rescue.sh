#!/bin/sh
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true

    # edge repo
    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    # kernel
    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        log_info "installing kernel"
        _mount_chroot_fs
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
        _umount_chroot_fs
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel"; return 1; }
    log_ok "kernel: $KVER"

    # initramfs
    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme"
MK
    img="initramfs-lts"
    case "$KVER" in
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac
    _mount_chroot_fs
    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then break; fi
        rm -f "$TARGET/boot/$img"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkdir -p /boot; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs
    _verify_initramfs "$TARGET/boot/$img" || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    # ESP
    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    # services
    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done

    # runtime-dir
    install_runtime_dir_service

    # home + river config 保証
    for u in $(chroot "$TARGET" /bin/sh -c "awk -F: '\\\$3 >= 1000 && \\\$3 < 60000 {print \\\$1}' /etc/passwd" 2>/dev/null); do
        mkdir -p "$TARGET/home/$u"
        chroot "$TARGET" /bin/sh -c "chown $u:$u /home/$u 2>/dev/null" || true
        river_config_for "$u"
    done

    # autostart
    if chroot "$TARGET" /bin/sh -c 'command -v river >/dev/null 2>&1'; then
        setup_autostart
    elif chroot "$TARGET" /bin/sh -c 'command -v sway >/dev/null 2>&1'; then
        setup_autostart
    fi

    log_ok "=========================================="
    log_ok " Rescue COMPLETE"
    log_ok "=========================================="
    ls -la "$ESP/EFI/BOOT/"
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

# ============ v2.0.1 override ============
rescue_installed_system() {
    log_info "=========================================="
    log_info " Full Rescue v2.0.1"
    log_info "=========================================="
    auto_mount_target || { log_err "no install found"; return 1; }
    log_ok "target: $TARGET"

    cp /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
    mkdir -p "$TARGET/home"

    [ -f "$TARGET/etc/apk/repositories.stable.bak" ] || cp "$TARGET/etc/apk/repositories" "$TARGET/etc/apk/repositories.stable.bak" 2>/dev/null || true
    cat > "$TARGET/etc/apk/repositories" << 'R1'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
R1
    chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk update --force-missing-repositories 2>&1 | tail -2'

    if [ ! -d "$TARGET/lib/modules" ] || [ -z "$(ls -A "$TARGET/lib/modules" 2>/dev/null)" ]; then
        _mount_chroot_fs
        chroot "$TARGET" /bin/sh -c 'export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories linux-lts mkinitfs linux-firmware-i915 linux-firmware-intel linux-firmware-rtw88 linux-firmware-rtw89 linux-firmware-amdgpu 2>&1 | tail -5' || true
        _umount_chroot_fs
    fi
    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    [ -n "$KVER" ] || { log_err "no kernel"; return 1; }
    log_ok "kernel: $KVER"

    mkdir -p "$TARGET/etc/mkinitfs"
    cat > "$TARGET/etc/mkinitfs/mkinitfs.conf" << 'MK'
features="ata base ide scsi usb virtio ext4 nvme"
MK
    img="initramfs-lts"
    case "$KVER" in
        *-edge) img="initramfs-edge" ;;
        *-virt) img="initramfs-virt" ;;
    esac
    _mount_chroot_fs
    i=0
    while [ $i -lt 3 ]; do
        i=$((i+1))
        if _verify_initramfs "$TARGET/boot/$img"; then break; fi
        rm -f "$TARGET/boot/$img"
        chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; mkdir -p /boot; mkinitfs -o /boot/$img $KVER 2>&1 | tail -3" || true
    done
    _umount_chroot_fs
    _verify_initramfs "$TARGET/boot/$img" || { log_err "initramfs failed"; return 1; }
    log_ok "initramfs ready"

    install_kernel_to_esp || return 1
    install_initramfs_to_esp || return 1
    install_limine "$DEPLOY_DIR/boot" || return 1
    write_limine_conf || return 1
    register_uefi
    sync

    for s in dbus elogind seatd polkit networkmanager; do
        target_rc_add "$s" default 2>/dev/null || true
        target_rc_add "$s" boot 2>/dev/null || true
    done

    install_runtime_dir_service

    # ★ home + river config 作成（ホスト側 awk）
    log_info "creating home directories from $TARGET/etc/passwd"
    mkdir -p "$TARGET/home"
    if [ -f "$TARGET/etc/passwd" ]; then
        awk -F: '$3 >= 1000 && $3 < 60000 {print $1"|"$3"|"$4"|"$6}' "$TARGET/etc/passwd" > /tmp/ame-users.txt
        while IFS='|' read -r uname uid gid home; do
            [ -z "$uname" ] && continue
            [ -z "$home" ] && home="/home/$uname"
            sub="${home#/}"
            target_home="$TARGET/$sub"

            mkdir -p "$target_home"
            chown "$uid:$gid" "$target_home" 2>/dev/null || true
            log_ok "  $uname -> $home (uid=$uid)"

            mkdir -p "$target_home/.config/river"
            cat > "$target_home/.config/river/init" << 'RC'
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
RC
            chmod +x "$target_home/.config/river/init"
            chown -R "$uid:$gid" "$target_home/.config" 2>/dev/null || true
        done < /tmp/ame-users.txt
        rm -f /tmp/ame-users.txt
    fi

    if [ -d "$TARGET/root" ]; then
        mkdir -p "$TARGET/root/.config/river"
        cat > "$TARGET/root/.config/river/init" << 'RC'
#!/bin/sh
swaybg -c "#1a1a2e" 2>/dev/null &
waybar 2>/dev/null &
riverctl map normal Super Return spawn foot
riverctl map normal Super D spawn fuzzel
riverctl map normal Super Q close
riverctl map normal Super+Shift E exit
riverctl modifier Super
RC
        chmod +x "$TARGET/root/.config/river/init"
    fi

    cat > "$TARGET/etc/profile.d/ame-autostart.sh" << 'AUTO'
# ame-deploy v2.0.1 autostart
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    if [ ! -d "$HOME" ]; then
        mkdir -p "$HOME" 2>/dev/null
        [ -d "$HOME" ] || { echo "ame-deploy: cannot create $HOME"; exit 0; }
    fi

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
            printf '%s\n' '#!/bin/sh' \
              'swaybg -c "#1a1a2e" &' \
              'waybar &' \
              'riverctl map normal Super Return spawn foot' \
              'riverctl map normal Super D spawn fuzzel' \
              'riverctl map normal Super Q close' \
              'riverctl map normal Super+Shift E exit' \
              'riverctl modifier Super' > "$HOME/.config/river/init"
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
    log_ok "autostart updated"

    log_ok "=========================================="
    log_ok " Rescue v2.0.1 COMPLETE"
    log_ok "=========================================="
    ls -la "$ESP/EFI/BOOT/"
    echo
    echo "  Home dirs:"
    ls -la "$TARGET/home/" 2>/dev/null
    echo
    echo "  sync; umount $ESP $TARGET; reboot"
    return 0
}

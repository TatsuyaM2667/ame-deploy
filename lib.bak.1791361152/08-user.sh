#!/bin/sh
create_user() {
    if state_done "user"; then log_info "user already created"; return 0; fi
    printf "  username [ame]: "; read uname
    [ -z "$uname" ] && uname="ame"
    printf "  password: "; stty -echo; read upass; stty echo; echo

    mkdir -p "$TARGET/home/$uname" "$TARGET/root"

    chroot "$TARGET" /bin/sh -c "
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        id '$uname' >/dev/null 2>&1 || adduser -D -s /bin/sh '$uname' 2>/dev/null || true
        echo '$uname:$upass' | chpasswd
        for g in wheel video audio input seat netdev plugdev; do
            addgroup '$uname' \$g 2>/dev/null || true
        done
        mkdir -p /home/$uname
        chown -R '$uname':'$uname' /home/$uname
    " || { log_err "user creation failed"; return 1; }

    mkdir -p "$TARGET/etc/sudoers.d"
    printf '%%wheel ALL=(ALL) ALL\n' > "$TARGET/etc/sudoers.d/wheel"
    chmod 0440 "$TARGET/etc/sudoers.d/wheel"

    printf "  root password: "; stty -echo; read rpass; stty echo; echo
    chroot "$TARGET" /bin/sh -c "echo 'root:$rpass' | chpasswd" || true

    uid=$(chroot "$TARGET" /bin/sh -c "id -u '$uname' 2>/dev/null" || echo 1000)
    mkdir -p "$TARGET/run/user/$uid"
    chmod 0700 "$TARGET/run/user/$uid"
    chroot "$TARGET" /bin/sh -c "chown '$uname':'$uname' /run/user/$uid 2>/dev/null" || true

    river_config_for "$uname"
    state_mark "user"
    log_ok "$uname created (uid=$uid, home+river config ready)"
}
cleanup_deploy() {
    rm -rf "$TARGET/usr/local/share/ame-deploy" 2>/dev/null || true
    rm -f "$TARGET/etc/profile.d/ame-deploy.sh" 2>/dev/null || true
}

#!/bin/sh
create_user() {
    if state_done "user"; then
        log_info "user already created - skip"
        return 0
    fi
    log_info "user creation"
    if [ "$AUTOMODE" = "1" ]; then
        uname="ame"; upass="ame"; rpass="ame"
        log_info "  [auto] user=ame pass=ame"
    else
        printf "  username [ame]: "; read uname
        [ -z "$uname" ] && uname="ame"
        printf "  password: "; stty -echo; read upass; stty echo; echo
    fi

    chroot "$TARGET" /bin/sh -c "
        export PATH=/sbin:/usr/sbin:/bin:/usr/bin
        adduser -D -s /bin/sh $uname 2>/dev/null || true
        echo '$uname:$upass' | chpasswd
        for g in wheel video audio input seat netdev plugdev; do
            addgroup $uname \$g 2>/dev/null || true
        done
    " || { log_err "user creation failed"; return 1; }

    mkdir -p "$TARGET/etc/sudoers.d"
    cat > "$TARGET/etc/sudoers.d/wheel" << 'SEOF'
%wheel ALL=(ALL) ALL
SEOF
    chmod 0440 "$TARGET/etc/sudoers.d/wheel"

    if [ "$AUTOMODE" != "1" ]; then
        printf "  root password: "; stty -echo; read rpass; stty echo; echo
    fi
    chroot "$TARGET" /bin/sh -c "echo 'root:$rpass' | chpasswd" || true

    uid=$(chroot "$TARGET" /bin/sh -c "id -u $uname 2>/dev/null" || echo 1000)
    mkdir -p "$TARGET/run/user/$uid"
    chmod 0700 "$TARGET/run/user/$uid"
    chroot "$TARGET" /bin/sh -c "chown $uname:$uname /run/user/$uid 2>/dev/null" || true

    state_mark "user"
    log_ok "$uname created (uid=$uid)"
}
cleanup_deploy() {
    rm -rf "$TARGET/usr/local/share/ame-deploy" 2>/dev/null || true
    rm -f  "$TARGET/etc/profile.d/ame-deploy.sh" 2>/dev/null || true
}

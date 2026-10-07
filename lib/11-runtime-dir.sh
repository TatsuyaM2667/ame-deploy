#!/bin/sh
install_runtime_dir_service() {
    log_info "installing ame-runtime-dir service"
    mkdir -p "$TARGET/etc/init.d"

    cat > "$TARGET/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user/<uid> directories at boot"
depend() { after elogind; need localmount; before display-manager; }
start() {
    ebegin "Creating /run/user directories"
    mkdir -p /run/user
    chmod 0755 /run/user
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | while read -r uid; do
        [ -z "$uid" ] && continue
        mkdir -p "/run/user/$uid"
        chmod 0700 "/run/user/$uid"
        chown "$uid:$uid" "/run/user/$uid" 2>/dev/null || true
    done
    eend 0
}
stop() {
    ebegin "Removing /run/user directories"
    rm -rf /run/user/* 2>/dev/null || true
    eend 0
}
SVC
    chmod +x "$TARGET/etc/init.d/ame-runtime-dir"

    for level in boot default; do
        mkdir -p "$TARGET/etc/runlevels/$level"
        ln -sf /etc/init.d/ame-runtime-dir "$TARGET/etc/runlevels/$level/ame-runtime-dir" 2>/dev/null || true
    done

    log_ok "ame-runtime-dir service installed"
}

#!/bin/sh
install_runtime_dir_service() {
    if state_done "runtime-dir"; then
        log_info "runtime-dir service already installed"
        return 0
    fi
    mkdir -p "$TARGET/etc/init.d"
    cat > "$TARGET/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user/<uid>"
depend() { after elogind; need localmount; before display-manager; }
start() {
    ebegin "Creating /run/user"
    mkdir -p /run/user; chmod 0755 /run/user
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | while read -r uid; do
        mkdir -p "/run/user/$uid"; chmod 0700 "/run/user/$uid"; chown "$uid:$uid" "/run/user/$uid" 2>/dev/null || true
    done
    eend 0
}
stop() { rm -rf /run/user/* 2>/dev/null || true; }
SVC
    chmod +x "$TARGET/etc/init.d/ame-runtime-dir"
    for lvl in boot default; do
        mkdir -p "$TARGET/etc/runlevels/$lvl"
        ln -sf /etc/init.d/ame-runtime-dir "$TARGET/etc/runlevels/$lvl/ame-runtime-dir" 2>/dev/null || true
    done
    state_mark "runtime-dir"
    log_ok "runtime-dir service installed"
}

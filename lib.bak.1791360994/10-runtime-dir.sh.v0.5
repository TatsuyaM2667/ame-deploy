#!/bin/sh
# /run/user/$UID を boot 時に確実に作成する OpenRC サービス

install_runtime_dir_service() {
    log_info "installing ame-runtime-dir service"

    mkdir -p "$TARGET/etc/init.d"

    cat > "$TARGET/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user/<uid> directories at boot"

depend() {
    after elogind
    need localmount
    before display-manager
}

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

    # 全ランレベルに登録（boot でも default でも起動）
    for level in boot default; do
        mkdir -p "$TARGET/etc/runlevels/$level"
        ln -sf /etc/init.d/ame-runtime-dir "$TARGET/etc/runlevels/$level/ame-runtime-dir" 2>/dev/null || true
    done

    log_ok "ame-runtime-dir service installed"
}

# 既存環境の救出（rescue 用）
rescue_runtime_dir_service() {
    ROOT="$1"
    [ -d "$ROOT/etc" ] || { log_err "invalid root: $ROOT"; return 1; }

    log_info "rescuing runtime-dir service in $ROOT"

    mkdir -p "$ROOT/etc/init.d"
    cat > "$ROOT/etc/init.d/ame-runtime-dir" << 'SVC'
#!/sbin/openrc-run
name="ame-runtime-dir"
description="Create /run/user/<uid> directories at boot"
depend() { after elogind; need localmount; before display-manager; }
start() {
    ebegin "Creating /run/user directories"
    mkdir -p /run/user; chmod 0755 /run/user
    awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | while read -r uid; do
        [ -z "$uid" ] && continue
        mkdir -p "/run/user/$uid"; chmod 0700 "/run/user/$uid"; chown "$uid:$uid" "/run/user/$uid" 2>/dev/null || true
    done
    eend 0
}
stop() { rm -rf /run/user/* 2>/dev/null || true; }
SVC
    chmod +x "$ROOT/etc/init.d/ame-runtime-dir"
    for level in boot default; do
        mkdir -p "$ROOT/etc/runlevels/$level"
        ln -sf /etc/init.d/ame-runtime-dir "$ROOT/etc/runlevels/$level/ame-runtime-dir" 2>/dev/null || true
    done

    log_ok "runtime-dir service rescued"
}

#!/bin/sh
# ame-deploy v0.4 - 共通ユーティリティ

# --- グローバル変数 ---
DEPLOY_VER="0.4"
: "${TARGET:=}"
: "${ESP:=}"
: "${DEV:=}"
: "${P1:=}"
: "${P2:=}"

# --- ログ ---
log_info() { printf "[INFO] %s\n" "$*"; }
log_ok()   { printf "[ OK ] %s\n" "$*"; }
log_warn() { printf "[WARN] %s\n" "$*" >&2; }
log_err()  { printf "[ERR ] %s\n" "$*" >&2; }
die()      { log_err "$*"; exit 1; }

# --- 共通ヘルパ ---
pause() {
    printf "\n  Enter > "
    read -r _
}

require_root() {
    [ "$(id -u)" = "0" ] || die "must run as root"
}

require_disk() {
    [ -n "$DEV" ] || die "disk not selected. Run [2] first"
    [ -b "$DEV" ] || die "$DEV not a block device"
    mountpoint -q "$TARGET" 2>/dev/null || die "$TARGET not mounted"
    mountpoint -q "$ESP" 2>/dev/null    || die "$ESP not mounted"
}

require_file() {
    [ -f "$1" ] || die "missing file: $1"
}

# 安全な /run/user/$UID 取得（3段フォールバック）
safe_runtime_dir() {
    uid="${1:-$(id -u)}"
    for d in "/run/user/$uid" "/tmp/xdg-$uid"; do
        if mkdir -p "$d" 2>/dev/null; then
            chmod 0700 "$d" 2>/dev/null || true
            echo "$d"
            return 0
        fi
    done
    echo "/tmp"
}

# サービスを確実に起動（timeout付き）
start_service() {
    svc="$1"
    if ! rc-service "$svc" status >/dev/null 2>&1; then
        rc-service "$svc" start >/dev/null 2>&1 || true
    fi
    sleep 0.5
    rc-service "$svc" status >/dev/null 2>&1
}

# target 内でサービス有効化
target_rc_add() {
    svc="$1"
    level="${2:-default}"
    chroot "$TARGET" /bin/sh -c "rc-update add $svc $level 2>/dev/null" || true
}

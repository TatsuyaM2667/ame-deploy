#!/bin/sh
DEPLOY_VER="0.7"
: "${TARGET:=}"
: "${ESP:=}"
: "${DEV:=}"
: "${P1:=}"
: "${P2:=}"

log_info() { printf "[INFO] %s\n" "$*"; }
log_ok()   { printf "[ OK ] %s\n" "$*"; }
log_warn() { printf "[WARN] %s\n" "$*" >&2; }
log_err()  { printf "[ERR ] %s\n" "$*" >&2; }
die()      { log_err "$*"; exit 1; }

pause() { printf "\n  Enter > "; read -r _; }
require_root() { [ "$(id -u)" = "0" ] || die "must run as root"; }

require_disk() {
    [ -n "$DEV" ] || die "disk not selected. Run [2] first"
    [ -b "$DEV" ] || die "$DEV not a block device"
    mountpoint -q "$TARGET" 2>/dev/null || die "$TARGET not mounted"
    mountpoint -q "$ESP" 2>/dev/null    || die "$ESP not mounted"
}

require_file() { [ -f "$1" ] || die "missing file: $1"; }

# ---- state 管理（target 側に保存 → 再起動後も保持） ----
STATE_DIR=""   # install 中に $TARGET/var/lib/ame-deploy/state を指す

state_init() {
    [ -n "$TARGET" ] || return 1
    STATE_DIR="$TARGET/var/lib/ame-deploy/state"
    mkdir -p "$STATE_DIR"
}

state_mark() {
    [ -n "$STATE_DIR" ] || state_init || return 1
    touch "$STATE_DIR/$1"
}

state_done() {
    [ -n "$STATE_DIR" ] || state_init || return 1
    [ -f "$STATE_DIR/$1" ]
}

state_clear() {
    [ -n "$STATE_DIR" ] || return 0
    rm -rf "$STATE_DIR"
}

state_list() {
    [ -n "$STATE_DIR" ] || return 0
    if [ -d "$STATE_DIR" ]; then
        for f in "$STATE_DIR"/*; do
            [ -f "$f" ] && echo "  * $(basename $f)"
        done
    fi
}

# target 内でサービス有効化
target_rc_add() {
    svc="$1"
    level="${2:-default}"
    chroot "$TARGET" /bin/sh -c "rc-update add $svc $level 2>/dev/null" || true
}

# target 内で apk add（失敗時 tail 出力）
target_apk_add() {
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; apk add --no-cache --force-missing-repositories $* 2>&1" | tail -5
}

# ---- chroot 前のマウントヘルパ ----
_mount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/dev/pts" "$TARGET/dev/shm"
    mountpoint -q "$TARGET/proc" || mount -t proc     none "$TARGET/proc" 2>/dev/null || true
    mountpoint -q "$TARGET/sys"  || mount -t sysfs    none "$TARGET/sys"  2>/dev/null || true
    mountpoint -q "$TARGET/dev"  || mount -t devtmpfs none "$TARGET/dev"  2>/dev/null || true
    mountpoint -q "$TARGET/dev/pts" || mount -t devpts none "$TARGET/dev/pts" 2>/dev/null || true
}

_umount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    umount "$TARGET/dev/pts" 2>/dev/null || true
    umount "$TARGET/dev/shm" 2>/dev/null || true
    umount "$TARGET/dev"     2>/dev/null || true
    umount "$TARGET/sys"     2>/dev/null || true
    umount "$TARGET/proc"    2>/dev/null || true
}

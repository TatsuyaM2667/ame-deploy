#!/bin/sh
DEPLOY_VER="1.0"
: "${TARGET:=}"; : "${ESP:=}"; : "${DEV:=}"; : "${P1:=}"; : "${P2:=}"
: "${AUTOMODE:=0}"

log_info() { printf "[INFO] %s\n" "$*"; }
log_ok()   { printf "[ OK ] %s\n" "$*"; }
log_warn() { printf "[WARN] %s\n" "$*" >&2; }
log_err()  { printf "[ERR ] %s\n" "$*" >&2; }
die()      { log_err "$*"; exit 1; }
pause()    { printf "\n  Enter > "; read -r _; }
require_root() { [ "$(id -u)" = "0" ] || die "must run as root"; }

require_disk() {
    [ -n "$DEV" ] || die "disk not selected"
    [ -b "$DEV" ] || die "$DEV not a block device"
    mountpoint -q "$TARGET" 2>/dev/null || die "$TARGET not mounted"
    mountpoint -q "$ESP" 2>/dev/null    || die "$ESP not mounted"
}
require_file() { [ -f "$1" ] || die "missing: $1"; }

# ---- state ----
STATE_DIR=""
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
state_clear() { [ -n "$STATE_DIR" ] && rm -rf "$STATE_DIR"; }
state_list() {
    [ -d "$STATE_DIR" ] && for f in "$STATE_DIR"/*; do
        [ -f "$f" ] && echo "  * $(basename $f)"
    done
}

# ---- chroot マウントヘルパ ----
_mount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/dev/pts" "$TARGET/dev/shm"
    mountpoint -q "$TARGET/proc"    || mount -t proc     none "$TARGET/proc"    2>/dev/null || true
    mountpoint -q "$TARGET/sys"     || mount -t sysfs    none "$TARGET/sys"     2>/dev/null || true
    mountpoint -q "$TARGET/dev"     || mount -t devtmpfs none "$TARGET/dev"     2>/dev/null || true
    mountpoint -q "$TARGET/dev/pts" || mount -t devpts   none "$TARGET/dev/pts" 2>/dev/null || true
}
_umount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    for m in dev/pts dev/shm dev sys proc; do
        umount "$TARGET/$m" 2>/dev/null || true
    done
}

# ---- chroot apk（マウント保証付き） ----
_chroot_apk() {
    _mount_chroot_fs
    chroot "$TARGET" /bin/sh -c "export PATH=/sbin:/usr/sbin:/bin:/usr/bin; $*"
    rc=$?
    return $rc
}
target_rc_add() {
    chroot "$TARGET" /bin/sh -c "rc-update add $1 ${2:-default} 2>/dev/null" || true
}

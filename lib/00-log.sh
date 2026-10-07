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

# ---- 内蔵ディスク自動検出 + マウント ----
auto_mount_target() {
    if mountpoint -q /mnt/ame-target 2>/dev/null; then
        TARGET=/mnt/ame-target; ESP=/mnt/ame-esp
        for d in sda nvme0n1 vda; do
            if [ -b "/dev/${d}2" ]; then
                DEV="/dev/$d"; P1="/dev/${d}1"; P2="/dev/${d}2"; break
            fi
            if [ -b "/dev/${d}p2" ]; then
                DEV="/dev/$d"; P1="/dev/${d}p1"; P2="/dev/${d}p2"; break
            fi
        done
        state_init; return 0
    fi

    mkdir -p /mnt/ame-target /mnt/ame-esp
    for d in sda nvme0n1 vda; do
        if [ -b "/dev/${d}2" ]; then
            P2="/dev/${d}2"; P1="/dev/${d}1"; DEV="/dev/$d"
        elif [ -b "/dev/${d}p2" ]; then
            P2="/dev/${d}p2"; P1="/dev/${d}p1"; DEV="/dev/$d"
        else
            continue
        fi
        if mount "$P2" /mnt/ame-target 2>/dev/null; then
            mount "$P1" /mnt/ame-esp 2>/dev/null || true
            TARGET=/mnt/ame-target; ESP=/mnt/ame-esp
            state_init
            log_ok "auto-mounted: $P2 -> $TARGET"
            return 0
        fi
    done
    return 1
}

# ============================================================
# 共通ヘルパ（v1.0.1 で追加）
# ============================================================

# chroot 内 /proc /sys /dev をマウント
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

# initramfs 検証（サイズ + /init 存在）
_verify_initramfs() {
    local f="$1"
    [ -f "$f" ] || return 1
    local sz
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$sz" -gt 500000 ] || return 1   # 500KB 以上

    local tmp=/tmp/ame-irv-$$
    rm -rf "$tmp"; mkdir -p "$tmp"
    ( cd "$tmp" && zcat "$f" 2>/dev/null | cpio -idm --quiet 2>/dev/null )
    local rc=1
    [ -e "$tmp/init" ] && rc=0
    rm -rf "$tmp"
    return $rc
}

# 内蔵ディスク自動マウント
auto_mount_target() {
    if mountpoint -q /mnt/ame-target 2>/dev/null; then
        TARGET=/mnt/ame-target; ESP=/mnt/ame-esp
        for d in sda nvme0n1 vda; do
            if [ -b "/dev/${d}2" ]; then DEV="/dev/$d"; P1="/dev/${d}1"; P2="/dev/${d}2"; break; fi
            if [ -b "/dev/${d}p2" ]; then DEV="/dev/$d"; P1="/dev/${d}p1"; P2="/dev/${d}p2"; break; fi
        done
        state_init; return 0
    fi

    mkdir -p /mnt/ame-target /mnt/ame-esp
    for d in sda nvme0n1 vda; do
        if [ -b "/dev/${d}2" ]; then
            P2="/dev/${d}2"; P1="/dev/${d}1"; DEV="/dev/$d"
        elif [ -b "/dev/${d}p2" ]; then
            P2="/dev/${d}p2"; P1="/dev/${d}p1"; DEV="/dev/$d"
        else
            continue
        fi
        if mount "$P2" /mnt/ame-target 2>/dev/null; then
            mount "$P1" /mnt/ame-esp 2>/dev/null || true
            TARGET=/mnt/ame-target; ESP=/mnt/ame-esp
            state_init
            log_ok "auto-mounted: $P2 -> $TARGET"
            return 0
        fi
    done
    return 1
}

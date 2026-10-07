#!/bin/sh
# ame-deploy v2.0: log + state + helpers

DEPLOY_VER="2.0"
: "${TARGET:=}"; : "${ESP:=}"; : "${DEV:=}"; : "${P1:=}"; : "${P2:=}"

log_info() { printf "[INFO] %s\n" "$*"; }
log_ok()   { printf "[ OK ] %s\n" "$*"; }
log_warn() { printf "[WARN] %s\n" "$*" >&2; }
log_err()  { printf "[ERR ] %s\n" "$*" >&2; }
die()      { log_err "$*"; exit 1; }
pause()    { printf "\n  Enter > "; read -r _; }
require_root() { [ "$(id -u)" = "0" ] || die "must be root"; }

require_disk() {
    [ -n "$DEV" ] || die "no disk selected"
    [ -b "$DEV" ] || die "$DEV not a block device"
    mountpoint -q "$TARGET" 2>/dev/null || die "$TARGET not mounted"
    mountpoint -q "$ESP" 2>/dev/null || die "$ESP not mounted"
}

require_file() { [ -f "$1" ] || die "missing: $1"; }

# --- state ---
state_init() {
    [ -n "$TARGET" ] || return 1
    STATE_DIR="$TARGET/var/lib/ame-deploy/state"
    mkdir -p "$STATE_DIR" 2>/dev/null
}
state_mark() { [ -n "$STATE_DIR" ] || state_init; touch "$STATE_DIR/$1" 2>/dev/null; }
state_done() { [ -n "$STATE_DIR" ] || state_init; [ -f "$STATE_DIR/$1" ]; }
state_clear(){ [ -n "$STATE_DIR" ] || return 0; rm -rf "$STATE_DIR" 2>/dev/null; }
state_list() {
    [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ] || return 0
    for f in "$STATE_DIR"/*; do [ -f "$f" ] && printf "  * %s\n" "$(basename "$f")"; done
}

# --- chroot mount helpers ---
_mount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/dev/pts" "$TARGET/dev/shm"
    mountpoint -q "$TARGET/proc" || mount -t proc none "$TARGET/proc" 2>/dev/null || true
    mountpoint -q "$TARGET/sys"  || mount -t sysfs none "$TARGET/sys" 2>/dev/null || true
    mountpoint -q "$TARGET/dev"  || mount -t devtmpfs none "$TARGET/dev" 2>/dev/null || true
    mountpoint -q "$TARGET/dev/pts" || mount -t devpts none "$TARGET/dev/pts" 2>/dev/null || true
}

_umount_chroot_fs() {
    [ -n "$TARGET" ] || return 0
    umount "$TARGET/dev/pts" 2>/dev/null || true
    umount "$TARGET/dev" 2>/dev/null || true
    umount "$TARGET/sys" 2>/dev/null || true
    umount "$TARGET/proc" 2>/dev/null || true
}

# --- initramfs verify ---
_verify_initramfs() {
    f="$1"
    [ -f "$f" ] || return 1
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$sz" -gt 500000 ] || return 1
    tmp="/tmp/irv-$$"
    rm -rf "$tmp"; mkdir -p "$tmp"
    ( cd "$tmp" && zcat "$f" 2>/dev/null | cpio -idm --quiet 2>/dev/null )
    rc=1
    [ -e "$tmp/init" ] && rc=0
    rm -rf "$tmp"
    return $rc
}

# --- auto mount target ---
auto_mount_target() {
    if mountpoint -q /mnt/ame-target 2>/dev/null; then
        TARGET=/mnt/ame-target; ESP=/mnt/ame-esp
        for d in sda nvme0n1 vda; do
            [ -b "/dev/${d}2" ]  && { DEV="/dev/$d"; P1="/dev/${d}1";  P2="/dev/${d}2";  break; }
            [ -b "/dev/${d}p2" ] && { DEV="/dev/$d"; P1="/dev/${d}p1"; P2="/dev/${d}p2"; break; }
        done
        state_init; return 0
    fi
    mkdir -p /mnt/ame-target /mnt/ame-esp
    for d in sda nvme0n1 vda; do
        if [ -b "/dev/${d}2" ]; then P2="/dev/${d}2"; P1="/dev/${d}1"; DEV="/dev/$d"
        elif [ -b "/dev/${d}p2" ]; then P2="/dev/${d}p2"; P1="/dev/${d}p1"; DEV="/dev/$d"
        else continue; fi
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

target_rc_add() {
    svc="$1"; level="${2:-default}"
    chroot "$TARGET" /bin/sh -c "rc-update add $svc $level 2>/dev/null" || true
}

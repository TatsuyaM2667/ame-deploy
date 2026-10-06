#!/bin/sh
select_disk() {
    echo
    echo "=== Select install target disk ==="
    lsblk -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -vE 'loop|zram|sr0|NAME'
    echo
    printf "  Enter device name (ex: sda, nvme0n1, vda) > "
    read DISK_NAME
    DEV="/dev/$DISK_NAME"
    [ -b "$DEV" ] || { log_err "$DEV not found"; return 1; }

    rota=$(lsblk -d -o ROTA "$DEV" 2>/dev/null | tail -1)
    if [ "$rota" = "0" ]; then
        echo
        echo "  !!! WARNING: internal disk ($DEV) !!!"
        printf "  Type 'INSTALL' to continue > "; read c
        [ "$c" = "INSTALL" ] || { log_warn "aborted"; return 1; }
    fi
    echo
    echo "  === Current partitions ==="
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTUUID "$DEV" 2>/dev/null
    echo
    printf "  %s will be WIPED. Type 'yes' > " "$DEV"
    read c
    [ "$c" = "yes" ] || { log_warn "aborted"; return 1; }
    return 0
}

umount_disk() {
    log_info "force unmounting $DEV..."
    # /proc/mounts から $DEV 由来のマウントを全部解除
    grep "^$DEV" /proc/mounts 2>/dev/null | awk '{print $2}' | while read -r m; do
        umount -f "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
    done
    for p in $(lsblk -n -o NAME "$DEV" 2>/dev/null | tail -n +2); do
        umount -f "/dev/$p" 2>/dev/null || umount -l "/dev/$p" 2>/dev/null || true
        swapoff "/dev/$p" 2>/dev/null || true
    done
    sleep 1
}

partition_disk() {
    log_info "cleaning metadata..."
    vgchange -an 2>/dev/null || true
    dmsetup remove_all 2>/dev/null || true
    for p in $(lsblk -n -o NAME "$DEV" 2>/dev/null | tail -n +2); do
        wipefs -a "/dev/$p" 2>/dev/null || true
    done
    wipefs -a "$DEV" 2>/dev/null || true
    dd if=/dev/zero of="$DEV" bs=1M count=10 status=none 2>/dev/null || true

    sgdisk -Z "$DEV" 2>/dev/null || sgdisk --zap-all "$DEV" 2>/dev/null || true
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:ESP "$DEV" || return 1
    sgdisk -n 2:0:0     -t 2:8300 -c 2:AME "$DEV" || return 1
    sync; sleep 2
    partprobe "$DEV" 2>/dev/null || true
    blockdev --rereadpt "$DEV" 2>/dev/null || true
    sleep 2

    if echo "$DISK_NAME" | grep -q nvme; then
        P1="${DEV}p1"; P2="${DEV}p2"
    else
        P1="${DEV}1"; P2="${DEV}2"
    fi
    log_ok "ESP=$P1 root=$P2"
}

format_partitions() {
    # 強制 umount してからフォーマット
    log_info "pre-format unmount..."
    for p in "$P1" "$P2"; do
        umount -f "$p" 2>/dev/null || umount -l "$p" 2>/dev/null || true
    done
    sleep 1

    if ! mkfs.fat -F32 "$P1"; then
        log_err "mkfs.fat failed on $P1"
        return 1
    fi
    if ! mkfs.ext4 -F "$P2"; then
        log_err "mkfs.ext4 failed on $P2"
        return 1
    fi
    log_ok "formatted"
}

mount_target() {
    TARGET=/mnt/ame-target
    ESP=/mnt/ame-esp
    mkdir -p "$TARGET" "$ESP"
    mount "$P2" "$TARGET" || return 1
    mount "$P1" "$ESP"    || return 1
    log_ok "mounted $TARGET $ESP"
}

#!/bin/sh
verify_target() {
    echo "=== Verification ==="
    ok=0; bad=0
    check() {
        if chroot "$TARGET" /bin/sh -c "test -e $1" 2>/dev/null; then
            echo "  [OK]  $1"; ok=$((ok+1))
        else
            echo "  [NG]  $1"; bad=$((bad+1))
        fi
    }
    check /bin/sh
    check /sbin/init
    check /etc/passwd
    check /etc/fstab
    check /etc/hostname
    check /etc/elogind/logind.conf

    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    if [ -n "$KVER" ]; then
        echo "  [OK]  /lib/modules/$KVER"; ok=$((ok+1))
        # 必須モジュール
        if find "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" -name '*.ko*' 2>/dev/null | head -1 | grep -q .; then
            echo "  [OK]  wireless modules"; ok=$((ok+1))
        else
            echo "  [NG]  wireless modules MISSING"; bad=$((bad+1))
        fi
    else
        echo "  [NG]  /lib/modules"; bad=$((bad+1))
    fi

    echo "  OK=$ok NG=$bad"
    echo "=== ESP ==="
    ls -la "$ESP/EFI/BOOT/" 2>/dev/null
    for f in BOOTX64.EFI vmlinuz-ame limine.conf initramfs.cpio.gz; do
        [ -f "$ESP/EFI/BOOT/$f" ] && echo "  [OK]  $f" || echo "  [NG]  $f"
    done
    echo "=== State ==="
    state_list
    return 0
}

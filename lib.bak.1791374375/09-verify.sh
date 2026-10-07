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
    check /etc/modules
    check /etc/modprobe.d/ame-i915.conf

    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    if [ -n "$KVER" ]; then
        echo "  [OK]  /lib/modules/$KVER"; ok=$((ok+1))
        [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" ] && echo "  [OK]  wireless mods" || { echo "  [NG]  wireless mods"; bad=$((bad+1)); }
        [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/gpu/drm/i915" ] && echo "  [OK]  i915 mods" || { echo "  [NG]  i915 mods"; bad=$((bad+1)); }
    else
        echo "  [NG]  /lib/modules"; bad=$((bad+1))
    fi

    # firmware 検証
    [ -d "$TARGET/lib/firmware/i915" ] && ls "$TARGET/lib/firmware/i915/"*guc*.bin >/dev/null 2>&1 && echo "  [OK]  i915 GuC fw" || { echo "  [NG]  i915 GuC fw"; bad=$((bad+1)); }
    [ -d "$TARGET/lib/firmware/rtw88" ] && ls "$TARGET/lib/firmware/rtw88/"*.bin >/dev/null 2>&1 && echo "  [OK]  rtw88 fw" || { echo "  [NG]  rtw88 fw"; bad=$((bad+1)); }

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

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
    check /etc/environment.d/10-wlroots.conf

    KVER=$(ls "$TARGET/lib/modules" 2>/dev/null | head -1)
    if [ -n "$KVER" ]; then
        echo "  [OK]  /lib/modules/$KVER"; ok=$((ok+1))
        [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/net/wireless" ] && { echo "  [OK]  wireless mods"; ok=$((ok+1)); } || { echo "  [NG]  wireless"; bad=$((bad+1)); }
        [ -d "$TARGET/lib/modules/$KVER/kernel/drivers/gpu/drm/i915" ] && { echo "  [OK]  i915 mods"; ok=$((ok+1)); } || { echo "  [NG]  i915"; bad=$((bad+1)); }
    fi

    ls "$TARGET/lib/firmware/i915/"* 2>/dev/null | grep -qiE 'guc|huc' && { echo "  [OK]  i915 firmware"; ok=$((ok+1)); } || { echo "  [NG]  i915 firmware"; bad=$((bad+1)); }
    ls "$TARGET/lib/firmware/rtw88/"* 2>/dev/null | grep -q . && { echo "  [OK]  rtw88 firmware"; ok=$((ok+1)); } || { echo "  [NG]  rtw88 firmware"; bad=$((bad+1)); }
    ls "$TARGET/lib/firmware/rtw89/"* 2>/dev/null | grep -q . && { echo "  [OK]  rtw89 firmware"; ok=$((ok+1)); } || true

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

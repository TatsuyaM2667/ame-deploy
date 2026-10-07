#!/bin/sh
verify_target() {
    echo
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
    check /etc/inittab
    check /etc/elogind/logind.conf

    echo "  OK=$ok NG=$bad"
    echo
    echo "=== ESP files ==="
    ls -la "$ESP/EFI/BOOT/" 2>/dev/null
    echo
    echo "=== Boot chain ==="
    for f in BOOTX64.EFI vmlinuz-ame limine.conf; do
        if [ -f "$ESP/EFI/BOOT/$f" ]; then
            echo "  [OK]  $f"
        else
            echo "  [NG]  $f"
        fi
    done
    return 0
}

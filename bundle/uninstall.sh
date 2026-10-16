#!/bin/bash
# =============================================================================
# csp-linux-bundle — rollback of the pen pressure fix
#   ./uninstall.sh                 # remove the fix (the CSP prefix is kept)
#   ./uninstall.sh --gpu           # additionally remove the DXVK/VKD3D overrides + dxvk.conf
#   ./uninstall.sh --purge-prefix  # additionally delete the complete Wine prefix
# =============================================================================
set -uo pipefail
PREFIX="${WINEPREFIX:-$HOME/.wine-csp}"
PURGE=0
REMOVE_GPU=0
for a in "$@"; do
    [ "$a" = "--purge-prefix" ] && PURGE=1
    [ "$a" = "--gpu" ] && REMOVE_GPU=1
done

if pgrep -f 'CLIPStudio[P]aint' >/dev/null 2>&1; then
    echo "ERROR: CSP is still running — please close it (the DLL is locked)." >&2
    exit 1
fi

PAINTDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT"

echo "Removing the pen pressure fix from: $PAINTDIR"
for f in wintab32.dll XWinTabHelper.dll.so t5w.exe XWinTabDeviceName.txt; do
    [ -e "$PAINTDIR/$f" ] && rm -f "$PAINTDIR/$f" && echo "  removed: $f"
done

if WINEPREFIX="$PREFIX" wine reg delete 'HKCU\Software\Wine\DllOverrides' /v wintab32 /f >/dev/null 2>&1; then
    echo "  Wine override 'wintab32' removed (wine uses its built-in wintab32 again)"
fi

# GPU path (only with --gpu): take back the DXVK/VKD3D overrides + configuration.
# The replaced DLLs themselves stay — after removing the overrides Wine takes its
# builtins again. If you also want the DLLs gone, delete them in the prefix
# (drive_c/windows/system32 + syswow64): dxgi/d3d9/d3d10core/
# d3d11/d3d12/d3d12core, or start over with --purge-prefix.
if [ "$REMOVE_GPU" = 1 ]; then
    echo "Removing the GPU path (DXVK/VKD3D) …"
    for v in '*dxgi' '*d3d9' '*d3d10core' '*d3d11' '*d3d12' '*d3d12core' '*d3d8'; do
        if WINEPREFIX="$PREFIX" wine reg delete 'HKCU\Software\Wine\DllOverrides' /v "$v" /f >/dev/null 2>&1; then
            echo "  override removed: $v"
        fi
    done
    [ -f "$PREFIX/dxvk.conf" ] && rm -f "$PREFIX/dxvk.conf" && echo "  removed: dxvk.conf"
    [ -f "$PREFIX/winetricks.log" ] && sed -i '/^dxvk$/d;/^vkd3d$/d' "$PREFIX/winetricks.log" && echo "  winetricks.log cleaned (dxvk/vkd3d)"
    echo "  Note: the native DLLs are still in the prefix — remove them with: ./uninstall.sh --purge-prefix"
fi

# Menu entries of the bundle (+ launcher copy and extracted icons)
DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"
APPDIR="$DATADIR/applications/wine/Programs"
mine() { grep -qF "WINEPREFIX=$PREFIX\"" "$1" 2>/dev/null || grep -qF -- "--prefix \"$PREFIX\"" "$1" 2>/dev/null; }
for d in "CLIP STUDIO.desktop" "CLIP STUDIO PAINT.desktop"; do
    if [ -f "$APPDIR/$d" ] && mine "$APPDIR/$d"; then
        rm -f "$APPDIR/$d" && echo "  menu entry removed: $d"
    fi
done
# Entries created by Wine that install.sh redirected to run-csp.sh: restore the original Exec
for f in "$APPDIR/CLIP STUDIO"/*.desktop; do
    [ -f "$f" ] || continue
    grep -q '^X-CSP-Linux-OrigExec=' "$f" && mine "$f" || continue
    ORIG="$(sed -n 's/^X-CSP-Linux-OrigExec=//p' "$f" | head -1)" \
    ORIGICON="$(sed -n 's/^X-CSP-Linux-OrigIcon=//p' "$f" | head -1)" awk '
        /^X-CSP-Linux-Orig(Exec|Icon)=/ { next }
        /^Exec=/ { print "Exec=" ENVIRON["ORIG"]; next }
        /^Icon=/ { if (ENVIRON["ORIGICON"] != "") { print "Icon=" ENVIRON["ORIGICON"]; next } }
        { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" && echo "  Wine entry restored: ${f#$APPDIR/}"
done
for n in csp-linux-clipstudiopaint csp-linux-clipstudio; do
    for i in "$DATADIR"/icons/hicolor/*/apps/$n.png; do
        [ -f "$i" ] && rm -f "$i"
    done
done
LAUNCH_DIR="$PREFIX/csp-launcher"
if [ -d "$LAUNCH_DIR" ]; then
    rm -f "$LAUNCH_DIR/run-csp.sh" "$LAUNCH_DIR/files/xdlg.c"
    rmdir "$LAUNCH_DIR/files" "$LAUNCH_DIR" 2>/dev/null && echo "  launcher copy removed: $LAUNCH_DIR"
fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --quiet >/dev/null 2>&1 || true

if [ "$PURGE" = 1 ]; then
    echo "Deleting the complete prefix: $PREFIX"
    rm -rf "$PREFIX"
    echo "  done."
else
    echo
    echo "CSP stays installed — it then runs with Wine's built-in wintab32 again"
    echo "(i.e. no pen pressure / sporadic ghost strokes, as before)."
fi
echo "Done."


#!/bin/bash
# =============================================================================
# install-xwintab.sh — installs the patched wintab32.dll (CSP-compatible)
# into the CSP app directory and sets the Wine DllOverride.
#
# Additionally the device name for WTInfo(WTI_DEVICES, DVC_NAME) is determined and
# placed as a sidecar file next to the DLL (XWinTabDeviceName.txt). Order:
#   $XWINTAB_DEVICE_NAME  >  name detection via diag/xi2-devname  >  nothing
# Without the file the DLL reports the previous placeholder.
# Details: CSP-TABLET-FIX.md
# =============================================================================
set -euo pipefail
# Resolve the repository root from this script's own location (portable checkout).
REPO_ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PREFIX="${WINEPREFIX:-$REPO_ROOT/wineprefix-csp}"
SRC="$REPO_ROOT/diag/csp-wintab"
PAINTDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT"

if pgrep -f 'CLIPStudio[P]aint' >/dev/null 2>&1; then
    echo "ERROR: CSP is still running — please close it (the loaded DLL is locked)." >&2
    exit 1
fi
[ -f "$SRC/wintab32.dll" ] || { echo "ERROR: $SRC/wintab32.dll is missing (to build it see CSP-TABLET-FIX.md §3)" >&2; exit 1; }
[ -d "$PAINTDIR" ] || { echo "ERROR: CSP app directory not found: $PAINTDIR" >&2; exit 1; }

cp "$SRC/wintab32.dll" "$PAINTDIR/"
for f in XWinTabHelper.dll.so LICENSE NOTICE; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$PAINTDIR/"
done
WINEPREFIX="$PREFIX" wine reg add 'HKCU\Software\Wine\DllOverrides' \
    /v wintab32 /t REG_SZ /d native /f >/dev/null

echo "OK: $PAINTDIR/wintab32.dll (patched, CSP-compatible) + XI2 helper installed."

# --- Device name for WTInfo(DVC_NAME) ----------------------------------------
# The helper does not export a device name; the DLL therefore reads it from
# <PAINTDIR>/XWinTabDeviceName.txt (or $XWINTAB_DEVICE_NAME). Here it is taken from
# the X11 device list - by the same rule the helper uses to select its
# device (name contains "stylus", or $XWINTAB_DEVICE).
DEVNAME="${XWINTAB_DEVICE_NAME:-}"
DEVTOOL="$REPO_ROOT/diag/xi2-devname"
if [ -z "$DEVNAME" ] && [ ! -x "$DEVTOOL" ] && [ -f "$DEVTOOL.c" ] \
   && command -v gcc >/dev/null 2>&1 && pkg-config --exists x11 xi 2>/dev/null; then
    gcc -O2 "$DEVTOOL.c" -o "$DEVTOOL" -lX11 -lXi 2>/dev/null || true   # build once
fi
if [ -z "$DEVNAME" ] && [ -x "$DEVTOOL" ]; then
    DEVNAME="$("$DEVTOOL" 2>/dev/null || true)"
fi
if [ -n "$DEVNAME" ]; then
    printf '%s\n' "$DEVNAME" > "$PAINTDIR/XWinTabDeviceName.txt"
    echo "OK: device name for WTInfo(DVC_NAME): \"$DEVNAME\""
else
    echo "Note: no tablet found at the X level -> WTInfo(DVC_NAME) reports the placeholder."
    echo "      After connecting the tablet: run $DEVTOOL and write its output"
    echo "      to \"$PAINTDIR/XWinTabDeviceName.txt\" (or set XWINTAB_DEVICE_NAME)."
fi

echo "Start:  $REPO_ROOT/start-csp.sh          (editor directly)"
echo "Tuning: $REPO_ROOT/start-csp.sh tilt 9   (default is now 9; larger = more aggressive)"

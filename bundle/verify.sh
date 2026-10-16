#!/bin/bash
# =============================================================================
# csp-linux-bundle — verification (changes nothing)
#   ./verify.sh              # checks prefix, fix files, override
#   ./verify.sh --tablet     # additionally: check the X level (XI2), if gcc/libXi are there
#   ./verify.sh --panels     # additionally: really start the Hub and measure the menu viewport
#                            #   (proof that the Hub menu is visible AND clickable)
#   ./verify.sh --prefix DIR # check another prefix (otherwise $WINEPREFIX or ~/.wine-csp)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${WINEPREFIX:-$HOME/.wine-csp}"
WITH_TABLET=0
WITH_WINRT=0
WITH_PANELS=0
for a in "$@"; do
    [ "$a" = "--tablet" ] && WITH_TABLET=1
    [ "$a" = "--winrt" ]  && WITH_WINRT=1
    [ "$a" = "--panels" ] && WITH_PANELS=1
done
# --prefix DIR (the value is in the next argument, hence its own pass)
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2;;
        *) shift;;
    esac
done

# Automatically use the own/portable Wine (noted in the prefix by the installer).
# Must come AFTER the --prefix evaluation, otherwise the wrong prefix is consulted.
if [ -f "$PREFIX/portable-wine-path" ]; then
    WB="$(cat "$PREFIX/portable-wine-path" 2>/dev/null)"
    if [ -n "$WB" ] && [ -x "$WB/wine" ]; then
        export PATH="$WB:$PATH"
        echo "(using Wine from $WB: $("$WB/wine" --version 2>/dev/null))"
    fi
fi

PASS=0; FAIL=0
chk() { # $1=status(ok|fail|warn) $2=text
    case "$1" in
        ok)   printf '\033[1;32m[ OK ]\033[0m %s\n' "$2"; PASS=$((PASS+1));;
        fail) printf '\033[1;31m[FAIL]\033[0m %s\n' "$2"; FAIL=$((FAIL+1));;
        *)    printf '\033[1;33m[WARN]\033[0m %s\n' "$2";;
    esac
}

echo "csp-linux-bundle — verification  (prefix: $PREFIX)"
echo

# wine
if command -v wine >/dev/null 2>&1; then chk ok "wine: $(wine --version 2>/dev/null)"; else chk fail "wine not found"; fi

PAINTDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT"
HUBDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO"
PAINT_EXE="$PAINTDIR/CLIPStudioPaint.exe"

# CSP
[ -f "$PAINT_EXE" ] && chk ok "CSP main program: $PAINT_EXE" || chk fail "CSP main program missing: $PAINT_EXE"
[ -f "$HUBDIR/CLIPStudio.exe" ] && chk ok "Hub present (login/assets): $HUBDIR/CLIPStudio.exe" || chk warn "Hub (CLIPStudio.exe) not found — login/assets may not be usable"

# Fix files + hash comparison with the package
for f in wintab32.dll XWinTabHelper.dll.so; do
    if [ -f "$PAINTDIR/$f" ]; then
        if [ -f "$HERE/files/$f" ]; then
            a=$(sha256sum "$PAINTDIR/$f" | cut -d' ' -f1)
            b=$(sha256sum "$HERE/files/$f" | cut -d' ' -f1)
            [ "$a" = "$b" ] && chk ok "$f installed (hash matches the package)" \
                            || chk warn "$f installed, but a different hash than in the package (foreign version?)"
        else
            chk ok "$f installed"
        fi
    else
        chk fail "$f missing in the app directory -> pen pressure will not work"
    fi
done

# DllOverride
OV=$(WINEPREFIX="$PREFIX" wine reg query 'HKCU\Software\Wine\DllOverrides' /v wintab32 2>/dev/null | grep -i wintab32 || true)
case "$OV" in
    *native*) chk ok "Wine override wintab32=native set";;
    *)        chk fail "Wine override wintab32=native missing (WINEPREFIX=\"$PREFIX\" wine reg add 'HKCU\\Software\\Wine\\DllOverrides' /v wintab32 /t REG_SZ /d native /f)";;
esac

# Device name reported by WTInfo(DVC_NAME) (sidecar next to the DLL / env)
if [ -n "${XWINTAB_DEVICE_NAME:-}" ]; then
    chk ok "Device name (DVC_NAME) from XWINTAB_DEVICE_NAME: \"$XWINTAB_DEVICE_NAME\""
elif [ -s "$PAINTDIR/XWinTabDeviceName.txt" ]; then
    chk ok "Device name (DVC_NAME): \"$(head -1 "$PAINTDIR/XWinTabDeviceName.txt")\" (XWinTabDeviceName.txt)"
else
    if [ -f "$HERE/files/xi2-devname.c" ] && command -v gcc >/dev/null 2>&1; then
        TMPD=$(mktemp -d); if gcc -O2 "$HERE/files/xi2-devname.c" -o "$TMPD/dn" -lX11 -lXi 2>/dev/null; then
            DN=$("$TMPD/dn" 2>/dev/null || true)
            [ -n "$DN" ] && chk warn "Device name not installed (WTInfo(DVC_NAME) reports the placeholder) - tablet is there: \"$DN\"" \
                         || chk warn "no tablet found at the X level -> WTInfo(DVC_NAME) reports the placeholder"
        else
            chk warn "Device name cannot be checked (xi2-devname not buildable: libX11/libXi?)"
        fi
        rm -rf "$TMPD"
    else
        chk warn "Device name (DVC_NAME) not set -> the DLL reports the placeholder"
    fi
fi

# WinRT classes (CSP 5 needs RadialController + Storage; otherwise crash when starting the editor)
winrt_ok() {   # the probe tool is the truth (a string search would be unreliable)
    local out
    [ -f "$HERE/files/winrt-probe.exe" ] || return 0
    out=$(WINEPREFIX="$PREFIX" wine "$HERE/files/winrt-probe.exe" 2>/dev/null) || true
    case "$out" in
        *"0 missing"*) return 0 ;;
        *"missing"*)   return 1 ;;
        *)            return 0 ;;
    esac
}
if winrt_ok; then
    chk ok "Wine provides the WinRT classes for CSP 5 (RadialController/Storage)"
else
    chk fail "Wine does not provide the WinRT classes (4-5 missing) -> CSP crashes when starting the editor. Use portable Wine 11.19+ (--wine-bin) or update system Wine. Probe: wine files/winrt-probe.exe"
fi

# Wine addons + WebView2 (crucial for UI windows)
# The source may be the prefix OR a distro package — Wine loads the trees directly:
#   Gecko: mshtml load_gecko() -> <datadir>/wine/gecko/wine-gecko-<ver>-<arch>, /opt/wine/gecko/…
#   Mono:  mscoree get_mono_path() -> <datadir>/wine/mono/wine-mono-<ver>,      /opt/wine/mono/…
gecko_present() {
    ls -d "$PREFIX/drive_c/windows/system32/gecko/"[0-9]* >/dev/null 2>&1 && return 0
    ls -d /usr/share/wine/gecko/wine-gecko-*/  >/dev/null 2>&1 && return 0
    ls -d /opt/wine/gecko/wine-gecko-*/        >/dev/null 2>&1 && return 0
    return 1
}
if gecko_present; then
    chk ok "Wine Gecko present (MSHTML/IE-based UI)"
else
    chk warn "Wine Gecko missing -> IE-based UI may stay empty/white; click \"Install\" in the Wine dialog or: ./install.sh --no-csp"
fi
mono_present() {
    grep -qi "Wine Mono Runtime" "$PREFIX/system.reg" 2>/dev/null && return 0
    ls -d /usr/share/wine/mono/wine-mono-*/ >/dev/null 2>&1 && return 0
    ls -d /opt/wine/mono/wine-mono-*/       >/dev/null 2>&1 && return 0
    return 1
}
if mono_present; then
    chk ok "Wine Mono present (.NET)"
else
    chk warn "Wine Mono missing (.NET) -> ./install.sh --no-csp (or confirm the Wine dialog)"
fi
if [ -d "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView" ]; then
    chk ok "WebView2 runtime present (Hub/login/assets)"
else
    chk warn "WebView2 missing -> Hub/login/assets incomplete; run the CSP installer again"
fi

# dcomp shim: "Present->target" only occurs in the patched version (files/src/dcomp-csp-linux.patch),
# "csp-linux rev2" only from v0.1.14 on (patch only in the WebView2 process; v0.1.13 broke native Hub dialogs).
# Without the patch the Hub content stays put/black after clicks.
DCOMP_SYS="$PREFIX/drive_c/windows/system32/dcomp.dll"
if [ ! -f "$DCOMP_SYS" ]; then
    chk warn "dcomp shim missing -> WebView2 panels may stay white; fix: ./install.sh (or --dcomp-dir DIR)"
elif grep -aq 'csp-linux rev2' "$DCOMP_SYS"; then
    chk ok "dcomp shim installed, patched (Hub content updates, clicks refresh the picture)"
elif grep -aq 'Present->target' "$DCOMP_SYS"; then
    chk warn "dcomp shim is the outdated v0.1.13 patch -> settings/security settings in the Hub are not clickable; fix: ./install.sh"
else
    chk warn "dcomp shim is the unpatched upstream version -> Hub seems not to react to clicks; fix: install mingw-w64 + ./install.sh"
fi
# Copies in the app folders take precedence over system32 (DLL search order) — must be identical
for d in "CLIP STUDIO" "CLIP STUDIO PAINT"; do
    f="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/$d/dcomp.dll"
    [ -f "$f" ] && [ -f "$DCOMP_SYS" ] || continue
    if cmp -s "$f" "$DCOMP_SYS"; then chk ok "dcomp.dll in '$d' = system32"
    else chk warn "dcomp.dll in '$d' differs from system32 (shadows it!); fix: ./install.sh"; fi
done

# Menu entries: must call run-csp.sh (otherwise WebView2 arguments, GPU path, UA, dialog fix are missing)
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications/wine/Programs"
for e in "CLIP STUDIO PAINT.desktop" "CLIP STUDIO.desktop"; do
    f="$APPS/$e"
    if [ ! -f "$f" ]; then
        chk warn "Menu entry '$e' missing (--no-shortcuts?) — ./install.sh creates it; otherwise start via ./run-csp.sh"
    elif ! grep -qF "$PREFIX" "$f" 2>/dev/null; then
        chk warn "Menu entry '$e' belongs to another prefix"
    elif ! grep -q 'run-csp.sh' "$f"; then
        chk warn "Menu entry '$e' starts Wine directly, without the fixes (Hub empty/sluggish, high RAM) — fix: ./install.sh"
    else
        launcher="$(sed -n 's/^Exec="\([^"]*run-csp.sh\)".*/\1/p' "$f" | head -1)"
        if [ -x "$launcher" ]; then chk ok "Menu entry '$e' -> run-csp.sh (launcher present)"
        else chk warn "Menu entry '$e' points to a missing launcher '$launcher' — fix: ./install.sh"; fi
    fi
done

# GPU path: DXVK + VKD3D (native d3d9/d3d11/d3d12/dxgi) + dxvk.conf
if grep -qx 'dxvk' "$PREFIX/winetricks.log" 2>/dev/null || grep -qx 'vkd3d' "$PREFIX/winetricks.log" 2>/dev/null; then
    chk ok "GPU path: DXVK/VKD3D installed (winetricks.log)"
else
    chk warn "GPU path: DXVK/VKD3D not installed -> WebView2 panels may stay black/empty; fix: ./install.sh (or --no-dxvk to turn it off)"
fi
d3d11_size=$(stat -c%s "$PREFIX/drive_c/windows/system32/d3d11.dll" 2>/dev/null || echo 0)
if [ "$d3d11_size" -gt 1000000 ]; then
    chk ok "GPU path: native d3d11.dll active ($((d3d11_size/1024)) KB; Wine builtin would be ~200 KB)"
else
    chk warn "GPU path: d3d11.dll is the Wine builtin ($((d3d11_size/1024)) KB) -> DXVK not active"
fi
if [ -f "$PREFIX/dxvk.conf" ]; then
    if grep -q 'deferSurfaceCreation' "$PREFIX/dxvk.conf"; then
        chk ok "dxvk.conf present (dxgi.deferSurfaceCreation = True)"
    else
        chk warn "dxvk.conf present, but without dxgi.deferSurfaceCreation -> WebView2 panels possibly empty"
    fi
else
    chk warn "dxvk.conf missing (run-csp.sh then does not set DXVK_CONFIG_FILE)"
fi

# WebView2 panels need the browser arguments; without them the menu buttons are dead.
# That can only be proven live: start the Hub, open the menu, measure the viewport.
# Without the arguments the viewport collapses to 1x1 px — the menu entries then have
# no clickable area. Measured via WebView2's DevTools protocol
# (--remote-debugging-port, set only for this check).
# The live probe opens the menu itself (by X click, see files/xdlg.c) and checks whether
# the panel CONTENT is really drawn. Two questions have to be separated:
#   a) Is the page running?       -> DevTools protocol reachable, menu.html found
#   b) Is it also DISPLAYED?      -> the content only arrives in Wine with --in-process-gpu
# For b) a screenshot of the menu window is taken and its colour variety measured:
# visible content => >1000 different colours, invisible (black or white) => ~100.
# Without a screenshot tool it stays with the viewport measurement.
panel_viewport_probe() {
    # Formerly the X11 root was captured via spectacle/scrot. That is worthless under Wayland
    # (KWin): the Xwayland root is empty (only ~54 colours, all black), and the panel windows
    # only draw the Chromium content at all via the dcomp shim. In addition spectacle triggers
    # the KDE dialog "Request remote control" on every call. So the measurement now uses the
    # DevTools protocol (CDP): the page itself delivers its picture (Page.captureScreenshot),
    # independent of the composition.
    #
    # Important: menu.html is already present as a target as soon as WebView2 runs — also with
    # the menu COLLAPSED (innerWidth=innerHeight=1). A hit is therefore only menu_iw > 100.
    # So first wait, then click the grid icon, then keep measuring.
    local port=9223
    local runner="$HERE/run-csp.sh"
    local probe="$HERE/files/panelprobe.py"
    [ -x "$runner" ] || return 2
    [ -f "$probe" ] || return 2
    command -v python3 >/dev/null 2>&1 || return 2
    # run-csp.sh sets the right arguments; only add the debug port.
    "$runner" hub --prefix "$PREFIX" --debug-port "$port" >/dev/null 2>&1 &
    local launcher=$!
    cleanup_probe() { kill "$launcher" 2>/dev/null; pkill -f "CLIPStudio\.exe" 2>/dev/null; }

    local i out="" iw=0
    # Phase 1: wait until WebView2 answers at all (target list parses).
    for ((i = 0; i < 40; i++)); do
        sleep 3
        out="$(timeout 12 python3 "$probe" report "$port" 2>/dev/null)" || true
        case "$out" in '{'*) break;; *) out="";; esac
    done
    if [ -z "$out" ]; then cleanup_probe; return 3; fi

    # Phase 2: open the menu via the grid icon and measure (WebView2 needs ~30-40 s,
    # the helper waits internally and then keeps clicking at 3 s intervals).
    local xd=""
    if [ -n "${DISPLAY:-}" ] && command -v gcc >/dev/null 2>&1 && [ -f "$HERE/files/xdlg.c" ]; then
        xd="$(mktemp -d)"
        gcc -O2 -o "$xd/xdlg" "$HERE/files/xdlg.c" -lX11 -lXtst 2>/dev/null \
            && ( "$xd/xdlg" grid 60 >/dev/null 2>&1 & ) || xd=""
    fi
    for ((i = 0; i < 24; i++)); do
        sleep 4
        out="$(timeout 12 python3 "$probe" report "$port" 2>/dev/null)" || true
        case "$out" in '{'*) : ;; *) continue;; esac
        iw=$(printf '%s' "$out" | tr ',' '\n' | grep -o '"menu_iw": *[0-9]*' | grep -o '[0-9]*$')
        [ "${iw:-0}" -gt 100 ] 2>/dev/null && break
    done
    [ -n "$xd" ] && rm -rf "$xd" 2>/dev/null
    echo "      (panels measured live: $out)"
    cleanup_probe
    [ "${iw:-0}" -gt 100 ] 2>/dev/null && return 0
    return 1
}

if grep -q 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS' "$HERE/run-csp.sh" 2>/dev/null; then
    chk ok "run-csp.sh sets WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS (menu buttons in the Hub)"
    # Without the UA replacement tips.clip-studio.com (menu "Official tutorials", start page)
    # returns 403 to every User-Agent with "Chrome/".
    if grep -q -- '--user-agent' "$HERE/run-csp.sh" 2>/dev/null; then
        chk ok "run-csp.sh replaces the User-Agent (prevents the 403 of the tutorial site)"
    else
        chk warn "run-csp.sh does not replace the User-Agent -> the CELSYS tutorial site may return 403"
    fi
    if [ -f "$HERE/files/panelprobe.py" ]; then
        chk ok "files/panelprobe.py present (panel diagnostics via DevTools protocol)"
    else
        chk warn "files/panelprobe.py missing (verify.sh --panels cannot measure)"
    fi
    if [ "$WITH_PANELS" = 1 ]; then
        echo "--- live probe: Hub menu viewport ---"
        if ! command -v python3 >/dev/null 2>&1; then
            chk warn "live probe skipped (python3 missing)"
        elif [ -z "${DISPLAY:-}" ]; then
            chk warn "live probe skipped (no DISPLAY — please run inside the session)"
        else
            panel_viewport_probe
            case $? in
                0) chk ok "Hub menu is rendered visibly (--in-process-gpu works)";;
                1) chk fail "Hub menu stays empty (black/white) -> use run-csp.sh (--in-process-gpu)!";;
                *) chk warn "Hub did not start / menu not found — live probe without result";;
            esac
        fi
    fi
else
    chk warn "run-csp.sh does not set the WebView2 arguments -> Hub menu stays empty/not clickable"
fi

# which wintab32 does CSP really load?
RUNNING=$(pgrep -f 'CLIPStudio[P]aint.exe' | head -1 || true)
if [ -n "$RUNNING" ]; then
    if grep -q "CLIP STUDIO PAINT/wintab32.dll" "/proc/$RUNNING/maps" 2>/dev/null; then
        chk ok "running CSP uses the patched DLL ($PAINTDIR/wintab32.dll)"
    else
        chk warn "running CSP (PID $RUNNING) has not mapped the app-dir DLL"
    fi
else
    chk warn "CSP is not running right now (live check of the DLL skipped)"
fi

# X level: tablet visible?
if [ "$WITH_TABLET" = 1 ]; then
    echo
    echo "--- tablet at the X level ---"
    if command -v gcc >/dev/null 2>&1 && [ -f "$HERE/files/xi2-probe.c" ]; then
        TMP=$(mktemp -d); gcc -O2 "$HERE/files/xi2-probe.c" -o "$TMP/xi2-probe" -lX11 -lXi 2>/dev/null \
            && "$TMP/xi2-probe" | grep -iE "stylus|pen|pressure|tilt" | head -10 \
            || chk warn "xi2-probe could not be built/run (libXi/gcc?)"
        rm -rf "$TMP"
        echo "  (lines with 'Abs Pressure' = a pen with pressure is offered by X)"
    else
        chk warn "gcc/libXi not available — tablet check skipped"
    fi
fi

if [ "$WITH_WINRT" = 1 ]; then
    echo
    echo "--- WinRT classes (probe) ---"
    if [ -f "$HERE/files/winrt-probe.exe" ]; then
        WINEPREFIX="$PREFIX" wine "$HERE/files/winrt-probe.exe" 2>/dev/null | sed 's/^/  /'
        echo "  (all lines \"OK\" = CSP can start the editor)"
    else
        echo "  files/winrt-probe.exe missing"
    fi
fi

if [ "$WITH_PANELS" != 1 ]; then
    echo "  (tip: ./verify.sh --panels checks live whether the Hub menu really becomes visible)"
fi

echo
echo "Result: $PASS OK, $FAIL errors"
[ "$FAIL" -eq 0 ] && echo "-> Should work. To test: open the editor, draw with pressure." \
                  || echo "-> Please fix the FAIL lines (see README.md, troubleshooting section)."

exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)

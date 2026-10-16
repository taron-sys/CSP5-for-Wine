#!/bin/bash
# =============================================================================
# run-csp.sh — start CLIP STUDIO PAINT with the RIGHT (possibly portable) Wine.
#
# Usage:
#   ./run-csp.sh                       # start the editor (prefix: $WINEPREFIX or ~/.wine-csp)
#   ./run-csp.sh hub                   # CLIP STUDIO launcher (login/assets)
#   ./run-csp.sh --prefix DIR          # other prefix
#   ./run-csp.sh --wine-bin DIR        # use a specific (portable) Wine
#   ./run-csp.sh --kill                # first terminate running Wine servers
#                                      #   (needed on "version mismatch ..."/a stuck wineserver)
#   ./run-csp.sh -- <file.clip>        # open a document directly
#   ./run-csp.sh --no-gpu-env          # do NOT set the WebView2/DXVK variables (diagnostics)
#   ./run-csp.sh --no-dialog-fix       # do NOT click away the "not closed properly" dialog
#   ./run-csp.sh --menu-open           # open the Hub menu automatically by click (experimental)
#   ./run-csp.sh --no-user-agent       # do NOT replace the User-Agent (diagnostics)
#   ./run-csp.sh --multi-process       # WebView2 with Chromium's default process model (more RAM)
#   ./run-csp.sh --debug-port N        # DevTools port N for panel diagnostics (only if needed)
#
# The Hub menu is NOT opened automatically: the click on the grid icon has to be timed
# exactly (WebView2 needs ~30-40 s) and can also close the menu again. Just click the grid
# icon at the top right yourself — with --in-process-gpu the content is then visible.
#
# The script sets PATH, WINELOADER and WINESERVER to the chosen Wine — so no Wine server
# of another version can interfere.
#
# It also sets the variables that make the WebView2 panels (Hub/login/settings)
# work:
#   WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS  -> --no-sandbox --in-process-gpu …
#       The Hub also starts without these arguments (except --no-sandbox, which WebView2
#       needs under Wine). But then the Hub menu STAYS INVISIBLE: the panel is there and
#       reacts to clicks (the items fire menuAction/callIce), but its content is never
#       drawn in its window — black (dark theme) or white (light theme). The cause is the
#       GPU composition of Chromium's compositor subprocess in Wine: --in-process-gpu
#       keeps the GPU work in the main process, then the dcomp shim takes effect and the
#       content appears. Measurements (reference system, Intel UHD, Wine 11.19): panel
#       pixels 138 colours/black WITHOUT, 4309 colours/visible WITH --in-process-gpu.
#       NOTE --disable-gpu-compositing breaks exactly that again (software path bypasses
#       the shim): it was in the CSPenguin installer but is wrong here and was therefore
#       removed. For the same reason --disable-gpu does not belong here either.
#       NOTE --user-agent: the menu entry "Official tutorials" and the start page call
#       tips.clip-studio.com. That host returns 403 Forbidden to EVERY User-Agent
#       containing "Chrome/" — and that is exactly what WebView2 (Chromium 115) sends.
#       Hence the UA is replaced. The replacement still contains "CLIPSTUDIO/<version>",
#       because menu.js reads its version from it (main.getIceVer) — without that part
#       the menu breaks. So: no "Chrome/" in the UA, but "CLIPSTUDIO/" must stay.
#   DXVK_CONFIG_FILE / DXVK_STATE_CACHE / mesa_glthread  -> GPU path
#
# And it clicks away the dialog "CLIP STUDIO was not closed properly last time". That dialog
# COMPLETELY BLOCKS the Hub: WebView2 does not start at all then (no menu, no window
# content). It only appears after a harsh termination (pkill / wineserver -k); after a
# clean exit it does not come.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${WINEPREFIX:-$HOME/.wine-csp}"
WINE_BIN=""
KILL=0
GPU_ENV=1
DIALOG_FIX=1
MENU_OPEN=0
UA_FIX=1
LOW_MEM=1
DEBUG_PORT=0
WHAT="editor"
ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        editor|paint) WHAT=editor; shift;;
        hub)          WHAT=hub; shift;;
        --prefix)     PREFIX="$2"; shift 2;;
        --wine-bin)   WINE_BIN="$2"; shift 2;;
        --kill)       KILL=1; shift;;
        --no-gpu-env)    GPU_ENV=0; shift;;
        --no-dialog-fix) DIALOG_FIX=0; shift;;
        --menu-open)     MENU_OPEN=1; shift;;
        --no-user-agent) UA_FIX=0; shift;;
        --multi-process) LOW_MEM=0; shift;;
        --debug-port)    DEBUG_PORT="$2"; shift 2;;
        -h|--help)    sed -n '5,/^#$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;

        --)           shift; ARGS=("$@"); break;;
        *)            ARGS+=("$1"); shift;;
    esac
done

# Determine Wine: --wine-bin > Wine noted in the prefix > system Wine
if [ -z "$WINE_BIN" ] && [ -f "$PREFIX/portable-wine-path" ]; then
    WINE_BIN="$(cat "$PREFIX/portable-wine-path" 2>/dev/null)"
fi
if [ -n "$WINE_BIN" ] && [ -x "$WINE_BIN/wine" ]; then
    export PATH="$WINE_BIN:$PATH"
    export WINELOADER="$WINE_BIN/wine"
    [ -x "$WINE_BIN/wineserver" ] && export WINESERVER="$WINE_BIN/wineserver"
    WINE="$WINE_BIN/wine"
else
    WINE="$(command -v wine 2>/dev/null)" || { echo "ERROR: no wine found (pass --wine-bin DIR)"; exit 1; }
fi
export WINEPREFIX="$PREFIX"

# User-Agent for WebView2. Deliberately contains NO "Chrome/" (that triggers the 403 from
# tips.clip-studio.com), but still "CLIPSTUDIO/<version>" — menu.js reads its version
# from it. 5.0.4 is the version of the reference prefix.
WV2_UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Win64/NT 10.0/CLIPSTUDIO/5.0.4/DoNotTrack'

# ---- WebView2 + GPU path -------------------------------------------------------
# Without --in-process-gpu the Hub menu content stays invisible (black/white) although
# the panel is there and accepts clicks. --disable-gpu-compositing would undo exactly
# that effect — hence do NOT pass it (see the header comment).
if [ "$GPU_ENV" = 1 ]; then
    WV2_ARGS="--no-sandbox --in-process-gpu --disable-gpu-vsync --disable-background-networking --no-first-run --disable-sync --disable-renderer-accessibility --disable-extensions --disable-component-extensions-with-background-pages --disk-cache-size=33554432 --disable-features=msEdgeSidebar"
    if [ "$UA_FIX" = 1 ]; then
        # CLIPSTUDIO/<version> is kept (menu.js reads the version from it),
        # "Chrome/" is dropped (otherwise 403 from tips.clip-studio.com).
        WV2_ARGS="$WV2_ARGS --user-agent=$WV2_UA"
    fi
    # Memory: under Wine EVERY WebView2 process holds a private copy of msedge.dll
    # (~230 MB; file alignment 0x200 < page size -> Wine cannot map the image from the
    # file and reads it into anonymous memory). The default is ~11 processes (one renderer
    # per panel + network/storage services) = ~5 GB right after the Hub starts.
    # One renderer for all panels + network service in the browser process: 4 processes, ~1.5 GB.
    # WebView2 sets MojoIpcz itself; --enable-features overrides, so pass it along.
    if [ "$LOW_MEM" = 1 ]; then
        WV2_ARGS="$WV2_ARGS --renderer-process-limit=1 --disable-site-isolation-trials --enable-features=MojoIpcz,NetworkServiceInProcess2"
    fi
    [ "$DEBUG_PORT" != 0 ] && WV2_ARGS="$WV2_ARGS --remote-debugging-port=$DEBUG_PORT"
    export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="${WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:-$WV2_ARGS}"
    if [ -f "$PREFIX/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="$PREFIX/dxvk.conf"
    fi
    export DXVK_STATE_CACHE=1
    # DXVK_STATE_CACHE_PATH / DXVK_ASYNC only exist from DXVK 2.x on (v1 ignores them).
    # We only set them if DXVK is really in the prefix — otherwise they do no harm,
    # but an existing DXVK-1 setup of your own stays untouched.
    if grep -qx 'dxvk' "$PREFIX/winetricks.log" 2>/dev/null; then
        export DXVK_ASYNC=1
        export DXVK_STATE_CACHE_PATH="$PREFIX/drive_c/users/${USER:-user}/AppData/Local/dxvk"
    fi
    export mesa_glthread=true
    [ "$(uname -m)" = x86_64 ] && export RADV_PERFTEST="${RADV_PERFTEST:-gpl}"
fi

echo "Wine:   $("$WINE" --version 2>/dev/null || echo '?')   [$WINE]"
echo "Prefix: $PREFIX"
[ "$GPU_ENV" = 1 ] && {
    echo "Panels: WebView2 arguments (--in-process-gpu) + GPU path set (--no-gpu-env turns this off)"
    [ "$UA_FIX" = 1 ] && echo "Panels: User-Agent replaced (prevents the 403 of the CELSYS tutorial site)"
    [ "$LOW_MEM" = 1 ] && echo "Panels: WebView2 with 1 renderer (saves ~3.5 GB RAM; --multi-process turns this off)"
    [ "$DEBUG_PORT" != 0 ] && echo "Panels: DevTools port $DEBUG_PORT open (diagnostics)"
}

xdlg_build() {          # prints the path to the built helper (or nothing)
    command -v gcc >/dev/null 2>&1 || return 1
    local src="$HERE/files/xdlg.c" d
    [ -f "$src" ] || return 1
    d="$(mktemp -d)" || return 1
    gcc -O2 -o "$d/xdlg" "$src" -lX11 -lXtst 2>/dev/null || { rm -rf "$d"; return 1; }
    echo "$d/xdlg"
}

if [ "$KILL" = 1 ]; then
    echo "Terminating running Wine servers …"
    # our own process name does not contain 'wineserver' -> no self-match
    pkill -f "wineserver" 2>/dev/null || true
    pkill -f "CLIPStudio" 2>/dev/null || true
    sleep 2
fi

# ---- click away the dialog / open the menu (X helper) -------------------------
# The dialog "CLIP STUDIO was not closed properly last time" appears shortly AFTER
# CLIPStudio.exe starts and blocks the app until the button "Open CLIP STUDIO" is pressed.
# While it is open, WebView2 does not start -> Hub and menu stay empty.
# There is no shell built-in for this (wmctrl/xdotool/python-xlib are not common), so
# a tiny C program (files/xdlg.c, built with gcc like the others).
#
# Important: the watcher is only started AFTER a possible --kill, otherwise it runs
# against the old windows and sleeps when the new dialog comes.
DISMISS_PID=""
XL=""
if [ "$DIALOG_FIX" = 1 ] && [ -n "${DISPLAY:-}" ]; then
    XL="$(xdlg_build || true)"
    if [ -n "$XL" ]; then
        ( "$XL" dismiss 60 ) >/dev/null 2>&1 &
        DISMISS_PID=$!
        echo "Dialog:   \"not closed properly\" is clicked away automatically (if it appears)"
    else
        echo "Note: gcc or files/xdlg.c is missing — click away the \"not closed properly\""
        echo "      dialog yourself if needed, otherwise the Hub menu stays empty."
    fi
fi

case "$WHAT" in
    editor) EXE='C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe';;
    hub)    EXE='C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO\CLIPStudio.exe';;
esac

if [ ! -f "$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe" ]; then
    echo "WARNING: CSP does not seem to be installed in this prefix."
fi

out="$(mktemp)"
"$WINE" "$EXE" ${ARGS[@]+"${ARGS[@]}"} >"$out" 2>&1 &
pid=$!
sleep 6
if grep -qi "version mismatch" "$out" 2>/dev/null; then
    echo
    echo "ERROR: 'version mismatch' — a Wine server of another Wine version is still running."
    echo "       Please terminate it and start again with:   $0 --kill${WINE_BIN:+ --wine-bin \"$WINE_BIN\"}"
    echo
    sed -n '1,4p' "$out"
    kill $pid 2>/dev/null || true
    rm -f "$out"
    exit 2
fi
# Open the Hub menu automatically on request (--menu-open). Without --in-process-gpu
# the panel content stays invisible (black/white) although it is there. The click has
# to be timed, so this is NOT the default: better click the grid icon at the top
# right yourself.
if [ "$GPU_ENV" = 1 ] && [ "$MENU_OPEN" = 1 ] && [ "$WHAT" = hub ] && [ -n "${DISPLAY:-}" ] && [ -n "$XL" ]; then
    "$XL" grid 12 >/dev/null 2>&1 &
fi
wait $pid
rc=$?
# Only now clean up the helper directory (the binary is still in use before)
[ -n "$XL" ] && rm -rf "$(dirname "$XL")" 2>/dev/null || true
grep -iE "unhandled exception|page fault in|triglavwinrt" "$out" | head -5
[ -n "$DISMISS_PID" ] && kill "$DISMISS_PID" 2>/dev/null || true
rm -f "$out"
exit $rc

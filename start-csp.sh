#!/bin/bash
# =============================================================================
# start-csp.sh — CLIP STUDIO PAINT under Wine, with the fixes found
#
# Usage:
#   ./start-csp.sh            → editor directly (recommended, bypasses Hub/JIT noise)
#   ./start-csp.sh hub        → CLIP STUDIO launcher (Hub; login/assets — works since CSP 5)
#   ./start-csp.sh quiet      → editor with WINEDEBUG=-all (no console output)
#   ./start-csp.sh debug      → editor with +seh (crash/exception traces to a file)
#   ./start-csp.sh tabtest    → Wintab pressure diagnostics window (25 s, then summary)
#   ./start-csp.sh nojitter   → editor + Wine “Just-In-Time debugger” dialogs disabled (this session only)
#
# NOTE: for the Hub prefer bundle/run-csp.sh (sets the WebView2 arguments, GPU path, etc.).
# =============================================================================

# Resolve the repository root from this script's own location so the checkout
# can live anywhere (no hard-coded paths).
REPO_ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PREFIX="${WINEPREFIX:-$REPO_ROOT/wineprefix-csp}"
PAINT='C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe'
HUB='C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO\CLIPStudio.exe'
DIAG="$REPO_ROOT/diag"

export WINEPREFIX="$PREFIX"
case "${1:-paint}" in
  paint|quiet)
    [ "$1" = quiet ] && export WINEDEBUG=-all
    exec wine "$PAINT"
    ;;
  hub)
    # The Hub spawns WebView2; sandbox arguments as a safety net:
    export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="${WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:---no-sandbox}"
    exec wine "$HUB"
    ;;
  debug)
    mkdir -p "$DIAG"
    exec wine "$PAINT" 2>&1 | tee "$DIAG/csp-debug-$(date +%H%M%S).log"
    ;;
  tabtest)
    cd "$PREFIX/drive_c/windows" && exec wine ./t4.exe
    ;;
  tilt)
    # Tilt fine-tuning: ./start-csp.sh tilt <factor>   (default 9; smaller = gentler)
    export XWINTAB_ALT_SCALE="${2:-9}"
    echo "Tablet tilt: XWINTAB_ALT_SCALE=$XWINTAB_ALT_SCALE (DLL default: 9)"
    exec wine "$PAINT"
    ;;
  tabtestw)
    # Live pressure test AGAINST the patched WineTab DLL (app dir!). Close CSP first!
    cd "$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT" \
        && exec env XWINTAB_LOG=1 wine ./t5w.exe
    ;;
  paintlog)
    # Editor start with Wintab logging: log under drive_c/users/$USER/XWinTabLog.txt
    export XWINTAB_LOG=1
    exec wine "$PAINT"
    ;;
  nojitter)
    # Suppress Wine’s “Unhandled exception … starting debugger” window:
    # set the AeDebug target to nothing (this prefix; CSP aborts silently instead of a JIT dialog)
    wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' \
        /v Debugger /t REG_SZ /d "" /f
    exec wine "$PAINT"
    ;;
  *)
    echo "usage: $0 [paint|hub|quiet|debug|tabtest|tabtestw|paintlog|tilt <factor>|nojitter]" >&2
    exit 2
    ;;
esac
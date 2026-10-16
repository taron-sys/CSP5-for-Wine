#!/bin/bash
# =============================================================================
# install-csp-prefix.sh — CLIP STUDIO PAINT 5.0.4, silent install into a
# dedicated Wine prefix.
#
# Usage:   ./install-csp-prefix.sh [installer.exe] [prefix-dir]
# Result:  CSP 5.0.4 in "<prefix>/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/"
# Verify:  ResultCode=0 in the setup.log files under <prefix>/drive_c/.../Temp/
#
# Notes (observed while installing):
#   * Installer = InstallShield InstallScript; silent switch is "-s".
#   * It auto-installs Microsoft Edge WebView2 Runtime (x64) as prerequisite.
#   * It registers 2 shell-preview COM DLLs, .clip/.c2fc/.c2fr/.cer file
#     associations, and clipstudio:// + clipstudiopaint:// URI protocols.
#   * Silent mode does NOT create an Add/Remove-Programs entry (observed).
# =============================================================================
set -euo pipefail

# Resolve the repository root from this script's own location (portable checkout).
REPO_ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
INSTALLER="${1:-$REPO_ROOT/installer/CSP_504w_setup.exe}"
PREFIX="${2:-$REPO_ROOT/wineprefix-csp}"

command -v wine >/dev/null || { echo "ERROR: wine not found"; exit 1; }
[ -f "$INSTALLER" ] || { echo "ERROR: installer not found: $INSTALLER"; exit 1; }

export WINEPREFIX="$(mkdir -p "$PREFIX" && readlink -f "$PREFIX")"
export WINEARCH=win64
export WINEDEBUG=-all

echo "[1/3] Creating dedicated 64-bit prefix: $WINEPREFIX"
wineboot -u

echo "[2/3] Running silent install (this takes several minutes)..."
wine "$(readlink -f "$INSTALLER")" -s 2>&1 | tee "$PREFIX/install-csp.log" | \
  grep -aiE "regsvr32|ResultCode|error|failed" || true

echo "[3/3] Verifying..."
APP="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe"
[ -f "$APP" ] && echo "OK: $APP" || { echo "ERROR: main exe missing"; exit 1; }
RC=$(grep -rh "ResultCode" "$PREFIX/drive_c/users/"*/AppData/Local/Temp/*/Disk1/setup.log 2>/dev/null | sort -u | tr '\n' ' ')
echo "InstallShield response: ${RC:-<no response logs found>}"
case "$RC" in
  *ResultCode=0*) echo "SUCCESS: CLIP STUDIO PAINT 5.0.4 installed." ;;
  *) echo "WARNING: ResultCode=0 not found — check $PREFIX/install-csp.log" ;;
esac
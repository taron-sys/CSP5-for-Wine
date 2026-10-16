#!/bin/bash
# =============================================================================
# csp-linux-bundle — CLIP STUDIO PAINT on Wine, incl. the pen pressure fix
#
# Installer (idempotent, safe to run repeatedly). Details & test plan: README.md
#   ./install.sh                 # everything: CSP (silent) + addons + dcomp + DXVK + pen pressure fix
#   ./install.sh --check         # only check, change nothing
#   ./install.sh --no-csp        # only the pen pressure fix, into an existing prefix
#   ./install.sh --prefix DIR    # other prefix (default: $WINEPREFIX or ~/.wine-csp)
#   ./install.sh --no-dxvk       # skip the GPU path (DXVK/VKD3D), use Wine's own d3d
# =============================================================================
set -uo pipefail

# The version lives in ./VERSION (one source for tarball + scripts, see publish-github.sh)
VERSION="$(cat "$(dirname "${BASH_SOURCE[0]}")/VERSION" 2>/dev/null || echo unknown)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/files"

PREFIX="${WINEPREFIX:-$HOME/.wine-csp}"
INSTALLER=""
DO_CSP=1
DO_ADDONS=1
DO_DCOMP=1
DO_DXVK=1
ADDON_MSI_DIR=""
DCOMP_DIR=""
WINE_BIN=""
WINE_PORTABLE=0
WINE_PORTABLE_VER="11.19"
WINE_MIN="11.19"          # CSP 5 needs WinRT classes that are only registered from 11.19 on
SYSTEM_WINE=0
# CSP installer: downloaded when none is found (official CELSYS server).
# Only 5.0.4 is tested with this package and pinned by SHA256.
CSP_VERSION="504"
CSP_SHA_504="27749e99fdf92634a621ace485805eb53001985afc2a73ad20576ae7b8f7c3e6"
WINE_PORTABLE_DIR="${WINE_PORTABLE_DIR:-$HOME/.local/share/wine-portable}"
CHECK_ONLY=0
CREATE_SHORTCUTS=1

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
csp-linux-bundle $VERSION — installer

Usage: ./install.sh [options]

Options:
  --prefix DIR        Wine prefix (default: \$WINEPREFIX or ~/.wine-csp)
  --installer FILE    Path to CSP_*setup.exe (default: automatic search, otherwise download)
  --csp-version VER   CSP version for the download, e.g. 512 (default 504 = 5.0.4, tested +
                      SHA256-checked; other versions are untested and not hash-checked)
  --no-csp            Skip the CSP installation (pen pressure fix only)
  --no-addons         Do not install the Wine addons (Gecko/Mono) automatically
  --wine-portable [VER]  Download and use a portable Wine (default 11.19; download ~100 MB,
                      unpacked ~1 GB, no root). Happens automatically if system Wine is
                      missing or older than $WINE_MIN
  --system-wine       Force system Wine (no automatic portable Wine)
  --wine-portable-dir D  Target directory for portable Wine (default ~/.local/share/wine-portable)
  --wine-bin DIR      Use your own (portable) Wine: DIR contains wine/wine64 (e.g. an unpacked
                      Wine-Staging tarball) — needed if the system Wine version is too old
  --addon-msi-dir DIR Directory with already downloaded wine-gecko-/wine-mono MSI files
  --no-dcomp          Do not install the DirectComposition shim (WebView2 panels may stay white)
  --dcomp-dir DIR     Directory with dcomp_csp.cpp + dcomp.def (offline build) or dcomp.dll +
                      libwinpthread-1.dll (fallback), e.g. a CSPenguin-Installer checkout
  --no-dxvk           Skip the GPU path (do not install DXVK/VKD3D; Wine's own d3d stays)
  --check             Only check, change nothing
  --no-shortcuts      Do not create menu entries
  -h, --help          This help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)      PREFIX="$2"; shift 2;;
        --installer)   INSTALLER="$2"; shift 2;;
        --csp-version) CSP_VERSION="$2"; shift 2;;
        --system-wine) SYSTEM_WINE=1; shift;;
        --no-csp)      DO_CSP=0; shift;;
        --no-addons)   DO_ADDONS=0; shift;;
        --addon-msi-dir) ADDON_MSI_DIR="$2"; shift 2;;
        --wine-bin)    WINE_BIN="$2"; shift 2;;
        --wine-portable) WINE_PORTABLE=1; shift
                         case "${1:-}" in [0-9]*.[0-9]*) WINE_PORTABLE_VER="$1"; shift;; esac;;
        --wine-portable-dir) WINE_PORTABLE_DIR="$2"; shift 2;;
        --no-dcomp)    DO_DCOMP=0; shift;;
        --dcomp-dir)   DCOMP_DIR="$2"; shift 2;;
        --no-dxvk)     DO_DXVK=0; shift;;
        --check)       CHECK_ONLY=1; shift;;
        --no-shortcuts) CREATE_SHORTCUTS=0; shift;;
        -h|--help)     usage; exit 0;;
        *)             die "Unknown option: $1 (see --help)";;
    esac
done

# ---------------------------------------------------------------- Helpers (download/cache)
# These helpers are needed both for portable Wine (1a) and for addons/dcomp (2b).
have() { command -v "$1" >/dev/null 2>&1; }
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wine"
mkdir -p "$CACHE_DIR"
ADDON_LOG="${ADDON_LOG:-$PREFIX/addon-install.log}"

# ---- Acquisition -----------------------------------------------------------------
MSI_DIRS=()
[ -n "$ADDON_MSI_DIR" ] && MSI_DIRS+=("$ADDON_MSI_DIR")
MSI_DIRS+=("$HERE" "$PWD" "$HOME/Downloads" "$CACHE_DIR" /usr/share/wine/mono /usr/share/wine/gecko)

find_local_msi() { # $1 = Glob
    local d f
    for d in "${MSI_DIRS[@]}"; do
        [ -d "$d" ] || continue
        for f in "$d"/$1; do [ -f "$f" ] && { printf '%s' "$f"; return 0; }; done
    done
    return 1
}

url_ok() {
    if have curl; then curl -sfI --connect-timeout 15 -o /dev/null "$1" 2>/dev/null && return 0; fi
    if have wget; then wget -q --spider --timeout=20 "$1" 2>/dev/null && return 0; fi
    return 0   # no check tool: just try
}

do_download() { # $1=URL $2=target
    local url="$1" out="$2" lg="$ADDON_LOG"
    # Before the prefix is created (portable Wine) its directory does not exist yet
    [ -d "$(dirname "$lg")" ] || lg="$CACHE_DIR/download.log"
    rm -f "$out.part"
    if have curl; then
        curl -fL --connect-timeout 20 --retry 2 -o "$out.part" "$url" >>"$lg" 2>&1
    elif have wget; then
        wget -T 25 -O "$out.part" "$url" >>"$lg" 2>&1
    elif have python3; then
        python3 -c 'import sys,urllib.request;urllib.request.urlretrieve(sys.argv[1],sys.argv[2])' \
            "$url" "$out.part" >>"$lg" 2>&1
    else
        warn "  neither curl nor wget nor python3 available — download not possible"
        return 1
    fi
    if [ -s "$out.part" ]; then mv "$out.part" "$out"; return 0; fi
    rm -f "$out.part"; return 1
}

listing_latest() {
    local html=""
    if have curl; then html=$(curl -sfL --connect-timeout 15 "$1" 2>/dev/null)
    elif have wget; then html=$(wget -qO- --timeout=20 "$1" 2>/dev/null)
    elif have python3; then
        html=$(python3 -c 'import sys,urllib.request;print(urllib.request.urlopen(sys.argv[1],timeout=20).read().decode("utf8","ignore"))' "$1" 2>/dev/null)
    fi
    printf '%s' "$html" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1
}

# ---------------------------------------------------------------- 1a) portable Wine (optional)
# For systems whose Wine is too old (CSP 5 needs >= 11.19) and where an update is not possible.
# Download + unpack directly on the target machine -> no need to transport symlinks.
WINE_EXE="wine"
# Automatic: prefix with a noted portable Wine -> use that one again.
# Otherwise: system Wine missing or older than $WINE_MIN -> download portable Wine.
if [ "$WINE_PORTABLE" = 0 ] && [ -z "$WINE_BIN" ]; then
    noted="$(cat "$PREFIX/portable-wine-path" 2>/dev/null || true)"
    if [ "$SYSTEM_WINE" = 0 ] && [ -n "$noted" ] && [ -x "$noted/wine" ]; then
        WINE_BIN="$noted"
        ok "using the Wine noted in the prefix: $noted"
    elif [ "$SYSTEM_WINE" = 0 ]; then
        sysver="$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
        reason=""
        if [ -z "$sysver" ]; then
            reason="no system Wine found"
        elif [ "$(printf '%s\n%s\n' "$WINE_MIN" "$sysver" | sort -V | head -1)" != "$WINE_MIN" ]; then
            reason="system Wine $sysver is older than $WINE_MIN (CSP 5 crashes with it)"
        fi
        if [ -n "$reason" ]; then
            log "$reason -> using portable Wine $WINE_PORTABLE_VER automatically (--system-wine prevents that)"
            WINE_PORTABLE=1
        fi
    fi
fi
if [ "$WINE_PORTABLE" = 1 ]; then
    log "1a/6 getting portable Wine (version $WINE_PORTABLE_VER)"
    mkdir -p "$WINE_PORTABLE_DIR"

    # already unpacked?
    PORT_DIR="$(find "$WINE_PORTABLE_DIR" -maxdepth 1 -type d -name "wine-$WINE_PORTABLE_VER-*" 2>/dev/null | head -1)"
    if [ -n "$PORT_DIR" ] && [ -x "$PORT_DIR/bin/wine" ]; then
        ok "already present: $PORT_DIR"
    elif [ "$CHECK_ONLY" = 1 ]; then
        warn "would download + unpack portable Wine $WINE_PORTABLE_VER to $WINE_PORTABLE_DIR"
    else
        # tarball: local (bundle, downloads, cache) or download
        variants="wine-$WINE_PORTABLE_VER-staging-amd64-wow64.tar.xz wine-$WINE_PORTABLE_VER-staging-amd64.tar.xz wine-$WINE_PORTABLE_VER-amd64-wow64.tar.xz"
        base="https://github.com/Kron4ek/Wine-Builds/releases/download/$WINE_PORTABLE_VER"
        tarball=""
        for v in $variants; do
            tarball=$(find_local_msi "$v") && break || tarball=""
        done
        if [ -z "$tarball" ]; then
            for v in $variants; do
                url="$base/$v"
                if url_ok "$url"; then
                    log "  downloading $v (~100 MB) …"
                    do_download "$url" "$CACHE_DIR/$v" && { tarball="$CACHE_DIR/$v"; break; }
                fi
            done
        else
            log "  using existing file: $(basename "$tarball")"
        fi
        [ -n "$tarball" ] || die "portable Wine: download failed (download manually: $base/)"

        # verify SHA256 (best effort: sha256sums.txt from the same release)
        if command -v sha256sum >/dev/null 2>&1; then
            sums="$CACHE_DIR/sha256sums-$WINE_PORTABLE_VER.txt"
            [ -f "$sums" ] || do_download "$base/sha256sums.txt" "$sums" || true
            if [ -f "$sums" ]; then
                want=$(grep -E "[ *]$(basename "$tarball")\$" "$sums" | awk '{print $1}' | head -1)
                have=$(sha256sum "$tarball" | awk '{print $1}')
                if [ -n "$want" ] && [ "$want" = "$have" ]; then
                    ok "SHA256 verified"
                elif [ -n "$want" ]; then
                    rm -f "$tarball"
                    die "SHA256 check failed — download discarded, please try again"
                fi
            fi
        fi

        # check free space (~1 GB unpacked)
        freekb=$(df -Pk "$WINE_PORTABLE_DIR" 2>/dev/null | awk 'NR==2{print $4}')
        if [ -n "$freekb" ] && [ "$freekb" -lt 1500000 ]; then
            die "not enough space in $WINE_PORTABLE_DIR (needs ~1 GB free, available: $((freekb/1024)) MB)"
        fi
        command -v tar >/dev/null 2>&1 || die "tar not found"
        log "  unpacking $(basename "$tarball") …"
        tar -xf "$tarball" -C "$WINE_PORTABLE_DIR" || die "unpacking failed (xz support installed?)"
        PORT_DIR="$(find "$WINE_PORTABLE_DIR" -maxdepth 1 -type d -name "wine-$WINE_PORTABLE_VER-*" 2>/dev/null | head -1)"
        [ -n "$PORT_DIR" ] && [ -x "$PORT_DIR/bin/wine" ] || die "unpacked Wine not found in $WINE_PORTABLE_DIR"
        ok "portable Wine: $PORT_DIR"
    fi
    [ -n "$PORT_DIR" ] && WINE_BIN="$PORT_DIR/bin"
fi

echo "csp-linux-bundle $VERSION"
echo "Prefix: $PREFIX"
echo

# ---------------------------------------------------------------- 1) Prerequisites
log "1/6 checking prerequisites"
if [ -n "$WINE_BIN" ]; then
    [ -x "$WINE_BIN/wine" ] || die "Wine not executable: '$WINE_BIN/wine'"
    export PATH="$WINE_BIN:$PATH"
    WINE_EXE="$WINE_BIN/wine"
    ok "using own Wine: $WINE_BIN ($("$WINE_EXE" --version 2>/dev/null))"
fi
export WINE_EXE
command -v wine >/dev/null 2>&1 || die "wine not found (e.g. 'sudo pacman -S wine' or 'sudo apt install wine')"
WINEVER="$(wine --version 2>/dev/null || true)"
[ -n "$WINEVER" ] || die "'wine --version' failed — check the wine installation"
ok "wine: $WINEVER"
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "Neither \$DISPLAY nor \$WAYLAND_DISPLAY is set — CSP needs a graphical session."
fi
# CSP 5 uses WinRT (RadialController/Storage). If the class is missing in the Wine installation,
# the editor crashes immediately (NULL deref in triglavwinrt.dll).
# NOTE: A string search in windows.ui.dll is NOT reliable (Wine 11.0 contains the name but
# does not register the class) -> that is why the bundled probe tool is used.
winrt_radial_ok() {   # only meaningful once the prefix exists
    local out
    [ -f "$FILES/winrt-probe.exe" ] || return 0
    out=$(WINEPREFIX="$PREFIX" "$WINE_EXE" "$FILES/winrt-probe.exe" 2>/dev/null) || true
    case "$out" in
        *"0 missing"*) return 0 ;;
        *"missing"*)   return 1 ;;
        *)             return 0 ;;
    esac
}

[ -f "$FILES/wintab32.dll" ]         || die "Package incomplete: files/wintab32.dll missing"
[ -f "$FILES/XWinTabHelper.dll.so" ] || die "Package incomplete: files/XWinTabHelper.dll.so missing"
ok "pen pressure fix files present"

export WINEPREFIX="$PREFIX"

# ---------------------------------------------------------------- 2) Prefix
log "2/6 Wine prefix"
if [ -d "$PREFIX" ]; then
    ok "prefix exists: $PREFIX"
else
    if [ "$CHECK_ONLY" = 1 ]; then
        warn "prefix missing (would be created): $PREFIX"
    else
        log "  creating (WINEARCH=win64) …"
        WINEARCH=win64 WINEBOOT_BIN="$(dirname "$WINE_EXE")/wineboot"; [ -x "$WINEBOOT_BIN" ] || WINEBOOT_BIN=wineboot; "$WINEBOOT_BIN" -u >/dev/null 2>&1 || die "wineboot failed"
        ok "prefix created"
    fi
fi

PAINTDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT"
PAINT_EXE="$PAINTDIR/CLIPStudioPaint.exe"
HUBDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO"

# Note the own/portable Wine in the prefix -> verify.sh and the start scripts use it automatically
if [ "$WINE_EXE" != "wine" ] && [ -d "$PREFIX/drive_c" ] && [ "$CHECK_ONLY" = 0 ]; then
    printf '%s\n' "$(dirname "$WINE_EXE")" > "$PREFIX/portable-wine-path"
    ok "Wine path noted in the prefix: $PREFIX/portable-wine-path"
fi

# Check this Wine version's WinRT capability (probe tool; see above)
if [ -d "$PREFIX/drive_c" ]; then
    if winrt_radial_ok; then
        ok "Wine provides the WinRT classes CSP 5 needs"
    else
        warn "WARNING: this Wine version does NOT provide the WinRT classes CSP 5 needs"
        warn "  (Windows.UI.Input.RadialController, Windows.Storage.StorageFile)."
        warn "  Consequence: CSP crashes when opening the editor (NULL deref in triglavwinrt.dll)."
        warn "  Solutions without a system installation:"
        warn "   1) Portable Wine (tested: 11.19): unpack a Wine-Staging tarball from"
        warn "      https://github.com/Kron4ek/Wine-Builds/releases and use"
        warn "      ./install.sh --wine-bin <unpacked>/bin ..."
        warn "   2) Update system Wine (>= 11.19; Fedora: 'sudo dnf upgrade wine-staging')"
        warn "  (Proton does not help: GE-Proton 8/9 = Wine 8/9 — also too old.)"
        warn "  Counter-check:  wine \"$FILES/winrt-probe.exe\"   (expected: 5 x OK)"
    fi
fi

# ---------------------------------------------------------------- 2b) Wine addons + dcomp
log "2b/6 Wine addons (Gecko/Mono) + dcomp (WebView2)"

# System-wide addons (Arch/Fedora ship them as a package: /usr/share/wine/{mono,gecko})
# Wine uses these trees DIRECTLY — e.g. mshtml: load_gecko() looks in
#   <datadir>/wine/gecko/wine-gecko-<ver>-<arch>, /opt/wine/gecko/… , $WINEDATADIR/gecko/…
# and mscoree: get_mono_path() likewise under …/mono/wine-mono-<ver>. Only if nothing is
# found there does Wine install from an MSI (dlls/appwiz.cpl/addons.c, searches the same
# directories + ~/.cache/wine, otherwise download). The distro package really saves the download.
if [ -d /usr/share/wine/mono ] || [ -d /usr/share/wine/gecko ]; then
    log "  system addons found under /usr/share/wine (Wine uses them without a download):"
    for d in /usr/share/wine/gecko/*/ /usr/share/wine/mono/*/; do
        [ -d "$d" ] && log "    $(basename "$d")"
    done
fi

# ---- addon versions expected by THIS Wine version (appwiz.cpl) -------------------
find_appwiz() {
    local c w
    w="$(command -v wine 2>/dev/null || echo /usr/bin/wine)"
    for c in \
        "$(dirname "$w")/../lib64/wine/x86_64-windows/appwiz.cpl" \
        "$(dirname "$w")/../lib/wine/x86_64-windows/appwiz.cpl" \
        /usr/lib64/wine/x86_64-windows/appwiz.cpl \
        /usr/lib/wine/x86_64-windows/appwiz.cpl \
        /usr/lib/x86_64-linux-gnu/wine/x86_64-windows/appwiz.cpl \
        /opt/wine*/lib64/wine/x86_64-windows/appwiz.cpl \
        /opt/wine*/lib/wine/x86_64-windows/appwiz.cpl \
        /app/lib/wine/x86_64-windows/appwiz.cpl; do
        [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
    if have find; then
        c=$(timeout 25 find /usr /opt /app -maxdepth 7 -name appwiz.cpl -path '*x86_64-windows*' 2>/dev/null | head -1)
        [ -n "$c" ] && { printf '%s' "$c"; return 0; }
    fi
    return 1
}

GECKO_VER="${GECKO_VER:-}"; MONO_VER="${MONO_VER:-}"
if APPWIZ="$(find_appwiz)"; then
    if have strings; then
        [ -z "$GECKO_VER" ] && GECKO_VER="$(strings "$APPWIZ" 2>/dev/null | grep -oE '^2\.[0-9]+\.[0-9]+$' | head -1)"
        [ -z "$MONO_VER" ]  && MONO_VER="$(strings "$APPWIZ" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^2\.' | head -1)"
    fi
    log "  Wine: $("$WINE_EXE" --version 2>/dev/null) expects Gecko ${GECKO_VER:-?} / Mono ${MONO_VER:-?}"
else
    warn "appwiz.cpl not found — addon versions unknown (Wine can still ask for them itself)"
fi

# ---- installed versions ------------------------------------------------------------
gecko_ver_installed() { # version from the prefix OR from a system package
    # prefix:  …/system32/gecko/<ver>/wine_gecko/xul.dll
    # system:  /usr/share/wine/gecko/wine-gecko-<ver>-<arch>/  (Wine loads it directly)
    local d
    {
        for d in "$PREFIX/drive_c/windows/system32/gecko/"[0-9]*; do
            [ -f "$d/wine_gecko/xul.dll" ] || continue
            basename "$d"
        done
        for d in /usr/share/wine/gecko/wine-gecko-*/ /opt/wine/gecko/wine-gecko-*/; do
            [ -d "$d" ] || continue
            d=$(basename "${d%/}")
            printf '%s\n' "${d#wine-gecko-}" | sed 's/-[^-]*$//'
        done
    } | sort -V | tail -1
}
mono_ver_installed() { # DisplayVersion from the prefix OR from a system package
    local d
    {
        have awk && awk -v RS='' 'index($0,"Wine Mono Runtime") && match($0,/"DisplayVersion"="[^"]+"/) {
            s=substr($0,RSTART,RLENGTH); gsub(/.*="|"$/,"",s); print s; exit }' \
            "$PREFIX/system.reg" 2>/dev/null
        for d in /usr/share/wine/mono/wine-mono-*/ /opt/wine/mono/wine-mono-*/; do
            [ -d "$d" ] || continue
            d=$(basename "${d%/}")
            printf '%s\n' "${d#wine-mono-}"
        done
    } | sort -V | tail -1
}

# ---- install an addon (version-aware) -----------------------------------------------
install_addon() { # 1=name 2=glob 3=URL template 4=directory URL 5=wanted version 6=installed version 7=marker function
    local name="$1" glob="$2" tmpl="$3" listing="$4" want="$5" got="$6" mark="$7" msi="" url=""
    mkurl() { printf "$tmpl" "$1" "$1"; }

    if [ -n "$want" ] && [ "$got" = "$want" ]; then ok "$name $got installed"; return 0; fi
    if [ -n "$got" ]; then
        warn "$name: installed is $got, Wine expects ${want:-?} — installing the matching version"
    fi
    if [ "$CHECK_ONLY" = 1 ]; then
        warn "$name ${want:+$want }missing/wrong (would be installed)"; return 0
    fi

    # 1) local file (prefer the matching version)
    [ -n "$want" ] && msi=$(find_local_msi "${glob//\*/$want}") || msi=""
    [ -z "$msi" ] && { msi=$(find_local_msi "$glob") || msi=""; }
    if [ -n "$msi" ]; then
        log "  using existing file: $(basename "$msi")"
    else
        [ -n "$want" ] && url="$(mkurl "$want")" || url=""
        if [ -z "$url" ] || ! url_ok "$url"; then
            local newer; newer=$(listing_latest "$listing")
            if [ -n "$newer" ] && [ "$newer" != "$want" ]; then
                warn "  version ${want:-?} not reachable — trying $newer (Wine may still expect ${want:-?})"
                url="$(mkurl "$newer")"
            fi
        fi
        if [ -n "$url" ]; then
            log "  downloading $(basename "$url") …"
            do_download "$url" "$CACHE_DIR/$(basename "$url")" && msi="$CACHE_DIR/$(basename "$url")"
        fi
    fi

    if [ -z "$msi" ]; then
        warn "$name: acquisition failed (details: $ADDON_LOG)"
        warn "  -> offline: put the MSI matching Wine ${want:-?} from $listing next to this script (or --addon-msi-dir)"
        warn "  -> or click \"Install\" in the Wine dialog on first start (needs internet)"
        return 1
    fi

    log "  installing $(basename "$msi") …"
    if "$WINE_EXE" msiexec /i "$msi" >>"$ADDON_LOG" 2>&1; then
        local now; now=$($mark)
        if [ -z "$want" ] || [ "$now" = "$want" ]; then ok "$name ${now} installed"; else
            warn "$name: installed is now $now${want:+, Wine expects $want} (log: $ADDON_LOG)"
        fi
    else
        warn "$name: msiexec installation failed (log: $ADDON_LOG)"
        return 1
    fi
}

if [ "$DO_ADDONS" = 1 ]; then
    install_addon "Wine Gecko (MSHTML/IE-UI)" "wine-gecko-*-x86_64.msi" \
        "https://dl.winehq.org/wine/wine-gecko/%s/wine-gecko-%s-x86_64.msi" \
        "https://dl.winehq.org/wine/wine-gecko/" "$GECKO_VER" "$(gecko_ver_installed)" gecko_ver_installed || true
    install_addon "Wine Mono (.NET)" "wine-mono-*-x86.msi" \
        "https://dl.winehq.org/wine/wine-mono/%s/wine-mono-%s-x86.msi" \
        "https://dl.winehq.org/wine/wine-mono/" "$MONO_VER" "$(mono_ver_installed)" mono_ver_installed || true
else
    warn "Addons skipped (--no-addons)"
fi

# ---- dcomp shim: makes the WebView2 panels (Hub/login/settings) render ------------
# Source: CSPenguin-Installer (parka6060), pinned commit. The upstream repo has no
# license file, so we ship neither its sources nor DLLs.
# Only OUR patch is shipped (files/src/dcomp-csp-linux.patch): it makes the Hub usable
# under Wine 11.x (content stays put, clicks update the picture).
# Flow: download upstream source (SHA256 pinned) -> patch -> build with mingw-w64.
# Without mingw-w64 fall back to the unmodified upstream DLL (Hub content then patchy).
DCOMP_BASE="https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/868d022adfdc3740449241f4721debbf4b1b1426/patches/dcomp"
DCOMP_SRC_SHA="e516fd33b7da2452a90b96a9bbb42920564afd1a91d4ba629cad34acfb0cc83a"   # dcomp_csp.cpp
DCOMP_DEF_SHA="319c1a01d6ca059c5127f62a4a6250ccead3af8ae1f4b335b7c2b1f7fe8b4e92"   # dcomp.def
DCOMP_PATCH="$HERE/files/src/dcomp-csp-linux.patch"
DCOMP_MARK="csp-linux rev2"    # text that only occurs in the current patched DLL
DCOMP_MARK_OLD="Present->target"   # patched but outdated (v0.1.13: native Hub dialogs not clickable)
DCOMP_CXX="x86_64-w64-mingw32-g++"
DCOMP_DIRS=()
[ -n "$DCOMP_DIR" ] && DCOMP_DIRS+=("$DCOMP_DIR" "$DCOMP_DIR/patches/dcomp")
DCOMP_DIRS+=("$HERE" "$HERE/dcomp" "$HERE/patches/dcomp" "$PWD" "$PWD/patches/dcomp" "$HOME/Downloads")

find_dcomp_file() { # $1 = file name
    local d f
    for d in "${DCOMP_DIRS[@]}"; do
        [ -d "$d" ] || continue
        f="$d/$1"; [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

dcomp_is_patched() { [ -f "$1" ] && grep -aq "$DCOMP_MARK" "$1" 2>/dev/null; }
dcomp_is_outdated() { [ -f "$1" ] && grep -aq "$DCOMP_MARK_OLD" "$1" 2>/dev/null; }

dcomp_installed() { [ -f "$PREFIX/drive_c/windows/system32/dcomp.dll" ]; }

# Build the patched shim. Prints the path of the finished DLL; return 1 = not possible.
build_patched_dcomp() {
    have "$DCOMP_CXX" || { echo "  mingw-w64 ($DCOMP_CXX) missing" >>"$ADDON_LOG"; return 1; }
    have patch        || { echo "  'patch' missing" >>"$ADDON_LOG"; return 1; }
    [ -f "$DCOMP_PATCH" ] || { echo "  $DCOMP_PATCH missing" >>"$ADDON_LOG"; return 1; }
    local bd="$CACHE_DIR/dcomp-build" f want src
    rm -rf "$bd"; mkdir -p "$bd" || return 1
    for f in dcomp_csp.cpp dcomp.def; do
        [ "$f" = dcomp_csp.cpp ] && want="$DCOMP_SRC_SHA" || want="$DCOMP_DEF_SHA"
        # use a local copy only if it matches the pinned state exactly
        if src=$(find_dcomp_file "$f") && [ "$(sha256sum "$src" | awk '{print $1}')" = "$want" ]; then
            cp "$src" "$bd/$f"
        else
            do_download "$DCOMP_BASE/$f" "$bd/$f" || return 1
        fi
        if [ "$(sha256sum "$bd/$f" | awk '{print $1}')" != "$want" ]; then
            echo "  $f: SHA256 does not match the pinned upstream state" >>"$ADDON_LOG"; return 1
        fi
    done
    patch -s -p1 -d "$bd" dcomp_csp.cpp <"$DCOMP_PATCH" >>"$ADDON_LOG" 2>&1 || return 1
    "$DCOMP_CXX" -shared -static -O2 -std=c++17 -o "$bd/dcomp.dll" \
        "$bd/dcomp_csp.cpp" "$bd/dcomp.def" \
        -lole32 -lgdi32 -luser32 -ldxgi -ld3d11 -luuid >>"$ADDON_LOG" 2>&1 || return 1
    dcomp_is_patched "$bd/dcomp.dll" || return 1
    printf '%s' "$bd/dcomp.dll"
}

if [ "$DO_DCOMP" = 1 ]; then
    SYS32="$PREFIX/drive_c/windows/system32"
    if dcomp_is_patched "$SYS32/dcomp.dll"; then
        ok "dcomp shim (patched, WebView2 panels) installed"
    elif [ "$CHECK_ONLY" = 1 ]; then
        if dcomp_is_outdated "$SYS32/dcomp.dll"; then warn "dcomp shim is the outdated v0.1.13 patch (would be replaced)"
        elif dcomp_installed; then warn "dcomp shim is the unpatched upstream version (would be replaced)"
        else warn "dcomp shim missing (would be installed)"; fi
    else
        log "  building dcomp shim (upstream source + patch) …"
        dll="" pth="" patched=0
        if dll=$(build_patched_dcomp); then
            patched=1
        else
            dll=""
            warn "dcomp shim could not be built (details: $ADDON_LOG)"
            warn "  -> install mingw-w64 and run ./install.sh again:"
            warn "     Arch: sudo pacman -S mingw-w64-gcc   Debian/Ubuntu: sudo apt install g++-mingw-w64-x86-64"
            warn "     Fedora: sudo dnf install mingw64-gcc-c++"
            if dcomp_installed; then
                if dcomp_is_outdated "$SYS32/dcomp.dll"; then
                    warn "  -> keeping the existing v0.1.13 dcomp.dll (settings in the Hub then not clickable)"
                else
                    warn "  -> keeping the existing (unpatched) dcomp.dll"
                fi
            else
                warn "  -> fallback: unmodified upstream DLL (Hub content stays patchy)"
                dll=$(find_dcomp_file dcomp.dll) || dll=""
                pth=$(find_dcomp_file libwinpthread-1.dll) || pth=""
                if [ -z "$dll" ]; then
                    do_download "$DCOMP_BASE/dcomp.dll" "$CACHE_DIR/dcomp.dll" && dll="$CACHE_DIR/dcomp.dll"
                fi
                if [ -z "$pth" ]; then
                    do_download "$DCOMP_BASE/libwinpthread-1.dll" "$CACHE_DIR/libwinpthread-1.dll" && pth="$CACHE_DIR/libwinpthread-1.dll"
                fi
                [ -n "$pth" ] || dll=""   # the upstream DLL needs libwinpthread
            fi
        fi
        if [ -n "$dll" ]; then
            [ -n "$pth" ] && cp "$pth" "$SYS32/libwinpthread-1.dll"
            cp "$dll" "$SYS32/dcomp.dll"
            # additionally into the app directories (DLL search order: they come before system32)
            [ -d "$PAINTDIR" ] && cp "$dll" "$PAINTDIR/dcomp.dll"
            [ -d "$HUBDIR" ]   && cp "$dll" "$HUBDIR/dcomp.dll"
            if "$WINE_EXE" reg add 'HKCU\Software\Wine\DllOverrides' /v dcomp /t REG_SZ /d 'native,builtin' /f >>"$ADDON_LOG" 2>&1; then
                if [ "$patched" = 1 ]; then ok "dcomp shim built + installed (patched: Hub content + clicks)"
                else ok "dcomp shim installed (unpatched)"; fi
            else
                warn "dcomp shim copied, but DllOverride failed"
            fi
        elif ! dcomp_installed; then
            warn "dcomp shim: neither build nor download possible (details: $ADDON_LOG)"
            warn "  -> alternative: ./install.sh --dcomp-dir /path/to/CSPenguin-Installer"
            warn "  -> or leave it out; then WebView2 panels (Hub/settings) may stay white"
        fi
    fi
else
    warn "dcomp shim skipped (--no-dcomp)"
fi

# ---- GPU path: DXVK + VKD3D (like CSPenguin) ------------------------------------
# Why: on some systems (especially AMD/radv) the WebView2 panels (Hub centre, settings,
# login) only render cleanly through the GPU path. With Wine's own d3d/GL route parts of
# the overlay stay black/empty even though the dcomp shim is active.
# Tested on the Arch reference machine (Intel UHD, Mesa): editor and panels render.
DXVK_CONF="$PREFIX/dxvk.conf"
dxvk_installed() {   # winetricks only logs the verb names
    grep -qx 'dxvk'   "$PREFIX/winetricks.log" 2>/dev/null && return 0
    grep -qx 'vkd3d'  "$PREFIX/winetricks.log" 2>/dev/null && return 0
    return 1
}
dxvk_native_ok() {   # native DLLs are much larger than Wine's builtins (~1.3 MB vs ~200 KB)
    local f=$(stat -c%s "$PREFIX/drive_c/windows/system32/d3d11.dll" 2>/dev/null || echo 0)
    [ "$f" -gt 1000000 ]
}

if [ "$DO_DXVK" = 1 ]; then
    if dxvk_installed && dxvk_native_ok; then
        ok "DXVK/VKD3D (GPU path) already installed"
    elif [ "$CHECK_ONLY" = 1 ]; then
        warn "DXVK/VKD3D missing (would be installed via winetricks)"
    elif ! have winetricks; then
        warn "winetricks not found -> GPU path skipped"
        warn "  -> catch up later: install winetricks, then './install.sh --no-csp'"
        warn "  -> or leave it out; the WebView2 panels may then stay black/empty"
    else
        log "  winetricks -q dxvk vkd3d  (downloads ~15 MB, changes DllOverrides) …"
        if WINEPREFIX="$PREFIX" winetricks -q dxvk vkd3d >>"$ADDON_LOG" 2>&1; then
            ok "DXVK/VKD3D installed (native d3d9/d3d11/d3d12/dxgi)"
        else
            warn "DXVK/VKD3D installation failed (details: $ADDON_LOG)"
            warn "  -> manually: WINEPREFIX=\"$PREFIX\" winetricks -q dxvk vkd3d"
        fi
    fi

    # dxvk.conf: same values as in the CSPenguin installer (WebView2 needs the deferred
    # surface creation, otherwise the overlay does not come up).
    if [ "$CHECK_ONLY" = 0 ] && [ ! -f "$DXVK_CONF" ]; then
        cat > "$DXVK_CONF" <<'EOF'
# csp-linux-bundle — DXVK configuration (loaded by run-csp.sh via DXVK_CONFIG_FILE)
# Values taken from the CSPenguin installer (parka6060); needed for the WebView2 panels.
dxgi.deferSurfaceCreation = True
dxvk.enableGraphicsPipelineLibrary = True
dxvk.numCompilerThreads = 0
dxvk.maxChunkSize = 16
EOF
        ok "DXVK configuration written: $DXVK_CONF"
    fi
else
    warn "GPU path (DXVK/VKD3D) skipped (--no-dxvk)"
fi

# ---------------------------------------------------------------- 3) Install CSP
log "3/6 CLIP STUDIO PAINT"
if [ -f "$PAINT_EXE" ]; then
    ok "CSP already installed"
elif [ "$DO_CSP" = 0 ]; then
    warn "CSP not found and --no-csp set → the pen pressure fix cannot be installed"
else
    CSP_NAME="CSP_${CSP_VERSION}w_setup.exe"
    CSP_URL="https://vd.clipstudio.net/clipcontent/paint/app/$CSP_VERSION/$CSP_NAME"
    if [ -z "$INSTALLER" ]; then
        for c in "$HERE"/CSP_*setup.exe "$HOME/Downloads"/CSP_*setup.exe "$HOME"/CSP_*setup.exe "$PWD"/CSP_*setup.exe "$CACHE_DIR/$CSP_NAME"; do
            [ -f "$c" ] && INSTALLER="$c" && break
        done
    fi
    if [ -z "$INSTALLER" ] && [ "$CHECK_ONLY" = 1 ]; then
        warn "no CSP installer found -> would download $CSP_NAME from CELSYS ($CSP_URL)"
    elif [ -z "$INSTALLER" ]; then
        [ "$CSP_VERSION" = 504 ] || warn "CSP version $CSP_VERSION is untested with this package (tested: 504 = 5.0.4)"
        freekb=$(df -Pk "$CACHE_DIR" 2>/dev/null | awk 'NR==2{print $4}')
        if [ -n "$freekb" ] && [ "$freekb" -lt 700000 ]; then
            die "not enough space in $CACHE_DIR for the CSP installer (~470 MB)"
        fi
        log "  no CSP installer found -> downloading $CSP_NAME from CELSYS (~470 MB) …"
        if have curl; then
            curl -fL --connect-timeout 20 --retry 2 --progress-bar -o "$CACHE_DIR/$CSP_NAME.part" "$CSP_URL" \
                && mv "$CACHE_DIR/$CSP_NAME.part" "$CACHE_DIR/$CSP_NAME"
        else
            do_download "$CSP_URL" "$CACHE_DIR/$CSP_NAME"
        fi
        [ -f "$CACHE_DIR/$CSP_NAME" ] || {
            warn "Download failed: $CSP_URL"
            warn "  -> download the installer yourself (https://www.clipstudio.net/) and put it next to this script"
            warn "     OR  --installer /path/$CSP_NAME"
            die "CSP installer missing"
        }
        if [ "$CSP_VERSION" = 504 ] && have sha256sum; then
            if [ "$(sha256sum "$CACHE_DIR/$CSP_NAME" | awk '{print $1}')" = "$CSP_SHA_504" ]; then
                ok "CSP installer downloaded, SHA256 verified: $CACHE_DIR/$CSP_NAME"
            else
                rm -f "$CACHE_DIR/$CSP_NAME"
                die "CSP installer: SHA256 does not match — download discarded, please try again"
            fi
        else
            ok "CSP installer downloaded (no hash check): $CACHE_DIR/$CSP_NAME"
        fi
        INSTALLER="$CACHE_DIR/$CSP_NAME"
    fi
    [ -z "$INSTALLER" ] || [ -f "$INSTALLER" ] || die "CSP installer not found: $INSTALLER"
    if [ -z "$INSTALLER" ]; then
        :   # --check only: the download was announced above
    elif [ "$CHECK_ONLY" = 1 ]; then
        warn "CSP would be installed (silent) from: $INSTALLER"
    else
        log "  silent installation starting — this takes a few minutes (a window appears briefly) …"
        "$WINE_EXE" "$INSTALLER" -s >"$PREFIX/install-csp.log" 2>&1 || warn "Installer exit code != 0 (log: $PREFIX/install-csp.log)"
        for _ in $(seq 1 120); do [ -f "$PAINT_EXE" ] && break; sleep 5; done
        [ -f "$PAINT_EXE" ] || die "CSP EXE not found after installation — check the log: $PREFIX/install-csp.log"
        ok "CSP installed: $PAINTDIR"
    fi
fi

# ---------------------------------------------------------------- 4) Pen pressure fix
log "4/6 installing the pen pressure fix"
if [ -d "$PAINTDIR" ]; then
    if [ "$CHECK_ONLY" = 1 ]; then
        warn "would install: wintab32.dll + XWinTabHelper.dll.so + device name -> $PAINTDIR"
    else
        cp "$FILES/wintab32.dll"         "$PAINTDIR/"
        cp "$FILES/XWinTabHelper.dll.so" "$PAINTDIR/"
        cp "$FILES/LICENSE-WineTab.txt"  "$PAINTDIR/" 2>/dev/null || true
        cp "$FILES/NOTICE-WineTab.txt"   "$PAINTDIR/" 2>/dev/null || true
        cp "$FILES/t5w.exe"              "$PAINTDIR/" 2>/dev/null || true

        # Determine the device name for WTInfo(WTI_DEVICES, DVC_NAME) -> sidecar file next
        # to the DLL. The DLL reads it on the first DVC_NAME call; without it it reports
        # the placeholder "XWayland Tablet (XWinTab/XI2)".
        DEVNAME="${XWINTAB_DEVICE_NAME:-}"
        if [ -z "$DEVNAME" ] && [ -f "$FILES/xi2-devname.c" ] && have gcc \
           && pkg-config --exists x11 xi 2>/dev/null; then
            TMPD=""; TMPD=$(mktemp -d 2>/dev/null) || TMPD=""
            if [ -n "$TMPD" ]; then
                gcc -O2 "$FILES/xi2-devname.c" -o "$TMPD/xi2-devname" -lX11 -lXi 2>/dev/null \
                    && DEVNAME=$("$TMPD/xi2-devname" 2>/dev/null || true)
                rm -rf "$TMPD"
            fi
        fi
        if [ -n "$DEVNAME" ]; then
            printf '%s\n' "$DEVNAME" > "$PAINTDIR/XWinTabDeviceName.txt"
            ok "device name for WTInfo(DVC_NAME): \"$DEVNAME\""
        else
            warn "could not determine the device name (tablet not connected? gcc/libX11+libXi missing?)"
            warn "  WTInfo(DVC_NAME) therefore reports the placeholder. Catch up with:"
            warn "    XWINTAB_DEVICE_NAME=\"<name>\" ./install.sh --no-csp      (or put the file next to the DLL)"
        fi

        if "$WINE_EXE" reg add 'HKCU\Software\Wine\DllOverrides' /v wintab32 /t REG_SZ /d native /f >/dev/null 2>&1; then
            ok "DLLs copied + Wine override 'wintab32=native' set"
        else
            warn "could not set the DllOverride — please check manually:"
            warn "  WINEPREFIX=\"$PREFIX\" wine reg add 'HKCU\\Software\\Wine\\DllOverrides' /v wintab32 /t REG_SZ /d native /f"
        fi
    fi
else
    warn "CSP app directory missing — fix skipped: $PAINTDIR"
fi

# ---------------------------------------------------------------- 5) Menu entries
# The entries do NOT start "wine CLIPStudio.exe" directly but run-csp.sh — only that sets
# the WebView2 arguments (--in-process-gpu, one-renderer mode), the User-Agent, the GPU
# path and dismisses the "not closed properly" dialog; it also picks the right (possibly
# portable) Wine. So that the entries keep working after the unpacked bundle is deleted,
# a copy of the launcher lives in the prefix: <prefix>/csp-launcher/.
log "5/6 menu entries"
LAUNCH_DIR="$PREFIX/csp-launcher"
if [ "$CREATE_SHORTCUTS" = 1 ] && [ "$CHECK_ONLY" = 0 ]; then
    APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications/wine/Programs"
    ICONDIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
    mkdir -p "$APPDIR" "$LAUNCH_DIR/files"

    if [ -f "$HERE/run-csp.sh" ] && [ -f "$FILES/xdlg.c" ]; then
        cp "$HERE/run-csp.sh" "$LAUNCH_DIR/run-csp.sh" && chmod +x "$LAUNCH_DIR/run-csp.sh"
        cp "$FILES/xdlg.c" "$LAUNCH_DIR/files/xdlg.c"
        ok "launcher installed: $LAUNCH_DIR/run-csp.sh"
    else
        warn "run-csp.sh/files/xdlg.c missing from the package — entries start without the fixes"
    fi

    # Exec line according to the Desktop Entry spec: arguments in "…", escape \ " $ ` inside
    dq() { local x="$1"; x="${x//\\/\\\\}"; x="${x//\"/\\\"}"; x="${x//\$/\\$}"; x="${x//\`/\\\`}"; printf '"%s"' "$x"; }

    write_desktop() { # $1=file  $2=name  $3=mode(editor|hub)  $4=icon  $5=wmclass  $6=comment
        cat > "$APPDIR/$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$6
Exec=$(dq "$LAUNCH_DIR/run-csp.sh") $3 --prefix $(dq "$PREFIX")
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;
Icon=$4
StartupWMClass=$5
EOF
    }

    # Extract icons from the EXEs (Wine's own icon names are hashes and often missing)
    icon_for() { # $1=exe  $2=name  -> prints the icon name (or a fallback)
        if [ -f "$1" ] && have python3 && python3 -I "$FILES/extract-icon.py" "$1" "$ICONDIR" "$2" >/dev/null 2>&1; then
            printf '%s' "$2"
        else
            printf '%s' "applications-graphics"
        fi
    }

    if [ -f "$PAINT_EXE" ]; then
        ICON_PAINT="$(icon_for "$PAINT_EXE" csp-linux-clipstudiopaint)"
        write_desktop "CLIP STUDIO PAINT.desktop" "CLIP STUDIO PAINT" editor "$ICON_PAINT" \
            "clipstudiopaint.exe" "CLIP STUDIO PAINT with the Linux fixes (pen pressure, GPU path, WebView2)"
        ok 'entry "CLIP STUDIO PAINT" (editor, recommended) -> run-csp.sh'
    fi
    if [ -f "$HUBDIR/CLIPStudio.exe" ]; then
        ICON_HUB="$(icon_for "$HUBDIR/CLIPStudio.exe" csp-linux-clipstudio)"
        write_desktop "CLIP STUDIO.desktop" "CLIP STUDIO (Hub)" hub "$ICON_HUB" \
            "clipstudio.exe" "CLIP STUDIO Hub (login, assets, material management) with the Linux fixes"
        ok 'entry "CLIP STUDIO (Hub)" (login/assets) -> run-csp.sh'
    fi

    # Entries the CSP installer itself created via winemenubuilder
    # (applications/wine/Programs/CLIP STUDIO/*.desktop) start "wine <lnk>" without the fixes.
    # Only those for THIS prefix and only the main shortcuts are redirected.
    WMB_DIR="$APPDIR/CLIP STUDIO"
    if [ -d "$WMB_DIR" ]; then
        for f in "$WMB_DIR"/*.desktop; do
            [ -f "$f" ] || continue
            grep -qF "WINEPREFIX=$PREFIX\"" "$f" 2>/dev/null || continue
            grep -q 'run-csp.sh' "$f" && continue
            mode=""
            grep -qF 'CLIP STUDIO PAINT.lnk' "$f" && mode=editor
            [ -z "$mode" ] && grep -qF 'CLIP STUDIO.lnk' "$f" && mode=hub
            [ -n "$mode" ] || continue
            icon="${ICON_HUB:-}"; [ "$mode" = editor ] && icon="${ICON_PAINT:-}"
            orig="$(grep -m1 '^Exec=' "$f" | cut -d= -f2-)"
            origicon="$(grep -m1 '^Icon=' "$f" | cut -d= -f2-)"
            newexec="$(dq "$LAUNCH_DIR/run-csp.sh") $mode --prefix $(dq "$PREFIX")"
            # remember the original Exec (uninstall.sh restores it); ENVIRON instead of -v: no backslash escaping
            NEWEXEC="$newexec" ORIG="$orig" ORIGICON="$origicon" ICON="$icon" awk '
                /^X-CSP-Linux-Orig(Exec|Icon)=/ { next }
                /^Exec=/  { print "Exec=" ENVIRON["NEWEXEC"]; next }
                /^Icon=/  { if (ENVIRON["ICON"] != "") { print "Icon=" ENVIRON["ICON"]; next } }
                { print }
                END { print "X-CSP-Linux-OrigExec=" ENVIRON["ORIG"]
                      if (ENVIRON["ORIGICON"] != "") print "X-CSP-Linux-OrigIcon=" ENVIRON["ORIGICON"] }' "$f" > "$f.tmp" \
                && mv "$f.tmp" "$f" && ok "Wine entry redirected: ${f#$APPDIR/}"
        done
    fi

    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONDIR" >/dev/null 2>&1 || true
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --quiet >/dev/null 2>&1 || true
elif [ "$CHECK_ONLY" = 1 ] && [ "$CREATE_SHORTCUTS" = 1 ]; then
    warn "would copy the launcher to $LAUNCH_DIR and create menu entries (editor + hub)"
else
    warn "skipped"
fi

# ---------------------------------------------------------------- 6) Summary
log "6/6 done"
echo
echo "Start:"
if [ -f "$PAINT_EXE" ]; then
    echo "  Editor directly (recommended):   WINEPREFIX=\"$PREFIX\" $WINE_EXE \"C:\\\\Program Files\\\\CELSYS\\\\CLIP STUDIO 1.5\\\\CLIP STUDIO PAINT\\\\CLIPStudioPaint.exe\""
fi
echo '  or menu: "CLIP STUDIO PAINT" / "CLIP STUDIO (Hub)"  (they call run-csp.sh with all the fixes)'
echo
echo "Pen diagnostics (open the window, draw over it with the pen):"
echo "  WINEPREFIX=\"$PREFIX\" $WINE_EXE \"$PAINTDIR/t5w.exe\""
echo "  Expected: lines with  pressure=<changing values>"
echo
echo "Adjust tilt (if the brush gets too wide when tilting):"
echo "  XWINTAB_ALT_SCALE=7 WINEPREFIX=\"$PREFIX\" $WINE_EXE \"…\\\\CLIPStudioPaint.exe\"   # Default 9"
echo
GV="$(gecko_ver_installed)"; [ -n "$GV" ] || GV=MISSING
MV="$(mono_ver_installed)";  [ -n "$MV" ] || MV=MISSING
echo "Wine addons:  Gecko=$GV  Mono=$MV"
echo "dcomp shim:   $(dcomp_is_patched "$PREFIX/drive_c/windows/system32/dcomp.dll" && echo "installed (patched)" || { dcomp_is_outdated "$PREFIX/drive_c/windows/system32/dcomp.dll" && echo "installed (OUTDATED v0.1.13 — Hub settings not clickable)"; } || { dcomp_installed && echo "installed (UNPATCHED — Hub seems unresponsive)" || echo MISSING; })"
echo "GPU path:     $(dxvk_installed && echo 'DXVK/VKD3D installed' || echo "MISSING (Wine's own d3d)")   (native d3d9/d3d11/d3d12/dxgi)"
echo "Wine WinRT:   $(winrt_radial_ok && echo OK || echo MISSING)   (MISSING = CSP crashes when starting the editor -> update Wine)"
echo "  (log of the addon installation: $PREFIX/addon-install.log)"
echo
echo "Recommended start (sets the Wine paths correctly):"
echo "  $HERE/run-csp.sh                 # editor"
echo "  $HERE/run-csp.sh hub             # launcher/login"
echo "  $HERE/run-csp.sh --kill          # on 'version mismatch' (an old Wine server is still running)"
echo
if [ "$DO_DXVK" = 1 ]; then
    echo "run-csp.sh sets automatically:"
    echo "  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=…--no-sandbox --in-process-gpu --renderer-process-limit=1 --user-agent=…"
    echo "  DXVK_STATE_CACHE=1  DXVK_CONFIG_FILE=\"$DXVK_CONF\"  mesa_glthread=true"
    echo "  (needed so the buttons in the Hub menu are clickable and the panels render)"
    echo
fi
echo "Uninstall/rollback:  ./uninstall.sh"
echo "Checklist & troubleshooting:  README.md"


# ToDo

As of: 2026-10-11 · Legend: `[ ]` open · `[~]` in progress · `[x]` done

---

## A. Tester package (current focus)

- [~] **`bundle/`** — installer + fix + docs for testers
  - [x] `install.sh` (idempotent, `--check`, `--no-csp`, `--prefix`, `--installer`)
  - [x] `uninstall.sh` (+ `--purge-prefix`)
  - [x] `verify.sh` (prefix, CSP, DLL + hash, Wine override, running process; `--tablet` for the X level)
  - [x] `README.md` with checklist + troubleshooting table
  - [x] `files/` (patched DLL, XI2 helper, `t5w.exe`, `xi2-probe.c`, sources, licenses)
  - [x] **End-to-end test** in a fresh prefix: `./install.sh` installed CSP **silently from the
        own installer**, applied the fix, created menu entries, `verify.sh` = **6 OK / 0 errors**,
        and the DLL opens the Wintab context there
        (`tilt config: base=900 scale=9`, `Using device: 11`, `WTOpenW: called`) — 2026-10-09
  - [x] Fix found in the end-to-end test (Hub path in `verify.sh`) and resolved
  - [x] Tarball **`csp-linux-bundle-0.1.0.tar.gz`** (125,000 B, 18 entries, scripts executable)
        + `csp-linux-bundle-0.1.0.tar.gz.sha256`
  - [x] **Automate the Wine addons** (v0.1.1): `install.sh` step 2b checks/installs
        **Wine Gecko** (MSHTML/IE UI) and **Wine Mono** (.NET) — version numbers are read from
        `appwiz.cpl` (`strings … | grep ^2\.` = Gecko, otherwise Mono), MSIs are downloaded
        cache-aware (`~/.cache/wine`) and installed via `wine msiexec /i`; `--no-addons` to skip
  - [x] `verify.sh` additionally checks Gecko/Mono/WebView2; Hub path bugfix
  - [x] **Addon installation hardened (v0.1.2)** — after a report "Gecko/Mono installation failed
        on the target machine": local MSI search (bundle folder, cwd, `~/Downloads`, Wine cache)
        + new `--addon-msi-dir DIR` → **offline installation without a download**; three download
        backends (curl → wget → python3); URL check + version fallback via the `dl.winehq.org`
        directory listing; distro-independent `appwiz.cpl` search (Debian/Fedora/opt/flatpak);
        error log `<prefix>/addon-install.log`; addon status in the final output
  - [x] Tested: (A) download path ✓, (B) local MSI without download ✓, (C) `--check` ✓
  - [x] **Test run 01 evaluated** (foreign machine Fedora/wine-11.0/AMD): white WebView2 panels
        identified (Hub centre, settings) + Mono problem = **version mismatch**
        (Wine 11.0 wants Mono **10.4.1**, not 11.3.0)
  - [x] **v0.1.3**: version-aware addon installation (expected version from `appwiz.cpl` incl.
        Fedora paths + `find` fallback; installed version from registry/files),
        **dcomp shim** for WebView2 panels (default, `--no-dcomp`, `--dcomp-dir`),
        Fedora hint (`dnf install wine-mono wine-gecko`), `verify.sh` checks dcomp
  - [x] **Test run 02 evaluated** (Fedora/wine-11.0/AMD): the dcomp shim works (panels render ✓),
        **new crash**: CSP's WinRT bridge `triglavwinrt.dll` activates
        `Windows.UI.Input.RadialController` (Surface Dial) — **Wine 11.0 does not provide the
        class** → NULL deref → editor crash. Proof: own `winrt-probe.exe` (5 classes) on wine 11.19 =
        all OK; `strings …/windows.ui.dll | grep -ci radialcontroller` = 21 (11.19) vs. 0 (11.0)
  - [x] **v0.1.4**: WinRT pre-check in `install.sh` (+ clear "Wine too old" warning),
        `verify.sh` line + `--winrt` (runs `files/winrt-probe.exe`), tool shipped,
        README troubleshooting + requirement "Wine ≥ 11.19"; false-alarm bug (`grep -q`+`pipefail`/SIGPIPE) fixed
  - [x] Tarballs: **0.1.4** and **0.1.4-offline** (Gecko 2.47.4 + Mono 10.4.1 + Mono 11.3.0)
  - [x] **Bundle contents updated to DLL 0.6** (2026-10-10): `files/wintab32.dll` (device name
        + complete `WTInfo` categories), `files/xi2-devname.c` new, `install.sh` writes the
        device name as a sidecar (builds the tool if needed), `uninstall.sh` removes it as well,
        `verify.sh` shows and checks the name source, `xi2-probe.c` uses `$DISPLAY`
        instead of hard-coded `:1`.
  - [x] **v0.1.9 packed** (2026-10-10): `bundle/VERSION` = 0.1.9, `RELEASE-NOTES.md` extended,
        `csp-linux-bundle-0.1.9{,-offline}.tar.gz` + `.sha256` rebuilt (offline package
        reproducible from `~/.cache/wine`: Gecko 2.47.4 + Mono 10.4.1/11.3.0, hashes identical
        to 0.1.8), cross-tested from a fresh unpack (`install.sh --check`, `verify.sh`
        = 12 OK / 0 errors).
  - [x] **Side finding corrected**: `install.sh` had the version hard-wired to 0.1.8
        (now from `VERSION`), and `install.sh`/`verify.sh` wrongly reported Gecko/Mono as
        missing although the distro package provides them — Wine loads these trees directly
        (`mshtml`: `load_gecko()` → `…/wine/gecko/wine-gecko-<ver>-<arch>`; `mscoree`:
        `get_mono_path()` → `…/wine/mono/wine-mono-<ver>`), MSI/download only afterwards.
  - [x] **`install.sh` downloads the CSP installer + portable Wine itself** (v0.1.16): official
        CELSYS server, SHA256 pinned; portable Wine automatically when system Wine is missing or
        < 11.19; `--csp-version`, `--system-wine`
  - [x] **Menu entries start via `run-csp.sh`** with all fixes, icons extracted from the EXEs,
        launcher copy in the prefix (v0.1.17)
  - Info: the own CSP installer can be placed at `installer/CSP_504w_setup.exe` (relative to the repo root)
  - **Observation**: Gecko/Mono are **not** needed in the reference prefix (CSP runs there without
    a Gecko version folder) — but the Wine addon dialog is the candidate for the "empty white
    window" on foreign machines; that is why the package installs them as a precaution
- [ ] Set up a **feedback loop**: have `verify.sh` output + an `XWinTabLog.txt` excerpt collected
      (section 6 of the tester README explains it)

## B. Comfort / robustness (after tester feedback)

- [x] **Real device name for `DVC_NAME`** (v0.6, 2026-10-10): resolution order
      `XWINTAB_DEVICE_NAME` → sidecar file `XWinTabDeviceName.txt` next to the DLL (written by
      `install-xwintab.sh`/`bundle/install.sh` via the new tool `diag/xi2-devname`) →
      `XWINTAB_DEVICE` → placeholder. **No helper rebuild:** the helper only exports
      `DeviceInfo` (without a name) and its source is not in the repo — a new
      `XWinTabHelper.dll.so` build would have required re-verifying the proven pressure path.
      Under XWayland the name is, for technical reasons, `xwayland-tablet stylus:<id>` (Wayland only
      hands out the hardware name via `zwp_tablet_manager_v2`, not to X11 clients); on Xorg it is
      e.g. `Wacom Intuos Pro M Pen stylus`.
      Verified: CSP log `device name: from XWinTabDeviceName.txt` +
      `DVC_NAME -> 52 bytes ("xwayland-tablet stylus:11")`. Docs: `CSP-TABLET-FIX.md` §7.2
- [x] **Answer `WTI_EXTENSIONS` + info categories cleanly** (v0.6, 2026-10-10):
      The log line `unhandled cat 400 idx 0` was in truth **`WTI_DDCTXS`** (400),
      not `WTI_EXTENSIONS` (300) — both are answered now:
      `WTI_DEFCONTEXT`/`WTI_DEFSYSCTX`/`WTI_DDCTXS` share one handler (index 0 = whole
      `LOGCONTEXTW`, `CTX_*` 1–34 = single field), `WTI_DDCTXS+n` (n≥1) = 0 (exactly one device),
      `WTI_EXTENSIONS` = 0 (no extensions), `WTI_INTERFACE` complete (SPECVERSION,
      IMPLVERSION, NDEVICES, NCURSORS, NCONTEXTS, CTXOPTIONS, CTXSAVESIZE, NEXTENSIONS,
      NMANAGERS) as well as `DVC_HARDWARE`/`DVC_NCSRTYPES`/`DVC_FIRSTCSR`. Expected semantics taken
      from Wine's builtin (`dlls/winex11.drv/wintab.c`); the new tool `diag/wtinfo-probe.c`
      dumps both sides comparably. CSP log now **without** `unhandled`; field-by-field diff
      against Wine shows only intended deviations (screen-space mapping, virtual
      screen origin). Docs: `CSP-TABLET-FIX.md` §7.1/7.3
- [x] **Test run 03 evaluated**: probe shows 4/5 missing WinRT classes (`0x80040154`);
      **Proton analysis**: GE-Proton 9-27 = Wine 9.0 (5/5 missing), 8-32 = Wine 8.0 → **Proton does not help**;
      **prefix vs. binary**: the binary decides (prefix of Wine 9.0 + Wine 11.19 = 5/5 OK).
- [x] **v0.1.5**: WinRT check **probe-based** (the string heuristic was a false alarm),
      **`--wine-bin DIR`** for portable/another Wine, the error message names concrete ways + Proton note
- [x] **Portable Wine 11.19 verified**: Kron4ek tarball (97 MB, wow64) unpacked to
      `installer/wine-portable/` (relative to the repo root), `./install.sh --wine-bin …/bin` → WinRT classes OK
- [x] **`STATUS.md`** (handover: requirements matrix, chronicle, resume guide, cheat sheet, artifact index)
- [x] **v0.1.6**: `--wine-portable [VER]` (+ `--wine-portable-dir`) — the installer downloads/unpacks
      the portable Wine itself (no symlink transport via the stick), checks SHA256 against
      `sha256sums.txt`, uses it internally + writes `$PREFIX/portable-wine-path`
      (verify.sh and menu entries then use it automatically). Helpers (`url_ok`,
      `do_download`, `find_local_msi`, cache) moved up for that. E2E tested.
- [x] **v0.1.7**: `run-csp.sh` launcher (automatically uses the noted portable Wine, sets
      PATH/WINELOADER/WINESERVER, `--kill` terminates old Wine servers). Cause of "wine client error:
      version mismatch 931/962" = **an old Wine server is still running** (Wine 11.0 = protocol 930,
      11.19 = 962); Wine does not always terminate it itself. Menu entries now also set
      loader/server/PATH with portable Wine. Docs: README (troubleshooting) + STATUS.md.
- [x] **Fedora test with v0.1.7 + portable Wine** ✅ **successful (2026-10-10)**:
      CSP runs there with `run-csp.sh` **like on the Arch reference** (editor, pressure, panels, login).
      **Finding:** a manual start (`WINEPREFIX=… <portable>/bin/wine …`) fails with
      `version mismatch 931/962` — Wine also searches `wineserver`/`wine64` via `PATH` (there system
      Wine 11.0 = protocol 930 vs. client 11.19 = 962) and does not terminate an old server itself.
      → Always use `run-csp.sh` (sets `PATH`+`WINELOADER`+`WINESERVER`), on mismatch `--kill`.
      Documented in `STATUS.md` §7b
- [x] **GPU path (DXVK/VKD3D like CSPenguin) + WebView2 arguments** ✅ **implemented (2026-10-10)**:
      `install.sh` installs via `winetricks -q dxvk vkd3d` (DXVK 3.1.1 / vkd3d-proton 3.0.1) and
      writes `<prefix>/dxvk.conf` (values like CSPenguin: `dxgi.deferSurfaceCreation = True`,
      `dxvk.enableGraphicsPipelineLibrary`, `dxvk.numCompilerThreads = 0`, `dxvk.maxChunkSize = 16`);
      `run-csp.sh` sets `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` (`--no-sandbox --in-process-gpu
      --disable-gpu-vsync …`), `DXVK_CONFIG_FILE`, `DXVK_STATE_CACHE`, `DXVK_ASYNC`, `mesa_glthread`,
      `RADV_PERFTEST`; `verify.sh` checks the GPU path (+ native `d3d11.dll` > 1 MB as proof) and
      has a **live probe** with `--panels` (start the Hub, open the menu, measure the viewport, count
      colours in the menu window); `uninstall.sh --gpu` takes the GPU path back.
      **Finding (corrected):** the panels were already no longer white before (the dcomp shim
      takes effect), and the page demonstrably renders the menu correctly — via CDP screenshot
      448×644 with 2350 colours, while in the X window only the fill arrived (133 colours,
      52 % of them the background colour). So a **presentation problem**, not a loading error.
      **The lever is `--in-process-gpu`:** the GPU work then runs in the main process, the
      compositor subprocess is dropped, and the dcomp shim's GDI blit takes effect. Measurement
      (panel window counted by screenshot):
      `--no-sandbox` → 138 colours/black; `--no-sandbox --in-process-gpu` → 4309 colours/complete;
      `--no-sandbox --disable-gpu-compositing` → viewport collapses;
      `--no-sandbox --disable-gpu-compositing --in-process-gpu` → 138 colours, black again.
      **`--disable-gpu-compositing` (from the CSPenguin installer) is therefore wrong here** and was
      removed; DXVK is not needed for the menu content (counter-tested with builtin d3d: same
      black state). Even without the arguments the menu entries are **clickable** and navigate.
      A viewport of 1×1 px only means: **panel is collapsed**, not "broken".
      **Additional finding:** the "not closed properly" dialog **blocks the Hub completely**
      (WebView2 then does not start at all). `run-csp.sh` clicks it away automatically
      (`files/xdlg.c`, needs `gcc`; can be turned off with `--no-dialog-fix`).
      **New switches:** `--no-dxvk`, `run-csp.sh --no-gpu-env`, `run-csp.sh --menu-open`
      (open the menu automatically, experimental — default is **off**, because the click has to be
      timed), `verify.sh --panels`, `verify.sh --prefix DIR`, `run-csp.sh --debug-port N`,
      `run-csp.sh --no-user-agent`.
- [x] **403 of the CELSYS tutorial site: replace the User-Agent** ✅ **implemented (2026-10-10, v0.1.12)**:
      `tips.clip-studio.com` (menu "Official tutorials", "Tutorials" and the start page) returns
      **403 Forbidden (nginx)** to every User-Agent containing `Chrome/` — and that is exactly
      what WebView2 sends (Chromium 115).
      Proven with `curl`: `…AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36` → 200,
      the same + `Chrome/115.0.0.0` → 403; headers (`Accept`, `sec-ch-ua`, `Sec-Fetch-*`) and
      HTTP version change nothing. `run-csp.sh` therefore now sets
      `--user-agent=…Safari/537.36 Win64/NT 10.0/CLIPSTUDIO/5.0.4/DoNotTrack` — **without** `Chrome/`,
      but **with** `CLIPSTUDIO/<version>`, because `menu.js` reads its version from it
      (`main.getIceVer()`); without the marker the menu breaks. Can be turned off with `--no-user-agent`.
      With that the tutorial site loads completely. The other menu items reported as black
      also load real content (`ec.clip-studio.com/…/application` 10,072 colours,
      `…/activation-codes/` 11,024, `ice…/guide/page/MS00` 555, `share.clip-studio.com` OK) —
      they were black because of the 403 or because the content lands in a **new window**.
      **Not a dcomp problem**, there is nothing to rebuild in the shim.
- [x] **Hub display + "ineffective" buttons fixed in the dcomp shim** (v0.1.13): blit into the
      parent DC (child windows have no drawing surface in Wine 11.x), `Present()` forwards frames
      (before only on `Commit()`), invisible targets skipped. The package only ships
      `files/src/dcomp-csp-linux.patch`; `install.sh` downloads the upstream source (SHA256), patches,
      builds with mingw-w64; `verify.sh` recognises patched/unpatched and app-folder copies that shadow
- [x] dcomp shim: Paint editor cross-tested with the patched shim — no side effects, drawing/painting flawless
- [x] Hub: enlarging the window without side effects; Cloud page fully functional
      (download of comic files + hand-over to the editor like on Windows) — user test
- [x] **Native Hub dialogs clickable again** (v0.1.14): the patch only applies in the WebView2
      process; CSP's own DirectComposition dialogs (settings, security settings) run with upstream
      behaviour
- [x] **Hub RAM: one WebView2 renderer instead of ~11 processes** (v0.1.15): 5.07 → 1.47 GB
- [ ] Hub: cross-test the user account/activation code panels
- [ ] dcomp shim: the 32-bit version (`syswow64`) is still the old one — check whether it is loaded at all
- [ ] dcomp shim: `commit_texture` without a lock — if Chromium ever calls `Present` and `Commit`
      from different threads, protect the staging buffer
- [ ] dcomp shim: clarify the license situation (upstream without a license file) → possibly an
      issue/PR at the CSPenguin project (our patch would be a sensible upstream contribution)
- [ ] Cosmetics: white borders in the settings window on the reference machine
- [ ] Optional: also install Gecko for the 32-bit side (syswow64) (x86 MSI), if 32-bit apps are affected
- [ ] Make further Wintab functions of the spec complete/robust, if a program needs them
      (`WTSave/WTRestore/WTConfig/WTExtGet/WTExtSet`, rest of `WTMgr*`)
      - [ ] `CSR_NAME` (WTI_CURSORS+1, name of the cursor) — Wine returns the X11 device name there,
            we (still) 0. With the v0.6 mechanism (`XWinTabDeviceName.txt`) it would be a 6-liner;
            CSP does not ask for it, so only if needed.
      - [ ] `WTI_STATUS` (2) — Wine returns 1 byte *without* filling it; we 0. Not queried either.
- [ ] Tilt: optionally a **non-linear curve** (e.g. `altitude` with an exponent) or
      azimuth influence, if linear is not enough
- [ ] Automatic fallback/diagnostics: the DLL writes a mini report on demand
      (device, axes, pressure range) to a file — for support without a log puzzle
- [ ] Wine version robustness: test with Wine 10.x/12.x; note in the docs
- [ ] `run-csp.sh --kill` uses `pkill -f "CLIPStudio"`, which also matches unrelated processes whose
      command line contains that word — narrow the pattern

## C. Upstream / community

- [ ] **Pull request to `Sylixa/WineTab`**: the 6 CSP compat exports
      (`WTPacket`, `WTDataGet`, `WTDataPeek`, `WTMgrOpen/Close/Ext`) + `WTQueuePacketsEx`
      + tilt control, plus a note "tested with CSP"
- [ ] Optional: issue/AppDB entry (WineHQ) for CSP 5 + WineTab fix, incl. bug reference 53052
- [ ] If appropriate, contact `parka6060/CSPenguin-Installer` (our fix as an optional component)
- [ ] Adopt fixes from CSPenguin that we do not have yet:
      - [ ] **KWin window rules** (ribbon/sub-windows appear behind CSP)
      - [ ] **Timelapse/animation export** (mfplat/mfreadwrite/winegstreamer patches)
      - [ ] **`.clip` file thumbnails** (native thumbnailer, Dolphin preview)
      - [ ] **CJK font** (WenQuanYi) for asset store/brush names

## D. Done (archive)

- [x] Install CSP 5.0.4 into its own Wine prefix (silent, `install-csp-prefix.sh`)
- [x] **Pen pressure fix** (WineTab + CSP compat exports) — confirmed by the user: pressure ✓, no ghost strokes ✓
- [x] Tilt control (`XWINTAB_ALT_SCALE`), **default 9** determined as comfortable and built in
- [x] Documentation: `README.md`, `CSP-TABLET-FIX.md`, `diag/README.md`, scripts

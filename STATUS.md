# STATUS — project state & handover

**As of:** 2026-10-11 · working directory: **repo root** (the directory of this document)

---

## 1. Goal

Run CLIP STUDIO PAINT 5.0.4 on Linux (Wine) — **with** pen pressure, without ghost strokes,
with rendering panels (Hub/settings/login) — and be able to **hand the setup on as a package**.

## 2. Summary of the state

| Machine | Status |
|---|---|
| **Reference** (Arch, `wine-staging 11.19`, Wacom) | ✅ **Everything works**: editor, pen pressure (measured 0–52,553), **no** ghost strokes, tilt tuned (default `XWINTAB_ALT_SCALE=9`), Hub/login/settings render, save/load |
| **Test** (Fedora, `wine-staging 11.0`, AMD/radv) | ✅ **Works completely** (2026-10-10) — **portable Wine 11.19** + start via **`run-csp.sh`**: editor, pen pressure, panels, login as on the reference. Prerequisite: Wine ≥ 11.19 (WinRT) and the launcher (sets `PATH`/`WINELOADER`/`WINESERVER`; `--kill` against old Wine servers) |

## 3. Requirements matrix (what a working system needs)

| # | Requirement | Why | Check |
|---|---|---|---|
| 1 | **Wine ≥ 11.19** (11.0 is **not** enough) | CSP 5 activates WinRT classes (`Windows.UI.Input.RadialController` = Surface Dial support, `Windows.Storage.StorageFile`). If they are missing → NULL deref in `triglavwinrt.dll` → **crash at editor start**. Wine 11.0: 4/5 missing, 11.19: 5/5 OK | `./verify.sh` or `wine files/winrt-probe.exe` (5 × OK) |
| 2 | **Version-exact Wine addons**: Gecko 2.47.4 + Mono matching the Wine version (**11.0 → 10.4.1**, **11.19 → 11.3.0**) | otherwise Wine keeps asking (dialog = "empty white window"); IE/MSHTML UI stays empty | `./verify.sh` (Gecko/Mono lines with version) |
| 3 | **WebView2 runtime** (the CSP installer installs it) | Hub, login, assets, material management | `./verify.sh` |
| 4 | **dcomp shim, patched** (CSPenguin source + `bundle/files/src/dcomp-csp-linux.patch`, built with **mingw-w64** during installation; override `dcomp=native,builtin`) | without the shim WebView2 panels stay **white** (esp. AMD/radv); without the patch the Hub content stays put/black after clicks | `./verify.sh` (dcomp shim line: "patched") |
| 5 | **Pen pressure fix**: patched `wintab32.dll` + `XWinTabHelper.dll.so` + override `wintab32=native` | Wine's builtin delivers no pressure / sporadic events under XWayland (WineHQ bug 53052) | `./verify.sh` (hash comparison + process mapping) |
| 6 | Vulkan-capable GPU (for parts of the CSP engine) | AMD/radv works (the "not conformant" message is only a notice) | — |
| 7 | **Not** needed: a newer Wine from a system package | replaceable by portable Wine (§5) | — |
| 8 | **Start via `run-csp.sh`** (or the created menu entries) | Wine must use `wineserver`/`wine64` of the same build — otherwise `version mismatch` (system Wine 11.0 = protocol 930, 11.19 = 962) | `./run-csp.sh` → shows the Wine version; on mismatch `--kill` |

## 4. Causes of the three test rounds (short chronicle)

| Run | Observation | Cause | Fix |
|---|---|---|---|
| **01** | Hub/settings **white**; Mono check error | (a) WebView2 panels without DirectComposition; (b) Wine 11.0 wants **Mono 10.4.1**, the installer had 11.3.0 (version not detected on Fedora) | v0.1.3: dcomp shim + version-aware addon installation + Fedora paths/`find` fallback |
| **02** | **Editor crash** right after opening | `triglavwinrt.dll` (WinRT bridge) dereferences NULL after a failed activation of `RadialController` | v0.1.4: WinRT check + `winrt-probe.exe` + docs |
| **03** | Probe: **4/5 classes missing** (`hr=0x80040154`); string check wrongly says "OK"; no newer Wine installable; question about Proton | Wine 11.0 does not register the classes (name in the binary ≠ activatable). **Proton does not help**: GE-Proton 9-27 = Wine **9.0**, GE-Proton 8-32 = Wine **8.0** → also too old (5/5 missing). **The prefix does not matter**: prefix of Wine 9.0 + binary 11.19 → 5/5 OK | v0.1.5: check is now **probe-based** (string heuristic removed) + `--wine-bin` for **portable Wine** |

## 5. Recommended path for a machine with an old Wine (resume guide)

**Portable Wine — no system installation needed, no symlink transport** (verified with 11.19).
The installer downloads and unpacks it itself on the target machine (since v0.1.16 even
automatically when system Wine is missing or older than 11.19):

```bash
# 0) If "wine client error: version mismatch 931/962" appears:
#    a Wine server of another version is still running -> terminate it
pkill -f wineserver        # (or: ./run-csp.sh --kill)

# 1) Install the package with portable Wine (download ~100 MB, unpacked ~1 GB, no root)
./install.sh --wine-portable --prefix ~/.wine-csp        # default 11.19
#   Options: --wine-portable 11.20   ·   --wine-portable-dir /path
#   (SHA256 is checked against sha256sums.txt; the Wine path is noted as
#    ~/.wine-csp/portable-wine-path and then used automatically)

# 2) Check (expected: "WinRT classes OK"; probe: 5 × OK)
./verify.sh
WINEPREFIX=~/.wine-csp wine files/winrt-probe.exe

# 3) Start — most robust with the bundled launcher:
./run-csp.sh                # editor (sets PATH/WINELOADER/WINESERVER to the portable Wine)
./run-csp.sh hub            # launcher/login
./run-csp.sh --kill         # on "version mismatch" (an old Wine server is still running)
# The menu entry "CLIP STUDIO PAINT" is wired up correctly as well (it calls run-csp.sh).
```

*Why the detour:* the stick used to transfer the package destroys symlinks in unpacked Wine
builds — so Wine is downloaded/unpacked **on the target machine**.

**Alternatives:** update system Wine (`sudo dnf upgrade wine-staging`, WineHQ repo) ·
`sudo dnf install wine-mono wine-gecko` (system addons, then no addon dialog) ·
**Proton: unsuitable** (Wine 8/9/10 base < required version).

## 6. Command cheat sheet

```bash
# All paths relative to the repo root (the directory of this document):
cd /path/to/CSP5-for-Wine

./start-csp.sh                              # start the editor
./start-csp.sh tilt 9                       # tilt (smaller = gentler; default 9)
./install-xwintab.sh                        # (re)install the pen pressure fix
XWINTAB_LOG=1 ./start-csp.sh                # detailed Wintab log (drive_c/users/<user>/XWinTabLog.txt)

cd bundle                                   # distribution package = its own root directory
./verify.sh                                 # system check (prefix $WINEPREFIX or ~/.wine-csp)
./verify.sh --winrt                         # + list WinRT classes
./install.sh --check                        # only check, change nothing

# Process side, independent of the cwd:
grep -c dcomp.dll /proc/$(pgrep -f 'CLIPStudio.exe' | tail -1)/maps   # dcomp active?
```

## 7. Documents & artifacts

| Path | Contents |
|---|---|
| `README.md` | Overview, quick start, document index |
| `CSP-TABLET-FIX.md` | Pen pressure fix: diagnostic chain, patch, installation, tilt, operation |
| `bundle/README.md` | **Tester guide** (checklist, troubleshooting, addons, dcomp) |
| `diag/` | Tools: `winrt-probe`, `wintab-test`, `t5w`, `xi1/xi2-probe`, `xi2-devname` (device name), `wtinfo-probe` (WTInfo dump), patched DLL sources |
| `TODO.md` | open points & ideas |
| `csp-linux-bundle-<version>.tar.gz` | distribution packages (release assets) |
| `bundle/run-csp.sh` | launcher (right Wine, `--kill` against "version mismatch") |

## 7b. Confirmed end result (2026-10-10)

Both machines run: **Arch** (system Wine 11.19) and **Fedora** (portable Wine 11.19 + `run-csp.sh`).
The original goal is thereby reached; only comfort/upstream topics remain open (§8).

**Addendum (v0.6 of the DLL, 2026-10-10)** — the two comfort points `DVC_NAME` and
`WTI_EXTENSIONS`/`WTI_DDCTXS` are done (details `CSP-TABLET-FIX.md` §7):
CSP's log is now free of `unhandled cat …`; `WTInfo(DVC_NAME)` reports the real
device name (`xwayland-tablet stylus:11`, source: sidecar file, written by the installer).
Live cross-checked: the editor starts, pressure works (t5w: pressure varying 21,438–48,750),
`verify.sh` = 11 OK / 0 errors.

## 8. Open points (for continuation)

1. ~~Fedora machine: portable Wine + editor test~~ ✅ **done** (runs, see §7b)
2. ~~`DVC_NAME` (real device name) + `WTI_EXTENSIONS`/info categories~~ ✅ **done** (v0.6, §7b)
3. ~~If panels are white again afterwards: check the GPU path (DXVK/VKD3D like CSPenguin), `WINEDEBUG=+dcomp`.~~
   ✅ **done v0.1.10 / corrected v0.1.11**: the panels were no longer white anyway (the dcomp shim
   takes effect); the page demonstrably renders the menu correctly (CDP screenshot: 2350 colours),
   but in the X window only the background fill arrived (133 colours) — a **presentation** problem,
   not a loading problem. Cause: Chromium's compositor subprocess; the shim (GDI blit of the GPU
   texture) only takes effect if the GPU work runs in the main process. **The lever is
   `--in-process-gpu`** (measurement: 138 colours/black without, 4309/visible with the flag).
   `--disable-gpu-compositing` from the CSPenguin installer is **counterproductive** here and was
   removed. The GPU path (DXVK/VKD3D + `dxvk.conf`) stays the bundle default in
   `install.sh`/`run-csp.sh`/`verify.sh` (`--no-dxvk`, `--no-gpu-env` to turn it off) — but it is
   not needed for the menu content.
   **Additional finding:** the "not closed properly" dialog blocks the Hub completely;
   `run-csp.sh` clicks it away automatically. A viewport of 1×1 px only means "menu closed".
   Live check: `./verify.sh --panels`.
3b. ~~Hub stays empty / buttons without effect although the shim is running~~ ✅ **done v0.1.12**:
   `tips.clip-studio.com` (menu "Official tutorials", "Tutorials", start page) returns **403
   Forbidden** to every User-Agent with `Chrome/` — and that is exactly what WebView2 sends
   (Chromium 115). `run-csp.sh` now sets
   `--user-agent=…Safari/537.36 Win64/NT 10.0/CLIPSTUDIO/5.0.4/DoNotTrack` (without `Chrome/`, but
   **with** `CLIPSTUDIO/<version>`, because `menu.js` reads its version from it); can be turned
   off with `--no-user-agent`. All other menu items reported as black load real content
   (10,072 / 11,024 / 555 colours) or open their own window — **not a dcomp problem**.
   `verify.sh --panels` now measures via the DevTools protocol instead of a screenshot tool
   (`files/panelprobe.py`); that also removes the KDE dialog "Request remote control".
3c. ~~Hub content flickers / buttons "without effect"~~ ✅ **done v0.1.13** — correction to 3b:
   "not a dcomp problem" only applied to the 403 cases. The actual remainder **was in the shim**:
   (a) WebView2 draws into child windows, which have no drawing surface of their own in Wine 11.x
   (`win32u` `get_window_surface`: `is_child` → `needs_surface = FALSE`) — the blit there was
   wiped by the next repaint; now a blit into the **parent window's** DC at the child's offset
   (experiment `diag/dcomp-shim/disp-test.c`). (b) New frames only arrived on
   `Device::Commit()`, which Chromium only calls when the layer tree changes (25× per session);
   `IDXGISwapChain::Present()` was a no-op → after every navigation the old/black picture stayed.
   Now `Present()` forwards the frame. (c) Invisible targets are skipped, the blit is limited to
   the own rectangle. Verified live: menu → ASSETS page, chip "New" → search results render.
   Paint editor with the shim without side effects; resize uncritical; Cloud incl. download +
   hand-over to the editor works (user tests). Package: only the patch is shipped (license, point 4).
3d. ~~Native Hub dialogs (settings via cog, "Security settings" greeting) not clickable~~ ✅ **done** —
   regression from 3c: these dialogs are **not WebView2**, `CLIPStudio.exe` draws them itself
   via DirectComposition (window classes `5704E805-…`, no CDP target). The patch's
   subclassing/Present forwarding took effect there as well and disabled the dialogs (A/B:
   upstream DLL only in the Hub folder → dialog clickable). Fix: patch behaviour only in the
   process `msedgewebview2.exe`; otherwise unmodified upstream behaviour. Subclassing now via
   `SetWindowLongPtrW` (the A variant turned Unicode windows into ANSI windows). Verified live:
   dark mode there and back, security settings → OK closes, Hub navigation refreshes.
   Not a missing CSPenguin patch — CSPenguin does not have the problem because it uses the
   upstream shim. Shipped as **v0.1.14**; `install.sh` replaces a v0.1.13 shim automatically
   (marker `csp-linux rev2`).
3e. ~~WebView2 takes 5–9 GB of RAM (7× `CrRendererMain`)~~ ✅ **done v0.1.15** — under Wine every
   WebView2 process holds a private copy of `msedge.dll` (~230 MB; file alignment 0x200 → Wine
   reads the image into anonymous memory instead of mapping it). `run-csp.sh` limits this to one
   renderer + network service in the browser process: 11 → 4 processes, 5.07 → 1.47 GB (PSS).
   `--multi-process` = old behaviour.
3f. ✅ **v0.1.16:** `install.sh` downloads the CSP installer (5.0.4, SHA256 pinned, CELSYS server)
   and, if system Wine is missing/too old, portable Wine 11.19 automatically. Fixed on the way:
   `--wine-portable` failed on new prefixes (download log in the not-yet-existing prefix). E2E on
   an empty prefix verified, incl. the first-start greeting.
3g. ✅ **v0.1.17:** menu entries start via `run-csp.sh` (copy in `<prefix>/csp-launcher/`), no
   longer `wine` directly — before, they lacked all fixes. Icons from the EXEs; Wine entries
   created by the CSP installer are redirected (original restorable). verify/uninstall adapted.
4. `dcomp` shim: clarify the license situation at the CSPenguin project (upstream without a
   license file) → issue/PR.
5. Upstream: PR to `Sylixa/WineTab` (CSP compat exports + tilt control + `DVC_NAME` sidecar).
6. Optional: "Free test"/offline button behaviour = expected without a CELSYS login (documented).

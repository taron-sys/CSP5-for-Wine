# Release Notes

## v0.1.17 — menu entries start with all the fixes

**Problem:** the menu entries "CLIP STUDIO PAINT" / "CLIP STUDIO (Hub)" used to run `wine
CLIPStudio.exe` directly. They therefore lacked everything `run-csp.sh` sets: WebView2 arguments
(`--in-process-gpu`, one-renderer mode → empty Hub or several GB of RAM), the User-Agent (403 on
the tutorial site), the GPU environment, the dialog dismisser and the choice of the portable Wine.
The variable `WINEDESKTOP_EXTRA` that was meant to carry this was never written into the entry. The
Paint icon (`9540_CLIPStudioPaint.0`) often did not exist at all. So anyone starting from the menu
instead of `run-csp.sh` got exactly the problems the recent versions fix.

**Now (`install.sh`, step 5):**
* The entries call `run-csp.sh editor|hub --prefix <prefix>`.
* A copy of the launcher lives in **`<prefix>/csp-launcher/`**. The entries keep working even if
  the unpacked bundle is deleted or moved.
* **Icons** are extracted from the EXEs (`files/extract-icon.py`, 16–256 px, hicolor).
* The Wine entries the **CSP installer** itself creates ("CLIP STUDIO" under *Wine → Programs*) are
  redirected to the launcher for this prefix; the original is noted in the entry
  (`X-CSP-Linux-OrigExec`) and restored by `./uninstall.sh`.
* `verify.sh` checks that the entries use `run-csp.sh` and that the launcher exists.
* `uninstall.sh` removes entries, icons and the launcher copy.

**Update:** run `./install.sh` again (idempotent; mingw-w64 as before).

Verified (Arch/KDE, Wine 11.19): entries started with `gio launch` like a menu click — Hub with
`--in-process-gpu --renderer-process-limit=1`, 4 processes / 1.46 GB; the editor starts and closes
cleanly; `desktop-file-validate` reports nothing; install → uninstall restores a redirected Wine
entry byte-identically.

## v0.1.16 — installation without pre-downloads

**New:** `install.sh` fetches the two things itself that previously had to be obtained by hand.

* **CSP installer:** if no `CSP_*setup.exe` is found (next to the script, `~/Downloads`, `~`,
  current directory), the installer downloads **CSP 5.0.4** from the official CELSYS server
  (`vd.clipstudio.net`, ~470 MB) and checks the **pinned SHA256**. `--csp-version 512` downloads
  another version (untested with this package, no hash check).
* **Portable Wine automatically:** if system Wine is missing or older than **11.19**, portable
  Wine 11.19 (Kron4ek, SHA256 from the release) is downloaded and used, without `--wine-portable`.
  A portable Wine noted in the prefix is reused on later runs. `--system-wine` forces system Wine.

**Fixed:** `--wine-portable` always failed on a **new** prefix with "download failed". The
download log lived in the prefix folder, which did not exist yet at that point. Also, the final
output still mentioned `--disable-gpu-compositing` (no longer used since v0.1.11).

**Verified end to end** (Arch; system Wine faked as 11.0, empty prefix, no local installer):
portable Wine downloaded + checked → CSP installer downloaded + SHA256 checked → CSP installed
silently → dcomp shim, DXVK, pen pressure fix OK → `verify.sh` 18 OK / 0 errors → first Hub start:
"Security settings" greeting (checkboxes + OK clickable), preparation, materials prompt, start page
renders; WebView2 1.3 GB.

## v0.1.15 — the Hub needs ~3.5 GB less RAM

**Symptom:** 7 `CrRendererMain` processes together take ~9 GB.

**Cause:** under Wine **every** WebView2 process holds a private copy of `msedge.dll` (~230 MB,
fully resident, at the same address in every process). The DLL has a file alignment of 0x200,
i.e. smaller than a memory page. Wine therefore cannot map the image from the file and reads it
into anonymous memory; Windows would share it. WebView2 starts ~11 processes for the Hub (one
renderer per panel + network and storage services). Measured (PSS, fresh Hub start): **5.07 GB**.
On top of that comes the renderers' normal page memory.

**Solution (`run-csp.sh`):** `--renderer-process-limit=1 --disable-site-isolation-trials
--enable-features=MojoIpcz,NetworkServiceInProcess2`, i.e. one renderer for all panels and the
network service in the browser process. Result: **4 processes, 1.47 GB** (1.55 GB with the ASSETS
page open). Back to the default: `./run-csp.sh --multi-process`.

Verified live (Arch, Wine 11.19): Hub start, projects, menu, "Search for materials" → ASSETS
render and react as before.

Includes v0.1.14 (Hub settings clickable again). **Update:** run `./install.sh` again so that a
v0.1.13 dcomp shim is replaced; afterwards always start via `./run-csp.sh`.

## v0.1.14 — Hub settings clickable again (regression from v0.1.13)

**Symptom:** the settings window (cog at the top right of the Hub) did not react to any click and
could block the Hub; on a fresh installation the "Security settings" greeting could not be
confirmed. Both worked with v0.1.12.

**Cause:** these dialogs are **not WebView2**. `CLIPStudio.exe` draws them itself via
DirectComposition (own window classes, no DevTools target). The v0.1.13 patch of the `dcomp` shim
(subclassing the target windows, `Present()` forwarding, blit into the parent window) was meant
for Chromium's child windows, but took effect in **every** process — and thereby disabled CSP's
native dialogs. Proven by an A/B test: unpatched DLL only in the Hub folder (= only
`CLIPStudio.exe`) → dialog immediately clickable. Not a missing CSPenguin patch; CSPenguin uses
the unpatched shim and therefore does not have the problem.

**Solution (`bundle/files/src/dcomp-csp-linux.patch`):**
* The patch behaviour now only applies in the process `msedgewebview2.exe`; in `CLIPStudio.exe`
  and `CLIPStudioPaint.exe` the shim behaves exactly like upstream.
* Subclassing via `SetWindowLongPtrW` instead of `…A` (the A variant turned Unicode windows into
  ANSI windows).
* New marker in the DLL: `install.sh` recognises a v0.1.13 shim as **outdated and rebuilds it**;
  `verify.sh` reports it as a warning.

**Update:** run `./install.sh` again (mingw-w64 required, as in v0.1.13).

Verified live (Arch, Wine 11.19, with the DLL built by the installer): dark mode off/on,
"Security settings" → OK closes, Hub navigation (projects, menu) still refreshes.

## v0.1.13 — Hub usable: content stays put, clicks refresh the picture (dcomp shim patched)

**Key point:** the Hub buttons always worked — clicks arrived and the pages loaded. Only the
**new picture never reached the screen**. The cause was the `dcomp` shim, not WebView2.
This corrects the assessment from v0.1.12 ("not a dcomp problem"), which only applied to the 403
cases.

### The causes

| Symptom | Cause |
|---|---|
| Content only flashes up when moving/resizing, a single white pixel at the top left | WebView2 draws into **child windows**. In Wine 11.x they have no drawing surface of their own (`win32u`, `get_window_surface`: `is_child` → `needs_surface = FALSE`). Whatever the shim drew there was wiped by the next repaint of the parent window. `UpdateLayeredWindow` (the v0.1.12 attempt) even lands at screen position (0,0) for child windows |
| **"Buttons do not work"**, menu/cloud "disappear after some time" | The shim only copied a frame on `IDCompositionDevice::Commit()`. Chromium only calls that when the **layer tree** changes — measured 25× in a whole session, never when idle. New frames arrive via `IDXGISwapChain::Present()`, and that was a no-op in the shim. After a click the picture of the last commit therefore stayed — often a still empty, black one |

### The solution (`bundle/files/src/dcomp-csp-linux.patch`)

* Draw the picture into the **parent window's** DC at the child window's offset — it lands in the
  surface Wine actually displays and survives repaints and moves
  (proven with the test program `diag/dcomp-shim/disp-test.c`).
* `Present()` forwards every new frame to the corresponding window immediately.
* Invisible WebView windows (old pages) are skipped, every frame is restricted to the window's
  own rectangle.

Verified live (Arch, Wine 11.19): menu renders completely; "Search for materials" → ASSETS page
appears; chip "New" in the page → search results with preview images appear.

### Delivery: only the patch (license)

The upstream shim (CSPenguin installer) has **no license file**, so the package ships neither its
source nor a built DLL. `install.sh` downloads `dcomp_csp.cpp` + `dcomp.def` from the pinned
commit, **verifies the SHA256**, applies our patch and builds with **mingw-w64**.
The DLL lands in `system32` **and** in both app folders (they take precedence over `system32`).
Existing installations with the unpatched DLL are replaced on the next `./install.sh`.

**New prerequisite (recommended): mingw-w64** — `sudo pacman -S mingw-w64-gcc` /
`sudo apt install g++-mingw-w64-x86-64` / `sudo dnf install mingw64-gcc-c++`. Without it the
installer installs the unmodified upstream DLL as before and says so clearly.

`verify.sh` now reports "patched" or "unpatched upstream version" and warns if a differing
`dcomp.dll` in an app folder shadows the one from `system32`.

**Addendum (after release):** the Paint editor runs with the patched shim without side effects —
drawing and painting work flawlessly (user test, Arch/Wine 11.19). Resizing the Hub window does
not affect the pages. The **Cloud** page works completely: comic files can be downloaded and are
handed over to the editor like on Windows.

### Not yet checked

* The user account/activation code panels, the 32-bit DLL in `syswow64`.

## v0.1.12 — the "403 Forbidden" in the Hub is gone (User-Agent) + reliable panel diagnostics

**Key point:** the remaining empty/black areas in the Hub (and the complaints "the buttons don't
work", "home shows this" with *403 Forbidden / nginx*) had **nothing to do with the dcomp shim**.
The cause was a **User-Agent block on the CELSYS server**.

### The cause

`tips.clip-studio.com` — that is the menu item **"Official tutorials"**, "Tutorials" and the
start page — answers **every** User-Agent containing `Chrome/` with **403 Forbidden (nginx)**.
WebView2 sends exactly that, because Chromium 115 runs underneath. Isolated with `curl`:

| User-Agent | Response |
|---|---|
| `…AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36` | **200** |
| `…Safari/537.36 Edg/115.0.1901.200` | 200 |
| `Mozilla/5.0 (…; rv:115.0) Gecko/20100101 Firefox/115.0` | 200 |
| WebView2 default (`…Chrome/115.0.0.0 … Edg/115.0.1901.200 …`) | **403** |
| Safari UA **plus** `Chrome/115.0.0.0` | **403** |

Only the UA string decides — headers (`Accept`, `sec-ch-ua`, `Sec-Fetch-*`), HTTP/1.1 vs. 2.0 and
the path change nothing. All other CELSYS hosts (`start`, `assets`, `ask`, `share`, `ec`,
`ice`.clip-studio.com) answer 200/302 with both UAs; only `tips` filters.

### The solution

`run-csp.sh` now sets `--user-agent=…Safari/537.36 Win64/NT 10.0/CLIPSTUDIO/5.0.4/DoNotTrack`:

* **no `Chrome/`** → no 403;
* **`CLIPSTUDIO/<version>` is kept** → `menu.js` reads its version from it
  (`main.getIceVer()`, pattern `/(CLIPSTUDIO|CLIP STUDIO PAINT)\/(\d+\.\d+\.\d+)/`). Without this
  part the menu breaks. Anyone adjusting the UA themselves must keep it.

Turn off: `./run-csp.sh --no-user-agent`.

### The other "black" menu items

Measured (panel content via DevTools protocol):

| Menu item | Target | Content |
|---|---|---|
| Use activation code | `ec.clip-studio.com/…/activation-codes/` | 11,024 colours, "Register an activation code" |
| Subscription & purchase of PAINT | `ec.clip-studio.com/…/application?product=paint` | 10,072 colours, "Options All usage plans Ver. 5.0" |
| CLIP STUDIO MODELER | `ice.clip-studio.com/…/guide/page/MS00` | 555 colours, "MODELER 3D setup tool (freeware)" |
| Present your works | `share.clip-studio.com/…/` | "CLIP STUDIO SHARE" |

They looked black because they (a) got the same 403 or (b) open their content in a **new
window**. **Nothing is missing in the dcomp shim** — the reverse-engineering question from the
test report is thereby answered for this case: there is no missing function to rebuild there.

### Reliable measurement instead of a screenshot tool

`verify.sh --panels` used to measure the menu content via `spectacle`/`scrot`/`import`. That was
wrong for two reasons:

1. Under KWin+Wayland the Xwayland root is **empty** (`ffmpeg -f x11grab -i :1` returns 5,115,675
   of 5,115,776 pixels black) — the real pixels live in the Wayland compositor.
2. `spectacle` triggers the KDE dialog **"Request remote control"** on every call — exactly the
   complaint from the test report.

`verify.sh` now measures via the **DevTools protocol** (`files/panelprobe.py`, standard library
only): start the Hub → wait → open the menu via the grid icon → read `innerWidth` and the content
of the menu page. That is independent of whether the compositor gets the picture onto the screen.

### Further changes

* `verify.sh --prefix DIR` is evaluated (previously the live probe always pointed at `~/.wine-csp`).
* `run-csp.sh --debug-port N` — open the DevTools port for diagnostics only.
* New check lines in `verify.sh` (User-Agent replacement, `files/panelprobe.py`); live probe now
  with a wait **and** a click phase. Reference prefix: **19 OK, 0 errors**.
* `files/xdlg.c` now closes the blocking dialog via `XRaiseWindow` + `XSetInputFocus` +
  `Return` (a mouse click alone was not enough — Wine swallows clicks on a window without input
  focus), followed by a success check.

### Artifacts

| File | Size | SHA256 |
|---|---|---|
| `csp-linux-bundle-0.1.12.tar.gz` | 207,280 B | `8fb899a6af902e546ab1792d249af617ba3e0d09e4f08160da6c89963565ff6c` |
| `csp-linux-bundle-0.1.12-offline.tar.gz` | 220,559,004 B | `f4bd47d972888afa9f68734887f84ae75b217f8407abcfad5feb7aec0082b777` |

The tarballs sit (like the earlier ones) in the repo directory, but are not versioned because of
`.gitignore`. Publish: `./publish-github.sh` (tags HEAD as `v0.1.12` and uploads the four artifacts).

## v0.1.11 — panels in the Hub menu are really drawn (`--in-process-gpu`)

**Correction to v0.1.10.** The reasoning there was wrong: the viewport does **not** collapse
without the WebView2 arguments — `innerWidth = 1` only means "menu panel is currently collapsed".

**The actual problem:** the page renders the menu completely and correctly — measured via DevTools
(`Page.captureScreenshot`): 448×644, 2350 colour shades, 96.4 % non-white, identical to the
target picture. In the X window, however, only the background fill arrived: 133 colour shades, 52 %
of them the fill colour (grey or black/white depending on the theme). Repaint nudges (window ±1 px,
minimise/open the Hub, close/open the menu) changed nothing. So a **presentation problem**:
Chromium's compositor subprocess does not push the GPU surface into the Wine window, and the
`dcomp` shim (GDI blit of the GPU texture) does not take effect because the texture lives in
another process.

**Solution: `--in-process-gpu`.** With it the GPU work runs in the main process and the shim can
blit the content. Counter-test with fresh runs, panel window counted by screenshot:

| Arguments | Panel window |
|---|---|
| `--no-sandbox` | **138 colour shades** (fill only) |
| `--no-sandbox --in-process-gpu` | **4309 colour shades**, menu complete |
| `--no-sandbox --disable-gpu-compositing` | viewport collapses |
| `--no-sandbox --disable-gpu-compositing --in-process-gpu` | **138** = broken again |

**Changed**
- **`run-csp.sh`**: `--disable-gpu-compositing` (and `--disable-gpu`) **removed** from the CSPenguin
  argument set — it forces the software path and bypasses the shim. New switch **`--menu-open`**
  (open the menu automatically after start; the default is **off**, because the click on the grid
  icon has to be timed). The documentation in the script explains the measurements.
- **`verify.sh --panels`**: live probe rewritten — starts the Hub, **opens the menu** and counts the
  colour shades in the menu window (`> 1000` = visible); without a screenshot tool it stays with the
  viewport measurement. It also checks whether `run-csp.sh` sets the arguments.
- **`files/xdlg.c`**: in the "not closed properly" dialog it now clicks the **button** (before:
  title bar + Return — repeated Return opened PAINT again and again and the dialog came back, the
  Hub stayed blocked). Opening the menu now waits ~20 s for WebView2 and cyclically checks whether
  the menu window has area.
- **`bundle/README.md`**: §3c completely rewritten (cause, measurement table, "1×1 only means
  collapsed", the blocking dialog), troubleshooting table extended by the two cases.

**Known limits**
- Opening the menu automatically by click is **not** the default: the click can also close the
  menu again and WebView2's readiness varies (observed 42 s to >2 min). When in doubt, just click
  the grid icon at the top right yourself.
- DXVK/VKD3D stay in as the bundle default, but are **not** needed for the menu content.

## v0.1.10 — GPU path (DXVK/VKD3D) + WebView2 arguments

⚠️ **The reasoning of this section is superseded by v0.1.11** (see above): the arguments are not
"mandatory for clickable buttons"; `innerWidth=1` only means that the panel is closed.
The GPU path itself (DXVK/VKD3D, `dxvk.conf`, `uninstall.sh --gpu`) remains valid unchanged.

**New**
- **`install.sh` installs DXVK + VKD3D** (`winetricks -q dxvk vkd3d` — DXVK 3.1.1,
  vkd3d-proton 3.0.1, as in the CSPenguin installer) and writes `<prefix>/dxvk.conf`:
  `dxgi.deferSurfaceCreation = True`, `dxvk.enableGraphicsPipelineLibrary = True`,
  `dxvk.numCompilerThreads = 0`, `dxvk.maxChunkSize = 16`. New switch **`--no-dxvk`**.
- **`run-csp.sh` sets at startup** (from v0.1.11 **without** `--disable-gpu-compositing`, see
  above): `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` (`--no-sandbox --in-process-gpu
  --disable-gpu-vsync …`), `DXVK_CONFIG_FILE`, `DXVK_STATE_CACHE`,
  `DXVK_ASYNC`, `mesa_glthread=true`, `RADV_PERFTEST=gpl`. New switch **`--no-gpu-env`** (diagnostics).
- **`verify.sh`** now additionally checks: DXVK/VKD3D in `winetricks.log`, **native `d3d11.dll`
  (> 1 MB = DXVK active, builtin ~200 KB)**, `dxvk.conf` with `deferSurfaceCreation`, and whether
  `run-csp.sh` sets the WebView2 arguments (5 new checks, → 16 OK / 0 errors).
- **`uninstall.sh --gpu`** takes back the GPU path (overrides `*dxgi/*d3d9/*d3d10core/*d3d11/
  *d3d12/*d3d12core/*d3d8`, `dxvk.conf`, `winetricks.log` entries).
- **README**: new section **3c** (GPU path + clickable Hub buttons), extended checklist
  (Hub menu with content + clickable), three new troubleshooting rows (black menu/dead buttons,
  slow panels, "not closed properly" dialog).

**Tested on the Arch reference** (Intel UHD, Mesa): DXVK 3.1.1 loads in the editor and in the Hub
(`info: DXVK: v3.1.1`, Vulkan init via `winevulkan.dll`, shader cache in
`AppData/Local/dxvk/*.dxvk.bin`); no new errors (only cosmetic:
`readMonitorEdidFromKey: Failed to get EDID reg key size`). Verified with a stub Wine that all
variables really arrive in the Wine/WebView2 process.

**Unchanged**: pen pressure fix (DLL v0.6), dcomp shim, addon logic (Gecko/Mono), menu entries,
tilt control (default 9), requirements (Wine ≥ 11.19).

**Artifacts**
| File | Contents |
|---|---|
| `csp-linux-bundle-0.1.10.tar.gz` | installer + fix + docs (slim, needs internet for addons/DXVK) |
| `csp-linux-bundle-0.1.10-offline.tar.gz` | additionally Gecko 2.47.4 + Mono 10.4.1/11.3.0 (offline-capable) |
| `…tar.gz.sha256` | SHA-256 checksums |

> **Note:** DXVK is downloaded via `winetricks` (internet needed). Without a network the step
> fails, the package keeps running — only the Hub panels may stay black/empty. The offline package
> does **not** contain DXVK (winetricks pulls it at installation time).

## v0.1.9 — info categories of the DLL: real device name + complete `WTInfo`

No new user-facing feature, but two comfort/correctness points from the TODO list (section B).
The event and pressure path is **unchanged**.

**Changed (DLL v0.6)**
- **Real device name for `WTInfo(WTI_DEVICES, DVC_NAME)`** instead of the placeholder
  "XWayland Tablet (XWinTab/XI2)": resolution via `XWINTAB_DEVICE_NAME` →
  sidecar file `XWinTabDeviceName.txt` next to the DLL (written by `install.sh`,
  determined with the new tool `files/xi2-devname.c`) → `XWINTAB_DEVICE` → placeholder.
- **`WTInfo` complete**: `WTI_DDCTXS` (400) including the `CTX_*` indices, `WTI_DDCTXS + n` (n ≥ 1) = 0,
  `WTI_EXTENSIONS` explicitly = 0 (no extensions), `WTI_INTERFACE` complete
  (`IFC_SPECVERSION`, `IMPLVERSION`, `NDEVICES`, `NCURSORS`, `NCONTEXTS`, `CTXOPTIONS`,
  `CTXSAVESIZE`, `NEXTENSIONS`, `NMANAGERS`) as well as `DVC_HARDWARE` / `DVC_NCSRTYPES` /
  `DVC_FIRSTCSR`. **The CSP log no longer contains `unhandled cat …`.**
  Semantics compared against Wine's built-in `wintab32`; the comparison is documented in
  `CSP-TABLET-FIX.md` §7.

**Fixed (bundle)**
- `install.sh` reads the version from `VERSION` (was hard-wired to 0.1.8 — output and tarball
  could diverge).
- **Addon detection corrected**: `install.sh` and `verify.sh` now also recognise Wine Gecko/Mono
  when they come from a **distro package** (`/usr/share/wine/gecko|mono/…`) — Wine loads these
  trees directly (`mshtml`: `load_gecko()`, `mscoree`: `get_mono_path()`), and only afterwards
  installs from an MSI or downloads. Before, an Arch machine with `wine-gecko`/`wine-mono`
  wrongly reported "Gecko missing/would be installed" (and the installer would have downloaded
  54 MB unnecessarily).
- `files/xi2-probe.c` now uses `$DISPLAY` (before hard-coded `:1` — failed on machines with
  another display).

**Unchanged**: `install.sh` flow/switches, menu entries, addon logic (Gecko/Mono),
`dcomp` shim, `run-csp.sh`, tilt control (default 9), requirements (Wine ≥ 11.19).

**New in the package**: `files/xi2-devname.c` (device name), `verify.sh` shows the source of the
device name; `uninstall.sh` also removes the sidecar file.

**Artifacts**
| File | Contents |
|---|---|
| `csp-linux-bundle-0.1.9.tar.gz` | installer + fix + docs (slim, needs internet for addons) |
| `csp-linux-bundle-0.1.9-offline.tar.gz` | additionally Gecko 2.47.4 + Mono 10.4.1/11.3.0 (offline-capable) |
| `…tar.gz.sha256` | SHA-256 checksums |

## v0.1.8 — CLIP STUDIO PAINT 5 on Linux (distribution package)

Tested ✅ on **Arch** (system Wine 11.19) and **Fedora** (Wine 11.0 + portable
Wine 11.19, AMD/radv): editor, pen pressure, panels and login.

**Prerequisite:** Wine ≥ 11.19 (WinRT class `Windows.UI.Input.RadialController`);
always start via `run-csp.sh` (sets `PATH`/`WINELOADER`/`WINESERVER`; `--kill`
against "version mismatch").

**Included**
- **Pen pressure fix**: patched `wintab32.dll` + `XWinTabHelper.dll.so`
  (+ CSP compat exports, `WTQueuePacketsEx`) — no ghost strokes.
- **dcomp shim** for WebView2 panels (Hub, settings, login) — no longer white.
- **Version-exact Wine addons**: Gecko 2.47.4 + Mono (11.0 → 10.4.1, 11.19 → 11.3.0).
- **`run-csp.sh`** launcher, idempotent `install.sh`, `verify.sh`, `uninstall.sh`.
- Tilt control `XWINTAB_ALT_SCALE` (DLL default **9**).

**Artifacts**
| File | Contents |
|---|---|
| `csp-linux-bundle-0.1.8.tar.gz` | installer + fix + docs (slim, needs internet for addons) |
| `csp-linux-bundle-0.1.8-offline.tar.gz` | additionally Gecko 2.47.4 + Mono 10.4.1/11.3.0 (offline-capable) |
| `…tar.gz.sha256` | SHA-256 checksums |

## v0.1.18 - Several Fixes
- There were several fixes untracked in the private repo between these versions.

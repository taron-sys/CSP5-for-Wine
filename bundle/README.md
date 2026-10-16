# CLIP STUDIO PAINT on Linux — test package (v0.1.17)

Hello! This package installs **CLIP STUDIO PAINT 5** into its own Wine environment and ships a
**pen pressure fix** (Wine's built-in Wintab delivers no pressure under Linux and sporadic
"ghost strokes").

> **Status: tested ✅** — runs on Arch Linux (system Wine 11.19) and on Fedora
> (Wine 11.0 + portable Wine 11.19, AMD GPU): editor, pen pressure, panels and login.
>
> **Important:** always start through **`./run-csp.sh`** (it sets the Wine paths **and** the
> WebView2/GPU variables correctly; otherwise you get `wine client error: version mismatch`, or
> the Hub menu stays empty and cannot be clicked — see section 3c).
>
> **Please read this once completely, then get going.** If something goes wrong there is a
> troubleshooting section below, and a `verify.sh` that looks for problems.
> Everything can be removed without leftovers (`uninstall.sh`, `--gpu` for the GPU path).

---

## 1. What you need

| Requirement | Details |
|---|---|
| Linux with X11 or Wayland | tested on Arch + KDE/Wayland (XWayland); should work anywhere with a current Wine |
| **Wine** | **≥ 11.19 recommended** (tested: 11.19-staging on Arch). ⚠️ **Wine 11.0 (Fedora) is not enough** — it lacks the WinRT class `Windows.UI.Input.RadialController`, and CSP 5 crashes when opening the editor. Install/update: `sudo pacman -S wine` (Arch) / `sudo dnf upgrade wine-staging` or the WineHQ repo (Fedora) / `sudo apt install wine` (Debian/Ubuntu). **Addons in advance (saves Wine's download):** `sudo pacman -S wine-gecko wine-mono` (Arch) or `sudo dnf install wine-gecko wine-mono` (Fedora) — Wine loads these system trees directly (`/usr/share/wine/{gecko,mono}/…`) and then does not ask. Check: `./verify.sh` or `wine files/winrt-probe.exe` (5 × OK). With a Wine that is too old and no way to install a new one: **portable Wine** (see section 2; `install.sh` fetches it automatically) |
| **CSP installer** | `CSP_504w_setup.exe` (official CELSYS download). `install.sh` downloads it itself if it does not find one; or put it next to the script / pass `--installer /path/...` |
| **mingw-w64** (recommended) | builds the patched `dcomp` shim during installation, without which the Hub does not refresh after clicks (section 3b). `sudo pacman -S mingw-w64-gcc` (Arch) / `sudo apt install g++-mingw-w64-x86-64` (Debian/Ubuntu) / `sudo dnf install mingw64-gcc-c++` (Fedora). Without it the unpatched version is installed |
| Wacom-compatible tablet | X input device with "stylus" or "pen" in its name (Wacom, Huion, XP-Pen, …) |
| ~4 GB disk space | Wine prefix with CSP (about 2.7 GB) + installer |
| Graphical session | no pure SSH operation (CSP needs X11/Wayland) |

## 2. Installation

```bash
# 1) unpack
tar xzf csp-linux-bundle-<VERSION>.tar.gz
cd csp-linux-bundle-<VERSION>

# 2) install
./install.sh
```

**What `install.sh` downloads itself** (none of this has to be fetched beforehand):

- **CSP installer** 5.0.4 (`CSP_504w_setup.exe`, ~470 MB) from the official CELSYS server
  `vd.clipstudio.net`, only if none is found (searched: next to the script, `~/Downloads`, `~`,
  current directory). The SHA256 is pinned. Another version: `--csp-version 512` (untested, not
  hash-checked). Your own file: `--installer PATH`.
- **Portable Wine 11.19** (Kron4ek build, ~100 MB, SHA256 from the release) if system Wine is
  missing or older than 11.19. It is unpacked to `~/.local/share/wine-portable` and noted in the
  prefix; `run-csp.sh`, `verify.sh` and later `install.sh` runs use it automatically. Force system
  Wine with `--system-wine`.

The script can be **run repeatedly** (idempotent) and does the following:

1. Check prerequisites (Wine, display, package files)
2. Create the Wine prefix at `~/.wine-csp` (`--prefix` changes that)
3. **Install CSP silently** (a window appears briefly; takes a few minutes)
4. Install the **pen pressure fix**: copy `wintab32.dll` + `XWinTabHelper.dll.so` into the
   app directory and set `wintab32=native`
5. Create menu entries ("CLIP STUDIO PAINT" = editor, "CLIP STUDIO (Hub)" = login/assets).
   They start **`run-csp.sh`** (not `wine` directly), i.e. with all the fixes: WebView2 arguments,
   GPU path, User-Agent, dialog dismisser, one-renderer mode, the right (portable) Wine.
   A copy of the launcher lives in `<prefix>/csp-launcher/` — so the entries keep working even if
   the unpacked bundle is deleted. Icons are extracted from the EXEs
6. Print instructions

Before that come two steps for the **WebView2 panels** (Hub centre, settings, login):

- **`dcomp` shim** (DirectComposition) — otherwise the panels stay white (section 3b)
- **GPU path: DXVK + VKD3D** via `winetricks` + `dxvk.conf` (section 3c). Needed because WebView2
  outputs its content via DirectComposition/d3d under Wine; Wine's own d3d implementation delivers
  only a **black/empty** overlay on some systems (mainly AMD/radv).

If you **already** have CSP in a Wine prefix (only install the fix afterwards):
```bash
./install.sh --no-csp --prefix /path/to/your/prefix
```
More options: `--check` (only check, change nothing) · `--wine-portable [VER]` (download + use
portable Wine even with a current system Wine) · `--system-wine` · `--csp-version VER` ·
`--wine-bin DIR` (own Wine) · `--no-addons` · `--no-dcomp` · `--dcomp-dir DIR` ·
`--no-dxvk` (leave out the GPU path) · `--addon-msi-dir DIR` · `--no-shortcuts` ·
`--installer PATH`

### If the system Wine version is too old (no update possible)

CSP 5 needs **Wine ≥ 11.19** (WinRT classes `RadialController`/`StorageFile`; older versions make
the editor crash). If system Wine is older (or missing), `install.sh` downloads portable Wine
11.19 **automatically** (since v0.1.16; `--system-wine` turns this off).

Controlling the portable Wine by hand:

```bash
./install.sh --wine-portable                 # downloads Wine 11.19 (~100 MB), unpacks to
                                             # ~/.local/share/wine-portable and uses it
./install.sh --wine-portable 11.20           # another version
./install.sh --wine-portable-dir /path       # another target directory
```

**Advantage:** everything happens on the target machine — **no symlinks** have to be
transferred (USB sticks destroy them). The file is checked against the release's
`sha256sums.txt`; the Wine path is noted in the prefix (`portable-wine-path`), so that `verify.sh`
and the menu entries use it **automatically** afterwards.

Manually (if the download in the script fails): put the tarball from
<https://github.com/Kron4ek/Wine-Builds/releases> (e.g. `wine-11.19-staging-amd64-wow64.tar.xz`)
next to `install.sh`, or unpack it and use `--wine-bin <unpacked>/bin`.
The **`wow64` variant** also runs without 32-bit system libraries.

**Proton is not a replacement:** GE-Proton 9-27 = Wine 9.0, GE-Proton 8-32 = Wine 8.0 — both older
than 11.0 and without these classes (tested: 5/5 missing).

### If the addon download fails (no network/proxy/firewall)

The installer downloads the Wine addons from the internet (`dl.winehq.org`). If that does not
work there are two ways:

**a) Provide the MSIs (offline, recommended in case of problems)** — simply **put the two files**
`wine-gecko-<ver>-x86_64.msi` and `wine-mono-<ver>-x86.msi` **next to `install.sh`**
(or into a folder and pass `--addon-msi-dir DIR`). The installer then takes them from there,
without any download. Sources:
`https://dl.winehq.org/wine/wine-gecko/` and `https://dl.winehq.org/wine/wine-mono/`
(versions: see the line "Wine expects …" in the installer output).

**b) Let Wine install them itself** — on first start Wine shows the missing-addon dialog; click
**"Install"** there (Wine then downloads them itself). Works only with internet. Afterwards
restart the application.

## 3. First start

> **If a small white/empty window appears over the application:**
> that is Wine's notice that an addon is missing — **Wine Gecko** (for embedded
> HTML/IE interfaces) or **Wine Mono** (.NET). Please click **"Install"** and wait
> (download about 50–140 MB). Without Gecko such interfaces stay empty/white.
> `install.sh` already tries that automatically (step 2b) — this dialog only appears if the
> download failed or was skipped with `--no-addons`.
> Afterwards close the application once and start it again.

1. Open menu → **CLIP STUDIO (Hub)** and log in there (CELSYS account).
   *The login needs the WebView2 runtime — the CSP installer installs it
   automatically. With CLIP STUDIO 2/3 the login used to fail exactly because of that;
   with CSP 5 it works with WebView2 installed.*
2. Open menu → **CLIP STUDIO PAINT** (editor). Simplest is to use this entry directly —
   the Hub is only needed for login/assets.
3. Create a new document and draw with a pressure-sensitive brush
   (e.g. "G-Pen" or "Millet"; brush size dynamics = pen pressure).

## 3b. White/empty windows in CSP (Hub, settings, login) — the `dcomp` shim

**Symptom:** the native UI renders (sidebar, menus), but the **content stays white** —
e.g. the centre of the "CLIP STUDIO START" Hub, the **settings** window, login/asset areas.
These areas are **WebView2** panels; under Wine they lack the DirectComposition connection,
which leads to white panels depending on GPU/driver (often with AMD/radv, other Wine versions).

**Solution:** a `dcomp.dll` shim (from the CSPenguin project, **with our patch**) +
`dcomp=native,builtin`.

```bash
./install.sh                                            # download source, patch, build (default)
./install.sh --dcomp-dir /path/to/CSPenguin-Installer   # source from a local checkout (offline)
./install.sh --no-dcomp                                 # do not install
```

Flow in the installer:

1. Download `dcomp_csp.cpp` + `dcomp.def` from the CSPenguin repo (pinned commit, **SHA256 verified**)
2. Apply `files/src/dcomp-csp-linux.patch`
3. Build with **mingw-w64** and copy to `system32` **and** into both app folders (the app folders
   take precedence over `system32` — an old copy there would shadow the new one)
4. Set the Wine override `dcomp=native,builtin`

An existing prefix with the unpatched DLL **or the v0.1.13 patch** is updated automatically on
the next `./install.sh`. Since v0.1.14 the patch only takes effect **in the WebView2 process**
(`msedgewebview2.exe`); CSP's own dialogs drawn via DirectComposition (settings, security
settings) run with the unmodified upstream behaviour. **Without mingw-w64** the installer falls
back to the unmodified upstream DLL: the Hub then shows content only sporadically, and **clicks
seem to do nothing** (see below).

**What the patch fixes** (Wine 11.x):

| Problem | Cause | Patch |
|---|---|---|
| Content only flashes up when moving/resizing and disappears again | WebView2 draws into a **child window**; child windows have no drawing surface of their own in Wine (`win32u`: `get_window_surface` → `needs_surface = FALSE`). Whatever lands there is wiped by the next repaint of the parent window | Draw the picture into the **parent window's** DC at the child window's position — it lands in the surface Wine really displays and stays there |
| **Buttons "do not work"** — the click arrives, the page loads, but the picture stays old/black | The shim only copied a frame on `IDCompositionDevice::Commit()`. Chromium only calls that when the **layer tree** changes (a few dozen times per session); new frames arrive via `IDXGISwapChain::Present()` — and that did nothing | `Present()` forwards every new frame to its window immediately |
| Old page paints over the new one | Several WebView windows share a parent window and position; invisible ones drew as well | Skip invisible windows, restrict to the own rectangle |

**Note on the license:** the upstream shim is third-party code **without a license file** — so the
package ships neither its source nor a DLL built from it, but **only our patch**. The installer
downloads the upstream files directly from the CSPenguin repo.

Check: `./verify.sh` (line "dcomp shim"), and whether the process loads it:
```bash
grep -c dcomp.dll /proc/$(pgrep -f 'CLIPStudio.exe' | tail -1)/maps     # > 0 = loaded
```

## 3c. GPU path: DXVK + VKD3D — and visible Hub panels

**Symptom — the panels stay black (dark theme) or white (light theme) although the menu reacts
to clicks:** the `dcomp` shim is active (section 3b), and the page also renders correctly —
but the content never arrives in the window. Cause: WebView2 runs with its own compositor
process; its GPU surface is overwritten by Wine's compositor with the window's GDI surface, and
only the background fill is left. The shim works around that by blitting the GPU texture onto
the window DC with `SetDIBitsToDevice` — but that only takes effect if the GPU work runs in the
**main process**.

**Solution:** the installer installs **DXVK + VKD3D** (`winetricks -q dxvk vkd3d`) and writes
`<prefix>/dxvk.conf`; **`run-csp.sh` sets** the necessary variables automatically at startup.

```bash
./install.sh --no-dxvk      # skip the GPU path (use Wine's own d3d)
./run-csp.sh hub            # Hub/login — the buttons are needed here
./run-csp.sh --no-gpu-env   # diagnostics: do NOT set the variables
./run-csp.sh --no-user-agent # diagnostics: do NOT replace the User-Agent (see below)
./run-csp.sh --multi-process # Chromium's default process model (~3.5 GB more RAM, see below)
./run-csp.sh --menu-open    # open the menu automatically after start (experimental)
./run-csp.sh --debug-port 9222  # open a DevTools port (diagnostics only)
```

What `run-csp.sh` sets:

| Variable | Effect |
|---|---|
| `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` | `--no-sandbox --in-process-gpu --disable-gpu-vsync … --user-agent=…` — **`--in-process-gpu` is the decisive switch** (see below) |
| `DXVK_CONFIG_FILE` | `<prefix>/dxvk.conf` with `dxgi.deferSurfaceCreation = True` (WebView2 needs the deferred surface creation) |
| `DXVK_STATE_CACHE`, `DXVK_ASYNC` | shader cache (only if DXVK is in the prefix) |
| `mesa_glthread=true`, `RADV_PERFTEST=gpl` | Mesa/AMD optimisations as in CSPenguin |

### Why the User-Agent is replaced (otherwise "403 Forbidden")

The menu items **"Official tutorials"** and **"Tutorials"** and the start page call
`tips.clip-studio.com`. This host returns **403 Forbidden (nginx)** to **every** User-Agent
containing `Chrome/` — and that is exactly what WebView2 sends, because Chromium 115 runs
underneath. Measured with `curl`:

| User-Agent | Response |
|---|---|
| `…AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36` | **200** |
| `…Safari/537.36 Edg/115.0.1901.200` | 200 |
| `Mozilla/5.0 (…; rv:115.0) Gecko/20100101 Firefox/115.0` | 200 |
| WebView2 default (contains `Chrome/115.0.0.0 … Edg/…`) | **403** |
| Safari UA **plus** `Chrome/115.0.0.0` | **403** |

Only the UA string decides: headers (`Accept`, `sec-ch-ua`, `Sec-Fetch-*`), HTTP/1.1 vs. 2.0 and
the path change nothing. All other CELSYS hosts (`start`, `assets`, `ask`, `share`, `ec`,
`ice`.clip-studio.com) answer 200/302 with both UAs — only `tips` filters.

`run-csp.sh` therefore sets
`--user-agent=…Safari/537.36 Win64/NT 10.0/CLIPSTUDIO/5.0.4/DoNotTrack`:

* **no `Chrome/`** → the 403 disappears,
* **`CLIPSTUDIO/<version>` stays** → `menu.js` reads its version from it
  (`main.getIceVer()`, pattern `/(CLIPSTUDIO|CLIP STUDIO PAINT)\/(\d+\.\d+\.\d+)/`). Without the
  marker the menu breaks. Anyone adjusting the UA must therefore keep this part.

Turn off: `./run-csp.sh --no-user-agent`.

### The other "black" menu items

Also measured (panel content read out via the DevTools protocol):

| Menu item | Target | Content |
|---|---|---|
| Use activation code | `ec.clip-studio.com/…/activation-codes/` | 11,024 colours, "Register an activation code" |
| Subscription & purchase of PAINT | `ec.clip-studio.com/…/application?product=paint` | 10,072 colours, "Options All usage plans Ver. 5.0" |
| CLIP STUDIO MODELER | `ice.clip-studio.com/…/guide/page/MS00` | 555 colours, "MODELER 3D setup tool (freeware)" |
| Present your works | `share.clip-studio.com/…/` | "CLIP STUDIO SHARE" (loads in a new window) |

They looked black because they (a) got the same 403 or (b) open their content in a
**new window**. **It is not a dcomp shim bug** — there is nothing to rebuild there.

### Why `--in-process-gpu` — and why `--disable-gpu-compositing` is wrong here

Measured on the reference system (Intel UHD, Wine 11.19): open the menu and count the panel
window's colours via screenshot ("colours" = different shades in the window; the plain
background fill gives ~138):

| Arguments | Panel window | Verdict |
|---|---|---|
| `--no-sandbox` | **138 colours**, all black | content missing (but clicks work!) |
| `--no-sandbox --in-process-gpu` | **4309 colours**, menu complete | ✅ as it should be |
| `--no-sandbox --disable-gpu-compositing` | viewport collapses | ❌ unusable |
| `--no-sandbox --disable-gpu-compositing --in-process-gpu` | **138 colours** = black again | ❌ cancels the effect |

> **Note:** `--disable-gpu-compositing` was in the CSPenguin installer, but is **counterproductive**
> here — it forces the software path and thereby bypasses exactly the shim that makes the content
> visible. It was therefore **removed** (together with `--disable-gpu`) from the default arguments.
>
> **And:** `--no-sandbox` alone is enough for the Hub; DXVK is not needed for the menu content
> (tested with Wine's builtin d3d: same black state). The GPU path stays in anyway —
> it does no harm and helps with drawing.

### Memory: why only one WebView2 renderer

Under Wine **every** WebView2 process holds its own private copy of `msedge.dll` (~230 MB).
The DLL is built with 512-byte alignment. Wine therefore cannot map it directly from the file
and reads it anew into every process; Windows shares it between processes.
In the default model WebView2 starts ~11 processes for the Hub (one `CrRendererMain` per panel,
plus network/storage services), measured at **~5 GB right after start**.

`run-csp.sh` therefore sets `--renderer-process-limit=1 --disable-site-isolation-trials` and moves
the network service into the browser process (`NetworkServiceInProcess2`): **4 processes,
~1.5 GB** (measured with the ASSETS page open: 1.55 GB). Downside: if one page hangs, all panels
hang with it. Back to the default: `./run-csp.sh --multi-process`.

### Common misunderstanding: "viewport 1×1 px"

A viewport of `1×1` **only means that the menu panel is currently collapsed** — not that
something is broken. Conversely: if the panel content is missing, the menu entries are still
**clickable** (in the test a click on "Official tutorials" correctly opened `tips.clip-studio.com`).
So **open** the menu first, then measure.

### The dialog "not closed properly"

After a hard exit (`pkill`, `wineserver -k`) CSP shows a dialog on the next start that
**completely blocks** the Hub: WebView2 does not start at all, there is no menu. `run-csp.sh`
clicks it away automatically (`files/xdlg.c` is built with `gcc` for that; without `gcc` a note
appears). Turn off with `--no-dialog-fix`.

Check: `./verify.sh` → lines "GPU path", "run-csp.sh sets WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"
and "replaces the User-Agent"; and `./verify.sh --panels` for the **live probe**: it starts the
Hub, opens the menu, measures the viewport and reads the content via the DevTools protocol.
With `./verify.sh --prefix DIR` another prefix can be checked.
Roll back: `./uninstall.sh --gpu`.

> **Important:** `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` only takes effect if the variable is set
> **when the Hub starts** — so start via `run-csp.sh hub` (or export the variable yourself).
> The menu entries `install.sh` creates do that (since v0.1.17). Older entries — and the ones
> the CSP installer itself creates ("CLIP STUDIO" under *Wine → Programs*) — start `wine`
> directly; running `./install.sh` again redirects them (`./verify.sh` reports it).

## 4. Checklist for you as a tester

Please tick off every item (and note everything unusual — even small things):

- [ ] **Installation** ran through without an error message (`./install.sh` ends with "done")
- [ ] `./verify.sh` shows **0 errors** at the end
- [ ] **Hub login** works
- [ ] **Editor starts** up to the canvas
- [ ] **Pen pressure**: stroke width visibly varies with pressure (press lightly → thin, firmly → thick)
- [ ] **Tilt**: the brush gets wider when tilting — does that feel natural? (default factor 9; see section 5)
- [ ] **No "ghost strokes"** (strokes that suddenly shoot across the canvas)
- [ ] **Drawing is smooth** — no dropouts/hangs
- [ ] **Saving/loading** a `.clip` file
- [ ] **Pen diagnostics**: `WINEPREFIX=~/.wine-csp wine "~/.wine-csp/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/t5w.exe"`
      → a window opens, drawing over it shows lines with **changing** `pressure=` values
- [ ] **Second start**: close CSP and start it again — does it still work?
- [ ] **Hub menu** (cog/grid icon at the top right) opens **with content** (icons + labels, no white/black area) — and an entry like "Official tutorials" **can be clicked** and opens the page
- [ ] **Hub menu, click through all items**: activation code, subscription & purchase, MODELER, present your works,
      draw comics, EPUB, customer service, questions & answers — is there **content** everywhere (no 403, no empty area)?
- [ ] **Hub sidebar**: Home, Projects, Notifications, User account, Cloud, Materials — does the content load?
- [ ] **Unplug/plug in the tablet** during operation — does CSP behave sensibly?
- [ ] **Several documents / long session** (at least 15 min) — any dropouts at some point?
- [ ] **Tablet system settings** (e.g. Wacom pressure curve) changed → does it take effect in CSP?

## 5. Adjusting tilt (optional)

If the brush gets too fast/too wide when tilting, change the factor:

```bash
XWINTAB_ALT_SCALE=7 WINEPREFIX=~/.wine-csp wine "C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe"
```
*The default is **9** (tested as comfortable on the reference machine). **Smaller = gentler** —
try 8, 7, 6 …; `10`–`15` is more aggressive (15 = Wine's own default).*

Seeing the values in detail (writes a log):
```bash
XWINTAB_LOG=1 WINEPREFIX=~/.wine-csp wine "…\CLIPStudioPaint.exe"
# log: ~/.wine-csp/drive_c/users/<you>/XWinTabLog.txt
#   "tilt config: base=900 scale=9"
#   "event: x … y … p … tltx 54 tlty -10 …"
```

## 6. Troubleshooting

**Run `./verify.sh` first** — it checks Wine, CSP, fix files (incl. hash), the Wine override
and, if applicable, the tablet at the X level.

| Problem | Cause / solution |
|---|---|
| `wine not found` | Install Wine (see requirements) |
| No window / abort "without display" | You are not in a graphical session (`echo $DISPLAY` / `$WAYLAND_DISPLAY`) |
| CSP installer not found / download failed | Download the installer yourself and put `CSP_*setup.exe` next to the script, or `--installer …` |
| Installation hangs | Look at the log: `~/.wine-csp/install-csp.log` — the CSP setup can take several minutes |
| **No pen pressure** | 1) `./verify.sh` → check DLL hash + override. 2) Is CSP still running in the old state? Close CSP completely and restart. 3) Check which `wintab32` the process uses: `grep -i wintab /proc/$(pgrep -f 'CLIPStudio[P]aint.exe')/maps` → the path **in the CSP app directory** must be listed (not `/usr/lib/wine/...`). 4) Start `t5w.exe` and draw over it: do changing `pressure=` values appear? If not → check the tablet at the X level: `./verify.sh --tablet` |
| **Ghost strokes** | should be gone with the fix. If they reappear: take a note (when? at stroke start? after pauses?) — and enable `XWINTAB_LOG=1`, then the packet sequence is visible |
| Brush gets too wide when tilting | see section 5 (lower the factor) |
| **Many error messages at start** ("Unhandled exception … starting debugger", JIT messages) | They come from the **Hub/WebView2**, not the editor. Either start the editor directly, or clear Wine's JIT debugger: `WINEPREFIX=~/.wine-csp wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Debugger /t REG_SZ /d "" /f` |
| **Content in CSP stays white** (Hub centre, settings, login/assets) | **WebView2 panel without DirectComposition** → install the dcomp shim: `./install.sh --dcomp-dir …` or without argument (download). See section 3b |
| **Hub buttons seem not to react** (click → nothing happens, content stays old or black) | Unpatched dcomp shim (mingw-w64 was missing during installation). `./verify.sh` then reports "unpatched upstream version" → install mingw-w64 (section 1) and run `./install.sh` again. See section 3b |
| **Hub settings (cog) or "security settings" not clickable** | dcomp shim from v0.1.13 (`./verify.sh` reports "outdated v0.1.13 patch") → run `./install.sh` again |
| **Many `CrRendererMain` processes, several GB of RAM** | Hub not started via `run-csp.sh` (or `--multi-process`). See section 3c "Memory" |
| **"403 Forbidden" / "nginx" in the Hub** (start page or menu "Official tutorials") | Host `tips.clip-studio.com` blocks User-Agents with `Chrome/` → use `./run-csp.sh hub` (sets a suitable User-Agent). See section 3c |
| **Hub menu stays black/empty, but reacts** | `run-csp.sh` not used → `--in-process-gpu` missing. Check live with `./verify.sh --panels` |
| **Hub does not start / no WebView2** (no menu, no window content) | The "not closed properly" dialog blocks it → `run-csp.sh` normally clicks it away itself; without `gcc` press "Open CLIP STUDIO" yourself |
| **Menu in the Hub is black/empty (buttons react though)** | Start via `./run-csp.sh hub` — the launcher sets the necessary WebView2 arguments; **`--in-process-gpu` is decisive** (see section 3c). Without it the panel content stays invisible (only the background fill: ~138 colours instead of ~4300). Important: **never add `--disable-gpu-compositing`** — it breaks exactly that again. Check live with `./verify.sh --panels`. For diagnostics: `WINEDEBUG=+dcomp` (the shim writes its log to `<prefix>/drive_c/dcomp-csp.log`) |
| **The menu does not come at all (no menu window, no WebView2)** | (a) Is the "not closed properly" dialog open? It blocks the Hub completely — `run-csp.sh` clicks it away (needs `gcc`), otherwise click "Open CLIP STUDIO" yourself. (b) After a start wait ~30–40 s, then click the grid icon at the top right. (c) Panel viewport `1×1` **only** means: the menu is closed — not an error |
| Panel loads very slowly / stays empty at first | The Hub panels come from the CELSYS servers ("Home", shop) — that can take **1–2 minutes**; that is not a Wine problem |
| Message "CLIP STUDIO was not closed properly last time" | Consequence of a **non-gracefully terminated** Hub (e.g. `pkill`/crash). Just click "Open CLIP STUDIO" in the dialog; always close CSP via its window. A common cause during testing: `./run-csp.sh --kill` or `wineserver -k` |
| **Empty/white window over the application** (has to be clicked away) | Missing **Wine addon**: click **"Install"** in the dialog (Wine Gecko/Mono). Without Gecko IE/MSHTML interfaces stay empty. Catch up automatically: `./install.sh --no-csp` (downloads and installs the addons). Check: `./verify.sh` → lines "Wine Gecko/Mono". Then restart the application |
| Device name in CSP is `XWayland Tablet (XWinTab/XI2)` | That is the placeholder: no tablet was connected during installation (or gcc/libX11 were missing for the detection). Catch up: connect the tablet, then `./install.sh --no-csp` — or set `XWINTAB_DEVICE_NAME="<name>"` at start. `./verify.sh` shows the current source |
| Hub/login shows an empty page | Check WebView2 (`./verify.sh`); run the CSP installer again (it installs WebView2 as well) |
| Pen pressure broken after a Wine update | Reinstall the fix: `./install.sh --no-csp` (DLL + override) |
| "Installation of Gecko/Mono failed" | See section 2 → put the MSIs next to `install.sh` (offline) or click "Install" in the Wine dialog. Details are in `<prefix>/addon-install.log`. Check with `./verify.sh` |
| **`wine client error: version mismatch 931/962`** | A **Wine server of another Wine version** is still running (e.g. from system Wine). Wine does not always terminate it itself. Solution: `./run-csp.sh --kill` (terminates old Wine servers and starts again). By hand: `pkill -f wineserver` and then start with `./run-csp.sh` (sets PATH/WINELOADER/WINESERVER correctly) |
| **CSP crashes right after opening the editor** (backtrace mentions `triglavwinrt`) | The Wine installation does not provide the WinRT class `Windows.UI.Input.RadialController` (CSP 5 uses it for Surface Dial support; Wine 11.0 lacks it, 11.19 has it). **Update Wine.** Check: `./verify.sh` (line "Wine provides the WinRT classes") or `wine files/winrt-probe.exe` — all classes must show `OK` |
| "Mono: installed is X, Wine expects Y" | Wine version and addon version do not match (e.g. Wine 11.0 wants Mono **10.4.1**, Wine 11.19 wants **11.3.0**). The installer detects that and installs the matching version — for offline use **both** MSI versions must be available. Alternatively install the matching **distro package** (Arch: `sudo pacman -S wine-gecko wine-mono`, Fedora: `sudo dnf install …`) — Wine loads these system trees directly |

## 7. Uninstallation

```bash
./uninstall.sh                 # only remove the pen pressure fix (CSP stays)
./uninstall.sh --gpu           # additionally take back the GPU path (DXVK/VKD3D overrides + dxvk.conf)
./uninstall.sh --purge-prefix  # delete the complete Wine prefix
```

## 8. What is in the package

| File | Purpose |
|---|---|
| `install.sh` | Installer (idempotent) |
| `run-csp.sh` | **Launcher**: automatically uses the right (possibly portable) Wine; `--kill` clears old Wine servers |
| `uninstall.sh` | Rollback (`--gpu` also removes the GPU path, `--purge-prefix` deletes the prefix) |
| `verify.sh` | Check script (`--tablet` for the X level) |
| `files/wintab32.dll` | **patched** Wintab DLL (WineTab, XI2-based + adaptations for CSP; v0.6: real device name for `DVC_NAME`, complete `WTInfo` categories) |
| `files/XWinTabHelper.dll.so` | native XInput2 helper (loads the DLL) |
| `files/t5w.exe` | pen diagnostics window (shows packets/pressure live) |
| `files/xi2-probe.c` | small program that checks what X reports about the tablet (builds itself, uses `$DISPLAY`) |
| `files/xi2-devname.c` | determines the name of the stylus in use — the installer writes it as `XWinTabDeviceName.txt` next to the DLL |
| `files/extract-icon.py` | extracts the program icon from the EXE (Python standard library only) — for the menu entries |
| `files/winrt-probe.exe` | checks whether Wine provides the WinRT classes CSP 5 needs (RadialController/Storage) |
| `files/xdlg.c` | X helper: clicks away the "not closed properly" dialog and opens the Hub menu (built with `gcc`) |
| `files/panelprobe.py` | panel diagnostics via the DevTools protocol (used by `verify.sh --panels`) |
| `files/src/` | sources of the Wintab DLL (MIT license) |
| `files/src/dcomp-csp-linux.patch` | our patch for the CSPenguin `dcomp` shim (Hub display + clicks, section 3b); applied and built during installation |
| `<prefix>/addon-install.log` | log of the Gecko/Mono/DXVK installation (include it when reporting problems) |
| `<prefix>/dxvk.conf` | DXVK configuration (GPU path; loaded by `run-csp.sh`) |
| `<prefix>/csp-launcher/` | copy of `run-csp.sh` (+ `xdlg.c`) used by the menu entries |
| `files/LICENSE-WineTab.txt`, `NOTICE-WineTab.txt` | license notices (MIT) |

## 9. Addon versions (Wine ↔ MSI)

Wine requires **exactly matching** addon versions (otherwise it keeps asking):

| Wine | Wine Gecko | Wine Mono |
|---|---|---|
| 11.0 (`wine-staging 11.0`) | 2.47.4 | **10.4.1** |
| 11.19 (our reference system) | 2.47.4 | **11.3.0** |

The installer reads the expected versions from the respective `appwiz.cpl` — so please watch
the line "Wine … expects Gecko … / Mono …" in the output.

## 10. License / provenance notice

CSP itself is commercial software by CELSYS and **not** part of this package.
The pen pressure fix is based on **WineTab** (MIT) by Sylixa, which in turn builds on
**XWinTab** (MIT) by Graham--M; both licenses are included. Changes in
this package: additional Wintab exports (`WTPacket`, `WTDataGet/Peek`, `WTMgr*`,
`WTQueuePacketsEx`), `DVC_NAME`, and an adjustable tilt curve.

The `dcomp.dll` shim comes from the **CSPenguin installer** (parka6060) — published there without
a license file. Therefore neither its source nor a built DLL is included here: the
installer downloads the upstream source (pinned commit) and applies only **our patch**
(`files/src/dcomp-csp-linux.patch`).

**If something does not work: please do not tinker for hours — open an issue and attach
the output of `./verify.sh` and what you were doing.** The more precise, the better.

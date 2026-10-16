# CLIP STUDIO PAINT 5 on Linux (Wine)

Run **CLIP STUDIO PAINT 5** on Linux with Wine, including the parts that usually break:

| | Status |
|---|---|
| Editor: drawing, painting, saving/loading | ✅ works |
| **Pen pressure** (Wacom and other XInput2 tablets), no ghost strokes, adjustable tilt | ✅ works — patched Wintab |
| **CLIP STUDIO Hub** (the WebView2 start page): menu, ASSETS, Cloud, clickable links | ✅ works — patched DirectComposition shim |
| Cloud: download your files and open them in the editor | ✅ works, like on Windows |
| Login, settings window | ✅ works |

Tested on Arch Linux (KDE/Wayland, Wine 11.19-staging) and Fedora (portable Wine 11.19).

Detailed documentation (troubleshooting, test checklist, background):
[`bundle/README.md`](bundle/README.md) · [`CSP-TABLET-FIX.md`](CSP-TABLET-FIX.md) ·
[`RELEASE-NOTES.md`](RELEASE-NOTES.md) · [`STATUS.md`](STATUS.md) · [`TODO.md`](TODO.md).

## Requirements

- **Wine ≥ 11.19.** Wine 11.0 lacks WinRT classes CSP 5 needs and the editor crashes on start.
  No recent Wine on your distro? The installer downloads a portable one automatically (no root).
- **mingw-w64**, so the installer can build the Hub fix:
  `sudo pacman -S mingw-w64-gcc` · `sudo apt install g++-mingw-w64-x86-64` · `sudo dnf install mingw64-gcc-c++`
- `winetricks` (installs DXVK/VKD3D for the WebView2 panels)
- Your own CELSYS license. The installer downloads the official CSP 5.0.4 installer
  (`CSP_504w_setup.exe`, SHA256-checked) from CELSYS if you do not provide one.
- A graphical session (X11 or Wayland/XWayland)

## Install

Download `csp-linux-bundle-<version>.tar.gz` from the releases page, then:

```bash
tar xzf csp-linux-bundle-<version>.tar.gz
cd csp-linux-bundle-<version>
./install.sh          # idempotent, safe to run again
./verify.sh           # checks everything, changes nothing
./run-csp.sh          # start the editor   (./run-csp.sh hub  for the CLIP STUDIO Hub)
```

The installer creates a separate Wine prefix (`~/.wine-csp`, change with `--prefix`), downloads the
CSP installer and — if your system Wine is missing or older than 11.19 — a portable Wine, installs
CSP silently, the pen-pressure fix, the DirectComposition shim, DXVK/VKD3D and **menu entries with
icons**. Your own installer is used if `CSP_504w_setup.exe` lies next to `install.sh`
(or pass `--installer`). Already have CSP in a prefix? `./install.sh --no-csp --prefix /path/to/prefix`.

**Always start through `run-csp.sh`** — or the menu entries, which call it. It picks the right Wine
and sets the WebView2 arguments the Hub needs: `--in-process-gpu`, a User-Agent that avoids a 403
from one CELSYS server, and a **one-renderer mode that cuts the Hub's RAM from ~5 GB to ~1.5 GB**
(`--multi-process` restores the default).

## What was broken, and why

### Pen pressure
Wine's built-in `wintab32` reads tablets through the old XInput1 API, which under XWayland
delivers only sporadic events: no pressure, jittery lines, ghost strokes (WineHQ bug 53052).
[WineTab](https://github.com/Sylixa/WineTab) reimplements Wintab on XInput2, but CSP resolves
16 Wintab functions and silently falls back to mouse input if *any* is missing. We added the
missing exports (`WTPacket`, `WTDataGet/Peek`, `WTMgr*`, `WTQueuePacketsEx`), a real device name
and an adjustable tilt curve. Full story: [`CSP-TABLET-FIX.md`](CSP-TABLET-FIX.md).

### The Hub (WebView2)
The Hub is a WebView2 (Chromium) window that presents through DirectComposition, which Wine
only stubs. The [CSPenguin-Installer](https://github.com/parka6060/CSPenguin-Installer) ships
a `dcomp.dll` shim that copies Chromium's frames into the window — on Wine 11.x it still left
the Hub blank, flickering, or apparently ignoring clicks. Two independent bugs:

1. **Child windows have no drawing surface in Wine 11.x** (`win32u`, `get_window_surface`:
   child → `needs_surface = FALSE`). WebView2 renders into child windows, so whatever the shim
   drew there was erased by the next repaint of the parent. Fix: draw into the **parent's** DC
   at the child's offset, which lands in the surface Wine actually displays.
2. **New frames never reached the screen.** The shim copied a frame only on
   `IDCompositionDevice::Commit()`, which Chromium calls only when its *layer tree* changes
   (25 times in a whole session). New frames arrive via `IDXGISwapChain::Present()`, which was a
   no-op. So after a click the page loaded fine, but the screen kept the last committed frame —
   often a black one. Fix: forward every `Present()` to its window.

The two bugs masked each other, and an unrelated server-side 403 (CELSYS blocks User-Agents
containing `Chrome/` on one host) made it look like a network problem for a while.

Because upstream has no license, this project ships **only a patch**
([`bundle/files/src/dcomp-csp-linux.patch`](bundle/files/src/dcomp-csp-linux.patch)); the
installer downloads the pinned upstream source, verifies its hash, patches and builds it.
Build it by hand with [`diag/dcomp-shim/build.sh`](diag/dcomp-shim/build.sh).

## Repository layout

| Path | Contents |
|---|---|
| `bundle/` | The distributable package: `install.sh`, `run-csp.sh`, `verify.sh`, `uninstall.sh`, fix DLLs, sources, patch |
| `diag/` | Diagnostic tools (XInput probes, Wintab test programs, WinRT probe), the dcomp build script and the Wine child-window experiment (`diag/dcomp-shim/disp-test.c`) |
| `CSP-TABLET-FIX.md` | The pen-pressure fix in depth |
| `STATUS.md`, `TODO.md`, `RELEASE-NOTES.md` | Project status, open points, changelog |
| `CONTRIBUTING.md` | Repository conventions, release process |

## License

MIT for the code in this repository — see [`LICENSE`](LICENSE). Third-party components and
their terms: [`THIRD-PARTY.md`](THIRD-PARTY.md). CLIP STUDIO PAINT is a product of CELSYS, Inc.;
this project is not affiliated with CELSYS and includes no CELSYS software.

## Credits

- [WineTab](https://github.com/Sylixa/WineTab) by Sylixa and XWinTab by Graham--M (MIT) — the basis of the pen-pressure fix
- [CSPenguin-Installer](https://github.com/parka6060/CSPenguin-Installer) by parka6060 — the original `dcomp` shim this project patches

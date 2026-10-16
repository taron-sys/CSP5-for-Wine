# `diag/` — diagnostic and measurement tools (CSP under Wine / tablet)

All tools are self-contained and document themselves in their source. The order follows the
diagnostic chain from the top (X level) down to the bottom (CSP level).

> **Paths in this document:** relative to the **repo root** (the directory containing `diag/`)
> — so change once to `cd /path/to/CSP5-for-Wine`. Exceptions are marked as such.

## X level (runs natively on the host, not under Wine)

| Tool | Build | Purpose |
|---|---|---|
| `xi2-probe.c` | `gcc -O2 xi2-probe.c -o xi2-probe -lX11 -lXi` | Shows all XI2 devices with **valuator labels** (Abs X/Y/Pressure/Tilt/Wheel) — checks whether XWayland offers the stylus correctly. Without an argument `$DISPLAY` is used, with an argument a specific one (`./xi2-probe :0`). |
| `xi2-devname.c` | `gcc -O2 xi2-devname.c -o xi2-devname -lX11 -lXi` | Prints **the name of the device** the helper attaches to (rule: name contains `stylus`, or `$XWINTAB_DEVICE`) — the basis for `WTInfo(DVC_NAME)`. `--list` shows all devices, `"*"` marks the choice. Exit 1 = no tablet found. |
| `xi1-probe.c` | `gcc -O2 xi1-probe.c -o xi1-probe -lX11 -lXi` | Shows the **XI1** device list (`XListInputDevices`) — exactly what Wine's built-in wintab sees (axis values, use types, type atoms) |

## Wine/WinTab level (Windows programs, run in the prefix)

| Tool | Build | Purpose |
|---|---|---|
| `wintab-test.c` | `x86_64-w64-mingw32-gcc -O2 wintab-test.c -o wintab-test.exe` | Queries `WTInfo` categories (DVC_X/Y/**NPRESSURE**/TPRESSURE, cursor names) — shows which axes Wine's wintab reports. **Note:** uses the A variants (`WTInfoA`) → only runnable against Wine's builtin. |
| `csp-wintab/t5w.c` | see below | **W**-variant test against the patched DLL (as CSP calls it): window + `WTOpenW` + packet printing on the console |
| `csp-wintab/t5w.exe` | prebuilt | the same as a ready-made EXE (also lives in the CSP app directory) |
| `wtinfo-probe.c` | `x86_64-w64-mingw32-gcc -O2 -Idiag/csp-wintab -o wtinfo-probe.exe wtinfo-probe.c -luser32` | Dumps `WTInfo` (category × index incl. 3/4/400, 100, 200, 300) with length and decoded value; additionally checks for **buffer overruns**. A counter-check against Wine's built-in `wintab32` in a fresh prefix (without DllOverride) shows the expected semantics. `-v` also shows empty categories. |
| `winrt-probe.c` | `x86_64-w64-mingw32-gcc -O2 winrt-probe.c -o winrt-probe.exe` | Checks whether Wine provides the WinRT classes CSP 5 needs (RadialController/Storage). Prints `Result: N classes checked, M missing`. |
| `t1.c` … `t5.c`, `wintab-live.c` | `x86_64-w64-mingw32-gcc -O2 tN.c -o tN.exe -luser32 -lgdi32` | early stepping-stone tests of the Wintab path (load, `WTInfo`, window, packets, live output) |

Build for `t5w.c` (from `diag/csp-wintab/`):
```bash
x86_64-w64-mingw32-gcc -O2 t5w.c -o t5w.exe -luser32 -lgdi32
```
Run (must lie in the CSP app directory so that it loads the patched DLL):
```bash
./start-csp.sh tabtestw      # red window, 120 s, then summary
```

## Patched DLL (the fix)

| File | Purpose |
|---|---|
| `csp-wintab/WinTab.c` | WineTab source (MIT) **+ CSP compat extension** at the end of the file (WTPacket, WTDataGet/Peek, WTMgr*, WTQueuePacketsEx) **+ tilt control + `WTInfo`/`DVC_NAME` (v0.6, see §7 of the fix document)** |
| `csp-wintab/wintab32.def` | export list (17 exports, ordinals like the Wintab spec) |
| `csp-wintab/wintab32.dll` | built DLL (install via `./install-xwintab.sh` from the repo root) |
| `csp-wintab/XWinTabHelper.dll.so` | native XI2 helper (unchanged from the WineTab release) |

Build:
```bash
cd diag/csp-wintab
x86_64-w64-mingw32-gcc -shared -O2 -o wintab32.dll WinTab.c wintab32.def -luser32 -lgdi32
```

**Device name (`DVC_NAME`)**: next to the DLL there is an optional `XWinTabDeviceName.txt`
(UTF-8, one line) — the DLL reads it on the first `DVC_NAME` call. Create it:
```bash
./xi2-devname > "/path/to/CLIP STUDIO PAINT/XWinTabDeviceName.txt"
```
`install-xwintab.sh` does this automatically after copying the DLL.

## Hub display (dcomp shim)

| File | Purpose |
|---|---|
| `dcomp-shim/build.sh` | builds the patched `dcomp.dll` exactly like `bundle/install.sh` (pinned upstream source + `bundle/files/src/dcomp-csp-linux.patch`); result in `dcomp-shim/build/` |
| `dcomp-shim/disp-test.c` | the Wine child-window experiment: shows that a blit into the **parent's** DC at the child offset survives repaints and `MoveWindow`, while drawing into the child's own DC does not |

## Evidence / logs

| File | Contents |
|---|---|
| `evidence-wintab-working.txt` | CSP's WinTab init sequence + pressure probe (ramp) + statistics |
| `user-session-XWinTabLog-16bytes.txt` | The 16-byte proof of the silent fallback (only `INIT_LOG_CALLED`) — before the `WTQueuePacketsEx` fix |

## Useful environment variables

| Variable | Effect |
|---|---|
| `XWINTAB_LOG=1` | the DLL writes a detailed log to `drive_c/users/<user>/XWinTabLog.txt` (every packet — for debugging only) |
| `XWINTAB_DEVICE_NAME=<name>` | device name `WTInfo(WTI_DEVICES, DVC_NAME)` should report (overrides the sidecar file) |
| `XWINTAB_DEVICE=<name>` | device selection of the helper (the name must contain this substring; default `stylus`) — also used as a last resort for `DVC_NAME` |
| `XWINTAB_ALT_SCALE=<n>` | steepness of tilt→altitude (**default 9** — tuned for CSP; smaller = the brush stays narrower) |
| `XWINTAB_ALT_BASE=<n>` | "perpendicular" value (default 900; Wine's builtin uses 1000) |
| `WINEDEBUG=+wintab32` | Wine traces of the **built-in** Wintab (only useful with the builtin) |

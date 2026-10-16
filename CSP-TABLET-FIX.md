# CSP 5 under Wine: pen pressure fix (WineTab + CSP compat)

**Status: ✅ confirmed by the user (2026-10-09)** — CSP 5.0.4 uses the WinTab backend through
our patched `wintab32.dll`: **pen pressure works**, **no more ghost strokes**.
Proven by measurement: 18,008 packets, pressure range 0–52,553 (mean 24,778).
Wine 11.19-staging (Arch) · KDE/Wayland (XWayland) · Wacom HID 48CE Pen

> **Paths in this document:** relative to the **repo root** = the directory this file lives in.
> So change there once (`cd /path/to/CSP5-for-Wine`); the scripts determine their own location and
> run independently of where the repo lives.

---

## 1. Symptom

- CSP 5 runs under Wine up to the editor, **no pen pressure** (strokes of constant width).
- Before: sporadic "ghost strokes", jittery strokes.
- Many error messages at start (Wine JIT debugger messages of the WebView2 Hub — a separate point, see below).

## 2. Diagnostic chain (everything empirically proven)

| Step | Tool | Finding |
|---|---|---|
| X level (XWayland) | `diag/xi2-probe`, `diag/xi1-probe` | XWayland delivers the stylus completely: `Abs X/Y 0..262143`, **`Abs Pressure 0..65535`**, tilt, wheel — labelled XI2 valuators |
| Wine's built-in `wintab32` | `diag/wintab-test.exe` (DVC_* queries) | detects the tablet via the old **XI1** API (`XListInputDevices`) and delivers packets only sporadically — WineHQ bug **53052** ("Tablet pressure does not work under Wayland", open since 2022) |
| Wine's Wintab internals | Wine source `dlls/winex11.drv/wintab.c` | "Did not find a valid stylus … Wintab is disabled" / fake-device path; event delivery via `XSelectExtensionEvent` (XI1) is unreliable under XWayland |
| Community solution | `github.com/Sylixa/WineTab` (MIT) | XI2/`libxcb-xinput` reimplementation of WinTab: continuous motion + **real pressure** + tilt |
| **CSP call analysis** | `/proc/<pid>/maps`, DLL logging (`XWINTAB_LOG=1`) | CSP loaded our DLL but **never called** it → CSP silently fell back to mouse/WM_POINTER |
| Cause | string analysis: CSP's Wintab function table | CSP resolves **16** exports; WineTab only exports 10 → after adding `WTPacket`, `WTDataGet`, `WTDataPeek`, `WTMgrOpen/Close/Ext`, **`WTQueuePacketsEx`** was still missing → a NULL pointer made CSP's WinTab backend init fail |

## 3. The fix

Patched `wintab32.dll` = **WineTab** (XI2 WinTab, MIT) **+ CSP compat extension**:

| Addition | Semantics |
|---|---|
| `WTPacket` (@24) | copy a packet by serial from the queue (mask-controlled), drain the queue up to there — Wine semantics |
| `WTDataGet` (@81) | remove packets with serial `wBegin..wEnd` inclusive, limited to `cMaxPkts`, + `*lpNPkts` |
| `WTDataPeek` (@82) | like `WTDataGet`, without removing |
| `WTMgrOpen/Close/Ext` (@100/101/180) | stubs with Wine-identical behaviour (`ERROR_CALL_NOT_IMPLEMENTED`) |
| **`WTQueuePacketsEx` (@200)** | oldest/newest serial in the queue (FALSE if empty) — **the actual blocker** |

Sources & build: `diag/csp-wintab/` (WinTab.c extension at the end of the file, `wintab32.def`).
Build: `x86_64-w64-mingw32-gcc -shared -O2 -o wintab32.dll WinTab.c wintab32.def -luser32 -lgdi32`
The native helper `XWinTabHelper.dll.so` stays unchanged (from the WineTab release).

## 4. Installation

Preferably by script (checks whether CSP is still running, copies DLL + helper + licenses,
sets the override):

```bash
./install-xwintab.sh
```

Manually (equivalent):
```bash
PREFIX="${WINEPREFIX:-$PWD/wineprefix-csp}"   # $PWD = repo root
PAINTDIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT"

# 1) both files into the app directory (DLL search order: app dir before system32)
cp diag/csp-wintab/wintab32.dll          "$PAINTDIR/"     # patched DLL
cp diag/csp-wintab/XWinTabHelper.dll.so  "$PAINTDIR/"     # native XI2 helper

# 2) make Wine load the file instead of the builtin (once, persistent)
env WINEPREFIX="$PREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" \
    /v wintab32 /t REG_SZ /d native /f
```

**Important:** the DLL must be **in the app directory** (not system32) — it is loaded
per application; that way other apps in the prefix are left untouched.

## 5. Verification

```bash
# Live test against the patched DLL (draw!):  start window, console output shows packets+pressure
./start-csp.sh tabtestw

# CSP with Wintab logging:  log -> drive_c/users/<user>/XWinTabLog.txt
./start-csp.sh paintlog
```

Expected log sequence (CSP start with a document):
```
Loaded XWinTabHelper.dll.so · Using device: 11
WTInfoW: probe (0,0) -> tablet present
WTInfoW: cat 400 (default context) idx 0 -> 212 bytes
WTQueueSizeSet: 1024
device name: from XWinTabDeviceName.txt      ← or "from XWINTAB_DEVICE_NAME" / "placeholder"
device name value: "xwayland-tablet stylus:11"
WTInfoW: DVC_NAME -> 52 bytes ("xwayland-tablet stylus:11")
WTInfoW: WTI_DEVICES idx 15 -> AXIS [0..65535]   ← pressure axis
event: x … y … p 16556 …  on_event: Send WT_PACKET   ← pressure flows
packet: x … y … p … serial …                ← CSP consumes (WTPacket)
```

`WTInfow: unhandled cat …` should **not occur at all** any more since v0.6 — the DLL
answers all categories CSP asks for (details: §7).

## 6. Fine-tuning tilt

**Observation:** with the default setting the brush reacts very early/strongly to tilt
(the brush gets wide quickly).

**How the value is produced** (in `diag/csp-wintab/WinTab.c`, `on_event`):

```c
altitude = base - scale * max(|xTilt|, |yTilt|)      // clamped to [0, base]
orAzimuth = azimuth(xTilt, yTilt)                    // atan2 rule (like Wine)
```

* `altitude` is the Wintab value from which CSP derives the "tilt":
  **base = pen perpendicular**, **0 = lying flat**.
* Wine's own `wintab32` computes `1000 - 15 × tilt` (axes declared as −1000…1000),
  WineTab took that over as `900 - 15 × tilt` (axes −900…900).
* **Our DLL default: base 900, scale 9** — chosen in practical testing as comfortable for CSP
  (the Wine/WineTab default 15 felt too aggressive: the brush got wide too early).

**Controls (environment variables, no rebuild needed):**

| Variable | Default | Effect |
|---|---:|---|
| `XWINTAB_ALT_SCALE` | **9** (Wine/WineTab: 15) | steepness: **smaller = the brush stays narrow for longer** (less aggressive) |
| `XWINTAB_ALT_BASE` | 900 | "perpendicular" value; `1000` corresponds exactly to Wine's builtin behaviour |

**Apply & compare:**
```bash
./start-csp.sh tilt 8      # factor 8 instead of 15
# or specifically:  XWINTAB_ALT_SCALE=6 ./start-csp.sh
```
To check what the DLL is doing right now:
```bash
start ~/.local/share/.../CLIPStudioPaint.exe  with  XWINTAB_LOG=1
# log: drive_c/users/<user>/XWinTabLog.txt  →  "tilt config: base=900 scale=8"
#                                              "event: … tltx 54 tlty -10 …"
```
If the factor does not achieve the desired effect, the **azimuth** (direction) or a non-linear
curve can be adjusted additionally — the formula sits in one place (`on_event`) and is
therefore easy to change.

**Result (tested by the user, 2026-10-09): `XWINTAB_ALT_SCALE = 9`.**
This value is built in as the **DLL default** — the environment variable is thus only needed
for special cases (e.g. `1000`+`15` for exact Wine builtin behaviour).

**Recommendation for other setups:** start at 15 and lower in steps of 1 (12 → 10 → 9 → 8)
until tilting feels natural.

## 7. WTInfo: device name (`DVC_NAME`) and info categories

CSP asks for a handful of `WTInfo` categories at start. The patched DLL answers them
completely since **v0.6** — before, some ran into the branch
`WTInfow: unhandled cat …`. These are pure info queries: nothing was changed on the event and
pressure path (`on_event` → queue → `WTPacket`).

### 7.1 What CSP actually asks for (from `XWinTabLog.txt`)

| Query | up to 0.5 | since 0.6 |
|---|---|---|
| `WTInfo(0,0)` (probe) | 212 if tablet present, otherwise 0 | unchanged |
| `WTInfo(WTI_DDCTXS=400, 0)` | **unhandled → 0** | default context (212 bytes), like Wine |
| `WTInfo(WTI_DEFCONTEXT=3, 0)` | default context (212 bytes) | unchanged |
| `WTInfo(401, 0)` (device 1) | **unhandled → 0** | explicitly 0 ("only one device"), like Wine |
| `WTInfo(WTI_DEVICES=100, DVC_NAME=1)` | placeholder | **real device name** (§7.2) |

> The TODO entry was called "`WTI_EXTENSIONS (400)`" — the **400** comes from the log line
> `unhandled cat 400 idx 0` and is `WTI_DDCTXS` (default context = *device default
> context*), not `WTI_EXTENSIONS` (= 300). Both are answered now.

### 7.2 Device name for `DVC_NAME`

The helper only exports `DeviceInfo` (id, axes, buttons) — **without** a name, and its source
is not in this repo (only the prebuilt `XWinTabHelper.dll.so`; a rebuild would have required
re-verifying the proven pressure path). The name therefore comes from the first applicable
source:

1. `XWINTAB_DEVICE_NAME` — environment variable (explicit override)
2. `XWinTabDeviceName.txt` — UTF-8 file **next to the DLL** in the CSP app directory,
   written by `install-xwintab.sh` / `bundle/install.sh` (determined via `diag/xi2-devname`)
3. `XWINTAB_DEVICE` — the same variable the helper uses to select its device
4. Placeholder "XWayland Tablet (XWinTab/XI2)" — unchanged legacy behaviour

```bash
./diag/xi2-devname          # -> xwayland-tablet stylus:11   (name of the stylus in use)
./diag/xi2-devname --list   # all X input devices, "*" = selected
```

**Setting the right expectation:** under **XWayland**, X11 clients — and therefore the helper
too — only see `xwayland-tablet stylus:<id>`; the hardware name ("Wacom HID 48CE Pen")
is only handed out by Wayland via `zwp_tablet_manager_v2`, which does not reach X11. On a
**native X session** (Xorg) the real device name is there, e.g.
`Wacom Intuos Pro M Pen stylus`. Wine's built-in `wintab32` reports the static string
`Wine Tablet Device` at this point, by the way. If you want something more readable:

```bash
XWINTAB_DEVICE_NAME="Wacom Intuos Pro M (XWinTab)" ./start-csp.sh
```

### 7.3 `WTI_INTERFACE`, extensions, cursor table

Values checked against Wine's builtin (`dlls/winex11.drv/wintab.c`, `get_tablet_info`) —
Wine indices that are not implemented return 0 there; here they are filled sensibly:

| Index | Value | Wine |
|---|---|---|
| `IFC_WINTABID` | `"XWinTab 0.6"` | `"Wine Wintab 1.1"` |
| `IFC_SPECVERSION` | `0x0101` (Wintab 1.1) | same |
| `IFC_IMPLVERSION` | `0x0006` (version of this DLL) | `0x0100` |
| `IFC_NDEVICES` | 1 | same |
| `IFC_NCURSORS` | 1 | 3 |
| `IFC_NCONTEXTS` | 1 | *0 (not implemented)* |
| `IFC_CTXOPTIONS` | `CXO_SYSTEM \| CXO_MESSAGES` | *0* |
| `IFC_CTXSAVESIZE` | `sizeof(LOGCONTEXTW)` = 212 | *0* |
| `IFC_NEXTENSIONS` | 0 | *0* |
| `IFC_NMANAGERS` | 0 | *0* |

* **`WTI_EXTENSIONS` (300)** is explicitly answered with 0 ("no extensions") so that the scan
  loop `for (i = 0; WTInfo(WTI_EXTENSIONS + i, EXT_TAG, …); i++)` terminates cleanly. Wine does
  not handle the category at all — implicitly 0 as well.
* **`WTI_DEFCONTEXT` (3), `WTI_DEFSYSCTX` (4), `WTI_DDCTXS` (400)** share one handler
  (as in Wine): index 0 → whole `LOGCONTEXTW`, `CTX_NAME` (1) → only the name,
  `CTX_OPTIONS`…`CTX_SYSSENSY` (2–34) → single field.
* **`WTI_DDCTXS + n` (n ≥ 1)** → 0, because exactly one device is reported (`IFC_NDEVICES` = 1).
* **`DVC_HARDWARE`** = `HWC_HARDPROX` (the helper delivers proximity in/out),
  **`DVC_NCSRTYPES`** = 1, **`DVC_FIRSTCSR`** = 1 — consistent with `packet_copy` setting
  `pkCursor` to 1 and the cursor being answered under `WTI_CURSORS + 1`
  (Wine: 3 cursors from 0 = puck/stylus/eraser).

Deliberately *not* adopted: Wine returns `WTInfo(0,0)` = 200 (with `FIXME("Return proper
size")`) and `WTI_DEFCONTEXT` without a device = 0. This DLL reports the real structure size (212)
and offers a context even without a tablet (that is what XWinTab wants: otherwise e.g.
Rebelle "forgets" the WinTab setting).

### 7.4 Re-checking

```bash
# dump all categories/indices (loads the DLL from its own directory)
cp diag/wtinfo-probe.exe "$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/"
WINEPREFIX=~/.wine-csp wine "…\\CLIP STUDIO PAINT\\wtinfo-probe.exe"

# counter-check: Wine's builtin in a fresh prefix (without DllOverride)
WINEPREFIX=/tmp/wt-builtin wine ./wtinfo-probe.exe
```

Build: `x86_64-w64-mingw32-gcc -O2 -Idiag/csp-wintab -o diag/wtinfo-probe.exe diag/wtinfo-probe.c -luser32`

## 8. Operating notes

- **`XWINTAB_LOG=1` only for debugging** — logs every packet (≈18 k lines/minute)
  and slows things down. Normal operation: without the variable (no log, no overhead).
- Ghost strokes should disappear with the XI2 path (WineTab fixes, among others,
  the "stroke from the canvas corner" at stroke start). Keep observing.
- The remaining CSP start messages ("JIT"/debugger) come from the **Hub/WebView2**
  (`msedgewebview2`, Crashpad) — not from the editor. Remedy: `start-csp.sh nojitter`
  (clear the AeDebug debugger) or start the editor directly (`start-csp.sh paint`).
- Open points: `WTI_STATUS` (2) and the spec fields `DVC_*`/`CSR_*` that CSP does not
  query remain unanswered. The earlier gaps (`WTI_DDCTXS` (400) and `DVC_NAME` (100/1))
  were closed in v0.6, see §7.

## 9. Artifacts

| Path | Contents |
|---|---|
| `diag/csp-wintab/wintab32.dll` | patched DLL (17 exports, MIT) — **+ tilt control + `DVC_NAME`/`WTInfo` categories (v0.6)** |
| `install-xwintab.sh` | installation script (DLL + helper + override) |
| `diag/README.md` | tool index, build commands, environment variables |
| `diag/csp-wintab/WinTab.c` / `wintab32.def` | sources + export definition |
| `diag/csp-wintab/LICENSE`, `NOTICE` | license chain (WineTab/XWinTab, MIT) |
| `diag/csp-wintab/t5w.c` / `t5w.exe` | W live test against the DLL |
| `diag/wintab-test.c`, `diag/xi1-probe.c`, `diag/xi2-probe.c` | diagnostic tools (X level, Wintab level) |
| `diag/xi2-devname.c` | determines the device name of the stylus in use (basis for `DVC_NAME`) |
| `diag/wtinfo-probe.c` | dumps `WTInfo` over all categories/indices — for comparison with Wine's builtin (§7.4) |
| `diag/user-session-XWinTabLog-16bytes.txt` | proof of the silent fallback (only `INIT_LOG_CALLED`) |

**Upstream option:** the CSP compat extension (6 additional exports) is a sensible
pull request to `Sylixa/WineTab` — it makes the DLL usable for CSP (and other Wintab apps with
full API needs).

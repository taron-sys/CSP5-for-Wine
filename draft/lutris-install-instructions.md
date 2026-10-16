# Installing CLIP STUDIO PAINT 5 in Lutris (csp-linux-bundle 0.1.22)

Status: draft, for testers. System Lutris (not Flatpak). The Lutris script itself has not been
run through Lutris's installer UI yet; report anything that behaves differently.

## 1. Requirements

| What | Why |
|---|---|
| Lutris (system package) | runs the install script |
| Vulkan-capable GPU + current Mesa or NVIDIA driver | DXVK/VKD3D, the Hub's WebView2 panels |
| `curl`, `tar`, `patch` | downloads and the shim patch |
| `mingw-w64` g++ (`x86_64-w64-mingw32-g++`) | builds the display shim for the Hub (no prebuilt DLL is shipped) |
| ~12 GB free disk space | portable Wine (~1 GB), CSP, prefix, caches |
| Internet | Wine (~100 MB) and the CSP installer (~470 MB) are downloaded during install |

Install the build tools:

```bash
# Arch / Manjaro
sudo pacman -S mingw-w64-gcc patch
# Debian / Ubuntu
sudo apt install g++-mingw-w64-x86-64 patch
# Fedora
sudo dnf install mingw64-gcc-c++ patch
```

You do **not** need to install Wine, winetricks, Mono or Gecko. The installer fetches its own
Wine 11.19 and keeps it inside the game folder.

## 2. Get the files

You need two files from the release:

* `csp-linux-bundle-0.1.22.tar.gz`
* `lutris-csp5-wine.yml` (the Lutris install script)

Check the download (optional):

```bash
sha256sum csp-linux-bundle-0.1.22.tar.gz
# 72e42cfba7d6b856f432c527473ead5882903311979bcc31f38331a71cdd9eee
```

## 3. Tarball location

Nothing to edit: the script uses `url: N/A:Select csp-linux-bundle-0.1.22.tar.gz`, so Lutris
opens a file picker during the install and asks for the tarball you downloaded. (For a hosted
release, replace that line with the https URL of the tarball.)

## 4. Install

```bash
lutris -i /path/to/lutris-csp5-wine.yml
```

Or in the Lutris window: **+ (Add game) → Install from a local install script**, then choose the file.

0. When Lutris asks for **the language of CLIP STUDIO PAINT**, pick it from the dropdown (default
   English; 11 languages). CLIP STUDIO fixes its language at install time; you can change it later
   without reinstalling, see section 6.
1. Choose an install folder (default `~/Games/clip-studio-paint-5-wine`). The Wine prefix, the
   portable Wine and the bundle all live inside it.
2. Pick `csp-linux-bundle-0.1.22.tar.gz` in the file picker when asked.
3. Wait. The first run takes several minutes: Wine download, prefix, Gecko/Mono, DXVK/VKD3D, the
   silent CSP setup. A CSP setup window may flash briefly; that is normal.
4. If `mingw-w64`/`patch` are missing, Lutris stops at the start and names the missing program.

## 5. Start

The game entry **CLIP STUDIO PAINT 5** starts the editor. The launch options menu (right-click →
*Launch…* or the arrow next to *Play*) also has **CLIP STUDIO (Hub)** for login and the asset store.

Notes:

* The Hub needs ~30–40 s until its panels appear; click the grid icon at the top right for the menu.
* If CSP was killed uncleanly, the launcher resets CSP's "still running" marker before the next start,
  so the "not closed properly" dialog does not appear.
* Pen tablets: nothing to configure. Check pressure with the diagnostic in the bundle `README.md`.

## 6. Update / remove

### Update an existing installation (keeps prefix, settings and your files)

Works from any earlier version (tested 0.1.18 → 0.1.22). Replace `GAME` with your game folder
(default `~/Games/clip-studio-paint-5-wine`) and `VER` with the new version.

1. **Quit CLIP STUDIO PAINT and the Hub** (close the windows normally).
2. **Download and check** the new `csp-linux-bundle-VER.tar.gz` (+ `.sha256`) from the release page:
   ```bash
   sha256sum -c csp-linux-bundle-VER.tar.gz.sha256        # must print "OK"
   ```
3. **Unpack it over the old bundle folder:**
   ```bash
   tar -xzf csp-linux-bundle-VER.tar.gz -C GAME/bundle --strip-components=1
   cat GAME/bundle/VERSION                                  # shows the new version
   ```
4. **Run the installer again** with the same options the Lutris script uses:
   ```bash
   bash GAME/bundle/install.sh --prefix GAME/prefix --wine-portable --wine-portable-dir GAME/wine --no-shortcuts
   ```
   It is idempotent: CSP is not reinstalled, your prefix, settings and artwork stay. It brings the
   prefix up to date (portable Wine, maximized-window fix, display shim, tablet fix). First time
   from an older version this downloads the portable Wine 11.19 (~100 MB) into `GAME/wine`.
5. **Check:**
   ```bash
   bash GAME/bundle/verify.sh --prefix GAME/prefix          # "Ergebnis: … 0 Fehler"
   ```
6. Start the game in Lutris as usual. The Lutris entry itself needs no change.

Alternatively install the new Lutris script as a **new** game (fresh folder, fresh prefix).

### Change the program language later

No reinstall needed (the official way, reinstalling, also works). Close CLIP STUDIO PAINT and the Hub, then:

```bash
bash GAME/bundle/install.sh --prefix GAME/prefix --wine-portable --wine-portable-dir GAME/wine --no-shortcuts --language en
```

`en de fr es pt ja ko zh-cn zh-tw th id`. The new language applies at the next start. Names of tools
and brushes that already exist keep their old language (this is the same when reinstalling).

### Remove

*Remove* in Lutris and tick *Remove game files* – this deletes the whole folder (prefix, Wine,
bundle). Your own artwork files outside the prefix are not touched.

## 7. If something goes wrong

| Symptom | Check |
|---|---|
| Hub shows gaps / settings dialogs don't react to clicks | the shim was not built: see `<game folder>/prefix/addon-install.log`; install mingw-w64 and `patch`, then re-run the install |
| Install log | `<game folder>/prefix/addon-install.log` and `<game folder>/prefix/install-csp.log` |
| "version mismatch …" at start | an old wineserver is running: `<game folder>/bundle/run-csp.sh --kill --prefix <game folder>/prefix` |
| Maximized window shifted by a few pixels (background visible on the left/top, right edge cut off) | `verify.sh` should say "Maximier-Fix aktiv". If not, re-run the install step above; the fix only works with the portable Wine 11.19 Staging the script installs |
| Anything else | `<game folder>/bundle/verify.sh --prefix <game folder>/prefix` prints a checklist |

Flatpak Lutris is not covered by this script (no mingw inside the sandbox → unpatched shim).

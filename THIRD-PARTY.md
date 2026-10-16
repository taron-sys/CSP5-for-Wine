# Third-party components

The MIT license in `LICENSE` covers the code written for this project. These parts
come from elsewhere and keep their own terms:

| Component | Where | License |
|---|---|---|
| **WineTab** (Sylixa) and **XWinTab** (Graham--M) — the XInput2 Wintab implementation our pen-pressure fix is built on | `bundle/files/wintab32.dll`, `bundle/files/XWinTabHelper.dll.so`, `bundle/files/src/`, `diag/csp-wintab/`, `diag/xwintab/`, `diag/xwintab.zip` | MIT — see `bundle/files/LICENSE-WineTab.txt`, `diag/csp-wintab/LICENSE`, `diag/xwintab/LICENSE` |
| Wine headers `wintab.h`, `pktdef.h` | `diag/wine_inc/` | LGPL-2.1-or-later (header in each file) |
| **CSPenguin-Installer** `dcomp` shim (parka6060) | **not included** | The upstream repository has no license. This project ships only `bundle/files/src/dcomp-csp-linux.patch`, a patch against upstream commit `868d022`. `bundle/install.sh` and `diag/dcomp-shim/build.sh` download the upstream source from GitHub, verify its SHA256 and apply the patch locally. |

**CLIP STUDIO PAINT** is commercial software by CELSYS, Inc. No part of it is included;
you need your own installer (`CSP_*_setup.exe`) and license. This project is not affiliated
with or endorsed by CELSYS.

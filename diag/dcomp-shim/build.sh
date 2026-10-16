#!/bin/bash
# Builds the patched dcomp shim exactly like bundle/install.sh:
#   upstream source (CSPenguin, pinned commit, SHA256 verified) + our patch
#   (bundle/files/src/dcomp-csp-linux.patch), upstream flags + dcomp.def (4 exports).
# The upstream files have no license and are therefore not in the repo.
# Result: diag/dcomp-shim/build/dcomp.dll (+ patched source to keep working on).
# Regenerate the patch after changes:
#   cd build && diff -u dcomp_csp.cpp.orig dcomp_csp.cpp | sed '1s|^--- .*|--- a/dcomp_csp.cpp|;2s|^+++ .*|+++ b/dcomp_csp.cpp|' \
#     > ../../../bundle/files/src/dcomp-csp-linux.patch
set -e
cd "$(dirname "$0")"
BASE="https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/868d022adfdc3740449241f4721debbf4b1b1426/patches/dcomp"
PATCH="$(cd ../.. && pwd)/bundle/files/src/dcomp-csp-linux.patch"
mkdir -p build && cd build
[ -f dcomp_csp.cpp.orig ] || curl -sfL -o dcomp_csp.cpp.orig "$BASE/dcomp_csp.cpp"
[ -f dcomp.def ]          || curl -sfL -o dcomp.def          "$BASE/dcomp.def"
echo "e516fd33b7da2452a90b96a9bbb42920564afd1a91d4ba629cad34acfb0cc83a  dcomp_csp.cpp.orig
319c1a01d6ca059c5127f62a4a6250ccead3af8ae1f4b335b7c2b1f7fe8b4e92  dcomp.def" | sha256sum -c --quiet
if [ ! -f dcomp_csp.cpp ]; then
    cp dcomp_csp.cpp.orig dcomp_csp.cpp
    patch -s -p1 dcomp_csp.cpp < "$PATCH"
fi
x86_64-w64-mingw32-g++ -shared -static -O2 -std=c++17 \
  -o dcomp.dll dcomp_csp.cpp dcomp.def \
  -lole32 -lgdi32 -luser32 -ldxgi -ld3d11 -luuid
echo "build/dcomp.dll built"

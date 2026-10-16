#!/usr/bin/env bash
# Build the release tarball from bundle/ (version from bundle/VERSION).
# Output (repo root, untracked): csp-linux-bundle-<V>.tar.gz + .sha256
# Packs the tracked files of bundle/ only, then verifies the unpacked result.
# Publish afterwards with ./publish-github.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

V=$(tr -d '[:space:]' < bundle/VERSION)
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: bad version '$V' in bundle/VERSION" >&2; exit 1; }
OUT="csp-linux-bundle-$V.tar.gz"

grep -q "^## v$V " RELEASE-NOTES.md || echo "warning: no '## v$V' section in RELEASE-NOTES.md (publish-github.sh will fail)" >&2
grep -q "$V" bundle/README.md || echo "warning: bundle/README.md does not mention $V (title not bumped?)" >&2

for s in install.sh run-csp.sh uninstall.sh verify.sh; do
    [[ -x bundle/$s ]] || { echo "error: bundle/$s is not executable (chmod +x)" >&2; exit 1; }
done

git ls-files -z bundle | tar --null -T - --owner=0 --group=0 --numeric-owner \
    --transform "s,^bundle,csp-linux-bundle-$V," -czf "$OUT"
sha256sum "$OUT" > "$OUT.sha256"

# verify: unpacked tarball must match the tracked files of bundle/
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tar xzf "$OUT" -C "$tmp"
while IFS= read -r -d '' f; do
    cmp -s "$f" "$tmp/csp-linux-bundle-$V/${f#bundle/}" || { echo "error: $f differs in tarball" >&2; exit 1; }
done < <(git ls-files -z bundle)
sha256sum -c "$OUT.sha256"

echo "built $OUT ($(stat -c %s "$OUT") B)"

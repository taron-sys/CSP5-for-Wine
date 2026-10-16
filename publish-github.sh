#!/usr/bin/env bash
# Publish the bundle tarballs as a GitHub release (needs the `gh` CLI, logged in).
# Version comes from bundle/VERSION; release text is that version's section of RELEASE-NOTES.md.
# Existing release for the tag: assets are re-uploaded (--clobber) and the notes updated.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v gh >/dev/null || { echo "error: gh CLI not found (https://cli.github.com/)" >&2; exit 1; }

V=$(tr -d '[:space:]' < bundle/VERSION)
TAG="v$V"

assets=()
for f in "csp-linux-bundle-$V.tar.gz"; do
    [[ -f $f ]] || { echo "note: $f not found, skipping"; continue; }
    [[ -f $f.sha256 ]] || { echo "error: $f.sha256 missing" >&2; exit 1; }
    assets+=("$f" "$f.sha256")
done
((${#assets[@]})) || { echo "error: no tarballs for $V in $PWD" >&2; exit 1; }

notes=$(mktemp); trap 'rm -f "$notes"' EXIT
# section "## v<V> — ..." up to the next "## " heading
awk -v tag="## $TAG " 'index($0, tag)==1 {p=1; next} /^## /{p=0} p' RELEASE-NOTES.md > "$notes"
[[ -s $notes ]] || { echo "error: no section '$TAG' in RELEASE-NOTES.md" >&2; exit 1; }
title=$(grep -m1 "^## $TAG " RELEASE-NOTES.md | sed 's/^## //')

if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit "$TAG" --title "$title" --notes-file "$notes"
    gh release upload "$TAG" --clobber "${assets[@]}"
else
    gh release create "$TAG" --target "$(git rev-parse HEAD)" --title "$title" --notes-file "$notes" "${assets[@]}"
fi

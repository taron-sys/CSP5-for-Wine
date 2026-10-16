# Working on `CSP5-for-Wine`

A short guide for development. Project overview: see `README.md`, state: `STATUS.md`,
open points: `TODO.md`.

## Repository layout (tracked)

```
CSP5-for-Wine/
├── README.md / STATUS.md / TODO.md     overview · state & handover · open points
├── CSP-TABLET-FIX.md                   pen pressure fix (diagnostic chain, patch, operation)
├── CONTRIBUTING.md / RELEASE-NOTES.md  guide · release text
├── start-csp.sh / install-*.sh         start & installation scripts (repo-relative)
├── publish-github.sh                   upload release assets to GitHub
├── bundle/                             distribution package (install/uninstall/verify + docs)
├── diag/                               diagnostic tools, patched DLL sources, evidence
```

**Not tracked** (see `.gitignore`): `installer/`, `wineprefix-csp/`, `example_files/`,
`testruns/` as well as logs, release tarballs and `*.err`. These stay local.

## Conventions

- **No large/generated files in the repo.** Wine prefix, CSP installer, portable
  Wine builds, logs and release tarballs are ignored. Release packages
  (`csp-linux-bundle-*.tar.gz` + `.sha256`) are published as **release assets**,
  not committed.
- **Scripts are repo-relative.** The repo root path is determined from `$BASH_SOURCE` so that
  the checkout can live anywhere. Overridable via `WINEPREFIX` or `CSP_BASE`.
- **Submodules**: none.
- **Binary formats** are marked as `binary` in `.gitattributes` (no diff/merge).
- **Language**: everything in the repository (code comments, messages, docs) is English.

## Fresh checkout

```bash
git clone <url> CSP5-for-Wine
cd CSP5-for-Wine

# install (downloads the CSP installer and, if needed, a portable Wine by itself):
./bundle/install.sh                            # or: ./install-csp-prefix.sh
./start-csp.sh                                 # start the editor
# (to use your own installer: put CSP_504w_setup.exe next to install.sh or into installer/
#  and pass --installer)
```

## Releases

The bundle tarballs are build artifacts and stay untracked; they are published as
GitHub release assets (needs the [`gh`](https://cli.github.com/) CLI, logged in via `gh auth login`):

```bash
./publish-github.sh                            # version from bundle/VERSION
```

The script creates the tag `v<VERSION>` (or updates an existing release) and uploads
`csp-linux-bundle-<VERSION>.tar.gz` together with `.sha256`. The release text is the
`## v<VERSION>` section of `RELEASE-NOTES.md`.

Packaging checklist: bump `bundle/VERSION`, update `bundle/README.md` (title) and
`RELEASE-NOTES.md`, build the tarball from `bundle/` (`files/` contents),
write the `.sha256` file, check the unpacked
tarball against `bundle/`.

> A submodule checkout only contains a `.git` **file** (a pointer to `.git/modules/…`),
> not a nested `.git` directory. That is exactly the normal case — do not confuse it with a
> "repo inside a repo".

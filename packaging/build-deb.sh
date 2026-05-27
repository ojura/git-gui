#!/bin/bash
# Build a .deb of this git-gui (syntax-highlighting fork). Architecture: all -
# it is Tcl plus a Python helper - so one package works on any architecture; we
# build per Ubuntu release mainly to validate the build and pin dependencies.
# Output goes to packaging/dist/ (override with $1).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

OUT="${1:-$REPO/packaging/dist}"; mkdir -p "$OUT"
PKGROOT="$(mktemp -d)"
trap 'rm -rf "$PKGROOT"' EXIT

# Build and stage-install into the standard Debian layout.
make
make install DESTDIR="$PKGROOT" gitexecdir=/usr/lib/git-core

# Version: git-gui's own version, '-' -> '.', plus the Ubuntu codename so the
# per-release builds sort and name distinctly.
VER="$(sed -n 's/^GITGUI_VERSION *= *//p' GIT-VERSION-FILE 2>/dev/null || true)"
# On a tagged CI build, take the version straight from the gitgui-* tag - robust
# even if git describe cannot see the tag in the CI checkout.
case "${GITHUB_REF_NAME:-}" in
  gitgui-[0-9]*) VER="${GITHUB_REF_NAME#gitgui-}" ;;
esac
[ -n "$VER" ] || VER="0.0.$(date +%Y%m%d)"
VER="${VER%-dirty}"; VER="${VER//-/.}"
CODENAME="$( . /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-unknown}" )"
DEBVER="${VER}~${CODENAME}"

mkdir -p "$PKGROOT/DEBIAN"
cat > "$PKGROOT/DEBIAN/control" <<CTRL
Package: git-gui-syntax
Version: $DEBVER
Architecture: all
Maintainer: ojura <ojura@users.noreply.github.com>
Installed-Size: $(du -sk "$PKGROOT" | cut -f1)
Depends: git (>= 2.20), tcl, tk, python3-pygments
Provides: git-gui
Conflicts: git-gui
Replaces: git-gui
Section: vcs
Priority: optional
Homepage: https://github.com/ojura/git-gui
Description: Git GUI with diff syntax highlighting
 A fork of git-gui that syntax-highlights the diff viewer using Pygments,
 with a long-line soft-wrap toggle and configurable colour modes. Per-line and
 per-hunk staging is byte-for-byte unchanged. Drop-in replacement for the
 standard git-gui (it Provides/Replaces it).
CTRL

DEB="$OUT/git-gui-syntax_${DEBVER}_all.deb"
dpkg-deb --build --root-owner-group "$PKGROOT" "$DEB"
echo "built: $DEB"

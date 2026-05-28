#!/bin/bash
# Assemble git-gui-pyggy-windows.zip: this git-gui plus a PowerShell installer
# that drops it into Git for Windows and sets up Python 3 + Pygments.
#
# Git for Windows already bundles Tcl/Tk (wish), so we only ship the git-gui
# script and its lib/. We build with GITGUI_RELATIVE=1 so the generated git-gui
# locates its lib relative to its own path (libexec/git-core/git-gui finds
# ../../share/git-gui/lib), which is exactly the Git for Windows layout the
# installer copies into. Output goes to packaging/dist/ (override with $1).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

OUT="${1:-$REPO/packaging/dist}"; mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/git-gui-pyggy-windows"
mkdir -p "$PKG"

# Build the relocatable git-gui (regenerates lib/tclIndex too).
make GITGUI_RELATIVE=1

# The wish launcher and its Tcl/Python lib are all Git for Windows needs.
cp git-gui "$PKG/git-gui"
cp -r lib "$PKG/lib"
cp "$HERE/windows/install.ps1" "$PKG/install.ps1"

cat > "$PKG/README.txt" <<'TXT'
git-gui-pyggy for Windows
=========================

git-gui with diff syntax highlighting (Pygments), a long-line soft-wrap toggle,
and byte-for-byte unchanged per-line / per-hunk staging.

Requires Git for Windows (https://git-scm.com/download/win).

Install
-------
Right-click install.ps1 -> "Run with PowerShell",
or in a PowerShell prompt:

    powershell -ExecutionPolicy Bypass -File install.ps1

It copies git-gui into your Git for Windows install (prompting for admin), then
sets up Python 3 (via winget if you don't have it) and Pygments, which power the
highlighting. git-gui runs without them, just without colour.

Then launch it as usual:

    git gui

Toggle highlighting / wrap from the diff viewer's right-click menu.
TXT

VER="$(sed -n 's/^GITGUI_VERSION *= *//p' GIT-VERSION-FILE 2>/dev/null || true)"
case "${GITHUB_REF_NAME:-}" in
  gitgui-[0-9]*) VER="${GITHUB_REF_NAME#gitgui-}" ;;
esac
[ -n "$VER" ] || VER="0.0.$(date +%Y%m%d)"
VER="${VER%-dirty}"; VER="${VER//-/.}"

# The package name already carries the "pyggy" codename, so the filename only
# needs the numeric version - drop a trailing non-numeric component (0.21.pyggy
# -> 0.21) to avoid saying pyggy twice.
ZIPVER="$VER"
case "${ZIPVER##*.}" in *[!0-9]*) ZIPVER="${ZIPVER%.*}" ;; esac

ZIP="$OUT/git-gui-pyggy-windows-${ZIPVER}.zip"
rm -f "$OUT"/git-gui-pyggy-windows*.zip
( cd "$STAGE" && zip -qr "$ZIP" git-gui-pyggy-windows )
echo "built: $ZIP"

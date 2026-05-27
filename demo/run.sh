#!/bin/bash
# (Re)launch this in-tree git-gui inside the Xephyr test display, with the
# version shim ahead on PATH. Usage: demo/run.sh [repo-dir]   (default: cwd)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GG="$(cd "$HERE/.." && pwd)/git-gui.sh"
export PATH="$HERE/gitshim:$PATH"
export DISPLAY="${GG_TEST_DISPLAY:-:1}"
REPO="${1:-$PWD}"

for p in $(pgrep -f "$GG"); do kill "$p" 2>/dev/null; done   # only this tree's git-gui
cd "$REPO"
setsid "$GG" >/tmp/gg.log 2>&1 </dev/null &
disown
echo "git-gui launched on $DISPLAY in $REPO"

#!/bin/bash
# Build the demo montage: launch this git-gui on a set of fixtures, screenshot
# each (default font and Ubuntu Mono, plus Python, merge conflict, context mode,
# highlighting-off, long-line wrap), label, and tile into one image.
# Prereqs: a running test display (demo/xephyr-env.sh), xdotool, ImageMagick.
# Captures via the GG_READY_FILE draw-finished hook, so no fixed sleeps.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GG="$(cd "$HERE/.." && pwd)/git-gui.sh"
export PATH="$HERE/gitshim:$PATH"
export DISPLAY="${GG_TEST_DISPLAY:-:1}"
UMONO="-family {Ubuntu Mono} -size 15"
LBLFONT=/usr/share/fonts/truetype/ubuntu/UbuntuMono-B.ttf
OUT="${GG_DEMO_OUT:-/tmp/ggdemo}"
rm -rf "$OUT"; mkdir -p "$OUT/repos"
RP="$OUT/repos"

mkrepo() {
  local d="$RP/$1"; mkdir -p "$d"; cd "$d"
  git init -q; git config user.email d@example.com; git config user.name demo
  git config gui.fontdiff "$UMONO"
}
shoot() {            # $1=repodir $2=outname $3=label
  pkill -f "$GG" 2>/dev/null; sleep 0.3
  cd "$1"
  local RDY="/tmp/ggready.$2"; rm -f "$RDY"
  GG_READY_FILE="$RDY" setsid "$GG" >/tmp/gg.log 2>&1 </dev/null &
  for i in $(seq 1 300); do xdotool search --name "Git Gui" >/dev/null 2>&1 && break; sleep 0.03; done
  local WID; WID=$(xdotool search --name "Git Gui" | head -1)
  xdotool windowsize "$WID" 1180 700; xdotool windowmove "$WID" 0 0; xdotool windowactivate --sync "$WID"
  rm -f "$RDY"; xdotool mousemove --window "$WID" 55 72 click 1
  for i in $(seq 1 300); do [ -s "$RDY" ] && break; sleep 0.02; done
  import -window "$WID" "$OUT/$2.png"
  convert "$OUT/$2.png" -crop 1180x440+0+0 +repage \
    -background '#1d1f21' -fill '#f4f4f4' -font "$LBLFONT" -pointsize 22 \
    -gravity North -splice 0x34 -annotate +0+6 "$3" "$OUT/$2.png"
  echo "shot $2"
}

mkrepo cpp
cat > main.cpp <<'EOF'
#include <string>
#include <vector>

// Accumulate a greeting for every name in the list.
std::string makeGreetings(const std::vector<std::string> &names) {
    std::string out;
    out.reserve(128);
    for (const std::string &name : names)
        out += "Hello, " + name + "!\n";
    return out;
}
EOF
git add main.cpp; git commit -qm init
sed -i 's/Hello/Greetings/; s/every name/each name/; s/128/256/' main.cpp
CPP="$RP/cpp"
git -C "$CPP" config --unset gui.fontdiff
shoot "$CPP" 1_cpp_default "C++ : default font"
git -C "$CPP" config gui.fontdiff "$UMONO"
shoot "$CPP" 2_cpp_ubuntu "C++ : Ubuntu Mono"

mkrepo py
cat > demo.py <<'EOF'
import sys
from typing import List


def greet(names: List[str]) -> str:
    """Return one numbered greeting per name."""
    out = ""
    for i, name in enumerate(names):  # zero-based index
        out += f"{i}: Hello, {name}!\n"
    return out
EOF
git add demo.py; git commit -qm init
sed -i 's/Hello/Hi/; s/numbered/indexed/' demo.py
shoot "$RP/py" 3_python "Python : same engine, any language"

mkrepo conflict
cat > calc.cpp <<'EOF'
int compute(int n) {
    int total = 0;
    return total;
}
EOF
git add calc.cpp; git commit -qm base
DEF=$(git symbolic-ref --short HEAD)
git checkout -q -b feature
cat > calc.cpp <<'EOF'
int compute(int n) {
    // sum of squares
    int total = 0;
    for (int i = 0; i < n; ++i) total += i * i;
    return total;
}
EOF
git commit -qam feature
git checkout -q "$DEF"
cat > calc.cpp <<'EOF'
int compute(int n) {
    // doubled running sum
    int total = 0;
    for (int i = 0; i < n; ++i) total += 2 * i;
    return total;
}
EOF
git commit -qam mainline
git merge feature >/dev/null 2>&1
shoot "$RP/conflict" 4_conflict "Merge conflict : combined (3-way) diff"

cd "$CPP"; git config gui.diffsyntaxmode context
shoot "$CPP" 5_context "C++ : context mode (solid +/- colour)"
cd "$CPP"; git config gui.diffsyntaxmode tint; git config gui.diffsyntax false
shoot "$CPP" 6_off "C++ : highlighting off (stock git-gui)"
git config gui.diffsyntax true

mkrepo wrap
printf '#include <string>\n\n' > long.cpp
echo 'const char *banner = "a deliberately very long single line that runs well past the right edge of the diff pane to show the soft-wrap toggle this patch adds to git-gui";' >> long.cpp
git add long.cpp; git commit -qm init
sed -i 's/very long/extremely long/' long.cpp
git config gui.diffwrap char
shoot "$RP/wrap" 7_wrap "Long line : Wrap Long Lines on (soft-wrapped)"

cd "$OUT"
montage 1_cpp_default.png 2_cpp_ubuntu.png 3_python.png 4_conflict.png 5_context.png 6_off.png 7_wrap.png \
  -tile 2x4 -geometry +8+8 -background '#111111' "$OUT/montage.png"
pkill -f "$GG" 2>/dev/null
echo "montage: $OUT/montage.png"

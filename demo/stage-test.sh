#!/bin/bash
# Thorough single/many-line stage AND unstage test, syntax highlighting ON.
# Sets up a fixture, drives each operation through the diff context menu, and
# checks the git index byte-exactly afterwards - proving the tags-only
# highlighting never perturbs what gets staged. Exit non-zero on any failure.
# Prereqs: a running test display (demo/xephyr-env.sh), xdotool.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GG="$(cd "$HERE/.." && pwd)/git-gui.sh"
export PATH="$HERE/gitshim:$PATH"
export DISPLAY="${GG_TEST_DISPLAY:-:1}"
REPO="${GG_STAGE_REPO:-/tmp/gg-stagetest}"
RDY=/tmp/ggready.stage
PASS=0; FAIL=0

# --- fixture: base committed, then three distinct added lines ---
rm -rf "$REPO"; mkdir -p "$REPO"; cd "$REPO"
git init -q; git config user.email t@example.com; git config user.name t
git config gui.fontdiff "-family {Ubuntu Mono} -size 16"
printf 'int main() {\n    int a = 1;\n    return 0;\n}\n' > calc.cpp
git add calc.cpp; git commit -qm base
printf 'int main() {\n    int a = 1;\n    int b = 2;\n    int c = 3;\n    int d = 4;\n    return 0;\n}\n' > calc.cpp

check(){ if [ "$2" = "$3" ]; then echo "PASS: $1"; PASS=$((PASS+1));
         else echo "FAIL: $1"; printf '  expected:[%s]\n  got:     [%s]\n' "$3" "$2"; FAIL=$((FAIL+1)); fi; }
launch(){ # $1 = window-y of file entry (72 = Unstaged pane, 242 = Staged pane)
  pkill -f "$GG" 2>/dev/null; sleep 0.4
  cd "$REPO"; rm -f "$RDY"
  GG_READY_FILE="$RDY" setsid "$GG" >/tmp/gg.log 2>&1 </dev/null &
  for i in $(seq 1 300); do xdotool search --name "Git Gui" >/dev/null 2>&1 && break; sleep 0.03; done
  WID=$(xdotool search --name "Git Gui" | head -1)
  xdotool windowsize "$WID" 1100 640; xdotool windowmove "$WID" 0 0; xdotool windowactivate --sync "$WID"
  rm -f "$RDY"; xdotool mousemove --window "$WID" 55 "$1" click 1
  for i in $(seq 1 400); do [ -s "$RDY" ] && break; sleep 0.02; done
}
menu(){ # $1=x $2=y line to right-click ; $3 = Downs to menu entry (1=Hunk, 2=Line)
  local n; n=$(cat "$RDY" 2>/dev/null)
  xdotool mousemove --window "$WID" "$1" "$2" click 3; sleep 0.4
  local k=""; for ((j=0;j<$3;j++)); do k="$k Down"; done
  xdotool key $k Return
  for i in $(seq 1 400); do [ -s "$RDY" ] && [ "$(cat "$RDY")" != "$n" ] && break; sleep 0.02; done
  sleep 0.2
}
cached(){ git -C "$REPO" --no-pager diff --cached calc.cpp | grep '^+' | grep -v '^++'; }

# 'int c = 3;' sits at window-y ~143; the Staged-pane file entry at ~242.
git -C "$REPO" reset -q; launch 72;  menu 230 143 2
check "single-line stage -> only 'int c = 3;'" "$(cached)" "+    int c = 3;"

git -C "$REPO" reset -q; launch 72;  menu 230 143 1
check "many-line (hunk) stage -> b,c,d" "$(cached)" "$(printf '+    int b = 2;\n+    int c = 3;\n+    int d = 4;')"

git -C "$REPO" reset -q; git -C "$REPO" add calc.cpp; launch 242; menu 230 143 2
check "single-line unstage 'int c = 3;' -> b,d remain" "$(cached)" "$(printf '+    int b = 2;\n+    int d = 4;')"

git -C "$REPO" reset -q; git -C "$REPO" add calc.cpp; launch 242; menu 230 143 1
check "many-line (hunk) unstage -> nothing staged" "$(cached)" ""

pkill -f "$GG" 2>/dev/null
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

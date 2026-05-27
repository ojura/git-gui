# git-gui syntax-highlighting demo + visual test harness

Scripts to demonstrate and regression-test the diff syntax highlighting, long-line
wrap, and (crucially) that per-line / per-hunk staging stays byte-exact with
highlighting on. They drive a real git-gui in a nested X server and screenshot it.

## Prerequisites

- `Xephyr`, `metacity`, `xdotool`, ImageMagick (`import`, `convert`, `montage`)
- Python 3 with `pygments` (the highlight helper)
- Ubuntu Mono font (for the labelled demo); any system git is fine

If the system git is older than 2.36, `gitshim/` fakes the version check and
no-ops `git hook run`, so this trunk git-gui still runs. It is put ahead on
`PATH` automatically by the scripts.

## Usage

    demo/xephyr-env.sh        # start Xephyr :1 (1920x1200) + metacity, once
    demo/make-demo.sh         # build the 7-tile demo montage -> /tmp/ggdemo/montage.png
    demo/stage-test.sh        # single/many-line stage+unstage suite (exits non-zero on failure)
    demo/run.sh [repo]        # just launch git-gui in the test display on a repo

Override the nested display with `GG_TEST_DISPLAY=:N`.

## How the capture stays fast

git-gui carries an optional, env-gated hook: when `GG_READY_FILE` is set it writes
an incrementing counter once a diff has loaded and its highlight is applied (after
forcing a redraw). The harness blocks on that counter changing and screenshots the
instant the draw is done, rather than sleeping a fixed interval.

## What the suites cover

- `make-demo.sh`: C++ in the default font and in Ubuntu Mono, Python, a merge
  conflict (combined / 3-way diff), context vs tint colour modes, highlighting
  off (stock git-gui), and long-line soft-wrap.
- `stage-test.sh`: stage a single line, stage a whole hunk, unstage a single
  line, unstage a whole hunk - each asserted byte-exact against the git index
  while syntax highlighting is on.

#!/bin/bash
# Nested test display for driving git-gui headless-ish: Xephyr on $GG_TEST_DISPLAY
# (default :1, 1920x1200) plus metacity, rendered as a window on your real
# session display. Run this once, then use run.sh / make-demo.sh / stage-test.sh.
# Tear down with:  kill $(cat /tmp/gg-xephyr.pids)   (killing Xephyr drops :1)
set -u
NEST="${GG_TEST_DISPLAY:-:1}"
HOST="${DISPLAY:-:0}"
: "${XAUTHORITY:=$HOME/.Xauthority}"; export XAUTHORITY
PIDS=/tmp/gg-xephyr.pids; : > "$PIDS"

DISPLAY="$HOST" Xephyr "$NEST" -screen 1920x1200 -ac -resizeable -no-host-grab \
    -title "git-gui test ($NEST)" >/tmp/gg-xephyr.log 2>&1 &
echo $! >> "$PIDS"

for i in $(seq 1 100); do DISPLAY="$NEST" xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done

DISPLAY="$NEST" metacity --sm-disable >/tmp/gg-metacity.log 2>&1 &
echo $! >> "$PIDS"

echo "ready: Xephyr + metacity on $NEST (host $HOST), pids: $(tr '\n' ' ' <"$PIDS")"

#!/usr/bin/env bash
# Runs once after herdr restores the session. The watcher is a detached
# process, so a server restart can leave an armed state file with nothing
# polling it — re-attach, and only then.
set -uo pipefail

WTS="$(cd "$(dirname "$0")" && pwd)/wts.sh"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/want-to-sleep}"

[ -f "$STATE_DIR/armed.json" ] || exit 0
pgrep -f "$WTS watch" >/dev/null 2>&1 && exit 0

if command -v caffeinate >/dev/null 2>&1; then
  nohup caffeinate -i bash "$WTS" watch >/dev/null 2>&1 &
else
  nohup bash "$WTS" watch >/dev/null 2>&1 &
fi
exit 0

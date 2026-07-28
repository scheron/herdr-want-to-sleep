#!/usr/bin/env bash
# Runs once after herdr restores the session. The watcher is a detached
# process, so a server restart can leave an armed state file with nothing
# polling it — re-attach, and only then.
set -uo pipefail

# herdr runs plugin commands with a minimal PATH; make sure jq resolves.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

WTS="$(cd "$(dirname "$0")" && pwd)/wts.sh"
PLUGIN_ID="${HERDR_PLUGIN_ID:-scheron.want-to-sleep}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/$PLUGIN_ID}"

[ -f "$STATE_DIR/armed.json" ] || exit 0
pgrep -f "$WTS watch" >/dev/null 2>&1 && exit 0

if command -v caffeinate >/dev/null 2>&1; then
  nohup caffeinate -i bash "$WTS" watch >/dev/null 2>&1 &
else
  nohup bash "$WTS" watch >/dev/null 2>&1 &
fi
exit 0

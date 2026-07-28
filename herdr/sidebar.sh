#!/usr/bin/env bash
# Open, close or toggle the want-to-sleep sidebar.
#
#   sidebar.sh toggle   open it, or close it if this workspace already has one
#   sidebar.sh open     open it, no-op if one is open
#   sidebar.sh close    close every want-to-sleep pane in the workspace
#
# The sidebar is any pane labelled "want-to-sleep" in the live pane list; there
# is no state file to drift. Plain `pane close` is used rather than `plugin pane
# close`, because the plugin-pane registry does not survive a herdr restart and
# a stale entry would strand the pane.
set -uo pipefail

# herdr runs plugin commands with a minimal PATH; make sure jq resolves.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

H="${HERDR_BIN_PATH:-herdr}"
PLUGIN_ID="${HERDR_PLUGIN_ID:-scheron.want-to-sleep}"
LABEL="want-to-sleep"
mode="${1:-toggle}"

refuse() { printf 'want-to-sleep: %s\n' "$1" >&2; exit 1; }

cfg() {
  local dir="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/$PLUGIN_ID}"
  local v=""
  [ -f "$dir/config" ] && v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$dir/config" \
    | sed 's/[[:space:]]*$//' | tail -1)
  printf '%s' "${v:-$2}"
}

ws="${HERDR_WORKSPACE_ID:-}"
pane="${HERDR_PANE_ID:-}"
[ -n "$ws" ] || refuse "no workspace context (invoke from inside herdr)"

# One snapshot for the whole run. A failed listing must not read as "nothing
# open" — that would stack a duplicate on toggle and false-succeed a close.
panes_json=$("$H" pane list --workspace "$ws" 2>/dev/null) && [ -n "$panes_json" ] \
  || refuse "herdr pane list failed for $ws"
existing=$(printf '%s' "$panes_json" | jq -r --arg l "$LABEL" \
  '.result.panes[] | select(.label == $l) | .pane_id' 2>/dev/null)

close_all() {
  local p closed="" failed=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if "$H" pane close "$p" >/dev/null 2>&1; then closed="$closed $p"; else failed="$failed $p"; fi
  done <<EOF
$existing
EOF
  [ -z "$failed" ] || refuse "failed to close$failed in $ws"
  printf 'closed%s in %s\n' "$closed" "$ws"
}

case "$mode" in
  close)
    [ -n "$existing" ] || { printf 'close: nothing open in %s\n' "$ws"; exit 0; }
    close_all; exit 0 ;;
  toggle)
    [ -n "$existing" ] && { close_all; exit 0; } ;;
  open)
    [ -n "$existing" ] && { printf 'open: already open in %s\n' "$ws"; exit 0; } ;;
  *)
    refuse "unknown mode '$mode' (toggle | open | close)" ;;
esac

placement=$(cfg placement split)
direction=$(cfg direction right)

case "$placement" in
  split|zoomed)
    [ -n "$pane" ] || pane=$(printf '%s' "$panes_json" | jq -r '.result.panes[0].pane_id // empty' 2>/dev/null)
    [ -n "$pane" ] || refuse "no pane to attach to in $ws"
    set -- --placement "$placement" --target-pane "$pane"
    [ "$placement" = "split" ] && set -- "$@" --direction "$direction" ;;
  tab)     set -- --placement tab --workspace "$ws" ;;
  overlay) set -- --placement overlay ;;
  *)       refuse "unknown placement '$placement' (split | tab | overlay | zoomed)" ;;
esac

new=$("$H" plugin pane open --plugin "$PLUGIN_ID" --entrypoint status "$@" --focus 2>/dev/null \
  | jq -r '.result.plugin_pane.pane.pane_id // empty' 2>/dev/null)
[ -n "$new" ] || refuse "herdr plugin pane open failed"
printf 'opened %s (%s) in %s\n' "$new" "$placement" "$ws"

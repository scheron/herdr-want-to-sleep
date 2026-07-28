#!/usr/bin/env bash
#
# want-to-sleep — wait until herdr reports that no agent is working any more,
# then put the machine to sleep. Usable standalone or through the plugin actions.
#
#   wts.sh arm [minutes] [sleep|shutdown] [HH:MM-HH:MM]
#   wts.sh disarm
#   wts.sh toggle
#   wts.sh status
#   wts.sh journal
#   wts.sh watch                internal — the polling loop
#
# Nothing ever powers down unless you armed it.

set -uo pipefail

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

# Fall back to the exact paths herdr itself would hand us, so that running this
# script from a shell and pressing the keybinding drive the same state. Anything
# else lets the CLI report "not armed" while the plugin's watcher is running.
PLUGIN_ID="${HERDR_PLUGIN_ID:-scheron.want-to-sleep}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/$PLUGIN_ID}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/$PLUGIN_ID}"
STATE="$STATE_DIR/armed.json"
JOURNAL="$STATE_DIR/journal.md"
CONFIG="$CONFIG_DIR/config"

POLL_SECONDS=60
MAX_ARMED_SECONDS=43200

die() { printf 'want-to-sleep: %s\n' "$*" >&2; exit 2; }

# key = value, comments and blanks ignored. Never sourced — a config file must
# not be able to run code.
cfg() {
  local key="$1" fallback="$2" v=""
  [ -f "$CONFIG" ] && v=$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$CONFIG" \
    | sed 's/[[:space:]]*$//; s/^"//; s/"$//' | tail -1)
  printf '%s' "${v:-$fallback}"
}

state_get() { jq -r "$1 // empty" "$STATE" 2>/dev/null; }
armed() { [ -f "$STATE" ]; }

agents_json() {
  command -v "$HERDR_BIN" >/dev/null 2>&1 || return 1
  "$HERDR_BIN" agent list 2>/dev/null | jq -ce '.result.agents // empty' 2>/dev/null
}

count_status() { printf '%s' "$1" | jq -r --arg s "$2" '[.[] | select(.agent_status == $s)] | length'; }

# Agents that would still make progress if we left the machine on. "blocked"
# means the agent is waiting on a human; overnight that is never coming, so by
# default it counts as settled rather than as a reason to stay awake.
unsettled_count() {
  local agents="$1" n
  n=$(count_status "$agents" working)
  [ "$(cfg blocked settle)" = "wait" ] && n=$(( n + $(count_status "$agents" blocked) ))
  printf '%s' "$n"
}

idle_seconds() {
  local v
  v=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  printf '%s' "${v:-0}"
}

in_window() {
  local w="${1:-}" start end now
  [ -n "$w" ] || return 0
  start="${w%%-*}"; end="${w##*-}"
  start=$(( 10#${start%%:*} * 60 + 10#${start##*:} ))
  end=$(( 10#${end%%:*} * 60 + 10#${end##*:} ))
  now=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
  if [ "$start" -le "$end" ]; then
    [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]
  else
    [ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
  fi
}

notify() {
  "$HERDR_BIN" notification show "$1" --body "$2" --sound "${3:-none}" >/dev/null 2>&1 && return 0
  command -v osascript >/dev/null 2>&1 \
    && osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1
  return 0
}

self_path() { printf '%s' "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"; }

watch_running() { pgrep -f "$(self_path) watch" >/dev/null 2>&1; }

watch_start() {
  watch_stop
  if command -v caffeinate >/dev/null 2>&1; then
    nohup caffeinate -i "$(self_path)" watch >/dev/null 2>&1 &
  else
    nohup "$(self_path)" watch >/dev/null 2>&1 &
  fi
}

watch_stop() { pkill -f "$(self_path) watch" >/dev/null 2>&1; return 0; }

set_settled_since() {
  local v="$1" tmp="$STATE.tmp"
  jq --argjson s "$v" '.settled_since = $s' "$STATE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE"
}

write_journal() {
  local action="$1" agents="${2:-}" blocked
  mkdir -p "$STATE_DIR"
  {
    printf '\n## %s — %s\n\n' "$(date '+%Y-%m-%d %H:%M')" "$action"
    if [ -n "$agents" ] && [ "$agents" != "[]" ]; then
      printf '%s' "$agents" | jq -r '.[]
        | "- **\(.agent_status)** — \(.terminal_title_stripped // .terminal_title // "untitled")\n  - \(.agent) · \(.cwd)"'
      blocked=$(count_status "$agents" blocked)
      if [ "$blocked" -gt 0 ]; then
        printf '\n> %s agent(s) were blocked waiting for input. They did not finish.\n' "$blocked"
      fi
    else
      printf '- (no agents were registered with herdr)\n'
    fi
  } >> "$JOURNAL"
}

power_down() {
  local action="$1" agents="$2" grace waited=0
  grace=$(cfg grace_seconds 120)
  notify "want-to-sleep" "Every agent has settled — ${action} in $(( grace / 60 )) min. Touch the keyboard to cancel." done
  while [ "$waited" -lt "$grace" ]; do
    sleep 5
    waited=$(( waited + 5 ))
    armed || return 1
    if [ "$(idle_seconds)" -lt 10 ]; then
      rm -f "$STATE"
      notify "want-to-sleep" "Cancelled — you are back at the keyboard."
      return 1
    fi
  done
  write_journal "$action" "$agents"
  rm -f "$STATE"
  case "$action" in
    sleep)    pmset sleepnow ;;
    shutdown) osascript -e 'tell application "System Events" to shut down' ;;
    *)        die "unknown action '$action'" ;;
  esac
}

check() {
  armed || return 1
  local action minutes window armed_at settled_since agents now
  action=$(state_get .action); minutes=$(state_get .minutes)
  window=$(state_get .window); armed_at=$(state_get .armed_at)
  settled_since=$(state_get .settled_since)
  [ -n "$action" ] && [ -n "$minutes" ] && [ -n "$armed_at" ] || return 1
  now=$(date +%s)

  if [ $(( now - armed_at )) -ge "$MAX_ARMED_SECONDS" ]; then
    rm -f "$STATE"
    notify "want-to-sleep" "Disarmed — 12h without ever settling."
    return 1
  fi

  agents=$(agents_json) || { set_settled_since 0; return 1; }

  if [ "$(unsettled_count "$agents")" -gt 0 ]; then
    [ "${settled_since:-0}" != "0" ] && set_settled_since 0
    return 1
  fi

  # Settled, and it has to stay that way — an agent that pauses for ten seconds
  # between tool calls must not read as finished.
  if [ "${settled_since:-0}" = "0" ]; then
    set_settled_since "$now"
    return 1
  fi
  [ $(( now - settled_since )) -ge $(( minutes * 60 )) ] || return 1

  in_window "$window" || return 1
  [ "$(idle_seconds)" -ge "$(cfg idle_seconds 300)" ] || return 1

  power_down "$action" "$agents"
}

cmd_arm() {
  local minutes action window arg
  minutes=$(cfg minutes 20); action=$(cfg action sleep); window=$(cfg window "")
  for arg in "$@"; do
    case "$arg" in
      *[!0-9]*)
        case "$arg" in
          sleep|shutdown) action="$arg" ;;
          [0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]) window="$arg" ;;
          *) die "unrecognised '$arg' — expected minutes, sleep|shutdown, or HH:MM-HH:MM" ;;
        esac ;;
      '') die "empty argument" ;;
      *) minutes="$arg" ;;
    esac
  done
  command -v jq >/dev/null || die "jq is required"
  agents_json >/dev/null || die "herdr is not reachable — cannot see agent states"

  mkdir -p "$STATE_DIR"
  jq -n --arg action "$action" --arg window "$window" \
        --argjson minutes "$minutes" --argjson at "$(date +%s)" \
    '{action: $action, minutes: $minutes, window: $window, armed_at: $at, settled_since: 0}' \
    > "$STATE" || die "could not write $STATE"

  watch_start
  printf 'armed — %s once no agent has been working for %s min%s\n' \
    "$action" "$minutes" "${window:+, only between $window}"
}

cmd_disarm() {
  rm -f "$STATE"
  watch_stop
  printf 'disarmed\n'
}

cmd_status() {
  local agents window
  if armed; then
    window=$(state_get .window)
    printf 'armed     %s after %s min settled, since %s\n' \
      "$(state_get .action)" "$(state_get .minutes)" \
      "$(date -r "$(state_get .armed_at)" '+%H:%M' 2>/dev/null)"
    printf 'window    %s\n' "${window:-any hour}"
    if [ "$(state_get .settled_since)" != "0" ]; then
      printf 'settled   %s min so far\n' \
        "$(( ( $(date +%s) - $(state_get .settled_since) ) / 60 ))"
    else
      printf 'settled   not yet\n'
    fi
  else
    printf 'armed     no\n'
  fi
  printf 'watcher   %s\n' "$(watch_running && printf running || printf stopped)"
  printf 'input     %s min since the last keyboard or mouse event\n' "$(( $(idle_seconds) / 60 ))"
  if agents=$(agents_json); then
    printf 'agents    %s working · %s blocked · %s idle · %s done\n' \
      "$(count_status "$agents" working)" "$(count_status "$agents" blocked)" \
      "$(count_status "$agents" idle)" "$(count_status "$agents" done)"
    printf '%s' "$agents" | jq -r '.[] | "          [\(.agent_status)] \(.terminal_title_stripped // "untitled")"'
  else
    printf 'agents    herdr unreachable\n'
  fi
}

cmd_journal() {
  [ -f "$JOURNAL" ] && cat "$JOURNAL" || printf 'no journal yet: %s\n' "$JOURNAL"
}

cmd_watch() {
  while armed; do
    check && return 0
    sleep "$POLL_SECONDS"
  done
}

case "${1:-status}" in
  arm)     shift; cmd_arm "$@" ;;
  disarm)  cmd_disarm ;;
  toggle)  armed && cmd_disarm || { shift; cmd_arm "$@"; } ;;
  status)  cmd_status ;;
  journal) cmd_journal ;;
  watch)   cmd_watch ;;
  -h|--help|help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0" ;;
  *)       die "unknown command '${1}' — try: arm, disarm, toggle, status, journal" ;;
esac

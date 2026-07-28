#!/usr/bin/env bash
# The want-to-sleep sidebar. Runs in a plugin pane, so unlike the actions it has
# a real TTY: it redraws the live watch state and takes keys.
#
#   a  start watching     c  stop
#   -  +  minutes
#   q  stop and close     x  close, keep watching
#
# `shutdown` is deliberately not reachable from here. It is a rarer and riskier
# choice than sleep, and offering it as a one-key toggle beside the others
# invited mistakes; it lives in the config file instead.
set -uo pipefail

# herdr runs plugin commands with a minimal PATH; make sure jq resolves.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

H="${HERDR_BIN_PATH:-herdr}"
WTS="$(cd "$(dirname "$0")" && pwd)/wts.sh"
PLUGIN_ID="${HERDR_PLUGIN_ID:-scheron.want-to-sleep}"
STATE="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/$PLUGIN_ID}/armed.json"

ESC=$'\033'
DIM="${ESC}[2m"; B="${ESC}[1m"; R="${ESC}[0m"
GREEN="${ESC}[38;5;114m"; YELLOW="${ESC}[38;5;179m"
RED="${ESC}[38;5;174m"; GREY="${ESC}[38;5;245m"
BLUE="${ESC}[38;5;111m"; TEXT="${ESC}[38;5;252m"

cleanup() { printf '%s[?25h' "$ESC"; }
trap cleanup EXIT INT TERM

armed() { [ -f "$STATE" ]; }
sget() { jq -r "$1 // empty" "$STATE" 2>/dev/null; }

# stty reads the pty window size directly. terminfo reported a stale 24 rows in
# a herdr split, which collapsed the bottom padding to nothing.
term_size() { stty size </dev/tty 2>/dev/null || printf '40 80'; }
rows() { local r; r=$(term_size | cut -d' ' -f1); [ "${r:-0}" -ge 10 ] || r=40; printf '%s' "$r"; }
cols() { local c; c=$(term_size | cut -d' ' -f2); [ "${c:-0}" -ge 24 ] || c=80; printf '%s' "$c"; }

# Wrap prose to the pane's real width instead of baking line breaks into the
# text, which left the legend in a narrow column no matter how wide the split.
para() { fold -s -w "$(( $(cols) - 4 ))" | sed 's/[[:space:]]*$//; s/^/  /'; }

cfg() {
  local dir="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/$PLUGIN_ID}"
  local v=""
  [ -f "$dir/config" ] && v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$dir/config" \
    | sed 's/[[:space:]]*$//' | tail -1)
  printf '%s' "${v:-$2}"
}

MIN=$(cfg minutes 15)
ACT=$(cfg action sleep)
armed && MIN=$(sget .minutes)

# Edit the state in place rather than re-arming. A full arm makes a herdr
# round-trip and restarts the watcher, slow enough that held keys queue up
# behind it; the watcher re-reads this file every poll anyway.
apply() {
  armed || return 0
  local tmp="$STATE.tmp"
  jq --argjson m "$MIN" '.minutes = $m' "$STATE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATE"
}

status_block() {
  local since settled w
  if armed; then
    since=$(sget .settled_since); w=$(sget .window)
    printf '  %s●%s  %swatching%s\n' "$GREEN" "$R" "$B" "$R"
    printf '     %ss after %s min with no agent working\n' "$(sget .action)" "$(sget .minutes)"
    [ -n "$w" ] && printf '     %swindow%s  %s\n' "$GREY" "$R" "$w"
    if [ -n "$since" ] && [ "$since" != "0" ]; then
      settled=$(( ( $(date +%s) - since ) / 60 ))
      printf '     %squiet%s   %s%s of %s min%s\n' "$GREY" "$R" "$GREEN" "$settled" "$(sget .minutes)" "$R"
    else
      printf '     %squiet%s   %snot yet%s\n' "$GREY" "$R" "$YELLOW" "$R"
    fi
  else
    printf '  %s○%s  %snot watching%s\n' "$GREY" "$R" "$B" "$R"
    printf '     would %s after %s min of quiet\n' "$ACT" "$MIN"
  fi
}

agents_block() {
  local agents st title c icon
  agents=$("$H" agent list 2>/dev/null | jq -c '.result.agents // []' 2>/dev/null)
  [ -n "$agents" ] || agents='[]'
  printf '  %sagents%s\n' "$GREY" "$R"
  if [ "$agents" = "[]" ]; then
    printf '     %s(none registered with herdr)%s\n' "$DIM" "$R"
    return
  fi
  printf '%s' "$agents" \
    | jq -r '.[] | "\(.agent_status)\t\(.terminal_title_stripped // .terminal_title // "untitled")"' \
    | while IFS=$'\t' read -r st title; do
        case "$st" in
          working) c="$YELLOW"; icon="●" ;;
          blocked) c="$RED";    icon="◐" ;;
          done)    c="$GREEN";  icon="✓" ;;
          idle)    c="$GREY";   icon="○" ;;
          *)       c="$DIM";    icon="?" ;;
        esac
        printf '     %s%s %-8s%s %s\n' "$c" "$icon" "$st" "$R" "${title:0:$(( $(cols) - 20 ))}"
      done
}

key() { printf '%s%s%s%s %s%s%s' "$B" "$BLUE" "$1" "$R" "$TEXT" "$2" "$R"; }

keys_block() {
  printf '  '
  if armed; then key c "stop"; else key a "start"; fi
  printf '   '; key "-/+" "quiet time"
  printf '   '; key x "close, keep watching"
  printf '   '; key q "stop and close"
}

rule() {
  printf '  %s' "$DIM"
  awk -v n="$(( $(cols) - 4 ))" 'BEGIN { while (i++ < n) printf "─" }'
  printf '%s' "$R"
}

legend_block() {
  printf '  %s%show it works%s\n' "$DIM" "$B" "$R"
  printf '%s' "$DIM"
  printf 'Every agent herdr can see is watched. While none of them is working, a quiet timer runs; anything going back to work resets it to zero.\n' | para
  printf '\n'
  printf '    ● working   still going, resets the timer\n'
  printf '    ◐ blocked   waiting on you, counts as quiet — it will not unblock overnight\n'
  printf '    ✓ done      finished\n'
  printf '    ○ idle      waiting for a prompt\n'
  printf '\n'
  printf 'It sleeps only when the quiet has run unbroken for the full N minutes, the keyboard has been untouched for five, and you are inside the time window if you set one. You get a two minute warning first, and touching the keyboard cancels it.\n' | para
  printf '\n'
  printf 'Closing this pane with x keeps watching; q stops it. Nothing ever sleeps unless you started it.\n' | para
  printf '%s' "$R"
}

# Redraw without clearing. A full ESC[2J leaves a blank frame on screen until
# the next write lands, which reads as a flicker every poll; overwriting each
# line and erasing to its end, then erasing what is left below, never blanks.
# ESC[?2026h/l asks terminals that support it to show the frame atomically.
draw() {
  local body footer pad
  body="$(status_block)"$'\n\n'"$(agents_block)"
  footer="$(keys_block)"$'\n'"$(rule)"$'\n\n'"$(legend_block)"
  pad=$(( $(rows) - $(printf '%s\n' "$body" | wc -l) - $(printf '%s\n' "$footer" | wc -l) - 3 ))
  [ "$pad" -lt 1 ] && pad=1

  printf '%s[?2026h%s[H%s[?25l' "$ESC" "$ESC" "$ESC"
  {
    printf '\n\n'
    printf '%s\n' "$body"
    printf '%*s' "$pad" '' | tr ' ' '\n'
    printf '%s\n' "$footer"
  } | awk -v e="$ESC" '{ printf "%s%s[K\n", $0, e }'
  printf '%s[J%s[?2026l' "$ESC" "$ESC"
}

while true; do
  draw
  key=""
  read -rsn1 -t 3 key 2>/dev/null
  case "$key" in
    a) armed || bash "$WTS" arm "$MIN" "$ACT" >/dev/null 2>&1 ;;
    c) bash "$WTS" disarm >/dev/null 2>&1 ;;
    +|=) MIN=$(( MIN + 5 )); apply ;;
    -|_) [ "$MIN" -gt 5 ] && MIN=$(( MIN - 5 )); apply ;;
    q) bash "$WTS" disarm >/dev/null 2>&1; break ;;
    x) break ;;
  esac
done

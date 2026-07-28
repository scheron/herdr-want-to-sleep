#!/usr/bin/env bash
# Plugin actions for scheron.want-to-sleep.
#
# The herdr server runs these without a TTY, so nothing here may expect a
# terminal: results go back as notifications, and stdout survives only in
# `herdr plugin log`.
set -uo pipefail

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
WTS="$(cd "$(dirname "$0")" && pwd)/wts.sh"

toast() {
  "$HERDR_BIN" notification show "$1" --body "$2" --sound "${3:-none}" >/dev/null 2>&1 || true
}

[ -r "$WTS" ] || { toast "want-to-sleep" "wts.sh is missing from the plugin root" request; exit 1; }

summary() {
  "$HERDR_BIN" agent list 2>/dev/null | jq -r '
    (.result.agents // []) as $a
    | "\([$a[]|select(.agent_status=="working")]|length) working · " +
      "\([$a[]|select(.agent_status=="blocked")]|length) blocked · " +
      "\([$a[]|select(.agent_status=="idle" or .agent_status=="done")]|length) settled"' 2>/dev/null \
    || printf 'agent states unavailable'
}

action="${1:-toggle}"
out="$(bash "$WTS" "$action" 2>&1)"
rc=$?

if [ "$rc" -ne 0 ]; then
  toast "want-to-sleep failed" "${out:-exit ${rc}}" request
  exit "$rc"
fi

case "$out" in
  armed*)     toast "Sleep armed" "$(summary). Sleeping once none is working." ;;
  disarmed*)  toast "Sleep cancelled" "The Mac will stay awake." ;;
  *)          toast "want-to-sleep" "$(summary)" ;;
esac

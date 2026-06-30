#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CONFIG:-$SCRIPT_DIR/config}"
if [[ ! -f "$CONFIG" ]]; then
  echo "obsidian-notify: missing config file: $CONFIG" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG"

[[ -f "$TASKS_FILE" ]] || exit 0

# Wake Obsidian so Obsidian Sync has time to pull latest changes before we read.
open "obsidian://open?vault=${VAULT_NAME}" 2>/dev/null || true
sleep 30

case "${1:-}" in
  morning) PERIOD="morning" ;;
  evening) PERIOD="evening" ;;
  *)
    if [[ $(date +%H) -lt 12 ]]; then
      PERIOD="morning"
    else
      PERIOD="evening"
    fi
    ;;
esac

TODAY=$(date +%Y-%m-%d)

ALL_TODAY=$(grep -e "- \[ \].*🛫 $TODAY" "$TASKS_FILE" 2>/dev/null || true)

if [[ "$PERIOD" == "morning" ]]; then
  TITLE="Morning household chores"
  MATCHES=$(grep "#morning" <<< "$ALL_TODAY" || true)
else
  TITLE="Evening household chores"
  MATCHES=$(grep -v "#morning" <<< "$ALL_TODAY" || true)
fi

[[ -z "$MATCHES" ]] && exit 0

# Strip Tasks plugin metadata, leaving plain task name.
# Process in two passes: first remove the recurrence field (🔁 ... takes
# everything to end of line, so do it before the individual date fields),
# then strip any remaining date/flag metadata for non-recurring tasks.
TASK_LIST=$(
  echo "$MATCHES" \
  | sed \
      -e 's/^- \[ \] //' \
      -e 's/ 🔁 .*//' \
  | sed -E \
      -e 's/ ➕ [0-9]{4}-[0-9]{2}-[0-9]{2}//' \
      -e 's/ 🛫 [0-9]{4}-[0-9]{2}-[0-9]{2}//' \
      -e 's/ 📅 [0-9]{4}-[0-9]{2}-[0-9]{2}//' \
      -e 's/ ✅ [0-9]{4}-[0-9]{2}-[0-9]{2}//' \
      -e 's/ 🏁 delete//' \
      -e 's/ #morning//' \
  | sed 's/[[:space:]]*$//'
)

curl -s --fail \
  -H "Title: $TITLE" \
  -H "Click: $CLICK_URL" \
  -H "Priority: default" \
  -d "$TASK_LIST" \
  "$NTFY_URL/$NTFY_TOPIC"

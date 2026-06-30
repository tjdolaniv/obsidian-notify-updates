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

STATE_FILE="${STATE_FILE:-$(dirname "$CONFIG")/seen_files.txt}"

extract_summary() {
  awk '
    /^> \[!summary\]/ { in_callout=1; next }
    in_callout && /^> /  { sub(/^> /, ""); print; next }
    in_callout           { exit }
  ' "$1"
}

url_encode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# Build sorted list of current .md files across all watched folders
CURRENT_FILES=$(
  read -ra folders <<< "$WATCH_FOLDERS"
  for folder in "${folders[@]}"; do
    dir_path="$VAULT_PATH/$folder"
    [[ -d "$dir_path" ]] && find "$dir_path" -name "*.md" -type f
  done | sort
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Initialization run: record current state without notifying
if [[ ! -f "$STATE_FILE" ]]; then
  log "init: seeding state with $(echo "$CURRENT_FILES" | grep -c . || true) file(s) in $WATCH_FOLDERS"
  echo "$CURRENT_FILES" > "$STATE_FILE"
  exit 0
fi

[[ -z "$CURRENT_FILES" ]] && exit 0

# Find files present now but not in the previous state
NEW_FILES=$(comm -23 <(echo "$CURRENT_FILES") <(sort "$STATE_FILE"))

NEW_COUNT=$(echo "$NEW_FILES" | grep -c . || true)
log "poll: $NEW_COUNT new file(s) in $WATCH_FOLDERS"

# Send a notification for each new file
while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  filename=$(basename "$file" .md)
  rel_path="${file#"$VAULT_PATH/"}"
  rel_path="${rel_path%.md}"

  encoded=$(url_encode "$rel_path")
  click_url="obsidian://open?vault=${VAULT_NAME}&file=${encoded}"

  summary=$(extract_summary "$file")
  body="${summary:-$rel_path}"

  log "notifying: $rel_path"
  curl -s --fail \
    -H "Title: New note: $filename" \
    -H "Click: $click_url" \
    -H "Priority: default" \
    -d "$body" \
    "$NTFY_URL/$NTFY_TOPIC"
done <<< "$NEW_FILES"

# Persist updated state
echo "$CURRENT_FILES" > "$STATE_FILE"

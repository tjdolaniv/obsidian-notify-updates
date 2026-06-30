#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_SCRIPT="$SCRIPT_DIR/watch_folders.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

VAULT="$WORK/vault"
CONFIG_FILE="$WORK/config"
STATE="$WORK/seen_files.txt"
CURL_LOG="$WORK/curl.log"
STUB_BIN="$WORK/bin"

mkdir -p "$VAULT/Projects" "$VAULT/Areas" "$VAULT/Ignored" "$STUB_BIN"

cat > "$STUB_BIN/curl" << 'STUB'
#!/usr/bin/env bash
echo "CURL: $*" >> "$TEST_CURL_LOG"
while [[ $# -gt 0 ]]; do
  [[ "$1" == "-d" ]] && { echo "BODY: $2" >> "$TEST_CURL_LOG"; break; }
  shift
done
exit 0
STUB
chmod +x "$STUB_BIN/curl"

cat > "$CONFIG_FILE" << EOF
VAULT_PATH="$VAULT"
VAULT_NAME="TestVault"
WATCH_FOLDERS="Projects Areas"
NTFY_TOPIC="test-topic"
NTFY_URL="https://ntfy.sh"
EOF

run_script() {
  TEST_CURL_LOG="$CURL_LOG" \
  CONFIG="$CONFIG_FILE" \
  STATE_FILE="$STATE" \
  PATH="$STUB_BIN:$PATH" \
  bash "$WATCH_SCRIPT"
}

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"
    (( ++pass ))
  else
    echo "FAIL: $desc"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
    (( ++fail ))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qF "$needle" <<< "$haystack" 2>/dev/null; then
    echo "PASS: $desc"
    (( ++pass ))
  else
    echo "FAIL: $desc — '$needle' not found"
    echo "  haystack: $haystack"
    (( ++fail ))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! grep -qF "$needle" <<< "$haystack" 2>/dev/null; then
    echo "PASS: $desc"
    (( ++pass ))
  else
    echo "FAIL: $desc — '$needle' unexpectedly found"
    (( ++fail ))
  fi
}

curl_log() { cat "$CURL_LOG" 2>/dev/null || true; }
reset_curl() { rm -f "$CURL_LOG"; }

# ── Test 1: Init run ──────────────────────────────────────────────────────────
echo "--- Test 1: init run"
rm -f "$STATE"
reset_curl
touch "$VAULT/Projects/Existing Note.md"

run_script

assert_eq   "init: state file created"        "true" "$([[ -f "$STATE" ]] && echo true || echo false)"
assert_eq   "init: no curl calls"             ""     "$(curl_log)"
assert_contains "init: existing file in state" "$VAULT/Projects/Existing Note.md" "$(cat "$STATE")"

# ── Test 2: No new files ──────────────────────────────────────────────────────
echo "--- Test 2: no new files"
reset_curl
run_script
assert_eq "no-new: no curl calls" "" "$(curl_log)"

# ── Test 3: New file detected ─────────────────────────────────────────────────
echo "--- Test 3: new file detected"
reset_curl
touch "$VAULT/Projects/New Note.md"

run_script

LOG=$(curl_log)
assert_contains "new-file: curl called"             "CURL:"                      "$LOG"
assert_contains "new-file: correct title header"    "Title: New note: New Note"  "$LOG"
assert_contains "new-file: vault name in click url" "TestVault"                  "$LOG"
assert_contains "new-file: spaces url-encoded"      "New%20Note"                 "$LOG"
assert_contains "new-file: slash url-encoded"       "Projects%2F"                "$LOG"
assert_not_contains "new-file: no re-notification for existing" "Existing Note"  "$LOG"

# ── Test 4: File in unwatched folder ──────────────────────────────────────────
echo "--- Test 4: file in unwatched folder"
reset_curl
touch "$VAULT/Ignored/Should Not Notify.md"

run_script

assert_eq "unwatched: no curl calls" "" "$(curl_log)"

# ── Test 5: Multiple new files ────────────────────────────────────────────────
echo "--- Test 5: multiple new files"
reset_curl
touch "$VAULT/Projects/Alpha.md"
touch "$VAULT/Areas/Beta.md"

run_script

LOG=$(curl_log)
CURL_COUNT=$(grep -c "^CURL:" <<< "$LOG" || true)
assert_eq "multi: two curl calls" "2" "$CURL_COUNT"

# ── Test 6: Summary present ───────────────────────────────────────────────────
echo "--- Test 6: summary present"
reset_curl
cat > "$VAULT/Projects/Summary Note.md" << 'EOF'
> [!summary]
> This is the summary text

# Title

Body content here.
EOF

run_script

LOG=$(curl_log)
assert_contains "summary: body is summary text"          "BODY: This is the summary text" "$LOG"
assert_not_contains "summary: rel path not used as body" "BODY: Projects/Summary Note"    "$LOG"

# ── Test 7: No summary ────────────────────────────────────────────────────────
echo "--- Test 7: no summary callout"
reset_curl
cat > "$VAULT/Areas/No Summary Note.md" << 'EOF'
# Just a title

Some content with no summary callout.
EOF

run_script

LOG=$(curl_log)
assert_contains "no-summary: body is relative path" "BODY: Areas/No Summary Note" "$LOG"

# ── Report ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]

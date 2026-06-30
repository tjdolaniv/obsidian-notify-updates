# Obsidian Notifications

Two complementary services that send push notifications via [ntfy.sh](https://ntfy.sh):

- **`check_tasks.sh`** — checks an Obsidian file for incomplete tasks due today, runs twice daily
- **`watch_folders.sh`** — watches configured vault folders and fires a notification whenever a new note is created, polls every 5 minutes

## Requirements

- macOS (uses `grep`, `sed`, `awk`, `curl`, `python3` — all default)
- [ntfy](https://ntfy.sh) app on iOS/Android, subscribed to your topic
- Obsidian desktop app with Obsidian Sync

## Install

### 1. Clone and configure

```bash
git clone https://github.com/you/obsidian-notify-updates
cd obsidian-notify-updates
cp config.example config
```

Edit `config` with your values:

```bash
VAULT_PATH="$HOME/Obsidian/MyVault"
VAULT_NAME="MyVault"
WATCH_FOLDERS="Projects Areas Daily/Digest"   # space-separated, relative to VAULT_PATH
TASKS_FILE="$VAULT_PATH/Household/Recurring Household Chores.md"
CLICK_URL="obsidian://open?vault=MyVault&file=path%2Fto%2Fdashboard"
NTFY_TOPIC="your-obscure-topic-name"          # acts as a password — keep it random
NTFY_URL="https://ntfy.sh"
```

### 2. Install the launch agents

The plist templates use `YOUR_REPO_PATH` as a placeholder:

```bash
REPO="$(pwd)"

sed "s|YOUR_REPO_PATH|$REPO|g" com.obsidian-notify.check-tasks.plist \
  > ~/Library/LaunchAgents/com.obsidian-notify.check-tasks.plist

sed "s|YOUR_REPO_PATH|$REPO|g" com.obsidian-notify.watch-folders.plist \
  > ~/Library/LaunchAgents/com.obsidian-notify.watch-folders.plist

launchctl load ~/Library/LaunchAgents/com.obsidian-notify.check-tasks.plist
launchctl load ~/Library/LaunchAgents/com.obsidian-notify.watch-folders.plist
```

`check_tasks.sh` runs at **7:20am, 7:30pm, and 9pm**. Edit the `Hour`/`Minute` values in the plist before installing to change the schedule.

`watch_folders.sh` polls every **5 minutes**. Edit `StartInterval` in the plist to adjust.

### 3. Grant Full Disk Access (macOS)

macOS blocks launch agents from reading files in iCloud Drive or `~/Documents` by default. Open **System Settings → Privacy & Security → Full Disk Access** and add `/bin/bash`.

### 4. Seed the folder watcher state

Run the watcher once manually to record existing notes as already-seen (so you don't get notified for every file in the folder on first run):

```bash
bash watch_folders.sh
```

This creates `seen_files.txt` in the repo directory and exits without sending any notifications.

---

## check_tasks.sh

Reads a single markdown file managed by the [Obsidian Tasks plugin](https://obsidian-tasks-group.github.io/Obsidian-Tasks-User-Docs/) and notifies you of incomplete tasks scheduled for today.

### How it works

Looks for lines that are incomplete (`- [ ]`) and scheduled for today (`🛫 YYYY-MM-DD`). Task names are stripped of all Tasks plugin metadata before sending.

Before reading the file, the script opens the vault via the Obsidian URI scheme to wake Obsidian and give Sync 30 seconds to pull the latest changes.

### Task file format

```markdown
- [ ] Kiddo meds 🔁 every day 🏁 delete ➕ 2026-04-26 🛫 2026-04-27
- [x] Charge watch 🔁 every day 🏁 delete ➕ 2026-04-26 🛫 2026-04-27
```

Completed tasks (`- [x]`) and tasks without today's date are excluded.

### Notification format

**Title:** `Morning household chores` or `Evening household chores`

**Body:** Plain task names, one per line

**Tap action:** Opens Obsidian to `CLICK_URL`

### Testing

```bash
bash check_tasks.sh morning
```

To force a notification when no tasks are due today:

```bash
TODAY=2026-04-27 bash check_tasks.sh morning
```

---

## watch_folders.sh

Polls configured vault folders for new `.md` files and fires a notification for each one found.

### How it works

On each run, `find` builds a sorted list of `.md` files across all `WATCH_FOLDERS`. This is compared against `seen_files.txt` (written to the repo directory). New files trigger a notification; the state file is then updated.

The first run (when no state file exists) seeds `seen_files.txt` with the current file list and exits silently — no notifications for pre-existing notes.

### Summary callout

If a new note contains a `> [!summary]` callout, its content becomes the notification body:

```markdown
> [!summary]
> Brief description of what this note covers.

# Note title
...
```

Without a summary callout, the body shows the note's path relative to the vault root.

### Notification format

**Title:** `New note: <filename>`

**Body:** Summary callout content, or relative path if none

**Tap action:** Opens Obsidian directly to the new note

---

## launchctl reference

```bash
# Check status
launchctl list | grep obsidian-notify

# Trigger immediately (for testing)
launchctl start com.obsidian-notify.check-tasks
launchctl start com.obsidian-notify.watch-folders

# Unload (disable)
launchctl unload ~/Library/LaunchAgents/com.obsidian-notify.check-tasks.plist
launchctl unload ~/Library/LaunchAgents/com.obsidian-notify.watch-folders.plist

# Reload after editing a plist
launchctl unload ~/Library/LaunchAgents/com.obsidian-notify.watch-folders.plist
launchctl load ~/Library/LaunchAgents/com.obsidian-notify.watch-folders.plist
```

## Files

```
obsidian-notify-updates/
  config                                    # Edit this with your settings (not committed)
  config.example                            # Template
  check_tasks.sh
  watch_folders.sh
  com.obsidian-notify.check-tasks.plist
  com.obsidian-notify.watch-folders.plist
  seen_files.txt                            # Created on first watcher run (not committed)
  notify.log                                # Created by launchd (not committed)
  tests/
    test_watch_folders.sh

~/Library/LaunchAgents/
  com.obsidian-notify.check-tasks.plist
  com.obsidian-notify.watch-folders.plist
```

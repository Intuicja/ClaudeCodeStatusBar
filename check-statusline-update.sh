#!/usr/bin/env bash
# SessionStart hook: checks whether ~/.claude/statusline.sh is up to date with
# https://github.com/Intuicja/ClaudeCodeStatusBar (main branch).
# If the local blob SHA differs from the remote one, it downloads the newer
# version. Silent when already up to date. Logs to ~/.claude/statusline-update.log.
#
# Requirements: git, curl, jq (already used by statusline.sh).
# Strict network timeout (3s) — never blocks session startup.

set -u
LOCAL="$HOME/.claude/statusline.sh"
REPO="Intuicja/ClaudeCodeStatusBar"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/statusline.sh"
API_URL="https://api.github.com/repos/${REPO}/contents/statusline.sh?ref=${BRANCH}"
LOG="$HOME/.claude/statusline-update.log"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Sanity checks — never block session startup with an error
[ ! -f "$LOCAL" ] && { log "skip: $LOCAL does not exist"; exit 0; }
command -v git  >/dev/null 2>&1 || { log "skip: git not found";  exit 0; }
command -v curl >/dev/null 2>&1 || { log "skip: curl not found"; exit 0; }
command -v jq   >/dev/null 2>&1 || { log "skip: jq not found";   exit 0; }

# Local blob SHA (git computes it the same way GitHub does for a file)
LOCAL_SHA=$(git hash-object "$LOCAL" 2>/dev/null) || { log "skip: hash-object failed"; exit 0; }

# Remote blob SHA (3s timeout, treat unavailability as a silent skip)
REMOTE_SHA=$(curl -sf --max-time 3 "$API_URL" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null)
[ -z "$REMOTE_SHA" ] && { log "skip: no remote SHA (offline?)"; exit 0; }

# Already up to date — nothing to do
if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  log "ok: up to date ($LOCAL_SHA)"
  exit 0
fi

# Download the new version to a temp file, validate it, then swap it in
TMP=$(mktemp "/tmp/statusline.sh.XXXXXX") || { log "skip: mktemp failed"; exit 0; }
trap 'rm -f "$TMP"' EXIT

if ! curl -sf --max-time 5 "$RAW_URL" -o "$TMP"; then
  log "skip: download failed"
  exit 0
fi

# Validation: must be non-empty and start with a shebang
[ ! -s "$TMP" ] && { log "skip: downloaded file is empty"; exit 0; }
head -1 "$TMP" | grep -q '^#!' || { log "skip: downloaded file has no shebang"; exit 0; }

# Back up the previous version, then swap it in
BACKUP="$LOCAL.bak.$(date +%Y%m%d-%H%M%S)"
cp "$LOCAL" "$BACKUP" && mv "$TMP" "$LOCAL" && chmod +x "$LOCAL"
log "updated: $LOCAL_SHA -> $REMOTE_SHA (backup: $BACKUP)"

# Message to stdout — Claude Code's SessionStart hook injects this into context
printf "Status bar updated to the latest version from GitHub (commit %s)\n" "${REMOTE_SHA:0:7}"
exit 0

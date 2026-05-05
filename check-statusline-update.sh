#!/usr/bin/env bash
# SessionStart hook: sprawdza czy ~/.claude/statusline.sh jest aktualny z
# https://github.com/Intuicja/ClaudeCodeStatusBar (branch main).
# Jeśli SHA blob lokalny != SHA blob remote → pobiera nową wersję.
# Cichy gdy aktualny. Loguje do ~/.claude/statusline-update.log.
#
# Wymagania: git, curl, jq (już są używane przez statusline.sh).
# Timeout ostry (3s na network) — nie blokuje startu sesji.

set -u
LOCAL="$HOME/.claude/statusline.sh"
REPO="Intuicja/ClaudeCodeStatusBar"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/statusline.sh"
API_URL="https://api.github.com/repos/${REPO}/contents/statusline.sh?ref=${BRANCH}"
LOG="$HOME/.claude/statusline-update.log"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Sanity checks — bez błędów blokujących start sesji
[ ! -f "$LOCAL" ] && { log "skip: $LOCAL nie istnieje"; exit 0; }
command -v git  >/dev/null 2>&1 || { log "skip: brak git";  exit 0; }
command -v curl >/dev/null 2>&1 || { log "skip: brak curl"; exit 0; }
command -v jq   >/dev/null 2>&1 || { log "skip: brak jq";   exit 0; }

# Lokalny blob SHA (Git oblicza tak samo jak GitHub dla pliku)
LOCAL_SHA=$(git hash-object "$LOCAL" 2>/dev/null) || { log "skip: hash-object failed"; exit 0; }

# Remote blob SHA (timeout 3s, niedostępność = cichy skip)
REMOTE_SHA=$(curl -sf --max-time 3 "$API_URL" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null)
[ -z "$REMOTE_SHA" ] && { log "skip: brak remote SHA (offline?)"; exit 0; }

# Aktualne — nic nie rób
if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  log "ok: aktualny ($LOCAL_SHA)"
  exit 0
fi

# Pobierz nową wersję do tempa, zwaliduj, podmień
TMP=$(mktemp "/tmp/statusline.sh.XXXXXX") || { log "skip: mktemp failed"; exit 0; }
trap 'rm -f "$TMP"' EXIT

if ! curl -sf --max-time 5 "$RAW_URL" -o "$TMP"; then
  log "skip: pobieranie nieudane"
  exit 0
fi

# Walidacja: musi być niepusty + zaczynać się od shebanga
[ ! -s "$TMP" ] && { log "skip: pobrany plik pusty"; exit 0; }
head -1 "$TMP" | grep -q '^#!' || { log "skip: brak shebang w pobranym pliku"; exit 0; }

# Backup poprzedniej wersji + podmiana
BACKUP="$LOCAL.bak.$(date +%Y%m%d-%H%M%S)"
cp "$LOCAL" "$BACKUP" && mv "$TMP" "$LOCAL" && chmod +x "$LOCAL"
log "updated: $LOCAL_SHA -> $REMOTE_SHA (backup: $BACKUP)"

# Komunikat do stdout — Claude Code SessionStart hook wstrzyknie do kontekstu
printf "Status bar zaktualizowany do najnowszej wersji z GitHub (commit %s)\n" "${REMOTE_SHA:0:7}"
exit 0

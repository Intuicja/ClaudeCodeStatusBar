#!/usr/bin/env bash
export LC_ALL=C
export LANG=C

INPUT=$(cat)

# ─── Debug: zapisz ostatni JSON stdin do podglądu ───────────────
# Odkomentuj gdy chcesz zobaczyć co Claude Code przekazuje:
# printf "%s" "$INPUT" > /tmp/.cc_statusline_stdin.json

# ─── Konfiguracja ───────────────────────────────────────────────
# UWAGA: Od Claude Code 2.x limity 5h/7d są po stronie serwera.
# Skrypt pobiera je z oficjalnego endpointu OAuth (jak Claude Code).
# Fallback na ccusage gdy endpoint nieosiągalny.
CC_USAGE_ENDPOINT="https://api.anthropic.com/api/oauth/usage"
CC_KEYCHAIN_SERVICE="Claude Code-credentials"
CC_USER_AGENT="claude-code/2.0.32"

# ─── Kolory ──────────────────────────────────────────────────────
R="\033[0m"
C_SEC="\033[38;5;37m"
C_LBL="\033[38;5;242m"
C_VAL="\033[38;5;252m"
C_MODEL="\033[38;5;114m"
C_DIR="\033[38;5;228m"
C_THINK="\033[38;5;183m"
C_DIM="\033[38;5;240m"
C_SEP="\033[38;5;240m"
C_WEATHER="\033[38;5;117m"

SEP=" ${C_SEP}│${R} "

# ─── Helpers ─────────────────────────────────────────────────────
pct_color() {
  local p=${1:-0}
  if   [ "$p" -lt 50 ]; then printf "\033[38;5;78m"
  elif [ "$p" -lt 75 ]; then printf "\033[38;5;221m"
  elif [ "$p" -lt 90 ]; then printf "\033[38;5;209m"
  else                        printf "\033[38;5;203m"
  fi
}

sys_color() {
  local val=$1 warn=$2 crit=$3
  if   [ "$val" -le "$crit" ]; then printf "\033[38;5;203m"
  elif [ "$val" -le "$warn" ]; then printf "\033[38;5;221m"
  else                               printf "\033[38;5;78m"
  fi
}

dotbar() {
  local pct=${1:-0} filled bar=""
  filled=$(( pct * 10 / 100 ))
  local color
  color=$(pct_color "$pct")
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ "$i" -le "$filled" ]; then bar="${bar}${color}▮${R}"
    else                            bar="${bar}${C_DIM}▯${R}"
    fi
  done
  printf "%b" "$bar"
}

print_lr() {
  local left="$1" right="$2"
  local tw=${COLUMNS:-$(tput cols 2>/dev/null || echo 200)}
  local ll rl pad
  ll=$(printf "%b" "$left"  | sed $'s/\x1b\[[0-9;]*m//g' | awk '{print length}')
  rl=$(printf "%b" "$right" | sed $'s/\x1b\[[0-9;]*m//g' | awk '{print length}')
  pad=$(( tw - ll - rl - 1 ))
  [ "$pad" -lt 1 ] && pad=1
  printf "%b%*s%b\n" "$left" "$pad" "" "$right"
}

# ─── Dane z JSON (kontekst sesji) ────────────────────────────────
MODEL=$(echo "$INPUT"       | jq -r '.model.display_name // "unknown"' 2>/dev/null)

# Procent pozostały kontekstu — nowe Claude Code wystawia gotowe pole.
# Fallback: licz z input+output / window_size (stary format).
CTX_REMAIN=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)
if [ -n "$CTX_REMAIN" ] && [ "$CTX_REMAIN" != "null" ]; then
  CTX_PCT=$(awk -v r="$CTX_REMAIN" 'BEGIN{printf "%d", 100 - r}')
else
  INPUT_TOK=$(echo "$INPUT"   | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
  OUTPUT_TOK=$(echo "$INPUT"  | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
  CTX_SIZE=$(echo "$INPUT"    | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
  INPUT_TOK=${INPUT_TOK:-0}; OUTPUT_TOK=${OUTPUT_TOK:-0}; CTX_SIZE=${CTX_SIZE:-200000}
  TOTAL_TOK=$(( INPUT_TOK + OUTPUT_TOK ))
  CTX_PCT=0
  [ "$CTX_SIZE" -gt 0 ] && CTX_PCT=$(( TOTAL_TOK * 100 / CTX_SIZE ))
fi
[ "$CTX_PCT" -lt 0 ] && CTX_PCT=0
[ "$CTX_PCT" -gt 100 ] && CTX_PCT=100

# ─── Limity planu Pro/Max z OAuth endpoint (cache 5min) ─────────
# Endpoint zwraca 5h i 7d utilization (jak w /status).
# Token OAuth siedzi w Keychain jako "Claude Code-credentials".
get_usage_limits() {
  local cache="/tmp/.cc_usage_limits" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 300 ] && cat "$cache" && return
  fi

  # Pobierz token z Keychain
  local creds token
  creds=$(security find-generic-password -s "$CC_KEYCHAIN_SERVICE" -w 2>/dev/null)
  if [ -z "$creds" ]; then
    printf "|||||" | tee "$cache"; return
  fi
  token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [ -z "$token" ] && { printf "|||||" | tee "$cache"; return; }

  # Zapytaj endpoint (max 3s)
  local resp
  resp=$(curl -sf --max-time 3 "$CC_USAGE_ENDPOINT" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: $CC_USER_AGENT" 2>/dev/null)
  [ -z "$resp" ] && { printf "|||||" | tee "$cache"; return; }

  local five_util five_reset seven_util seven_reset opus_util opus_reset
  five_util=$(echo "$resp"  | jq -r '.five_hour.utilization // 0' 2>/dev/null)
  five_reset=$(echo "$resp" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  seven_util=$(echo "$resp" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
  seven_reset=$(echo "$resp"| jq -r '.seven_day.resets_at // empty' 2>/dev/null)
  opus_util=$(echo "$resp"  | jq -r '.seven_day_opus.utilization // 0' 2>/dev/null)
  opus_reset=$(echo "$resp" | jq -r '.seven_day_opus.resets_at // empty' 2>/dev/null)

  # Zamień ISO timestamps na "XhYm do resetu"
  to_remaining() {
    local iso="$1" epoch diff h m
    [ -z "$iso" ] || [ "$iso" = "null" ] && return
    epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${iso%.*}" "+%s" 2>/dev/null || \
            date -jf "%Y-%m-%dT%H:%M:%SZ" "${iso%.*}Z" "+%s" 2>/dev/null || echo 0)
    diff=$(( epoch - $(date +%s) ))
    [ "$diff" -le 0 ] && return
    h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
    if [ "$h" -ge 24 ]; then
      printf "%dd%dh" $(( h / 24 )) $(( h % 24 ))
    elif [ "$h" -gt 0 ]; then
      printf "%dh%dm" "$h" "$m"
    else
      printf "%dm" "$m"
    fi
  }
  local five_left seven_left opus_left
  five_left=$(to_remaining "$five_reset")
  seven_left=$(to_remaining "$seven_reset")
  opus_left=$(to_remaining "$opus_reset")

  # Zaokrąglij procenty do int
  five_util=$(awk -v v="$five_util"  'BEGIN{printf "%d", v+0.5}')
  seven_util=$(awk -v v="$seven_util" 'BEGIN{printf "%d", v+0.5}')
  opus_util=$(awk -v v="$opus_util"  'BEGIN{printf "%d", v+0.5}')

  printf "%s|%s|%s|%s|%s|%s" \
    "${five_util:-0}" "${five_left:-}" \
    "${seven_util:-0}" "${seven_left:-}" \
    "${opus_util:-0}" "${opus_left:-}" | tee "$cache"
}

LIMITS=$(get_usage_limits)
FIVE_PCT=$(echo  "$LIMITS" | cut -d'|' -f1)
FIVE_LEFT=$(echo "$LIMITS" | cut -d'|' -f2)
SEVEN_PCT=$(echo "$LIMITS" | cut -d'|' -f3)
SEVEN_LEFT=$(echo "$LIMITS"| cut -d'|' -f4)
OPUS_PCT=$(echo  "$LIMITS" | cut -d'|' -f5)
OPUS_LEFT=$(echo "$LIMITS" | cut -d'|' -f6)
FIVE_PCT=${FIVE_PCT:-0}; SEVEN_PCT=${SEVEN_PCT:-0}; OPUS_PCT=${OPUS_PCT:-0}

# ─── CPU (cache 60s, top jest wolny) ────────────────────────────
get_cpu() {
  local cache="/tmp/.cc_cpu_cache" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && cat "$cache" && return
  fi
  local idle cpu
  idle=$(top -l 1 -n 0 2>/dev/null | awk '/CPU usage/{gsub(/%/,"",$7);printf "%d",$7}')
  cpu=$(( 100 - ${idle:-0} ))
  printf "%s" "$cpu" | tee "$cache"
}
CPU_PCT=$(get_cpu)
CPU_COL="\033[38;5;78m"
[ -n "$CPU_PCT" ] && {
  if   [ "$CPU_PCT" -ge 80 ]; then CPU_COL="\033[38;5;203m"
  elif [ "$CPU_PCT" -ge 50 ]; then CPU_COL="\033[38;5;221m"
  fi
}

# ─── Dysk (cache 10min) ──────────────────────────────────────────
get_disk() {
  local cache="/tmp/.cc_disk_cache" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 600 ] && cat "$cache" && return
  fi
  df -g / 2>/dev/null | awk 'NR==2{print $4}' | tee "$cache"
}
DISK_FREE=$(get_disk)
DISK_COL=$(sys_color "${DISK_FREE:-999}" 20 5)

# ─── RAM (cache 60s) ────────────────────────────────────────────
get_ram() {
  local cache="/tmp/.cc_ram_cache" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && cat "$cache" && return
  fi
  if command -v vm_stat &>/dev/null; then
    local PF PI PS FB
    PF=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,"",$3);print $3}')
    PI=$(vm_stat 2>/dev/null | awk '/Pages inactive/{gsub(/\./,"",$3);print $3}')
    PS=$(pagesize 2>/dev/null || echo 4096)
    PF=${PF:-0}; PI=${PI:-0}
    awk -v b="$(( (PF + PI) * PS ))" 'BEGIN{printf "%.1f", b/1073741824}' | tee "$cache"
  fi
}
RAM_FREE=$(get_ram)

# ─── Bateria (cache 60s) ────────────────────────────────────────
get_bat() {
  local cache="/tmp/.cc_bat_cache" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && cat "$cache" && return
  fi
  if command -v pmset &>/dev/null; then
    local info pct is_ac seg=""
    info=$(pmset -g batt 2>/dev/null)
    pct=$(echo "$info" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    is_ac=$(echo "$info" | grep -c 'AC Power')
    if [ -n "$pct" ]; then
      if [ "$is_ac" -eq 0 ]; then
        local col
        col=$(sys_color "$pct" 50 20)
        seg="🔋 ${col}${pct}%${R}"
      else
        seg="⚡ \033[38;5;78m${pct}%${R}"
      fi
    fi
    printf "%s" "$seg" | tee "$cache"
  fi
}
BAT_SEG=$(get_bat)

# ─── Pogoda (cache 10min) ───────────────────────────────────────
get_weather() {
  local cache="/tmp/.cc_weather" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 600 ] && cat "$cache" && return
  fi
  local loc lat lon wx temp wcode icon
  local locstr
  locstr=$(curl -sf --max-time 3 "https://ipinfo.io/loc" 2>/dev/null)
  lat=$(echo "$locstr" | cut -d',' -f1)
  lon=$(echo "$locstr" | cut -d',' -f2)
  [ -z "$lat" ] && printf "" | tee "$cache" && return
  wx=$(curl -sf --max-time 3 \
    "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weathercode" \
    2>/dev/null)
  temp=$(echo "$wx"  | jq -r '.current.temperature_2m // empty' 2>/dev/null)
  wcode=$(echo "$wx" | jq -r '.current.weathercode // empty'    2>/dev/null)
  [ -z "$temp" ] && printf "" | tee "$cache" && return
  case "$wcode" in
    0)           icon="☀" ;;
    1|2)         icon="⛅";;
    3)           icon="☁" ;;
    45|48)       icon="🌫";;
    51|53|55)    icon="🌦";;
    61|63|65)    icon="🌧";;
    71|73|75|77) icon="❄" ;;
    80|81|82)    icon="🌦";;
    95|96|99)    icon="⛈";;
    *)           icon="?" ;;
  esac
  printf "%s %.0f°C" "$icon" "$temp" | tee "$cache"
}
WEATHER=$(get_weather)

# ─── Skrócony path ───────────────────────────────────────────────
SHORT_DIR=$(pwd | sed "s|$HOME|~|" | awk -F'/' '{
  n=NF; if(n<=3){print $0} else {
    out="~/"; for(i=2;i<n;i++) out=out substr($i,1,1) "/"; print out $NF
  }
}')

# ═══ LINIA 1: AI — kontekst + limity 5h / 7d / Opus ═════════════
CTX_C=$(pct_color "$CTX_PCT")
CTX_BAR=$(dotbar "$CTX_PCT")
L1="${C_MODEL}${MODEL}${R}"
L1="${L1}${SEP}🧩 ${C_LBL}CTX:${R} ${CTX_BAR} ${CTX_C}${CTX_PCT}%${R}"

# 5h block (aktualne okno rozliczeniowe)
FIVE_C=$(pct_color "$FIVE_PCT")
FIVE_BAR=$(dotbar "$FIVE_PCT")
L1="${L1}${SEP}💎 ${FIVE_BAR} ${FIVE_C}${FIVE_PCT}%${R}"
[ -n "$FIVE_LEFT" ] && L1="${L1} ${C_DIM}(${C_VAL}${FIVE_LEFT}${C_DIM})${R}"

# 7d total
SEVEN_C=$(pct_color "$SEVEN_PCT")
L1="${L1}${SEP}📆 ${C_LBL}7d:${R} ${SEVEN_C}${SEVEN_PCT}%${R}"
[ -n "$SEVEN_LEFT" ] && L1="${L1} ${C_DIM}(${C_VAL}${SEVEN_LEFT}${C_DIM})${R}"

# 7d Opus (osobny licznik na Max plan)
if [ "$OPUS_PCT" -gt 0 ] || [ -n "$OPUS_LEFT" ]; then
  OPUS_C=$(pct_color "$OPUS_PCT")
  L1="${L1}${SEP}🧠 ${C_LBL}Opus:${R} ${OPUS_C}${OPUS_PCT}%${R}"
fi

R1=""

# ═══ LINIA 2: Środowisko — katalog + system + pogoda ════════════
L2="🕐 ${C_VAL}$(date '+%H:%M')${R}"
L2="${L2}${SEP}📁 ${C_DIR}${SHORT_DIR}${R}"
[ -n "$DISK_FREE" ]   && L2="${L2}${SEP}💾 ${DISK_COL}${DISK_FREE}GB${R}"
[ -n "$RAM_FREE" ]     && L2="${L2}${SEP}🧠 \033[38;5;78m${RAM_FREE}GB${R}"
[ -n "$CPU_PCT" ]      && L2="${L2}${SEP}⚙ ${CPU_COL}${CPU_PCT}%${R}"
[ -n "$BAT_SEG" ]      && L2="${L2}${SEP}${BAT_SEG}"

R2=""
[ -n "$WEATHER" ] && R2="${C_WEATHER}${WEATHER}${R}"

print_lr "$L1" "$R1"
print_lr "$L2" "$R2"

#!/usr/bin/env bash
export LC_ALL=C
export LANG=C

INPUT=$(cat)

# ─── Konfiguracja (dostosuj do swojego planu) ───────────────────
BLOCK_LIMIT_5H=15000000   # Max 5 ≈ 15M tokenów / 5h (zmień jak poznasz dokładny limit)

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

# ─── Dane z JSON ─────────────────────────────────────────────────
MODEL=$(echo "$INPUT"       | jq -r '.model.display_name // "unknown"' 2>/dev/null)
INPUT_TOK=$(echo "$INPUT"   | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
OUTPUT_TOK=$(echo "$INPUT"  | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
CTX_SIZE=$(echo "$INPUT"    | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)

INPUT_TOK=${INPUT_TOK:-0}; OUTPUT_TOK=${OUTPUT_TOK:-0}; CTX_SIZE=${CTX_SIZE:-200000}
TOTAL_TOK=$(( INPUT_TOK + OUTPUT_TOK ))
CTX_PCT=0
[ "$CTX_SIZE" -gt 0 ] && CTX_PCT=$(( TOTAL_TOK * 100 / CTX_SIZE ))

# ─── ccusage: 5H block (cache 5min) ─────────────────────────────
get_ccusage() {
  local cache="/tmp/.cc_usage_cache" now
  now=$(date +%s)
  if [ -f "$cache" ]; then
    local age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 300 ] && cat "$cache" && return
  fi
  if ! command -v ccusage &>/dev/null; then
    printf "0|0|0||" | tee "$cache"; return
  fi
  local raw
  raw=$(ccusage blocks --json 2>/dev/null)
  [ -z "$raw" ] && printf "0|0|0||" | tee "$cache" && return

  local cur_block cur_tokens cur_start cur_end
  local cur_tokens_fmt remaining_fmt cur_pct cur_reset_str="" est_end_str=""
  cur_block=$(echo "$raw" | jq '
    ([.blocks[] | select(.isActive == true)] | last) //
    ([.blocks[] | select(.isGap == false)]   | last) // null' 2>/dev/null)
  cur_tokens=$(echo "$cur_block" | jq -r '.totalTokens // 0' 2>/dev/null)
  cur_tokens=${cur_tokens:-0}
  cur_start=$(echo "$cur_block" | jq -r '.startTime // empty' 2>/dev/null)
  cur_end=$(echo "$cur_block" | jq -r '.endTime // empty' 2>/dev/null)

  # Format tokenów (k/M)
  fmt_t() {
    local t=$1
    if [ "$t" -ge 1000000 ]; then
      awk -v t="$t" 'BEGIN{printf "%.1fM", t/1000000}'
    elif [ "$t" -ge 1000 ]; then
      awk -v t="$t" 'BEGIN{printf "%.0fk", t/1000}'
    else
      printf "%d" "$t"
    fi
  }
  cur_tokens_fmt=$(fmt_t "$cur_tokens")

  # Pozostałe tokeny
  local remaining=$(( BLOCK_LIMIT_5H - cur_tokens ))
  [ "$remaining" -lt 0 ] && remaining=0
  remaining_fmt=$(fmt_t "$remaining")

  # Procent zużycia
  cur_pct=0
  [ "$BLOCK_LIMIT_5H" -gt 0 ] && cur_pct=$(( cur_tokens * 100 / BLOCK_LIMIT_5H ))
  [ "$cur_pct" -gt 100 ] && cur_pct=100

  # Czas do resetu
  if [ -n "$cur_end" ] && [ "$cur_end" != "null" ]; then
    local end_epoch diff h m
    end_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${cur_end%.*}" "+%s" 2>/dev/null || \
                date -d "${cur_end%.*}" "+%s" 2>/dev/null || echo 0)
    diff=$(( end_epoch - now ))
    if [ "$diff" -gt 0 ]; then
      h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
      [ "$h" -gt 0 ] && cur_reset_str="${h}h${m}m" || cur_reset_str="${m}m"
    else
      cur_reset_str="wygasł"
    fi
  fi

  # Szacowany czas wyczerpania (na podstawie tempa)
  if [ -n "$cur_start" ] && [ "$cur_start" != "null" ] && [ "$cur_tokens" -gt 0 ] && [ "$remaining" -gt 0 ]; then
    local start_epoch elapsed
    start_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${cur_start%.*}" "+%s" 2>/dev/null || \
                  date -d "${cur_start%.*}" "+%s" 2>/dev/null || echo 0)
    elapsed=$(( now - start_epoch ))
    if [ "$elapsed" -gt 60 ]; then
      local sec_left end_at h m
      sec_left=$(awk -v rem="$remaining" -v tok="$cur_tokens" -v dur="$elapsed" \
        'BEGIN{printf "%d", (rem/tok)*dur}')
      if [ "$sec_left" -gt 0 ]; then
        local est_h=$(( sec_left / 3600 )) est_m=$(( (sec_left % 3600) / 60 ))
        [ "$est_h" -gt 0 ] && est_end_str="${est_h}h${est_m}m" || est_end_str="${est_m}m"
      fi
    fi
  fi

  printf "%s|%s|%s|%s|%s" "${cur_tokens_fmt:-0}" "${remaining_fmt:-0}" "${cur_pct:-0}" "${cur_reset_str:-}" "${est_end_str:-}" | tee "$cache"
}

CCDATA=$(get_ccusage)
CUR_TOKENS=$(echo "$CCDATA"   | cut -d'|' -f1)
CUR_LEFT=$(echo "$CCDATA"     | cut -d'|' -f2)
CUR_PCT=$(echo "$CCDATA"      | cut -d'|' -f3)
RESET_TIMER=$(echo "$CCDATA"  | cut -d'|' -f4)
EST_END=$(echo "$CCDATA"      | cut -d'|' -f5)

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

# ═══ LINIA 1: AI — kontekst + limit 5H ══════════════════════════
CTX_C=$(pct_color "$CTX_PCT")
CTX_BAR=$(dotbar "$CTX_PCT")
L1="${C_MODEL}${MODEL}${R}"
L1="${L1}${SEP}🧩 ${C_LBL}CTX:${R} ${CTX_BAR} ${CTX_C}${CTX_PCT}%${R}"
TOK_C=$(pct_color "${CUR_PCT:-0}")
TOK_BAR=$(dotbar "${CUR_PCT:-0}")
L1="${L1}${SEP}💎 ${C_LBL}TOKENY:${R} ${TOK_BAR} ${C_VAL}${CUR_TOKENS:-0}${R}${C_DIM}/${R}${C_VAL}${CUR_LEFT:-0}${R} ${TOK_C}${CUR_PCT:-0}%${R}"
[ -n "$EST_END" ] && L1="${L1}${SEP}${C_LBL}koniec ~${R}${C_VAL}${EST_END}${R}"
[ -n "$RESET_TIMER" ] && L1="${L1}${SEP}${C_LBL}reset${R} ${C_VAL}${RESET_TIMER}${R}"

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

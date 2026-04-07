#!/usr/bin/env bash
# statusline.sh — rich terminal statusline for Claude Code
#
# Data sources:
#   Context usage → stdin JSON piped by Claude Code (context_window fields)
#   Session stats → ~/.claude/projects/**/*.jsonl (5-hour rolling window)
#   Model         → stdin JSON (.model.id) or ~/.claude/settings.json fallback
#   Git / dir     → live from shell
#
# Optional overrides:
#   CLAUDE_MAX_TOKENS     context window ceiling fallback
#   CLAUDE_SESSION_LIMIT  session window seconds (default: 18000 = 5h)
#
# Dependencies: bash ≥4, git (optional), jq (required for stdin parsing), JetBrainsMono Nerd Font
# Usage: invoked automatically by Claude Code as the statusLine command

# ─────────────────────────────────────────────
#  Catppuccin Mocha — true-color ANSI escapes
# ─────────────────────────────────────────────
R=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'

FG_TEXT=$'\e[38;2;205;214;244m'       # #cdd6f4  Primary text
FG_SUBTEXT=$'\e[38;2;166;173;200m'    # #a6adc8  Dim / labels
FG_GREEN=$'\e[38;2;166;227;161m'      # #a6e3a1  Low usage
FG_YELLOW=$'\e[38;2;249;226;175m'     # #f9e2af  Mid usage
FG_PEACH=$'\e[38;2;250;179;135m'      # #fab387  High usage
FG_RED=$'\e[38;2;243;139;168m'        # #f38ba8  Critical usage
FG_MAUVE=$'\e[38;2;203;166;247m'      # #cba6f7  Accent / icons
FG_LAVENDER=$'\e[38;2;180;190;254m'   # #b4befe  Model name
FG_BLUE=$'\e[38;2;137;180;250m'       # #89b4fa  Numbers / stats
FG_TEAL=$'\e[38;2;148;226;213m'       # #94e2d5  Session time

FG_GRAY=$FG_SUBTEXT
FG_DKGRAY=$'\e[38;2;88;91;112m'       # Surface2 — subtle separators

BG_BAR_TRACK=$'\e[48;2;49;50;68m'     # Surface0 — bar background

# ─────────────────────────────────────────────
#  Icons (Nerd Font glyphs)
# ─────────────────────────────────────────────
ICON_DIR="󰉋 "
ICON_GIT=" "
ICON_MOD="󰝶 "
ICON_STG="󰐕 "
ICON_UTR="? "
ICON_BOT="󱙺 "
ICON_CTX="󰹿 "
ICON_CLK="󱑎 "
SEP="${FG_DKGRAY}│${R}"

# ─────────────────────────────────────────────
#  Model → context-window size fallback
# ─────────────────────────────────────────────
_model_max_tokens() {
  case "$1" in
    *opus*|*sonnet*|*haiku*) echo 200000 ;;
    *claude-2*)              echo 100000 ;;
    *)                       echo 200000 ;;
  esac
}

# ─────────────────────────────────────────────
#  Read model from ~/.claude/settings.json (fallback)
# ─────────────────────────────────────────────
_read_model_fallback() {
  local settings="${HOME}/.claude/settings.json"
  local model=""

  if [[ -f "$settings" ]] && command -v jq &>/dev/null; then
    model=$(jq -r '.model // empty' "$settings" 2>/dev/null)
  fi

  [[ -z "$model" ]] && model="${ANTHROPIC_MODEL:-}"
  [[ -z "$model" ]] && model="${CLAUDE_MODEL:-}"
  [[ -z "$model" ]] && model="claude-sonnet-4-6"
  printf '%s' "$model"
}

# ─────────────────────────────────────────────
#  Parse stdin JSON from Claude Code
#  Globals set: _CC_MODEL _CC_USED_TOKENS _CC_MAX_TOKENS _CC_USED_PCT
# ─────────────────────────────────────────────
_CC_MODEL=""
_CC_USED_TOKENS=0
_CC_MAX_TOKENS=0
_CC_USED_PCT=0
_CC_RL5_PCT=""
_CC_RL5_RESETS=0
_CC_RL7_PCT=""
_CC_RL7_RESETS=0

_read_stdin_json() {
  local json="$1"
  [[ -z "$json" ]] && return

  if command -v jq &>/dev/null; then
    local parsed
    parsed=$(printf '%s' "$json" | jq -r '
      [
        (.model.id // .model // ""),
        (.context_window.current_tokens // (.context_window.used_percentage // 0) * (.context_window.context_window_size // .context_window.max_tokens // 200000) / 100 | floor | tostring),
        (.context_window.context_window_size // .context_window.max_tokens // 0 | tostring),
        (.context_window.used_percentage // 0 | tostring),
        (.rate_limits.five_hour.used_percentage // "" | tostring),
        (.rate_limits.five_hour.resets_at       // 0  | tostring),
        (.rate_limits.seven_day.used_percentage // "" | tostring),
        (.rate_limits.seven_day.resets_at       // 0  | tostring)
      ] | join("\t")
    ' 2>/dev/null)

    IFS=$'\t' read -r _CC_MODEL _CC_USED_TOKENS _CC_MAX_TOKENS _CC_USED_PCT \
                       _CC_RL5_PCT _CC_RL5_RESETS _CC_RL7_PCT _CC_RL7_RESETS <<< "$parsed"
  fi

  # Sanitize
  [[ "$_CC_USED_TOKENS" =~ ^[0-9]+$ ]]   || _CC_USED_TOKENS=0
  [[ "$_CC_MAX_TOKENS"  =~ ^[0-9]+$ ]]   || _CC_MAX_TOKENS=0
  [[ "$_CC_USED_PCT"    =~ ^[0-9.]+$ ]]  || _CC_USED_PCT=0
  [[ "$_CC_RL5_PCT"     =~ ^[0-9.]+$ ]]  || _CC_RL5_PCT=""
  [[ "$_CC_RL5_RESETS"  =~ ^[0-9]+$ ]]   || _CC_RL5_RESETS=0
  [[ "$_CC_RL7_PCT"     =~ ^[0-9.]+$ ]]  || _CC_RL7_PCT=""
  [[ "$_CC_RL7_RESETS"  =~ ^[0-9]+$ ]]   || _CC_RL7_RESETS=0

  # Fallbacks
  [[ -z "$_CC_MODEL" ]]     && _CC_MODEL=$(_read_model_fallback)
  (( _CC_MAX_TOKENS == 0 )) && _CC_MAX_TOKENS=$(_model_max_tokens "$_CC_MODEL")
  if (( _CC_USED_TOKENS == 0 )) && (( _CC_MAX_TOKENS > 0 )); then
    _CC_USED_TOKENS=$(( ${_CC_USED_PCT%.*} * _CC_MAX_TOKENS / 100 ))
  fi
}

# ─────────────────────────────────────────────
#  5-hour rolling session stats from JSONL logs
#  Globals set: _SES_ELAPSED_S _SES_IN _SES_OUT _SES_CACHE_R _SES_CACHE_W
# ─────────────────────────────────────────────
_SES_ELAPSED_S=0
_SES_ELAPSED_PCT=0
_SES_REMAINING_S=0
_SES_IN=0
_SES_OUT=0
_SES_CACHE_R=0
_SES_CACHE_W=0

_read_session_stats() {
  command -v jq &>/dev/null || return

  local window="${CLAUDE_SESSION_LIMIT:-18000}"   # 5 h in seconds
  local now
  now=$(date +%s)
  local cutoff=$(( now - window ))

  local jsonl_files=()
  while IFS= read -r -d '' f; do
    jsonl_files+=("$f")
  done < <(find "${HOME}/.claude/projects" -name '*.jsonl' -print0 2>/dev/null)

  [[ ${#jsonl_files[@]} -eq 0 ]] && return

  local stats
  stats=$(
    jq -rn --argjson cutoff "$cutoff" '
      [ inputs
        | select(.type == "assistant" and .message.usage != null)
        | . as $e
        | ($e.timestamp // "" | gsub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0) as $ts
        | select($ts >= $cutoff)
        | $e.message.usage
        | [
            (.input_tokens                // 0),
            (.output_tokens               // 0),
            (.cache_read_input_tokens     // 0),
            (.cache_creation_input_tokens // 0)
          ]
      ]
      | if length == 0 then "0\t0\t0\t0\t0"
        else
          ( map(.[0]) | add ) as $in  |
          ( map(.[1]) | add ) as $out |
          ( map(.[2]) | add ) as $cr  |
          ( map(.[3]) | add ) as $cw  |
          ( length ) as $n            |
          "\($n)\t\($in)\t\($out)\t\($cr)\t\($cw)"
        end
    ' "${jsonl_files[@]}" 2>/dev/null
  )

  [[ -z "$stats" ]] && return

  local n_msgs in_tok out_tok cr_tok cw_tok
  IFS=$'\t' read -r n_msgs in_tok out_tok cr_tok cw_tok <<< "$stats"

  [[ "$in_tok"  =~ ^[0-9]+$ ]] || in_tok=0
  [[ "$out_tok" =~ ^[0-9]+$ ]] || out_tok=0
  [[ "$cr_tok"  =~ ^[0-9]+$ ]] || cr_tok=0
  [[ "$cw_tok"  =~ ^[0-9]+$ ]] || cw_tok=0

  _SES_IN=$in_tok
  _SES_OUT=$out_tok
  _SES_CACHE_R=$cr_tok
  _SES_CACHE_W=$cw_tok

  local earliest
  earliest=$(
    jq -rn --argjson cutoff "$cutoff" '
      [ inputs
        | select(.type == "assistant" and .message.usage != null)
        | (.timestamp // "" | gsub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0)
        | select(. >= $cutoff)
      ] | if length == 0 then empty else min end
    ' "${jsonl_files[@]}" 2>/dev/null
  )

  if [[ "$earliest" =~ ^[0-9]+$ ]] && (( earliest > 0 )); then
    _SES_ELAPSED_S=$(( now - earliest ))
    (( _SES_ELAPSED_S < 0 )) && _SES_ELAPSED_S=0
    _SES_ELAPSED_PCT=$(( _SES_ELAPSED_S * 100 / window ))
    (( _SES_ELAPSED_PCT > 100 )) && _SES_ELAPSED_PCT=100
    _SES_REMAINING_S=$(( window - _SES_ELAPSED_S ))
    (( _SES_REMAINING_S < 0 )) && _SES_REMAINING_S=0
  fi
}

# ─────────────────────────────────────────────
#  Format helpers
# ─────────────────────────────────────────────
_fmt_tokens() {
  local n=$1
  if   (( n >= 1000000 )); then printf '%.1fM' "$(echo "scale=1; $n/1000000" | bc)"
  elif (( n >= 1000    )); then printf '%.1fk' "$(echo "scale=1; $n/1000"    | bc)"
  else                         printf '%d'    "$n"
  fi
}

_fmt_duration() {
  local s=$1
  local h=$(( s / 3600 )) m=$(( (s % 3600) / 60 ))
  if (( h > 0 )); then printf '%dh%02dm' "$h" "$m"
  else                 printf '%dm'       "$m"
  fi
}

_fmt_duration_days() {
  local s=$1
  local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
  if (( d > 0 )); then printf '%dd%dh%02dm' "$d" "$h" "$m"
  else                 printf '%dh%02dm'     "$h" "$m"
  fi
}

# ─────────────────────────────────────────────
#  Progress bar  _bar <pct> <width>
# ─────────────────────────────────────────────
_bar() {
  local pct=${1:-0} width=${2:-12}
  local color
  if   (( pct >= 90 )); then color=$FG_RED
  elif (( pct >= 70 )); then color=$FG_PEACH
  elif (( pct >= 40 )); then color=$FG_YELLOW
  else                       color=$FG_GREEN
  fi
  local filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  local empty=$(( width - filled ))
  local bar="${BG_BAR_TRACK}" i
  for (( i=0; i<filled; i++ )); do bar+="${color}█${R}${BG_BAR_TRACK}"; done
  for (( i=0; i<empty;  i++ )); do bar+="${FG_DKGRAY}░${R}${BG_BAR_TRACK}"; done
  bar+="${R}"
  printf '%s' "$bar"
}

# ─────────────────────────────────────────────
#  Sections
# ─────────────────────────────────────────────
_section_dir() {
  local cwd="${PWD/#$HOME/\~}"
  local short
  short=$(awk -F'/' '{n=NF; if(n<=2) print $0;
    else { if($1=="") printf "/"; printf "%s/%s", $(n-1), $n } }' <<< "$cwd")
  printf '%s%s%s%s%s%s' \
    "${FG_MAUVE}${BOLD}" "${ICON_DIR}" "${R}" \
    "${FG_TEXT}${BOLD}" "${short}" "${R}"
}

_section_git() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf '%s(no git)%s' "${FG_DKGRAY}" "${R}"; return
  fi
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null \
        || git rev-parse --short HEAD 2>/dev/null)

  local modified=0 staged=0 untracked=0
  while IFS= read -r line; do
    local x="${line:0:1}" y="${line:1:1}"
    [[ "$x" != " " && "$x" != "?" && "$x" != "!" ]] && (( staged++ ))
    [[ "$y" != " " && "$y" != "?" && "$y" != "!" ]] && (( modified++ ))
    [[ "$x" == "?" ]] && (( untracked++ ))
  done < <(git status --porcelain 2>/dev/null)

  local bcol="${FG_GREEN}"
  (( staged   > 0 )) && bcol="${FG_YELLOW}"
  (( modified > 0 )) && bcol="${FG_PEACH}"

  printf '%s%s%s%s%s%s' \
    "${FG_MAUVE}${BOLD}" "${ICON_GIT}" "${R}" \
    "${bcol}${BOLD}" "${branch}" "${R}"
  printf '  '

  local mcol="${FG_SUBTEXT}${DIM}"; (( modified  > 0 )) && mcol="${FG_PEACH}${BOLD}"
  local scol="${FG_SUBTEXT}${DIM}"; (( staged    > 0 )) && scol="${FG_YELLOW}${BOLD}"
  local ucol="${FG_SUBTEXT}${DIM}"; (( untracked > 0 )) && ucol="${FG_RED}${BOLD}"

  printf '%s%sM:%d%s  ' "${mcol}" "${ICON_MOD}" "$modified"  "${R}"
  printf '%s%sS:%d%s  ' "${scol}" "${ICON_STG}" "$staged"    "${R}"
  printf '%s%sU:%d%s'   "${ucol}" "${ICON_UTR}" "$untracked" "${R}"
}

_section_claude() {
  local model="$1" used_tokens="$2" max_tokens="$3" ctx_pct="$4"

  local ctx_pct_int="${ctx_pct%.*}"
  [[ "$ctx_pct_int" =~ ^[0-9]+$ ]] || ctx_pct_int=0
  (( ctx_pct_int > 100 )) && ctx_pct_int=100

  local display_model="${model#claude-}"

  local vcol
  if   (( ctx_pct_int >= 90 )); then vcol="${FG_RED}"
  elif (( ctx_pct_int >= 70 )); then vcol="${FG_PEACH}"
  elif (( ctx_pct_int >= 40 )); then vcol="${FG_YELLOW}"
  else                               vcol="${FG_GREEN}"
  fi

  printf '%s%s%s%s%s%s' \
    "${FG_MAUVE}${BOLD}" "${ICON_BOT}" "${R}" \
    "${FG_LAVENDER}${BOLD}" "${display_model}" "${R}"
  printf '  %s%s%s' "${FG_SUBTEXT}" "${ICON_CTX}" "${R}"
  _bar "$ctx_pct_int" 12
  printf ' %s%s%s/%s%s%s %s(%d%%)%s' \
    "${vcol}${BOLD}" "$(_fmt_tokens "$used_tokens")" "${R}" \
    "${FG_SUBTEXT}" "$(_fmt_tokens "$max_tokens")" "${R}" \
    "${FG_MAUVE}" "$ctx_pct_int" "${R}"
}

_rl_segment() {
  local label="$1" pct_raw="$2" resets_at="$3" now="$4" use_days="${5:-0}"
  [[ -z "$pct_raw" ]] && return
  local pct_int="${pct_raw%.*}"
  [[ "$pct_int" =~ ^[0-9]+$ ]] || pct_int=0
  local vcol
  if   (( pct_int >= 90 )); then vcol="${FG_RED}"
  elif (( pct_int >= 70 )); then vcol="${FG_PEACH}"
  elif (( pct_int >= 40 )); then vcol="${FG_YELLOW}"
  else                           vcol="${FG_GREEN}"
  fi
  printf '%s%s%s ' "${FG_SUBTEXT}" "$label" "${R}"
  _bar "$pct_int" 10
  printf ' %s%s%d%%%s' "${vcol}" "${BOLD}" "$pct_int" "${R}"
  local rem=$(( resets_at - now ))
  if (( rem > 0 && resets_at > 0 )); then
    local fmt; (( use_days )) && fmt=$(_fmt_duration_days "$rem") || fmt=$(_fmt_duration "$rem")
    printf ' %sreset%s %s%s%s' "${FG_SUBTEXT}" "${R}" "${FG_TEAL}${BOLD}" "$fmt" "${R}"
  fi
}

_section_rate_limits() {
  local rl5_pct="$1" rl5_resets="$2" rl7_pct="$3" rl7_resets="$4"
  [[ -z "$rl5_pct" && -z "$rl7_pct" ]] && return
  local now; now=$(date +%s)
  printf '%s%s%s ' "${FG_MAUVE}${BOLD}" "${ICON_CLK}" "${R}"
  _rl_segment "5h" "$rl5_pct" "$rl5_resets" "$now" 0
  [[ -n "$rl5_pct" && -n "$rl7_pct" ]] && printf '  %s  ' "${SEP}"
  _rl_segment "7d" "$rl7_pct" "$rl7_resets" "$now" 1
}

# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────
statusline() {
  local stdin_json=""
  if [[ -t 0 ]]; then
    : # stdin is a terminal — no JSON piped, use fallbacks
  else
    stdin_json=$(cat)
  fi

  _read_stdin_json "$stdin_json"
  _read_session_stats

  local sp="  ${SEP}  "

  # Line 1: dir + git
  printf '%s%s%s\n' \
    "$(_section_dir)" \
    "$sp"             \
    "$(_section_git)"

  # Line 2: model + live context bar
  printf '%s\n' \
    "$(_section_claude "$_CC_MODEL" "$_CC_USED_TOKENS" "$_CC_MAX_TOKENS" "$_CC_USED_PCT")"

  # Line 3: rate limits (hidden when not available — Pro/Max only)
  local rl_line
  rl_line="$(_section_rate_limits "$_CC_RL5_PCT" "$_CC_RL5_RESETS" "$_CC_RL7_PCT" "$_CC_RL7_RESETS")"
  [[ -n "$rl_line" ]] && printf '%s\n' "$rl_line"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  statusline
fi

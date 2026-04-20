#!/bin/bash
input=$(cat)

# DEBUG: dump raw JSON to file for inspection (remove after investigation)
echo "$input" > /tmp/statusline-debug.json

# ---------------------------------------------------------------------------
# Helper: build a compact progress bar (8 filled chars wide)
# Usage: make_bar <integer_percentage> <color_escape>
# ---------------------------------------------------------------------------
make_bar() {
  local pct=$1
  local color=$2
  local total=8
  local filled=$(( pct * total / 100 ))
  [ "$filled" -gt "$total" ] && filled=$total
  local empty=$(( total - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}▓"; done
  for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
  printf "${color}%s\033[0m" "$bar"
}

# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
model=$(echo "$input" | jq -r '.model.display_name // "..."')

# ---------------------------------------------------------------------------
# Current working directory (basename) and git branch
# ---------------------------------------------------------------------------
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$cwd" ]; then
  dir_name=$(basename "$cwd")
else
  dir_name=$(basename "$PWD")
  cwd="$PWD"
fi

# Git branch — silently omitted when not in a git repo
git_branch=$(GIT_DIR="${cwd}/.git" git --git-dir="${cwd}/.git" --work-tree="${cwd}" \
  rev-parse --abbrev-ref HEAD 2>/dev/null)
# Walk up the tree once if .git is not directly in cwd (worktree / subdirectory)
if [ -z "$git_branch" ]; then
  git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Determine branch color + extra info: green = clean & not ahead, yellow = dirty or ahead
if [ -n "$git_branch" ]; then
  # Count modified files (staged + unstaged)
  git_modified_count=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')

  # Count commits ahead of upstream (silently empty when no upstream configured)
  git_ahead_count=$(git -C "$cwd" rev-list --count @{u}..HEAD 2>/dev/null | tr -d '[:space:]')

  # Build the extra info string that appears inside the parentheses
  # Labels are emitted as color placeholders; actual color is applied after branch_color is determined.
  branch_extra_mod=""
  branch_extra_ahead=""
  if [ -n "$git_modified_count" ] && [ "$git_modified_count" -gt 0 ] 2>/dev/null; then
    branch_extra_mod=" mod:${git_modified_count}"
  fi
  if [ -n "$git_ahead_count" ] && [ "$git_ahead_count" -gt 0 ] 2>/dev/null; then
    branch_extra_ahead=" ahead:${git_ahead_count}"
  fi
  branch_extra="${branch_extra_mod}${branch_extra_ahead}"

  # Git insertions/deletions vs HEAD (staged + unstaged)
  shortstat=$(git -C "$cwd" diff --shortstat HEAD 2>/dev/null)
  git_ins=""
  git_del=""
  if [ -n "$shortstat" ]; then
    ins_num=$(echo "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
    del_num=$(echo "$shortstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
    if [ -n "$ins_num" ] && [ "$ins_num" -gt 0 ] 2>/dev/null; then
      git_ins=$(printf " \033[32m+%s\033[0m" "$ins_num")
    fi
    if [ -n "$del_num" ] && [ "$del_num" -gt 0 ] 2>/dev/null; then
      git_del=$(printf " \033[31m-%s\033[0m" "$del_num")
    fi
  fi

  # Color: yellow when there are modified files OR ahead commits; green when fully clean
  if [ -n "$branch_extra" ]; then
    branch_color="\033[33m"   # yellow — dirty or ahead of remote
  else
    branch_color="\033[32m"   # green  — working tree clean and up-to-date
  fi
fi

location_str=$(printf "\033[36m%s\033[0m" "$dir_name")
if [ -n "$git_branch" ]; then
  location_str="${location_str} $(printf "${branch_color}(%s%s\033[0m%s%s${branch_color})\033[0m" "$git_branch" "$branch_extra" "$git_ins" "$git_del")"

  # Last commit message — truncated to 50 chars, dim/gray, omitted when not in a git repo
  last_commit=$(git -C "$cwd" log -1 --pretty=format:"%s" 2>/dev/null)
  if [ -n "$last_commit" ]; then
    if [ ${#last_commit} -gt 50 ]; then
      last_commit="${last_commit:0:50}…"
    fi
    location_str="${location_str}  $(printf "\033[90mlast:\033[0m \033[2;37m%s\033[0m" "$last_commit")"
  fi
fi

# Worktree indicator — shown when Claude Code is running inside a git worktree
worktree_label=$(echo "$input" | jq -r '
  .workspace.git_worktree //
  .worktree.branch //
  .worktree.path //
  .agent.worktree //
  empty
' 2>/dev/null)
if [ -n "$worktree_label" ]; then
  # If the value looks like a path, show only the basename
  if [[ "$worktree_label" == */* ]]; then
    worktree_label=$(basename "$worktree_label")
  fi
  location_str="${location_str}  $(printf "\033[36m[worktree: %s]\033[0m" "$worktree_label")"
fi

# ---------------------------------------------------------------------------
# Effort level — Claude Code reasoning-effort setting.
# Not exposed via stdin JSON, so it's resolved from the same sources Claude
# Code itself honors, in its precedence order:
#   1. $CLAUDE_CODE_EFFORT_LEVEL env var (except the sentinels "unset"/"auto",
#      which mean "defer to settings")
#   2. `effortLevel` key in settings.json, searched project-local → project → user
# Omitted silently when nothing defines it.
# ---------------------------------------------------------------------------
effort_level=""
if [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
  _env_eff=$(echo "$CLAUDE_CODE_EFFORT_LEVEL" | tr '[:upper:]' '[:lower:]')
  if [ "$_env_eff" != "unset" ] && [ "$_env_eff" != "auto" ]; then
    effort_level="$_env_eff"
  fi
fi
if [ -z "$effort_level" ]; then
  for _s in "${cwd}/.claude/settings.local.json" "${cwd}/.claude/settings.json" "$HOME/.claude/settings.json"; do
    if [ -f "$_s" ]; then
      _v=$(jq -r '.effortLevel // empty' "$_s" 2>/dev/null)
      if [ -n "$_v" ]; then
        effort_level="$_v"
        break
      fi
    fi
  done
fi

# Valid effort levels are discovered dynamically from `claude --help` so new
# levels introduced by future CLI versions are recognized without code changes.
# The parsed list is cached and invalidated when the `claude` binary changes.
# Falls back to the known-good hardcoded list when the CLI is unavailable.
_effort_cache_file="/tmp/claudebar-effort-levels.cache"
_claude_bin=$(command -v claude 2>/dev/null)
valid_effort_levels=""
if [ -n "$_claude_bin" ]; then
  if [ ! -f "$_effort_cache_file" ] || [ "$_claude_bin" -nt "$_effort_cache_file" ]; then
    claude --help 2>/dev/null \
      | sed -n 's/.*--effort <level>.*(\([^)]*\)).*/\1/p' \
      | tr ',' '\n' | tr -d ' ' > "$_effort_cache_file" 2>/dev/null
  fi
  valid_effort_levels=$(cat "$_effort_cache_file" 2>/dev/null)
fi
if [ -z "$valid_effort_levels" ]; then
  valid_effort_levels=$'low\nmedium\nhigh\nxhigh\nmax'
fi

effort_str=""
if [ -n "$effort_level" ]; then
  level_count=$(echo "$valid_effort_levels" | wc -l | tr -d ' ')
  level_pos=$(echo "$valid_effort_levels" | grep -nx -- "$effort_level" | head -1 | cut -d: -f1)
  if [ -n "$level_pos" ] && [ "$level_count" -gt 1 ]; then
    # Map ordinal position to a traffic-light-like gradient.
    level_pct=$(( (level_pos - 1) * 100 / (level_count - 1) ))
    if   [ "$level_pct" -lt 13 ]; then effort_color="\033[32m"   # green
    elif [ "$level_pct" -lt 38 ]; then effort_color="\033[36m"   # cyan
    elif [ "$level_pct" -lt 63 ]; then effort_color="\033[33m"   # yellow
    elif [ "$level_pct" -lt 88 ]; then effort_color="\033[91m"   # bright red
    else                                effort_color="\033[31m"  # red
    fi
  elif [ -n "$level_pos" ]; then
    effort_color="\033[32m"   # single-item list
  else
    effort_color="\033[90m"   # gray — not a recognized level
  fi
  effort_str=$(printf "  \033[90m⚙\033[0m ${effort_color}%s\033[0m" "$effort_level")
fi

# ---------------------------------------------------------------------------
# Context window
# ---------------------------------------------------------------------------
ctx_used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')

# Input tokens: new input + cache creation + cache read
tokens_in=$(echo "$input" | jq -r '
  (.context_window.current_usage.input_tokens // 0) +
  (.context_window.current_usage.cache_creation_input_tokens // 0) +
  (.context_window.current_usage.cache_read_input_tokens // 0)
')
# Output tokens: cumulative session total
tokens_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // .context_window.current_usage.output_tokens // 0')

fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    echo "$(echo "$n" | awk '{printf "%.0fk", $1/1000}')t"
  else
    echo "${n}t"
  fi
}

tokens_in_fmt=$(fmt_tokens "$tokens_in")
tokens_out_fmt=$(fmt_tokens "$tokens_out")

# Context percentage color
ctx_pct_int=${ctx_used_pct%.*}
ctx_pct_int=${ctx_pct_int:-0}
if [ "$ctx_pct_int" -ge 90 ] 2>/dev/null; then
  ctx_color="\033[31m"
elif [ "$ctx_pct_int" -ge 70 ] 2>/dev/null; then
  ctx_color="\033[33m"
else
  ctx_color="\033[32m"
fi

# Context block: bar + percentage + in/out tokens
if [ -n "$ctx_used_pct" ]; then
  ctx_bar=$(make_bar "$ctx_pct_int" "$ctx_color")
  ctx_block=$(printf "ctx ${ctx_bar} ${ctx_color}%s%%\033[0m \033[36m←%s\033[0m \033[35m→%s\033[0m" "$ctx_pct_int" "$tokens_in_fmt" "$tokens_out_fmt")
else
  ctx_block=$(printf "\033[36mctx ←%s\033[0m \033[35m→%s\033[0m" "$tokens_in_fmt" "$tokens_out_fmt")
fi

# ---------------------------------------------------------------------------
# Helper: format seconds-until-reset as a human-readable countdown string
# Returns "(Xm)", "(Xh Ym)", or "(Xd Yh)"; empty string when input is invalid.
# Usage: format_reset_time <unix_epoch_reset_timestamp>
# ---------------------------------------------------------------------------
format_reset_time() {
  local resets_at=$1
  # Validate: must be a non-empty integer
  [[ -z "$resets_at" || "$resets_at" == "null" ]] && return
  [[ ! "$resets_at" =~ ^[0-9]+$ ]] && return

  local now
  now=$(date +%s)
  local diff=$(( resets_at - now ))
  [ "$diff" -le 0 ] && return

  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local minutes=$(( (diff % 3600) / 60 ))

  if [ "$days" -ge 1 ]; then
    printf "(%dd %dh)" "$days" "$hours"
  elif [ "$hours" -ge 1 ]; then
    printf "(%dh %dm)" "$hours" "$minutes"
  else
    printf "(%dm)" "$minutes"
  fi
}

# ---------------------------------------------------------------------------
# 5-hour session limit
# ---------------------------------------------------------------------------
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_str=""
if [ -n "$five_pct" ]; then
  # macOS /bin/bash 3.2 `printf "%.0f"` rejects values like "28.000000000000004";
  # awk handles them cleanly across platforms.
  five_int=$(awk -v v="$five_pct" 'BEGIN{printf "%.0f", v}')
  if [ "$five_int" -ge 90 ] 2>/dev/null; then
    five_color="\033[31m"
  elif [ "$five_int" -ge 70 ] 2>/dev/null; then
    five_color="\033[33m"
  else
    five_color="\033[32m"
  fi
  five_bar=$(make_bar "$five_int" "$five_color")
  five_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  five_countdown=$(format_reset_time "$five_resets_at")
  if [ -n "$five_countdown" ]; then
    five_str=$(printf "  5h ${five_bar} ${five_color}%s%% %s\033[0m" "$five_int" "$five_countdown")
  else
    five_str=$(printf "  5h ${five_bar} ${five_color}%s%%\033[0m" "$five_int")
  fi
fi

# ---------------------------------------------------------------------------
# 7-day weekly limit
# ---------------------------------------------------------------------------
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_str=""
if [ -n "$week_pct" ]; then
  week_int=$(awk -v v="$week_pct" 'BEGIN{printf "%.0f", v}')
  if [ "$week_int" -ge 90 ] 2>/dev/null; then
    week_color="\033[31m"
  elif [ "$week_int" -ge 70 ] 2>/dev/null; then
    week_color="\033[33m"
  else
    week_color="\033[32m"
  fi
  week_bar=$(make_bar "$week_int" "$week_color")
  week_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  week_countdown=$(format_reset_time "$week_resets_at")
  if [ -n "$week_countdown" ]; then
    week_str=$(printf "  7d ${week_bar} ${week_color}%s%% %s\033[0m" "$week_int" "$week_countdown")
  else
    week_str=$(printf "  7d ${week_bar} ${week_color}%s%%\033[0m" "$week_int")
  fi
fi

# ---------------------------------------------------------------------------
# Session stats — duration, cache hit rate, lines edited
# ---------------------------------------------------------------------------
session_stats_str=""

# Duration
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$duration_ms" ] && [ "$duration_ms" -gt 0 ] 2>/dev/null; then
  duration_s=$(( duration_ms / 1000 ))
  if [ "$duration_s" -ge 3600 ]; then
    h=$(( duration_s / 3600 ))
    m=$(( (duration_s % 3600) / 60 ))
    duration_fmt="${h}h ${m}m"
  elif [ "$duration_s" -ge 60 ]; then
    m=$(( duration_s / 60 ))
    s=$(( duration_s % 60 ))
    duration_fmt="${m}m ${s}s"
  else
    duration_fmt="${duration_s}s"
  fi
  session_stats_str="${session_stats_str}$(printf "\033[90m⏱\033[0m %s" "$duration_fmt")  "
fi

# Cache hit rate bar
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
total_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_total=$(( cache_read + cache_create + total_in ))
if [ "$cache_total" -gt 0 ]; then
  cache_pct=$(( cache_read * 100 / cache_total ))
  if [ "$cache_pct" -ge 80 ]; then
    cache_color="\033[32m"
  elif [ "$cache_pct" -ge 50 ]; then
    cache_color="\033[33m"
  else
    cache_color="\033[31m"
  fi
  cache_bar=$(make_bar "$cache_pct" "$cache_color")
  session_stats_str="${session_stats_str}$(printf "\033[90mcache\033[0m %s ${cache_color}%s%%\033[0m" "$cache_bar" "$cache_pct")  "
fi

# Lines edited by Claude
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  session_stats_str="${session_stats_str}$(printf "\033[90medited\033[0m \033[32m+%s\033[0m \033[31m-%s\033[0m" "$lines_added" "$lines_removed")  "
fi
session_stats_str="${session_stats_str%  }"

# Tool usage, agents and skills — third line (omitted when transcript is absent)
# Reads the session JSONL transcript to extract:
#   - tool_use counts per tool name (excluding Agent/Task/Skill meta-tools)
#   - agent subagent_type counts
#   - skill names used
# ---------------------------------------------------------------------------
tools_str=""
agents_str=""
skills_str=""
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then

  # Tools — exclude meta-tools Agent, Task, Skill, ToolSearch
  tool_counts=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name | IN("Agent","Task","Skill","ToolSearch") | not) |
    .name
  ' "$transcript_path" 2>/dev/null | sort | uniq -c | sort -rn | head -10)

  if [ -n "$tool_counts" ]; then
    tools_str=$(printf "\033[90mTools:\033[0m")
    while IFS= read -r line; do
      count=$(echo "$line" | awk '{print $1}')
      name=$(echo "$line" | awk '{print $2}')
      tools_str="${tools_str} $(printf "%s\033[90m×\033[0m%s" "$name" "$count")"
    done <<< "$tool_counts"
  fi

  # Agents — group by subagent_type
  agent_counts=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Agent" or .name == "Task") |
    .input.subagent_type // "general"
  ' "$transcript_path" 2>/dev/null | sort | uniq -c | sort -rn)

  if [ -n "$agent_counts" ]; then
    agents_str=$(printf "\033[90mAgents:\033[0m")
    while IFS= read -r line; do
      count=$(echo "$line" | awk '{print $1}')
      name=$(echo "$line" | awk '{print $2}')
      agents_str="${agents_str} $(printf "\033[33m%s\033[90m×\033[0m%s" "$name" "$count")"
    done <<< "$agent_counts"
  fi

  # Skills — list unique skill names used
  skill_names=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Skill") |
    .input.skill // "unknown"
  ' "$transcript_path" 2>/dev/null | sort -u)

  if [ -n "$skill_names" ]; then
    skills_str=$(printf "\033[90mSkills:\033[0m")
    while IFS= read -r sk; do
      skills_str="${skills_str} $(printf "\033[36m%s\033[0m" "$sk")"
    done <<< "$skill_names"
  fi

fi

# ---------------------------------------------------------------------------
# Compaction indicator — composite score from context %, cache efficiency,
# session duration and tool call volume.
# ---------------------------------------------------------------------------
compact_score=0
compact_str=""

# Factor 1: context usage (primary)
if [ "$ctx_pct_int" -ge 85 ] 2>/dev/null; then
  compact_score=$(( compact_score + 3 ))
elif [ "$ctx_pct_int" -ge 70 ] 2>/dev/null; then
  compact_score=$(( compact_score + 2 ))
elif [ "$ctx_pct_int" -ge 50 ] 2>/dev/null; then
  compact_score=$(( compact_score + 1 ))
fi

# Factor 2: cache hit rate degradation (low = context growing fast)
cache_read_raw=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_create_raw=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
input_raw=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_denom=$(( cache_read_raw + cache_create_raw + input_raw ))
if [ "$cache_denom" -gt 0 ]; then
  cache_hit_pct=$(( cache_read_raw * 100 / cache_denom ))
  if [ "$cache_hit_pct" -lt 60 ] 2>/dev/null; then
    compact_score=$(( compact_score + 1 ))
  fi
fi

# Factor 3: long session (>90 min = stale context risk)
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
dur_min=$(( dur_ms / 60000 ))
if [ "$dur_min" -ge 90 ] 2>/dev/null; then
  compact_score=$(( compact_score + 1 ))
fi

# Render indicator — gated on primary context signal: if ctx is low
# (e.g. fresh session or just-compacted), secondary factors like long
# duration or cache churn shouldn't trigger the hint on their own.
if [ "$ctx_pct_int" -ge 30 ] 2>/dev/null; then
  if [ "$compact_score" -ge 4 ]; then
    compact_str=$(printf "  \033[31;1m⚠ COMPACT\033[0m")
  elif [ "$compact_score" -ge 2 ]; then
    compact_str=$(printf "  \033[33m⚡ /compact\033[0m")
  elif [ "$compact_score" -ge 1 ]; then
    compact_str=$(printf "  \033[90m✦ compact?\033[0m")
  fi
fi

# ---------------------------------------------------------------------------
# Assemble final output:
#   Line 1: dir (branch  mod:N  ahead:N  +N -N)  last commit msg  [worktree: x]
#   Line 2: model  [⚙ effort]  ctx [bar] pct% ←in →out  [compact indicator]
#   Line 3: 5h [bar] pct% (…)  7d [bar] pct% (…)   (omitted when no rate-limit data)
#   Line 4: ⏱ duration  cache [bar] pct%  edited +N -N
#   Line 5: Tools: ...                               (omitted when no tool calls)
#   Line 6: Agents: ...  Skills: ...                 (omitted when both empty)
#
# Rate limits live on their own line because concatenating them into line 2
# often pushes it past the terminal width (~80 cols). Ink's statusline
# renderer wraps overflow across terminal rows, which silently eats the
# following output lines — so we'd lose Tools/Agents/Skills entirely.
# ---------------------------------------------------------------------------
printf "%s\n\033[35m%s\033[0m%s  %s%s" \
  "$location_str" "$model" "$effort_str" "$ctx_block" "$compact_str"

# Rate limits — strip the leading "  " spacer from five_str so the joined line
# doesn't start with indentation.
if [ -n "$five_str" ] || [ -n "$week_str" ]; then
  limits_line="${five_str}${week_str}"
  limits_line="${limits_line#  }"
  printf "\n%s" "$limits_line"
fi

if [ -n "$session_stats_str" ]; then
  printf "\n%s" "$session_stats_str"
fi

if [ -n "$tools_str" ]; then
  printf "\n%s" "$tools_str"
fi

last_line=""
[ -n "$agents_str" ] && last_line="${last_line}${agents_str}  "
[ -n "$skills_str" ] && last_line="${last_line}${skills_str}"
last_line="${last_line%  }"

if [ -n "$last_line" ]; then
  printf "\n%s" "$last_line"
fi

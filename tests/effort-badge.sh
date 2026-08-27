#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Regression tests for line 2's reasoning-effort badge (⚙ <level>).
#
# The bug these lock down: claudebar used to re-derive the effort level from
# $CLAUDE_CODE_EFFORT_LEVEL and the `effortLevel` settings key. Claude Code
# ≥2.1.x resolves the effort itself and ships it on stdin as `.effort.level`,
# and `/effort` no longer writes `effortLevel` to disk — so the settings-derived
# value froze the badge on a stale leftover (case B).
#
# Usage: bash tests/effort-badge.sh [path/to/statusline.sh]
# ---------------------------------------------------------------------------
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/statusline.sh}"
[ -f "$SCRIPT" ] || { echo "no encuentro $SCRIPT" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# Minimal payload. $1 = effort fragment (may be empty), $2 = cwd.
payload() {
  printf '{"model":{"display_name":"Opus 5"},%s"cwd":"%s","workspace":{"current_dir":"%s"},"context_window":{"used_percentage":7,"context_window_size":200000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000},"total_output_tokens":500},"cost":{"total_duration_ms":60000,"total_lines_added":5,"total_lines_removed":1}}' "$1" "$2" "$2"
}

# Pull the badge level out of line 2, stripping ANSI.
badge() {
  bash "$SCRIPT" | sed -n '2p' | sed $'s/\x1b\\[[0-9;]*m//g' \
    | sed -n 's/.*⚙ \([a-z]*\).*/\1/p'
}

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"; pass=$((pass+1))
  else printf '  ✗ %s — esperado "%s", obtenido "%s"\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# A: stdin carries the level and nothing contradicts it.
mkdir -p "$TMP/a/.claude"
check "A: stdin effort=max → max" "max" \
  "$(payload '"effort":{"level":"max"},' "$TMP/a" | badge)"

# B: the regression — a stale settings value must NOT beat the live session.
mkdir -p "$TMP/b/.claude"
echo '{"effortLevel":"xhigh"}' > "$TMP/b/.claude/settings.local.json"
check "B: stdin max gana a settings xhigh → max" "max" \
  "$(payload '"effort":{"level":"max"},' "$TMP/b" | badge)"

# C: older CLI builds omit .effort — the settings fallback still applies.
mkdir -p "$TMP/c/.claude"
echo '{"effortLevel":"xhigh"}' > "$TMP/c/.claude/settings.local.json"
check "C: sin .effort en stdin → cae a settings (xhigh)" "xhigh" \
  "$(payload '' "$TMP/c" | badge)"

# D: no source at all → the badge is omitted entirely.
mkdir -p "$TMP/d/.claude"
check "D: sin fuentes → badge vacío" "" "$(payload '' "$TMP/d" | badge)"

# E: a null level degrades like a missing one.
mkdir -p "$TMP/e/.claude"
check "E: .effort.level null → badge vacío" "" \
  "$(payload '"effort":{"level":null},' "$TMP/e" | badge)"

# F: level discovery from `claude --help` still works end to end. The help
# wraps the "(low, medium, …)" list onto the next line, which is what broke it.
# Note: exercises the real cache path, so it clears the shared cache file.
if command -v claude >/dev/null 2>&1; then
  CACHE=/tmp/claudebar-effort-levels.cache
  rm -f "$CACHE"
  mkdir -p "$TMP/f/.claude"
  payload '' "$TMP/f" | bash "$SCRIPT" >/dev/null 2>&1
  n=$(grep -c . "$CACHE" 2>/dev/null | head -1 | tr -dc 0-9); n=${n:-0}
  check "F: descubre los niveles del help (>=2)" "ok" \
    "$([ "$n" -ge 2 ] && echo ok || echo "solo $n")"
else
  printf '  – F: omitido (claude no está en PATH)\n'
fi

printf '\n  %d pasan, %d fallan\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

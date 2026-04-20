# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

claudebar is a Claude Code plugin that renders a 5-line statusline. The entire runtime is a single bash script (`statusline.sh`) that Claude Code invokes on every turn, piping a session-state JSON document into it on stdin. There is no build step, no tests, no language runtime — just bash + `git` + `jq`.

## Repository shape

- `statusline.sh` — the one file that matters. Reads JSON from stdin, prints 4 ANSI-colored lines to stdout.
- `commands/setup.md` — the `/claudebar:setup` slash command users run after installing the plugin. It discovers the cached plugin path, `chmod +x` the script, smoke-tests it, and merges a `statusLine` entry into `~/.claude/settings.json`.
- `.claude-plugin/plugin.json` + `marketplace.json` — plugin manifests consumed by `claude plugin install`.
- `package.json` — distribution metadata only (no scripts, no dependencies).

## The statusline.sh contract

The script is a pure stdin→stdout filter. Understand these inputs/outputs before editing:

**Input JSON fields consumed** (all optional — missing fields degrade gracefully, never error):
- `model.display_name`
- `workspace.current_dir` / `cwd` — resolved to basename for the directory label; also used as git work-tree root
- `workspace.git_worktree` / `worktree.*` — if present, renders `[worktree: name]`
- `context_window.used_percentage`, `context_window.context_window_size`
- `context_window.current_usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens}`
- `context_window.total_output_tokens`
- `rate_limits.five_hour.{used_percentage, resets_at}` and `rate_limits.seven_day.{...}` — Claude.ai subscription only; API-key sessions omit these silently
- `cost.{total_duration_ms, total_lines_added, total_lines_removed}`
- `transcript_path` — path to the session JSONL; when present, line 3's `Tools:` and line 4's `Agents:`/`Skills:` are populated by re-reading the transcript with `jq`

**Output layout** (each line is optional — entire lines are suppressed when empty):
1. Directory + git branch + dirty/ahead counts + insertions/deletions + last commit subject + optional worktree tag
2. Model + reasoning-effort badge + context bar + in/out tokens + compaction hint
3. 5h + 7d rate-limit bars with countdowns (suppressed when no Claude.ai subscription data is present)
4. Duration + cache hit-rate bar + lines edited
5. Top-10 tool counts (split onto its own line because it can grow wide)
6. Agents (by subagent_type) + unique skills invoked

Rate-limit bars live on their own line because Ink's statusline renderer truncates long lines by wrapping them to a second terminal row — and that overflow silently eats the lines that would have come after. Keeping each line short-ish (<80 visible cols) is a hard requirement for the whole stack to show up.

## Non-obvious conventions

- **Bar rendering** (`make_bar`): fixed 8-char width, filled with `▓`, empty with `░`. Color is passed in as an ANSI escape.
- **Traffic-light thresholds** appear in multiple places and should stay consistent: green <70%, yellow 70–89%, red ≥90%. Cache hit rate uses a different scale: green ≥80%, yellow ≥50%, red <50% (high cache reads are good; a low rate means context is churning).
- **Compaction score** (lines 364–407) is a composite with three factors: context % (weighted 1–3), cache hit <60% (+1), session >90 min (+1). Scores map to three severity tiers: `✦ compact?` (≥1), `⚡ /compact` (≥2), `⚠ COMPACT` (≥4). The render block is **gated on `ctx_pct_int ≥ 30`**: if context is low (fresh session or just-compacted), secondary factors like long duration or cache churn won't trigger the hint on their own. When tweaking thresholds in Line 2's context bar, remember this scorer reads the same `ctx_pct_int`.
- **Reasoning-effort badge** on line 2 (`⚙ <level>`) mirrors Claude Code's own resolution order: `$CLAUDE_CODE_EFFORT_LEVEL` env var first (with the sentinels `unset` / `auto` meaning "ignore me, use settings"), then the `effortLevel` key in `settings.local.json` / `settings.json` / `~/.claude/settings.json` (first match wins). The setting is **not** exposed on stdin, which is why it's the only piece of state read from outside the pipe. Claude Code persists `/effort <level>` by writing `effortLevel` into user `settings.json` via its internal `W8("userSettings", …)` call — the `--effort` CLI flag is per-session only and never hits disk, so the badge won't reflect it unless the user also exports the env var. The list of valid level names is discovered dynamically by parsing `claude --help` and cached at `/tmp/claudebar-effort-levels.cache`; the cache is invalidated whenever the resolved `claude` binary is newer than the cache file, so new CLI versions that add levels pick up automatically. If the CLI isn't on `PATH`, the script falls back to the known-good list `low / medium / high / xhigh / max`. Colors are assigned by ordinal position within the detected list using a 5-bucket gradient (green → cyan → yellow → bright-red → red), so adding or removing levels upstream won't require tweaking the palette. Values not in the list render gray to signal "unrecognized".
- **Meta-tool exclusion**: `Agent`, `Task`, `Skill`, and `ToolSearch` are excluded from the `Tools:` count and handled as separate aggregations. Keep this list in sync if new meta-tools appear.
- **Agent counting** treats `Agent` and `Task` as the same thing (Task is the legacy name) and groups by `.input.subagent_type`.
- **Git lookup** tries `GIT_DIR=cwd/.git` first, then falls back to `git -C cwd` (handles worktrees and nested subdirectories).
- **Debug breadcrumb** at line 5 writes the raw stdin JSON to `/tmp/statusline-debug.json` on every invocation. This is intentional during active development — remove only if the user explicitly asks to finalize.

## Testing changes

There is no test suite. Smoke-test edits by piping a sample JSON payload through the script:

```bash
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":10,"context_window_size":200000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000},"total_output_tokens":500},"cwd":"/tmp","workspace":{"current_dir":"/tmp"},"cost":{"total_duration_ms":60000,"total_lines_added":5,"total_lines_removed":1},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":9999999999},"seven_day":{"used_percentage":10,"resets_at":9999999999}}}' | bash statusline.sh
```

For richer scenarios, replay the last real invocation from `/tmp/statusline-debug.json`:

```bash
bash statusline.sh < /tmp/statusline-debug.json
```

To exercise the `Tools:`/`Agents:`/`Skills:` paths, inject a `transcript_path` pointing at a real JSONL from `~/.claude/projects/<project>/<session>.jsonl`.

## Distribution & installation flow

End users run `claude plugin install github:visiblesoft-es/claudebar`, which caches the repo under `~/.claude/plugins/cache/claudebar/claudebar/<version>/`. Then `/claudebar:setup` (defined in `commands/setup.md`) resolves the newest version directory using a `sort -t.` numeric sort across semver components, and writes a `statusLine.command` to `settings.json` that re-runs the same lookup at invocation time — so plugin updates are picked up without re-running setup. When bumping version numbers, update `package.json`, `plugin.json`, and `marketplace.json` together.

## When editing

- Preserve graceful degradation — every JSON field read through `jq` uses `// empty` or `// 0` so missing data never crashes the script.
- Keep line counts bounded: lines 4 and 5 can grow unboundedly if the transcript has many distinct tools/agents. The `Tools:` list is capped at 10 via `head -10`; keep a similar cap if adding new enumerations.
- When adding a new rate-limit or metric, mirror the existing `five_pct`/`week_pct` pattern: parse → color-pick → build bar → format countdown → append to the line only if the percentage field was present.

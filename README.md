# claudebar

A rich 4-line statusline for [Claude Code](https://claude.ai/code) that keeps your most relevant session information always visible: git context, model, reasoning-effort level, context window usage, session rate limits, cache efficiency, compaction hints, and a full breakdown of tools, agents and skills used.

## Preview

```
my-app (main  mod:3  ahead:2  +47 -12)  last: feat(auth): add refresh token rotation
Sonnet 4.6  ⚙ high  ctx ▓▓░░░░░░ 25% ←51kt →27kt  5h ▓░░░░░░░ 4% (1h 23m)  7d ▓▓░░░░░░ 18%
⏱ 22m 34s  cache ▓▓▓▓▓▓▓▓ 98%  edited +308 -66  Tools: Read×14  Edit×6  Bash×4
Agents: code-reviewer×2  Explore×1  Skills: commit  feature-dev
```

When the context is getting full, the compaction indicator appears at the end of line 2:

```
my-app (main  mod:3  ahead:2  +47 -12)  last: feat(auth): add refresh token rotation
Sonnet 4.6  ⚙ high  ctx ▓▓▓▓▓▓░░ 74% ←148kt →52kt  5h ▓▓░░░░░░ 28%  7d ▓▓▓░░░░░ 38%  ⚡ /compact
⏱ 1h 8m  cache ▓▓▓░░░░░ 42%  edited +1204 -389  Tools: Read×38  Edit×17  Bash×9
Agents: code-reviewer×2  Explore×1  Skills: commit  feature-dev
```

### Line 1 — Git context
- **Directory name** and **branch** — green when clean, yellow when there are uncommitted changes
- `mod:N` — number of modified files (staged + unstaged)
- `ahead:N` — commits not yet pushed to remote
- `+N -N` — line insertions (green) / deletions (red) compared to HEAD
- `last: <message>` — subject of the last commit, truncated to 50 characters
- `[worktree: name]` — displayed when running inside a git worktree

### Line 2 — Model, effort, context window & compaction hint
- **Model name** in use
- **⚙ Effort level** — Claude Code's reasoning-effort setting (`effortLevel` in `settings.json`). Color-coded by intensity: `low` (green), `medium` (cyan), `high` (yellow), `max` (red). Read with Claude Code's precedence order: project-local → project → user settings. Omitted silently when unset.
- **Context bar** `▓▓░░░░░░` with percentage and token breakdown:
  - `←Nkt` total input tokens (new + cache creation + cache reads)
  - `→Nkt` cumulative output tokens for the session
- **5h rate limit bar** with percentage and countdown until reset
- **7d rate limit bar** with percentage and countdown until reset
- **Compaction hint** — a composite signal that watches three factors and tells you when to run `/compact`:

| Indicator | Meaning | When it appears |
|-----------|---------|-----------------|
| `✦ compact?` | Worth considering | Context >50%, or session >90 min |
| `⚡ /compact` | Recommended | Context >70%, or cache hit rate dropping |
| `⚠ COMPACT` | Act soon | Context >85% — approaching auto-compact |

  The score is computed from: context window usage (primary), cache hit rate degradation (a dropping rate means new context is accumulating fast), and session duration. Silent when the session is healthy.

### Line 3 — Session stats & tools
- **⏱ Duration** — wall time elapsed since the session started
- **Cache hit rate bar** — how efficiently the prompt cache is being used (green ≥80%, yellow ≥50%, red <50%). A low rate means the model is processing large amounts of new context on every turn.
- **edited +N -N** — lines added and removed by Claude across the entire session
- **Tools** — top 10 most-used tool names with call counts, sorted descending

### Line 4 — Agents & skills
- **Agents** — subagent types launched during the session, with call counts (yellow)
- **Skills** — unique skills invoked via the `Skill` tool (cyan). Only shown when skills have been used.

---

## Requirements

- macOS or Linux (Windows not supported — the statusline is a bash script)
- `bash` — available by default on macOS and most Linux distributions
- `git` — required for branch info, dirty state, ahead count and diff stats
- `jq` — required for JSON parsing. Install with:
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt install jq`
  - Fedora: `sudo dnf install jq`
- Claude Code ≥ 2.0

---

## Installation

### Step 1 — Install the plugin

Run this command in your terminal:

```bash
claude plugin install github:visiblesoft-es/claudebar
```

> **Local installation** (for development or offline use):
> ```bash
> git clone https://github.com/visiblesoft-es/claudebar.git
> claude plugin install ./claudebar
> ```

### Step 2 — Run the setup command

Open Claude Code and run:

```
/claudebar:setup
```

This command will:
1. Locate the installed plugin files
2. Make the statusline script executable
3. Test it produces output correctly
4. Write the `statusLine` configuration to your `~/.claude/settings.json`

### Step 3 — Restart Claude Code

Quit Claude Code completely and launch it again:

```bash
claude
```

The 4-line statusline will now appear below the input field in every session.

---

## Updating

When a new version is released, update with:

```bash
claude plugin update claudebar
```

No need to re-run `/claudebar:setup` after an update — the setup command generates a dynamic path that always resolves to the latest installed version automatically.

---

## Troubleshooting

**The statusline does not appear after restart**

Re-run `/claudebar:setup` to verify the configuration was written correctly. Check that `~/.claude/settings.json` contains a `statusLine.command` key.

**`jq: command not found`**

Install `jq` (see Requirements above) and restart your terminal.

**git info is missing**

The plugin reads git data from the `cwd` reported by Claude Code. Make sure you are working inside a git repository. If the repo root is a parent directory, the plugin walks up one level to find `.git`.

**Rate limit bars are not showing**

Rate limit data (`5h` / `7d`) is only available on Claude.ai subscription plans. It will not appear on API-key-only setups.

---

## License

MIT

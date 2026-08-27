# claudebar

A rich 6-line statusline for [Claude Code](https://claude.ai/code) that keeps your most relevant session information always visible: git context, model, reasoning-effort level, context window usage, session rate limits, cache efficiency, compaction hints, and a full breakdown of tools, agents and skills used. Every line is dropped when it has nothing to show, so a fresh session starts compact and grows as the session does.

## Preview

```
my-app (main mod:3 ahead:2 +47 -12)  last: feat(auth): refresh token rotation
Sonnet 4.6  ⚙ high  ctx ▓▓░░░░░░ 25% ←51kt →27kt
5h ░░░░░░░░ 4% (1h 22m)  7d ▓░░░░░░░ 18% (4d 5h)
⏱ 22m 34s  cache ▓▓▓▓▓▓▓░ 98%  edited +308 -66
Tools: Read×14 Edit×6 Bash×4
Agents: code-reviewer×2 Explore×1  Skills: commit feature-dev
```

When the context is getting full, the compaction indicator appears at the end of line 2:

```
my-app (main mod:3 ahead:2 +47 -12)  last: feat(auth): refresh token rotation
Sonnet 4.6  ⚙ high  ctx ▓▓▓▓▓░░░ 74% ←148kt →52kt  ⚡ /compact
5h ▓▓░░░░░░ 28% (1h 56m)  7d ▓▓▓░░░░░ 38% (2d 23h)
⏱ 1h 8m  cache ▓▓▓░░░░░ 42%  edited +1204 -389
Tools: Read×38 Edit×17 Bash×9
Agents: code-reviewer×2 Explore×1  Skills: commit feature-dev
```

### Line 1 — Git context
- **Directory name** and **branch** — green when clean, yellow when there are uncommitted changes or unpushed commits
- `mod:N` — number of modified files (staged, unstaged and untracked)
- `ahead:N` — commits not yet pushed to the upstream branch
- `+N -N` — line insertions (green) / deletions (red) compared to HEAD
- `last: <message>` — subject of the last commit, shortened (or dropped) to keep the line within the panel width
- `[worktree: name]` — displayed when running inside a git worktree

### Line 2 — Model, effort, context window & compaction hint
- **Model name** in use
- **⚙ Effort level** — the reasoning effort of the running session, as reported by Claude Code itself, so it follows `/effort` and `--effort` live. Color-coded by position in the scale: `low` (green), `medium` (cyan), `high` (yellow), `xhigh` (bright red), `max` (red); an unrecognized value renders gray. Omitted silently when Claude Code reports none.
- **Context bar** `▓▓░░░░░░` with percentage and token breakdown:
  - `←Nkt` total input tokens (new + cache creation + cache reads)
  - `→Nkt` cumulative output tokens for the session
- **Compaction hint** — a composite signal that tells you when to run `/compact`. It scores three factors:

| Factor | Points |
|--------|--------|
| Context ≥85% / ≥70% / ≥50% | +3 / +2 / +1 |
| Cache hit rate below 60% | +1 |
| Session longer than 90 minutes | +1 |

| Indicator | Meaning | Score |
|-----------|---------|-------|
| `✦ compact?` | Worth considering | 1 |
| `⚡ /compact` | Recommended | 2–3 |
| `⚠ COMPACT` | Act soon | 4+ |

  The hint stays silent below 30% context, so a fresh or just-compacted session is never nagged by the secondary factors alone.

### Line 3 — Rate limits
- **5h bar** — usage of the rolling 5-hour limit, with a countdown to reset
- **7d bar** — usage of the weekly limit, with a countdown to reset

  Both come from your Claude.ai subscription; the whole line is omitted on API-key sessions. It sits on its own row on purpose: appended to line 2 it would overflow the panel width, and the overflow silently eats the lines below it.

### Line 4 — Session stats
- **⏱ Duration** — wall time elapsed since the session started
- **Cache hit rate bar** — how efficiently the prompt cache is being used (green ≥80%, yellow ≥50%, red <50%). A low rate means the model is processing large amounts of new context on every turn.
- **edited +N -N** — lines added and removed by Claude across the entire session

### Line 5 — Tools
- Top 10 most-used tool names with call counts, sorted descending. Read from the session transcript, and omitted when no tools have been called. `Agent`, `Task`, `Skill` and `ToolSearch` are counted on line 6 instead.

### Line 6 — Agents & skills
- **Agents** — subagent types launched during the session, with call counts (yellow)
- **Skills** — unique skills invoked via the `Skill` tool (cyan)

  Omitted when neither has been used.

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

The statusline will now appear below the input field in every session.

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

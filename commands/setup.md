---
description: Install claudebar as your Claude Code statusline
allowed-tools: Bash, Read, Edit
---

## Step 1: Locate the plugin

Find the installed plugin directory (highest installed version):

```bash
ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claudebar/claudebar/*/ 2>/dev/null \
  | sort -V | tail -1
```

If empty, the plugin is not installed. Ask the user to install it first:
```
claude plugin install claudebar
```

## Step 2: Make the script executable

```bash
plugin_dir=$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claudebar/claudebar/*/ 2>/dev/null | sort -V | tail -1)
chmod +x "${plugin_dir}statusline.sh"
```

## Step 3: Test the script

Run a quick smoke-test to confirm it produces output:

```bash
plugin_dir=$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claudebar/claudebar/*/ 2>/dev/null | sort -V | tail -1)
echo '{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":10,"context_window_size":200000,"current_usage":{"input_tokens":1,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000},"total_output_tokens":500},"cwd":"/tmp","workspace":{"current_dir":"/tmp"},"cost":{"total_duration_ms":60000,"total_lines_added":5,"total_lines_removed":1},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":9999999999},"seven_day":{"used_percentage":10,"resets_at":9999999999}}}' \
  | bash "${plugin_dir}statusline.sh"
```

If it errors or produces no output, do not proceed to Step 4. Report the error.

## Step 4: Write the configuration

Build the statusLine command and merge it into `settings.json`. Do NOT overwrite existing settings — merge only the `statusLine` key.

The command to set (re-resolves the latest installed version on every invocation, so plugin updates are picked up without re-running setup):
```
bash -c 'plugin_dir=$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claudebar/claudebar/*/ 2>/dev/null | sort -V | tail -1); exec bash "${plugin_dir}statusline.sh"'
```

Settings file: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`

Merge using the Edit tool to set:
```json
{
  "statusLine": {
    "type": "command",
    "command": "<the command above>"
  }
}
```

## Step 5: Confirm

Tell the user:

> ✅ claudebar installed. **Please restart Claude Code** — quit and run `claude` again.
>
> The statusline shows up to 6 lines — each one is dropped when it has nothing to show:
> - **Line 1** — git branch, dirty state, ahead commits, insertions/deletions, last commit message
> - **Line 2** — model, reasoning-effort badge, context bar (←input →output), compaction hint
> - **Line 3** — 5h and 7d rate limits with countdowns (Claude.ai subscriptions only)
> - **Line 4** — session duration, cache hit rate bar, lines edited by Claude
> - **Line 5** — tool usage counts
> - **Line 6** — agents used (grouped by type) and skills invoked
>
> Requirements: `bash`, `git`, `jq` must be available in PATH.

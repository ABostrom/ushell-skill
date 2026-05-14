# Claude Code statusLine + hooks — research findings

**Researched:** 2026-05-14 (claude-code-guide subagent + WebFetch on code.claude.com).
**For:** [`2026-05-14-ushell-statusline-design.md`](2026-05-14-ushell-statusline-design.md) Open Questions.

## Q1 — `statusLine` in `~/.claude/settings.json`

**Schema (statusline.md):**

```json
{
  "statusLine": {
    "type": "command",
    "command": "<path or inline shell>",
    "padding": 0,
    "refreshInterval": 1,
    "hideVimModeIndicator": false
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `type` | yes | must be `"command"` for a custom script |
| `command` | yes | path to script, or inline command |
| `padding` | no | horizontal padding in chars (default 0) |
| `refreshInterval` | no | seconds; **minimum is `1`** — also fires on events |
| `hideVimModeIndicator` | no | hide built-in `-- INSERT --` (default false) |

**Multi-line: SUPPORTED.** Each `echo` / `Write-Output` = separate row. Max lines NOT documented; assume reasonable (test if we exceed 5). Stdout-only; stderr ignored. Script input is JSON on stdin (session data).

## Q2 — `hooks` in `~/.claude/settings.json`

**Schema (hooks.md):**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          { "type": "command", "command": "<...>" }
        ]
      }
    ]
  }
}
```

**Matcher field:**
- `"*"` or omitted → match all.
- Letters/digits/underscore/pipe only → exact string or `|`-separated OR list. `Bash|PowerShell` matches either tool.
- Anything else → JavaScript regex.

**Input contract: JSON via stdin** (not env vars; env vars only supplement). Exact quote from hooks.md:244: *"Command hooks: JSON via stdin"*.

**PreToolUse input fields:**

```json
{
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "...",
  "permission_mode": "...",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash|Edit|...",
  "tool_input": { ... },
  "tool_use_id": "..."
}
```

**PostToolUse input fields:** same plus `"tool_response": { ... }`.

**Bash `tool_input`:**

```json
{
  "command": "...",
  "description": "...",
  "timeout": 120000,
  "run_in_background": true
}
```

**Environment variables for hooks** (supplement to stdin JSON):
- `CLAUDE_PROJECT_DIR` — project root.
- `CLAUDE_PLUGIN_ROOT` — plugin install dir.
- `CLAUDE_PLUGIN_DATA` — plugin persistent data dir.
- `CLAUDE_CODE_REMOTE` — `"true"` in web env.
- `CLAUDE_EFFORT` — `low|medium|high|xhigh|max`.

## Q3 — Background-task metadata in hook input

**The critical unknown.** Documentation lists `tool_input.run_in_background: true/false` in PreToolUse, but does **NOT** document where the harness exposes the background task's `shell_id` or `output_file` path.

**Empirical evidence from this session:** the harness gives Claude (not the hook) a structured response on background launch:

```
Command running in background with ID: bgxxxxxxx.
Output is being written to: C:\Users\Aaron\AppData\Local\Temp\claude\<cwd-mangled>\<session_id>\tasks\<task_id>.output
```

The cwd-mangling rule: replace `:` and `\` in the absolute CWD with `-`. Example: `E:\Work\ushell-skill` → `E--Work-ushell-skill`.

**Workaround for our statusline:** the hook **doesn't need** the exact `output_file` at PreToolUse time. It needs the tasks **directory**, which is deterministic from `session_id` + `cwd`:

```
$env:TEMP\claude\<cwd-mangled>\<session_id>\tasks\
```

The statusline script then globs that directory for the most-recently-modified `*.output` file and tails it. Single-active-ushell-task model (per brainstorm) → newest output file = active task. This handles the case where the harness creates the output file AFTER PreToolUse fires.

PostToolUse may or may not include `tool_response.shell_id` — undocumented; check empirically in a follow-up if we need exact-match instead of "newest".

## Q4 — Plugin manifest extensions

**Hooks do NOT live in `plugin.json`.** Per plugins.md "Migrate hooks" section: create `<plugin>/hooks/hooks.json` and copy the same shape as `settings.json`'s `hooks` block.

**Plugin directory layout (canonical):**

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          ← MANIFEST ONLY (name/desc/version/author)
├── skills/
├── commands/
├── agents/
├── hooks/
│   └── hooks.json           ← hooks live here
├── settings.json            ← default settings applied on plugin enable
└── bin/
```

Don't put `hooks/`, `skills/`, `commands/` *inside* `.claude-plugin/` — only `plugin.json` goes there.

**statusLine in plugins: not documented**. Most-likely shape based on the `hooks/hooks.json` pattern:
- Ship a `settings.json` in the plugin root with the `statusLine` block (auto-merged on plugin enable).
- OR document a manual user-side `settings.json` snippet for opt-in.

We'll go with the `settings.json`-in-plugin-root approach for v2.1 — matches the documented "default settings applied when plugin enabled" mechanism.

**Plugin template variables (available in hook/script commands):**

- `${CLAUDE_PLUGIN_ROOT}` — plugin install dir (also exported as env var to spawned process).
- `${CLAUDE_PROJECT_DIR}` — project root.
- `${CLAUDE_PLUGIN_DATA}` — plugin persistent data dir.

## Implementation decisions (locked in)

| Question | Decision | Notes |
|---|---|---|
| Multi-line statusline? | Yes, 3 lines | Each Write-Output = row. Test for truncation at 5+. |
| `refreshInterval` | 1 second | Min allowed; smooth live updates. |
| Hook input | stdin JSON | `[Console]::In.ReadToEnd()` then `ConvertFrom-Json`. |
| Background output_file | **Glob session tasks dir for newest `*.output`** | Hook writes tasks_dir to state, statusline finds active file by mtime. |
| Hook matcher | `"Bash\|PowerShell"` | OR-list of tool names. |
| Plugin shape (v2.1+) | `hooks/hooks.json` + `settings.json` in plugin root | NOT inside `plugin.json`. |
| Template var | `${CLAUDE_PLUGIN_ROOT}` | for script paths in hooks.json and plugin settings.json. |

## Implementation changes to the plan

1. **A6 (hook script):** read `session_id` and `cwd` from hook input JSON. Compute cwd-mangled tasks dir. Write `tasks_dir` to state's `active.tasks_dir` instead of trying to know `output_file` upfront. Also keep `tool_use_id` so PostToolUse can match the right entry.

2. **A7 (statusline):** when `active` is set, look at `active.tasks_dir`. Glob `*.output`. Pick the file with the most recent `LastWriteTime`. Tail that.

3. **B1 (plugin manifest):** ship `hooks/hooks.json` + `settings.json` in plugin root (not extensions to `plugin.json`). Use `${CLAUDE_PLUGIN_ROOT}` for paths.

## What's NOT documented and we still might hit

- statusLine max lines (empirical: test 3, 5, 10).
- PowerShell tool input schema (assumed same shape as Bash).
- `tool_response` shape on PostToolUse for background commands (need to log it once to see).

These don't block implementation — the design is robust to all three unknowns via the "glob newest" approach.

# ushell statusline — design spec

**Status:** Draft
**Date:** 2026-05-14
**Author:** Aaron Bostrom (with Claude Code)
**Related specs:** [`2026-05-13-phase17-install-ergonomics.md`](2026-05-13-phase17-install-ergonomics.md) (the install ergonomics this builds on), [`2026-05-13-ushell-skill-design.md`](2026-05-13-ushell-skill-design.md) (the parent skill design).
**Target ship:** part of the next minor (`v2.1` or `v2.2`) following the v2.0.1 carve-out content fix.

---

## Motivation

When you run ushell directly in a cmd window, you see live progress: `Cooked packages 450 / Total 477`, UBT's `[N/M] Compiling Foo.cpp`, `.p4 sync` byte counts. When Claude drives ushell on your behalf — `run_in_background: true` on a `Bash`/`PowerShell` tool call — that stream goes to a harness-managed output file you don't see in real time. You only get the result on completion notification.

For long-running verbs (a full Lyra cook is 30–90 min; a fresh BuildCookRun shipping pipeline is 45–120 min) this loss of visibility is the worst of both worlds: you can't see what's happening, and you can't easily check without asking Claude or tailing a file path you'd have to remember.

The Claude Code statusline is the natural surface to restore that visibility: it refreshes automatically, sits at the bottom of every conversation, and supports custom shell scripts.

**Stated user pain (verbatim from 2026-05-14 brainstorm):** *"It's important people can just see the progress of a cook very quickly whilst in CLI. I don't want us to lose that as we have wrapped ushell."*

---

## Goals

1. **Zero-config install.** A single `/plugin install ushell@ABostrom-skills` enables the statusline. No manual `settings.json` edits, no ushell-channel install step, no per-project setup.
2. **Live cook (and build, sync, etc.) progress.** While a ushell command is in flight, statusline shows `<verb> · <N>/<Total> · ~<ETA>` and updates every 1–2 seconds.
3. **Composite context view.** Three lines:
   - L1: active project @ engine path `(installed|source)`
   - L2: in-flight verb + progress + ETA, or `idle`
   - L3: last command + result (✓ / ✗) + time
4. **Catches Claude-driven ushell.** Every ushell-shaped command Claude invokes via the Bash/PowerShell tool is tracked.
5. **Cross-platform.** Windows (PowerShell) and POSIX (bash) variants ship in the plugin.

---

## Non-goals

- **Catching ushell run directly in a separate cmd window** (no hook fires → no state update). Future enhancement: ship an optional ushell channel that catches those too. Out of scope for v1.
- **Multi-project parallel tracking.** Brainstorm resolved single-focus.
- **Persistent history beyond the most recent `last` command.** Statusline is not a log viewer.
- **Real-time output streaming into the conversation.** Different feature (`Monitor`-tail pattern already documented in `reference/invocation.md`).
- **ZenServer / DDC status.** Separate surface; `.zen status` and `.ddc auth --query` already exist.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Claude Code session                                                     │
│                                                                         │
│   Claude assembles ushell command                                       │
│        │                                                                │
│        │  PreToolUse hook ──► hook-update.ps1 ──► state file            │
│        ▼                                          (active populated)    │
│   cmd.exe /d /s /c "call ushell.bat ... && .cook game Win64"            │
│        │                                                                │
│        └──► stdout/stderr ──► harness bg output file                    │
│                                                                         │
│   ┌──── statusLine (refresh ~1.5s) ────┐                                │
│   │ statusline.ps1 reads state file +  │                                │
│   │ tails bg output for progress regex │                                │
│   └──► renders 3 lines to status bar ◄─┘                                │
│                                                                         │
│   bg command exits ──► PostToolUse hook ──► hook-update.ps1             │
│                                              ──► state file             │
│                                                  (active cleared,       │
│                                                   last populated)       │
└─────────────────────────────────────────────────────────────────────────┘
```

Three components, one piece of state, one statusline renderer. No daemon, no background process beyond the existing harness-managed task.

---

## Components

### 1. Plugin manifest extensions (`.claude-plugin/plugin.json`)

Add `statusLine` and `hooks` fields:

```json
{
  "name": "ushell",
  "version": "2.1.0",
  "description": "Drives ushell (Epic's Unreal Engine CLI) end-to-end ...",
  "...": "...",
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File ${PLUGIN_DIR}/scripts/statusline.ps1",
    "refreshInterval": 1500
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [{
          "type": "command",
          "command": "pwsh -NoProfile -File ${PLUGIN_DIR}/scripts/hook-update.ps1 -Phase pre"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [{
          "type": "command",
          "command": "pwsh -NoProfile -File ${PLUGIN_DIR}/scripts/hook-update.ps1 -Phase post"
        }]
      }
    ]
  }
}
```

**Assumption (verify during planning):** the Claude Code plugin manifest format supports `statusLine` and `hooks` fields directly inside `plugin.json`, with auto-merge into user settings on install. If the spec instead expects a separate `hooks.json` / `statusline.json` in `.claude-plugin/`, the layout adapts accordingly — the data is the same.

**Cross-platform script routing.** PowerShell 7+ (`pwsh`) is available on Windows by default and broadly installable on macOS/Linux, so the manifest commands reference the `.ps1` scripts unconditionally and rely on `pwsh` being on PATH. The `.sh` variants ship as fallbacks for users who prefer not to install PowerShell — they're invoked via a manifest override the user can enable in their personal `~/.claude/settings.json` (documented in the plugin README). v1 does not auto-detect platform inside the manifest; that's a v2 enhancement if needed.

### 2. State file

**Location:** `~/.claude/ushell-state.json` (Windows: `%USERPROFILE%\.claude\ushell-state.json`).

**Schema** (`schema_version: 1`):

```json
{
  "schema_version": 1,
  "active": {
    "task_id": "b9795py03",
    "output_file": "C:\\Users\\Aaron\\AppData\\Local\\Temp\\claude\\...\\b9795py03.output",
    "command": ".cook game Win64",
    "verb": "cook",
    "verb_args": "game Win64",
    "project": "ProjectGear",
    "project_path": "E:\\Work\\Games\\ProjectGear",
    "engine": "E:\\UE_5.7",
    "engine_branch": "++UE5+Release-5.7",
    "engine_kind": "installed",
    "started": "2026-05-14T11:40:01Z"
  },
  "last": {
    "command": ".build game Win64 shipping",
    "verb": "build",
    "project": "ProjectGear",
    "result": "ok",
    "exit_code": 0,
    "finished": "2026-05-14T11:51:23Z",
    "duration_s": 287,
    "note": null
  },
  "context": {
    "project": "ProjectGear",
    "project_path": "E:\\Work\\Games\\ProjectGear",
    "engine": "E:\\UE_5.7",
    "engine_kind": "installed"
  }
}
```

Field semantics:
- `active`: present iff a ushell command is in flight; `null` otherwise.
- `last`: most recent completed command; survives across sessions until overwritten.
- `context`: most-recently-seen project/engine pair; survives `last` overwrites. Lets the statusline keep showing project context after a non-ushell tool call.

**Atomic writes.** All updates write to `ushell-state.json.tmp`, `fsync`, then atomic-rename to `ushell-state.json`. Prevents torn reads from the statusline script that runs concurrently.

**Schema versioning.** The `schema_version` field gates the reader. If a `statusline.ps1` from v2.1 encounters a `schema_version: 2` state file written by a newer version, it logs to `~/.claude/ushell-state.error.log` and renders `(ushell: state version mismatch — upgrade plugin)` rather than crashing. Forward-incompatible schema changes bump the integer; backward-compatible additions reuse the version.

### 3. `hook-update.{ps1,sh}` — state writer

Invoked by PreToolUse / PostToolUse hooks. Behavior:

**Phase `pre`:**
1. Read the tool-call command string from hook input (stdin or `CLAUDE_TOOL_INPUT` env — verify hook contract).
2. Match against the ushell regex:
   ```
   \b(ushell\.bat|RunUAT\.bat|UnrealBuildTool\.exe|UnrealEditor(-Cmd)?\.exe)\b
   ```
   If no match → exit 0, do nothing.
3. Parse the verb (`.build`, `.cook`, `.stage`, `.uat`, `.run`, `.p4`, etc.) and arguments from the command string.
4. Extract `--project=<path>` (or infer from the active `FLOW_SID` noticeboard if not present in the command).
5. Read `Engine/Build/InstalledBuild.txt` presence to set `engine_kind`.
6. Read `Engine/Build/Build.version` for `engine_branch`.
7. Identify the harness background output file from the hook's task-id context (verify available in hook input).
8. Read existing state, populate `active`, update `context`, atomic-write.

**Phase `post`:**
1. Read tool-call result (exit code, possibly stderr summary) from hook input.
2. Read existing state. If `active` is null or doesn't match this task, no-op (defensive).
3. Move `active` → `last`, capture `exit_code`, `finished` timestamp, `duration_s = finished - started`.
4. For known verbs, parse the tail of the output file for a `Result: <X>` line and optionally a one-line `note` (e.g., `1 error / 6 warnings`).
5. Clear `active`, atomic-write.

The hook intentionally does *not* read or modify any project files — it only touches `~/.claude/ushell-state.json` and reads two engine-side metadata files (`InstalledBuild.txt`, `Build.version`).

### 4. `statusline.{ps1,sh}` — renderer

Invoked by Claude Code's statusline subsystem on every refresh (~1.5s). Behavior:

1. Read `~/.claude/ushell-state.json`. If missing/unreadable → emit `(ushell: no context)` single-line and exit 0.
2. Emit **L1** from `context` (or `active.project_path` if no context yet):
   ```
   <project> @ <engine_short> (<engine_kind>)
   ```
   Where `<engine_short>` is the engine path's last segment (`UE_5.7`, not the full path). Example: `ProjectGear @ UE_5.7 (installed)`.
3. **L2 — active branch:**
   - If `active` is non-null:
     - Look up the verb's progress regex (table below).
     - Tail the last ~200 lines of `active.output_file` (use a small cached read-position file `~/.claude/ushell-state.tail.json` for incremental tailing — keyed by `output_file` path and `inode/mtime`).
     - Apply progress regex; extract `num/total`.
     - Compute ETA from rate over the last ~30s of samples (need to keep a small rolling window — store in `ushell-state.tail.json` next to the read-position).
     - Render: `<active.command> · <num>/<total> · ~<eta>`.
     - If progress regex doesn't match yet: render `<active.command> · starting...`.
   - If `active` is null:
     - Render: `idle`.
4. **L3 — last branch:**
   - If `last` is non-null:
     - Render: `last: <last.command> <✓|✗> <HH:MM>[ · <note>]`.
     - `✓` if `result == "ok"` else `✗`.
   - If `last` is null:
     - Skip L3.

### 5. Verb progress regex table

Lives in `scripts/progress-patterns.json` (or inline). Initial set:

| Verb pattern | Regex (on tailed output) | Display |
|---|---|---|
| `.cook *` | `LogCook: Display: Cooked packages (?<n>\d+) Packages Remain \d+ Total (?<t>\d+)` | `<n>/<t>` |
| `.build *` | `\[(?<n>\d+)/(?<t>\d+)\] ` | `<n>/<t>` (UBT action progress) |
| `.uat BuildCookRun` w/ `-build` | same as `.build` until cook starts, then `.cook` | passes through |
| `.uat BuildCookRun` w/ `-stage` | `********** STAGE COMMAND` markers + `Saving <N>` | textual phase |
| `.p4 sync` | `(?<n>\d+) of (?<t>\d+) files` | `<n>/<t>` |
| `.sln generate` | `Creating Build Targets (\d+)%` | `<pct>%` |
| fallback | last non-empty line | textual, truncated |

Adding a new pattern is one row in this table — explicitly the extension point.

---

## Data flow (example: cook a Win64 build)

1. User: *"Cook ProjectGear for Win64."*
2. Claude assembles `cmd /d /s /c "call ushell.bat --project=... && .cook game Win64"`, prepares `Bash` (or `PowerShell`) tool call with `run_in_background: true`.
3. **PreToolUse** hook fires. `hook-update.ps1 -Phase pre` reads the command, matches ushell pattern, parses `verb=cook`, `project=ProjectGear`, engine path from `--project=`, detects `InstalledBuild.txt` → `engine_kind=installed`. Captures `task_id` and `output_file` from hook input. Atomic-writes state with `active` populated.
4. Tool call launches the background command.
5. Statusline refreshes (~1.5s cadence). `statusline.ps1`:
   - Reads state → finds `active`.
   - Tails `output_file` → matches `LogCook: Display: Cooked packages 32 Packages Remain 445 Total 477`.
   - Reads tail-state file → ETA estimator says ~12 minutes.
   - Renders:
     ```
     ProjectGear @ UE_5.7 (installed)
     .cook game Win64 · 32/477 · ~12m
     last: .build game Win64 shipping ✓ 11:51
     ```
6. Cook continues. Statusline updates every 1–2s. ETA refines as rate stabilises.
7. Cook exits (success or fail). Harness fires task-completion notification.
8. **PostToolUse** hook fires. `hook-update.ps1 -Phase post` reads exit code, tails the output file for `Result: <X>` and warning/error counts, writes new state: `active=null`, `last={command:".cook game Win64", result:"fail", exit_code:1, note:"1 error / 6 warnings"}`.
9. Statusline:
   ```
   ProjectGear @ UE_5.7 (installed)
   idle
   last: .cook game Win64 ✗ 12:38 · 1err/6warn
   ```

---

## Error handling

| Failure mode | Behavior |
|---|---|
| State file missing | Render `(ushell: no context)`. Don't crash. |
| State file corrupt JSON | Same as missing; log to `~/.claude/ushell-state.error.log`. |
| Output file missing or rotated mid-tail | Render `<command> · starting...` until file appears. |
| Output file truncated | Reset cached read position, restart tail. |
| Progress regex no match yet | Render verb without progress count. |
| Hook script fails | Log to `~/.claude/ushell-state.error.log`; statusline renders last known state. |
| Hook detects non-ushell command | Exit 0, no state mutation. |
| Concurrent state writes (rare — PreToolUse can race PostToolUse of an unrelated call) | Atomic-rename + last-writer-wins. Acceptable since hooks are per-tool-call and unrelated calls don't share fields. |
| Cross-platform path issues | Store paths in state as-provided; render in OS-native form. |

---

## Cross-platform notes

- **Windows:** primary target. PowerShell 7+ for both `statusline.ps1` and `hook-update.ps1`. The skill's existing examples assume `pwsh`.
- **POSIX (macOS, Linux):** ship bash equivalents `statusline.sh` / `hook-update.sh`. JSON parsing via `jq` (declare as a dependency in the plugin's README).
- **Path normalization:** state file always stores absolute paths in the OS's native form. The statusline shortens engine paths to last segment for display.
- **Atomic rename:** Windows requires `MoveFile` with `MOVEFILE_REPLACE_EXISTING` (PowerShell `Move-Item -Force`). POSIX `rename(2)` is atomic by default.

---

## Testing strategy

Three layers, matching the skill's existing TDD-for-skills discipline:

1. **Progress-regex unit tests** (`tests/statusline/test-progress-regex.ps1`).
   Synthetic ushell output snippets (snapshots of real `.cook`, `.build`, `.uat`, `.p4 sync`, etc. outputs) as fixtures. Assert each regex extracts the expected `num/total` pair.

2. **State-file lifecycle integration test** (`tests/statusline/test-state-lifecycle.ps1`).
   Simulate a PreToolUse + PostToolUse pair. Verify: state file written atomically, `active` populated correctly, statusline renders three expected lines. Repeat for the `Pre → fail` path (no PostToolUse fires) — verify defensive cleanup.

3. **Battle test** (`tests/battle-test-statusline.md`).
   Same shape as `battle-test-projectgear.md`. Run a real `.cook game Win64` against ProjectGear; observe statusline updates over 20+ minutes; capture screenshots / paste rendered lines at 1 min, 5 min, 15 min, post-completion. Find real-world quirks the synthetic tests didn't catch (output-file rotation? statusline truncation? non-ASCII in project names?). File any findings as F-numbered defects per the battle-test convention.

---

## Open questions (verify during planning / before implementation)

These are not blockers for the spec; they're items to confirm against current Claude Code docs / the live plugin spec before locking the manifest layout.

1. **Plugin manifest fields.** Does `plugin.json` accept `statusLine` and `hooks` directly, or do these need to live in `.claude-plugin/statusline.json` / `.claude-plugin/hooks.json` (or similar)? Affects layout but not architecture.
2. **`${PLUGIN_DIR}` template.** Confirm this resolves correctly inside plugin-shipped script paths.
3. **Hook input contract.** Verify how the hook receives the tool-call command string and exit code (stdin JSON? env vars? `CLAUDE_TOOL_INPUT`?).
4. **Background task ID and output-file path access.** Confirm hooks can read these from input context (we need both to populate `active.task_id` and `active.output_file`).
5. **Refresh interval.** Verify CC's minimum `refreshInterval` and whether 1500ms is a sane default (vs. 1000ms, 2000ms).
6. **Multi-line statusline.** Confirm 3-line output renders properly. If only single-line, the design falls back to a compact one-liner:
   `<project> [<kind>] · <verb> <n>/<t> ~<eta> · last: <verb> <✓|✗> <HH:MM>`

---

## File layout in the plugin

```
ushell-skill/
├── .claude-plugin/
│   ├── marketplace.json    (existing, no change)
│   └── plugin.json         (extended with statusLine + hooks fields)
├── scripts/                (NEW)
│   ├── statusline.ps1
│   ├── statusline.sh
│   ├── hook-update.ps1
│   ├── hook-update.sh
│   └── progress-patterns.json
├── skills/ushell/...       (existing, unchanged)
├── tests/
│   ├── statusline/         (NEW — unit + integration tests)
│   │   ├── test-progress-regex.ps1
│   │   └── test-state-lifecycle.ps1
│   ├── battle-test-statusline.md   (NEW — battle-test log, gitignored or committed)
│   └── ...                 (existing test corpus)
└── docs/superpowers/specs/
    └── 2026-05-14-ushell-statusline-design.md   (this file)
```

---

## Future work (out of scope for v1)

- **Optional ushell channel** that catches direct (non-Claude) ushell invocations. Plugin would offer a one-time setup script to install the channel under `~/.ushell/channels/ushell-status/`. Would extend coverage to "user runs ushell in a separate cmd window" case.
- **Persistent ring-buffer history** of recent ushell commands, exposed via a `/ushell-history` slash command.
- **Trace progress display** for `.run game --trace`: parse frame-capture or memory-snapshot markers from UE log.
- **ZenServer status integration**: optional 4th line showing `.zen status` if ZenServer is running.
- **BuildGraph node progress**: parse `<Node>` markers from `.uat BuildGraph` runs.

---

## Acceptance criteria (DoD for v1)

- [ ] `/plugin install ushell@ABostrom-skills` (against the new version tag) registers the statusLine and hooks automatically. No manual settings.json edits.
- [ ] Running `.cook game <P>` through Claude shows live `N/Total` progress in the statusline within 5 seconds of the cook starting emitting `LogCook` lines.
- [ ] ETA appears within 30 seconds of cook progress starting and refines as the rate stabilises.
- [ ] On cook completion, statusline transitions from active to idle, and L3 shows the last command's result with ✓/✗.
- [ ] All three progress regexes (`.cook`, `.build`, `.p4 sync`) verified against real ushell output snippets in unit tests.
- [ ] Battle test (`tests/battle-test-statusline.md`) executed end-to-end on at least one real cook of `ProjectGear`. Any findings filed as F-numbered defects with fix targets.
- [ ] Both Windows (PowerShell) and POSIX (bash) variants of the scripts ship and are exercised at least at the regex-unit-test layer.

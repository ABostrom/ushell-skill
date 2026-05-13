# Driving ushell non-interactively

ushell normally boots an interactive `cmd.exe` window. To drive it from Bash/PowerShell — i.e. as a Claude Code session — use the **scripting** invocation path.

## The launch contract

`ushell.bat` inspects how it was launched:

- **Launched from Explorer or a shortcut** → interactive: spawns its own console, host shell awaits user input.
- **Called via `cmd /d /k`, `cmd /d /s /c`, or `call` from another `.bat`** → scripting: stays in the calling shell, runs commands non-interactively, exits.

On POSIX systems the script is sourced:

```bash
source <branch>/Engine/Extras/ushell/ushell.sh
```

…which establishes ushell in the **current** bash/zsh session. Arguments after `source` follow the same rules as Windows (e.g. `--project=<path>`).

## Single-command form (Windows)

```powershell
cmd.exe /d /s /c "call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .info"
```

- `/d` skips AutoRun registry hooks; `/s` rationalises quoting; `/c` runs and exits.
- `&&` chains a single ushell verb after the bat finishes establishing itself. Multiple commands need the multi-command form below — `&&` does NOT carry into ushell's own command parser the same way.

## Multi-command form (Windows)

Write a temp `.bat`:

```bat
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.p4 sync --all
.build editor
.cook game ps5 --iterate
```

Then invoke it with `cmd.exe /d /s /c "<path_to_temp.bat>"`. Inside the bat, ushell's verbs execute sequentially; `&&` works inside ushell too (`.build editor && .cook game ps5`).

## PowerShell

For interactive use, import the PowerShell module:

```powershell
$env:PSModulePath = "$env:PSModulePath;<branch>\Engine\Extras\ushell"
Import-Module powerushell
```

…then use ushell verbs as PowerShell-friendly cmdlets. For non-interactive scripting from a PowerShell-hosted Claude session, **still go via `cmd.exe`** — the cmd-hosted scripting path is the canonical one and is what every other ushell consumer expects.

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Failure |
| `126` | Argument parse error (your bug — fix the command, don't retry) |
| `127` | Help was printed (the user asked `--help`; not a failure to surface) |
| `80` | `.p4 bisect` script protocol: "bad" CL |
| `90` | `.p4 bisect` script protocol: "failed to build" CL |

## --nosummary

Commands decorated with `Cmd.summarise` print a footer like:

```
== Result: Success
== Time: 0:00:42
```

This breaks log parsers. Suppress with `--nosummary` on the commands that **actually accept it** (decorated with `@flow.cmd.Cmd.summarise` in their source):

| Accepts `--nosummary` | Rejects `--nosummary` (errors with `Unknown argument(s)`) |
|---|---|
| `.build *` (every variant — target, editor, program, server, client, game, clean *) | `.info`, `.info projects`, `.info config` |
| `.p4 sync` | `.run *` (editor, commandlet, program, target, server, client, game) |
| `.p4 mergedown` | `.cook *` (most variants) |
| `.p4 switch` | `.cook odsc *` |
|  | `.sln *`, `.kill`, `.notify`, `.uat`, `.ushell gather`, `.getbuild`, `.ddc auth` |
|  | `.p4 cherrypick`, `.p4 clean`, `.p4 reset`, `.p4 authors`, `.p4 who`, `.p4 v` |
|  | `.zen *`, `.perf *` |

**Empirically verified on UE 5.7.** When in doubt, omit `--nosummary` — adding it to a command that doesn't accept it makes the verb exit non-zero with `Usage: [--<options>] / ERROR: Unknown argument(s) 'nosummary'`.

## Active-project propagation

The active `.uproject` is stored in a session **noticeboard** keyed by the environment variable `FLOW_SID`. Each fresh shell invocation gets a new SID, so the noticeboard is empty — meaning the active project is **not inherited from your previous session** even if you set it earlier with `.project`.

Always do one of:

1. Pass `--project=<absolute path to .uproject>` to `ushell.bat` (preferred for one-shot scripts).
2. Run `.project <path|name|cwd|auto>` as the **first** ushell command after bat establishment (preferred for multi-command bats).
3. Set `cwd` to a directory inside the project before launching, then run `.project cwd`.

`.project list` enumerates projects under the branch without switching. `.project active` prints the current active project.

## Env-var arg overrides

For any arg/opt whose value is unset (still at its default), ushell will substitute from the environment if a key of the form

```
ushell/<invoke-path>:<arg-name>
```

is set. For example, set the default build variant to `test`:

```powershell
$env:'ushell/build/editor:variant' = 'test'
```

…and `.build editor` becomes `.build editor test` for the rest of the session. Useful for site-level defaults injected from `$USERPROFILE/.ushell/hooks/startup.bat`.

## Output parsing

ushell wraps build/cook/etc. output in `_PrettyPrinter`, which colourises errors/warnings and emits `@progress` markers. Markers worth recognising:

- `@progress 'phase' N/M` — task counter; useful for progress display.
- `** For <Target> **` — per-target prefix when multiple targets build in one invocation.
- `== Errors and warnings ==` — end-of-build summary; one line per diagnostic.

For grep-friendly output, pass `--unpretty` where supported (`.cook *`, `.cook odsc *`). For machine parsing, prefer `--nosummary` plus `--unpretty`.

## Live output streaming (from Claude Code Agents)

When driving ushell from an Agent tool call, two modes give the user visibility into what's happening:

### Mode A — synchronous, full output inline

Run via Bash without `run_in_background`. The tool waits for completion, then returns the full transcript as the tool result. Good for any operation up to ~10 minutes (the Bash tool's default timeout cap).

```bash
MSYS_NO_PATHCONV=1 cmd.exe /d /s /c 'call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .build editor' 2>&1 | \
    tr -d '\r' | \
    sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g' | \
    grep -aE '\[[0-9]+/[0-9]+\]|Result:|Total time|Total execution|Cleaning|^== Run:|error C[0-9]+|fatal error|Plugin .*dependency'
```

Per-flag rationale:

| Bit | Why |
|---|---|
| `MSYS_NO_PATHCONV=1` | Stops Git Bash converting `/d /s /c` to filesystem paths |
| Single-quoted cmd string | Avoids variable expansion (cmd args may contain `$`/`%`) |
| `tr -d '\r'` | Strip CRLF → LF |
| First `sed` | Strip ANSI color codes (`\x1b[...]m`) |
| Second `sed` | Strip ANSI OSC progress codes (`\x1b]...\x07` — UBT writes these for terminal title bars) |
| `grep -aE` | `-a` = treat as text even if log has nulls; `-E` = extended regex |
| Filter pattern | Keep `[N/M]` actions, `Result:`, `Total time`, errors, plugin warnings; drop verbose line-of-the-day stuff |

### Mode B — background + Monitor (live event streaming)

For long operations (>10 min) where the user wants to see progress *as it happens* rather than at the end:

```bash
cat > /tmp/build-stream.sh << 'EOF'
#!/bin/bash
set -o pipefail
LOG=/e/Work/build-stream.log
rm -f "$LOG"
echo "STREAM_BEGIN $(date +%s)" > "$LOG"
MSYS_NO_PATHCONV=1 cmd.exe /d /s /c 'call <ushell.bat> --project=<x> && .build editor --nosummary' \
    >> "$LOG" 2>&1
echo "STREAM_END exit_code=$? $(date +%s)" >> "$LOG"
EOF
chmod +x /tmp/build-stream.sh
# Dispatch with run_in_background: true
/tmp/build-stream.sh
```

Then concurrently set up a Monitor:

```bash
touch /e/Work/build-stream.log
tail -F /e/Work/build-stream.log 2>/dev/null | \
  stdbuf -oL grep -E 'STREAM_(BEGIN|END)|\[[0-9]+/[0-9]+\]|Result: Succeeded|Result: Failed|^== Run:|error C[0-9]+:|fatal error|ERROR:|Exception while|Plugin .* dependency' | \
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == STREAM_END* ]]; then exit 0; fi
  done
```

Each matched line becomes one Monitor notification streamed to the conversation as it occurs. `stdbuf -oL` is mandatory — without it `grep` buffers in 4KB chunks and you don't see anything for minutes. The `STREAM_BEGIN`/`STREAM_END` sentinels let Monitor shut down cleanly when the build exits (vs. running to its 600s timeout).

### Choosing between A and B

- **A** when you'll act on the output as a whole (parse for failures, copy the report path, etc.). Simpler — one tool call.
- **B** when you want the user to watch live (long shipping build, cook, BuildGraph). More moving parts (two tool calls + a log file) but gives real-time event flow.

Both should ALWAYS filter to interesting lines — UBT's raw output is ~1500 lines for a 33-action build; piping that whole stream wastes context and floods the user.

---

## Forbidden moves

- **Don't `cd` inside a `cmd /d /k ushell.bat` chain.** ushell deliberately unsets `PWD` in `_call_main` (`<ushell>/channels/flow/core/system/flow/cmd.py`) because subprocess + `os.chdir + p4` had subtle bugs. Use `--project=<path>` instead.
- **Don't set `FLOW_SID` yourself.** It's set to the parent PID at boot time; overwriting it desynchronises the noticeboard.
- **Don't invoke `_build`, `_cook`, `_uat`, `_run`, or `_p4` directly.** These are ushell's internal subprocess shims used by commands that need to re-dispatch themselves (e.g. `.cook --attach` shells out to `_run commandlet cook --attach`). User-facing verbs are the dotted ones (`.build`, `.cook`, …).

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

## Forbidden moves

- **Don't `cd` inside a `cmd /d /k ushell.bat` chain.** ushell deliberately unsets `PWD` in `_call_main` (`<ushell>/channels/flow/core/system/flow/cmd.py`) because subprocess + `os.chdir + p4` had subtle bugs. Use `--project=<path>` instead.
- **Don't set `FLOW_SID` yourself.** It's set to the parent PID at boot time; overwriting it desynchronises the noticeboard.
- **Don't invoke `_build`, `_cook`, `_uat`, `_run`, or `_p4` directly.** These are ushell's internal subprocess shims used by commands that need to re-dispatch themselves (e.g. `.cook --attach` shells out to `_run commandlet cook --attach`). User-facing verbs are the dotted ones (`.build`, `.cook`, …).

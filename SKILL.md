---
name: ushell
description: Use when working in an Unreal Engine branch that contains
  Engine/Extras/ushell, or when a task involves building/cooking/staging/running
  UE targets, generating VS solutions, syncing or integrating UE Perforce
  branches, running editor commandlets (-run=...), driving UAT (RunUAT,
  BuildCookRun), managing Zen storage or DDC, running automated perf tests,
  downloading cloud builds, or authoring a new ushell channel
  (describe.flow.py, flow.cmd.Cmd / unrealcmd.Cmd subclasses). Also use when
  a ushell command fails and needs diagnosis.
---

# ushell

ushell is Epic's command-line interface for Unreal Engine, shipped at `<branch>/Engine/Extras/ushell/`. It wraps UBT, UAT, the editor, the runtime, and Perforce behind a single `.command arg arg --opts` interface with tab completion, history, and session-scoped project state.

## Iron rules

1. **If `Engine/Extras/ushell/ushell.bat` (or `.sh`) exists for the active `.uproject`, drive build infrastructure through ushell.** Do not invoke `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, `Build.bat`, or raw `p4` directly. There is no silent fallback — if a need genuinely isn't covered, stop and report.
2. **Every ushell command accepts `--help`.** Run it before guessing flags.
3. **Don't invent a command.** If `.foo` isn't in the Quick Reference below or `reference/commands.md`, look it up. Don't reach for a half-remembered RunUAT flag instead.

## Detection gate

Before doing anything else, locate ushell:

- Windows: `<branch>/Engine/Extras/ushell/ushell.bat`
- POSIX:   `<branch>/Engine/Extras/ushell/ushell.sh`

If neither exists for the active `.uproject`'s engine, **stop and tell the user.** This is an older or partial branch; ushell verbs will not exist. Do not silently fall back to raw UBT/UAT.

## Non-interactive invocation

ushell normally opens an interactive `cmd.exe` window. To drive it from a Bash/PowerShell session without that, use one of these two forms.

**Single command:**

```powershell
cmd.exe /d /s /c "call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .info --nosummary"
```

**Multiple commands — write a temp .bat:**

```bat
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.p4 sync --all
.build editor
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Failure |
| `126` | Argument parse error (treat as your bug) |
| `127` | Help printed (the user asked for help; not a failure) |
| `80` / `90` | Reserved for the `.p4 bisect` script protocol (bad / failed-build) |

Suppress the `Cmd.summarise` result/time banner with `--nosummary` on commands that have it (build, sync, mergedown, switch, …). Use this whenever you parse output.

The active `.uproject` lives in a session noticeboard keyed by `$FLOW_SID`. Every fresh invocation is a new session ID, so always pass `--project=<path>` to `ushell.bat`, or run `.project <path>` as the first command. Do NOT `cd` inside a `cmd /d /k ushell.bat` chain — ushell deliberately unsets `PWD`.

Full details and PowerShell module integration: `reference/invocation.md`.

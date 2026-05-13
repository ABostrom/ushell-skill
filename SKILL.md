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
cmd.exe /d /s /c "call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .info"
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

Suppress the `Cmd.summarise` result/time banner with `--nosummary` on commands decorated with `@summarise`: **`.build *`, `.p4 sync`, `.p4 mergedown`, `.p4 switch`** (and any future verb whose docstring or source declares it). Adding `--nosummary` to commands that don't have it (`.info`, `.run *`, `.cook *`, `.sln *`, `.kill`, `.notify`, `.uat`, `.p4 cherrypick`, `.p4 clean`, etc.) produces `ERROR: Unknown argument(s) 'nosummary'` and exits non-zero. When in doubt, omit it.

The active `.uproject` lives in a session noticeboard keyed by `$FLOW_SID`. Every fresh invocation is a new session ID, so always pass `--project=<path>` to `ushell.bat`, or run `.project <path>` as the first command. Do NOT `cd` inside a `cmd /d /k ushell.bat` chain — ushell deliberately unsets `PWD`.

Full details and PowerShell module integration: `reference/invocation.md`.

## Goal-directed planning

When the user states a **goal** (e.g. *"an Insights trace at CL X on PS5"*), do NOT jump to a single command. Walk backwards:

1. **Terminal command** — what command actually produces the goal artifact?
2. **Preconditions** — what must already exist for it to succeed?
3. **Recurse** until a precondition is already satisfied (verify with `.info`, file checks, `.zen snapshot list`, etc.).
4. **Execute forwards**, verifying after each step.

Each `reference/commands.md` entry declares **Preconditions** and **Produces**. `reference/workflows.md` provides full goal-to-plan DAGs. For anything passed after `-- <UE args>` (map URL, `#Portal` spawn selector, `-trace=<channels>`, `-ExecCmds=`, LLM/memory switches, commandlet `-run=<Name>` recipes, etc.), source the actual args from `reference/unreal-args.md` — **do not invent UE switches**.

**Skip-policy:** skip a precondition only when verifiable. Checks that count as verification:
- A `.target` receipt file exists at `Binaries/<Plat>/<Name>[-<Plat>-<Variant>].target`.
- `Saved/Cooked/<cook_form>/` exists and is non-empty.
- `.zen snapshot list <runtime> <platform>` returns a hit at the requested CL.
- `Engine/Build/Build.version` `Changelist` matches the target CL.

If the check is unclear, re-run the precondition.

**Failure-policy:** if a step fails or a precondition is truly unreachable, **stop, report the verbatim error, suggest the next action, hand back to the user.** No silent fallback to raw tools, no destructive auto-recovery (don't delete `Saved/`, don't edit `.uproject`, don't `p4 reset` without consent).

## Quick reference

| Want to… | Command |
|---|---|
| See engine/project/platform state | `.info` |
| List branch projects | `.info projects` |
| Switch active project | `.project <name\|path\|cwd\|auto>` |
| Generate VS solution | `.sln generate` |
| Open existing solution | `.sln open` |
| Open a tiny solution (fzf-only) | `.sln open tiny` |
| Build editor | `.build editor [variant]` |
| Build runtime | `.build {game\|client\|server} <platform>` |
| Build a named program | `.build program <Name>` |
| Clean before build | `.build clean editor` (etc.) |
| Single file/module build | `.build editor <Module/File.cpp>` |
| Build XML config (BuildConfiguration.xml) | `.build xml [edit\|set\|clear]` |
| Generate compile_commands.json | `.build misc clangdb` |
| Run editor | `.run editor -- <args>` |
| Run a commandlet | `.run commandlet <Name> -- <args>` |
| Run a program / named target | `.run program <Name>` / `.run target <Name>` |
| Run cooked runtime | `.run {game\|client\|server} <platform> -- <args>` |
| Run runtime with Insights trace | `.run game <P> --trace=<channels> -- <args>` |
| Cook | `.cook {game\|client\|server} <platform>` |
| Cook iteratively | `.cook game <P> --iterate` |
| ODSC shader server | `.cook odsc {game\|client\|all} <platform>` |
| Stage (auto Zen/pak) | `.stage <target> <platform> auto` |
| Stage with Zen storage | `.stage <target> <platform> zen` |
| Stage with pak files | `.stage <target> <platform> pak` |
| Deploy already-staged | `.deploy <target> <platform>` |
| Run UAT directly | `.uat <Command> -- <uat-args>` |
| BuildCookRun via UAT | `.uat BuildCookRun -- <bcr-args>` *(reference/uat.md §2)* |
| Package a plugin | `.uat BuildPlugin -- -Plugin=<path> -Package=<out> -TargetPlatforms=Win64+Linux -Rocket -StrictIncludes` |
| Run a BuildGraph script | `.uat BuildGraph -- -script=<path.xml> -target=<Node> [-set:Foo=Bar]` |
| List BuildGraph nodes | `.uat BuildGraph -- -script=<path.xml> -listonly` |
| Run Gauntlet tests | `.uat RunUnreal -- -test=<TestName> -build=<staged\|editor> -platform=<P>` |
| CI-friendly UAT baseline | append `-buildmachine -CrashForUAT -nop4 -NoCodeSign -unattended -nullrhi -utf8output -stdlog` |
| Kill running UE process | `.kill {editor\|server\|client\|<platform>}` |
| Sync from Perforce | `.p4 sync [<cl>]` |
| Filter sync (edit .p4sync.txt) | `.p4 sync edit` |
| Cherrypick CLs | `.p4 cherrypick <cl> [...]` |
| Bisect a regression | `.p4 bisect <good> <bad> -- <script>` |
| Mergedown from parent stream | `.p4 mergedown` |
| Switch stream | `.p4 switch <stream>` / `.p4 switch list` |
| List CL authors | `.p4 authors <path>` |
| Who-broke-this-line | `.p4 who <path> [<line>]` |
| Open P4V on this clientspec | `.p4 v` |
| Create a new workspace | `.p4 workspace <dir> [<depotpath>]` |
| Clean intermediate/Saved/ | `.p4 clean [--dryrun]` |
| Authorize cloud DDC | `.ddc auth [<service>]` |
| Start/stop ZenServer | `.zen start` / `.zen stop` |
| ZenServer status / version | `.zen status` / `.zen version` |
| Open Zen dashboard GUI | `.zen dashboard` |
| Create Zen workspace / share | `.zen createworkspace <dir>` / `.zen createshare <dir>` |
| Import a Zen oplog snapshot | `.zen importsnapshot <descriptor> [<index>]` |
| Find a cooked-data snapshot for CL | `.zen snapshot find <runtime> <platform>` |
| Download + import a snapshot | `.zen snapshot get <runtime> <platform> [<cl>]` |
| List available snapshots | `.zen snapshot list <runtime> <platform>` |
| Launch Insights | `.perf insights [<trace>\|latest]` |
| Run automated perf test | `.perf test {default\|sequence\|replay\|material\|camera} <platform>` |
| Download a cloud build | `.getbuild {packaged\|staged} <platform>` |
| Flash console for attention | `.notify` |
| Gather standalone ushell | `.ushell gather <destdir>` |

## Zen ↔ UAT relationship

`.zen *` commands talk to the standalone **ZenServer** process and the cloud/fileshare snapshot index. They are **not** a substitute for `.stage`. Staging still goes through UAT `BuildCookRun`, but `style=zen` (or `style=auto` driven by `Saved/Cooked/<form>/ue.projectstore`) tells UAT to package as a Zen oplog rather than pak/utoc. `.zen snapshot get` is the fast path for *"pull a pre-cooked dataset for this CL"* — it launches ZenServer if needed and imports the oplog. Always check `.zen status` before assuming Zen is running.

## Load reference when…

- Need flag/option detail on a ushell command → `reference/commands.md`
- Need a multi-step plan / DAG for a goal → `reference/workflows.md`
- Authoring a new ushell command/channel → `reference/channel-authoring.md`
- Spawning ushell yourself from a script/Bash/PS → `reference/invocation.md`
- A command failed or behaves oddly → `reference/troubleshooting.md`
- Shaping what UE itself does once launched (boot mode, map, `#Portal` spawn selector, trace channels, `-ExecCmds`, LLM/memory tracking, etc.) → `reference/unreal-args.md`
- Driving UAT directly — `BuildCookRun` recipes, `BuildPlugin`, `RunUnreal` for tests, full ProjectParams flag groups, CI-friendly invocations, packaging/signing — → `reference/uat.md`
- Authoring or invoking a BuildGraph script (schema, tasks, `-script=`, `-target=`, `-set:`, idiomatic pipelines) → `reference/buildgraph.md`

## Anti-patterns

- **Don't call `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, `Build.bat`, or raw `p4` when ushell is present.** Use `.uat`, `.build`, `.sln generate`, `.p4 *` instead.
- **Don't invent UE switches.** Common hallucinations to watch for:
  - `?StartPoint=<Name>` or `?PlayerStartTag=<Name>` — **does not exist as a UE switch**. The spawn selector is the URL `#Portal` segment: `<MapName>#<PortalTag>`. The tag must match an `APlayerStart`'s `PlayerStartTag` property. (Resolved by `AGameModeBase::FindPlayerStart_Implementation`.) See `reference/unreal-args.md` §2.
  - `-encrypt` — use `-encryptinifiles` plus `-signpak`/`-signpakid=` and `-cryptokeys=<keychain.json>`.
  - `-RunAutomationTest=` under BCR — fragile (client exits before UAT polls, reports BUILD FAILED on green tests). Use `.uat RunUnreal -- -test=UE.TargetAutomation -RunTest="<filter>"` (Gauntlet) or `.run editor -- -ExecCmds="Automation RunTests <filter>; Quit" -ReportExportPath=<dir>` instead.
  - `.engine <path>`, `.platform list` — invented ushell verbs that don't exist. The full canonical list is in `reference/commands.md`. Use `.info` to inspect engine + platforms.
- **Don't invent ushell commands.** If `.foo` isn't in the Quick Reference or `commands.md`, it doesn't exist.
- **Don't pipe `-Foo="path with spaces"` through plain subprocess argv when extending ushell** — use `unreal.cmdline.read_ueified()`. UE's quoting differs from POSIX/Windows shells; plain argv will mangle it.
- **Don't set `FLOW_SID` yourself**, and don't invoke `_build`/`_cook`/`_uat`/`_run`/`_p4` (those are ushell's internal subprocess shims, not user-facing).
- **Don't `cd` inside a `cmd /d /k ushell.bat` chain** — PWD is unset deliberately by ushell.
- **Don't use `.cook --iterate` for shipping builds** (community-confirmed stale-asset bugs). Iterative cook is for dev only; always full `-cook` for release.
- **Don't trust Project Settings → Packaging → StagingDirectory under UAT** — it's ignored. Always pass `-stagingdirectory=` and `-archive -archivedirectory=` on the CLI.
- **Channel authoring: `describe.flow.py`, not `__init__.py`.** Channels live under lowercase `channels/<name>/` and declare themselves via `flow.describe.Channel()` + `flow.describe.Command().source().invoke()` in `describe.flow.py`. See `reference/channel-authoring.md`.
- **Manual P4 bisect is wasted effort.** `.p4 bisect <good> <bad> -- <script>` exists; the script returns `0` (good), `80` (bad), or `90` (failed to build). See `commands.md` `.p4 bisect`.

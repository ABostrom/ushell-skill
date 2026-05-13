# `ushell` skill — design spec

Authored: 2026-05-13
Working tree: `E:\Work\ushell-skill\`
Reference engine tree (for grounding): `E:\UE_5.7\Engine\Extras\ushell\`

---

## 1. Purpose

A Claude Code skill that lets future Claude sessions drive **ushell** — Epic's command-line interface for Unreal Engine, shipped at `Engine/Extras/ushell` — competently, end-to-end, including:

- **Day-to-day UE workflows** (sync, build, run, cook, stage, deploy, perf, profiling).
- **Goal-directed planning**: when the user states an outcome (e.g. *"get me an Insights trace at CL X on PS5"*), Claude walks the dependency graph backwards from the goal to the current state, then executes forwards, skipping work already done.
- **Channel authoring**: extending ushell with new `.mychan ...` commands by writing `describe.flow.py` + `unrealcmd.Cmd` subclasses.
- **Troubleshooting** when a ushell command fails.

The skill makes ushell the **single way** Claude interacts with UE build infrastructure when a ushell-equipped branch is present — replacing raw `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, and direct `p4` calls.

## 2. Non-goals

- Skills for engine-source modification, asset workflows, Blueprint editing, gameplay code — out of scope.
- Replacing the engine docs themselves — this is a *usage* skill, not a UE reference manual.
- Wrapping ushell in a separate executable (Option C from brainstorming was deferred — may be revisited if baseline testing shows Claude consistently mangles non-interactive invocation).
- Cross-platform parity guarantee for every command — the skill targets Windows primarily, with POSIX paths noted where they differ. The user works on Windows.

## 3. Identity & trigger

**Slug:** `ushell`

**Frontmatter:**

```yaml
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
```

**Rationale.** The description encodes only *when to use*, never *what the skill does* — per writing-skills CSO guidance. It anchors on observable cues (presence of `Engine/Extras/ushell`, mention of `.uproject`, mention of the raw tools Claude is otherwise tempted to reach for), plus the commandlet keyword path, the Zen/DDC path, and the channel-authoring trigger phrases. No workflow summary.

**Detection gate** (encoded in SKILL.md body): the skill body must early-out if `Engine/Extras/ushell/ushell.bat` (or `ushell.sh` on POSIX) cannot be located relative to the active `.uproject` or current directory. Older UE branches and content-only projects without an engine in-tree don't have ushell; the skill must NOT invent commands in those contexts.

## 4. File layout

```
ushell-skill/                              (=E:\Work\ushell-skill\)
  SKILL.md                                 always-loaded; ~250 words of prose
  reference/
    commands.md                            per-command pages (all ~60 verbs)
    invocation.md                          driving ushell non-interactively
    workflows.md                           goal-first DAG catalogue
    channel-authoring.md                   writing new commands/channels
    troubleshooting.md                     symptom-keyed diagnostics
    unreal-args.md                         UE's own CLI lexicon — boot modes,
                                           map URL syntax, -trace channels,
                                           -ExecCmds, common engine switches.
                                           Loaded when shaping what gets
                                           passed after `-- <args>`.
    uat.md                                 UAT command catalogue —
                                           BuildCookRun (with full
                                           ProjectParams flag groups), the
                                           other ~45 RunUAT commands
                                           (BuildPlugin, BuildTarget,
                                           SyncProject, ResavePackages, etc),
                                           Gauntlet test driving via RunUnreal,
                                           shipping/CI recipes, and
                                           community-confirmed gotchas.
    buildgraph.md                          BuildGraph reference — schema
                                           (Agent/Node/Trigger/Task), the
                                           ~50 built-in tasks, idiomatic
                                           script patterns, CookedEditor +
                                           LiveLinkHub case studies, and
                                           ushell ↔ BuildGraph plumbing.
  tests/
    baseline.md                            RED prompts (subagent, no skill)
    with-skill.md                          GREEN prompts (subagent, skill on)
    notes.md                               verbatim rationalisations captured
                                           during RED runs; used to tighten skill
  docs/superpowers/specs/                  (this directory)
    2026-05-13-ushell-skill-design.md      this file
  ue5-launch-with-spawn-point.md           user-authored seed content for
                                           reference/unreal-args.md §2
                                           (FURL grammar + PlayerStart
                                           Portal resolution; full call
                                           stack and code refs)
```

**Install target** (later, post-test): copy/symlink the working tree's content into `~/.claude/skills/ushell/` so it loads in every Claude Code session. The working tree at `E:\Work\ushell-skill\` remains the source of truth.

## 5. SKILL.md body (always-loaded surface)

Six tight chunks. Target: ≤250 words of prose between the frontmatter and the end of the body, plus the quick-reference table.

### 5.1 Iron rules

1. If `Engine/Extras/ushell/ushell.bat` (or `.sh`) exists for the active `.uproject`, prefer ushell over raw `RunUAT.bat` / `UnrealBuildTool.exe` / `GenerateProjectFiles.bat` / direct `p4`. **No silent fallback to raw tools.**
2. Every ushell command accepts `--help`. **Run it before guessing flags.**
3. Don't invent a command. If `.foo` isn't in the Quick Reference or `reference/commands.md`, look it up.

### 5.2 Detection gate

```
Locate ushell:
  <branch>/Engine/Extras/ushell/ushell.bat        (Windows)
  <branch>/Engine/Extras/ushell/ushell.sh         (POSIX)
If neither exists for the active .uproject:
  STOP and tell the user. Do not run raw UBT/UAT.
```

### 5.3 Non-interactive invocation (the canonical recipe)

```powershell
# Single command — Windows:
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .info --nosummary"

# Multiple commands — write a temp .bat:
@echo off
call <ushell.bat> --project=<uproject>
.p4 sync --all
.build editor
```

Exit codes: `0` success · `1` failure · `126` bad args · `127` help printed · `80`/`90` are reserved by `.p4 bisect` script protocol.

Suppress the result/time banner with `--nosummary` on commands that use `Cmd.summarise` (build, sync, mergedown, switch, …) — required for clean log parsing.

### 5.4 Goal-directed planning rule

> When the user states a **goal** (e.g. "Insights trace at CL X on PS5"), do NOT jump to a single command. Walk backwards:
> 1. **Terminal command** — what command actually produces the goal artifact?
> 2. **Preconditions** — what must already exist for it to succeed?
> 3. **Recurse** until a precondition is already satisfied (verify with `.info`, file checks, `.zen snapshot list`, etc.).
> 4. **Execute forwards**, verifying after each step.
>
> Each `reference/commands.md` entry declares **Preconditions** and **Produces**. `reference/workflows.md` provides full goal-to-plan DAGs. For anything that ends up after `-- <UE args>` (map URL, `?StartPoint=`, `-trace=<channels>`, `-ExecCmds=`, LLM/memory switches, commandlet `-run=<Name>` recipes, etc.), source the actual args from `reference/unreal-args.md` — do **not** invent UE switches.
>
> **Skip-policy:** skip a precondition only when verifiable (a `.target` receipt exists, `Saved/Cooked/<form>/` is non-empty, `.zen snapshot list` returns a hit at the requested CL, `Engine/Build/Build.version` matches, etc.). If the check is unclear, re-run.
>
> **Failure-policy:** if a step fails or a precondition is truly unreachable, **stop, report verbatim error, suggest next action, hand back to user.** No silent fallbacks, no destructive auto-recovery.

### 5.5 Quick reference table

Single table, ~40 rows, covering the most-reached-for verbs across the unreal and perforce channels. Sorted by surface area (build → run → cook → stage → uat → sln → info → project → p4 → zen → perf → ddc → getbuild → ushell gather → notify).

Body of the table is the union of the table presented in the brainstorm Section 2 plus the Zen-row patch from the Zen-feedback round. Notable rows (representative — full list lives in the file):

| Want to… | Command |
|---|---|
| See engine/project/platform state | `.info` |
| Switch active project | `.project <name\|path\|cwd\|auto>` |
| Generate VS solution | `.sln generate` |
| Build editor | `.build editor [variant]` |
| Build runtime | `.build {game\|client\|server} <platform>` |
| Run a commandlet | `.run commandlet <Name> -- <args>` |
| Cook | `.cook {game\|client\|server} <platform>` |
| Stage (auto Zen/pak) | `.stage <target> <platform> auto` |
| Stage with Zen storage | `.stage <target> <platform> zen` |
| Run UAT directly | `.uat <Command> -- <uat-args>` |
| BuildCookRun via UAT | `.uat BuildCookRun -- <bcr-args>` (see uat.md §A) |
| Package a plugin | `.uat BuildPlugin -- -Plugin=<path> -Package=<out> -TargetPlatforms=Win64+Linux -Rocket -StrictIncludes` |
| Run a BuildGraph script | `.uat BuildGraph -- -script=<path.xml> -target=<Node> [-set:Foo=Bar]` |
| List nodes in a BuildGraph | `.uat BuildGraph -- -script=<path.xml> -listonly` |
| Run Gauntlet tests | `.uat RunUnreal -- -test=<TestName> -build=<staged|editor> -platform=<P> -configuration=<C>` |
| CI-friendly BCR baseline | append `-buildmachine -CrashForUAT -nop4 -NoCodeSign -unattended -nullrhi -utf8output -stdlog` |
| Sync from Perforce | `.p4 sync [<cl>]` |
| Cherrypick CLs | `.p4 cherrypick <cl> [...]` |
| Bisect a regression | `.p4 bisect <good> <bad> -- <script>` |
| Mergedown from parent stream | `.p4 mergedown` |
| Start/stop ZenServer | `.zen start` / `.zen stop` |
| Pull pre-cooked snapshot for CL | `.zen snapshot get <runtime> <platform> [<cl>]` |
| List snapshots | `.zen snapshot list <runtime> <platform>` |
| Launch Insights | `.perf insights [trace\|latest]` |
| Run automated perf test | `.perf test {default\|sequence\|replay\|material\|camera}` |
| Download a cloud build | `.getbuild {packaged\|staged} <platform>` |
| Authorize cloud DDC | `.ddc auth [<service>]` |

### 5.6 Zen ↔ UAT relationship (inline note — high salience)

> ushell's `.zen *` commands talk to the standalone **ZenServer** process and the cloud/fileshare snapshot index. They are **not** a substitute for `.stage`. Staging still goes through UAT `BuildCookRun`, but `style=zen` (or `style=auto` driven by `Saved/Cooked/<form>/ue.projectstore`) tells UAT to package as a Zen oplog rather than pak/utoc. `.zen snapshot get` is the fast path for "pull a pre-cooked dataset for this CL" — it launches ZenServer if needed and imports the oplog. Always check `.zen status` before assuming Zen is running.

### 5.7 "Load reference when…"

- Need flag/option detail on a ushell command → `reference/commands.md`
- Need a multi-step plan / DAG → `reference/workflows.md`
- Authoring a new ushell command/channel → `reference/channel-authoring.md`
- Spawning ushell yourself from a script/Bash/PS → `reference/invocation.md`
- A command failed or behaves oddly → `reference/troubleshooting.md`
- Need to shape what UE itself does once launched (boot mode, map, start
  point, trace channels, `-ExecCmds`, low-memory tracking, etc.) →
  `reference/unreal-args.md`
- Driving UAT directly — `BuildCookRun` recipes, `BuildPlugin`, `RunUnreal`
  for tests, full ProjectParams flag groups, CI-friendly invocations,
  packaging/signing — → `reference/uat.md`
- Authoring or invoking a BuildGraph script (schema, tasks, `-script=`,
  `-target=`, `-set:`, idiomatic pipelines) → `reference/buildgraph.md`

### 5.8 Anti-patterns

- Don't call `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, or raw `p4` when ushell is present.
- Don't pipe `-Foo="path with spaces"` through plain subprocess argv when extending ushell — use `unreal.cmdline.read_ueified()`.
- Don't set `FLOW_SID` yourself, and don't invoke `_build`/`_cook`/`_uat`/`_run`/`_p4` (internal subprocess shims).
- Don't `cd` inside a `cmd /d/k ushell.bat` chain — PWD is unset deliberately by ushell.

## 6. `reference/commands.md` template & coverage

Every command page follows this template:

```markdown
## `.<words>` — <one-line purpose>

**When:** <triggering need>

**Usage:** `.<words> <positional1> [<positional2>] [-- <passthrough>]`

**Args:** name : type/choices/default : description (one per line)
**Flags:** --flag : type/default : description (one per line)

**Preconditions:** <what must be true before this command will succeed>
**Produces:** <artifacts left on disk / state changes>

**Implicit behaviour:** <auto-injected flags, target munging, env setup, etc.>

**Common pitfalls:** <bullet list>

**Examples:** <2-5 grounded examples>
```

**Coverage at v1:** all registered verbs in `unreal/core` and `unreal/perforce` channels — approximately 60 entries. The brainstorming exploration produced verbatim catalogues for each; those are the seed material.

The **Preconditions/Produces** fields are what make the dependency graph computable for goal-directed planning (Section 5.4).

## 7. `reference/invocation.md` outline

1. The launch contract (Explorer/shortcut → interactive; `cmd /d/k` or `call` → scripting).
2. Single-command form on Windows.
3. Multi-command form via temp `.bat`.
4. PowerShell: `Import-Module powerushell` for interactive; cmd.exe shim for scripting.
5. Exit-code cheatsheet (0/1/126/127/80/90).
6. `--nosummary` for clean log parsing.
7. Active-project propagation: noticeboard keyed by `$FLOW_SID`; every Claude session is a new SID, so always pass `--project=` or run `.project` first.
8. Env-var arg overrides: `ushell/<invoke_path>:<arg>=value`.
9. Output parsing: `_PrettyPrinter` markers (`@progress`, `Errors and warnings`, `** For X **`); `--unpretty` where supported for grep-friendly output.
10. Forbidden moves (don't `cd` inside a chain, don't set `FLOW_SID`, don't call `_*` internal shims).

## 8. `reference/workflows.md` — goal-first DAGs

Each entry uses this structure:

```
GOAL: <one-line outcome>

Terminal: <command that produces the goal>
  Preconditions:
    [A] <precondition>
        → <command to satisfy it>
           Preconditions: …
    [B] <precondition>
        → <command> -- OR -- <alternative command>

Post: <where the artifact ends up, how to consume it>

Skip-conditions:
  • <how to verify each precondition is already satisfied>
```

**Entries at v1** (≤30 lines each):

1. **Insights trace at CL X on platform P** *(the user's motivating example; canonical worked example)*
2. **Reproduce a crash at CL X** — sync · build editor · `.run editor --attach -- <args>`
3. **Profile shipping build on platform P at CL X** — generalisation of #1
4. **Find the CL that broke the editor** — `.p4 bisect` with build-and-run.bat script
5. **Fresh sync → build → run editor** — the everyday loop
6. **Stream switch + minimal verify**
7. **Cook + stage + run on a target platform (with Zen)**
8. **Pull pre-cooked data for this CL via `.zen snapshot get`**
9. **Cherrypick a CL across streams**
10. **Run an automated perf test (`.perf test sequence`)**
11. **Generate a Visual Studio solution and open it (with `tiny` fallback)**
12. **Drive a commandlet (`.run commandlet ResavePackages -- -PackageDir=…`)**
13. **Run `BuildCookRun` directly via `.uat`** — when wrapped `.stage`/`.cook` doesn't fit
14. **Clean a branch safely (`.p4 clean --dryrun` → `.p4 clean`)**

The Insights-trace entry is reproduced in full in §10 of this spec (test fixture rubric).

## 9. `reference/channel-authoring.md` outline

Anchored to real files in the engine tree so a maintainer can re-verify on UE version bumps.

1. **Skeleton**: `channels/<name>/{describe.flow.py, cmds/<x>.py}`; optional `pylib/`, `boot.py`, `prompt.py`, `tips.py`. `pylib/` auto-added to `sys.path`. Channel discovery by directory layout.
2. **`describe.flow.py` annotated** — working example with `Channel().parent("unreal.core").version("1")`, `Command().source(...).invoke(...).prefix(...)`, one `Tool().bundle().payload().bin().sha1()` registration.
3. **Authoring a command** — subclass `unrealcmd.Cmd` / `unrealcmd.MultiPlatformCmd`; declare `Arg` / `Opt`; implement `complete_<arg>`; return exit code from `main`. **`@flow.cmd.Cmd.summarise`** decorator. **No `bool` or raw `tuple` as positional Arg types.** Tri-state `Opt((default, implicit))` for "--name" with optional value.
4. **Driving a commandlet from your channel** — the canonical inlined pattern (no `make_commandlet()` helper exists). Includes:
   - Editor target lookup: `ue_context.get_target_by_type(unreal.TargetType.EDITOR).get_build(variant=…).get_binary_path()`
   - `.exe` → `-Cmd.exe` swap (commandlets need stdout)
   - `args = (project.get_path(), "-run=Name", *unreal.cmdline.read_ueified(*forwarded))`
   - `self.get_exec_context().create_runnable(binary, *args)` + `uelogprinter.Printer().run(cmd)` for interactive runs
   - The `--attach` shortcut via `subprocess.run(("_run", "commandlet", Name, "--attach", "--", ...))` — reuses `.run commandlet`'s debugger plumbing
5. **Driving UAT from your channel** — `subprocess.run(("_uat", "BuildCookRun", "--", ...))` vs. calling `RunUAT.bat` directly (don't).
6. **Deps & distribution** — pure-Python deps under `pylib/`; binaries via `Tool` with sha1; **pips are deprecated, do not use**. Site-level install paths: `$USERPROFILE/.ushell/`, `<branch>/Engine/Platforms/<Name>/Extras/ushell/platform_*.py` for platform plugins, `.ushell gather` for standalone bundles consumable by UGS.
7. **Boot/prompt/tip hooks** — `invoke("boot")` / `invoke("prompt")` / `invoke("tip")` with `prefix("$")`; chain via `super().run(env)` / `super().prompt(context)` / `super().get_tips()`.
8. **Smallest viable channel template** — copy-pasteable; ~20 lines total.

## 10. `reference/troubleshooting.md` — symptom-keyed entries

Each entry: *Symptom* → *Likely cause* → *Resolution*. Seed list:

- `Unable to establish an Unreal context from directory '...'` → noticeboard empty / no `.uproject` reachable → `--project=<path>` or `.project <path>`.
- `No valid Perforce session found. Run 'p4 login' to authenticate.` → P4 session expired → `p4 login`, retry.
- `Client 'X' is not a stream` → `.p4 switch`/`.p4 mergedown` require stream client → use a stream-mapped workspace.
- "`ushell.bat` opened a new window and exited" → launched from Explorer/shortcut without scripting form → use `cmd /d/k call <ushell.bat>` or temp `.bat`.
- Hang on `.cook` → likely shader compile; check `.zen status`, try `--noxge` and `--unpretty`.
- `.run editor --attach` shows nothing → debugger detached on hot-reload → ensure `.sln open` ran first; check `USHELL_DEBUGGER`.
- `.stage` complains about `ue.projectstore` → Zen marker mismatch → pick `style=pak` or `style=zen` explicitly.
- `.p4 sync` says client is `*unknown*` → fix `P4CLIENT` in local `.p4config.txt` (or run `ensure_p4config` via the `.project` re-bind).
- `RunUAT.bat: not found` from inside `.uat` → branch missing `Engine/Build/BatchFiles/`; engine tree is broken or partial sync.
- Tab completion empty for `.build target` → `Source/*.Target.cs` not synced or not generated; run `.p4 sync` then `.sln generate`.
- `Unable to establish branch root` from `.p4 *` → P4 server doesn't have the engine path; check workspace view.

## 10.5 `reference/unreal-args.md` — UE's own CLI lexicon

ushell wraps the *outer* pipeline, but most useful goals require shaping
what UE itself does once it's running — and those arguments are passed
through the ushell `-- <args>` boundary into the editor / runtime / commandlet
binary directly. This reference exists so Claude can compose those args
correctly without guessing.

**Sections:**

1. **Boot modes.** How a UE binary decides what it is:
   - First positional after the binary: a `.uproject` path (project context) or a map URL.
   - `-server`, `-server -log` (dedicated server).
   - `-game` (client/standalone game from editor binary).
   - `-run=<CommandletName>` (commandlet on `<Editor>-Cmd.exe`).
   - `-listen` / `?Listen` (listen server).
   - Headless/automation flavour: `-nullrhi -unattended -stdout -log`.

2. **Map URL syntax** (positional arg after the `.uproject`, parsed by `FURL::Parse` in `Engine/Source/Runtime/Engine/Private/URL.cpp`). Grammar:
   ```
   Protocol://Host:Port/Map#Portal?Option1=Value1?Option2=Value2
   ```
   For local launches: `Map#Portal?Key=Value?Key=Value`. The `#Portal` segment is the spawn selector — **not** a `?` option.
   - `<MapName>` — load the map at the default `PlayerStart`.
   - `<MapName>#<Portal>` — spawn at the `APlayerStart` actor whose `PlayerStartTag` (FName) matches `<Portal>`. Resolved by `AGameModeBase::FindPlayerStart_Implementation`.
   - `<MapName>?Game=<GameModeClass>` — override the gamemode class.
   - `<MapName>?Listen` — host as listen server.
   - `<MapName>?Name=<PlayerName>` — player display name (truncated to 20 chars); **NOT** a spawn selector.
   - `<MapName>?<KeyN>=<ValueN>` — arbitrary options consumed by `GameMode`/`GameState` via `UGameplayStatics::ParseOption`.

   Gotchas:
   - Custom `GameMode` overrides of `ChoosePlayerStart` / `FindPlayerStart` that don't honour `IncomingName` will silently ignore the Portal — the engine falls through to `ChoosePlayerStart` and looks like "Portal didn't work."
   - PIE doesn't use the command-line URL; PIE constructs its own. Test with `-game` (standalone) or against a packaged build.
   - `PlayerStartTag` matching is FName-based (practically case-insensitive). Match the authored casing anyway.

   Canonical seed content for this section: `ue5-launch-with-spawn-point.md` at the working-tree root, written by the user, with full call-stack from `UWorld::SpawnPlayActor` → `AGameModeBase::Login` → `InitNewPlayer` → `UpdatePlayerStartSpot` → `FindPlayerStart_Implementation` and code references in `World.cpp` / `GameModeBase.cpp`. **Move that file into `reference/` (or inline its content into `unreal-args.md` §2) during implementation.**

3. **Trace / Insights.** `-trace=<channels-csv>` with the canonical channel list:
   `default, log, frame, bookmark, screenshot, stats, gpu, memory, memtag,
   cpu, animation, slate, csv, file, loadtime, savegame, taskgraph,
   counters, regions, rendercommands, audiomixer`.
   Companion args: `-tracehost=<ip>` (live host stream), `-traceFile=<path>`
   (write to disk), `-statnamedevents` (CSV-friendly), `-statunitcsv` (csv
   profiler). LLM memory tracking adds `-llm` (and `-llm.AutoReportMemory`
   for periodic dumps).

4. **`-ExecCmds=`.** Run a semicolon-separated list of console commands
   after boot. Canonical example: `-ExecCmds="Automation RunTests <suite>;Quit"`.
   Quoting rules: pass through `unreal.cmdline.read_ueified()` when
   constructing from a channel; in shell scripts, double-quote and escape
   embedded `"` per the host shell's rules.

5. **Rendering / windowing.** `-Windowed`, `-FullScreen`, `-ResX=<n>`,
   `-ResY=<n>`, `-Resolution=<WxH>`, `-WindowedFullScreen`, `-RHI=<name>`
   (`-DX12`/`-DX11`/`-Vulkan`/`-OpenGL` as shortcuts), `-NoVSync`,
   `-FrameLimit=<fps>`, `-MaxFps=<fps>`.

6. **Performance / determinism.** `-deterministic`, `-FixedSeed`,
   `-StompMalloc`, `-PoisonOSMemory`, `-MemoryProfiler`, `-CrashForUAT`,
   `-NoTextureStreaming`, `-AllowSoftwareRendering`.

7. **Logging.** `-log` (engine log to console), `-LogCmds="LogX Verbose, LogY VeryVerbose"`,
   `-AbsLog=<path>`, `-NoConsole`, `-stdout`, `-LogLine=<text>`,
   `-Verbose`, `-VeryVerbose`.

8. **Cooking-specific** (mirrors what `.cook` injects; useful when calling
   the commandlet directly via `.run commandlet cook`): `-targetplatform=`,
   `-cookcultures=`, `-iterate`, `-forcerecook=false`, `-unattended`,
   `-unversioned`, `-stdout`, `-cookonthefly`, `-noxgeshadercompile`,
   `-PackageDir=`, `-Map=`, `-SkipCookedPackages`.

9. **Stage / run-cooked specific** (mirrors what `.stage`/`.run game` injects):
   `-pak`, `-skipbuild`, `-skipcook`, `-skipstage`, `-deploy`, `-onthefly`,
   `-filehostip=`, `-cookflavor=`, `-platform=`, `-config=`.

10. **Networking / multiplayer client boot.** `-CONNECT=<ip[:port]>`,
    `?Game=<GameMode>?Listen`, `-port=`, `-multihome=`.

11. **Common commandlet `-run=<Name>` recipes.** With required/typical args:
    - `-run=Cook -targetplatform=Win64 -unattended -unversioned`
    - `-run=ResavePackages -PackageDir=<dir> [-AutoCheckOutPackages]`
    - `-run=DerivedDataCache -fill -unattended`
    - `-run=GenerateDistillFileSets`
    - `-run=PluginCommandlet`
    - `-run=DumpFormalTechDebt`
    - and others as identified during baseline testing.

12. **Discovering args for a specific project.** Where to look:
    - `Config/Default*.ini` — many feature toggles use `[Sections]` that map
      to CLI overrides (e.g. `-ini:Engine:[/Script/Engine.Engine]:GameViewportClientClassName=...`).
    - `[/Script/AutomatedPerfTesting.*PerfTestProjectSettings]` for the
      `MapsAndSequencesToTest`, `MapsToTest`, `ReplaysToTest`, `SequenceCombos`
      arrays — feeds `.perf test`.
    - `Source/<Project>/Private/<Project>GameInstance.cpp` and `*GameMode*.cpp`
      for project-specific `FParse::Param`/`FParse::Value` callers (gives
      you the project's bespoke switches like `-stresstest=...`).
    - Engine-side: `Engine/Source/Runtime/Launch/Private/Launch*.cpp` and
      `Engine/Source/Runtime/CoreUObject/Private/UObject/UObjectGlobals.cpp`
      for the standard switches.

13. **Goal → required UE args quick map** (for compositional reasoning):

    | Goal | UE args (after `-- ` in ushell) |
    |---|---|
    | Capture Insights trace to disk | `-trace=<channels> -traceFile=<path>` |
    | Capture Insights trace to live host | `-trace=<channels> -tracehost=<ip>` |
    | Spawn at a specific PlayerStart | `<MapName>#<PortalTag>` (matches `APlayerStart::PlayerStartTag`; **not** `?StartPoint=`) |
    | Headless automation run | `-nullrhi -unattended -stdout -log` |
    | Run console cmds and quit | `-ExecCmds="cmd1;cmd2;Quit"` |
    | Dedicated server | `-server -log [<MapName>?Listen]` |
    | Wait for debugger to attach | `-WaitForDebugger` |
    | LLM memory profile | `-llm -llm.AutoReportMemory -trace=memory,memtag` |
    | Force a render API | `-DX12` (or `-Vulkan`, `-OpenGL`) |
    | Specific resolution | `-Windowed -ResX=1920 -ResY=1080` |
    | Skip startup map | `-NoLoadStartupPackages` |
    | Cook a single map only | `-run=Cook -targetplatform=<P> -Map=<MapName>` |

This file is consulted at *plan composition* time, not just at flag-lookup
time: whenever `workflows.md` shows a DAG node like `.run game <P> -- <UE args>`,
the contents of `<UE args>` are sourced from this file rather than invented.

## 10.6 `reference/uat.md` — UAT command catalogue

ushell's `.uat` is the wrapper; UAT is the underlying tool that does the work. The skill needs deep UAT competence because Claude will need to drive it directly when ushell's higher-level wrappers (`.build`, `.cook`, `.stage`) don't fit the request — e.g. when shipping, signing, packaging plugins, running BuildGraph pipelines, or building CI invocations.

Source material for this file lives in `docs/superpowers/specs/research-notes-uat.md` (digest of five parallel research agents covering BuildCookRun, the other ~45 UAT scripts, Gauntlet testing, and community usage). That file is the seed — `uat.md` is written by re-organising and expanding it.

**Sections:**

1. **The UAT contract.** `RunUAT.bat` / `RunUAT.sh` entry; argv is `<CommandName> -Name=Value ...`; how UAT discovers scripts under `Engine/Source/Programs/AutomationTool/Scripts/*.Automation.cs` (and `<branch>/Engine/Source/Programs/AutomationTool/Scripts/`); exit-code conventions.
2. **BuildCookRun deep-dive.** The seven verbs (`Build → Cook → Stage → Package → Archive → Deploy → Run`) in fixed execution order. Full ProjectParams flag groups (build / cook / stage / package / archive / deploy / run / paks / iostore / zen / paks-encryption / CI). 15 idiomatic recipes covering editor-only, dev client, dev server, shipping, IoStore, Zen, distribution build, iterative cook, automation tests, multi-platform, cooked-editor, mobile.
3. **The other UAT commands.** Per-command entries grouped by lifecycle area: Plugin (BuildPlugin), Engine/tool (BuildCommonTools, BuildTarget, BuildCMakeLib, BuildHlslcc, BuildThirdPartyLibs), Project (SyncProject, SyncBinariesFromUGS, UpdateLocalVersion, OpenEditor), Content (ResavePackages, FixupRedirects, RebuildHLOD, RebuildLightMaps, WorldPartitionBuilder, WrangleContentForDebugging), Localisation, Build infra (BuildDerivedDataCache, Virtualization, CopySharedCookedBuild, CleanFormalBuilds, Bisect), Packaging/signing (ExtractPaks, CryptoKeys, IPhonePackager, UnsignedFilesViolationCheck), Mobile/Apple (GenerateDSYM, ListMobileDevices, SetSecondaryRemoteMac), Multi-process (LaunchMultiServer, MultiClientLauncher), Perf (BenchmarkBuild, RecordPerformance), Utility (GetFileCommand, ZipUtils, AnalyzeThirdPartyLibs, ListThirdPartySoftware, DedupeAutomationScripts, MegaXGE, StageLiveLinkHub).
4. **Testing via UAT (Gauntlet).** RunUnreal is the launcher (no separate RunGauntlet). Test selector grammar (`-test=Name(K=V,K=V),Name2`). Default namespaces. Important test nodes (`UE.EditorAutomation`, `UE.TargetAutomation`, `UE.BootTest`). Report output (`-ReportExportPath=<dir>/index.json`) and the JUnit gotcha (no native JUnit; post-process JSON or use RunLowLevelTests for Catch2). The `.perf test` → `RunUnreal -test=AutomatedPerfTest.*` mapping (canonical seed: `Engine/Extras/ushell/channels/unreal/core/cmds/perftest.py:217-237`). Failure modes (crash, hang via log-idle, no-matching-tests, devkit disconnect).
5. **Engine-side `Automation` exec command.** The verbs (`List`, `RunTests <spec>`, `RunFilter <flag>`, `SetPriority`, `Quit`, `SoftQuit`, etc.) and filter syntax (`Group:`, `StartsWith:`, `^anchor`, `anchor$`, bare substring). For when you bypass Gauntlet and drive the editor directly via `.run editor -- -ExecCmds="Automation RunTests X; Quit" -ReportExportPath=<dir>`.
6. **Canonical shipping/CI invocations.** The "build my game for shipping" recipe (with `-target=`, `-pak -iostore -compressed`, `-archive -archivedirectory=`, `-prereqs -nodebuginfo`). The CI flag tetrad (`-buildmachine -CrashForUAT -unattended -nop4 -NoCodeSign -utf8output -stdlog`). The plugin-packaging recipe (`BuildPlugin -Plugin= -Package= -TargetPlatforms= -Rocket -StrictIncludes`).
7. **Top community gotchas.** `-platform=` vs `-targetplatform=` vs `-clientconfig=` vs `-configuration=` confusion. `BuildPlugin` building every detected SDK by default since 4.25 (must pass `-TargetPlatforms=`). `-pak` / `-iostore` / `-zenstore` interaction subtleties. `-iterate` staleness — never for shipping. Project Settings StagingDirectory ignored — always pass `-stagingdirectory=`. `-buildmachine` as the CI must-have. `-RunAutomationTest=` under BCR being fragile — prefer Gauntlet RunUnreal or direct editor `-ExecCmds=`.
8. **Sources of truth.** Pointer table: when --help is wrong, read these files (`ProjectParams.cs`, `BuildCookRun.Automation.cs`, `BuildPluginCommand.Automation.cs`, `Gauntlet.UnrealTestContext.cs`, `UE.Automation.cs`, `AutomationCommandline.cpp`, `AutomationTest.h`).
9. **Public CI examples to cite.** botman99's reference doc, vela-games CircleCI BuildGraph, the GHA `ue5-build-project` action, Guganana plugin CI, Jenkins/TeamCity references — for showing Claude the shapes real projects use.

## 10.7 `reference/buildgraph.md` — BuildGraph reference

BuildGraph is UAT's meta-orchestration layer: an XML-described directed graph of Nodes (sequences of Tasks), Agents (lanes), and Triggers. Worth its own file because the schema + the ~50 built-in tasks + idiomatic patterns are substantial and distinct from BCR-style direct invocations.

Source material: the same `research-notes-uat.md` digest (section C), plus the two shipped example BuildGraph scripts inside the engine tree:
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/CookedEditor/EpicGames.BuildGraph.xml`
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/LiveLinkHub/EpicGames.BuildGraph.xml`
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/Platforms/Windows/EpicGames.BuildGraph.xml`

**Sections:**

1. **What BuildGraph is.** One-paragraph framing. Quote `BuildGraph.cs:206-235` class comment.
2. **CLI signature.** `.uat BuildGraph -- -script=<path> -target=<Node> [-set:Foo=Bar] [-listonly|-singlenode=|-resume|-clean|-cleannode=|-noxge|-noPCH|-tokensignal=|-storage=|-writetoshareddir|-validate|-export=]`.
3. **Schema elements.** `<BuildGraph>`, `<Property>`, `<Option>`, `<Agent>`, `<Node>` (with `Requires`, `Produces`, `After`, `RunEarly`, `NotifyOnWarnings`), `<Aggregate>`, `<Trigger>`, `<Label>`, `<Include>`, `<Macro>` + `<Expand>`, `<Notify>`, `<Annotation>`, `<EnvVar>`, `<Warning>`/`<Error>`, conditional `If="..."`.
4. **Built-in tasks reference.** ~50 task elements grouped by purpose: Build (`<Compile>`, `<CsCompile>`), Cook/Stage/Pak (`<Cook>`, `<Stage>`, `<Pak>`, `<IoStore>`), File ops (`<Copy>`, `<Delete>`, `<Tag>`, `<Untag>`, `<Zip>`, `<Unzip>`), Composition (`<Command>` to invoke other UAT, `<Commandlet>` to invoke editor commandlets), Artifacts (`<CreateArtifact>`, `<CreateCloudArtifact>`), Cloud/deploy (`<AwsAssumeRole>`, `<AwsEcsDeploy>`, `<DockerBuild>`, `<DeployTool>`), Source control (`<Submit>`, `<Sync>`), Misc (`<Log>`, `<Sleep>`, `<HordeCreateReport>`).
5. **Property/macro/include idioms.** Reusable patterns observed in the shipped scripts.
6. **Case study: CookedEditor.** Walk through the script — what it produces, the node graph, notable patterns.
7. **Case study: LiveLinkHub.** Same — a multi-platform stage/archive pipeline.
8. **Idiomatic recipes.** Eight 15-30 line BuildGraph skeletons covering: multi-platform parallel build/cook, plugin build+test+archive, sync+build+test+Horde report, multi-platform shipping (PC + dedicated server + mobile), nightly iterative cook, plugin marketplace packaging, per-PR validation, Cloud DDC fill.
9. **ushell ↔ BuildGraph.** `.uat BuildGraph -- -script=... -target=... -set:Foo=Bar`. ushell adds `-project=` automatically (unless `--unprojected`).
10. **Gotchas.** `<Command Name="BuildCookRun">` doesn't inherit `-project=` from the graph — pass explicitly. XGE/SN-DBS/FastBuild auto-detection (`-noxge` to disable). `<Submit>` needs `-AllowSubmit -Submit` at the BuildGraph CLI level too. Shared-storage path mismatch produces "no output" failures. `-resume` is fragile after schema changes — `-clean -cleannode=<X>` to force fresh.

## 11. Testing strategy (RED → GREEN → REFACTOR)

The skill is TDD-driven per writing-skills. The five baseline scenarios cover the surface plus the goal-directed concern.

### 11.1 Baseline (RED) scenarios — `tests/baseline.md`

Seven scenarios. Each is run against a subagent **with no skill loaded**,
capturing verbatim behaviour. S1–S5 exercise the surface; S6 is the
compositional acid test that forces use of `reference/unreal-args.md`;
S7 is the UAT-fluency test that forces use of `reference/uat.md` and
`reference/buildgraph.md`.

**S1. "Build the editor for MyProject."**
- RED expectation: agent calls `RunUAT.bat` / `msbuild` or invents flags.
- GREEN: detects ushell, runs `.build editor`, reports result/time summary.

**S2. "I'm in `<branch>`. Get me an Insights trace of the game at CL 1234567 on PS5, channels default+gpu."** *(motivating example)*
- RED: agent invents a sequence, calls `RunUAT BuildCookRun`, forgets the trace flag, or asks many clarifying questions.
- GREEN: walks the DAG —
  ```
  .p4 sync 1234567
  → verify Engine/Build/Build.version Changelist
  → .info  (confirm engine + project + ps5 platform env)
  → check editor target receipt; if missing: .build editor
  → check game ps5 receipt; if missing: .build game ps5
  → .zen snapshot list game ps5  (look for 1234567 hit)
  → IF hit:  .zen snapshot get game ps5 1234567
    ELSE:   .cook game ps5
  → check Saved/StagedBuilds/ps5; if missing: .stage game ps5 auto
  → .run game ps5 --trace -- -trace=default,gpu  (add -tracehost= if devkit)
  → .perf insights latest
  ```
  Re-uses any precondition already satisfied (verified via on-disk checks).

**S3. "The editor builds but crashes on startup at this CL. Find the change that broke it. Last known good was CL 1234000."**
- RED: agent suggests git-bisect, hand-syncs CLs one at a time, or doesn't write a script.
- GREEN: writes `build-and-run.bat`:
  ```bat
  @echo off
  .build editor && .run editor -- -stdout -ExecCmds="Quit"
  if errorlevel 1 exit 80
  exit 0
  ```
  Invokes `.p4 bisect 1234000 <bad> -- build-and-run.bat`. Reports the offending CL.

**S4. "Add a `.mychan resave` command to ushell that runs ResavePackages on a directory I pass in."**
- RED: agent invents a different extension mechanism, edits engine source, or writes plain Python ignoring the channels framework.
- GREEN: creates `channels/mychan/describe.flow.py` registering `Channel().parent("unreal.core")` and `Command().source("cmds/resave.py","Resave").invoke("mychan","resave")`. Creates `cmds/resave.py` subclassing `unrealcmd.MultiPlatformCmd`, declaring `packagedir = unrealcmd.Arg(str, "...")` and `extra = unrealcmd.Arg([str], "...")`, swapping `.exe` → `-Cmd.exe`, piping forwarded args through `unreal.cmdline.read_ueified`, returning `cmd.get_return_code()`.

**S5. "I did `.cook game ps5` and it failed with `Unable to establish an Unreal context`. Fix it."**
- RED: agent restarts ushell, deletes `Saved/`, or edits the `.uproject`.
- GREEN: recognises noticeboard-not-set / no `.uproject` in cwd; runs `.project <path>` or relaunches ushell.bat with `--project=`; retries the cook.

**S6 (compositional). "Capture an Insights trace of the game on Windows,
booting into `/Game/Maps/BossArena` and spawning at the `PlayerStart`
tagged `MainStart`, with LLM memory tracking on, channels
`default,memory,memtag,gpu`, writing the trace to
`Saved/Profiling/Traces/Boss.utrace`. Then open it."**
- This goal is *not* in `workflows.md` as a hardcoded DAG. The skill must
  compose it from primitives + `reference/unreal-args.md`.
- RED: agent invents flags, omits LLM, picks the wrong trace channels,
  uses `?StartPoint=` (a real-world hallucination — the URL grammar is
  `Map#Portal`, not a `?` option), or skips `.perf insights`.
- GREEN: produces — and executes — a sequence equivalent to:
  ```
  .info                                              # confirm context, platform
  .build editor                                      # if no editor build
  .build game win64                                  # if no game receipt
  .cook game win64       (or .zen snapshot get game win64)
  .stage game win64 auto
  .run game win64 --trace=default,memory,memtag,gpu -- ^
       /Game/Maps/BossArena#MainStart ^
       -llm -llm.AutoReportMemory ^
       -traceFile=Saved/Profiling/Traces/Boss.utrace ^
       -unattended -stdout
  .perf insights Saved/Profiling/Traces/Boss.utrace
  ```
  Skip-conditions honoured: re-uses receipts/cooks already present.
  Also requires the project's `PlayerStart` in `/Game/Maps/BossArena`
  to have `PlayerStartTag = MainStart` — if Claude is told this is a
  fresh project, it should note the precondition and ask the user to
  confirm rather than silently fail (Failure-policy §5.4).
- **Why this test matters:** it forces the skill to (a) walk the standard
  Insights DAG, (b) consult `reference/unreal-args.md` for the map URL
  grammar (specifically the `#Portal` segment vs the `?` Op syntax —
  a very common LLM hallucination point), LLM switches, trace-file path,
  and channel taxonomy, and (c) compose them into a single `.run game`
  invocation. None of this is a copy-paste from `workflows.md`. If the
  skill only knows fixed DAGs — or if `unreal-args.md` is wrong about
  the URL grammar — S6 fails.

**S7 (UAT fluency). "Make me a shipping-grade packaged build of MyProject
for Win64 and Linux dedicated server in one go, with IoStore + compression,
encrypted-ini paks, archived to `D:\Builds\MyProject\$BUILDVER\`. This
will run in CI so it must not pop dialogs or hang on crashes. Then run
Project.Smoke automation tests against the staged client and write a
Horde-readable report."**
- This goal cannot be served by `.cook` + `.stage` alone — it needs direct
  `.uat BuildCookRun` (multi-target, encryption, archive control) and
  `.uat RunUnreal` (Gauntlet) plumbing. Forces use of `reference/uat.md`.
- RED: agent invokes `.stage` repeatedly hoping the per-platform args
  thread through; invents an `-encrypt` flag; uses `-RunAutomationTest=`
  under BCR (fragile); forgets `-buildmachine`; passes `-stagingdirectory`
  through Project Settings instead of CLI; tries to set `-platform=` with
  both client and server platforms in one BCR call without `-target=`.
- GREEN: produces — and explains — invocations equivalent to:
  ```
  .uat BuildCookRun -- ^
       -project=<full path>\MyProject.uproject ^
       -target=MyProject+MyProjectServer ^
       -platform=Win64 -serverplatform=Linux ^
       -clientconfig=Shipping -serverconfig=Shipping ^
       -build -cook -stage -pak -iostore -compressed -package -archive ^
       -archivedirectory="D:\Builds\MyProject\%BUILDVER%" ^
       -encryptinifiles -keychain=<path> ^
       -prereqs -nodebuginfo -utf8output ^
       -buildmachine -CrashForUAT -NoCodeSign -unattended -nullrhi -nop4 -stdlog

  .uat RunUnreal -- ^
       -project=MyProject ^
       -test=UE.TargetAutomation ^
       -RunTest="Filter:Smoke" ^
       -build="D:\Builds\MyProject\%BUILDVER%\WindowsClient" ^
       -platform=Win64 -configuration=Shipping ^
       -ReportExportPath="D:\Builds\MyProject\%BUILDVER%\TestReport" ^
       -WriteTestResultsForHorde ^
       -MaxDuration=900 ^
       -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT
  ```
  Plus: explains the JUnit caveat (post-process `index.json` if JUnit is
  needed downstream) and notes that the `Project.Smoke` filter substring-
  matches against beautified test names (use `^Project.Smoke$` anchors to
  pin).
- **Why this test matters:** UAT fluency is the difference between a skill
  that wraps day-to-day verbs and a skill that's actually useful for the
  serious work — shipping, CI, signing, plugin distribution, Gauntlet
  test harnessing. If `reference/uat.md` is missing the multi-target /
  encryption / Horde-report material, S7 fails.

### 11.2 With-skill (GREEN) verification — `tests/with-skill.md`

Same seven prompts re-dispatched to subagents with the skill loaded.
Scored as an `n/7` rubric — each scenario passes only if the agent hits
every step in the GREEN expectation. Below 7/7 ⇒ REFACTOR.

### 11.3 REFACTOR

For each non-passing scenario, identify the rationalisation, add an explicit counter (rule, table row, troubleshooting entry, or tightened DAG skip-condition), re-run. Repeat until all GREEN.

## 12. Implementation order (will become the plan)

1. Write `tests/baseline.md` and **run the RED prompts** against fresh subagents *before any skill content exists*. Save verbatim rationalisations into `tests/notes.md`.
2. Write `SKILL.md` (always-loaded surface) — frontmatter, iron rules, detection gate, non-interactive recipe, goal-directed planning rule, Zen↔UAT note, quick reference table, "Load reference when…" pointers, anti-patterns.
3. Write `reference/invocation.md` (prerequisite for everything else functioning at the shell level).
4. Write `reference/commands.md` in two passes: (a) skeleton of all ~60 entries with the template + Preconditions/Produces fields; (b) bodies in priority order — build/run/cook/stage/uat/sln/info/project → p4 → zen + zen snapshot → perf → ddc → getbuild → clangdb → gather → notify.
5. Write `reference/workflows.md` as the goal-first DAG catalogue. Insights-trace DAG is the headline; ≥12 other entries.
6. Write `reference/channel-authoring.md` anchored to `unrealcmd.py`, `_context.py`, and the canonical `cmds/run.py::Commandlet` / `cmds/cook.py` patterns. Include the smallest-viable-channel template.
7. Write `reference/troubleshooting.md` seeded from real `EnvironmentError`/`ValueError` strings identified in the codebase, organised by symptom keyword.
8. Write `reference/unreal-args.md` covering boot modes, the `FURL` map URL grammar (`Map#Portal?Key=Value`), trace channels, LLM/profiling switches, `-ExecCmds`, common commandlet recipes, and the goal→UE-args quick map. **Inline the user's `ue5-launch-with-spawn-point.md` verbatim** as the §2 (Map URL syntax) section — it's already grounded in `URL.cpp` / `GameModeBase.cpp` source quotes and documents the real gotchas (custom GameMode overrides, PIE, FName casing, `StartSpot` fallback). Source the rest from the UE 5.7 engine tree (Launch, CoreUObject) and from the perf-test ProjectSettings sections.
9. Write `reference/uat.md` — UAT command catalogue per §10.6. Seed from `docs/superpowers/specs/research-notes-uat.md` (sections A, B, D, E, F, G); expand into per-command pages following the same template as `commands.md` (Args/Flags/Preconditions/Produces/Examples). Include the 15-recipe BCR gallery, the Gauntlet recipes, the shipping/CI canonical invocations, and the top-7 gotchas section.
10. Write `reference/buildgraph.md` — BuildGraph reference per §10.7. Seed from `research-notes-uat.md` section C plus direct reading of the two shipped example scripts (`CookedEditor/EpicGames.BuildGraph.xml`, `LiveLinkHub/EpicGames.BuildGraph.xml`). Include the 8 idiomatic recipe skeletons.
11. Run `tests/with-skill.md` — dispatch the same seven prompts with skill loaded.
12. REFACTOR until 7/7 GREEN. Capture each new rationalisation in `tests/notes.md`.
13. Install to `~/.claude/skills/ushell/` (working copy stays at `E:\Work\ushell-skill\`).

## 13. Distribution

- Personal install: `~/.claude/skills/ushell/` (Windows: `C:\Users\Aaron\.claude\skills\ushell\`).
- Working tree at `E:\Work\ushell-skill\` is the source of truth; the install location is updated via copy or symlink.
- Not (yet) packaged as a Claude Code plugin. If the skill proves useful to others, a future task can promote it into a marketplace plugin under `plugins/ushell/skills/ushell/`. Out of scope for v1.

## 14. Open risks & follow-ups

- **Engine version drift.** Built against UE 5.7's ushell. Major engine bumps may rename commands, add flags, or change Zen/Cloud DDC plumbing. Mitigation: every commands.md entry cites the source file path in the engine tree; the REFACTOR cycle is cheap to re-run on a new UE version.
- **Non-interactive invocation quirks.** ushell.bat's scripting-detection heuristic is brittle on alternative terminals. If baseline testing surfaces consistent invocation breakage, revisit Option C (a `tools/ushell-run.ps1` wrapper).
- **PowerShell host.** This environment is PowerShell-first; the canonical recipe still goes via `cmd.exe`. If users prefer `Import-Module powerushell` interactive flow, document it as the secondary path but keep cmd.exe scripting as canonical for Claude's automation use case.
- **No git history.** `E:\Work\ushell-skill\` is not a git repo at spec time. If the user wants version control, `git init` after spec approval and commit per-step during plan execution.
- **Cloud DDC / Zen evolution.** Some Zen verbs (`importsnapshot`, `createworkspace`, `createshare`) are still settling in 5.7. The skill should treat these as "may move"; commands.md entries will flag any surface that depends on `[StorageServers]` ini keys.

## 15. Acceptance criteria

- SKILL.md ≤300 words of prose (excluding the quick-reference table).
- All ~60 registered ushell verbs have entries in `reference/commands.md` with Preconditions/Produces.
- `reference/workflows.md` has ≥12 goal-first DAGs including the Insights-trace example.
- `reference/unreal-args.md` covers — at minimum — boot modes, the **`FURL` map URL grammar** (`Map#Portal?Key=Value...`, with `#Portal` matched against `APlayerStart::PlayerStartTag` and the documented gotchas), the trace-channel taxonomy, `-ExecCmds`, LLM/memory switches, render/window switches, common commandlet `-run=<Name>` recipes, and the goal→UE-args quick map.
- The content of `ue5-launch-with-spawn-point.md` (user-authored seed material at the working-tree root, covering `FURL` grammar, the call-stack from `UWorld::SpawnPlayActor` to `FindPlayerStart_Implementation`, and the `?Name=` vs `#Portal` distinction) is either inlined into `reference/unreal-args.md` or moved into `reference/` and cross-linked — never silently dropped.
- `reference/uat.md` exists and covers — at minimum — the seven BCR verbs in execution order, the ProjectParams flag groups (build/cook/stage/package/archive/deploy/run/paks/iostore/zen/encryption/CI), at least 12 of the 15 idiomatic BCR recipes, the BuildPlugin packaging recipe with the `-TargetPlatforms=` gotcha, the Gauntlet/RunUnreal recipes including the `Project.Smoke` smoke-test invocation, the `.perf test` → `RunUnreal -test=AutomatedPerfTest.*` mapping, the JUnit caveat, and the top community gotchas. The CI-flag tetrad (`-buildmachine -CrashForUAT -unattended -nop4 -NoCodeSign -utf8output -stdlog`) appears as a named recipe.
- `reference/buildgraph.md` exists and covers — at minimum — the `RunUAT BuildGraph` CLI, every schema element (Property/Option/Agent/Node/Aggregate/Trigger/Label/Include/Macro/Expand/Notify/Annotation/EnvVar), at least 30 of the ~50 built-in tasks (with `<Compile>`, `<Cook>`, `<Stage>`, `<Command>`, `<Commandlet>`, `<Copy>`, `<Tag>`, `<Submit>`, `<HordeCreateReport>` mandatory), the two shipped case studies, at least 5 of the 8 recipe skeletons, and the ushell `.uat BuildGraph` integration.
- All seven RED scenarios produced verbatim baseline notes BEFORE any skill content was written.
- All seven with-skill scenarios pass 7/7 with no manual hint to the subagent beyond loading the skill — including S6 (compositional UE-args use) and S7 (UAT fluency), the two canaries that the skill can compose real-world goals from primitives rather than recite fixed DAGs.
- The skill is installed at `~/.claude/skills/ushell/` and loads correctly in a fresh Claude Code session (verified by a `--help` round-trip).

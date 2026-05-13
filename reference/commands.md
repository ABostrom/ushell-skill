# ushell command reference

One section per registered command, in the order they appear in `<ushell>/channels/unreal/core/describe.flow.py` and `<ushell>/channels/unreal/perforce/describe.flow.py`. Each section follows the **template** below. Field semantics are non-negotiable — they're what powers `SKILL.md`'s goal-directed-planning rule.

## Template

```markdown
## `.<words>` — <one-line purpose>

**When:** <triggering need>

**Usage:** `.<words> <positional1> [<positional2>] [-- <UE passthrough args>]`

**Args:**
- `<name>` (<type>/<default>) — <description>
…

**Flags:**
- `--<flag>` (<type>/<default>) — <description>
…

**Preconditions:**
- <verifiable check>

**Produces:**
- <artifact or state change>

**Implicit behaviour:** <auto-injected flags, target munging, env setup>

**Common pitfalls:**
- <bullet>

**Examples:**

\`\`\`
.<words> <real example>     # one-line justification
\`\`\`

**Source:** `<ushell>/channels/<channel>/cmds/<file>.py::<ClassName>`
```

The **Preconditions** and **Produces** fields are how `SKILL.md`'s goal-directed planner walks the DAG. They must be verifiable from on-disk state when possible.

## Table of contents

- **Core channel** (`channels/unreal/core/cmds/`)
  - Build: `.build target`, `.build editor`, `.build clean editor`, `.build program`, `.build clean program`, `.build server`, `.build clean server`, `.build client`, `.build clean client`, `.build game`, `.build clean game`
  - Build config: `.build xml`, `.build xml edit`, `.build xml set`, `.build xml clear`
  - Misc build: `.build misc clangdb`
  - Run: `.run editor`, `.run commandlet`, `.run program`, `.run target`, `.run server`, `.run client`, `.run game`
  - Cook: `.cook`, `.cook game`, `.cook client`, `.cook server`
  - ODSC: `.cook odsc client`, `.cook odsc game`, `.cook odsc all`
  - Stage / deploy: `.stage`, `.deploy`
  - UAT: `.uat`
  - Solutions: `.sln generate`, `.sln open`, `.sln open 10x`, `.sln open tiny`
  - Info / project: `.info`, `.info projects`, `.info config`, `.project`
  - Misc: `.kill`, `.notify`, `.ushell gather`, `.getbuild`
  - Storage / data: `.ddc auth`
  - Zen: `.zen start`, `.zen stop`, `.zen status`, `.zen version`, `.zen dashboard`, `.zen createworkspace`, `.zen createshare`, `.zen importsnapshot`
  - Zen snapshots: `.zen snapshot find`, `.zen snapshot get`, `.zen snapshot list`
  - Perf: `.perf insights`, `.perf test default`, `.perf test sequence`, `.perf test replay`, `.perf test material`, `.perf test camera`
- **Perforce channel** (`channels/unreal/perforce/cmds/`)
  - `.p4 sync`, `.p4 sync edit`, `.p4 sync mini`
  - `.p4 cherrypick`
  - `.p4 bisect`
  - `.p4 mergedown`
  - `.p4 switch`, `.p4 switch list`
  - `.p4 workspace`
  - `.p4 clean`, `.p4 reset`
  - `.p4 authors`, `.p4 who`
  - `.p4 v` (P4V launcher)

---

# Build family

## Shared `_BuildCmd` options

Every `.build <target>` and `.build clean <target>` accepts:

- `--clean` (bool/false) — Clean before building.
- `--nouht` (bool/false) — Skip building UnrealHeaderTool.
- `--noxge` (bool/false) — Disable IncrediBuild / SN-DBS / FastBuild.
- `--analyze` (`visualcpp` | `pvsstudio` / "") — Run static analysis (`-StaticAnalyzer=`).
- `--projected` (bool/false) — Add `-Project=<uproject>` when running UBT.
- `--noshowcfg` (bool/false) — Bypass printing of XML build configuration.
- `--nosummary` (bool/false) — Suppress the `Cmd.summarise` footer.

UBT extra args go after a `--` boundary: `.build editor -- -Define:FOO=1 -DisableUnity`.

## `.build target` — Run UBT on a named target

**When:** You want to drive UnrealBuildTool against a custom target name not covered by editor/game/client/server/program.

**Usage:** `.build target <target>[ <target2>...] [<platform>] [<variant>] [<fileormod>] [-- <UBT args>]`

**Args:**
- `target` (str) — Target name(s); space-separated for multiple. Tab-completed from `Intermediate/Build/BuildRules/*RulesManifest.json` and `Source/*.Target.cs`.
- `platform` (str/"") — Target platform (default: host).
- `variant` (str/"development") — Build configuration.
- `fileormod` (str/"") — Single module name, `Module/File.cpp`, an absolute/relative `.cpp`/`.h`, or `.` to fzf.

**Flags:** `_BuildCmd` shared options.

**Preconditions:**
- Active branch (engine `Build.version` exists at `Engine/Build/Build.version`).
- Source/target files synced (for fzf completion to find anything).

**Produces:**
- `Binaries/<Plat>/<Target>[-<Plat>-<Variant>].target` receipt JSON.
- Object files under `Intermediate/Build/`.

**Implicit behaviour:** Adds `-Progress` always. Streams output through `_PrettyPrinter` (errors/warnings colourised; `@progress` markers; "Errors and warnings" summary at end).

**Examples:**

```
.build target UnrealHeaderTool                          # build UHT for host
.build target ShaderCompileWorker win64 development     # explicit platform/variant
.build target MyCustomProgram win64 -- -DisableUnity   # pass UBT flag
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Build`

## `.build editor` — Build the editor target

**When:** You need a working `UnrealEditor.exe` (or `<Project>Editor.exe`) for the active project.

**Usage:** `.build editor [<variant>] [<fileormod>] [-- <UBT args>]`

**Args:**
- `variant` (str/"development") — `debug | debuggame | development | test | shipping`.
- `fileormod` (str/"") — Single module name, `Module/File.cpp`, an absolute/relative `.cpp`/`.h`, or `.` to fzf-pick.

**Flags:**
- `_BuildCmd` shared options.
- `--noscw` (bool/false) — Skip building `ShaderCompileWorker`.
- `--nopak` (bool/false) — Skip building `UnrealPak`.
- `--nointworker` (bool/false) — Skip building `InterchangeWorker`.
- `--platform` (str/"") — Cross-compile editor for non-host platform.

**Preconditions:** Active branch. Active `.uproject` recommended (auto-targets project's editor variant if present).

**Produces:**
- Editor `.target` receipt at `Binaries/<HostPlatform>/<Name>[Editor].target`.
- (Implicit) `ShaderCompileWorker.target`, `UnrealPak.target`, `InterchangeWorker.target` unless suppressed.

**Implicit behaviour:** Auto-builds `ShaderCompileWorker`, `UnrealPak`, and `InterchangeWorker` programs unless `fileormod` is set, `--analyze` is set, or any of `--noscw`/`--nopak`/`--nointworker` is given. Adds `-AllModules` unless the project path matches `EngineTest`/`Samples`. Always passes `-Progress`.

**Common pitfalls:**
- Don't pass `-Project=…` yourself; use `--projected` (picks the active project).
- Single-file builds add `-SingleFile=` and `-SkipDeploy` — incompatible with staging.

**Examples:**

```
.build editor                                # development host editor
.build editor debug                          # debug variant
.build editor CoreTest                       # just CoreTest module
.build editor . --clean                      # fzf-pick file/module + clean
.build editor -- -Define:FOO=1 -DisableUnity # pass through to UBT
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Editor`

## `.build clean editor` — Clean+rebuild the editor

Same as `.build editor` with `--clean` forced on. Auto-generated by the `_add_clean_cmd` decorator.

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::CleanEditor`

## `.build program` — Build a named program

**When:** Build any `Source/Programs/<Name>/*.Target.cs` target (UnrealInsights, UnrealFrontend, ShaderCompileWorker, etc.).

**Usage:** `.build program <program> [<variant>] [<fileormod>] [-- <UBT args>]`

**Args:**
- `program` (str) — Program target name. Tab-completed from `Source/Programs/*/*.Target.cs` and `Source/Programs/*/*/*.Target.cs`.
- `variant` (str/"development").
- `fileormod` (str/"").

**Flags:**
- `_BuildCmd` shared options.
- `--platform` (str/"") — Cross-compile the program.

**Preconditions:** Active branch; the program's `*.Target.cs` exists.
**Produces:** `Binaries/<Plat>/<Program>[-<Plat>-<Variant>].target`.

**Examples:**

```
.build program UnrealInsights                     # development host
.build program UnrealInsights shipping            # shipping build
.build program ShaderCompileWorker --clean
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Program`

## `.build clean program` — Clean+rebuild a program

Same as `.build program` with `--clean` forced.

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::CleanProgram`

## `.build server` — Build the server target

**When:** Build dedicated server binary for the active project.

**Usage:** `.build server [<platform>] [<variant>] [<fileormod>] [-- <UBT args>]`

**Args:**
- `platform` (str/"") — Server platform. `complete_platform = ("win64", "linux")`.
- `variant` (str/"development").
- `fileormod` (str/"").

**Flags:** `_BuildCmd` shared options.

**Preconditions:** Active project with a `<ProjectName>Server.Target.cs` (or the project falls back to host-engine server target).
**Produces:** `Binaries/<Plat>/<Project>Server[-<Plat>-<Variant>].target`.

**Examples:**

```
.build server linux                              # Linux dedicated server, dev
.build server linux shipping
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Server`

## `.build clean server`

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::CleanServer`

## `.build client` — Build the client runtime

**When:** Build the standalone game client (the runtime, not the editor).

**Usage:** `.build client [<platform>] [<variant>] [<fileormod>] [-- <UBT args>]`

**Args:** `platform`, `variant`, `fileormod` (as Server).

**Flags:** `_BuildCmd` shared options.

**Preconditions:** Active project.
**Produces:** `Binaries/<Plat>/<Project>Client[-<Plat>-<Variant>].target`. Auto-injects `-Project=` (projected) when a project is active.

**Examples:**

```
.build client win64                              # Win64 dev client
.build client ps5 test
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Client`

## `.build clean client`

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::CleanClient`

## `.build game` — Build the game runtime

**When:** Build the standalone game target (not client/server-only, not editor).

**Usage:** `.build game [<platform>] [<variant>] [<fileormod>] [-- <UBT args>]`

**Args/Flags/Preconditions:** Same as `.build client`.
**Produces:** `Binaries/<Plat>/<Project>[-<Plat>-<Variant>].target`.

**Examples:**

```
.build game win64                                # Win64 dev game
.build game ps5 shipping
```

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::Game`

## `.build clean game`

**Source:** `<ushell>/channels/unreal/core/cmds/build.py::CleanGame`

---

# Build config (BuildConfiguration.xml)

UBT reads `BuildConfiguration.xml` from four hierarchical levels (INTERNAL, BRANCH, GLOBAL, LEGACY). These commands query/edit them.

## `.build xml` — Display current build configuration

**When:** Inspect what UBT flags are set across all four BuildConfiguration.xml levels.

**Usage:** `.build xml`

**Args:** none.
**Flags:** none.
**Preconditions:** Active branch.
**Produces:** Stdout only (no on-disk effect).

**Implicit behaviour:** Iterates `ubt.read_configurations()` (INTERNAL → BRANCH → GLOBAL → LEGACY). Prints sections, values, and file existence with green/red indicators.

**Source:** `<ushell>/channels/unreal/core/cmds/build_xml.py::Show`

## `.build xml edit` — Open BuildConfiguration.xml in editor

**Usage:** `.build xml edit [--branch]`

**Flags:**
- `--branch` (bool/false) — Edit the branch-level config (otherwise GLOBAL/user-level).

**Implicit behaviour:** Uses `$GIT_EDITOR`, `$P4EDITOR`, then system default editor.

**Source:** `<ushell>/channels/unreal/core/cmds/build_xml.py::Edit`

## `.build xml set` — Set a build configuration value

**Usage:** `.build xml set <section> <name> <value> [--branch]`

**Args:**
- `section` (str) — Tab-completed from UBT schema.
- `name` (str) — Tab-completed from schema.
- `value` (str) — Tab-completed from schema where enum/bool.

**Flags:** `--branch` (bool/false).

**Produces:** Modified XML. Prints `was '<prev>'` on success.

**Examples:**

```
.build xml set BuildConfiguration bUseUnityBuild false
.build xml set ParallelExecutor MaxLocalActions 16 --branch
```

**Source:** `<ushell>/channels/unreal/core/cmds/build_xml.py::Set`

## `.build xml clear` — Clear a configuration value

**Usage:** `.build xml clear <section> <name> [--branch]`

**Source:** `<ushell>/channels/unreal/core/cmds/build_xml.py::Clear`

---

# Misc build

## `.build misc clangdb` — Generate compile_commands.json

**When:** You want clangd / VS Code IntelliSense / a Clang-based static analyzer to index the engine.

**Usage:** `.build misc clangdb [<target>] [-- <UBT args>]`

**Args:**
- `target` (str/"") — Defaults to the editor target.

**Flags:**
- `--platform` (str/"") — Platform to generate for (default: host).
- `--projected` (bool/false) — Include the project (when in project context).
- `--keepgenfiles` (bool/false) — Include UHT-generated `.gen.cpp` files.
- `--keepplatformcode` (bool/false) — Include `Platforms/` source.
- `--keepthirdpartycode` (bool/false) — Include `ThirdParty/` source.

**Preconditions:** Active branch. Clang toolchain available (probes `$UE_SDKS_ROOT/Host<Host>/Win64/LLVM/*/bin/clang-cl.exe`, falls back to `clang-cl` on PATH).

**Produces:** `compile_commands.json` at engine root (or project root for FOREIGN projects). Prints final path + size.

**Examples:**

```
.build misc clangdb                              # editor target, exclude gen/platform/3p
.build misc clangdb --projected                  # add -Project=
.build misc clangdb MyCustomTarget win64 --keepgenfiles
```

**Source:** `<ushell>/channels/unreal/core/cmds/clangdb.py::ClangDb`

---

# Run family

## Shared `_Attachable` (debugger) behaviour

`.run editor`, `.run commandlet`, `.run program`, `.run target`, `.run server`, `.run client`, and `.run game` all support `--attach`. The debugger backend is selected dynamically:

- `USHELL_DEBUGGER=vs` (Windows default) → `<ushell>/channels/unreal/core/debuggers/vs.py` (Visual Studio via DTE).
- `USHELL_DEBUGGER=lldb` (POSIX default) → `<ushell>/channels/unreal/core/debuggers/lldb.py`.
- `USHELL_DEBUGGER=rider` → `<ushell>/channels/unreal/core/debuggers/rider.py` (JetBrains Rider).

For `--attach` on Windows to actually attach a VS instance, `.sln open` (or another way of opening the matching `.sln` in VS) must have happened first — VS DTE enumeration is how attach finds the instance.

## Shared `_Runtime` behaviour (server/client/game)

`.run {server,client,game}` extend `_Runtime` which adds:

- `--trace` / `--trace=<channels>` ((False, "")/"") — Enable Unreal Insights tracing. Auto-adds `-tracehost=<host>` and optional `-trace=<value>`.
- `--cooked` (bool/false) — Use cooked data instead of staged data.
- `--onthefly` (bool/false) — Add `-filehostip=` argument.
- `--binpath` (str/"") — Override the binary that is launched.
- `--datadir` (str/"") — Use an alternative staged/packaged directory.

Implicitly, `_Runtime` renames any existing `UECommandLine.txt` to `*_old_ushell.txt`, writes an empty replacement, and restores on exit. Adds `-pak` unless a `ue.projectstore` marker exists.

## `.run editor` — Launch the editor

**When:** Open the project editor (with or without debugger).

**Usage:** `.run editor [<variant>] [-- <UE args>]`

**Args:**
- `variant` (str/"development").
- `runargs` ([str]) — Args passed to the editor process.

**Flags:**
- `--build` (bool/false) — Build target prior to running (shells out to `_build editor <variant>`).
- `--attach` (bool/false) — Attach a debugger to the launched process.
- `--noproject` (bool/false) — Start the editor without specifying a project.

**Preconditions:** Editor `.target` receipt exists (or `--build` will create it).
**Produces:** Running editor process (or under debugger if `--attach`).

**Implicit behaviour:** Auto-prepends the active `.uproject` path to argv unless `--noproject`. If `-stdout` appears in `runargs` on Windows, switches binary from `<Name>.exe` to `<Name>-Cmd.exe`.

**Examples:**

```
.run editor                                            # standard launch
.run editor debug --attach                             # debug variant under VS
.run editor -- -ExecCmds="stat fps;stat unit"          # boot with console cmds
.run editor -- -ExecCmds="Automation RunTests Project.Smoke;Quit" -ReportExportPath=E:\Reports
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Editor`

## `.run commandlet` — Run an editor commandlet

**When:** Invoke `<Editor>-Cmd.exe -run=<CommandletName>` against the active project. This is the canonical generic commandlet entry point.

**Usage:** `.run commandlet <commandlet> [<variant>] [-- <UE args>]`

**Args:**
- `commandlet` (str) — Tab-completed from `Source/Editor/UnrealEd/Classes/Commandlets/*Commandlet.h` (strips the trailing `Commandlet`).
- `variant` (str/"development").
- `runargs` ([str]).

**Flags:** `--build`, `--attach`.

**Preconditions:** Editor `.target` receipt exists (or `--build`). Active `.uproject`.
**Produces:** Whatever the commandlet writes (e.g. resaved packages, generated files, cooked content).

**Implicit behaviour:** Always uses the `<Editor>-Cmd.exe` console variant (not the GUI `.exe`). Inserts `<.uproject>` then `-run=<commandlet>` at the front of argv. With `--attach`, debugger backend re-enters via `<ushell>/channels/unreal/core/debuggers/`.

**Examples:**

```
.run commandlet ResavePackages -- -PackageDir=Content/Foo
.run commandlet DerivedDataCache -- -fill -unattended
.run commandlet GatherText -- -config=Engine/Config/Localization/Engine.ini
.run commandlet PluginInfoDump --build                              # build editor first
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Commandlet`

## `.run program` — Launch a program target

**Usage:** `.run program <program> [<variant>] [-- <args>]`

**Args:**
- `program` (str) — Tab-completed from `Source/Programs/*/*.Target.cs`.
- `variant` (str/"development").
- `runargs` ([str]).

**Flags:** `--build`, `--attach`.

**Preconditions:** Program `.target` receipt exists.
**Produces:** Running program process.

**Examples:**

```
.run program UnrealInsights
.run program UnrealFrontend --build
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Program`

## `.run target` — Launch a named target

**Usage:** `.run target <target> [<variant>] [-- <args>]`

Similar to `.run program` but for any named target.

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Target`

## `.run server` — Launch the server runtime

**When:** Run cooked dedicated server.

**Usage:** `.run server [<platform>] [<variant>] [-- <args>]`

**Args:**
- `platform` (str/"") — `complete_platform = ("win64", "linux")`.
- `variant` (str/"development").
- `runargs` ([str]).

**Flags:** `--build`, `--attach`, plus `_Runtime` shared options (`--trace`, `--cooked`, `--onthefly`, `--binpath`, `--datadir`).

**Preconditions:** Server `.target` + active `.uproject` + staged build at `Saved/StagedBuilds/<cook_form>/` (unless `--datadir`).
**Produces:** Running server process.

**Implicit behaviour:** Auto-appends `-log -unattended` to runargs.

**Examples:**

```
.run server linux                                          # local Linux dedicated server
.run server linux --trace=default,memory -- -Map=Boot
.run server linux --binpath=E:\CustomBuild\Server.exe
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Server`

## `.run client` — Launch the game client runtime

**Usage:** `.run client [<platform>] [<variant>] [-- <args>]`

**Args:** `platform`, `variant`, `runargs`.

**Flags:** `--build`, `--attach`, plus `_Runtime` shared options.

**Preconditions:** Client `.target` + active project + staged build (unless `--datadir`).
**Produces:** Running client process.

**Examples:**

```
.run client win64                                          # standalone Win64 client
.run client ps5 --trace=default,gpu -- -CONNECT=10.1.2.3:7777
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Client`

## `.run game` — Launch the standalone game runtime

**Usage:** `.run game [<platform>] [<variant>] [-- <args>]`

**Args:** `platform` (adds `"editor"` to completions), `variant`, `runargs`.

**Flags:** `--build`, `--attach`, plus `_Runtime` shared options.

**Special case:** if `platform == "editor"`, delegates to `.run editor` with `runargs + -game` (and forwards `--build`/`--attach`). This is the way to run the editor binary in standalone-game mode without packaging.

**Preconditions:** Game `.target` + active project + staged build (unless `platform=editor`).
**Produces:** Running game process.

**Examples:**

```
.run game win64                                          # standalone Win64 game
.run game editor -- -Map=BossArena                        # editor binary in -game mode
.run game ps5 --trace=default,memory,memtag,gpu \
    -- /Game/Maps/BossArena#MainStart -llm -llm.AutoReportMemory \
       -traceFile=Saved/Profiling/Traces/Boss.utrace
```

**Source:** `<ushell>/channels/unreal/core/cmds/run.py::Game`

---

# Cook family

`.cook *` runs the **editor commandlet `-run=Cook`** directly against `<Editor>-Cmd.exe`. It does NOT go through UAT. Compare with `.stage` (which does use UAT `BuildCookRun`).

## Shared `_Cook` options

All `.cook *` accept:

- `--cultures` (str/"en") — Cultures to cook (comma-separated). Joined with `+` for `-cookcultures=`.
- `--onthefly` (bool/false) — Launch as cook-on-the-fly server.
- `--iterate` (bool/false) — Cook iteratively on top of previous output. Adds `-forcerecook=false` if not already in cookargs.
- `--noxge` (bool/false) — Disable XGE shader compilation.
- `--unpretty` (bool/false) — Turn off colourful pretty-printing.
- `--attach` (bool/false) — Attach a debugger to the cook.
- `--build` (bool/false) — Build editor binaries first.
- `--debug` (bool/false) — Use the debug editor.
- `--nounattended` (bool/false) — Skip implicit `-unattended`.
- `--versioned` (bool/false) — Skip implicit `-unversioned`.

**Iterative-cook warning:** `--iterate` is **dev only**. Community-confirmed stale-asset bugs. Never for shipping.

## `.cook` — Cook for a raw target platform string

**Usage:** `.cook <target> [-- <cook args>]`

**Args:**
- `target` (str) — Full target platform name (e.g. `WindowsNoEditor`, `LinuxServer`). Passed to `-targetplatform=`.
- `cookargs` ([str]).

**Preconditions:** Editor binary built (`Binaries/<HostPlatform>/UnrealEditor-Cmd.exe`); active project.
**Produces:** `Saved/Cooked/<target>/` populated.

**Examples:**

```
.cook WindowsClient
.cook LinuxServer --iterate
```

**Source:** `<ushell>/channels/unreal/core/cmds/cook.py::Cook`

## `.cook game` — Cook game data for a platform

**Usage:** `.cook game [<platform>] [-- <cook args>]`

**Args:**
- `platform` (str/"").
- `cookargs` ([str]).

**Preconditions:** Editor built; active project.
**Produces:** `Saved/Cooked/<cook_form>/` (cook_form via `platform.get_cook_form("game")`).

**Implicit behaviour:** Sets up platform SDK env via `platform.read_env()`. Always passes `-unattended -unversioned -stdout`. With `--attach`, re-dispatches via `_run commandlet cook --attach` so debugger plumbing kicks in.

**Examples:**

```
.cook game win64
.cook game ps5 --iterate
.cook game ps5 -- -Map=BossArena                       # cook a single map
```

**Source:** `<ushell>/channels/unreal/core/cmds/cook.py::Game`

## `.cook client` — Cook client data

**Source:** `<ushell>/channels/unreal/core/cmds/cook.py::Client`

## `.cook server` — Cook server data

**Usage:** `.cook server [<platform>] [-- <cook args>]`

`complete_platform = ("win64", "linux")`.

**Source:** `<ushell>/channels/unreal/core/cmds/cook.py::Server`

---

# ODSC (On-Demand Shader Compile)

ODSC is a special cook mode that runs a long-lived shader compile server clients connect to with `-odschost=<ip>`. All three commands run the cook commandlet with `-odsc -cookonthefly -dpcvars=r.ShaderDevelopmentMode=1`.

## `.cook odsc client` — Launch ODSC server for client

**Usage:** `.cook odsc client [<platform>] [-- <args>]`

**Flags:** Inherits `_Odsc` shared (`--cultures`, `--noxge`, `--unpretty`, `--attach`, `--skipassetscan`, `--debug`, `--symbols`).

**Examples:**

```
.cook odsc client win64
# then on the cooked client:
#   <Game>.exe -odschost=<your-host-ip>
```

**Source:** `<ushell>/channels/unreal/core/cmds/odsc.py::Client`

## `.cook odsc game`

**Source:** `<ushell>/channels/unreal/core/cmds/odsc.py::Game`

## `.cook odsc all`

Uses literal cook_form `All`.

**Source:** `<ushell>/channels/unreal/core/cmds/odsc.py::All`

---

# Stage / deploy

## `.stage` — Stage a build via UAT BuildCookRun

**When:** Produce a deployable `Saved/StagedBuilds/<cook_form>/` directory. Goes through UAT.

**Usage:** `.stage <target> [<platform>] [<variant>] [<style>] [-- <UAT args>]`

**Args:**
- `target` (str) — `complete_target = ("game", "client", "server")`.
- `platform` (str/"").
- `variant` (str/"development").
- `style` (str/"auto") — `pak | nopak | zen | auto`.
- `uatargs` ([str]).

**Flags:**
- `--debug` (bool/false) — Use debug variant of UAT.
- `--attach` (bool/false) — Open VS to debug UAT.
- `--build` ((False, "")) — Build code prior to staging. Optional string of UBT args: `--build="-DisableUnity"`.
- `--cook` ((False, "")) — Run a cook before staging.
- `--deploy` (bool/false) — Deploy to devkit after staging.

**Style choices:**
- `pak` — Stage to `.pak`/`.utoc`/`.ucas`.
- `nopak` — Stage loose files (Zen streaming if enabled, pak otherwise).
- `zen` — Zen streaming; fail if Zen disabled.
- `auto` — `nopak` (default; UAT chooses based on `ue.projectstore`).

**Preconditions:** Active project. Cooked content at `Saved/Cooked/<cook_form>/` (unless `--cook`). Editor built (unless `--build=False` and editor was pre-built).
**Produces:** `Saved/StagedBuilds/<cook_form>/` populated. (Plus deployed bits on devkit if `--deploy`.)

**Implicit behaviour:** Sequences `_build editor` → `_build <target>` → `_cook <target>` → `_uat BuildCookRun -- -<target> -skipbuild -skipcook -stage -config=<variant> -platform=<plat>`. For `server`, adds `-noclient`. For `client`, adds `-client`.

**Quoting note:** `--build="..."` or `--cook="..."` arg-strings with quotes: double-up or escape backslashes (`"-Build=""-DisableUnity"""`).

**Examples:**

```
.stage game ps5 auto                                    # cooked + staged, auto style
.stage game ps5 zen                                     # force Zen streaming
.stage game ps5 pak                                     # force pak files
.stage game ps5 auto --build --cook                     # full chain in one go
.stage game ps5 auto --deploy                           # also push to devkit
```

**Source:** `<ushell>/channels/unreal/core/cmds/stage.py::Stage`

## `.deploy` — Push an already-staged build to devkit

**Usage:** `.deploy <target> [<platform>] [<variant>] [<style>] [-- <UAT args>]`

Same args as `.stage`. Forces `--build=False --cook=False --deploy=True --style=nopak`, and tells UAT `-skipstage -deploy`.

**Preconditions:** Existing staged build at `Saved/StagedBuilds/<cook_form>/`.
**Produces:** Build deployed to platform's connected devkit.

**Examples:**

```
.deploy game ps5                                        # push existing PS5 stage
```

**Source:** `<ushell>/channels/unreal/core/cmds/stage.py::Deploy`

---

# UAT

## `.uat` — Run an UnrealAutomationTool command

**When:** Invoke any `RunUAT.bat` subcommand directly. Use for `BuildCookRun`, `BuildPlugin`, `BuildGraph`, `RunUnreal` (Gauntlet), or any custom UAT script.

**Usage:** `.uat <command> [-- <uat-args>]`

**Args:**
- `command` (str) — UAT command name. Tab-completed by scanning `Source/Programs/AutomationTool/**` and project `Build/**` for `BuildCommand` subclasses and `*.Automation.csproj` files.
- `uatargs` ([str]).

**Flags:**
- `--unprojected` (bool/false) — Suppress implicit `-project=<uproject>`.
- `--allscripts` (bool/false) — Ask UAT to compile all script projects (default: project-only).
- `--debug` (bool/false) — Use debug variant of AutomationTool.
- `--attach` (bool/false) — Open VS to debug UAT (launches `devenv.exe /debugexe AutomationTool.exe`).

**Preconditions:** Active branch. Active `.uproject` (for the implicit `-project=` unless `--unprojected`).
**Produces:** Whatever the underlying UAT command produces.

**Implicit behaviour:** Builds UAT via `Engine/Build/BatchFiles/BuildUAT.bat` first. Auto-injects `-project=<uproject>` and `-ScriptsForProject=<name>` unless `--unprojected`/`--allscripts` or context is FOREIGN. For `--debug`, runs `GetDotnetPath.bat` then `dotnet build AutomationTool.csproj -c Debug`.

**Examples:**

```
.uat BuildCookRun -- -platform=Win64 -clientconfig=Shipping -build -cook -stage -pak -iostore
.uat BuildPlugin -- -Plugin=Plugins/MyPlugin.uplugin -Package=D:\Out -TargetPlatforms=Win64+Linux
.uat BuildGraph -- -script=Build/Pipeline.xml -target=Stage -set:Platform=Win64
.uat RunUnreal -- -test=UE.EditorAutomation -RunTest="Filter:Smoke" -build=editor -platform=Win64
.uat BuildCookRun -- -RunAutomationTest="DummySuite.SmokeTest" -unattended -nullrhi    # FRAGILE - prefer RunUnreal
```

For the full UAT catalogue, BuildCookRun's ProjectParams flag groups, BuildPlugin gotchas, Gauntlet RunUnreal, and CI-friendly invocation recipes, see `reference/uat.md`.

**Source:** `<ushell>/channels/unreal/core/cmds/uat.py::Uat`

---

# Solutions (Visual Studio)

## `.sln generate` — Generate the VS solution

**Usage:** `.sln generate [<open>] [-- <UBT args>]`

**Args:**
- `open` (str/"") — Pass literal `open` to also open after generating.
- `ubtargs` ([str]).

**Flags:**
- `--notag` (bool/false) — Do not tag the solution name with a branch identifier (sets `UE_NAME_PROJECT_AFTER_FOLDER=1`).
- `--all` (bool/false) — Include all branch projects in the solution.

**Preconditions:** Active branch.
**Produces:** `<Project>.sln` (or branch-named variant) in the engine/project root, plus `Intermediate/ProjectFiles/`.

**Implicit behaviour:** Sets `UE_NAME_PROJECT_AFTER_FOLDER=1` env var unless `--notag`. Runs UBT with `-ProjectFiles` (plus `-Project=` unless `--all`). For Blueprint-only projects without `Source/`, also writes synthetic `ushell_<project><target>.vcxproj` for Game/Client/Server/Editor.

**Examples:**

```
.sln generate                                          # generate, don't open
.sln generate open                                     # generate + open
.sln generate --all                                    # include every branch project
```

**Source:** `<ushell>/channels/unreal/core/cmds/sln.py::Generate`

## `.sln open` — Open the generated solution in VS

**Usage:** `.sln open`

Windows-only. Detects whether a VS instance with the same `.sln` is already running (via `vs.dte.running()`) and activates it; otherwise launches `cmd /c start <sln>`.

**Source:** `<ushell>/channels/unreal/core/cmds/sln.py::Open`

## `.sln open 10x` — Open in 10x Editor

Windows-only. Hardcoded path `C:\Program Files\PureDevSoftware\10x\10x.exe`.

**Source:** `<ushell>/channels/unreal/core/cmds/sln.py::Open10x`

## `.sln open tiny` — Generate + open a minimal solution

**When:** You don't need a full UE solution — just enough to debug-attach and have fzf-based file open. Generates without needing `.sln generate` first.

**Usage:** `.sln open tiny`

Uses `slnformer` to create a minimal `.sln` in `Intermediate/ProjectFiles/TinySln/` with one project per `Source/*.Target.cs`. Each project's NMake build action invokes `.build target $(ushell_target) win64 $(Configuration.ToLower())`. Opens VS.

**Source:** `<ushell>/channels/unreal/core/cmds/sln.py::Tiny`

---

# Info / project

## `.info` — Display current session info

**Usage:** `.info [--json]`

**Flags:** `--json` (bool/false).

**Produces:** Three sections: `engine` (path, version, version_full, branch, changelist), `project` (name, path, dir, per-target-type names), `platforms` (per-registered-platform name + version + env dict). Values prefixed `?` are yellow warnings; `!` are red errors.

**Examples:**

```
.info                                                  # human-readable
.info --json                                           # parseable
```

**Source:** `<ushell>/channels/unreal/core/cmds/info.py::Info`

## `.info projects` — List branch projects

**Usage:** `.info projects [--json]`

Calls `branch.read_projects()` and prints `.uproject` paths.

**Source:** `<ushell>/channels/unreal/core/cmds/info.py::Projects`

## `.info config` — Evaluate INI config for a category

**Usage:** `.info config <category> [--json] [--override=<set>]`

**Args:**
- `category` (str) — Tab-completed: `Engine | Game | Input | DeviceProfiles | GameUserSettings | Scalability | RuntimeOptions | InstallBundle | Hardware | GameplayTags`.

**Flags:**
- `--json` (bool/false).
- `--override` (str/"") — Alternative config set (e.g. `WinGDK`).

**Examples:**

```
.info config Engine
.info config DeviceProfiles --override=WinGDK
```

**Source:** `<ushell>/channels/unreal/core/cmds/info.py::Config`

## `.project` — Change the active project for this session

**Usage:** `.project [<nameorpath>]`

**Args:**
- `nameorpath` (str/"") — Several special forms:
  - `MyProjectName` — find by name (uses `.uprojectdirs`).
  - `d:/foo/bar.uproject` — set by qualified path.
  - `branch` or `none` — unset active project.
  - `cwd` — follow CWD on subsequent commands.
  - `active` — print current active project and return.
  - `list` — list all projects under branch, don't switch.
  - `auto` — pick most recently modified `.uproject`.
  - (empty) — fzf-pick.

**Implicit behaviour:** Stores chosen path in `session["uproject"]` noticeboard (`Cmd.Noticeboard.SESSION`).

**Tab completion:** `branch`, `cwd`, `active`, `list`, `auto`, plus all branch projects' stems.

**Examples:**

```
.project MyProjectName
.project E:\Work\MyProject\MyProject.uproject
.project cwd
.project list
.project                                               # fzf-pick
```

In the `unreal/perforce` channel, `.project` is **overridden** to also bootstrap the P4 environment for the project's directory (creates `.p4config.txt` if missing).

**Source:** `<ushell>/channels/unreal/core/cmds/project.py::Change` (overridden by `<ushell>/channels/unreal/perforce/cmds/project.py::Change`)

---

# Misc

## `.kill` — Hard-terminate UE processes

**Usage:** `.kill <what> [--wait=<minutes>]`

**Args:**
- `what` (str) — `editor | server | client | <platform>`. For a platform name, kills everything for that platform.

**Flags:** `--wait` (float/0.0) — Countdown in minutes (printed on same line).

**Implicit behaviour:** Tries `get_platform(what)` first; otherwise treats `what` as `editor`/`server`/`client` and calls `platform.kill(what)` on the active platform.

**Examples:**

```
.kill editor
.kill ps5                                              # kills all PS5 procs
.kill server --wait=5                                  # countdown 5min
```

**Source:** `<ushell>/channels/unreal/core/cmds/kill.py::Kill`

## `.notify` — Flash the console for attention

Windows-only. Calls `ctypes.windll.user32.FlashWindow(GetConsoleWindow(), True)`. On other OSes prints `"Notify is not supported by this OS"`.

**Source:** `<ushell>/channels/unreal/core/cmds/notify.py::Notify`

## `.ushell gather` — Bundle a standalone ushell deployment

**Usage:** `.ushell gather <destdir> [<srcdir>] [--overwrite]`

**Args:**
- `destdir` (Path) — Destination directory.
- `srcdir` (str/"") — Source (default: this ushell instance).

**Flags:** `--overwrite` (bool/false).

**Implicit behaviour:** Recursively copies all files (skips `.pyc` + `tps/`). Picks up platform-specific extras from `<branch>/Platforms/*/Extras/ushell/*`. Used by UGS to deploy ushell to users regardless of branch.

**Source:** `<ushell>/channels/unreal/core/cmds/gather.py::Gather`

## `.getbuild` — Download a build from UE Cloud Storage

**Usage:** `.getbuild <buildtype> <platforms...> [-- <runargs>]`

**Args:**
- `buildtype` (str) — `packaged | staged` (translated to `packaged-build`/`staged-build`).
- `platforms` ([str]).
- `runargs` ([str]) — Passed to zen download.

**Flags:**
- `--project` (str/"") — Override project name.
- `--branch` (str/"") — Stream (e.g. `//UE5/Main`).
- `--namespace` (str/"") — Override Zen namespace.
- `--host` (str/"") — Override Zen host.
- `--clean` (bool/false) — Re-fetch all.
- `--verbose` (bool/false).
- `--preflight` (bool/false) — Show preflights too.
- `--wildcard` (str/"") — Windows-style include pattern.
- `--exclude-wildcard` (str/"") — Exclude pattern (applied after include).
- `--dest` (str/"") — Destination dir (default `<projectdir>/Saved/<StagedBuilds|PackagedBuilds>/<platform>`).
- `--match` (str/"") — Build id (hex), changelist (number), or `k=v;k=v` query.

**Preconditions:** OIDC token configured (run `.ddc auth` first if needed). Network reachable to Zen host.
**Produces:** Build downloaded to `<dest>` directory.

**Examples:**

```
.getbuild staged win64                                 # latest staged Win64
.getbuild packaged ps5 --match=1234567                 # by CL
.getbuild staged win64 --match=8v93f39cvn3             # by build id
.getbuild staged win64 --match="job=v99f3;step=39f983" # advanced query
```

If multiple builds match, runs `fzf` for picking (closest-to-current-CL marked `*`).

**Source:** `<ushell>/channels/unreal/core/cmds/getbuild.py::GetBuild`

---

# Storage / data

## `.ddc auth` — Authorize for Cloud DDC

**Usage:** `.ddc auth [<service>] [-- <auth args>] [--query]`

**Args:**
- `service` (str/"") — Service name (defaults to `[StorageServers]Default.OAuthProviderIdentifier`, falls back to `.Cloud.OAuthProviderIdentifier`).
- `extraargs` ([str]).

**Flags:** `--query` (bool/false) — Only check current status (`--Mode=Query`).

**Implicit behaviour:** Shells out to `Engine/Binaries/DotNET/OidcToken/<host>/OidcToken[.exe]` with `--Service=<name>` (and `--Project=` when project active).

**Source:** `<ushell>/channels/unreal/core/cmds/ddc.py::Auth`

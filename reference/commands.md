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

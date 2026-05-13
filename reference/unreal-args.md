# Unreal Engine command-line lexicon

The arguments passed **after `-- `** to ushell's `.run *` / `.cook *` / `.uat` etc. are UE's own switches — they belong to the engine binary, not to ushell. This file is the canonical list of the switches that matter.

When `reference/workflows.md` shows a step like `.run game <P> --trace=<ch> -- <UE args>`, the `<UE args>` come from here, not from imagination.

## TOC

1. Boot modes
2. Map URL syntax (FURL grammar, the `#Portal` spawn selector)
3. Trace / Insights channels
4. `-ExecCmds`
5. Rendering / windowing
6. Performance / determinism
7. Logging
8. Cooking-specific
9. Stage / run-cooked specific
10. Networking / multiplayer
11. Commandlet `-run=<Name>` recipes
12. Discovering args for a specific project
13. Goal → required UE args quick map

---

## 1. Boot modes

How a UE binary decides what it is:

- **First positional arg after the binary**: a `.uproject` path (project context) OR a map URL.
- `-server` — run as dedicated server.
- `-server -log` — dedicated server with stdout logging.
- `-game` — run the editor binary as standalone game (no editor UI). Useful for `.run game editor` and ad-hoc test runs from a .uproject without packaging.
- `-run=<CommandletName>` — commandlet mode. Requires the `-Cmd.exe` variant on Windows for stdout.
- `-listen` or `?Listen` (in map URL) — host as listen server.
- `-NULLRHI` / `-nullrhi` — null rendering RHI (no GPU output). Standard for headless automation.
- Headless automation flavour: `-nullrhi -unattended -stdout -log` (the standard tetrad).
- `-WaitForDebugger` / `-waitforattach` — HALT at startup until a debugger attaches. Use locally only; do not put in CI.

---

## 2. Map URL syntax (FURL grammar)

The canonical reference. Parsed by `FURL::Parse` in `Engine/Source/Runtime/Engine/Private/URL.cpp`. Grammar:

```
Protocol://Host:Port/Map#Portal?Option1=Value1?Option2=Value2
```

For local launches you typically only use:

```
Map#Portal?Key=Value?Key=Value
```

The struct shape:

```cpp
struct FURL
{
    FString Protocol;   // "unreal"
    FString Host;
    int32   Port;
    FString Map;        // e.g. "/Game/Maps/Test"
    FString Portal;     // e.g. "Arena"  <-- spawn point selector
    TArray<FString> Op; // e.g. ["Name=Aaron", "SpectatorOnly=1"]
};
```

- `#` separates Map from Portal
- `?` introduces each option in `Op[]`

### Important gotcha: `?Name=` is NOT the spawn selector

`?Name=` sets the **player's display name** (truncated to 20 chars), not the spawn point. From `AGameModeBase::InitNewPlayer`:

```cpp
FString InName = UGameplayStatics::ParseOption(Options, TEXT("Name")).Left(20);
if (InName.IsEmpty())
{
    InName = FString::Printf(TEXT("%s%i"), *DefaultPlayerName.ToString(), NewPC->PlayerState->GetPlayerId());
}
ChangeName(NewPlayerController, InName, false);
```

The spawn point comes from `Portal`, which is a sibling field on `FURL`, parsed from the `#` segment.

**Equally wrong: `?StartPoint=`, `?PlayerStartTag=`.** Neither is a UE switch. The spawn selector is **always** the `#Portal` URL segment.

### Call stack: URL → spawn point

Starting from `UWorld::SpawnPlayActor` (in `World.cpp`):

```
UWorld::SpawnPlayActor(NewPlayer, RemoteRole, InURL, ...)
  builds Options string from InURL.Op[]
  └─ AGameModeBase::Login(NewPlayer, RemoteRole, *InURL.Portal, Options, ...)
     └─ AGameModeBase::InitNewPlayer(NewPC, UniqueId, Options, Portal)
        └─ AGameModeBase::UpdatePlayerStartSpot(NewPC, Portal, ErrorMessage)
           └─ AGameModeBase::FindPlayerStart(NewPC, Portal)   // Portal == IncomingName
              └─ AGameModeBase::FindPlayerStart_Implementation
                 matches IncomingName against APlayerStart::PlayerStartTag
```

Note the split: `InURL.Op[]` becomes `Options` (the `?Key=Value` pairs), while `InURL.Portal` is passed separately as `*InURL.Portal`. They take different paths through `Login` / `InitNewPlayer`.

### Key code references

**`Engine/Source/Runtime/Engine/Private/World.cpp`** — `UWorld::SpawnPlayActor`:

```cpp
FString Options;
for (int32 i = 0; i < InURL.Op.Num(); i++)
{
    Options += TEXT('?');
    Options += InURL.Op[i];
}
if (AGameModeBase* const GameMode = GetAuthGameMode())
{
    APlayerController* const NewPlayerController =
        GameMode->Login(NewPlayer, RemoteRole, *InURL.Portal, Options, UniqueId, Error);
    ...
}
```

**`Engine/Source/Runtime/Engine/Private/GameModeBase.cpp`** — `AGameModeBase::InitNewPlayer`:

```cpp
FString AGameModeBase::InitNewPlayer(APlayerController* NewPlayerController,
    const FUniqueNetIdRepl& UniqueId, const FString& Options, const FString& Portal)
{
    ...
    // Find a starting spot
    FString ErrorMessage;
    if (!UpdatePlayerStartSpot(NewPlayerController, Portal, ErrorMessage))
    {
        UE_LOG(LogGameMode, Warning, TEXT("InitNewPlayer: %s"), *ErrorMessage);
    }
    ...
    FString InName = UGameplayStatics::ParseOption(Options, TEXT("Name")).Left(20);
    ...
}
```

**`AGameModeBase::FindPlayerStart_Implementation`** (paraphrased):

```cpp
AActor* AGameModeBase::FindPlayerStart_Implementation(
    AController* Player, const FString& IncomingName)
{
    UWorld* World = GetWorld();
    if (!IncomingName.IsEmpty())
    {
        const FName IncomingPlayerStartTag = FName(*IncomingName);
        for (TActorIterator<APlayerStart> It(World); It; ++It)
        {
            APlayerStart* Start = *It;
            if (Start && Start->PlayerStartTag == IncomingPlayerStartTag)
            {
                return Start;
            }
        }
    }
    if (Player->StartSpot.IsValid())
    {
        return Player->StartSpot.Get();
    }
    return ChoosePlayerStart(Player);
}
```

### Practical recipes

#### Launch standalone game at a named spawn

```
UnrealEditor.exe "C:\Path\To\MyProject.uproject" /Game/Maps/Test#Arena -game
```

Requirements:
- A `PlayerStart` in `/Game/Maps/Test` with `PlayerStartTag = "Arena"`.
- The active `GameMode` doesn't override `FindPlayerStart_Implementation` in a way that ignores `IncomingName`. (Custom GameModes commonly do; check yours.)

#### Combine with other useful flags

```
UnrealEditor.exe MyProject.uproject /Game/Maps/Test#Arena ^
    -game ^
    -windowed -ResX=1280 -ResY=720 ^
    -log ^
    -NoSplash
```

#### Packaged build

Same URL grammar, just runs against the packaged exe:

```
MyGame.exe /Game/Maps/Test#Arena
```

#### Combine Portal with options

```
MyGame.exe /Game/Maps/Test#Arena?Name=Aaron?SpectatorOnly=1
```

Portal = `Arena`, Op = `["Name=Aaron", "SpectatorOnly=1"]`.

### Things that bite

1. **Custom GameMode overrides.** If a project overrides `ChoosePlayerStart` or `FindPlayerStart` without calling Super or without honoring `IncomingName`, the Portal will be ignored. Worth checking the project's game mode before assuming the URL is broken.

2. **PIE doesn't use the command-line URL by default.** PIE constructs its own URL from the editor's "Play From Here" / start location logic. To exercise Portal in PIE, use Play Mode → Standalone with additional launch parameters set in Editor Preferences, or just launch the editor with `-game`.

3. **`PlayerStartTag` is an `FName`, comparison is case-sensitive at the `FName` level** (case-insensitive in practice because `FName` normalizes). Still, match the casing you authored.

4. **Net travel re-parses URLs.** During seamless travel, the URL is rebuilt; Portal will be preserved through `FURL` copying but custom seamless travel code can drop it.

5. **`StartSpot` fallback.** If `Portal` is empty or no `PlayerStart` matches, `FindPlayerStart_Implementation` falls back to `Player->StartSpot` then to `ChoosePlayerStart`, which means a failed match silently goes to the default spawn — easy to mistake for "Portal didn't work" when actually the tag just didn't match.

### Grep starting points

```
Engine/Source/Runtime/Engine/Classes/Engine/EngineBaseTypes.h   # FURL declaration
Engine/Source/Runtime/Engine/Private/URL.cpp                    # FURL::Parse
Engine/Source/Runtime/Engine/Private/World.cpp                  # SpawnPlayActor
Engine/Source/Runtime/Engine/Private/GameModeBase.cpp           # Login, InitNewPlayer, UpdatePlayerStartSpot, FindPlayerStart
Engine/Source/Runtime/Engine/Classes/GameFramework/PlayerStart.h
```

Useful search terms: `FURL::Parse`, `Portal`, `IncomingName`, `PlayerStartTag`, `UpdatePlayerStartSpot`.

---

## 3. Trace / Insights channels

The `-trace=<csv>` arg controls which Unreal Insights channels are emitted. Channel names (canonical taxonomy from `Engine/Source/Runtime/TraceLog/`):

| Channel | What it captures |
|---|---|
| `default` | Frame, CPU, GPU, Bookmark, Log, Memory — the "everything-on default" set |
| `log` | UE log output |
| `frame` | Frame boundaries |
| `bookmark` | `TRACE_BOOKMARK(...)` markers |
| `screenshot` | Periodic screenshots |
| `stats` | Stat group data |
| `gpu` | GPU command queue / GPU timings |
| `memory` | High-level memory allocation tracking |
| `memtag` | LLM memory tags (requires `-llm`) |
| `cpu` | CPU profiler (named scopes) |
| `animation` | Anim node ticks, blend weights |
| `slate` | UMG / Slate widget activity |
| `csv` | CSV profiler bridge |
| `file` | File I/O timings |
| `loadtime` | Asset load times |
| `savegame` | Save-game ops |
| `taskgraph` | Task-graph dependencies |
| `counters` | Generic counters |
| `regions` | Named regions for selective trace start/stop |
| `rendercommands` | RHI command lists |
| `audiomixer` | Audio mixer activity |

**Companion switches:**

- `-tracehost=<ip>` — stream trace to a live host running Unreal Insights' trace server. Default port 1980.
- `-traceFile=<path>` — write trace to a `.utrace` file on disk instead of streaming.
- `-statnamedevents` — produce CSV-friendly named events.
- `-statunitcsv` — write unit stats as CSV.

**LLM memory tracking:**

- `-llm` — enable Low-Level Memory tracker (must be compile-time-enabled in the build).
- `-llm.AutoReportMemory` — periodic memory dumps.
- Pair with `-trace=memory,memtag` to surface LLM data in Insights.

**Trace regions** (recording only a window of activity):

- `-trace.startat=<frame>` and `-trace.stopat=<frame>` — frame-bounded capture.
- Console commands: `Trace.Start`, `Trace.Stop`, `Trace.Bookmark "name"`.

---

## 4. `-ExecCmds`

Run a semicolon-separated list of console commands after boot.

**Format:** `-ExecCmds="cmd1;cmd2;Quit"` (semicolon-separated, double-quoted at the shell level).

**Standard idioms:**

```
-ExecCmds="Automation RunTests <filter>;Quit"      # automation harness
-ExecCmds="stat fps;stat unit"                     # show perf overlays
-ExecCmds="ce DebugLevel 2;ToggleHUD"              # custom commands
-ExecCmds="Trace.Bookmark BootComplete;stat fps"   # mark trace at boot
-ExecCmds="r.ScreenPercentage 50;Quit"             # quick CVar test
```

When constructing from a channel (Python), pipe through `unreal.cmdline.read_ueified()` to avoid subprocess quoting mangling.

---

## 5. Rendering / windowing

- `-Windowed` — windowed mode (not fullscreen).
- `-FullScreen` — exclusive fullscreen.
- `-WindowedFullScreen` — borderless fullscreen.
- `-ResX=<n>`, `-ResY=<n>` — resolution components.
- `-Resolution=<WxH>` — combined.
- `-RHI=<name>` — render API: `-DX12` / `-DX11` / `-Vulkan` / `-OpenGL` as shortcuts.
- `-NoVSync` — disable vsync.
- `-FrameLimit=<fps>`, `-MaxFps=<fps>` — frame rate cap.
- `-AllowSoftwareRendering` — let SW renderer kick in if HW fails.

---

## 6. Performance / determinism

- `-deterministic` — deterministic frame timing.
- `-FixedSeed` — deterministic random seeds.
- `-StompMalloc` — memory debug allocator (catches use-after-free).
- `-PoisonOSMemory` — poison allocated memory.
- `-MemoryProfiler` — built-in memory profiler.
- `-CrashForUAT` — exit non-zero on engine crash (CI must-have).
- `-NoTextureStreaming` — disable streaming (load everything resident).
- `-NoSound` — disable audio entirely (CI).

---

## 7. Logging

- `-log` — engine log to console.
- `-LogCmds="LogX Verbose, LogY VeryVerbose"` — per-category verbosity overrides.
- `-AbsLog=<path>` — absolute path for the log file (overrides default `Saved/Logs/`).
- `-NoConsole` — suppress console window (when `-log` would normally open one).
- `-stdout` — log to stdout instead of file.
- `-FORCELOGFLUSH` — flush every log line (slow, but catches the last-line-before-crash).
- `-Verbose`, `-VeryVerbose` — global verbosity bumps.

---

## 8. Cooking-specific

(Mirrors what `.cook` injects; useful when calling the commandlet directly via `.run commandlet Cook`):

- `-targetplatform=<platform>` — cook output platform (e.g. `Windows`, `LinuxServer`, `WindowsNoEditor`).
- `-cookcultures=en+fr+de` — cultures to cook (note: `+` separator, not `,`).
- `-iterate` — iterative cook on top of previous output. **Dev only**; never shipping.
- `-forcerecook=false` — used with `-iterate` to retain previous output when sure.
- `-unattended` — no dialog boxes.
- `-unversioned` — don't write package version metadata (CI).
- `-stdout` — log to stdout.
- `-cookonthefly` — launch as cook-on-the-fly server.
- `-noxgeshadercompile` — disable XGE for shader compile.
- `-PackageDir=<path>` — restrict cook to a directory (for ResavePackages too).
- `-Map=<MapName>` — cook only this map.
- `-SkipCookedPackages` — skip packages already cooked.
- `-cooksinglepackage` — cook only the listed package(s).
- `-mapsonlyincook` — only include maps, not loose packages.

---

## 9. Stage / run-cooked specific

(Mirrors what `.stage`/`.run game` injects):

- `-pak` — package into `.pak` files.
- `-iostore` — IO Store packaging (`.utoc`/`.ucas`).
- `-compressed` — Oodle-compress paks.
- `-zenstore` — Zen oplog packaging.
- `-zenstreaming` — Zen streaming mode.
- `-skipbuild`, `-skipcook`, `-skipstage`, `-skiparchive` — skip individual BCR verbs.
- `-deploy` — push to devkit/device.
- `-onthefly` — runtime hits a cook-on-the-fly server.
- `-filehostip=<ip>` — cook-on-the-fly server address.
- `-cookflavor=<flavor>` — platform sub-flavor (ASTC, ETC2, etc.).
- `-platform=<plat>` — for cook + stage.
- `-config=<variant>` — build configuration (Debug/Development/Test/Shipping).
- `-clientconfig=`, `-serverconfig=` — separate client/server configs in one BCR.

---

## 10. Networking / multiplayer

- `-CONNECT=<ip[:port]>` — client direct-connect.
- `<MapName>?Game=<GameModeClass>?Listen` — listen-server boot from map URL.
- `-port=<n>` — server listen port.
- `-multihome=<ip>` — bind to specific NIC.
- `-server -log [<MapName>?Listen]` — dedicated server starting on a map.

---

## 11. Commandlet `-run=<Name>` recipes

With required/typical args:

```
-run=Cook -targetplatform=Win64 -unattended -unversioned
-run=ResavePackages -PackageDir=<dir> [-AutoCheckOutPackages]
-run=DerivedDataCache -fill -unattended
-run=GenerateDistillFileSets
-run=GatherText -config=Config/Localization/<file>.ini
-run=DumpFormalTechDebt
-run=WorldPartitionBuilder <MapPath> -Builder=Minimap
-run=PluginCommandlet
-run=FixupRedirects
-run=RebuildLightMaps -AutoCheckOutPackages
-run=RebuildHLOD -AutoCheckOutPackages
```

Cross-reference: `.run commandlet <Name>` (ushell wrapper) for in-engine route, or `.uat <CommandName>` for the UAT-side variants that exist (e.g. `.uat ResavePackagesCommand`).

---

## 12. Discovering args for a specific project

Where to look:

- `Config/Default*.ini` — many feature toggles via `[Section]` overrides usable as `-ini:Engine:[/Script/Foo]:bSomething=true`.
- `[/Script/AutomatedPerfTesting.*PerfTestProjectSettings]` — `MapsAndSequencesToTest`, `MapsToTest`, `ReplaysToTest`, `SequenceCombos` arrays feed `.perf test`.
- `Source/<Project>/Private/<Project>GameInstance.cpp` and `*GameMode*.cpp` — project-specific `FParse::Param(FCommandLine::Get(), TEXT("Name"))` callers (the bespoke `-stresstest=`, `-modename=`, etc.).
- Engine-side: `Engine/Source/Runtime/Launch/Private/Launch*.cpp` and `Engine/Source/Runtime/CoreUObject/Private/UObject/UObjectGlobals.cpp` for standard switches.
- `Engine/Source/Runtime/CoreUObject/Private/UObject/Class.cpp` — `-ini:` overrides parsing.

---

## 13. Goal → required UE args quick map

| Goal | UE args (after `-- ` in ushell) |
|---|---|
| Capture Insights trace to disk | `-trace=<channels> -traceFile=<path>` |
| Capture Insights trace to live host | `-trace=<channels> -tracehost=<ip>` |
| Spawn at a specific PlayerStart | `<MapName>#<PortalTag>` (matches `APlayerStart::PlayerStartTag`; **not** `?StartPoint=` or `?PlayerStartTag=`) |
| Headless automation run | `-nullrhi -unattended -stdout -log` |
| Run console cmds and quit | `-ExecCmds="cmd1;cmd2;Quit"` |
| Dedicated server | `-server -log [<MapName>?Listen]` |
| Wait for debugger to attach | `-WaitForDebugger` (local only — never CI) |
| LLM memory profile | `-llm -llm.AutoReportMemory -trace=memory,memtag` |
| Force a render API | `-DX12` (or `-Vulkan`, `-OpenGL`) |
| Specific resolution | `-Windowed -ResX=1920 -ResY=1080` |
| Skip startup map | `-NoLoadStartupPackages` |
| Cook a single map only | `-run=Cook -targetplatform=<P> -Map=<MapName>` |
| Listen-server start | `<MapName>?Listen?Game=<GameModeClass>` |
| Client direct-connect | `-CONNECT=<ip:port>` |
| Resave a content directory | `-run=ResavePackages -PackageDir=<dir>` |
| Per-category verbose logging | `-LogCmds="LogX Verbose, LogY VeryVerbose"` |
| CSV perf profiler | `-statnamedevents -statunitcsv` |
| Force log flush after each line (CI debug) | `-FORCELOGFLUSH` |

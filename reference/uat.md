# UAT — Unreal Automation Tool

ushell's `.uat` is the wrapper; UAT is the underlying tool. This file covers UAT directly — when ushell's higher-level verbs (`.build`, `.cook`, `.stage`) don't fit (shipping builds, plugin packaging, BuildGraph orchestration, signed/encrypted paks, custom test harnesses), drive UAT yourself via `.uat <Command> -- <args>`.

## TOC

1. The UAT contract
2. `BuildCookRun` — the workhorse
3. Other UAT commands (per lifecycle area)
4. Testing via UAT (Gauntlet `RunUnreal`)
5. Engine-side `Automation` exec command
6. Canonical shipping / CI invocations
7. Top community gotchas
8. Sources of truth
9. Public CI examples to cite

---

## 1. The UAT contract

**Entry:** `Engine/Build/BatchFiles/RunUAT.bat` (Windows), `RunUAT.sh` (POSIX), `RunUAT.command` (mac).

**Argv:** `RunUAT <CommandName> [-Name=Value]...`

**Command discovery:** UAT scans `Engine/Source/Programs/AutomationTool/Scripts/*.Automation.cs` and project-side `Build/*.Automation.csproj` for `BuildCommand` subclasses. The first positional argv is matched against class names.

**`-help` is incomplete.** Many practical flags are not listed by `--help` output. For canonical flag definitions, read:
- `Engine/Source/Programs/AutomationTool/AutomationUtils/ProjectParams.cs` — every BCR/UAT flag.
- The `*.Automation.cs` file for the specific command.

**Exit codes:** standard UAT exit codes are integers; non-zero = failure. `ExitCode.Success = 0`, `ExitCode.Error_TestFailure` and friends are in `Engine/Source/Programs/AutomationTool/AutomationUtils/Automation.cs`.

**Through ushell:** `.uat <Command> -- <args>` invokes RunUAT and forwards `<args>` after the `--` boundary. ushell automatically:
- Builds UAT first via `BuildUAT.bat` (compiles AutomationTool.csproj).
- Injects `-project=<active uproject>` unless `--unprojected`.
- Injects `-ScriptsForProject=<project name>` unless `--allscripts`.
- Sets `DOTNET_CLI_TELEMETRY_OPTOUT=1`.

---

## 2. BuildCookRun — the workhorse

The single UAT command that orchestrates the full build pipeline.

### 2.1 Seven verbs in fixed order

```
Build → Cook → Stage → Package → Archive → Deploy → Run
```

Dispatched in this order in `BuildCookRun.Automation.cs:258-266`. Each has a `-<verb>` flag to enable it (`-build`, `-cook`, `-stage`, `-package`, `-archive`, `-deploy`, `-run`) and a `-skip<verb>` flag to disable it (`-skipbuild`, `-skipcook`, `-skipstage`, `-skiparchive`).

By default, no verbs run — you opt in. The exception: BCR auto-enables some predecessors when you enable a successor.

### 2.2 ProjectParams flag catalogue

`ProjectParams.cs` is the truth source for every BCR flag. Grouped by lifecycle area:

**Build:**
- `-build`, `-skipbuild`
- `-targetplatform=<P>`, `-platform=<P>` (interchangeable on BCR)
- `-target=<Name>[+<Name2>...]` (multi via `+`)
- `-clientconfig=<Config>`, `-serverconfig=<Config>`
- `-server`, `-noclient`, `-client`
- `-serverplatform=<P>`
- `-Distribution`
- `-ubtargs="<UBT-flags>"` (passes through to UBT)
- `-clean`
- `-buildmachine` (critical for CI: disables modals/crash reporter, removes warning caps, dumps cook timing CSV)

**Cook:**
- `-cook`, `-skipcook`
- `-iterate` — iterative cook. **Dev only**; never shipping.
- `-iterativecooking`, `-iteratesharedcookedbuild`, `-fastcook`
- `-mapsonlyincook`, `-cooksinglepackage`
- `-cookflavor=<F>`, `-CookCultures=<csv>`, `-cookoverrides=<file>`
- `-fullcleanafteriterate`
- `-CookCommandletArgs="<passthrough>"`
- `-RunAssetNudge`
- `-mpcook=<N>` (multi-process cook)
- `-iostore`, `-zenstore`, `-nozenstore`

**Stage:**
- `-stage`, `-skipstage`
- `-stagingdirectory=<path>` — **must be passed on CLI** (Project Settings is ignored)
- `-stagecommandline="<inner args>"`, `-cmdline="<args>"`
- `-skiplevelchecks`, `-NoCleanStage`
- `-pak`, `-skippak`, `-compressed`, `-uncompressed`
- `-AdditionalStagedFiles=<list>`
- `-CustomDeploymentHandler=<class>`

**Package:**
- `-package`, `-skippackage`
- `-skipencryption`, `-encryptinifiles`
- `-signpak`, `-signpakid=<id>`, `-cryptokeys=<keychain.json>`
- `-EncryptionIni=<file>`
- `-zenstreaming`

**Archive:**
- `-archive`, `-skiparchive`
- `-archivedirectory=<path>`
- `-archivemetadata`

**Deploy:**
- `-deploy`, `-deploydir=<path>`, `-deployworkspace=<path>`

**Run:**
- `-run`, `-runargs="<inner argv>"`, `-addcmdline="<args>"`, `-cmdline="<args>"`
- `-attach`, `-nullrhi`
- `-test=<TestName>` — chains into Gauntlet flow.
- `-RunAutomationTest=<filter>` — **legacy and fragile** (see §4 and §7).

**CI / build-machine:**
- `-buildmachine` — must-have for CI.
- `-CrashForUAT` — non-zero exit on engine crash.
- `-NoSign`, `-NoCodeSign`
- `-NoSubmit`
- `-buildversion=<ver>`
- `-PreFlightChange=<cl>`
- `-utf8output`
- `-stdlog`

**P4:**
- `-NoP4`, `-nop4` (case-insensitive)
- `-Submit`, `-AllowSubmit`
- `-WorkingCL=<cl>`

### 2.3 -pak / -iostore / -zenstore interaction

Subtle and gets people. UE 5.x defaults:

- `-pak` alone: legacy pak files.
- `-pak -iostore -compressed`: modern UE 5 default. Produces `.pak` + `.utoc` + `.ucas` triad with Oodle compression.
- `-iostore` without `-pak`: IO Store-only — `.utoc`/`.ucas` ride alongside an implicit `.pak`.
- `-zenstore`: Zen Store oplog packaging (the modern modern path). Replaces pak/utoc/ucas.
- `-zenstreaming`: Zen Loader streaming mode for devkits with low local storage.

**Project Settings interaction:** If Project Settings → Packaging → "Use IO Store" is enabled but you pass `-pak` without `-iostore`, you get **hybrid loose+pak output**. Match your CLI flags to your Project Settings to avoid surprise. If Zen Store is enabled in settings and not on the command line, BCR may produce empty paks.

### 2.4 Multi-target invocations

- One platform, one target: `-target=MyGame -platform=Win64 -clientconfig=Shipping`.
- Client + dedicated server in one BCR: `-target=MyGame+MyGameServer -platform=Win64 -server -serverplatform=Linux -clientconfig=Shipping -serverconfig=Shipping`.
- Multi-platform cook in one go: `-platform=Win64+Linux` (BCR iterates).

For CI, **splitting into two BCR calls** (one for client, one for server) is often cleaner — separate archive paths, separate logs.

### 2.5 Iterative cook gotcha

`-iterate` is **dev only**. Community-confirmed: assets without source changes get re-cooked anyway under some conditions, and assets *with* indirect dependency changes sometimes *don't* — meaning iterative cook can produce silently stale paks. **Never use `-iterate` for shipping builds.** Always full `-cook` for release.

Use `-iteratesharedcookedbuild` instead if you want to bootstrap from a shared cook output (CI seeds dev iteration).

### 2.6 The canonical "build my game for shipping" 5.x invocation

```
"<UE_ROOT>\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun ^
  -project="<full path>\MyGame.uproject" ^
  -target=MyGame ^
  -platform=Win64 ^
  -clientconfig=Shipping ^
  -build -cook -stage -pak -iostore -compressed -package -archive ^
  -archivedirectory="<full path>\Out" ^
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

**Append for CI:** `-buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog`.

Through ushell: `.uat BuildCookRun -- <the args above>`.

### 2.7 Recipe gallery (15 idiomatic invocations)

All invocations show the args after `.uat BuildCookRun --`. Substitute your project path and engine root.

**1. Editor-only sanity build**
```
-project=<path> -build -editor -platform=Win64 -clientconfig=Development -skipcook -skipstage
```
*Use:* confirm the editor compiles after a sync.

**2. Dev client for one platform**
```
-project=<path> -build -platform=Win64 -clientconfig=Development -skipcook -skipstage
```
*Use:* PC dev loop; produce the client binary without staging.

**3. Dev server for one platform**
```
-project=<path> -build -server -serverplatform=Linux -serverconfig=Development -noclient -skipcook -skipstage
```
*Use:* fast iteration on server logic.

**4. Shipping packaged game (pak)**
```
-project=<path> -target=MyGame -platform=Win64 -clientconfig=Shipping
-build -cook -stage -pak -compressed -package -archive
-archivedirectory=<out> -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```
*Use:* old-school pak shipping.

**5. Shipping packaged game (IoStore — modern)**
```
... -pak -iostore -compressed ...
```
*Use:* modern UE 5 default. `.utoc`/`.ucas` alongside `.pak`.

**6. Shipping packaged game (Zen)**
```
... -zenstore -zenstreaming ...
```
*Use:* Zen Loader path. Requires Zen enabled in Project Settings.

**7. Distribution build for store submission**
```
... -encryptinifiles -signpak -signpakid=<id> -cryptokeys=<path>
-Distribution -PreFlightChange=<cl> ...
```
*Use:* Marketplace / store-grade signed and encrypted build.

**8. Iterative cook (dev only)**
```
-project=<path> -cook -iterate -fastcook -stage
-platform=Win64 -clientconfig=Development
```
*Use:* dev iteration. **Never ship from this.**

**9. Build + cook + stage + run for automation tests**
```
-project=<path> -build -cook -stage -pak -run -test=UE.EditorAutomation
-platform=Win64 -clientconfig=Development -unattended -nullrhi -CrashForUAT
```
*Use:* one-shot CI gate. Prefer §4 split (BCR for build, RunUnreal for test) for cleaner reporting.

**10. "Just stage, I already cooked"**
```
-project=<path> -skipbuild -skipcook -stage -pak
-platform=Win64 -clientconfig=Development -stagingdirectory=<path>
```
*Use:* re-stage with different output paths without rebuilding.

**11. "Just deploy what I staged earlier"**
```
-project=<path> -skipbuild -skipcook -skipstage -deploy -deploydir=<remote>
```
*Use:* push existing stage to a freshly-flashed devkit.

**12. Multi-platform in one invocation**
```
-project=<path> -platform=Win64+Linux -target=MyGame+MyGameServer
-clientconfig=Shipping -serverconfig=Shipping
-build -cook -stage -pak -iostore -compressed
```
*Use:* CI matrix in one BCR call. May be cleaner as two separate calls for archive layout.

**13. Cooked-editor pipeline**
```
-project=<path> -target=MyGameCookedEditor -CookedEditor
-platform=Win64 -clientconfig=Development -build -cook -stage
```
*Use:* thin-client cooked-editor scenarios.

**14. Plugin-aware build**
```
-project=<path> -PluginsList=Plugins/X.uplugin+Plugins/Y.uplugin
-target=MyGame -platform=Win64 -clientconfig=Development -build
```
*Use:* restrict to specific plugins (less common; usually you build all enabled).

**15. Mobile shipping (iOS)**
```
-project=<path> -platform=IOS -clientconfig=Shipping
-build -cook -stage -package -iphonepackager -Distribution
-SigningCertificate=<name> -MobileProvision=<path>
-archive -archivedirectory=<out>
```
*Use:* iOS submission build. Requires the iOS toolchain + signing identities.

### 2.8 Top BCR gotchas

- **Project Settings → StagingDirectory is IGNORED by UAT.** Always pass `-stagingdirectory=` and `-archive -archivedirectory=` explicitly.
- **`-buildmachine` is the magic CI flag.** Disables modals, crash reporter, removes warning caps, dumps cook-timing CSV. Without it, CI builds hang on dialogs.
- **`-platform=` vs `-targetplatform=`:** both accepted by BCR; other UAT commands (`BuildTarget`, `BuildGame`) only honour `-platform=`. Match the command.
- **`-RunAutomationTest=` under BCR is fragile** — the client process can exit before UAT polls; "BUILD FAILED" reported on green tests. Use `RunUnreal -test=` (Gauntlet) or `UnrealEditor-Cmd.exe -ExecCmds="Automation RunTests ...; Quit" -ReportExportPath=` instead.
- **`-help` output for BCR is incomplete.** Many practical flags are not listed. Read `ProjectParams.cs` directly for the canonical list.

---

## 3. Other UAT commands

Per-command entries grouped by lifecycle area. Through ushell: `.uat <Command> -- <args>`.

### 3.1 Plugin lifecycle

#### `BuildPlugin`

Compiles a `.uplugin` for distribution.

- **Required:** `-Plugin=<path-to-.uplugin>`, `-Package=<output-dir>`.
- **Critical gotcha:** Since 4.25, `BuildPlugin` defaults to **all** detected SDK platforms (TVOS, Android, HoloLens, IOS, Linux, LinuxAArch64, Win64). Without `-TargetPlatforms=Win64+Linux+...` it tries every SDK and aborts on missing ones.
- **Marketplace flags:** `-Rocket` (binary engine layout), `-StrictIncludes` (IWYU enforcement).
- **Engine-version locked:** binary plugins compatible at the minor level (5.4.x), incompatible across minor (5.4 ↔ 5.5).

**Canonical invocation:**

```
.uat BuildPlugin -- ^
  -Plugin="<full path>\MyPlugin.uplugin" ^
  -Package="<output dir>" ^
  -TargetPlatforms=Win64+Linux ^
  -Rocket -StrictIncludes ^
  -unattended -nop4
```

### 3.2 Engine / tool building

- **`BuildCommonTools`** — builds standard UE tools (UHT, ShaderCompileWorker, UnrealPak, etc.) per platform.
- **`BuildTarget`** — compile arbitrary UBT targets. Accepts `-target=Editor+Game+Server -platform=Win64+Linux -configuration=Development+Shipping`. The lower-level companion to BCR.
- **`BuildCMakeLib`, `BuildHlslcc`, `BuildThirdPartyLibs`** — third-party library build wrappers.

### 3.3 Project lifecycle (non-BCR)

- **`SyncProject`** — sync engine + project from P4 with BuildGraph dependency expansion.
- **`SyncBinariesFromUGS`** — pull precompiled binaries from UGS storage.
- **`UpdateLocalVersion`** — stamp `Build.version` with build metadata.
- **`OpenEditor`** — invoke the editor with UAT-injected environment.

### 3.4 Content / data ops

- **`ResavePackagesCommand`** — UAT wrapper around the ResavePackages commandlet; P4-required, designed for lightmap rebuilds in Epic's internal CI. Note: the **inner** ResavePackages commandlet uses `-PackageFolder=<filesystem-path>` / `-Package=<Name>` / `-Map=<MapName>` to restrict scope — **NOT `-PackageDir=`** (that flag doesn't exist for this commandlet). See `reference/unreal-args.md` §11 ResavePackages scope.
- **`FixupRedirects`** — flush soft-reference redirects.
- **`RebuildHLODCommand`** — rebuild Hierarchical LODs.
- **`RebuildLightMapsCommand`** — rebuild lightmaps.
- **`WorldPartitionBuilder`** — World Partition data baking.
- **`WrangleContentForDebugging`** — strips content for symbol-rich debug builds.

### 3.5 Localisation

- **`Localisation`** — gather, compile, export. Drives `-run=GatherText` commandlet pipelines.

### 3.6 Build infra

- **`BuildDerivedDataCache`** — DDC fill (build a shared cache for distribution).
- **`Virtualization`** — virtualised asset payload management.
- **`CopySharedCookedBuild`** — fetch a shared cooked-build seed for `-iteratesharedcookedbuild`.
- **`CleanFormalBuilds`** — strip a formal build directory of intermediate artefacts.
- **`Bisect`** — UAT-driven bisect harness (separate from ushell's `.p4 bisect`).

### 3.7 Packaging / signing / paks

- **`ExtractPaks`** — extract `.pak`/`.utoc`/`.ucas` archives.
- **`CryptoKeys`** — generate/encrypt signing keys for use with `-cryptokeys=`.
- **`IPhonePackager`** — iOS signing, packaging, IPA generation.
- **`UnsignedFilesViolationCheck`** — verify signed-build expectations.

### 3.8 Mobile / Apple

- **`GenerateDSYM`** — Apple debug symbols.
- **`ListMobileDevices`** — discover connected devices.
- **`SetSecondaryRemoteMac`** — multi-Mac iOS build farms.

### 3.9 Multi-process / perf / utility

- **`LaunchMultiServer`** — spin up N dedicated servers (matchmaking/playtest).
- **`MultiClientLauncher`** — spin up N game clients (net-replication testing).
- **`BenchmarkBuild`** — wall-clock the build pipeline.
- **`RecordPerformance`** — perf-record wrapper.
- **`GetFileCommand`** — fetch a file via UAT's HTTP/Horde plumbing.
- **`ZipUtils`** — Zip/Unzip used internally by UAT.
- **`AnalyzeThirdPartyLibs`, `ListThirdPartySoftware`** — TPS reporting.
- **`DedupeAutomationScripts`** — clean duplicate UAT script discoveries.
- **`MegaXGE`** — single-host XGE distribution.
- **`StageLiveLinkHub`** — stage LiveLinkHub binaries.

---

## 4. Testing via UAT — Gauntlet `RunUnreal`

`RunUnreal` is THE Gauntlet entry point. **No separate `RunGauntlet.cs`.**

### 4.1 Invocation shape

```
RunUAT RunUnreal -test=<TestName>[(K=V,K=V)] [-test=<More>,...] \
    -build=<staged_dir|editor> -platform=<P> -configuration=<C> \
    [other flags]
```

`-test=` accepts a comma-separated list. Per-test parameters in parens: `BootTest(MapName=Foo,Loops=2)`. Platform per-test override: `UE.EditorAutomation(Platform=Win64)`.

### 4.2 Default discovery namespaces

`Gauntlet.UnrealTest`, `UnrealGame`, `UnrealEditor`. The `AutomatedPerfTesting.Automation.dll` plugin adds `AutomatedPerfTest.*` test nodes.

### 4.3 Important test nodes

- **`UE.EditorAutomation`** — in-editor `FAutomationTestBase` tests; `-RunTest=<filter>` selects.
- **`UE.TargetAutomation`** — cooked-target automation; editor hosts, target runs.
- **`UE.BootTest` / `EditorBootTest` / `TargetBootTest`** — boot-to-front-end + clean exit.

### 4.4 Report output

- **No native JUnit export.** Output is JSON at `<ReportExportPath>/index.json` + HTML at `index.html` + per-test artifacts (screenshots, logs).
- For JUnit XML you must **post-process `index.json`** or use `RunLowLevelTests` (Catch2-based, emits JUnit natively via `--reporter=junit`).
- `-WriteTestResultsForHorde` activates the Horde-friendly JSON format.

### 4.5 Headless flags

Standard tetrad: `-unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT`. Often auto-set by `EditorAutomation` / `TargetAutomation`; redundant but harmless.

### 4.6 Failure modes

- **Crash:** `-CrashForUAT` ensures non-zero exit. Gauntlet returns `UnrealProcessResult.EngineTestError`.
- **Hang:** detected via log-idle monitor. Set `-LogIdleTimeout=<seconds>` (default 30 min for automation, 10 min for boot). Outer cap `-MaxDuration=<seconds>` (default 3600). `-NoTimeout` to disable.
- **No matching tests:** Gauntlet returns `UnrealProcessResult.InitializationFailure`, non-zero exit, message `"No tests were executed!"`.
- **Device disconnect mid-test:** log-idle fires; if `ResumeOnCriticalFailure=true` + retries remain (default 3), pass resumes from the next test.

### 4.7 `.perf test` → RunUnreal mapping

ushell's `.perf test sequence Win64 perf <Combo>` resolves to:

```
RunUAT RunUnreal --
  -test=AutomatedPerfTest.SequenceTest
  -AutomatedPerfTest.DoPerf
  -platform=Win64 -configuration=test -iterations=6 -target=Game
  -build=<project>/Saved/StagedBuilds/Windows
  -AutomatedPerfTest.TestID=<project>-perf-autoperftest-ushell
  -AutomatedPerfTest.DoCSVProfiler
  -AutomatedPerfTest.TraceChannels=default,screenshot,stats
  -resX=1920 -resY=1080
  -LocalReports
  -AutomatedPerfTest.SequencePerfTest.MapSequenceName=<Combo>
```

`subtest=all` runs perf+llm+insights+gpuperf sequentially. Defaults from `Engine/Plugins/Performance/AutomatedPerfTesting/<...>/AutomatedPerfTestCommonSettings.xml`.

Source: `<ushell>/channels/unreal/core/cmds/perftest.py:217-237`.

### 4.8 Canonical CI smoke invocation

```
.uat RunUnreal -- ^
  -project=MyProject ^
  -test=UE.EditorAutomation -RunTest="Filter:Smoke" ^
  -build=editor -platform=Win64 -configuration=Development ^
  -ReportExportPath="%WORKSPACE%\AutoReport" -WriteTestResultsForHorde ^
  -MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT ^
  -NoP4 -NoSubmit
```

**Filter syntax:**
- `Filter:Smoke` — all tests with `EAutomationTestFlags::SmokeFilter`.
- `Project.Combat` — substring match on beautified test name.
- `^Project.Combat$` — anchored match (no substring).
- `Group:<name>` — expand from `UAutomationControllerSettings::Groups` ini.

### 4.9 Canonical packaged-target smoke

```
.uat RunUnreal -- ^
  -project=MyProject ^
  -test=UE.TargetAutomation -RunTest="Project.Smoke" ^
  -build="<archived path>\WindowsClient" ^
  -platform=Win64 -configuration=Shipping ^
  -ReportExportPath="<output>\TestReport" ^
  -WriteTestResultsForHorde ^
  -MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT
```

`UE.TargetAutomation` requires both an `Editor` host role (build-machine-side) and a `Client` role on the target (devkit or local).

---

## 5. Engine-side `Automation` exec command

When Gauntlet is overkill (simple smoke tests, ad-hoc filter), drive the editor directly:

```
.run editor -- -ExecCmds="Automation <verb> <args>;Quit" -ReportExportPath=<dir> -unattended -nullrhi -stdout
```

### 5.1 Verbs

| Verb | Behaviour |
|---|---|
| `List` | Dump every visible test name then complete. |
| `RunTests <spec>` / `RunTest <spec>` | Run tests matching `<spec>` filter. |
| `RunAll` | Run every visible test. |
| `RunFilter <flag>` | Filter group: `Engine | Smoke | Stress | Perf | Product | Standard | Negative | All`. |
| `SetFilter <flag>` | Set requested flags without running. |
| `SetMinimumPriority Critical|High|Medium|Low|None` | Priority gate. |
| `SetPriority Critical|High|Medium|Low|None` | Priority filter. |
| `Quit` | After tests, request exit with status (non-zero if any errors). |
| `SoftQuit` | Same, but non-forced. |
| `Now` | Skip the find-workers delay timer. |
| `IgnoreLogEvents`, `EnableStereoTests`, `SetTagFilter <tag>` | Misc toggles. |
| `Help` | Print supported commands. |

### 5.2 Filter syntax

Split on `+` and applied per-token:
- `Group:<name>` — expand from ini.
- `StartsWith:<text>` — anchored prefix match.
- `^<text>` — start anchor.
- `<text>$` — end anchor.
- Bare `<text>` — substring match on beautified test name.

### 5.3 Report output

Same as Gauntlet: `<ReportExportPath>/index.json` + HTML + per-test artifacts. **No native JUnit.** Post-process JSON to JUnit if downstream needs it.

---

## 6. Canonical shipping / CI invocations

### 6.1 Shipping single-platform

```
.uat BuildCookRun -- ^
  -project="<full path>\MyGame.uproject" ^
  -target=MyGame ^
  -platform=Win64 ^
  -clientconfig=Shipping ^
  -build -cook -stage -pak -iostore -compressed -package -archive ^
  -archivedirectory="<full path>\Out" ^
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

### 6.2 Shipping client + dedicated server

```
.uat BuildCookRun -- ^
  -project="<full path>\MyGame.uproject" ^
  -target=MyGame+MyGameServer ^
  -platform=Win64 -serverplatform=Linux ^
  -clientconfig=Shipping -serverconfig=Shipping ^
  -build -cook -stage -pak -iostore -compressed -package -archive ^
  -archivedirectory="<full path>\Out" ^
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

### 6.3 CI baseline (append to any shipping invocation)

```
-buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog
```

These six flags collectively:
- Disable all modal dialogs (`-buildmachine`).
- Force non-zero exit on engine crash (`-CrashForUAT`).
- Skip code signing (`-NoCodeSign`) — assume CI handles signing externally.
- Disable audio init (`-nosound`).
- Standardise log format (`-stdlog`).

### 6.4 Plugin packaging (Marketplace-grade)

```
.uat BuildPlugin -- ^
  -Plugin="<full path>\MyPlugin.uplugin" ^
  -Package="<output dir>" ^
  -TargetPlatforms=Win64+Linux ^
  -Rocket ^
  -StrictIncludes ^
  -unattended -nop4
```

### 6.5 BuildGraph invocation

```
.uat BuildGraph -- ^
  -script=<path-to-script.xml> ^
  -target=<NodeName> ^
  -set:Property1=Value1 ^
  -set:Property2=Value2 ^
  [-listonly | -singlenode=<Name> | -resume | -clean | -cleannode=<Name>]
```

See `reference/buildgraph.md` for the full BuildGraph reference.

---

## 7. Top community gotchas (consolidated)

1. **`-platform=` vs `-targetplatform=` vs `-clientconfig=` vs `-configuration=` is a maze.** BCR accepts both `-platform=` and `-targetplatform=`. Other UAT commands (`BuildTarget`, `BuildGame`) only honour `-platform=`. Build *configuration* splits into `-clientconfig=` and `-serverconfig=`; `-configuration=` is the UBT-level flag accepted by `BuildTarget`/`BuildEditor`. Pick wrong and you silently build the host target instead.

2. **`BuildPlugin` builds every detected SDK platform by default (since 4.25).** Always set `-TargetPlatforms=Win64+...` explicitly, even if you "know" Linux isn't installed — UAT may still try it and abort.

3. **`-pak`, `-iostore`, `-zenstore` interactions trip people up.** `-pak` alone is legacy; UE5 defaults the IO Store path. Setting `-pak` without `-iostore` while `Use IoStore` is enabled in Project Settings produces hybrid loose+pak output. The opposite (`-iostore` without `-pak`) is also surprising — `.utoc/.ucas` always rides alongside a `.pak` container. The 5.4/5.5 Zen Store transition adds `-zenstore` for the cooked-output side.

4. **Iterative cook (`-iterate`) stales easily.** Community-confirmed: assets without source changes still get re-cooked under some conditions, and assets *with* indirect dependency changes sometimes *don't*. Iterative cook can produce silently stale paks. Forum guidance: *"use iterate for dev iteration, never for shipping builds; always use a clean `-cook` for release."*

5. **Project Settings → Packaging → StagingDirectory is ignored by RunUAT.** This is a perennial forum complaint. RunUAT only honors command-line `-stagingdirectory=` and `-archive -archivedirectory=`. Setting it in the editor gives a false sense of control.

6. **`-buildmachine` is the CI must-have.** Disables modals, crash reporter, removes warning caps, dumps cook-timing CSV. CI builds without it hang on dialogs.

7. **`-RunAutomationTest=` under BCR is fragile.** The client exits before UAT polls; "BUILD FAILED" reported on green tests. Prefer Gauntlet `RunUnreal` or direct editor `-ExecCmds=`.

---

## 8. Sources of truth

When `--help` lies or is incomplete, these files are canonical:

- `Engine/Source/Programs/AutomationTool/AutomationUtils/ProjectParams.cs` — BCR/UAT flag definitions.
- `Engine/Source/Programs/AutomationTool/Scripts/BuildCookRun.Automation.cs` — verb ordering, execution loop.
- `Engine/Source/Programs/AutomationTool/Scripts/BuildPluginCommand.Automation.cs` — plugin packaging.
- `Engine/Source/Programs/AutomationTool/BuildGraph/BuildGraph.cs` — BuildGraph CLI.
- `Engine/Source/Programs/AutomationTool/BuildGraph/BgScriptReader.cs` — BuildGraph XML schema implementation.
- `Engine/Source/Programs/AutomationTool/BuildGraph/Tasks/*.cs` — every BuildGraph task element (`[TaskElement("Name", typeof(ParamsClass))]`).
- `Engine/Source/Programs/AutomationTool/Gauntlet/Unreal/RunUnreal.cs` — RunUnreal entry.
- `Engine/Source/Programs/AutomationTool/Gauntlet/Unreal/Base/Gauntlet.UnrealTestContext.cs` — Gauntlet options.
- `Engine/Source/Programs/AutomationTool/Gauntlet/Unreal/Automation/UE.Automation.cs` — automation test config.
- `Engine/Source/Developer/AutomationController/Private/AutomationCommandline.cpp` — engine-side `Automation` exec command.
- `Engine/Source/Runtime/Core/Public/Misc/AutomationTest.h` — `IMPLEMENT_*_AUTOMATION_TEST` macros.

---

## 9. Public CI examples to cite

When the user asks "show me a real CI pipeline":

- **CircleCI:** `vela-games/circleci-ue5-game` — full BuildGraph with 4 agents (Win/Linux × build/cook).
- **TeamCity:** `jamescallin/teamcity-UEBuildGraph` — BuildGraph runner with UGS notifier.
- **GitHub Actions:** `marketplace/actions/ue5-build-project` — parameterised BCR wrapper. `Guganana/UnrealPluginCIWithGithubActions` — plugin-marketplace flow.
- **Jenkins:** Medium article `@lifeexe/unreal-engine-ci-part-02` — parameterised freestyle.
- **Most useful single-doc reference:** `botman99/ue4-unreal-automation-tool` README — concrete RunUAT examples, log path locations, common gotchas.

Epic's official documentation (URLs valid as of 2025-05):
- `dev.epicgames.com/documentation/en-us/unreal-engine/unreal-automation-tool-for-unreal-engine`
- `dev.epicgames.com/documentation/en-us/unreal-engine/buildgraph-for-unreal-engine`
- `dev.epicgames.com/documentation/en-us/unreal-engine/gauntlet-automation-framework-in-unreal-engine`

# UAT research notes — digested for plan execution

Captured: 2026-05-13. Source: five parallel research agents (BuildCookRun deep-dive, other UAT scripts catalog, BuildGraph deep-dive, testing/Gauntlet harness, online docs + community usage). This file is the working digest. When implementing `reference/uat.md` and `reference/buildgraph.md`, this is the seed material.

---

## A. BuildCookRun — the workhorse

**File:** `Engine/Source/Programs/AutomationTool/Scripts/BuildCookRun.Automation.cs`
**Truth source for every flag:** `Engine/Source/Programs/AutomationTool/AutomationUtils/ProjectParams.cs`

### A.1 Seven verbs in fixed order
`Build → Cook → Stage → Package → Archive → Deploy → Run`. Dispatched in `DoBuildCookRun` at `BuildCookRun.Automation.cs:258-266`. Each has a `-skip<verb>` counterpart and a positive `-<verb>` enabler.

### A.2 ProjectParams flag categories
Grouped (from `ProjectParams.cs`):

- **Build:** `-build`, `-skipbuild`, `-targetplatform=`, `-platform=`, `-target=` (multi via `+`), `-clientconfig=`, `-serverconfig=`, `-server`, `-noclient`, `-client`, `-Distribution`, `-ubtargs=`, `-clean`, `-buildmachine`.
- **Cook:** `-cook`, `-skipcook`, `-iterate`, `-iterativecooking`, `-iteratesharedcookedbuild`, `-fastcook`, `-mapsonlyincook`, `-cooksinglepackage`, `-cookflavor=`, `-CookCultures=`, `-cookoverrides=`, `-fullcleanafteriterate`, `-CookCommandletArgs=`, `-RunAssetNudge`, `-mpcook=N` (multi-process), `-iostore`, `-zenstore`, `-nozenstore`.
- **Stage:** `-stage`, `-skipstage`, `-stagingdirectory=`, `-stagecommandline=`, `-cmdline=`, `-skiplevelchecks`, `-NoCleanStage`, `-pak`, `-skippak`, `-compressed`, `-uncompressed`, `-AdditionalStagedFiles=`, `-CustomDeploymentHandler=`.
- **Package:** `-package`, `-skippackage`, `-skipencryption`, `-encryptinifiles`, `-signpak`, `-signpakid`, `-keychain=`, `-EncryptionIni=`, `-zenstreaming`.
- **Archive:** `-archive`, `-archivedirectory=`, `-archivemetadata`, `-skiparchive`.
- **Deploy:** `-deploy`, `-deploydir=`, `-deployworkspace=`.
- **Run:** `-run`, `-runargs=`, `-addcmdline=`, `-attach`, `-nullrhi`, `-test=` (chains into RunUnreal-style flow), `-RunAutomationTest=` (legacy — fragile, see gotchas).
- **CI/CD/UGS:** `-buildmachine` (critical — disables modals/crash reporter, removes warning caps, dumps cook timing CSV), `-CrashForUAT`, `-NoSign`, `-NoSubmit`, `-buildversion=`, `-PreFlightChange=`, `-utf8output`, `-stdlog`.
- **P4:** `-NoP4`, `-Submit`, `-AllowSubmit`, `-WorkingCL=`.

### A.3 `-pak` / `-iostore` / `-zenstore` / `-zenstreaming` interaction
- Default 5.x behaviour with IO Store on in Project Settings: `-pak` produces `.pak + .utoc + .ucas` triad.
- `-iostore` flag explicitly forces IO Store packaging; without `-pak`, you still get `.utoc/.ucas` riding alongside a `.pak`.
- `-zenstore` (Zen Store) replaces the pak/utoc/ucas with a Zen oplog. Enabled by default if Project Settings has Zen Store on **and** the cook output writes the `ue.projectstore` marker.
- `-zenstreaming` enables Zen Loader's streaming-from-server mode (for devkits with low local storage).
- Setting `-iostore` while Project Settings disables IO Store will produce hybrid loose+pak output (community gotcha).

### A.4 Multi-target invocations
- One platform, one target: `-target=MyGame -platform=Win64 -clientconfig=Shipping`.
- Client + dedicated server in one BCR: `-target=MyGame+MyGameServer -platform=Win64 -server -serverconfig=Shipping`.
- Multi-platform cook in one go: `-platform=Win64+Linux` (BCR iterates).

### A.5 Iterative cook gotcha (community-confirmed)
`-iterate` is for dev iteration only. Real-world reports of stale assets surviving `-iterate` even with source-asset modtime changes; conversely, assets with **indirect** dependency changes may not get re-cooked. **Never use `-iterate` for shipping builds.** Always `-cook` clean for release. Use `-iteratesharedcookedbuild` instead if you want to bootstrap from a shared cook output.

### A.6 The canonical "build my game for shipping" 5.x invocation

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

Append for CI:
`-buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog`

### A.7 Recipe gallery (15 idiomatic invocations)

1. **Editor-only sanity build:** `BuildCookRun -project=... -build -editor -platform=Win64 -clientconfig=Development -skipcook -skipstage`
2. **Dev client one platform:** `BuildCookRun -project=... -build -platform=Win64 -clientconfig=Development -skipcook -skipstage`
3. **Dev server one platform:** `... -server -serverplatform=Linux -serverconfig=Development -noclient`
4. **Shipping packaged game (pak):** the §A.6 canonical above with `-pak` only.
5. **Shipping packaged game (IoStore — modern):** `-pak -iostore -compressed`.
6. **Shipping packaged game (Zen):** `-zenstore -zenstreaming` (requires Zen-enabled project).
7. **Distribution build for store submission:** add `-encryptinifiles -signpak -signpakid=<id> -keychain=<path> -Distribution -PreFlightChange=<cl>`.
8. **Iterative cook (dev only):** `-cook -iterate -fastcook -stage`.
9. **Build + cook + stage + run for automation tests:** add `-run -test=<TestName> -unattended -nullrhi -RunAutomationTest="Filter:Smoke" -CrashForUAT`.
10. **"Just stage, I already cooked":** `-skipbuild -skipcook -stage -pak -platform=Win64 -clientconfig=Development -stagingdirectory=<path>`.
11. **"Just deploy what I staged":** `-skipbuild -skipcook -skipstage -deploy -deploydir=<remote>`.
12. **Multi-platform in one invocation:** `-platform=Win64+Linux -target=MyGame+MyGameServer -clientconfig=Shipping -serverconfig=Shipping`.
13. **Cooked-editor pipeline:** add `-target=MyGameCookedEditor -CookedEditor` (uses CookedEditor target type).
14. **Plugin-aware build:** `-PluginsList=Plugins/X.uplugin+Plugins/Y.uplugin` if you need to restrict the plugin set.
15. **Mobile shipping (iOS):** `-platform=IOS -clientconfig=Shipping -package -iphonepackager -Distribution -SigningCertificate=<name> -MobileProvision=<path>`.

### A.8 Top gotchas (community-confirmed)
- **Project Settings → StagingDirectory is IGNORED by RunUAT.** Always pass `-stagingdirectory=` and `-archivedirectory=` explicitly.
- **`-buildmachine` is the magic CI flag.** Disables modals, crash reporter, removes warning caps, dumps cook-timing CSV. Without it, CI builds hang on dialogs.
- **`-platform=` vs `-targetplatform=`:** both accepted by BCR; other UAT commands (BuildTarget, BuildGame) only honour `-platform=`. Match the command.
- **`-RunAutomationTest=` under BCR is fragile** — the client process can exit before UAT polls; "BUILD FAILED" reported on green tests. Use `RunUnreal -test=` (Gauntlet) or `UnrealEditor-Cmd.exe -ExecCmds="Automation RunTests ...; Quit" -ReportExportPath=` instead.
- **`-help` output for BCR is incomplete.** Many practical flags are not listed. Read `ProjectParams.cs` directly for the canonical list.

---

## B. Other UAT commands — catalog

Full per-command details preserved in research persisted-output. Below is the index, organised by lifecycle area, so the implementation can pull each entry into `reference/uat.md`.

### Plugin lifecycle
- **`BuildPlugin`** — compiles a `.uplugin` for distribution. Required: `-Plugin=` and `-Package=`. Critical gotcha: **must pass `-TargetPlatforms=Win64+Linux+...` since 4.25** or UAT attempts every SDK it can detect (TVOS, Android, HoloLens, IOS, Linux, LinuxAArch64, Win32, Win64) and aborts on missing SDKs. Marketplace plugins want `-Rocket -StrictIncludes`. Engine-version locked at the minor level (5.4 vs 5.5 incompatible).

### Engine/tool building
- **`BuildCommonTools`** — builds the standard set of UE tools (UnrealHeaderTool, ShaderCompileWorker, UnrealPak, etc.) per platform.
- **`BuildTarget`** — compiles arbitrary UBT targets, accepts `-target=Editor+Game+Server -platform=Win64+Linux -configuration=Development+Shipping`. The lower-level companion to BuildCookRun.
- **`BuildCMakeLib` / `BuildHlslcc` / `BuildThirdPartyLibs`** — third-party library build wrappers.

### Project lifecycle (non-BCR)
- **`SyncProject`** — sync engine + project from P4 with the BuildGraph dependency expansion.
- **`SyncBinariesFromUGS`** — pull precompiled binaries from UGS storage.
- **`UpdateLocalVersion`** — stamp `Build.version` with build metadata.
- **`OpenEditor`** — invoke the editor with project + UAT-injected environment.

### Content / data ops
- **`ResavePackagesCommand`** — resave all packages (forced commandlet wrapper). Common args: `-PackageDir=`, `-AutoCheckOutPackages`.
- **`FixupRedirects`** — flush soft-reference redirects.
- **`RebuildHLODCommand`** — rebuild Hierarchical LODs via a commandlet.
- **`RebuildLightMapsCommand`** — rebuild lightmaps via commandlet.
- **`WorldPartitionBuilder`** — World Partition data baking.
- **`WrangleContentForDebugging`** — strips content for symbol-rich debug builds.

### Localisation
- **`Localisation`** — gather, compile, export. Drives `-run=GatherText` commandlet pipelines.

### Build infra
- **`BuildDerivedDataCache`** — DDC fill (build a shared cache for distribution).
- **`Virtualization`** — virtualised asset payload management.
- **`CopySharedCookedBuild`** — fetch a shared cooked-build seed for `-iteratesharedcookedbuild`.
- **`CleanFormalBuilds`** — strip a formal build directory of intermediate artefacts.
- **`Bisect`** — UAT-driven bisect harness (separate from ushell's `.p4 bisect`).

### Packaging / signing / paks
- **`ExtractPaks`** — extract `.pak`/`.utoc`/`.ucas` archives.
- **`CryptoKeys`** — generate/encrypt signing keys.
- **`IPhonePackager`** — iOS signing, packaging, IPA generation.
- **`UnsignedFilesViolationCheck`** — verify signed-build expectations.

### Mobile / Apple
- **`GenerateDSYM`** — Apple debug symbols.
- **`ListMobileDevices`** — discover devices.
- **`SetSecondaryRemoteMac`** — multi-Mac iOS build farms.

### Multi-process / testing
- **`LaunchMultiServer`** — spin up N dedicated servers for matchmaking/playtest.
- **`MultiClientLauncher`** — spin up N game clients (often used for net-replication testing).

### Perf / benchmarks
- **`BenchmarkBuild`** — wall-clock the build pipeline.
- **`RecordPerformance`** — perf-record wrapper.

### Utility
- **`GetFileCommand`** — fetch a file via UAT's HTTP/Horde plumbing.
- **`ZipUtils`** — Zip/Unzip used by the rest of UAT.
- **`AnalyzeThirdPartyLibs` / `ListThirdPartySoftware`** — TPS reporting.
- **`DedupeAutomationScripts`** — clean up duplicate UAT script discoveries.
- **`MegaXGE`** — single-host XGE distribution.
- **`StageLiveLinkHub`** — stage LiveLinkHub binaries.

---

## C. BuildGraph — the meta-orchestration

### C.1 What it is
A graph of named **Nodes** (sequences of **Tasks**), grouped into **Agents** (lanes/machines) and gated by **Triggers**. Output between nodes is transferred via shared storage; runs locally (sequential, in-process) or fanned out across a build farm (Horde, Jenkins, CircleCI, TeamCity).

Class-level comment, `BuildGraph.cs:206-235`: *"Tool to execute build automation scripts for UE projects, which can be run locally or in parallel across a build farm (assuming synchronization and resource allocation implemented by a separate system)."*

### C.2 CLI signature
`RunUAT BuildGraph -script=<path.xml> -target=<NodeName> [-set:Name=Value ...] [flags]`

Key flags:
- `-listonly` — print the node graph and exit.
- `-singlenode=<Name>` — run just one node.
- `-resume` — pick up where a previous run failed.
- `-clean` / `-cleannode=<Name>` — purge stored outputs.
- `-noxge`, `-noPCH` — disable XGE / PCH for this run.
- `-buildmachine` — same flag as BCR; flips CI mode (no modals, etc.).
- `-tokensignal=` — file path written when a node completes (for external orchestrators).
- `-storage=` — override shared-storage location.
- `-writetoshareddir` — promote artifacts to shared storage.
- `-validate` — schema-validate only.
- `-export=<json>` — dump graph to JSON for external tools.

### C.3 XML schema elements
- `<BuildGraph>` (root)
- `<Property Name="..." Value="..."/>` — variables.
- `<Option Name="..." DefaultValue="..." Description="..."/>` — CLI-exposed parameters.
- `<Agent Name="..." Type="...">` — execution lane.
- `<Node Name="..." Requires="..." Produces="..." After="..." RunEarly="..." NotifyOnWarnings="...">` — work unit.
- `<Aggregate Name="..." Requires="..."/>` — virtual node grouping others.
- `<Trigger Name="..." Requires="..."/>` — manual gate.
- `<Label Name="..." Requires="..." Category="..."/>` — UI grouping (for Horde/UGS).
- `<Include Script="..."/>` — modular composition.
- `<Macro Name="..." Arguments="...">...</Macro>` — parameterised XML expansion.
- `<Expand Name="..." Arg1="..."/>` — invoke a macro.
- `<Notify Default="..."/>` — failure notification routing.
- `<Annotation Name="..." Value="..."/>` — metadata for downstream tooling.
- `<EnvVar Name="..."/>` — surface environment to tasks.
- `<Warning Message="..."/>` and `<Error Message="..."/>` — script-level diagnostics.
- Conditionals: `If="..."` attribute on most elements.

### C.4 Built-in tasks (selected — full list in agent output)
- `<Compile Target="..." Platform="..." Configuration="..." Arguments="..."/>` — UBT compile.
- `<Cook Project="..." Platform="..." Maps="..." Versioned="..." Arguments="..."/>` — cook step.
- `<Stage>` — copy to staging.
- `<Pak>` / `<IoStore>` — pak/IO Store packaging.
- `<Command Name="<UATCommand>" Arguments="..."/>` — invoke any UAT command (this is how you chain BCR, RunUnreal, etc.).
- `<Commandlet Name="..." Arguments="..."/>` — invoke a UE editor commandlet.
- `<Copy Files="..." From="..." To="..."/>` / `<Delete Files="..."/>`.
- `<CreateArtifact Name="..." Files="..."/>` — declare a named build output.
- `<Tag Files="..." With="#TagName"/>` / `<Untag .../>` — file-set tag operations.
- `<Submit Files="..." Description="..."/>` — P4 submit.
- `<Zip From="..." ZipFile="..."/>` / `<Unzip ...>`.
- `<HordeCreateReport ...>` — Horde dashboard reports.
- `<AwsAssumeRole>`, `<AwsEcsDeploy>`, `<DockerBuild>` — cloud deploy.
- `<CsCompile>` — compile UAT script DLL during graph build.
- `<Log Message="..."/>`.

### C.5 Real-world case studies (shipped with engine)
Two complete BuildGraph scripts ship in the engine and are first-rate references:
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/CookedEditor/EpicGames.BuildGraph.xml` — Cooked Editor pipeline (editor binaries cooked for distribution, useful for thin-client scenarios).
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/LiveLinkHub/EpicGames.BuildGraph.xml` — LiveLinkHub multi-platform build/stage/archive.
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/Platforms/Windows/EpicGames.BuildGraph.xml` — Windows-platform fragments included by the above.

### C.6 Idiomatic recipes (target for `reference/buildgraph.md`)
1. Build & cook a project for two platforms in parallel.
2. Build a plugin, run plugin tests, archive the result.
3. Sync, build editor, run automation tests, produce a Horde-readable test report.
4. Multi-platform shipping pipeline (PC + dedicated server + mobile).
5. Nightly build with iterative cook.
6. Plugin packaging for marketplace.
7. Per-PR validation build.
8. Cloud DDC fill from a BuildGraph node.

### C.7 ushell ↔ BuildGraph
ushell's `.uat` is the wrapper. BuildGraph runs through it as:
```
.uat BuildGraph -- -script=Tools/MyPipeline.xml -target=Stage -set:Platform=Win64
```
ushell adds `-project=` automatically (unless `--unprojected` is passed). No other ushell wrapping is BuildGraph-specific.

### C.8 BuildGraph gotchas
- `<Command Name="BuildCookRun" Arguments="..."/>` doesn't inherit `-project=` automatically — pass it explicitly in `Arguments`.
- XGE/SN-DBS / FastBuild interactions: pass `-noxge` to disable; BuildGraph defaults to XGE if detected.
- `<Submit>` requires `-AllowSubmit -Submit` at the BuildGraph CLI level too; defending against accidental submits.
- Shared storage paths must be writable by every agent; mismatched paths produce "node X has no output" failures.
- `-resume` doesn't always work after a schema change; use `-clean -cleannode=` to force a fresh start.

---

## D. Testing harness via UAT

### D.1 The launcher
`RunUnreal` is THE entry point (`Engine/Source/Programs/AutomationTool/Gauntlet/Unreal/RunUnreal.cs`). All test driving goes through it. **No separate RunGauntlet.cs.**

### D.2 Test selector grammar
`-test=BootTest(MapName=Foo,Loops=2)` → one TestRequest, two params. Comma-separated for multiple. Parens for parameters. `-test=UE.EditorAutomation(Platform=Win64)` for per-test platform override.

### D.3 Default namespaces for test discovery
`Gauntlet.UnrealTest,UnrealGame,UnrealEditor`. The `AutomatedPerfTesting.Automation.dll` adds `AutomatedPerfTest.*` test nodes (DLL ships, source doesn't).

### D.4 Important test nodes
- `UE.EditorAutomation` — editor automation tests (in-editor `FAutomationTestBase`).
- `UE.TargetAutomation` — cooked-target automation; editor hosts, devkit runs.
- `UE.BootTest` / `EditorBootTest` / `TargetBootTest` — verify boot-to-front-end + clean exit.
- `EditorTest.EditorTestNode` — hardcoded `Project.Functional Tests.<X>` filter.

### D.5 Reports
- **No native JUnit export from in-engine automation.** Output is JSON at `<ReportExportPath>/index.json` + HTML at `index.html` + per-test artifacts.
- **Only `RunLowLevelTests` (Catch2) emits JUnit** via `--reporter=junit`.
- To get JUnit from regular UE automation, post-process `index.json` to JUnit XML.

### D.6 `Automation` console command verbs (engine-side)
- `Automation List`, `Automation RunTests <filter>`, `Automation RunAll`, `Automation RunFilter <Engine|Smoke|Perf|Stress|Product|Standard|Negative|All>`, `Automation SetFilter <flag>`, `Automation SetPriority <Critical|High|Medium|Low>`, `Automation Quit`, `Automation SoftQuit`, `Automation IgnoreLogEvents`, `Automation EnableStereoTests`, `Automation SetTagFilter <tag>`.

### D.7 Filter spec syntax (server-side)
- `Group:<name>` — expand from ini Groups list.
- `StartsWith:<text>` — anchored prefix.
- `^<text>` — start anchor.
- `<text>$` — end anchor.
- bare `<text>` — substring match on beautified test name.

### D.8 Failure modes
- **Crash:** `-CrashForUAT` ensures non-zero exit. Gauntlet detects via `UnrealProcessResult.EngineTestError`.
- **Hang:** detected via log-idle monitor (`-LogIdleTimeout=<seconds>`, default 30 min for automation, 10 min for boot tests). Outer cap: `-MaxDuration=<seconds>` (default 3600). `-NoTimeout` to disable.
- **No matching tests:** Gauntlet returns `UnrealProcessResult.InitializationFailure`, non-zero exit, message "No tests were executed!".
- **Device disconnect mid-test:** log-idle detector fires; if `ResumeOnCriticalFailure=true` + retries remain (default 3), pass resumes.

### D.9 Headless flags
`-unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT` — the standard headless tetrad. `-WaitForDebugger`/`-waitforattach` HALTS startup (Launch.cpp:100-113) — local only.

### D.10 `.perf test` ↔ Gauntlet mapping
ushell's `.perf test sequence Win64 perf <ComboName>` resolves to (perftest.py:217-237):
```
RunUAT.bat RunUnreal --
  -test=AutomatedPerfTest.SequenceTest
  -AutomatedPerfTest.DoPerf
  -platform=Win64 -configuration=test -iterations=6 -target=Game
  -build=<Project>/Saved/StagedBuilds/Windows
  -AutomatedPerfTest.TestID=<Project>-perf-autoperftest-ushell
  -AutomatedPerfTest.DoCSVProfiler
  -AutomatedPerfTest.TraceChannels=default,screenshot,stats
  -resX=1920 -resY=1080 -LocalReports
  -AutomatedPerfTest.SequencePerfTest.MapSequenceName=<ComboName>
```

`subtest=all` runs all four (perf, llm, insights, gpuperf) sequentially. Defaults pulled from `Engine/Plugins/Performance/AutomatedPerfTesting/<...>/AutomatedPerfTestCommonSettings.xml`.

---

## E. Community-confirmed gotchas (top 5, distilled across sources)

1. **`-platform=` vs `-targetplatform=` vs `-clientconfig=` vs `-configuration=` is a maze.** BCR accepts both `-platform=` and `-targetplatform=`. Other UAT commands only accept `-platform=`. Configuration splits into `-clientconfig=` and `-serverconfig=`; `-configuration=` is for `BuildTarget`/`BuildEditor`. Pick wrong → silently builds host target.
2. **`BuildPlugin` defaults to every SDK platform (since 4.25).** Always pass `-TargetPlatforms=`.
3. **`-pak`/`-iostore`/`-zenstore` interaction is subtle.** Project Settings vs CLI flags can produce hybrid output.
4. **`-iterate` is stale-prone.** Use for dev only; never for shipping.
5. **Project Settings StagingDirectory is ignored.** Always pass `-stagingdirectory=` and `-archive -archivedirectory=` explicitly.

Plus a sixth honourable mention:
6. **`-buildmachine` is the CI flag.** Disables dialogs, crash reporter, removes warning caps, dumps cook-timing CSV. CI builds without it hang on modals.

---

## F. CI/CD reference pipelines

Concrete public pipelines worth citing in the skill:
- **CircleCI:** `vela-games/circleci-ue5-game` — full BuildGraph with 4 agents.
- **TeamCity:** `jamescallin/teamcity-UEBuildGraph` — BuildGraph runner, UGS notifier, log parser.
- **GitHub Actions:** `marketplace/actions/ue5-build-project` — parameterised BCR wrapper. `Guganana/UnrealPluginCIWithGithubActions` — plugin-marketplace flow.
- **Jenkins:** Medium article `@lifeexe` — parameterised freestyle.
- **Most useful single doc:** `botman99/ue4-unreal-automation-tool` README — concrete RunUAT examples, log path locations, `-map=` packaging-size gotcha.

---

## G. Sources of truth in the engine tree

When `--help` lies or is incomplete, these files are canonical:
- `ProjectParams.cs` — BCR/UAT flag definitions.
- `BuildCookRun.Automation.cs` — verb ordering, execution loop.
- `BuildPluginCommand.Automation.cs` — plugin packaging.
- `BuildGraph.cs` — BuildGraph CLI.
- `BgScriptReader.cs` — BuildGraph XML schema implementation.
- `Tasks/*.cs` — every BuildGraph task element (`[TaskElement("Name", typeof(ParamsClass))]`).
- `Gauntlet/Unreal/RunUnreal.cs` — RunUnreal entry.
- `Gauntlet/Unreal/Base/Gauntlet.UnrealTestContext.cs` — Gauntlet options.
- `Gauntlet/Unreal/Automation/UE.Automation.cs` — automation test config (AutomationTestConfig).
- `Engine/Source/Developer/AutomationController/Private/AutomationCommandline.cpp` — engine-side `Automation` exec command.
- `Engine/Source/Runtime/Core/Public/Misc/AutomationTest.h` — `IMPLEMENT_*_AUTOMATION_TEST` macros.

---

## H. Persisted full agent outputs (this session)

The five research agents' full outputs (~300KB total) were persisted by the harness. They contain extensive verbatim code quotes and command-line examples beyond this digest. If they're still accessible at implementation time, they are at `C:\Users\Aaron\.claude\projects\E--Work-ushell-skill\<session-id>\tool-results\` as `toolu_*.json`. If not, this digest is the surviving record — re-dispatch the agents as needed when writing `reference/uat.md` and `reference/buildgraph.md`.

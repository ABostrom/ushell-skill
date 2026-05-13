# BuildGraph reference

BuildGraph is UAT's meta-orchestration layer: a directed graph of **Nodes** (sequences of **Tasks**), grouped into **Agents** (lanes/machines) and gated by **Triggers**, declared in XML. Runs locally (sequential) or distributed across a build farm (Horde, Jenkins, CircleCI, TeamCity).

## TOC

1. What BuildGraph is
2. CLI signature
3. Schema elements
4. Built-in tasks reference
5. Property / macro / include idioms
6. Case study: CookedEditor
7. Case study: LiveLinkHub
8. Idiomatic recipes
9. ushell ↔ BuildGraph
10. Gotchas
11. Built-in BuildGraph properties
12. Engine-shipped meta-scripts (source-build only)
13. Extending `BuildAndTestProject.xml` — the Lyra pattern

---

## 1. What BuildGraph is

From `Engine/Source/Programs/AutomationTool/BuildGraph/BuildGraph.cs:206-235`:

> Tool to execute build automation scripts for UE projects, which can be run locally or in parallel across a build farm (assuming synchronization and resource allocation implemented by a separate system).
>
> Build graphs are declared using an XML script using syntax similar to MSBuild, ANT or NAnt, and consist of the following components:
> - **Tasks**: Building blocks which can be executed as part of the build process. Many predefined tasks are provided ('Cook', 'Compile', 'Copy', 'Stage', 'Log', 'PakFile', etc...), and additional tasks may be added by declaring classes derived from `AutomationTool.BuildTask` in other UAT modules.
> - **Nodes**: A named sequence of tasks which are executed in order to produce outputs. Nodes may have dependencies on other nodes for their outputs before they can be executed. Declared with the 'Node' element.
> - **Agents**: A machine which can execute a sequence of nodes, if running as part of a build system. Has no effect when building locally. Declared with the 'Agent' element.
> - **Triggers**: Container for agents which should only be executed when explicitly triggered.

**When to use:**
- Multi-platform / multi-target shipping pipelines.
- CI integration (Horde, Jenkins) where you want declarative orchestration with parallel agents.
- Anything that requires running steps across multiple machines with artifact transfer.

**When NOT to use:**
- One-off invocations — just use `.uat BuildCookRun --` directly.
- Local dev iteration — overkill; use ushell verbs.

---

## 2. CLI signature

```
RunUAT BuildGraph -script=<path.xml> -target=<NodeName> [-set:Name=Value ...] [flags]
```

Through ushell: `.uat BuildGraph -- -script=<path> -target=<Node> [-set:Foo=Bar]`. ushell auto-injects `-project=` unless `--unprojected`.

**Key flags:**

| Flag | Effect |
|------|--------|
| `-script=<path.xml>` | Path to the BuildGraph script. |
| `-target=<NodeName>` | Node to execute (and its dependencies). |
| `-set:Name=Value` | Override an `<Option>` or `<Property>` value. Can repeat. |
| `-listonly` | Print the node graph and exit (don't run). |
| `-singlenode=<Name>` | Run just this node (skip dependencies). |
| `-resume` | Pick up where a previous run failed. |
| `-clean` | Purge all stored node outputs before running. |
| `-cleannode=<Name>` | Purge just this node's stored output. |
| `-noxge`, `-noPCH` | Disable XGE / PCH for this run. |
| `-buildmachine` | Same as BCR — flips CI mode (no modals etc.). |
| `-tokensignal=<path>` | File path written when a node completes (for external orchestrators). |
| `-storage=<path>` | Override shared-storage location. |
| `-writetoshareddir` | Promote artifacts to shared storage. |
| `-validate` | Schema-validate only (don't run). |
| `-export=<json>` | Dump graph to JSON for external tools. |
| `-preprocessing` | Show preprocessed (macro-expanded) script. |
| `-UseLocalBuildStorage` | Use local-filesystem path for inter-node artifact storage instead of network/Horde shared storage. **Essential for local-dev BuildGraph runs** — without it, nodes that depend on cross-agent file transfers will fail because there's no shared storage configured. |
| `-AllowSubmit -Submit` | Required pair to allow `<Submit>` tasks to actually submit to P4. Either flag alone is a no-op defence. |
| `-set:Horde=true` | Force-enable the `$(Horde)` built-in. Normally inferred from the build environment. |
| `-WriteToSharedStorage` | Promote stored artifacts to shared storage (for downstream agents to consume). |

---

## 3. Schema elements

All elements support a `If="<expr>"` conditional attribute.

| Element | Purpose | Example |
|---------|---------|---------|
| `<BuildGraph>` | Root element. |  |
| `<Property Name="..." Value="..."/>` | Variable. | `<Property Name="EngineRoot" Value="$(RootDir)/Engine"/>` |
| `<Option Name="..." DefaultValue="..." Description="..."/>` | CLI-exposed parameter (set via `-set:Name=Value`). | `<Option Name="Platform" DefaultValue="Win64" Description="Target platform"/>` |
| `<Agent Name="..." Type="...">` | Execution lane (machine). | `<Agent Name="Win64BuildAgent" Type="CompileWin64">...</Agent>` |
| `<Node Name="..." Requires="..." Produces="..." After="..." RunEarly="..." NotifyOnWarnings="...">` | Work unit. | See §6. |
| `<Aggregate Name="..." Requires="..."/>` | Virtual node grouping others. |  |
| `<Trigger Name="..." Requires="..."/>` | Manual gate (CI-only). |  |
| `<Label Name="..." Requires="..." Category="..."/>` | UI grouping (Horde/UGS). |  |
| `<Include Script="..."/>` | Modular composition. |  |
| `<Macro Name="..." Arguments="...">...</Macro>` | Parameterised XML expansion. |  |
| `<Expand Name="..." Arg1="..."/>` | Invoke a macro. |  |
| `<Notify Default="..." Failures="..." Warnings="..."/>` | Failure notification routing. |  |
| `<Annotation Name="..." Value="..."/>` | Metadata for downstream tooling. |  |
| `<EnvVar Name="..."/>` | Surface env var to tasks. |  |
| `<Warning Message="..."/>`, `<Error Message="..."/>` | Script-level diagnostics. |  |
| `<ForEach Name="..." Values="..." Separator="..." If="...">...</ForEach>` | Iterate over a delimited list. `Values` is the source string; `Separator` defaults to `;` (override with e.g. `+`). Each iteration sets `$(Name)` and re-evaluates the body. Used heavily by Lyra for "one node per target platform". | `<ForEach Name="P" Values="$(TargetPlatforms)"><Node Name="Compile $(P)">...</Node></ForEach>` |
| `<Do If="...">...</Do>` | Block conditional. Wraps multiple elements; the whole block is skipped if `If` is false. Cleaner than putting `If="..."` on every child. | `<Do If="!$(SkipTest)">...</Do>` |
| `<Switch>` with `<Case If="...">` / `<Default>` | XML if-else. Evaluates each `Case` in order; runs `Default` if none match. | `<Switch><Case If="$(Horde)"><RetrieveArtifact .../></Case><Default><Copy .../></Default></Switch>` |

**Conditional `If="..."` expressions** support:
- Comparison: `'$(X)' == 'foo'`, `'$(X)' != ''`, numeric `>` / `<` / `>=` / `<=`.
- Boolean: `And`, `Or`, `!`.
- Functions: `Exists('<path>')`, `ContainsItem('<list>', '<item>', '<separator>')` — membership test in a delimited list.
- Built-in properties (see §11) like `$(IsBuildMachine)`, `$(IsPreflight)`, `$(Horde)`.

---

## 4. Built-in tasks reference

Each task is registered via `[TaskElement("Name", typeof(ParamsClass))]` on a `BgTask` subclass. ~50 task types ship in 5.7; the most-used are documented below.

### Build / compile

#### `<Compile>` — Build a UBT target

```xml
<Compile Target="MyGameEditor" Platform="Win64" Configuration="Development"
         Project="$(ProjectPath)" Arguments="-DisableUnity"/>
```

**Attrs:** `Target` (required), `Platform`, `Configuration`, `Project`, `Tag`, `Arguments`, `AllowParallelExecutor`.

#### `<CsCompile>` — Compile C# (UAT script, custom UAT modules)

```xml
<CsCompile Project="$(ProjectRoot)/Build/MyScripts.csproj" Configuration="Development"/>
```

### Cook / stage / pak

#### `<Cook>` — Cook content for a platform

```xml
<Cook Project="$(ProjectPath)" Platform="$(CookPlatform)"
      Maps="MapA+MapB" Versioned="false" Arguments="-iterate -fastcook"/>
```

**Attrs:** `Project` (required), `Platform`, `Maps`, `Versioned`, `Arguments`, `Tag`.

#### `<Stage>` — Copy cooked content to a staging directory

```xml
<Stage Project="$(ProjectPath)" Platform="Win64" Configuration="Development"
       Directory="$(StagedDir)" Tag="#Staged"/>
```

#### `<Pak>` / `<IoStore>` — Package as pak / IoStore

```xml
<Pak Files="#StagedContent" PakFile="$(OutputDir)/Pak.pak" Order="$(PakOrderFile)"/>
<IoStore Files="#StagedContent" Container="$(OutputDir)/Container.utoc"/>
```

### Composition

#### `<Command>` — Invoke any UAT command

```xml
<Command Name="BuildCookRun"
         Arguments="-project=$(UProjectPath) -platform=$(TargetPlatform)
                    -clientconfig=$(TargetConfiguration) -SkipCook -cook -pak -stage
                    -stagingdirectory=$(StageDirectory) -compressed -unattended -stdlog"/>
```

This is how you call BCR from BuildGraph. **`-project=` is NOT inherited** — pass explicitly.

#### `<Commandlet>` — Invoke an editor commandlet

```xml
<Commandlet Name="ResavePackages" Project="$(ProjectPath)"
            Arguments="-PackageFolder=$(ProjectDir)/Content/Foo -AutoCheckOutPackages"/>
<!-- IMPORTANT: ResavePackages uses -PackageFolder=<filesystem-path>, NOT -PackageDir=.
     Without one of -Package=, -PackageFolder=, or -Map=, the commandlet resaves
     EVERY package including engine packages. See reference/unreal-args.md §11. -->
```

### File ops

#### `<Copy>` — Copy files

```xml
<Copy Files="$(SourceDir)/*.dll" From="$(SourceDir)" To="$(DestDir)" Tag="#CopiedDlls"/>
```

#### `<Delete>` — Remove files

```xml
<Delete Files="$(BuildDir)/Intermediate/..."/>
```

#### `<Tag>` / `<Untag>` — File-set tag operations

```xml
<Tag Files="$(StagedDir)/..." With="#StagedFiles"/>
<Untag Files="$(StagedDir)/*.tmp" With="#StagedFiles"/>
```

File tags are how nodes pass artifacts to dependent nodes.

#### `<Zip>` / `<Unzip>`

```xml
<Zip From="$(StagedDir)" ZipFile="$(ArchiveDir)/MyBuild.zip"/>
<Unzip ZipFile="$(InputDir)/Package.zip" ToDir="$(WorkDir)"/>
```

### Artifacts

#### `<CreateArtifact>` — Declare a named build output

```xml
<CreateArtifact Name="WindowsClient" Files="$(StagedDir)/Win64/..." Tag="#ClientArtifact"/>
```

#### `<CreateCloudArtifact>` — Cloud (Horde) artifact

```xml
<CreateCloudArtifact Name="WindowsClient" Files="$(StagedDir)/Win64/..."
                     Type="staged-build" Description="Win64 client Shipping"/>
```

#### `<RetrieveArtifact>` — Pull a previously-created Horde artifact

```xml
<RetrieveArtifact Name="MyProject-Staged-Windows" Type="staged-build"
                  OutputDir="$(ProjectOutputDirectory)/Windows" />
```

Used downstream of `<CreateCloudArtifact>` in a Horde job. Lyra wraps this in a `<Switch>` so local builds fall back to a `<Copy>` from `$(NetworkOutputDirectory)`:

```xml
<Switch>
    <Case If="$(Horde)">
        <RetrieveArtifact Name="$(ProjectName)-Staged-$(UploadPlatform)" Type="staged-build"
                          OutputDir="$(ProjectOutputDirectory)/$(UploadPlatform)" />
    </Case>
    <Default>
        <Copy From="$(NetworkOutputDirectory)/$(UploadPlatform)/Staged/..."
              To="$(ProjectOutputDirectory)/$(UploadPlatform)/..." />
    </Default>
</Switch>
```

### Binaries / symbols

#### `<Strip>` — Strip pdbs/symbols into a separate output dir

```xml
<Strip Files="#ArchiveSymbols" BaseDir="$(RootDir)" OutputDir="$(ArchiveStagingDir)"
       Platform="Win64"/>
```

Used to separate "binaries for distribution" from "symbols for a symbol server / debug builds". Pair with `<Tag Files="#X" Except="*.pdb" With="#Binaries"/>` + `<Tag Files="#X" Filter="*.pdb" With="#Symbols"/>` to partition. Then `Strip` the symbols into a parallel tree. Common in the PCB-for-UGS workflow (recipe 9).

#### `<SetVersion>` — Stamp `Engine/Build/Build.version`

```xml
<SetVersion Change="$(Change)" Branch="$(EscapedBranch)" If="$(Versioned)"/>
```

Writes CL + branch into the engine's `Build.version` JSON so subsequent compiles bake them into binaries. Standard first step in any node that produces versioned binaries for distribution.

### Cloud / deploy

- `<AwsAssumeRole>`, `<AwsEcsDeploy>` — AWS integration.
- `<DockerBuild>` — Docker image builds.
- `<DeployTool>` — generic deploy step.

### Source control

#### `<Submit>` — P4 submit

```xml
<Submit Files="$(GeneratedDir)/..." Description="Auto-submit by BuildGraph"
        Stream="//depot/Main"/>
```

Requires `-AllowSubmit -Submit` at BuildGraph CLI level too (defends against accidental submits).

#### `<Sync>` — P4 sync

```xml
<Sync Files="//depot/Engine/..." Changelist="$(SyncCL)"/>
```

### Logging / reporting

#### `<Log>` — Log a message

```xml
<Log Message="Building platform $(Platform) configuration $(Config)"/>
```

#### `<HordeCreateReport>` — Horde dashboard report

```xml
<HordeCreateReport Name="SmokeTestReport" Type="Test"
                   Files="$(ReportDir)/index.json"/>
```

### Misc

- `<Sleep>` — pause N seconds.
- `<Warning Message="..."/>`, `<Error Message="..."/>` — diagnostics.
- `<Annotation>` — attach metadata to downstream tooling.

---

## 5. Property / macro / include idioms

### Properties for parameterisation

```xml
<Property Name="EngineDir" Value="$(RootDir)/Engine"/>
<Property Name="ProjectName" Value="MyGame"/>
<Property Name="ProjectPath" Value="$(RootDir)/$(ProjectName)/$(ProjectName).uproject"/>
<Property Name="OutputDir" Value="$(RootDir)/LocalBuilds/$(ProjectName)"/>
```

### Options for CLI-exposed parameters

```xml
<Option Name="Platform" DefaultValue="Win64" Description="Target platform"/>
<Option Name="Configuration" DefaultValue="Development" Description="Build config"/>
<Option Name="StageDir" DefaultValue="$(RootDir)/Stage" Description="Where to stage"/>
```

Override at the CLI: `.uat BuildGraph -- -script=... -target=... -set:Platform=Linux -set:Configuration=Shipping`.

### Macros for repeated patterns

```xml
<Macro Name="BuildAndStage" Arguments="Platform;Config">
    <Compile Target="MyGame" Platform="$(Platform)" Configuration="$(Config)"
             Project="$(ProjectPath)"/>
    <Command Name="BuildCookRun"
             Arguments="-project=$(ProjectPath) -platform=$(Platform)
                        -clientconfig=$(Config) -cook -stage -pak
                        -stagingdirectory=$(OutputDir)/$(Platform)
                        -compressed -unattended"/>
</Macro>

<!-- Invoke per-platform: -->
<Expand Name="BuildAndStage" Platform="Win64" Config="Development"/>
<Expand Name="BuildAndStage" Platform="Linux" Config="Development"/>
```

### Includes for cross-script sharing

```xml
<Include Script="Build/Common.xml"/>
<Include Script="Build/Platforms/$(Platform).xml" If="Exists('Build/Platforms/$(Platform).xml')"/>
```

Used in the shipped CookedEditor and LiveLinkHub scripts to factor platform-specific tasks out.

---

## 6. Case study: CookedEditor

`Engine/Binaries/DotNET/AutomationTool/AutomationScripts/CookedEditor/EpicGames.BuildGraph.xml` is Epic's example pipeline for producing a **cooked editor** distribution.

**What it produces:** an editor binary plus a cooked content set, packaged for thin-client distribution. Useful for projects where you want non-developers to load editor functionality without a full source/Intermediate sync.

**Node graph (simplified):**

```
SyncEngine ──► CompileTools ──► CompileEditor ──► CookEditorContent ──► StageCookedEditor
                                                                              │
                                                                              ▼
                                                                       ArchiveOutput
```

**Notable patterns:**
- `<Property>` for engine + project paths, then `<Option>` for build version + output dir overrides.
- A `<Macro>` factoring per-platform compile + cook into a single expandable unit.
- `<Command Name="BuildCookRun" Arguments="..."/>` for the cook stage rather than `<Cook>` — gives access to BCR's full flag surface.
- `<Tag Files="$(StagedDir)/..." With="#CookedEditorOutput"/>` to declare the cross-node artifact.
- `<CreateCloudArtifact>` at the end for Horde upload.

Open the file directly when authoring; it's the canonical reference for the "cooked editor" pattern.

---

## 7. Case study: LiveLinkHub

`Engine/Binaries/DotNET/AutomationTool/AutomationScripts/LiveLinkHub/EpicGames.BuildGraph.xml`.

**What it produces:** LiveLinkHub binaries for distribution (multi-platform: Win64, Mac, Linux).

**Pattern highlights:**
- Multi-agent execution: separate `<Agent>` blocks per platform.
- Heavy use of `<Property>` for engine paths, output paths, version strings.
- A `<Trigger>` for the actual archive/publish step (gated on user approval in CI).
- `<HordeCreateReport>` for surfacing test results.
- `<Submit>` for publishing the build version to P4 metadata.

Useful template for any multi-platform tool/utility shipping pipeline.

---

## 8. Idiomatic recipes (8 skeletons)

### Recipe 1 — Build & cook a project for two platforms in parallel

```xml
<BuildGraph>
  <Property Name="ProjectPath" Value="$(RootDir)/MyGame/MyGame.uproject"/>

  <Agent Name="Win64BuildAgent" Type="CompileWin64">
    <Node Name="Compile Editor Win64">
      <Compile Target="MyGameEditor" Platform="Win64" Configuration="Development"
               Project="$(ProjectPath)"/>
    </Node>
    <Node Name="Cook Win64" Requires="Compile Editor Win64">
      <Cook Project="$(ProjectPath)" Platform="Win64"/>
      <Tag Files="$(RootDir)/MyGame/Saved/Cooked/Windows/..." With="#CookedWin64"/>
    </Node>
  </Agent>

  <Agent Name="LinuxBuildAgent" Type="CompileLinux">
    <Node Name="Compile Editor Linux">
      <Compile Target="MyGameEditor" Platform="Linux" Configuration="Development"
               Project="$(ProjectPath)"/>
    </Node>
    <Node Name="Cook Linux" Requires="Compile Editor Linux">
      <Cook Project="$(ProjectPath)" Platform="LinuxServer"/>
      <Tag Files="$(RootDir)/MyGame/Saved/Cooked/LinuxServer/..." With="#CookedLinux"/>
    </Node>
  </Agent>

  <Aggregate Name="All Cooks" Requires="Cook Win64;Cook Linux"/>
</BuildGraph>
```

Run: `.uat BuildGraph -- -script=Build/Pipeline.xml -target="All Cooks"`.

### Recipe 2 — Build a plugin, run tests, archive

```xml
<BuildGraph>
  <Option Name="PluginPath" DefaultValue="Plugins/MyPlugin.uplugin"/>
  <Property Name="OutputDir" Value="$(RootDir)/Out/MyPlugin"/>

  <Agent Name="PluginAgent" Type="CompileWin64">
    <Node Name="BuildPlugin">
      <Command Name="BuildPlugin"
               Arguments="-Plugin=$(RootDir)/$(PluginPath)
                          -Package=$(OutputDir)
                          -TargetPlatforms=Win64+Linux
                          -Rocket -StrictIncludes -unattended -nop4"/>
      <Tag Files="$(OutputDir)/..." With="#PluginPackage"/>
    </Node>

    <Node Name="PluginSmokeTests" Requires="BuildPlugin">
      <Command Name="RunUnreal"
               Arguments="-project=$(RootDir)/MyGame/MyGame.uproject
                          -test=UE.EditorAutomation
                          -RunTest=&quot;Project.Plugin.Smoke&quot;
                          -build=editor -platform=Win64 -configuration=Development
                          -ReportExportPath=$(RootDir)/Reports/Plugin
                          -unattended -nullrhi -MaxDuration=900"/>
    </Node>

    <Node Name="ArchivePlugin" Requires="PluginSmokeTests">
      <Zip From="$(OutputDir)" ZipFile="$(RootDir)/Archive/MyPlugin.zip"/>
    </Node>
  </Agent>
</BuildGraph>
```

### Recipe 3 — Sync, build editor, run automation tests, Horde report

```xml
<BuildGraph>
  <Property Name="ProjectPath" Value="$(RootDir)/MyGame/MyGame.uproject"/>
  <Property Name="ReportDir" Value="$(RootDir)/Reports/EditorTests"/>

  <Agent Name="TestAgent">
    <Node Name="Sync Source">
      <Sync Files="//depot/MyGame/..." Changelist="$(SyncCL)"/>
    </Node>

    <Node Name="Build Editor" Requires="Sync Source">
      <Compile Target="MyGameEditor" Platform="Win64" Configuration="Development"
               Project="$(ProjectPath)"/>
    </Node>

    <Node Name="Run Editor Smoke" Requires="Build Editor">
      <Command Name="RunUnreal"
               Arguments="-project=MyGame
                          -test=UE.EditorAutomation
                          -RunTest=&quot;Filter:Smoke&quot;
                          -build=editor -platform=Win64 -configuration=Development
                          -ReportExportPath=$(ReportDir)
                          -WriteTestResultsForHorde
                          -unattended -nullrhi -MaxDuration=900 -CrashForUAT"/>
      <Tag Files="$(ReportDir)/..." With="#TestReport"/>
    </Node>

    <Node Name="Publish Test Report" Requires="Run Editor Smoke">
      <HordeCreateReport Name="EditorSmoke" Type="Test"
                         Files="$(ReportDir)/index.json"/>
    </Node>
  </Agent>
</BuildGraph>
```

### Recipe 4 — Multi-platform shipping pipeline (PC + dedicated server + mobile)

```xml
<BuildGraph>
  <Option Name="BuildVersion" DefaultValue="dev"/>
  <Property Name="OutDir" Value="$(RootDir)/Builds/$(BuildVersion)"/>

  <Macro Name="ShipPlatform" Arguments="Platform;Config;Target;OutSubdir">
    <Command Name="BuildCookRun"
             Arguments="-project=$(RootDir)/MyGame/MyGame.uproject
                        -target=$(Target) -platform=$(Platform) -clientconfig=$(Config)
                        -build -cook -stage -pak -iostore -compressed -package -archive
                        -archivedirectory=$(OutDir)/$(OutSubdir)
                        -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
                        -buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog"/>
  </Macro>

  <Agent Name="WindowsShip">
    <Node Name="Ship Win64 Client">
      <Expand Name="ShipPlatform" Platform="Win64" Config="Shipping" Target="MyGame" OutSubdir="Win64"/>
    </Node>
  </Agent>

  <Agent Name="LinuxShip">
    <Node Name="Ship Linux Server">
      <Expand Name="ShipPlatform" Platform="Linux" Config="Shipping" Target="MyGameServer" OutSubdir="LinuxServer"/>
    </Node>
  </Agent>

  <Agent Name="iOSShip">
    <Node Name="Ship iOS Client">
      <Command Name="BuildCookRun"
               Arguments="-project=$(RootDir)/MyGame/MyGame.uproject
                          -platform=IOS -clientconfig=Shipping
                          -build -cook -stage -package -iphonepackager -Distribution
                          -archive -archivedirectory=$(OutDir)/iOS
                          -unattended -buildmachine -CrashForUAT"/>
    </Node>
  </Agent>

  <Aggregate Name="Ship All" Requires="Ship Win64 Client;Ship Linux Server;Ship iOS Client"/>
</BuildGraph>
```

### Recipe 5 — Nightly build with iterative cook (DEV ONLY)

```xml
<BuildGraph>
  <Agent Name="Nightly">
    <Node Name="Sync">
      <Sync Files="//depot/MyGame/..."/>
    </Node>

    <Node Name="Iterative Cook" Requires="Sync">
      <Command Name="BuildCookRun"
               Arguments="-project=$(RootDir)/MyGame/MyGame.uproject
                          -platform=Win64 -clientconfig=Development
                          -cook -iterate -fastcook -stage -pak
                          -unattended -nop4"/>
    </Node>
  </Agent>
</BuildGraph>
```

**Warning:** `-iterate` is dev-only. Don't use this template for any release build.

### Recipe 6 — Plugin marketplace packaging

```xml
<BuildGraph>
  <Option Name="PluginVersion" DefaultValue="1.0.0"/>
  <Property Name="OutDir" Value="$(RootDir)/Marketplace/MyPlugin-$(PluginVersion)"/>

  <Agent Name="MarketplaceAgent">
    <Node Name="Validate Plugin">
      <Command Name="BuildPlugin"
               Arguments="-Plugin=$(RootDir)/Plugins/MyPlugin.uplugin
                          -Package=$(OutDir)
                          -TargetPlatforms=Win64+Linux
                          -Rocket -StrictIncludes
                          -unattended -nop4"/>
    </Node>

    <Node Name="Archive for Submission" Requires="Validate Plugin">
      <Zip From="$(OutDir)" ZipFile="$(RootDir)/MyPlugin-$(PluginVersion).zip"/>
    </Node>
  </Agent>
</BuildGraph>
```

### Recipe 7 — Per-PR validation build

```xml
<BuildGraph>
  <Agent Name="PRValidate">
    <Node Name="Compile">
      <Compile Target="MyGameEditor" Platform="Win64" Configuration="Development"
               Project="$(RootDir)/MyGame/MyGame.uproject"
               Arguments="-DisableUnity"/>
    </Node>

    <Node Name="Static Analysis" Requires="Compile" RunEarly="false">
      <Compile Target="MyGameEditor" Platform="Win64" Configuration="Development"
               Project="$(RootDir)/MyGame/MyGame.uproject"
               Arguments="-StaticAnalyzer=PVSStudio"/>
    </Node>

    <Node Name="Smoke Tests" Requires="Compile">
      <Command Name="RunUnreal"
               Arguments="-project=MyGame -test=UE.EditorAutomation
                          -RunTest=&quot;Filter:Smoke&quot;
                          -build=editor -platform=Win64 -configuration=Development
                          -ReportExportPath=$(RootDir)/Reports/PR
                          -unattended -nullrhi -MaxDuration=600 -CrashForUAT"/>
    </Node>
  </Agent>

  <Aggregate Name="PR Gate" Requires="Static Analysis;Smoke Tests"/>
</BuildGraph>
```

### Recipe 8 — Cloud DDC fill from a BuildGraph node

```xml
<BuildGraph>
  <Agent Name="DDCFill">
    <Node Name="Authorize">
      <Command Name="OidcToken" Arguments="--Service=DDCService --Mode=Login"/>
    </Node>

    <Node Name="Fill DDC" Requires="Authorize">
      <Commandlet Name="DerivedDataCache"
                  Project="$(RootDir)/MyGame/MyGame.uproject"
                  Arguments="-fill -unattended -Map=BootMap+LevelOne+LevelTwo"/>
    </Node>
  </Agent>
</BuildGraph>
```

---

## 9. ushell ↔ BuildGraph

```
.uat BuildGraph -- -script=Build/Pipeline.xml -target=Stage -set:Platform=Win64
```

ushell auto-injects `-project=<uproject>` unless `--unprojected`. No other ushell wrapping is BuildGraph-specific.

**Listing nodes before running:**
```
.uat BuildGraph -- -script=Build/Pipeline.xml -listonly
```

**Running a single node, ignoring dependencies:**
```
.uat BuildGraph -- -script=Build/Pipeline.xml -singlenode="Stage Win64"
```

**Resuming after a failure:**
```
.uat BuildGraph -- -script=Build/Pipeline.xml -target=Stage -resume
```

**Clean run (purge stored outputs first):**
```
.uat BuildGraph -- -script=Build/Pipeline.xml -target=Stage -clean
```

---

## 10. Gotchas

- **`<Command Name="BuildCookRun">` does NOT inherit `-project=` from BuildGraph.** Pass it explicitly in `Arguments=`. (Same for any nested `<Command>` invocation.)
- **XGE / FastBuild / SN-DBS auto-detection.** BuildGraph defaults to XGE if detected. Pass `-noxge` to the BuildGraph CLI to disable.
- **`<Submit>` requires `-AllowSubmit -Submit` at the BuildGraph CLI level too** — defends against accidental submits. Without both flags, the submit is silently skipped.
- **Shared-storage path mismatch produces "node X has no output" failures.** Every agent must agree on the shared-storage location; pass `-storage=<path>` consistently.
- **`-resume` doesn't always work after a schema change.** If you've edited the script and `-resume` errors with strange schema messages, use `-clean -cleannode=<Last Good Node>` to force a fresh start from a known point.
- **Property substitution is text-level.** `$(Property)` is replaced verbatim — beware of paths with spaces or special chars. Use `&quot;` around args that contain spaces.
- **Conditionals (`If="..."`) are evaluated at preprocess time**, not runtime. `If="Exists('$(Path)')"` is static.
- **Custom tasks** can be added by declaring `BgTask` subclasses in other UAT modules. The `[TaskElement("Name", typeof(ParamsClass))]` attribute registers them with the schema reader.

---

## 11. Built-in BuildGraph properties

These are available without explicit `<Option>` or `<Property>` declaration. Reading any real script (Lyra, Epic samples, internal CI) requires recognising them.

| Property | Meaning | Set by |
|---|---|---|
| `$(IsBuildMachine)` | `true` on CI agents (anything that sets `IsBuildMachine=1` in env, including Horde). `false` locally. Gate logic. | Build env / CI scripts |
| `$(IsPreflight)` | `true` when `-set:PreflightChange=<cl>` is set (i.e. we're testing a P4 shelve). | Conventionally set in script: `<Property Name="IsPreflight" Value="true" If="'$(PreflightChange)' != ''"/>` |
| `$(Horde)` | `true` when running under Horde specifically (vs Jenkins / CircleCI / local). Used to gate Horde-specific tasks like `<RetrieveArtifact>`. | Build env |
| `$(Change)` | Current Perforce CL number (engine-side). | Build env |
| `$(CodeChange)` | Latest CL that contains code (`.cpp/.h/.cs/.usf/.ush`). Smaller than `$(Change)` if recent CLs are content-only. | Build env |
| `$(PreflightChange)` | Shelved CL number being tested in preflight mode. Empty otherwise. | CLI: `-set:PreflightChange=<cl>` |
| `$(Branch)` | Current branch path (P4 stream like `//UE5/Main`). | Build env |
| `$(EscapedBranch)` | `$(Branch)` with `/` → `+` substituted. Safe for filenames. | Derived |
| `$(RootDir)` | Workspace root — the engine root in a typical UE checkout. All script paths are resolved relative to this. | Detected at startup |
| `$(BuildName)` | Derived build version string (e.g. `CL-12345`). | Conventional |
| `$(BuildNamePath)` | Build version including preflight suffix if applicable (e.g. `CL-12345-PF67890`). Use this for archive directory names. | Derived |
| `$(NetworkOutputDirectory)` | Shared-storage path for build outputs. Set by `BuildAndTestProject.xml`. | Project script |
| `$(NetworkTempRootOverride)` / `$(NetworkPublishRootOverride)` / `$(NetworkReportRootOverride)` | Override paths for the temp / publish / report storage roots. | Project script (Lyra-style) |
| `$(PreNodeName)` | Prefix used by `BuildAndTestProject.xml` for project-namespaced node names. Allows multiple projects in one job. Used in `Requires="$(PreNodeName)Compile Editor Win64"`. | `BuildAndTestProject.xml` |
| `$(RequiredEditorPlatforms)` | Computed from `$(EditorPlatforms)` option; the set of platforms whose editor we need to build. | `BuildAndTestProject.xml` |
| `$(TargetPlatforms)` / `$(TargetConfigurations)` / `$(EditorPlatforms)` | Standard option names for the platform/config matrix. Default `Win64` / `Development` / `Win64`. | `<Option>` declarations |

**Empty-default conventions:** scripts often `<Property Name="Foo" Value="$(IsBuildMachine)"/>` to gate by CI mode; or `<Property Name="DefaultX" Value="..."/>` then conditionally clear it inside `<Do If="$(IsBuildMachine)">` so CI users must specify explicitly while locals get defaults.

---

## 12. Engine-shipped meta-scripts (source-build only)

Epic ships several BuildGraph meta-scripts in the engine source tree. They define standard scaffolds, properties, and aggregates that project scripts include and extend. **These are only present in a source-build UE clone (or a Perforce-checked-out engine tree) — installed engines (Epic Games Launcher) DO NOT have them.** Attempting to `<Include Script="..."/>` from an installed-engine layout will fail.

| Path | Provides |
|---|---|
| `Engine/Build/Graph/Tasks/BuildAndTestProject.xml` | The canonical project-test scaffold. Declares a `BuildAndTest <ProjectName>` aggregate plus standard nodes (`Compile <ProjectName>Editor Win64`, `Stage <TargetName> <Platform>`, `Publish Staged <Platform>`, etc.), and the built-in properties `$(NetworkOutputDirectory)`, `$(PreNodeName)`, `$(RequiredEditorPlatforms)`. |
| `Engine/Build/Graph/Tasks/PGOProfileProject.xml` | PGO (Profile-Guided Optimization) macros: `BasicReplayPGOProfile`, `$(AllPGOPlatforms)`, `$(PGOOptimizeCompileArgs<Platform>)`. Pair with `<Expand Name="BasicReplayPGOProfile" .../>` to wire a project's PGO pipeline (see Lyra recipe in §8). |
| `Engine/Build/Graph/Tasks/Inc/GauntletSettings.xml` | Engine-side Gauntlet defaults (timeout, default exec lists, etc.). Included by project-side `GauntletSettings.xml`. |
| `Engine/Plugins/Performance/AutomatedPerfTesting/Build/Inc/AutomatedPerfTestCommonSettings.xml` | Common settings for the AutomatedPerfTesting plugin (iteration defaults, FPS chart, CSV profiler, etc.). |
| `Engine/Plugins/Performance/AutomatedPerfTesting/Build/Inc/AutomatedPerfTestProjectSettings.xml` | Per-project AutomatedPerfTest run definitions; expects `$(ReplayName)`, `$(ProjectName)` etc. to be set by the including script. |

**Project usage pattern** (from `Samples/Games/Lyra/Build/LyraTests.xml`):

```xml
<!-- Required: set project info before including the engine scaffold -->
<Property Name="ProjectName" Value="Lyra" />
<Property Name="ProjectPath" Value="Samples/Games/Lyra" />
<Property Name="WithBATDefaults" Value="false" />  <!-- opt out of engine defaults -->

<!-- Pull in engine-side perf-test plumbing first (so its properties exist when BAT runs) -->
<Include Script="../../../../Engine/Plugins/Performance/AutomatedPerfTesting/Build/Inc/AutomatedPerfTestProjectSettings.xml" />

<!-- Project-local GauntletSettings (includes the engine one) -->
<Property Name="GauntletSettingsFile" Value="$(RootDir)/Samples/Games/Lyra/Build/GauntletSettings.xml" />

<!-- The big one: declares 'BuildAndTest Lyra' aggregate + all standard nodes -->
<Include Script="../../../../Engine/Build/Graph/Tasks/BuildAndTestProject.xml" />

<!-- PGO support (optional) -->
<Include Script="$(RootDir)/Engine/Build/Graph/Tasks/PGOProfileProject.xml" />
```

If your project is on an **installed engine** (Epic Games Launcher), prefer writing your BuildGraph script from scratch with explicit `<Compile>` / `<Cook>` / `<Stage>` / `<Command Name="BuildCookRun" />` nodes. The Lyra meta-script pattern is not available to you.

---

## 13. Extending `BuildAndTestProject.xml` — the Lyra pattern

`BuildAndTestProject.xml` exposes an `Aggregate` named `BuildAndTest <ProjectName>`. Project scripts extend by appending to a list property and declaring a super-aggregate:

```xml
<!-- 1. Take the base aggregate as the starting requirement set -->
<Property Name="BuildAndTestExtendedRequirements" Value="BuildAndTest $(ProjectName)" />

<!-- 2. Declare custom nodes that extend the build/test pipeline -->
<Agent Name="$(ProjectName) Content Validation" Type="Win64">
    <Node Name="$(ProjectName) Content Validation" Requires="$(PreNodeName)Compile Editor Win64">
        <Command Name="LyraContentValidation" Arguments="..."/>
    </Node>
</Agent>

<!-- 3. Conditionally append each custom node to the requirements -->
<Do If="!$(SkipTest)">
    <Property Name="BuildAndTestExtendedRequirements"
              Value="$(BuildAndTestExtendedRequirements);$(ProjectName) Content Validation"/>
</Do>

<Do If="!$(SkipLocalization)">
    <Property Name="BuildAndTestExtendedRequirements"
              Value="$(BuildAndTestExtendedRequirements);$(ProjectName) Localize"/>
</Do>

<!-- 4. Final super-aggregate that pulls everything in -->
<Aggregate Name="BuildAndTestExtended $(ProjectName)"
           Requires="$(BuildAndTestExtendedRequirements)" />
```

**Why this pattern:** the base aggregate has Epic's standard build+test+stage chain. The super-aggregate adds project-specific steps (content validation, localization, audit-collection updates, store deployment) without modifying the engine scaffold. CI invokes `-Target="BuildAndTestExtended <ProjectName>"` instead of `BuildAndTest`.

**`$(PreNodeName)` matters here.** Required-node names in `BuildAndTestProject.xml` are namespaced as `$(PreNodeName)Compile Editor Win64`, `$(PreNodeName)Stage Win64`, etc. — so multiple projects can coexist in one BuildGraph job. Always include `$(PreNodeName)` when referencing engine-scaffold nodes from your project script.

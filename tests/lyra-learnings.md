# Lyra learnings — what an Epic-authored sample teaches the skill

Captured: 2026-05-13. Target: `D:\LyraStarterGame` (UE 5.6, originally `Lyra.uproject` in the engine's `Samples/Games/Lyra/` tree but renamed `LyraStarterGame.uproject` for standalone distribution). Lyra is the canonical Epic CI/build-infrastructure sample — what its setup does, our skill should know.

This doc surfaces gaps. None of these are *bugs* in the skill (the existing content is correct as far as it goes) — they're **coverage gaps** the Lyra read-through identified. Triaged into MUST/SHOULD/NICE buckets at the bottom.

---

## L1. `Build/LyraBuild.xml` — the canonical "PCB-for-UGS" BuildGraph

5.9 KB Epic-authored script. **Purpose:** compile engine + project binaries, strip symbols, archive to a zip, submit to a separate Perforce stream for UnrealGameSync to consume. This is the standard pattern for distributing precompiled binaries to a team that mostly works in P4 + UGS.

Patterns/elements our skill doesn't yet document:

- **`<SetVersion Change="$(Change)" Branch="$(EscapedBranch)" If="$(Versioned)"/>`** — stamps `Build.version` with the CL + branch. Used at the top of any node that needs versioned binaries.
- **`<ForEach Name="TargetPlatform" Values="$(TargetPlatforms)">`** — runtime iteration over a semicolon-separated `<Option>`. Lyra uses it to spawn one Compile-LyraGame node per platform from a single XML.
- **`<Strip Files="#X" BaseDir="$(RootDir)" OutputDir="$(ArchiveStagingDir)" Platform="Win64"/>`** — strips pdbs/symbols into a separate output dir. Our `buildgraph.md` §4 doesn't list `<Strip>`.
- **`<Submit ... FileType="binary+FS32" Workspace="$(SubmitClient)" Stream="$(PCBSubmitPath)" RootDir="$(ArchivePerforceDir)"/>`** — submits a built archive to a *separate* P4 stream (typically `//<depot>/Engine/Build/PCBs` or similar) that UGS reads. `FileType="binary+FS32"` is the precompiled-binaries file type.
- **`$(IsBuildMachine)` built-in property** — true on CI agents (Horde), false locally. Used as conditional gate everywhere.
- **`Tag` with `Except=".../Intermediate/..."`** — exclude pattern syntax with `...` wildcards.
- **The implicit `XGEControlWorker.exe`** — `\Engine\Binaries\Win64\XGEControlWorker.exe` is a post-build copy of ShaderCompileWorker.exe needed for shader compile under IncrediBuild. Worth noting in the troubleshooting section.

**Composite ETA:** a single `RunUAT BuildGraph -Script=LyraBuild.xml -Target="Submit To Perforce For UGS"` on a multi-core build agent: ~20-40 min depending on platforms.

---

## L2. `Build/LyraTests.xml` — the canonical project-test orchestrator

13.6 KB. Far more interesting than LyraBuild.xml. **The key line:**

```xml
<Include Script="../../../../Engine/Build/Graph/Tasks/BuildAndTestProject.xml" />
```

**`BuildAndTestProject.xml` is an engine-shipped meta-script** that defines:
- A `BuildAndTest <ProjectName>` aggregate.
- A set of nodes named `Compile <ProjectName>Editor Win64`, `Stage <TargetName> <Platform>`, etc.
- Standard properties: `$(NetworkOutputDirectory)`, `$(NetworkTempRootOverride)`, `$(NetworkReportRootOverride)`, `$(IsBuildMachine)`, `$(IsPreflight)`, `$(SkipTest)`, `$(WithBATDefaults)`, etc.

**Caveat (also a finding):** `BuildAndTestProject.xml` ships only in **source-build** UE installs — it's at `Engine/Build/Graph/Tasks/BuildAndTestProject.xml`. An installed-engine user (Epic Games Launcher) doesn't get it. Our skill should warn: *"this pattern requires a source-build UE clone or a Perforce-checked-out engine tree."*

Lyra extends the aggregate by appending to `$(BuildAndTestExtendedRequirements)`:

```xml
<Property Name="BuildAndTestExtendedRequirements" Value="BuildAndTest $(ProjectName)" />
<!-- ... append more nodes -->
<Property Name="BuildAndTestExtendedRequirements" Value="$(BuildAndTestExtendedRequirements);Lyra Content Validation"/>
<Property Name="BuildAndTestExtendedRequirements" Value="$(BuildAndTestExtendedRequirements);Localize" If="..." />
<Property Name="BuildAndTestExtendedRequirements" Value="$(BuildAndTestExtendedRequirements);UpdateAuditCollections" If="..."/>
<!-- final aggregate that pulls everything in -->
<Aggregate Name="BuildAndTestExtended $(ProjectName)" Requires="$(BuildAndTestExtendedRequirements)" />
```

This pattern — append-to-a-list-then-aggregate — is genuinely useful and not in our skill.

Other patterns from LyraTests.xml worth documenting:

- **`<Do If="...">` blocks** — conditional execution of multiple elements at once (vs `If="..."` on individual elements). Cleaner for whole sections.
- **`ContainsItem('$(TargetPlatforms)', 'Win64', '+')`** — built-in BuildGraph function for membership testing in `+`-delimited lists.
- **Preflight handling:** `$(PreflightChange)` (CL number for a P4 shelve) + `$(IsPreflight)` derived flag.
- **The `DefaultEditorTestList = "UE.EditorAutomation(RunTest=Project.Maps.PIE)"` pattern** — explicit Gauntlet test-list strings with `RunTest=` parameter inside parens.
- **`<Property Name="WithBATDefaults" Value="false" />`** before the include — opt-out of `BuildAndTestProject.xml`'s defaults so the project script controls them.
- **The Localization workflow** via `<Command Name="Localize" Arguments="-LocalizationProvider=XLoc_Sample ...">` — invoking the `Localize` UAT command with provider-specific args (XLoc, Crowdin, OneSky).
- **Audit Collections pattern** — `<Command Name="Lyra_UpdateAuditCollections">` reads `Manifest_UFSFiles_Win64.txt` (the cook output manifest) and produces a `.collection` file at `Content/Collections/Audit_InCook.collection`. Useful for content engineers to audit "what's actually cooked".
- **Epic Game Store deployment** via `<Command Name="DeployToEpicGameStore" Arguments="-ArtifactId=... -BuildRoot=... -CloudDir=... -BuildVersion=... -AppLaunch=... -Platform=Windows -CommandLineFile=...">` — full BPT (BuildPatchTool) integration.

---

## L3. `Build/Scripts/Lyra.Automation.csproj` — custom UAT script project pattern

Verbatim:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netcoreapp3.1</TargetFramework>
    <OutputType>Library</OutputType>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <GenerateTargetFrameworkAttribute>false</GenerateTargetFrameworkAttribute>
    <Configurations>Debug;Release;Development</Configurations>
    <RootNamespace>Lyra.Automation</RootNamespace>
    <AssemblyName>Lyra.Automation</AssemblyName>
    <OutputPath>..\..\..\..\..\Binaries\DotNET\AutomationTool\AutomationScripts\Lyra</OutputPath>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningsNotAsErrors>612,618</WarningsNotAsErrors>
    <DebugType>pdbonly</DebugType>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\AutomationUtils\AutomationUtils.Automation.csproj" />
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\CrowdinLocalization\CrowdinLocalization.Automation.csproj" />
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\Localization\Localization.Automation.csproj" />
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\OneSkyLocalization\OneSkyLocalization.Automation.csproj" />
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\XLocLocalization\XLocLocalization.Automation.csproj" />
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\Shared\EpicGames.Core\EpicGames.Core.csproj" PrivateAssets="All">
      <Private>false</Private>
    </ProjectReference>
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\AutomationTool\Gauntlet\Gauntlet.Automation.csproj" PrivateAssets="All">
      <Private>false</Private>
    </ProjectReference>
    <ProjectReference Include="..\..\..\..\..\Engine\Source\Programs\UnrealBuildTool\UnrealBuildTool.csproj" />
  </ItemGroup>
</Project>
```

**Why this matters:** UAT auto-discovers `*.Automation.csproj` files anywhere in the engine tree (and in project-side `Build/` directories when `-ScriptsForProject=` is set). Building this csproj produces `Lyra.Automation.dll` at `<Engine>/Binaries/DotNET/AutomationTool/AutomationScripts/Lyra/`. UAT loads the DLL and exposes any `BuildCommand` subclass as a runnable command.

**Worth noting:**
- `TreatWarningsAsErrors=true` with `WarningsNotAsErrors=612,618` — Epic's own convention; allow obsolete + obsoleted-member warnings, fail on everything else.
- The set of project references is the canonical "what you need to extend UAT": AutomationUtils, Gauntlet (private), the localization variants, EpicGames.Core (private), UnrealBuildTool.

---

## L4. `LyraTest.ContentValidation.cs` — a 320-line real-world `BuildCommand`

Verbatim header attributes show the canonical `[Help]` usage:

```csharp
[Help("Commandlet for checking content to know if passes all the existing UEditorValidators.")]
[Help("Branch=<Name>", "Branch to use")]
[Help("CL=<value>", "Check file changes in the range LastCL,CL")]
[Help("p4shelved", "If specified, treat CL as a shelved file to check the contents")]
[Help("p4opened", "Check currently opened files instead of using CL ranged")]
[Help("MaxPackagesToLoad=<value>", "Maximum number of recent changes to check")]
[Help("LastGoodContentCLPath=<value>", "A directory location to store the 'last good' CL so we can determine CLs between runs.")]
public class LyraContentValidation : BuildCommand
{
    public override void ExecuteBuild()
    {
        // ...
        bool CheckOpenedFiles = ParseParam("opened");
        string ThisCL = ParseParamValue("CL");
        // ...
        CommandUtils.RunCommandlet(
            new FileReference(CombinePaths(CmdEnv.LocalRoot, GameProjectDirectory, GameProject)),
            EditorExe,
            "ContentValidationCommandlet",
            CommandletArgs);
    }
}
```

**The killer API:** `CommandUtils.RunCommandlet(uproject, editorExe, "ContentValidationCommandlet", args)` — the canonical "from UAT, spin up the editor and run this commandlet" call. Our `reference/uat.md` doesn't show this.

Other patterns:
- `ParseParam("name")` for booleans / `ParseParamValue("Name", default)` for strings — standard UAT arg parsing.
- `P4.GetAuthenticationToken()`, `P4.Changes(...)`, `P4.DescribeChangelist(...)`, `P4.Files(...)`, `P4.Opened(...)` — the UAT P4 wrapper API.
- `P4Env.Client`, `P4Env.User`, `P4Env.ServerAndPort` — env-derived P4 info.
- `AutomationException(...)` — the right exception type for command-level failures.
- **Smart skip logic:** persists `LastGoodContentCL` to a file; subsequent runs that share or precede that CL skip the commandlet entirely. Saves CI time.
- **Retry loop pattern:** 10 retries with 5s sleep for file I/O failures.
- **Extension prefilter:** before firing up the editor (slow), check the P4 changelist for any files of interest (fast). If none of the changes touch `.uasset/.umap/.cpp/.h/.ini/.uproject/.uplugin/.json`, skip.

---

## L5. `LyraTest.BootTest.cs` + `LyraTestConfig.cs` — Gauntlet test patterns

```csharp
public class BootTest : EpicGameTestNode<LyraTestConfig>
{
    public BootTest(UnrealTestContext InContext) : base (InContext) { }

    public override LyraTestConfig GetConfiguration()
    {
        LyraTestConfig Config = base.GetConfiguration();
        Config.NoMCP = true;
        UnrealTestRole Client = Config.RequireRole(UnrealTargetRole.Client);
        Client.Controllers.Add("BootTest");
        return Config;
    }
}
```

```csharp
public class LyraTestConfig : EpicGameTestConfig
{
    [AutoParam]
    public int TargetNumOfCycledMatches = 2;

    public override void ApplyToConfig(UnrealAppConfig AppConfig, UnrealSessionRole ConfigRole, IEnumerable<UnrealSessionRole> OtherRoles)
    {
        base.ApplyToConfig(AppConfig, ConfigRole, OtherRoles);
        if (AppConfig.ProcessType.IsClient())
        {
            AppConfig.CommandLine += string.Format(" -TargetNumOfCycledMatches={0}", TargetNumOfCycledMatches);
        }
        const float InitTime = 120.0f;
        const float MatchTime = 300.0f;
        MaxDuration = InitTime + (MatchTime * TargetNumOfCycledMatches);
    }
}
```

**What we learn:**
- Custom Gauntlet test = `EpicGameTestNode<ConfigClass>` subclass + `EpicGameTestConfig` subclass.
- `[AutoParam]` on a public field → automatic CLI-arg parsing (`-TargetNumOfCycledMatches=5`).
- `Config.NoMCP = true` — disables MCP/Epic Online Services for the test session.
- `Config.RequireRole(UnrealTargetRole.Client)` then `.Controllers.Add("BootTest")` — wires the engine-side `UTestController_BootTest` Blueprint/C++ class.
- `ApplyToConfig` is where you mutate `AppConfig.CommandLine` per role, set `MaxDuration`, etc.

This is the missing detail in our `reference/uat.md` §4 "Testing via UAT" — how to actually *author* a test, not just run an existing one.

---

## L6. `Build/BatchFiles/Run*.bat` — local convenience scripts

Three files, very illuminating in their simplicity:

```bat
:: RunLocalTests.bat
pushd "%~dp0..\..\..\..\.."
call .\Engine\Build\BatchFiles\RunUAT.bat BuildGraph -Script=Samples/Games/Lyra/Build/LyraTests.xml -Target="BuildAndTest Lyra" -UseLocalBuildStorage
pause
```

```bat
:: RunLocalPackage.bat
pushd "%~dp0..\..\..\..\.."
call .\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -nop4 -project=./Samples/Games/Lyra/Lyra.uproject -cook -stage -archive -archivedirectory=./Samples/Games/Lyra/PackagedDev -package -compressed -pak -prereqs -targetplatform=Win64 -build -target=LyraGame -clientconfig=Development -utf8output -compile
pause
```

**New flags our skill doesn't list:**

- **`-UseLocalBuildStorage`** (BuildGraph flag) — use a local-filesystem path for inter-node artifact storage instead of network/Horde shared storage. Essential for local-dev BuildGraph runs.
- **`-compile`** (RunUAT/BCR flag) — instructs UAT to compile its script .csproj files before running. Useful when you've changed a `MyProject.Automation.csproj`.

**The `pushd "%~dp0..\..\..\..\.."` pattern** — anchor the working dir to the engine root regardless of where the bat is invoked from. (`%~dp0` is the bat's own directory; `..\..\..\..\..` walks up to the engine root since the bat lives at `Samples/Games/Lyra/Build/BatchFiles/`.) Real-world convenience pattern worth documenting.

---

## L7. `Build/UnrealGameSync.ini`

```ini
[Default]
BuildHealthProject=Lyra

;[//UE5/Main/Samples/Games/Lyra/Lyra.uproject]
;Message=:alert: You can put a message here, including [hyperlinks to docs](http://example.com)
;StatusPanelColor=#9b49cc
```

**Minimal but informative:** the per-project UGS config that's auto-discovered by UGS at `<project>/Build/UnrealGameSync.ini`. The commented section shows you can inject messages (with Slack-style emoji + markdown links) and recolour the UGS status panel per project. Real-world UGS customisation pattern.

---

## L8. `LyraDeployment.EpicGameStore.cs` — store-deployment pattern (selected)

```csharp
public class DeployToEpicGameStore : BuildCommand
{
    static string DownloadBuildPackageTool()
    {
        // Downloads BPT from Epic's CDN at runtime
        string BuildPackageToolUrl = "https://launcher-public-service-prod.ol.epicgames.com/launcher/api/installer/download/BuildPatchTool.zip";
        // ... unzip + execute
    }

    public override void ExecuteBuild()
    {
        var LogInstanceId = Guid.NewGuid().ToString("N");  // correlation id for logs
        var BuildPathToolPath = DownloadBuildPackageTool();
        // ... ParseParamValue("ArtifactId"), ParseParamValue("BuildRoot"), etc.
        // Then shell BPT.exe with all the args
    }
}
```

**Pattern:** download Epic's `BuildPatchTool.exe` from their public service URL, unzip locally, exec it with credentials passed via `-CommandLineFile=<path-to-secrets.json>`. Useful template for any store-upload UAT command.

---

## Triage — what should land in the skill

**Status (2026-05-13):** v1.4 has landed all MUST + SHOULD items below. NICE items remain backlog.

### ✅ MUST (landed in v1.4)

1. **Document `BuildAndTestProject.xml`** in `buildgraph.md` as the canonical project-test scaffold. Include the caveat: **source-build engine only**. Show the `<Include Script="..."/>` + `<Property Name="WithBATDefaults" Value="false"/>` + append-to-`$(BuildAndTestExtendedRequirements)` + final `<Aggregate Name="BuildAndTestExtended <X>">` pattern.
2. **Add `<Strip>` task** to `buildgraph.md` §4 built-in tasks reference. Plus `<ForEach>` and `<Do If="...">` blocks.
3. **Add `-UseLocalBuildStorage`** and `-compile` flags to `uat.md` (and `commands.md` `.uat` entry).
4. **Add the "custom UAT script project" pattern** to `uat.md` §3 (or new subsection). Lyra.Automation.csproj as the canonical template.

### SHOULD (medium value, medium cost — v1.5)

5. **Gauntlet test authoring pattern** (`EpicGameTestNode<Config>` + `EpicGameTestConfig` + `[AutoParam]`) — add to `channel-authoring.md` OR a new "writing UAT/Gauntlet code" section in `uat.md`. Currently we only document how to *invoke* Gauntlet tests.
6. **`CommandUtils.RunCommandlet(uproject, exe, name, args)` API** — add to `channel-authoring.md` "Driving a commandlet from your channel" §6.4 as Pattern C: "from a UAT BuildCommand, use `CommandUtils.RunCommandlet`".
7. **PCB-for-UGS workflow** — add to `workflows.md` (recipe 15?) — the LyraBuild.xml pattern for "build, strip, zip, submit to a separate stream for UGS".

### NICE (low value or specific use case — v1.5+)

8. UnrealGameSync.ini examples (BuildHealthProject, Message, StatusPanelColor) — minor.
9. Localization UAT command (`Localize -LocalizationProvider=XLoc_Sample -APIKey=...`) — add to commandlet recipes.
10. Audit Collections pattern (`Manifest_UFSFiles_<P>.txt` → `.collection`) — niche.
11. Epic Game Store deployment via BPT — too specific to most readers.
12. `pushd "%~dp0..\..\..\..\.."` convenience-bat pattern — small but useful.

---

## Open questions for the user

1. **Land v1.4 with the MUST items now**, or hold for a bigger batch including SHOULD items?
2. **Should we add a `reference/lyra-patterns.md`** file (single source of truth for "things copied from Lyra")? Or fold into the existing 8 reference files?
3. **Skill alignment with installed-engine vs source-build:** the skill currently assumes installed engine (ProjectGear context). Several Lyra patterns (`BuildAndTestProject.xml` include, the PCB workflow) are source-build-only. Should the skill explicitly call out which features need a source build?

The Lyra read-through alone has surfaced more material than the entire 13-scenario synthetic GREEN corpus combined — and none of it is "the skill is broken", all of it is "the skill could do more". That's exactly what battle-testing on real projects should produce.

---

## Addendum — latest Lyra in `EpicGames/UnrealEngine` `release` branch (via `gh`)

The local copy at `D:\LyraStarterGame` is 5.6. Reading the latest from `github.com/EpicGames/UnrealEngine/tree/release/Samples/Games/Lyra` surfaces substantial additions that weren't in the local copy.

### L9. `GauntletSettings.xml` — Gauntlet defaults via includes

New file in the latest Lyra:

```xml
<BuildGraph ...>
  <Option Name="GauntletTimeout" DefaultValue="2400" Description="..."/>
  <Property Name="ExtraAutomatedPerformanceCommonArgs" Value="-windowed -BuildName=$(BuildNamePath)" />
  <Option Name="ResX" DefaultValue="1920" Restrict="^[0-9]+$" Description="..."/>
  <Option Name="ResY" DefaultValue="1080" Restrict="^[0-9]+$" Description="..."/>

  <Include Script="$(RootDir)/Engine/Plugins/Performance/AutomatedPerfTesting/Build/Inc/AutomatedPerfTestCommonSettings.xml" />
  <Include Script="$(RootDir)/Engine/Build/Graph/Tasks/Inc/GauntletSettings.xml" />
</BuildGraph>
```

**Two more engine-shipped meta-scripts our skill doesn't document:**

- `Engine/Plugins/Performance/AutomatedPerfTesting/Build/Inc/AutomatedPerfTestCommonSettings.xml` — common settings for AutomatedPerfTest plugin (our skill mentions this plugin but not the BuildGraph wiring).
- `Engine/Build/Graph/Tasks/Inc/GauntletSettings.xml` — engine-shipped Gauntlet defaults. Sets timeouts, exec lists, etc.

LyraTests.xml then references this via `<Property Name="GauntletSettingsFile" Value="$(RootDir)/Samples/Games/Lyra/Build/GauntletSettings.xml" />`.

### L10. PGO (Profile-Guided Optimization) builds — entire new BuildGraph section

The latest LyraTests.xml adds a PGO section (~50 lines) using:

```xml
<Include Script="$(RootDir)/Engine/Build/Graph/Tasks/PGOProfileProject.xml" />

<ForEach Name="Platform" Values="$(AllPGOPlatforms)"
         If="ContainsItem('$(TargetConfigurations)','Test','+') or ContainsItem('$(TargetConfigurations)','Shipping','+')">
    <Property Name="StagedPlatformFolder" Value="$(Platform)"/>
    <Property Name="StagedPlatformFolder" Value="Windows" If="'$(Platform)'=='Win64'"/>
    ...
    <Expand Name="BasicReplayPGOProfile"
        Platform="$(Platform)"
        Configuration="$(TargetConfigurations)"
        LocalReplay="$(ProjectPath)/Build/Replays/PGO.replay"
        LocalStagingDir="..."
        Build="$(ProjectPath)/Saved/StagedBuilds/$(StagedPlatformFolder)"
        BuildRequires="$(PreNodeName)Stage $(Platform)"
        CompileArgs="$(GenericCompileArguments) $(ExtraTargetCompileArguments)" />

    <!-- Then a second pass that rebuilds with PGO data -->
    <Agent Name="PGO Optimize Agent $(Platform)" Type="$(HostAgentType)">
        <Node Name="$(ProjectName) PGO Optimize $(Platform)" Requires="$(PreNodeName)PGO Profile Replay $(Platform)">
            <ForEach Name="Configuration" Values="$(TargetConfigurations)" Separator="+">
                <Compile Target="$(TargetName)" Platform="$(Platform)" Configuration="$(Configuration)"
                         Arguments="$(PGOOptimizeCompileArgs$(Platform)) -BuildVersion=&quot;$(BuildVersion)&quot; ..." />
            </ForEach>
        </Node>
    </Agent>
</ForEach>
```

Comment in the script gives the exact invocations:

```
RunUAT BuildGraph -script="...\LyraTests.xml" -target="Lyra PGO Profile Replay Win64" \
    -set:TargetConfigurations=Shipping -set:WithWin64=true -set:PGOAutoSubmitResults=true

RunUAT BuildGraph -script="...\LyraTests.xml" -target="Lyra PGO Optimize Win64" \
    -set:TargetConfigurations=Shipping -set:WithWin64=true
```

**New findings:**
- `Engine/Build/Graph/Tasks/PGOProfileProject.xml` — engine-shipped PGO meta-script (a fourth!).
- `<Expand Name="BasicReplayPGOProfile" .../>` — macro expansion from the included script.
- **PGO is two-step:** Profile (gather perf data from a replay run) → Optimize (rebuild with PGO data).
- **PGO requires Test or Shipping configurations** (Development PGO is meaningless).
- **`$(PGOOptimizeCompileArgs$(Platform))` — variable-name interpolation.** Real BuildGraph feature: the property name itself is computed from another property's value. Powerful but obscure.

### L11. Cook test matrix — 11 cook flavours

The latest Lyra exposes 11 cook-flavour test options via `<Option>` flags:

```xml
<Option Name="RunCookOnTheFlyTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunFastCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunColdCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunCookByTheBookCacheSettingsTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunUnversionedCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunIterativeCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunInterruptedCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunCookSinglePackageByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunIncrementalCookByTheBookTest" DefaultValue="$(RunAllCookTests)" />
<Option Name="RunProjectTests" DefaultValue="false" />
```

Each appends a Gauntlet test selector to `DefaultTargetTestList` — for example:

```xml
<Property Name="DefaultTargetTestList" Value="$(DefaultTargetTestList)+UE.CookByTheBook(Map=L_Expanse)" If="$(RunCookByTheBookTest)" />
<Property Name="DefaultTargetTestList" Value="$(DefaultTargetTestList)+UE.IterativeCookByTheBook" If="$(RunIterativeCookByTheBookTest)" />
<Property Name="DefaultTargetTestList" Value="$(DefaultTargetTestList)+UE.CookSinglePackageByTheBook(Map=L_Expanse, WorldPartitionMap)" If="$(RunCookSinglePackageByTheBookTest)" />
<Property Name="DefaultTargetTestList" Value="$(DefaultTargetTestList)+UE.TargetAutomation(RunTest=Group:Project)" If="$(RunProjectTests)" />
```

**These are real Gauntlet test node names** in `Engine/Source/Programs/AutomationTool/Gauntlet/Unreal/Automation/UE.CookByTheBook.cs`. Our skill's §4 mentions `UE.BootTest` / `UE.EditorAutomation` / `UE.TargetAutomation` but not these eight cook-test variants.

### L12. `<Switch>`/`<Case>`/`<Default>` element — XML control flow

Not in our skill. Example from Lyra:

```xml
<Switch>
    <Case If="$(Horde)">
        <RetrieveArtifact Name="$(ProjectName)-Staged-$(UploadPlatform)" Type="staged-build" OutputDir="$(ProjectOutputDirectory)/$(UploadPlatform)" />
    </Case>
    <Default>
        <Copy From="$(NetworkOutputDirectory)/$(UploadPlatform)/Staged/..." To="$(ProjectOutputDirectory)/$(UploadPlatform)/..." />
    </Default>
</Switch>
```

Cleaner than chaining `<Do If="X">` + `<Do If="!X">` blocks. Worth adding to schema reference.

### L13. `<RetrieveArtifact>` task — Horde-aware artifact pull

```xml
<RetrieveArtifact Name="<ProjectName>-Staged-<Platform>" Type="staged-build"
                  OutputDir="$(ProjectOutputDirectory)/$(Platform)" />
```

Pulls a previously-staged build artifact from Horde's artifact store. Companion to `<CreateCloudArtifact>` (which our skill does mention). Not in our skill.

### L14. Built-in BuildGraph properties our skill doesn't list

From reading the upstream Lyra scripts:

- **`$(IsBuildMachine)`** — true on CI agents.
- **`$(IsPreflight)`** — true when `-set:PreflightChange=<cl>` is set.
- **`$(Horde)`** — true when running under Horde specifically.
- **`$(Change)`** — current CL (engine-side).
- **`$(EscapedBranch)`** — current branch name with `/` → `+` substituted (safe for file paths).
- **`$(Branch)`** — current branch path (P4 stream).
- **`$(RootDir)`** — workspace root.
- **`$(BuildName)`** / **`$(BuildNamePath)`** — derived build version names; `BuildNamePath` includes the preflight suffix.
- **`$(PreNodeName)`** — prefix used by `BuildAndTestProject.xml` for project-namespaced node names.
- **`$(RequiredEditorPlatforms)`** — set by BuildAndTestProject from CLI options.
- **`$(NetworkOutputDirectory)`** — shared-storage path for build outputs.

These should all be documented in our `buildgraph.md` as "built-in BuildGraph properties available without explicit `<Option>` or `<Property>` declaration."

### L15. Smartling provider for localization

Latest Lyra adds Smartling alongside XLoc / Crowdin / OneSky:

```xml
<Option Name="Smartling_ProjectId" DefaultValue="" />
<Option Name="Smartling_UserId" DefaultValue="" />
<Option Name="Smartling_APISecret" DefaultValue="" />
...
<Command Name="Localize" Arguments="-LocalizationProvider=Smartling_Sample
    -UEProjectDirectory=$(ProjectPath) -UEProjectName=$(ProjectName)
    -LocalizationProjectNames=$(ProjectsIncludedInLocalization)
    -LocalizationBranch=&quot;$(EscapedBranch)&quot;
    -SmartlingProjectId=&quot;$(Smartling_ProjectId)&quot;
    -SmartlingUserId=&quot;$(Smartling_UserId)&quot;
    -SmartlingAPISecret=&quot;$(Smartling_APISecret)&quot;" />
```

UAT now ships `SmartlingLocalization.Automation.csproj` alongside XLoc/Crowdin/OneSky.

### L16. `LyraGameSteam` / `LyraGameSteamEOS` targets

The TargetName option has expanded from `LyraGame|LyraGameEOS` to `LyraGame|LyraGameEOS|LyraGameSteam|LyraGameSteamEOS`. **This is the canonical pattern for multi-storefront builds** — separate target names per platform/storefront, each with its own `*.Target.cs` declaring different `bUseEpicOnlineServices`, `bUseSteamSubsystem`, etc. Worth adding to our skill as an example of how Epic handles "same project, different storefront builds".

---

## Updated triage

Adding to the original triage above:

### MUST (high value, low cost — land in v1.4)

Additions from latest Lyra:
- **List of engine-shipped meta-scripts** in `buildgraph.md`: `BuildAndTestProject.xml`, `PGOProfileProject.xml`, `GauntletSettings.xml` (the engine one at `Engine/Build/Graph/Tasks/Inc/`), `AutomatedPerfTestCommonSettings.xml`. Plus the warning: most of these need a source-build engine.
- **Built-in BuildGraph properties table** in `buildgraph.md` §3: `$(IsBuildMachine)`, `$(IsPreflight)`, `$(Horde)`, `$(Change)`, `$(Branch)`, `$(EscapedBranch)`, `$(RootDir)`, `$(BuildName)`, `$(BuildNamePath)`, `$(PreNodeName)`, `$(RequiredEditorPlatforms)`, `$(NetworkOutputDirectory)`.

### SHOULD (medium value — v1.5)

Additions:
- **PGO build workflow** as a recipe in `workflows.md` — Profile → Optimize two-step with `BasicReplayPGOProfile` expansion.
- **Cook test matrix** mentioned in `uat.md` §4 alongside the existing UE.BootTest/EditorAutomation/TargetAutomation — list `UE.CookOnTheFly`, `UE.CookByTheBook`, `UE.FastCookByTheBook`, `UE.ColdCookByTheBook`, `UE.CookByTheBookCacheSettings`, `UE.UnversionedCookByTheBook`, `UE.IterativeCookByTheBook`, `UE.InterruptedCookByTheBook`, `UE.CookSinglePackageByTheBook`, `UE.IncrementalCookByTheBook`.
- **`<Switch>`/`<Case>`/`<Default>` + `<RetrieveArtifact>` tasks** in buildgraph.md §4.
- **Multi-storefront target pattern** (`LyraGame|LyraGameSteam|LyraGameEOS|LyraGameSteamEOS`) — a paragraph in `commands.md` or `uat.md` about how Epic structures per-storefront targets.

### NICE (v1.5+)

- **Variable property-name interpolation** (`$(PGOOptimizeCompileArgs$(Platform))`) — advanced; mention once.
- **Smartling localization provider** — add to the existing XLoc/Crowdin list.

---

## Now what

The latest-upstream reading has roughly **doubled** the things we should add to the skill. Most are coverage gaps, not bugs. I'd propose:

- **v1.4** lands MUST items from both passes (~9 changes across buildgraph.md + uat.md). ~30 min of doc edits.
- **v1.5** lands SHOULD items (~6 changes). Another 30 min.
- **v1.6** picks up NICE items as time permits.

Or one big v1.4 with everything. Up to the user.

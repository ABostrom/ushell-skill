# Epic EngineTest learnings — what Epic's own test-pipeline sample teaches the skill

Captured: 2026-05-13. Target: `C:\Users\Aaron\Downloads\Build (1)\Build\` (Epic's `EngineTest` sample, an Epic-internal project. Source-build only — not in Lyra's public release branch.)

EngineTest is structurally **distinct from Lyra** despite occasional overlap. Lyra is "ship a game"; EngineTest is "test the engine itself". Their BuildGraph approaches differ in size, modularity, and conventions.

Files reviewed:
- `EngineTest.xml` (922 lines, main script)
- `EngineTest_CommonProperties.xml` (104 lines, shared properties)
- `EngineTest_TestOptions.xml` (116 lines, user-facing test toggles)
- `EngineTest_TestConfigs.xml` (476 lines, 26-entry test-config matrix)
- `EngineTestPCB.xml` (159 lines, separate PCB-for-UGS pipeline)
- `Scripts/EngineTest.Automation.csproj` (UAT script project)
- `Scripts/HelloWorld.Automation.cs` (12-line minimal skeleton)
- `Scripts/RunEngineTest.cs` (wrapper BuildCommand)
- `Scripts/EngineTestCookedEditor.Automation.cs` (subclass with ModifyParams hook)
- `Scripts/Tests/EngineTest.NetworkingTestDedicatedServer.cs` (Gauntlet test node)
- `Scripts/Tests/EngineTest.NetworkingTestListenServer.cs` (Gauntlet test node w/ custom config class)

---

## E1. `HelloWorld.Automation.cs` — the minimal skeleton

12 lines, zero ceremony:

```csharp
namespace AutomationTool
{
    class HelloWorld : BuildCommand
    {
        public override ExitCode Execute()
        {
            Log.Logger.LogInformation("Hello World");
            return ExitCode.Success;
        }
    }
}
```

**Why it matters:** every studio that authors a custom UAT command starts with this skeleton. It's the entry point we should hand readers in `uat.md` §10.5 before showing them the `LyraContentValidation` 320-line beast.

Note: lives inside `EngineTest/Build/Scripts/`, not in `Engine/Source/Programs/AutomationTool/Scripts/`. So it's part of EngineTest's `EngineTest.Automation.csproj`, not a standalone Epic-shipped example.

---

## E2. `RunEngineTest : RunUnrealTests` — dev-ergonomics wrapper (Pattern B)

```csharp
public class RunEngineTest : RunUnrealTests
{
    public override string DefaultTestName { get { return "EngineTest"; } }

    public override ExitCode Execute()
    {
        Globals.Params = new Gauntlet.Params(this.Params);
        UnrealTestOptions ContextOptions = new UnrealTestOptions();
        AutoParam.ApplyDefaults(ContextOptions);
        ContextOptions.Project           = "EngineTest";
        ContextOptions.Namespaces        = "EngineTest,Gauntlet.UnrealTest";
        ContextOptions.UsesSharedBuildType = true;
        AutoParam.ApplyParams(ContextOptions, Globals.Params.AllArguments);
        return RunTests(ContextOptions);
    }
}
```

**Pattern:** subclass an existing UAT command (here `RunUnrealTests`), bake in project defaults inside `Execute()`. Operators call `RunUAT RunEngineTest -test=BootTest` instead of `RunUAT RunUnrealTests -project=EngineTest -namespaces=EngineTest,Gauntlet.UnrealTest -uses-shared-build-type -test=BootTest`.

**Important nuance:** EngineTest's own BuildGraph (`EngineTest.xml:194`) still invokes `<Command Name="RunUnreal" Arguments="$(AllTestArgs)"/>` directly. The wrapper isn't used by CI — it's pure dev-ergonomics for humans on terminals. CI passes full args explicitly via BuildGraph properties; humans get the shortcut.

**Distinction from Pattern A:** Lyra's `LyraContentValidation` is called *from* BuildGraph nodes (does project-specific work). EngineTest's `RunEngineTest` is called *from human terminals* (saves typing).

---

## E3. `MakeEngineTestCookedEditor : MakeCookedEditor` — subclass with `ModifyParams` hook

```csharp
class MakeEngineTestCookedEditor : MakeCookedEditor
{
    public override void ExecuteBuild()
    {
        List<string> NewParams = new List<string>(Params);
        NewParams.Add("project=EngineTest");
        Params = NewParams.ToArray();
        base.ExecuteBuild();
    }

    protected override void ModifyParams(ProjectParams Params)
    {
        if (bIsCookedCooker)
        {
            // modify cooked cooker settings here
        }
        else
        {
            // modify cooked editor settings here
        }
    }
}
```

**Pattern:** subclass an engine-shipped command (`MakeCookedEditor`), inject `-project=EngineTest` into `Params` early (before path setup runs), override `ModifyParams` to tweak project-specific cooked-editor / cooked-cooker settings.

**`ModifyParams` is the canonical extension hook** for UAT commands that subclass an engine command — the base class calls into it at the right time so subclasses can mutate `ProjectParams`.

---

## E4. `<Macro>` — first-class BuildGraph functions

Our skill barely mentions `<Macro>`. EngineTest's entire architecture is built on it. The pattern:

```xml
<Macro Name="HostPrerequisites" Arguments="Platform">
  <!-- body uses $(Platform) as a parameter -->
  <Agent Name="Prereqs Agent $(Platform)" Type="Win64">
    <Node Name="Compile EngineTest Prereqs $(Platform)">
      <Compile Target="CrashReportClient" Platform="$(Platform)" Configuration="Shipping"/>
      ...
    </Node>
  </Agent>
</Macro>

<!-- Instantiate -->
<Expand Name="HostPrerequisites" Platform="Win64"/>
<Expand Name="HostPrerequisites" Platform="Linux"/>
<Expand Name="HostPrerequisites" Platform="Mac"/>
```

**With `OptionalArguments=`:**

```xml
<Macro Name="PackageTargetPlatform"
       Arguments="Platform;HostTargetPlatform;Variations"
       OptionalArguments="CookedEditorVariations;ExtraCookerArgs;StageForMobile;ExtraCompileArgs;ExtraStageArgs">
  <Property Name="StageForMobile" Value="false" If="'$(StageForMobile)' == ''"/>
  <!-- ... -->
</Macro>
```

**The default-value idiom inside a macro:** `<Property Name="X" Value="default" If="'$(X)' == ''"/>` — set the property iff the caller didn't pass one.

**Macros that call macros:** `<Expand Name="RunTest" .../>` is invoked from inside the `HostPlatformBootTests` macro. Macros compose like functions.

**Real-world EngineTest macro inventory:**
- `RunTest` — single test node generator (~50 lines)
- `HostPrerequisites` — tools+editor+server compile per platform
- `PackageTargetPlatform` — full build/cook/stage/publish pipeline per target (~100 lines, the workhorse)
- `HostPlatformBootTests` — boot tests across editor/game/cooked-editor variations
- `TargetPlatformBootTest` — boot test on a non-host platform with device reservation
- `TargetPlatformBootTestCustomAgent` — wrapper for tests that need their own agent
- `AvailableTargetPlatformBootTests` / `AvailableTargetPlatformBootTestsCustomAgent` — extension points (empty by default; platform XMLs override)
- `SanitizeTestNodeName` — utility for cleaning `:` from node names
- `TestConfig` — generates the test config matrix entry for a `(Config, HostTargetPlatform, TargetPlatform, BuildTarget, RHI, Variation)` tuple
- `OverrideProperties` — utility for SM6/SM5 RHI suffix application
- `AddPlatform` — utility for accumulating into `$(AllVirtualizedPlatforms)`

**Total verdict on `<Macro>`:** this is the most underdocumented major BuildGraph feature in our skill. EngineTest proves the macro system scales to thousands of lines while staying readable. Worth a new buildgraph.md section dedicated to it.

---

## E5. Modular BuildGraph via wildcard includes

EngineTest splits a >1700-line BuildGraph into 5 focused files plus extension points:

```xml
<!-- in main EngineTest.xml -->
<Include Script="EngineTest_TestOptions.xml" />
<Include Script="../Restricted/NotForLicensees/Build/*TestOptions.xml"/>  <!-- Epic-internal-only -->
<Include Script="EngineTest_CommonProperties.xml" />
<Include Script="../Platforms/*/Build/PackageConfigs.xml"/>               <!-- per-console plug-in -->
<Include Script="EngineTest_TestConfigs.xml" />
<Include Script="../Platforms/*/Build/TestConfigs.xml"/>                  <!-- per-console plug-in -->
<Include Script="../Restricted/NotForLicensees/Build/*TestConfigs.xml"/>  <!-- Epic-internal-only -->
```

**Three wildcard idioms:**
1. **Sibling-file include** — `<Include Script="EngineTest_X.xml"/>` — splits the main script into focused sub-scripts.
2. **Platform plug-in** — `<Include Script="../Platforms/*/Build/*.xml"/>` — each console platform (`Platforms/PS5/`, `Platforms/XSX/`, etc.) drops a `PackageConfigs.xml` + `TestConfigs.xml` that auto-loads. New console = new folder, no edit to main script.
3. **Restricted gating** — `<Include Script="../Restricted/NotForLicensees/Build/*.xml"/>` — Epic-internal extensions live in `Restricted/NotForLicensees/` which licensees don't sync. The wildcard returns nothing for licensees, full content for Epic.

**Why split:**
- `_TestOptions.xml`: user-facing toggles (`-set:RunAITests=true`). Clean separation between options and orchestration.
- `_CommonProperties.xml`: derived properties (test arg accumulators like `$(EngineTest_GameTestArgs)`).
- `_TestConfigs.xml`: 26 `<Expand Name="TestConfig" Config="Win64Editor" ...>` calls. Pure data; no logic.
- Main `EngineTest.xml`: orchestration macros (`HostPrerequisites`, `PackageTargetPlatform`, `TestConfig`) and the `<Expand>` invocations that wire them up.

This is **the** scalable BuildGraph pattern. Our skill currently says "use `<Include>` to share properties" but never shows this depth.

---

## E6. Horde annotations + device reservation flow

```xml
<Node Name="Stage X $(Platform)" Annotations="Workflow=$(AnnotationsTarget)">
<Node Name="Install Y" Annotations="DeviceReserve=Begin">
```

**`Annotations="key=value"`** — arbitrary metadata attached to a node, consumed by Horde's dashboard / workflow system. Two known keys:
- `Workflow=X` — bucket this node into a named workflow lane for dashboard filtering.
- `DeviceReserve=Begin` / `DeviceReserve=End` — mark the start/end of a device-reservation block. Horde keeps the device assigned across nodes in the block.

**The install-once-skip pattern:**

```xml
<Property Name="WithPreInstall" Value="!$(IsVirtualizedPlatform) And $(WithDeviceReservation)"/>

<Do If="$(WithPreInstall)">
  <!-- One node installs the build and grabs the device -->
  <Expand Name="RunTest"
          TestType="UE.InstallOnly"
          TestName="None"
          NodeAnnotations="DeviceReserve=Begin"
          TestArgs="$(TestArgs) -ClientCount=1 -fullclean -destlocalinstalldir=&quot;...&quot;"/>
  <!-- All later tests skip-install onto the same device -->
  <Property Name="TestArgs" Value="$(TestArgs) -skipinstall -destlocalinstalldir=&quot;...&quot;"/>
</Do>
```

**`UE.InstallOnly`** is a Gauntlet test type that does just the install step, used as a pre-step in a chain of "real" tests. Saves N installs across N tests.

Not in our skill at all.

---

## E7. Variation system — stacked variations via `+`

```xml
<Option Name="Win64Variations" DefaultValue="Default;ASan;arm64"/>
<Option Name="MacVariations"   DefaultValue="Default;ASan;arm64"/>
<Option Name="LinuxVariations" DefaultValue="Default;ASan"/>

<!-- Stacking: -->
<Property Name="IsASanVariation"  Value="ContainsItem('$(Variation)', 'ASan', '+')"/>
<Property Name="IsArm64Variation" Value="ContainsItem('$(Variation)', 'arm64', '+')"/>
<!-- ...then conditional CompileArguments per variation flag set -->
```

Variations supported: `Default`, `ASan`, `arm64`, `HMD`, `Stereo`, `StompMalloc`, `Foo` (test placeholder). Stacked via `+` separator (e.g. `ASan+arm64`). Each variation contributes flags to `CompileArguments` / `CookerArgs` / `StagingArgs`.

**Pattern note:** each variation has a `Title` (path-friendly, prefixed with `_` if not Default) and a flag-set. `VariationTitle = ""` for Default and `"_arm64"` for arm64. Node names embed it: `Compile EngineTest Game_arm64 Win64`.

---

## E8. Priority test groups

```xml
<Option Name="RunCriticalPriorityTests" DefaultValue="false" .../>
<Option Name="RunHighPriorityTests"     DefaultValue="false" .../>
<Option Name="RunNormalPriorityTests"   DefaultValue="false" .../>
<Option Name="RunLowPriorityTests"      DefaultValue="false" .../>

<Property Name="AvailableCriticalPriorityTests" Value="BootTest"/>
<Property Name="AvailableHighPriorityTests"     Value="BootTest;System;Editor;ContentPipeline;..."/>
<Property Name="AvailableNormalPriorityTests"   Value="BootTest;UE.PLMTest;Raytracing;..."/>
<Property Name="AvailableLowPriorityTests"      Value="BootTest;AI;Audio"/>

<!-- Build-marker suffix to prevent output-dir collisions when multiple priorities run -->
<Property Name="Build-Marker" Value="-Cr" If="$(RunCriticalPriorityTests)"/>
<Property Name="Build-Marker" Value="-Hi" If="$(RunHighPriorityTests)"/>
<!-- ... -->
```

**Why:** CI can run several priority lanes (e.g. preflight = critical, post-submit = high, nightly = normal+low). Each gets its own output path via `-Cr` / `-Hi` / `-Nr` / `-Lo` suffix, so they don't clobber each other.

---

## E9. RHI matrix testing

Test configs are tuples of `(Config, HostTargetPlatform, TargetPlatform, BuildTarget, RHI, Variation)`. Same project gets tested across:
- Win64 × `{Editor, Game, Server, CookedEditor}` × `{d3d11, d3d12, vulkan}` × `{Default, Stereo, ASan, arm64, StompMalloc}`
- Mac × `{Editor, Game, CookedEditor}` × `{metal-sm5, metal-sm6}` × `{Default, ASan, arm64}`
- Linux × `{Editor, Game}` × `{vulkan}` × `{Default, ASan, Stereo}`

26 configs total in `EngineTest_TestConfigs.xml`. Each declared via:

```xml
<Expand Name="TestConfig"
        Config="Win64EditorDX12"
        HostTargetPlatform="Win64"
        TargetPlatform="Win64"
        BuildTarget="Editor"
        Tests="$(AvailableRenderingTests);$(AvailableRaytracingTests)"
        RHI="d3d12"
        Variation="Default"
        Aggregate="$(TestWin64) And $(TestEditor) And $(TestRHId3d12) And $(TestDefaultVariation)"/>
```

The `Aggregate=` field gates whether the config is included in `Run Engine Tests` aggregate based on the user's `-set:TestWin64=true -set:TestEditor=true` etc. **This is a clever boolean-gating pattern** — declarative inclusion without `If="..."` everywhere.

---

## E10. First-class BuildGraph tasks our skill doesn't list

EngineTest uses these as first-class XML tasks (not via `<Command Name="BuildCookRun" ...>`):

- **`<Compile Target="X" Platform="Win64" Configuration="Development" Arguments="..."/>`** — direct compile (UBT under the hood). Already in our skill.
- **`<Cook Project="X.uproject" Platform="Win64" Arguments="..."/>`** — direct cook. **Not in our skill — we currently route via `BuildCookRun`.** Cleaner.
- **`<Commandlet Name="DerivedDataCache" Project="EngineTest" Arguments="-fill -targetplatform=WindowsEditor"/>`** — run a commandlet. **Not in our skill.** Used here to fill DDC before editor tests.
- **`<CsCompile Project="#UAT Projects" Configuration="Development" Platform="AnyCPU" Tag="..." EnumerateOnly="true"/>`** — C# project compile with optional enumerate-without-build mode. Partially documented in our skill.
- **`<Regex Pattern="(.*):(.*)" Capture="Left;Right" Input="$(Var)"/>`** — first-class regex extraction. **Not in our skill.**
- **`<Spawn Exe="cmd.exe" Arguments="/C echo. &gt; ..."/>`** — generic process spawn. Already mentioned in passing.
- **`<Warning Message="..." If="..."/>`** / **`<Log Message="..."/>`** — diagnostic emission. **Not in our skill.**

---

## E11. Property and function operations our skill doesn't list

- **`$(VAR:60)`** — substring slice (first 60 chars). Used for truncating test names that would make node names too long.
- **`Length('$(VAR)')`** — string length. Used to gate inclusion of tag filters in node names (keeps them ≤ 100 chars).
- **`Contains('$(VAR)', 'substring')`** — substring test. Already in our skill.
- **`ContainsItem('$(LIST)', 'item', ';')`** — list membership with explicit separator. Partially documented.

---

## E12. Test args accumulator pattern

EngineTest builds long `-foo=bar -baz=qux ...` arg strings incrementally:

```xml
<Property Name="EngineTest_CommonArgs" Value="-tempdir=&quot;$(RootDir)/Tests&quot; -gauntlet.verbose -report -branch=$(Branch) -Changelist=&quot;$(Change)&quot; -ResumeOnCriticalFailure" />
<Property Name="EngineTest_CommonArgs" Value="$(EngineTest_CommonArgs) -UseTestDataV2" If="$(UseTestDataV2)"/>

<Property Name="EngineTest_EditorTestArgs" Value="-build=editor $(EngineTest_CommonArgs) $(EngineTest_DDCArgs) -maxduration=7200"/>
<Property Name="EngineTest_EditorTestArgs" Value="$(EngineTest_EditorTestArgs) -d3ddebug -stompmalloc" If="$(WithExtraValidation)"/>
<Property Name="EngineTest_EditorTestArgs" Value="$(EngineTest_EditorTestArgs) -RHIValidation" If="$(WithRHIValidation)"/>
```

**Pattern:** assign initial value, then re-assign-with-append (`$(Var) extra`) under `If="condition"`. Composable, readable. Worth showing as the canonical "how to build a long arg string from many small flags" idiom.

---

## E13. Gauntlet test classes — `UnrealTestNode<Config>` + custom `UnrealTestConfig`

`NetworkingTestListenServer` shows the full custom-config pattern:

```csharp
public class NetworkingTestListenServerConfig : UnrealGame.UnrealTestConfig
{
    string ListenServerIP = "";   // shared state across roles
    public override void ApplyToConfig(UnrealAppConfig AppConfig,
                                       UnrealSessionRole ConfigRole,
                                       IEnumerable<UnrealSessionRole> OtherRoles)
    {
        base.ApplyToConfig(AppConfig, ConfigRole, OtherRoles);
        if (ConfigRole.RoleType.IsClient())
        {
            // First client (server-role) gets a free IP and stores it
            // Subsequent clients use AppConfig.CommandLine += " -ExecCmds=\"open <IP>\" -log"
        }
    }
}

public class NetworkingTestListenServer : UnrealTestNode<NetworkingTestListenServerConfig>
{
    public override NetworkingTestListenServerConfig GetConfiguration()
    {
        var Config = base.GetConfiguration();
        IEnumerable<UnrealTestRole> Clients = Config.RequireRoles(UnrealTargetRole.Client, 3);
        Clients.ElementAt(0).Controllers.Add("NetTestGauntletServerController");
        Clients.ElementAt(0).CommandLine += " -ExecCmds=\"open ?Listen\" -log";
        Clients.ElementAt(1).Controllers.Add("NetTestGauntletClientController");
        Clients.ElementAt(2).Controllers.Add("NetTestGauntletClientController");
        return Config;
    }
}
```

**What this teaches:**
- Test node = `UnrealTestNode<ConfigClass>` subclass. Implements `GetConfiguration()`.
- Custom config = `UnrealTestConfig` subclass. Implements `ApplyToConfig(AppConfig, role, otherRoles)` to mutate per-role command lines.
- `Config.RequireRoles(UnrealTargetRole.Client, 3)` requests 3 client instances; Gauntlet allocates devices.
- `Config.NoMCP = true` / `Config.PreAssignAccount = false` — disable MCP/account flows for tests.
- `role.Controllers.Add("NetTestGauntletServerController")` — wires the engine-side `UTestController_NetTestGauntletServer` (Blueprint/C++) class to drive the role.
- `role.CommandLine += " -ExecCmds=\"open Map?Listen\""` — per-role command-line injection. Listen-server in particular needs the dynamic IP exchange shown above.

Lyra's `BootTest` (`EpicGameTestNode<LyraTestConfig>`) is simpler — single role, no shared state between roles. EngineTest's networking test shows the multi-role/shared-state variant.

---

## Triage — what to land

### A. MUST (high value, low cost — covers gaps that hurt the skill)

1. **`uat.md` §10.5 HelloWorld** — 12-line skeleton. Easy.
2. **`uat.md` §10.6 Pattern A re-frame** — already covered authoring; add the BuildGraph-side `<Command Name>` wiring with Lyra's `LyraContentValidation` example.
3. **`uat.md` §10.7 Pattern B subclass-for-ergonomics** — `RunEngineTest`, `MakeEngineTestCookedEditor`. Cite both. Highlight that EngineTest's CI doesn't use the wrapper — it's pure dev convenience.
4. **`buildgraph.md` new §13 `<Macro>` definitions** — Arguments / OptionalArguments / `<Expand>` / default-value idiom / composition. This is the biggest gap and it's a top-tier feature.
5. **`buildgraph.md` §4 add `<Cook>`, `<Commandlet>`, `<Command>`, `<Regex>`, `<Log>`, `<Warning>` as first-class tasks** in the table.
6. **`workflows.md` Recipe 17 "Author commands the project's CI can call"** — Pattern A end-to-end.
7. **`workflows.md` Recipe 18 "Add a dev-friendly UAT wrapper for your project's tests"** — Pattern B end-to-end.

### B. SHOULD (medium value — v1.6)

8. **`buildgraph.md` new §14 Modular BuildGraph structure** — wildcard includes, the `_CommonProperties` / `_TestOptions` / `_TestConfigs` split, `Platforms/*/Build/*.xml` and `Restricted/NotForLicensees/*` patterns.
9. **`buildgraph.md` new §15 Horde annotations + device reservation** — `Annotations="..."`, `UE.InstallOnly`, the install-once-skip pattern.
10. **`buildgraph.md` new §16 Variation matrix + priority lanes + RHI matrix** — stacked variations via `+`, `Build-Marker` suffixes, the `Aggregate=` boolean-gating pattern for test configs.
11. **`channel-authoring.md` Gauntlet test class deep-dive** — `UnrealTestNode<Config>` + custom `UnrealTestConfig` with `ApplyToConfig` per-role mutation, shared state across roles for listen-server tests.

### C. NICE (low priority — v1.7+ or backlog)

12. Property slicing `$(VAR:60)` + `Length()` function.
13. `<Spawn>`, `<Warning>`, `<Log>` task entries (low-frequency use).
14. Test args accumulator pattern (assign-then-re-assign-with-append idiom).

### Tests (RED → GREEN scenarios)

- **S14**: "Add an asset-audit step to our cooked build pipeline that CI runs after staging." Covers Pattern A.
- **S15**: "Make our test runner one-line callable from CI and from dev terminals — operators shouldn't need to remember `-project=X -namespaces=Y -uses-shared-build-type`." Covers Pattern B.
- **S16**: "Our BuildGraph is getting unwieldy. How do we split it into multiple files and let console platforms plug in without editing the main script?" Covers §14 modular structure.
- **S17** *(optional)*: "Set up a device-reservation block so 5 sequential tests share one install on our PS5 dev kit." Covers §15 install-once-skip.

---

## Scope estimate

The EngineTest read surfaced more than I expected. Total addressable work in MUST + SHOULD ≈ **2-3 hours** of careful doc work + 2-4 test scenarios. NICE adds ~30 min.

Split options for landing:
- **v1.5 = MUST only** (~60-75 min, ~7 doc changes + S14 + S15)
- **v1.6 = SHOULD** (~60-75 min, ~4 doc changes + S16 + S17)
- **v1.7 = NICE** (backlog)

Or one big bang:
- **v1.5 = MUST + SHOULD + NICE** (~3 hours)

Or defer most of it:
- **v1.5 = MUST only, then ship Phase 17 as v2.0 immediately** so install ergonomics aren't blocked on content perfection.

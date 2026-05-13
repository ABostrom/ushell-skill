# Cookbook — common ushell workflows

User-facing recipes for the workflows the skill encodes. For machine-readable DAGs see `reference/workflows.md`. For per-command flag reference see `reference/commands.md`.

Every recipe assumes you have a UE 5.7 branch with `Engine/Extras/ushell/ushell.bat` present, an active `.uproject`, and PowerShell access. Substitute paths for your project.

---

## Daily loop: sync, build, run editor

After a fresh P4 sync, get the editor running.

```powershell
cmd.exe /d /s /c "call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .p4 sync --nosummary && .build editor --nosummary && .run editor"
```

**What's happening:**
- `--project=<uproject>` binds the active project in the session noticeboard (each fresh ushell session is a new `$FLOW_SID`).
- `.p4 sync --nosummary` syncs engine + project, honouring `<root>/.p4sync.txt` filters.
- `.build editor --nosummary` runs UBT; auto-builds `ShaderCompileWorker`, `UnrealPak`, `InterchangeWorker`.
- `.run editor` launches `UnrealEditor.exe` with the project pre-loaded.

`--nosummary` suppresses the `== Result: Success / Time: 0:00:42` footer so a script can parse exit codes cleanly. Without it, the verb still runs — you just see the banner.

**If it fails:** the exit code is `1`. Re-read the `== Errors and warnings ==` block. Do NOT fall back to `Build.bat` / `UnrealBuildTool.exe`.

---

## Goal: an Insights trace of the game at a specific CL on PS5

This is the headline workflow. You're investigating perf at a known-bad CL. You want a `.utrace` file in Unreal Insights.

```powershell
# Write a temp .bat (multi-command form):
@"
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.p4 sync 1234567 --nosummary
.build editor --nosummary
.build game PS5 --nosummary
.zen snapshot list game PS5
"@ | Set-Content E:\trace-prep.bat
cmd.exe /d /s /c "E:\trace-prep.bat"
```

After `.zen snapshot list` prints, decide:

- **If a snapshot is available** at-or-near CL 1234567 → use the fast path:
  ```
  .zen snapshot get game PS5 1234567
  ```
- **Otherwise** → cook locally:
  ```
  .cook game PS5 --nosummary
  ```

Then in either case:

```
.stage game PS5 auto --nosummary
.run game PS5 --trace=default,gpu
.perf insights latest
```

**What you've done:**
- Synced source to a specific CL.
- Got either pre-built or freshly-cooked content for PS5.
- Staged it (using whichever packaging style — pak or Zen — matches `Saved/Cooked/<form>/ue.projectstore`).
- Launched the game on the devkit with `-trace=default,gpu` (the standard channel set + GPU timings).
- Opened the resulting `.utrace` in Unreal Insights.

**Why the `.zen snapshot list` check matters:** if a snapshot exists for that CL, downloading + importing the oplog is ~50× faster than a fresh local cook. Baseline Claude doesn't know to check; the skill always does.

---

## Reproduce a bug at a specific CL under the debugger

You got a crash report. You want to repro under VS.

```powershell
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .p4 sync <CL>"
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .sln generate open"
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .build editor"
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .run editor --attach"
```

`--attach` looks for a running VS instance with the matching `.sln` (via `vs.dte.running()`) and attaches the debugger. The `.sln open` step is critical — without it, `--attach` finds nothing.

**Optional:** add `-- -WaitForDebugger` to the `.run editor` line to halt the process at `WinMain` for early-crash investigation. Don't use in CI.

---

## Find which CL broke editor startup

The editor crashes at head, was fine at CL 1234000. You want to find the culprit unattended.

Write `E:\bisect-editor.bat`:

```bat
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.build editor --nosummary
if errorlevel 1 exit 90
.run editor -- -nullrhi -unattended -stdout -log -ExecCmds="Quit"
if errorlevel 1 exit 80
exit 0
```

Then kick off the bisect:

```powershell
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .p4 bisect 1234000 <bad-CL> -- E:\bisect-editor.bat"
```

ushell runs the bisect protocol: at each candidate CL, syncs, runs the script, reads exit code (`0=good`, `80=bad`, `90=failed-build` — treated as "ugly", expand outward). Reports the first-bad CL.

**To inspect the offending CL afterward:**

```
.p4 cherrypick --dryrun <N>
```

(or via P4V: `.p4 v` opens it scoped to the right client).

---

## Cook + stage + run on a platform with Zen storage

Modern UE 5.x default. Produces a runnable cooked build with content served from a local ZenServer.

```
.build game ps5 --nosummary
.cook game ps5 --nosummary
.stage game ps5 zen --nosummary
.zen status                      # confirm ZenServer is up
.run game ps5
```

If `.zen status` reports the server is down: `.zen start` first.

**Why `style=zen` vs `auto`:** explicit `zen` fails if Zen isn't enabled in Project Settings; `auto` falls back to pak. For a Zen-enabled project, `zen` is more strict (good for CI). For an older project, leave it `auto`.

---

## Switch to a different stream and confirm engine builds

You're moving from `//depot/Main` to `//depot/Release`.

```
.p4 switch list                  # see available streams
.p4 switch Release --nosummary   # switch + sync (shelves open files, restores after)
.build editor --nosummary        # confirm it builds clean
.info                            # verify engine + project + platforms
```

`.p4 switch` requires a stream client. If yours isn't, you'll see `Client 'X' is not a stream` — create one with `.p4 workspace <dir> //depot/Release` first.

---

## Cherrypick a hotfix from another stream

You're on `//depot/Release` and CL 1234567 in `//depot/Main` needs to come over as a hotfix.

```
.p4 cherrypick 1234567
```

That's it. ushell handles:
- Generating the cross-stream branchspec.
- Integrating the CL into a new pending CL.
- Auto-resolving safe merges.
- Clearing integration records ("edigrate") so the result looks like a native edit if the streams are unrelated.

**For partial-resolve workflows:** add `--saferesolve` to skip auto-resolve; you'll get the cherrypicked files in a pending CL needing `p4 resolve -as / -am` manually. Useful when you want one review for the easy files and a separate one for the contested ones.

---

## Run an automated perf-test sequence

`.perf test sequence` runs `RunUAT RunUnreal -test=AutomatedPerfTest.SequenceTest` against a staged build, using the project's `AutomatedSequencePerfTestProjectSettings.MapsAndSequencesToTest` config.

Preconditions:
- Project has the `AutomatedPerfTesting` plugin enabled.
- A staged build exists at `<project>/Saved/StagedBuilds/<cook_form>/`.

```
.build editor && .build game win64 && .cook game win64 && .stage game win64 auto
.perf test sequence win64 perf development game <ComboName>
```

`<ComboName>` must match a `ComboName=` entry in your project's `DefaultEngine.ini` under `[/Script/AutomatedPerfTesting.AutomatedSequencePerfTestProjectSettings] MapsAndSequencesToTest=(...)`.

`subtest=all` runs perf + LLM + Insights + GPUperf subtests sequentially. Drop `all` for single subtests:

```
.perf test sequence win64 llm development game <Combo>      # just LLM
.perf test sequence win64 insights development game <Combo> # just Insights
```

Output: CSV + `.utrace` files under `<project>/Saved/Profiling/`.

---

## Generate a Visual Studio solution

```
.sln generate open
```

Generates `<Project>.sln` (branch-name-tagged) plus `Intermediate/ProjectFiles/`, then opens VS.

For Blueprint-only projects without `Source/`, use the lightweight variant:

```
.sln open tiny
```

Generates a minimal sln in `Intermediate/ProjectFiles/TinySln/` without running UBT — useful when you just want VS for file navigation + debugging.

---

## Drive a commandlet

The generic editor commandlet entry point. ushell auto-swaps `.exe` → `-Cmd.exe`, prepends the `.uproject`, and inserts `-run=<Name>`.

```
.run commandlet ResavePackages -- -PackageDir=Content/Foo
.run commandlet DerivedDataCache -- -fill -unattended
.run commandlet GatherText -- -config=Config/Localization/Game.ini
.run commandlet WorldPartitionBuilder -- /Game/Maps/MyMap -Builder=Minimap
```

To rebuild the editor first (if your `.target` is stale):

```
.run commandlet ResavePackages --build -- -PackageDir=Content/Foo
```

To debug a commandlet:

```
.run commandlet ResavePackages --attach -- -PackageDir=Content/Foo
```

`--attach` re-dispatches through `_run commandlet ... --attach` which has full debugger plumbing (VS / lldb / Rider via `$USHELL_DEBUGGER`).

---

## Run BuildCookRun directly

When `.cook` / `.stage` wrappers don't fit (custom shipping pipeline, plugin packaging, signing, etc.):

```
.uat BuildCookRun -- ^
  -project=<full-path>\MyGame.uproject ^
  -target=MyGame ^
  -platform=Win64 ^
  -clientconfig=Shipping ^
  -build -cook -stage -pak -iostore -compressed -package -archive ^
  -archivedirectory="D:\Out\Shipping" ^
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

**Append for CI** (mandatory if running headless):

```
-buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog
```

`-buildmachine` is the magic flag — disables every modal dialog, kills the crash reporter, removes warning caps, dumps cook-timing CSV. Without it, CI hangs.

**For client + dedicated server in one CI run**, split into two BCR calls (cleaner archive paths):

```
.uat BuildCookRun -- -target=MyGame       -platform=Win64 -clientconfig=Shipping -build -cook -stage -pak -iostore -compressed -archive -archivedirectory=D:\Out\Win64 ...
.uat BuildCookRun -- -target=MyGameServer -platform=Linux -serverconfig=Shipping -server -noclient -build -cook -stage -pak -iostore -compressed -archive -archivedirectory=D:\Out\LinuxServer ...
```

**For encrypted/signed paks (Marketplace, store submission):**

```
-encryptinifiles -signpak -signpakid=<id> -cryptokeys="<path-to-keychain.json>"
```

**Don't use `-sign` alone** (doesn't exist). **Don't use `-RunAutomationTest=`** under BCR (fragile; client exits before UAT polls). Use Gauntlet `RunUnreal -test=UE.TargetAutomation` for packaged-target tests instead.

---

## Package a plugin for Marketplace

```
.uat BuildPlugin -- ^
  -Plugin="<full-path>\MyPlugin.uplugin" ^
  -Package="D:\Out\MyPlugin" ^
  -TargetPlatforms=Win64+Linux ^
  -Rocket -StrictIncludes ^
  -unattended -nop4
```

**The `-TargetPlatforms=` is non-optional.** Since UE 4.25, `BuildPlugin` defaults to **every detected SDK platform** and aborts on the first missing one. Always pass an explicit list.

For Marketplace submission: append `-StrictIncludes` (IWYU enforcement — Marketplace QA runs equivalent checks). `-Rocket` emulates the binary engine layout users have.

Binary plugins are engine-minor-locked: a plugin built against 5.4 will not load in 5.5. Build separately per minor version you want to ship.

---

## Run automation tests (Gauntlet)

For editor-side automation:

```
.uat RunUnreal -- ^
  -project=MyProject ^
  -test=UE.EditorAutomation -RunTest="Filter:Smoke" ^
  -build=editor -platform=Win64 -configuration=Development ^
  -ReportExportPath="<output>\AutoReport" ^
  -WriteTestResultsForHorde ^
  -MaxDuration=900 -unattended -nullrhi -CrashForUAT
```

For tests against a packaged client (the real CI gate):

```
.uat RunUnreal -- ^
  -project=MyProject ^
  -test=UE.TargetAutomation -RunTest="Project.Smoke" ^
  -build="<archived-build-path>\WindowsClient" ^
  -platform=Win64 -configuration=Shipping ^
  -ReportExportPath="<output>\TestReport" ^
  -WriteTestResultsForHorde ^
  -MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT
```

**Filter syntax:**
- `Filter:Smoke` — all tests with `EAutomationTestFlags::SmokeFilter`.
- `Project.Combat` — substring match on test name.
- `^Project.Combat$` — anchored exact match.
- `Group:<name>` — expand from ini Groups.

**Report output:** JSON at `<ReportExportPath>/index.json` + HTML. **No native JUnit** — post-process the JSON if downstream needs JUnit.

---

## Author a new ushell verb

Drop into `$USERPROFILE/.ushell/channels/mychan/`:

`describe.flow.py`:

```python
import flow.describe
hello = flow.describe.Command()
hello.source("cmds/hello.py", "Hello")
hello.invoke("mychan", "hello")
channel = flow.describe.Channel()
channel.parent("unreal.core")
channel.version("1")
```

`cmds/hello.py`:

```python
import unrealcmd
class Hello(unrealcmd.Cmd):
    """Says hello and prints the active project."""
    name = unrealcmd.Arg("world", "Who to greet")
    def main(self):
        ue = self.get_unreal_context()
        project_name = ue.get_project().get_name() if ue.get_project() else "(no project)"
        print(f"Hello {self.args.name} — active project is {project_name}")
        return 0
```

Then:

```
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .mychan hello Aaron"
```

Expected: `Hello Aaron — active project is MyProject`.

For a real commandlet wrapper (e.g. `.mychan resave <dir>` running ResavePackages), see `reference/channel-authoring.md` — copy-paste-ready.

---

## Common combinations

| Goal | Recipe |
|---|---|
| "Get me a working editor" | `.p4 sync && .build editor && .run editor` |
| "Trace the game at this CL on PS5" | The S2 DAG above (with `.zen snapshot` fast-path) |
| "Find the bad CL" | `.p4 bisect <good> <bad> -- bisect.bat` |
| "Reproduce under debugger" | `.sln open && .run editor --attach` |
| "Ship for Win64" | `.uat BuildCookRun -- ... -clientconfig=Shipping` (CI baseline) |
| "Test the staged client" | `.uat RunUnreal -- -test=UE.TargetAutomation -RunTest=...` |
| "Package my plugin" | `.uat BuildPlugin -- -Plugin= -Package= -TargetPlatforms=...` |
| "Run a commandlet" | `.run commandlet <Name> -- <args>` |
| "Add a custom verb" | drop into `$USERPROFILE/.ushell/channels/<mychan>/` |
| "Clean disk space" | `.p4 clean --dryrun` then `.p4 clean` |

---

## When things go wrong

`reference/troubleshooting.md` is symptom-keyed. Common ones:

- `Unable to establish an Unreal context` — relaunch with `--project=` or run `.project <path>` first.
- `Client 'X' is not a stream` — `.p4 switch`/`.p4 mergedown` need stream clients.
- `BuildPlugin tries Android/iOS/etc.` — pass `-TargetPlatforms=` explicitly.
- `BCR archive directory empty` — Project Settings StagingDirectory is ignored; pass `-stagingdirectory=` and `-archivedirectory=` on the CLI.
- `RunUAT: not found` from inside `.uat` — partial sync, run `.p4 sync --all`.

For anything not listed, check `.info` first to confirm context, then the relevant `reference/*.md` file.

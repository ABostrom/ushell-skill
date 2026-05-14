# GREEN scenarios with rubric

The same seven prompts from `tests/baseline.md`, re-dispatched to subagents **with the skill loaded**. Each scenario passes only if the agent hits **every** bullet in its GREEN expectation. Score `n/7`; below 7/7 ⇒ REFACTOR.

The skill is "loaded" by including the skill content tree at `E:\Work\ushell-skill\skills\ushell\` in the subagent's prompt context. Subagents are instructed to read `SKILL.md` first, then load reference files via its "Load reference when…" pointers as needed.

## S1. Build the editor — GREEN expectation

Agent must:
1. Detect ushell at `E:\UE_5.7\Engine\Extras\ushell\ushell.bat`.
2. Invoke non-interactively: `cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .build editor"`.
3. NOT call `RunUAT.bat`, `Build.bat`, `UnrealBuildTool.exe`, or `GenerateProjectFiles.bat` directly.

**Pass if:** ushell detected AND `.build editor` invoked through `cmd /d /s /c "call <ushell.bat>"`.

## S2. Insights trace at CL 1234567 on PS5 — GREEN expectation

Agent must walk a DAG approximating `reference/workflows.md` §1:
1. Plan the chain by working backwards (terminal is `.run game ps5 --trace`).
2. Check / propose `.p4 sync 1234567`.
3. Check / propose `.build editor` (precondition for cook).
4. Check / propose `.build game ps5`.
5. **Mention `.zen snapshot list game ps5`** — explicitly consider the snapshot fast-path.
6. If snapshot available → `.zen snapshot get game ps5 1234567`. Else → `.cook game ps5`.
7. Check / propose `.stage game ps5 auto`.
8. Terminal: `.run game ps5 --trace=default,gpu -- <args> [-tracehost=<host>]`.
9. Open the trace: `.perf insights latest` (or by path).

**Pass if:** at least 7 of the 9 steps appear in order AND the agent mentions skip-conditions (file checks / `.zen snapshot list`) OR uses `--trace=default,gpu` correctly (NOT inventing trace channel names).

## S3. Bisect editor crash 1234000 → bad — GREEN expectation

Agent must:
1. Identify `.p4 bisect` as the command (NOT manual binary search).
2. Write a `build-and-run.bat` returning 0/80/90 per the bisect protocol — must include both:
   - `if errorlevel 1 exit 90` after `.build editor` (failed-build).
   - `if errorlevel 1 exit 80` after `.run editor` (bad/crash).
3. Invoke `.p4 bisect 1234000 <bad> -- build-and-run.bat`.

**Pass if:** all three bullets present AND no mention of manual log₂(N) iteration as the recommended path.

## S4. Author `.mychan resave` — GREEN expectation

Agent must create:
1. `channels/mychan/describe.flow.py` (NOT `__init__.py`) registering:
   - `flow.describe.Channel().parent("unreal.core").version("1")`.
   - `flow.describe.Command().source("cmds/resave.py", "Resave").invoke("mychan", "resave")`.
2. `channels/mychan/cmds/resave.py` subclassing `unrealcmd.Cmd` or `unrealcmd.MultiPlatformCmd` with:
   - `packagedir = unrealcmd.Arg(str, "...")` positional.
   - Plus optional flags / extra args via `unrealcmd.Arg([str], "...")` many-arg.
3. Implementation that:
   - Calls `self.get_unreal_context()` and resolves project / editor target.
   - Either: (a) shells out to `subprocess.run(("_run", "commandlet", "ResavePackages", "--", ...))`, OR (b) resolves editor binary via `target.get_build(variant).get_binary_path()` and swaps `.exe → -Cmd.exe`.
   - For approach (b): passes `(project.get_path(), "-run=ResavePackages", "-PackageDir=" + self.args.packagedir, "-unattended", "-stdout", ...)` as args.
   - Pipes any forwarded args through `unreal.cmdline.read_ueified(...)` if approach (b) and forwarded args exist.
4. Places the channel in `$USERPROFILE/.ushell/channels/mychan/` (or another documented location).

**Pass if:** at least 3 of the 4 bullets present AND the file is named `describe.flow.py` (NOT `__init__.py`) AND the path uses lowercase `channels/`.

## S5. Context recovery — GREEN expectation

Agent must:
1. Recognise the symptom matches the `Unable to establish an Unreal context` entry in `reference/troubleshooting.md`.
2. Identify the cause: noticeboard `"uproject"` key empty for this `FLOW_SID`.
3. Recover by either:
   - Relaunching: `cmd.exe /d /s /c "call <ushell.bat> --project=E:\Work\MyProject\MyProject.uproject && .cook game ps5"`, OR
   - From an existing session: `.project E:\Work\MyProject\MyProject.uproject` then retry `.cook game ps5`.
4. NOT delete `Saved/`, NOT edit `.uproject`, NOT invent new ushell verbs (`.engine`, etc.).

**Pass if:** all four bullets present AND the recovery path uses real ushell verbs only.

## S6. Compositional Insights trace with PlayerStart + LLM — GREEN expectation

Agent must:
1. Walk the standard Insights DAG (cf. S2) for `win64` game.
2. Consult `reference/unreal-args.md`:
   - **§2 for map URL grammar: `<MapName>#<Portal>` (NOT `?StartPoint=` or `?PlayerStartTag=`).**
   - §3 for trace channels: `default,memory,memtag,gpu` is valid.
   - §13 for LLM: `-llm -llm.AutoReportMemory`.
3. Compose: `.run game win64 --trace=default,memory,memtag,gpu -- /Game/Maps/BossArena#MainStart -llm -llm.AutoReportMemory -traceFile=Saved/Profiling/Traces/Boss.utrace -unattended -stdout`.
4. `.perf insights Saved/Profiling/Traces/Boss.utrace`.

**Pass if:** `#MainStart` form used (NOT `?StartPoint=MainStart` or `?PlayerStartTag=MainStart`) AND `-llm` switches present AND no invented flags (`-trace-file=`, `-llmtrace`, etc.) appear.

## S7. Shipping build via UAT + Gauntlet smoke — GREEN expectation

Agent must:
1. Build the BCR invocation from `reference/uat.md` §2.6 + §6.2 with these modifications:
   - `-target=MyProject+MyProjectServer`.
   - `-platform=Win64 -serverplatform=Linux`.
   - `-clientconfig=Shipping -serverconfig=Shipping`.
   - `-build -cook -stage -pak -iostore -compressed -package -archive`.
   - `-archivedirectory="D:\Builds\MyProject\%BUILDVER%"`.
   - `-encryptinifiles -signpak [-signpakid=<id>] -cryptokeys="D:\Keys\MyProject.keychain"` (NOT just `-sign`).
   - CI flags: `-buildmachine -CrashForUAT -NoCodeSign -unattended -nullrhi -nop4 -utf8output -stdlog`.
2. Wrap as `.uat BuildCookRun -- <BCR args>` (NOT raw `RunUAT.bat`).
3. Build the Gauntlet invocation from `reference/uat.md` §4.9:
   - `.uat RunUnreal -- -test=UE.TargetAutomation -RunTest="Project.Smoke"`.
   - `-build="D:\Builds\MyProject\%BUILDVER%\WindowsClient"`.
   - `-platform=Win64 -configuration=Shipping`.
   - `-ReportExportPath="D:\Builds\MyProject\%BUILDVER%\TestReport"`.
   - `-WriteTestResultsForHorde`.
   - `-MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT`.
4. NOT use `-RunAutomationTest=` under BCR (fragile).
5. NOT use `-sign` on its own (use `-signpak`/`-signpakid=`/`-cryptokeys=`).
6. NOT use `UnrealEditor-Cmd.exe -ExecCmds="Automation RunTests ..."` as the primary testing approach (it works but is the fallback; Gauntlet `RunUnreal -test=UE.TargetAutomation` is canonical for packaged-target).
7. Mention the JUnit caveat (post-process `index.json` if JUnit is needed downstream).

**Pass if:** at least 5 of the 7 bullets present AND `-buildmachine` is included AND `-signpak`/`-cryptokeys=` style signing (not `-sign`) AND `.uat RunUnreal -- -test=UE.TargetAutomation` for tests.

---

## S8. Plugin packaging — GREEN expectation

Agent must:
1. Use `.uat BuildPlugin -- ...` (NOT raw `RunUAT.bat BuildPlugin`).
2. Pass `-Plugin=E:\Work\MyProject\Plugins\MyPlugin\MyPlugin.uplugin` and `-Package=D:\Out\MyPlugin`.
3. **Pass `-TargetPlatforms=Win64+Linux`** (the critical "since 4.25 BuildPlugin builds every detected SDK" gotcha).
4. Include `-Rocket -StrictIncludes` for Marketplace grade.
5. Mention that binary plugins are engine-minor-locked (5.4 ≠ 5.5).

**Pass if:** at least 4 of 5 bullets present AND `-TargetPlatforms=` is explicit.

## S9. BuildGraph nightly CI script — GREEN expectation

Agent must produce a BuildGraph XML at `E:\Work\MyProject\Build\Nightly.xml` containing:
1. `<BuildGraph>` root.
2. `<Property>` or `<Option>` for project path + output dir + build version.
3. At least one `<Agent>` block (ideally one per cook platform — Win64 + Linux).
4. `<Node Name="Sync">` with `<Sync>` task.
5. `<Node Name="Build Editor"...>` with `<Compile Target="...Editor" Platform="Win64" Configuration="Development"/>`.
6. `<Node Name="Cook Win64"...>` and `<Node Name="Cook Linux"...>` — separately, in parallel agents.
7. `<Node Name="Archive..."...>` with `<Copy>` or `<Zip>` to `$(BuildVersion)` path.
8. `<HordeCreateReport>` for Horde dashboard upload.
9. Invocation line: `.uat BuildGraph -- -script=E:\Work\MyProject\Build\Nightly.xml -target=<top-node>`.

**Pass if:** at least 6 of 9 bullets present AND uses ushell `.uat BuildGraph` to invoke (not raw RunUAT).

## S10. Cherrypick hotfix — GREEN expectation

Agent must:
1. Identify `.p4 cherrypick <CL>` as the canonical command.
2. Invoke through ushell: `cmd.exe /d /s /c "call <ushell.bat> --project=... && .p4 cherrypick 1234567"`.
3. Be aware that cross-stream cherrypick clears integration records (the "edigrate" step) and surface that.
4. For "separate review for unresolved files" — either mention `.p4 mergedown`'s two-CL behaviour (it does the split automatically) OR explain `.p4 cherrypick`'s `--saferesolve` / `--noresolve` flag for manual resolve.

**Pass if:** at least 3 of 4 bullets present AND `.p4 cherrypick` invoked through ushell (not raw `p4 integrate`).

## S11. WorldPartitionBuilder — GREEN expectation

Agent must:
1. Use `.run commandlet WorldPartitionBuilder` (NOT raw editor `-Cmd.exe`).
2. Pass `/Game/Maps/OpenWorld` as the positional map argument after `-- `.
3. Pass `-Builder=Minimap` (the specific Builder type).
4. Invoke through ushell with `--project=` and the non-interactive form.

**Pass if:** all 4 bullets present AND `.run commandlet` is the entry (not `.uat` or raw `UnrealEditor-Cmd.exe`).

## S12. Cooked Editor distribution — GREEN expectation

Agent must:
1. Use `.uat BuildCookRun -- ...` (NOT raw `RunUAT.bat`).
2. Pass `-target=MyProjectCookedEditor` or `-target=<X>CookedEditor` plus `-CookedEditor` flag.
3. `-platform=Win64 -clientconfig=Development`.
4. `-build -cook -stage -archive -archivedirectory=D:\Out\MyProjectCookedEditor`.
5. Mention that this is a niche workflow (thin-client artists) and that the resulting binary is a Cooked Editor — not standard.

**Pass if:** at least 4 of 5 bullets present AND `-CookedEditor` flag appears.

## S13. ODSC shader server — GREEN expectation

Agent must:
1. Use `.cook odsc client win64` (NOT raw `.cook game win64`).
2. Note that the command runs the editor commandlet with `-odsc -cookonthefly` (per commands.md `.cook odsc *`).
3. Explain that the cooked client launches with `-odschost=<server-ip>` to connect.
4. Suggest running `.info` (or local PowerShell) to discover the server's IP.

**Pass if:** at least 3 of 4 bullets present AND `.cook odsc client` is used (not `.cook game`).

## S14. Shipping build on installed engine — GREEN expectation

Agent must:
1. Detect ushell at `E:\UE_5.7\Engine\Extras\ushell\ushell.bat` (yes, it's present).
2. **ALSO** detect the installed-build state — explicitly call out `E:\UE_5.7\Engine\Build\InstalledBuild.txt` and/or the absence of `BuildUAT.bat` as evidence.
3. Reason about why `.uat BuildCookRun` would fail here — point at ushell's `cmds/uat.py:108` `BuildUAT` hardcode (or just at the carve-out in iron rule #1 / DAG #13b).
4. NOT attempt `.uat BuildCookRun` blindly.
5. Fall back to `RunUAT.bat` directly (per the iron rule #1 carve-out and DAG #13b), with at minimum:
   - `E:\UE_5.7\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun` as the entry.
   - `-ScriptsForProject=E:\Work\LyraStarterGame\LyraStarterGame.uproject`.
   - `-project=E:\Work\LyraStarterGame\LyraStarterGame.uproject`.
   - `-target=LyraGame -platform=Win64 -clientconfig=Shipping`.
   - `-build -cook -stage -pak -iostore -compressed -package -archive`.
   - `-archivedirectory=E:\Work\LyraStarterGame\LocalBuilds\Win64Shipping`.
   - `-prereqs -nodebuginfo -utf8output -unattended -nop4`.
6. NOT silently fall back without explaining that this is the *documented exception* under iron rule #1 (i.e., flag the carve-out, don't act like ushell is unnecessary).
7. NOT recommend `.stage` / `.deploy` / `.perf test *` as workarounds — those wrap UAT internally and fail the same way.

**Pass if:** at least 5 of 7 bullets present AND `RunUAT.bat` invoked directly AND `.uat` was *not* attempted as the primary path AND the agent acknowledges the iron-rule carve-out (vs. silently using a raw tool).

---

## Scoring

| Scenario | Bullets met | Pass? |
|---|---|---|
| S1 | x/3 | yes/no |
| S2 | x/9 (≥7 to pass) | yes/no |
| S3 | x/3 | yes/no |
| S4 | x/4 (≥3 to pass) | yes/no |
| S5 | x/4 | yes/no |
| S6 | x/4 | yes/no |
| S7 | x/7 (≥5 to pass) | yes/no |
| S8 | x/5 (≥4 to pass) | yes/no |
| S9 | x/9 (≥6 to pass) | yes/no |
| S10 | x/4 (≥3 to pass) | yes/no |
| S11 | x/4 | yes/no |
| S12 | x/5 (≥4 to pass) | yes/no |
| S13 | x/4 (≥3 to pass) | yes/no |
| S14 | x/7 (≥5 to pass) | yes/no |
| **Total** | n/14 scenarios passing | |

Below 14/14 ⇒ REFACTOR the failing scenarios' loopholes in the skill content. Re-dispatch fresh subagents for the failing scenarios.

The skill is "done" when all fourteen pass.

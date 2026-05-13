# Before & After: the ushell skill in action

This is a gallery of the **same prompts** asked twice — once to a Claude subagent with **no skill loaded** (RED, baseline), once with the skill loaded (GREEN). Captured during the v1.0 and v1.1 verification passes on 2026-05-13.

Each entry shows:
- The verbatim user prompt.
- A summary of what baseline Claude produced.
- A summary of what the skill-loaded Claude produced.
- The exact RED→GREEN diff that matters.

For full per-scenario rubrics see `tests/with-skill.md`. For verbatim transcripts (gitignored) see `tests/notes.md`.

---

## S1 — Build the editor

> I'm in `E:\Work\MyProject` (a UE 5.7 project with engine at `E:\UE_5.7`). Build the editor.

**Baseline (RED):** Reached straight for `Engine\Build\BatchFiles\Build.bat -projectfiles ...` then `Build.bat MyProjectEditor Win64 Development -Project=... -WaitMutex -FromMsBuild`. Reasoning: *"this is the canonical UBT invocation."* Never mentioned ushell.

**With skill (GREEN):** Detected `Engine/Extras/ushell/ushell.bat`. Produced one line:

```powershell
cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\MyProject\MyProject.uproject && .build editor --nosummary"
```

Reasoning: walked the iron rules, noted active project must be set on `$FLOW_SID`, used `--nosummary` for clean exit-code parsing.

**Diff:** Two-step raw UBT invocation → one ushell command that handles project context, target resolution, and pretty-printing for free.

---

## S2 — Insights trace at CL on PS5

> I'm in a UE 5.7 Perforce branch at `E:\Stream\MyProj`. Get me an Insights trace of the game at CL 1234567 on PS5, channels default and gpu. Save the trace and open it.

**Baseline (RED):** Linear chain: `p4 sync`, then `Build.bat` twice (editor + PS5 game), then `RunUAT.bat BuildCookRun -build -cook -stage -package -deploy -run -device=PS5@... -cmdline="-trace=default,gpu -tracehost=..."`. **Never checked if a pre-cooked snapshot existed** at that CL; never considered the goal-directed planning angle.

**With skill (GREEN):** Walked the DAG from `reference/workflows.md` §1 backwards from terminal command:

```
.p4 sync 1234567 --nosummary
.build editor --nosummary
.build game PS5 --nosummary
.cook game PS5 --nosummary           # OR .zen snapshot get game PS5 1234567 (faster if available)
.stage game PS5 auto --nosummary
.run game PS5 --trace=default,gpu
.perf insights latest
```

Explicitly described the skip-conditions for each step: check `.target` receipt, check `Saved/Cooked/`, run `.zen snapshot list game PS5` to see if a snapshot path exists.

**Diff:** Linear "do everything" pipeline → DAG with explicit precondition skip-checks. The `.zen snapshot get` fast-path was invisible to baseline — it can be ~50× faster than a fresh cook.

---

## S3 — Bisect editor crash

> The editor for MyProject builds but crashes on startup at the current CL. Last known good was CL 1234000. Find the change that broke it.

**Baseline (RED):** *"P4 has no built-in bisect like git, so I drive it manually"* — proposed `p4 changes` to list CLs, then `p4 sync @<midpoint>` + `Build.bat` + manual launch + mark good/bad, repeat. **`log₂(N)` manual iterations**, no exit-code protocol, no script.

**With skill (GREEN):** Identified `.p4 bisect <good> <bad> -- <script>` as the canonical command. Wrote the script directly from `reference/workflows.md` §4:

```bat
@echo off
call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=<UPROJECT>
.build editor --nosummary
if errorlevel 1 exit 90              :: failed-build (ushell treats as 'ugly')
.run editor -- -nullrhi -unattended -stdout -log -ExecCmds="Quit"
if errorlevel 1 exit 80              :: bad
exit 0                                :: good
```

Then `.p4 bisect 1234000 <bad> -- E:\Work\bisect-editor.bat` runs the whole thing unattended.

**Diff:** ~10 manual cycles for log₂(1000)=10 CLs over an afternoon → one command, ushell drives the protocol, runs unattended.

---

## S4 — Author `.mychan resave` channel

> Add a `.mychan resave <dir>` command to my ushell that runs the ResavePackages commandlet on the directory I pass. ushell is at `E:\UE_5.7\Engine\Extras\ushell\`.

**Baseline (RED):** Hedged with uncertainty — *"I'd verify against an existing command before committing to this"*. Proposed `Channels/mychan/__init__.py` + `resave.py` (wrong filename, wrong case). Hand-built the editor binary path (`engine.get_dir() / "Binaries/Win64/UnrealEditor-Cmd.exe"`) instead of using the target/build API. Forgot `unreal.cmdline.read_ueified()` for arg forwarding.

**With skill (GREEN):** Created `channels/mychan/describe.flow.py` (lowercase, correct filename) + `cmds/resave.py`. Subclassed `unrealcmd.Cmd`. Used Pattern A (`subprocess.run(("_run", "commandlet", "ResavePackages", ...))`) per the skill's explicit recommendation — *"use Pattern A by default; it gets `--attach` debugger support and the canonical UE log pretty-printer for free"*. Piped forwarded args through `unreal.cmdline.read_ueified()`. Suggested per-user install at `$USERPROFILE/.ushell/channels/mychan/`.

**Diff:** Three wrong details (`__init__.py`, capital `Channels/`, hand-built path) → idiomatic channel that inherits the framework's debugger + log-printer flow.

---

## S5 — Recover from "Unable to establish an Unreal context"

> I ran `.cook game ps5` from ushell and it failed with `Unable to establish an Unreal context from directory ...`. The project is at `E:\Work\MyProject\MyProject.uproject`. Fix it.

**Baseline (RED):** Correctly diagnosed (`cwd has no .uproject upward, project not bound`). Recommended `.project E:\Work\MyProject\MyProject.uproject` (✓ real command). But also invented `.engine E:\UE_5.7` (doesn't exist) and `.platform list` (wrong form).

**With skill (GREEN):** Matched the symptom against `reference/troubleshooting.md` directly. Diagnosed the noticeboard / `FLOW_SID` mechanism. Two valid fixes:
- Relaunch: `cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .cook game ps5"`
- From existing session: `.project <path>` then retry.

Did NOT invent neighbour commands.

**Diff:** Right answer + invented commands → right answer with cited troubleshooting entry and zero hallucinations.

---

## S6 — Compositional trace (the headline result)

> Capture an Insights trace of the game on Windows, booting into `/Game/Maps/BossArena` and spawning at the `PlayerStart` tagged `MainStart`, with LLM memory tracking on, channels `default,memory,memtag,gpu`, writing the trace to `Saved/Profiling/Traces/Boss.utrace`. Then open it. Project is at `E:\Work\MyProject\MyProject.uproject`.

**Baseline (RED):** Confidently produced `/Game/Maps/BossArena?PlayerStartTag=MainStart`. Justification: *"the standard mechanism is the `PlayerStartTag` URL option ... `AGameModeBase::ChoosePlayerStart_Implementation` honors this."*

That switch **does not exist**. `?PlayerStartTag=` is a hallucination.

**With skill (GREEN):** Consulted `reference/unreal-args.md` §2 (the user-authored seed inlined verbatim, with FURL grammar + call-stack citations). Produced:

```powershell
.run game win64 --trace=default,memory,memtag,gpu -- ^
    /Game/Maps/BossArena#MainStart ^
    -llm -llm.AutoReportMemory ^
    -traceFile=Saved/Profiling/Traces/Boss.utrace ^
    -unattended -stdout
.perf insights Saved/Profiling/Traces/Boss.utrace
```

**`#MainStart`** is the correct URL Portal segment. The agent's reasoning even cited the file:line in `unreal-args.md` it came from.

**Diff:** Confidently-wrong fabricated flag → correct grammar with source-code provenance. **This is the test the skill was designed to win**, and it does.

---

## S7 — Shipping build + Gauntlet smoke

> Make me a shipping-grade packaged build of `MyProject` for Win64 client and Linux dedicated server in one go, with IoStore + compression, encrypted-ini paks (keychain at `D:\Keys\MyProject.keychain`), archived to `D:\Builds\MyProject\%BUILDVER%\`. This will run in CI so it must not pop dialogs or hang on crashes. Then run `Project.Smoke` automation tests against the staged Win64 client and write a Horde-readable report at `D:\Builds\MyProject\%BUILDVER%\TestReport\`.

**Baseline (RED):** Got many things right — `-iostore -compressed`, `-cryptokeys=<path>`, `-buildmachine -CrashForUAT`. But:
- Used `-sign` (not real) instead of `-signpak -signpakid=`.
- Used `UnrealEditor-Cmd.exe -ExecCmds="Automation RunTests Project.Smoke+; Quit"` for the test step (the fragile editor-cmd path) instead of Gauntlet `RunUnreal -test=UE.TargetAutomation`.
- Invoked through raw `RunUAT.bat`, not `.uat`.

**With skill (GREEN):** Built directly from `reference/uat.md` §2.6 + §4.9 templates. Split into two `.uat BuildCookRun --` calls (client + server, per uat.md §2.4 recommendation). Used `-encryptinifiles -signpak -cryptokeys=<keychain>` (the real signing trio). Used `.uat RunUnreal -- -test=UE.TargetAutomation -RunTest="Project.Smoke"` against the archived client with `-WriteTestResultsForHorde`. Explicitly warned the user about the empty-pak trap if Zen Store is enabled in Project Settings.

**Diff:** Subtle wrong flag (`-sign`) + fragile test path → canonical Marketplace-grade encrypted signing trio + Gauntlet packaged-target smoke that exits non-zero correctly.

---

## S8 — Plugin packaging for Marketplace

> Package `E:\Work\MyProject\Plugins\MyPlugin\MyPlugin.uplugin` for Marketplace submission. Target Win64 + Linux. Output to `D:\Out\MyPlugin\`.

**Baseline (RED):** Reached for raw `RunUAT.bat BuildPlugin`. Did include `-TargetPlatforms=Win64+Linux` (which is the gotcha-killer flag), so this baseline was a partial win for the agent's existing knowledge.

**With skill (GREEN):** `.uat BuildPlugin -- -Plugin=... -Package=D:\Out\MyPlugin -TargetPlatforms=Win64+Linux -Rocket -StrictIncludes -unattended -nop4 -buildmachine -CrashForUAT -NoCodeSign -utf8output -stdlog`. Cited the *"since 4.25 BuildPlugin builds every detected SDK by default"* gotcha from `uat.md` §3.1 by name and explained why `-TargetPlatforms=` is non-optional.

**Diff:** Right invocation, raw entry point → right invocation through ushell with provenance.

---

## S9 — BuildGraph nightly script

> Write me a BuildGraph script that, run nightly, syncs the engine + project, builds the editor for Win64, cooks Win64 + Linux in parallel agents, stages each, archives to `D:\Nightly\$BUILDVER\<Platform>\`, and produces a Horde report.

**Baseline (RED):** Produced a passable BuildGraph script with multiple agents, `P4-Sync`, `Compile`, `Cook`, `Spawn` tasks, `Label`/`Badge` elements. Invoked via `RunUAT.bat BuildGraph -Script=... -Target=...` directly.

**With skill (GREEN):** Produced a similar (slightly better-structured) BuildGraph script with `<Option>` for `BuildVersion`/`ArchiveRoot`/`SyncCL`/`SkipSync`, derived `<Property>` for paths, four `<Agent>` blocks (Sync / Win64 / Linux / Report), `<Command Name="BuildCookRun">` for cook+stage+archive in one shot (avoiding cross-agent storage transfer of cooked data), and `<HordeCreateReport>` for the dashboard. Invoked via `.uat BuildGraph --`. Explicitly noted the `-project=` non-inheritance gotcha and inlined the CI baseline flags as a `$(CiFlags)` reused property.

**Diff:** A working BuildGraph script → a working BuildGraph script grounded in the engine-shipped CookedEditor/LiveLinkHub patterns + the §10 gotchas list.

---

## S10 — Cherrypick hotfix

> I'm on `//depot/Release` and CL 1234567 was submitted to `//depot/Main`. Pull just that CL into our Release stream as a hotfix, with a separate review for any files that don't resolve cleanly.

**Baseline (RED):** Wrote raw `p4 integrate -c CL_A -S //depot/Release -P //depot/Main //depot/Main/...@1234567,@1234567 //depot/Release/...` plus manual `p4 reopen -c CL_B` for the unresolved files. Comprehensive and correct, but raw P4 throughout.

**With skill (GREEN):** Used `.p4 cherrypick 1234567` through ushell. Mentioned the automatic "edigrate" step (clearing integration records when streams are unrelated). Offered `--saferesolve` for the two-CL split (matching the user's "separate review" requirement). Cited `commands.md` `.p4 cherrypick` + `workflows.md` §9 by file:line.

**Diff:** Manual stream-aware integrate dance → one ushell verb that handles branchspec generation, integration-record clearing, and post-resolve splitting.

---

## S11 — WorldPartitionBuilder

> Build the minimap for `/Game/Maps/OpenWorld` via WorldPartitionBuilder.

**Baseline (RED):** `UnrealEditor-Cmd.exe MyProject.uproject -run=WorldPartitionBuilderCommandlet /Game/Maps/OpenWorld -Builder=WorldPartitionMiniMapBuilder -AllowCommandletRendering -unattended -nop4 -stdout -FullStdOutLogOutput`. Direct commandlet invocation, lots of correct flags. Used the full builder class name `WorldPartitionMiniMapBuilder`.

**With skill (GREEN):** `.run commandlet WorldPartitionBuilder -- /Game/Maps/OpenWorld -Builder=Minimap` per `unreal-args.md` §11. Cleaner: ushell wraps the `-Cmd.exe` swap + project injection + `-run=` prefix. The `-Builder=Minimap` short form (vs the full class name `WorldPartitionMiniMapBuilder`) is the documented BuildGraph/builder API.

**Diff:** Raw `UnrealEditor-Cmd.exe` invocation → ushell verb that's also discoverable via tab-completion next time.

---

## S12 — Cooked Editor distribution

> Build a Cooked Editor distribution of `MyProject` for thin-client artists who shouldn't need a full source build.

**Baseline (RED):** Started with `BuildCookRun`, then mid-thought reconsidered when they noticed `CookedEditor.Automation.cs` exists, and ended up recommending the user grep the engine source to find the right UAT command. Honest about uncertainty, but unable to commit to a single answer.

**With skill (GREEN):** Drew directly from `uat.md` §2.7 recipe #13. Produced:

```
.uat BuildCookRun -- -target=MyProjectCookedEditor -CookedEditor
                     -platform=Win64 -clientconfig=Development
                     -build -cook -stage -pak -iostore -compressed
                     -archive -stagingdirectory=D:\Out\MyProjectCookedEditor\Staged
                     -archivedirectory=D:\Out\MyProjectCookedEditor
                     -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

Cited the recipe + flagged the *"requires a `*CookedEditor.Target.cs` to exist in the project"* precondition as a clarifying question.

**Diff:** Uncertainty (and a research detour) → confident invocation with the precondition surfaced.

---

## S13 — ODSC shader server

> Start an ODSC server for the Win64 cooked client of `MyProject`. Then tell me how to point a running cooked client at it.

**Baseline (RED):** Expressed genuine uncertainty about `-odschost=` vs `-filehostip=` (both have historically been used), and offered to grep the engine source rather than guess. Produced a partial command and warned the user.

**With skill (GREEN):** `.cook odsc client win64` from `commands.md`. Confirmed the runtime arg is `-odschost=<server-ip>` per the same entry. Suggested `ipconfig` to discover the IP. Noted that the connect is at startup (per ODSC's design), so a "running" client must be relaunched.

**Diff:** Uncertain about flag names (good!) → confident with provenance, no need to grep engine source.

---

## What the gallery shows

Three patterns recur across every scenario:

1. **Baseline reaches for raw tools.** `Build.bat`, `RunUAT.bat`, `UnrealEditor-Cmd.exe`, `p4 integrate`. The skill consistently routes everything through `.<verb>` wrappers, which then handle project context, env setup, and (for build/cook) pretty-printing automatically.

2. **Baseline is uncertain about specific flags or invents them.** `?PlayerStartTag=`, `-sign`, `.engine`, `__init__.py` — these aren't real. The skill never invents because every flag comes from a cited source: `unreal-args.md`, `commands.md`, `uat.md`, with file:line references back to engine source where it matters.

3. **Baseline goes linear; the skill walks DAGs.** The most striking example is S2's Insights trace: baseline cooks and stages every time; the skill checks for a pre-built `.zen snapshot` first and skips ~50× of work when one exists.

The skill's strength isn't that it knows more than the baseline — sometimes it knows the same thing. The strength is **provenance + discipline**. Every recommendation traces back to a file, with a citation, in a structure that lets the agent skip work that's already done and stop cleanly when a precondition is unreachable.

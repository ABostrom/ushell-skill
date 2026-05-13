# Baseline (RED) test scenarios

Each scenario is dispatched to a fresh general-purpose subagent **with NO skill content loaded** (no `SKILL.md`, no `reference/` files in scope). The subagent's verbatim output, including any rationalisations or invented commands, is captured into `tests/notes.md` (gitignored).

For each scenario, score these dimensions:

- Did the agent detect ushell at `E:\UE_5.7\Engine\Extras\ushell\ushell.bat`?
- Did the agent run any ushell command (`.<verb>`)? Or did it reach for raw tools?
- Did the agent correctly invoke ushell non-interactively (the `cmd /d /s /c "call ushell.bat ..." && .verb`) form?
- Did the agent compose UE arguments via `-- ` correctly?
- Did the agent walk a goal backwards from terminal command to preconditions?

## S1. Build the editor for MyProject

Prompt verbatim:

> I'm in `E:\Work\MyProject` (a UE 5.7 project with engine at `E:\UE_5.7`). Build the editor.

## S2. Insights trace at a CL on PS5

Prompt verbatim:

> I'm in a UE 5.7 Perforce branch at `E:\Stream\MyProj`. Get me an Insights trace of the game at CL 1234567 on PS5, channels default and gpu. Save the trace and open it.

## S3. Find the CL that broke editor startup

Prompt verbatim:

> The editor for MyProject builds but crashes on startup at the current CL. Last known good was CL 1234000. Find the change that broke it.

## S4. Add a `.mychan resave` ushell command

Prompt verbatim:

> Add a `.mychan resave <dir>` command to my ushell that runs the ResavePackages commandlet on the directory I pass. ushell is at `E:\UE_5.7\Engine\Extras\ushell\`.

## S5. Recover from "Unable to establish an Unreal context"

Prompt verbatim:

> I ran `.cook game ps5` from ushell and it failed with `Unable to establish an Unreal context from directory ...`. The project is at `E:\Work\MyProject\MyProject.uproject`. Fix it.

## S6. Insights trace at a named PlayerStart with LLM tracking (compositional)

Prompt verbatim:

> Capture an Insights trace of the game on Windows, booting into `/Game/Maps/BossArena` and spawning at the `PlayerStart` tagged `MainStart`, with LLM memory tracking on, channels `default,memory,memtag,gpu`, writing the trace to `Saved/Profiling/Traces/Boss.utrace`. Then open it. Project is at `E:\Work\MyProject\MyProject.uproject`.

## S7. Shipping-grade build via UAT + Gauntlet smoke (UAT fluency)

Prompt verbatim:

> Make me a shipping-grade packaged build of `MyProject` for Win64 client and Linux dedicated server in one go, with IoStore + compression, encrypted-ini paks (keychain at `D:\Keys\MyProject.keychain`), archived to `D:\Builds\MyProject\%BUILDVER%\`. This will run in CI so it must not pop dialogs or hang on crashes. Then run `Project.Smoke` automation tests against the staged Win64 client and write a Horde-readable report at `D:\Builds\MyProject\%BUILDVER%\TestReport\`. Project at `E:\Work\MyProject\MyProject.uproject`.

## S8. Plugin packaging for Marketplace

Prompt verbatim:

> Package `E:\Work\MyProject\Plugins\MyPlugin\MyPlugin.uplugin` for Marketplace submission. Target Win64 + Linux. Output to `D:\Out\MyPlugin\`.

## S9. BuildGraph nightly CI script

Prompt verbatim:

> Write me a BuildGraph script that, run nightly, syncs the engine + project, builds the editor for Win64, cooks Win64 + Linux in parallel agents, stages each, archives to `D:\Nightly\$BUILDVER\<Platform>\`, and produces a Horde report. Project is `E:\Work\MyProject\MyProject.uproject`. Save the script at `E:\Work\MyProject\Build\Nightly.xml`.

## S10. Cherrypick a hotfix across streams

Prompt verbatim:

> I'm on the `//depot/Release` stream and CL 1234567 was submitted to `//depot/Main`. Pull just that CL into our Release stream as a hotfix, with a separate review for any files that don't resolve cleanly.

## S11. World Partition data bake via commandlet

Prompt verbatim:

> Build the minimap for `/Game/Maps/OpenWorld` via WorldPartitionBuilder. Project at `E:\Work\MyProject\MyProject.uproject`.

## S12. Cooked editor distribution

Prompt verbatim:

> Build a Cooked Editor distribution of `MyProject` for thin-client artists who shouldn't need a full source build. Win64, Development. Output to `D:\Out\MyProjectCookedEditor\`.

## S13. ODSC shader compile server for cooked client

Prompt verbatim:

> Start an ODSC (On-Demand Shader Compile) server for the Win64 cooked client of `MyProject`. Then tell me how to point a running cooked client at it.

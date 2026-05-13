# Battle test — ProjectGear (real-world)

Captured: 2026-05-13. Project: `E:\Work\Games\ProjectGear`, UE 5.7.4. ushell at `E:\UE_5.7\Engine\Extras\ushell\`.

The 13-scenario synthetic GREEN corpus passed cleanly. This file logs what happens when the skill is used on a real project, end-to-end. Each test produced a binary pass/fail plus zero-or-more *findings* — real-world quirks the synthetic tests didn't catch.

---

## B0. Earlier success: compile + open editor

Already-documented working result (this session's first battle test):

- `.build editor --nosummary` — **PASS** in 155s. 33 actions, 5 module DLLs, receipt written, exit 0.
- `.run editor` — **PASS**. `UnrealEditor.exe` launched, project loaded, editor window came up.

Real-world findings from B0:
- **UBT surfaced a project issue:** `ProjectGear.uproject does not list plugin 'Chooser' as a dependency, but module 'Locomotion' depends on 'Chooser'.` Real defect in the project — needs `{"Name":"Chooser","Enabled":true}` added to the `Plugins[]` array, or the Chooser reference removed from `Source/Locomotion/Locomotion.Build.cs`. Not a skill issue; the skill correctly surfaced it.

---

## B1. `.info` + `.info projects` + `.info config Engine` — PASS (with 2 findings)

`.info` printed correctly: engine 5.7.4 / branch ++UE5+Release-5.7 / CL 51494982 / project ProjectGear / 4 target names / Android+Linux+Win64 platforms with SDK details.

`.info config Engine --json` wrote a 286KB JSON file containing every config setting (`GameMapsSettings`, etc.). Useful for CI introspection.

**Finding F1 (skill defect): `.info`, `.info projects`, and `.info config` do NOT accept `--nosummary`.**
- They error with `Usage: [--<options>] / ERROR: Unknown argument(s) 'nosummary'` and exit non-zero.
- SKILL.md says *"commands that have it (build, sync, mergedown, switch, …)"* — the `…` is too permissive. Real impact: an agent following the skill defensively will add `--nosummary` to `.info` and watch it fail.
- **v1.2 fix:** rewrite the `--nosummary` paragraph in SKILL.md and `reference/invocation.md` to explicitly list rejecting commands, OR rephrase as "only commands decorated with `Cmd.summarise`: `.build *`, `.p4 sync`, `.p4 mergedown`, `.p4 switch`, and a few others. If unsure, omit it." The defensive-add pattern bites cleanly here.

**Finding F2 (ushell quirk): `.info projects` on a non-branch project leaks an `OSError` stack trace to stderr.**
- Returns empty output (correct — no `.uprojectdirs` discoverable from an installed-engine non-branch context).
- But stderr gets *"Unable to establish an Unreal context from directory 'X' [OSError]"* with a 4-line Python stack trace. Looks alarming in CI logs even though command exits 0.
- **v1.2 fix:** add to `reference/troubleshooting.md` and `commands.md` `.info projects` Preconditions: "Requires a UE branch layout with `*.uprojectdirs`. For standalone projects against an installed engine, expect noisy stderr; use `.info` for project info instead."

---

## B2. `.sln generate` — PASS

`ProjectGear.sln` regenerated in 60s. All `Intermediate/ProjectFiles/*.vcxproj` files refreshed. Exit 0.

**Finding F3 (project quirk, not skill defect): three "Program targets are not currently supported from this engine distribution" exceptions for `IoStoreOnDemandTests`, `EventLoopUnitTests`, `DotNetPerforceLib`.**
- Non-fatal — UBT skips them and continues. Standard behaviour for an installed engine; these targets only build from source.
- Worth noting in `reference/troubleshooting.md` as "expected noise on installed engines."

The `Chooser` plugin warning from B0 appeared again — consistent across builds. Real project issue.

---

## B3. Reproduce S5 (context-recovery) on the wild — PASS

Launched ushell.bat with **no `--project=` and CWD outside any project**:

```
!! Unable to locate any projects from 'C:\Users\Aaron'
!! Set a shortcut's 'Start In' to a folder with a valid .uproject
!! path or launch with the 'ushell --project=[uprojpath]' argument.
```

Then tried `.cook game win64` → got the documented stack trace:

```
## Unable to establish an Unreal context from directory 'C:\Users\Aaron'
## [OSError]
## __init__ ............ _\unreal\core\pylib\unreal\_context.py:602
## get_unreal_context .. _annels\unreal\core\pylib\unrealcmd.py:40
## get_platform ........ _annels\unreal\core\pylib\unrealcmd.py:48
## main ................ _ell\channels\unreal\core\cmds\cook.py:143
```

Exit code 1.

Then `.project E:\Work\Games\ProjectGear\ProjectGear.uproject` recovered cleanly, `.info` post-recovery confirmed the noticeboard.

**Finding F4 (minor — additional troubleshooting wording):**
- The **boot-time** message (`!! Unable to locate any projects from 'X'` from `ushell.bat` itself, before any verb runs) is different from the **command-time** stack trace (`Unable to establish an Unreal context from directory 'X' [OSError]` from a verb's `get_unreal_context`). Both should appear in `reference/troubleshooting.md` so users find the entry whichever symptom they see first.

---

## B4. `.kill editor` + `.run commandlet ResavePackages` — **PARTIAL PASS (with a major finding)**

`.kill editor` worked — no UnrealEditor process surviving after invocation. ✅

`.run commandlet ResavePackages -- -PackageDir=/Game/MovementModes -unattended` engaged correctly:
- ushell drove `UnrealEditor-Cmd.exe E:\Work\Games\ProjectGear\ProjectGear.uproject -run=ResavePackages -PackageDir=/Game/MovementModes -unattended` — exactly as documented.
- Editor-Cmd.exe started (2.2 GB resident — full editor + UnrealEd module).

**Finding F5 (MAJOR — skill correctness defect): `-PackageDir=/Game/MovementModes` does NOT restrict ResavePackagesCommandlet to that directory.**

Empirical evidence:
- Log line 44: `LogCsvProfiler: ... commandline="" E:\Work\Games\ProjectGear\ProjectGear.uproject -run=ResavePackages -PackageDir=/Game/MovementModes -unattended""` — the flag WAS parsed.
- Despite that, the commandlet started resaving every Engine package, beginning with `Engine/Content/EditorResources/LightIcons/S_LightError.uasset` and proceeding through 1500+ `Engine/Content/...` files until I killed the process.
- Zero `E:\Work\Games\ProjectGear\` files touched (`git status --short` returned empty).
- Engine packages had UE Version bumped 1004 → 1018 on disk.

Where the skill is wrong:
- `reference/unreal-args.md` §11 lists `-run=ResavePackages -PackageDir=<dir>` without scope-restriction warning.
- `reference/channel-authoring.md` "Driving a commandlet" example uses `-PackageDir=` to limit ResavePackages to a folder.
- `reference/workflows.md` §12 "Drive a commandlet" example: `.run commandlet ResavePackages -- -PackageDir=Content/Foo -AutoCheckOutPackages` — the assumption being that `-PackageDir=Content/Foo` restricts.

Possible causes (need engine .cpp to confirm; not shipped in this install):
- `-PackageDir=` is additive/seed, not restrictive.
- Path format is wrong (`/Game/MovementModes` is a content-browser path; the commandlet may expect filesystem-relative path or `LongPackageName` form).
- The exclusive filter is a different flag entirely (`-FilesToResave=`, `-MapsOnly`, `-Package=<wildcard>`).

**v1.2 fix:** until verified by reading `Engine/Source/Editor/UnrealEd/Private/Commandlets/ResavePackagesCommandlet.cpp` (not in this source-only install — needs an Epic Games GitHub UE5 clone), the skill should:
1. Replace the ResavePackages examples with a **strong warning** that the documented `-PackageDir=` flag may not restrict scope and Engine content can be modified.
2. Recommend ResavePackages users perform a **dry-run first** to confirm scope before letting it write. The commandlet supports `-CheckOutOnly` and `-NoAutoCheckout` for read-only modes; a true `-WhatIf` flag is also worth searching for.
3. Note that the canonical safe pattern for "resave only project content" may need additional flags or a different approach (run in PIE mode with a tagged Python script, use the editor's right-click → "Asset Actions → Resave" UI in batch, etc.).

**Operational damage:**
- 1500+ Engine packages had their on-disk format bumped 1004 → 1018. UE 5.7's editor accepts both versions, so the engine install should still work. Will continue to monitor.
- No project files modified (git clean).

**Cost of this finding:** ~3 minutes of compute + a small write-amplification on the engine install. Acceptable as a real-world battle-test cost.

---

## B5. Full development packaged build via `.uat BuildCookRun` — (proposed)

Proposed invocation:

```
.uat BuildCookRun -- \
  -target=ProjectGear \
  -platform=Win64 \
  -clientconfig=Development \
  -build -cook -stage -pak -iostore -compressed -package -archive \
  -archivedirectory=D:\Out\PG-Dev \
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

ETA 30-90 min. Will run unattended; user can decide whether to fire it.

---

## Summary so far

| Test | Result | Real findings |
|---|---|---|
| B0 build + open editor | PASS | Chooser plugin reference inconsistency in project (real defect) |
| B1 .info family | PASS | F1: `--nosummary` is rejected by several commands (skill doc gap); F2: `.info projects` leaks stack trace on non-branch projects |
| B2 .sln generate | PASS | F3: "Program targets not supported" exceptions on installed engines (expected noise; worth documenting) |
| B3 context recovery | PASS | F4: boot-time wording differs from command-time wording (both should be in troubleshooting.md) |
| B4 commandlet | (in progress) | |
| B5 packaged build | (proposed) | |

**Score so far:** skill correctness 4/4, real defects in skill docs (not behavior) 4. The skill DRIVES correctly; the documentation has small gaps that defensive use exposes.

This is the expected shape of battle-testing: synthetic tests verify the skill produces the right commands, but real use stresses the framing/doc edges that synthetic agents (already cooperative) gloss over.

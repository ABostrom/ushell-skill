# ushell Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code skill that teaches Claude to drive ushell (Epic's CLI for Unreal Engine) end-to-end — usage, channel authoring, UAT/BuildGraph fluency, and goal-directed planning from a stated outcome backwards to a concrete command sequence.

**Architecture:** One skill, layered reference. A small always-loaded `SKILL.md` (~250 words of prose + a quick-reference table) plus eight on-demand reference files under `reference/`. TDD discipline per superpowers:writing-skills: RED scenarios run against subagents *before* any skill content is written, then GREEN scenarios re-run with the skill loaded; the skill is "done" at 7/7 GREEN.

**Tech Stack:** Markdown (skill content). PowerShell + Bash (verification). Git (commits). Python (ushell channels — only relevant for channel-authoring reference). Engine tree at `E:\UE_5.7\Engine\Extras\ushell\` is the citation source.

**Spec:** `docs/superpowers/specs/2026-05-13-ushell-skill-design.md`
**Research seed:** `docs/superpowers/specs/research-notes-uat.md`
**URL-grammar seed:** `ue5-launch-with-spawn-point.md` (root of working tree)
**Working branch:** `feat/skill-implementation` (already checked out)

---

## Phase 0 — Repo prep

### Task 0.1: Create directory skeleton

**Files:**
- Create: `reference/.gitkeep`
- Create: `tests/.gitkeep`

- [ ] **Step 1: Create the empty reference and tests directories**

Run (PowerShell):
```powershell
New-Item -ItemType Directory -Path "E:\Work\ushell-skill\reference" -Force | Out-Null
New-Item -ItemType Directory -Path "E:\Work\ushell-skill\tests"     -Force | Out-Null
New-Item -ItemType File -Path "E:\Work\ushell-skill\reference\.gitkeep" | Out-Null
New-Item -ItemType File -Path "E:\Work\ushell-skill\tests\.gitkeep"     | Out-Null
```

- [ ] **Step 2: Verify directories exist**

Run: `Get-ChildItem -Force E:\Work\ushell-skill\ | Select-Object Name`
Expected: `reference` and `tests` directories appear alongside `.claude`, `.git`, `.gitignore`, `CLAUDE.md`, `README.md`, `docs`, `ue5-launch-with-spawn-point.md`.

- [ ] **Step 3: Commit**

```bash
git add reference/.gitkeep tests/.gitkeep
git commit -m "chore: scaffold reference/ and tests/ directories"
```

---

## Phase 1 — RED baseline tests (write first, no skill content yet)

The Iron Law of writing-skills: **no skill content before failing tests**. This phase produces `tests/baseline.md` and dispatches subagents to capture verbatim baseline behaviour into `tests/notes.md`. `notes.md` is gitignored — only the prompts in `baseline.md` and the eventual summary in `with-skill.md` are tracked.

### Task 1.1: Write tests/baseline.md with seven RED scenarios

**Files:**
- Create: `tests/baseline.md`

- [ ] **Step 1: Write baseline.md**

```markdown
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
```

- [ ] **Step 2: Verify the file**

Run: `Get-Content E:\Work\ushell-skill\tests\baseline.md -TotalCount 5`
Expected: file starts with `# Baseline (RED) test scenarios`.

- [ ] **Step 3: Commit**

```bash
git add tests/baseline.md
git commit -m "test(RED): seven baseline scenarios for ushell skill

Per superpowers:writing-skills, capture failing tests before any skill
content is authored. Each scenario will be dispatched to a subagent
with no skill loaded; baseline rationalisations are captured into
tests/notes.md (gitignored) and used to inform the SKILL.md content
that needs to plug each loophole.

Scenarios:
- S1 vanilla build         - S2 Insights trace at CL on PS5
- S3 bisect crash          - S4 author .mychan resave channel
- S5 context recovery      - S6 compositional UE-args (PlayerStart)
- S7 UAT fluency (shipping + Gauntlet)"
```

### Task 1.2: Dispatch a RED subagent for each scenario and capture output

**Files:**
- Create: `tests/notes.md` (gitignored — local only)

- [ ] **Step 1: Create the notes file header**

Write `tests/notes.md`:
```markdown
# RED baseline transcripts (gitignored)

Captured at: <fill in YYYY-MM-DD HH:MM>
Subagent model: general-purpose, no skill loaded.

## How scenarios were dispatched

For each scenario, a fresh general-purpose subagent received a prompt of the form:

> You have no project context. You have access to a Windows machine with PowerShell. UE 5.7 is installed at `E:\UE_5.7\`. ushell ships in the engine at `E:\UE_5.7\Engine\Extras\ushell\` but you do NOT have to use it. Approach the following request as you would normally:
>
> [verbatim scenario from tests/baseline.md]

Each subagent ran with read-only Bash/PowerShell exploration only (no actual builds dispatched). The full transcript of its proposed sequence of actions and rationalisations is captured below verbatim.

---

## S1 transcript

[paste verbatim agent output here]

## S2 transcript

[paste verbatim agent output here]

(... and so on for S3-S7)

---

## Summary of baseline rationalisations

The following table is filled in after all 7 transcripts are captured. Each row is one verbatim phrase or pattern the agent used, plus the scenario it appeared in and the loophole it represents.

| Verbatim rationalisation | Scenarios | Loophole the skill must plug |
|---|---|---|
| (fill in after capture) | | |
```

- [ ] **Step 2: Dispatch all 7 RED subagents in parallel**

In the executing session, use the `Agent` tool to dispatch seven general-purpose subagents simultaneously. Prompt template (use one per scenario, substituting the verbatim scenario text):

```
You have no project context. You have access to a Windows machine with PowerShell. UE 5.7 is installed at `E:\UE_5.7\`. ushell ships at `E:\UE_5.7\Engine\Extras\ushell\` but you do NOT have to use it. Approach the following request as you would normally — describe the exact commands you would run, in order, with brief justifications. Do not invent flags; only describe what you genuinely believe to be correct.

If you would normally ask the user a clarifying question, list the question instead of asking it.

Scenario:

[paste the scenario S1..S7 verbatim from tests/baseline.md]

Return your full reasoning + the proposed command sequence as a single markdown response.
```

Expected: seven distinct response bodies, each describing what a baseline (no-skill) agent would do. None should use `.build editor` / `.cook` / `.run commandlet` patterns idiomatically — if they do, the scenario is too easy and should be tightened (rare).

- [ ] **Step 3: Paste each transcript verbatim into tests/notes.md**

Edit `tests/notes.md` to replace each `[paste verbatim agent output here]` block with the actual subagent response. Do not paraphrase. Keep the agent's exact wording, including any wrong flags.

- [ ] **Step 4: Score each transcript and fill the rationalisation table**

For each transcript, extract:
- Did it detect ushell? (Y/N)
- Did it use any `.<verb>` command? (Y/N)
- Did it use raw `RunUAT.bat` / `UnrealBuildTool.exe` / `GenerateProjectFiles.bat` / direct `p4`? (Y/N + which)
- For S2/S6: did it walk the Insights DAG backwards or jump to a single command?
- For S6: did it invent `?StartPoint=` or some other non-existent flag?
- For S7: did it try `.stage` repeatedly hoping for multi-target, or did it correctly identify the need for direct `.uat BuildCookRun`?

Append a "Summary" table at the bottom of `tests/notes.md` with one row per verbatim rationalisation (e.g. *"I'll use `RunUAT.bat BuildCookRun -platform=Win64 -targetplatform=Win64`"* → *S1, S7* → *Doesn't know about ushell wrappers; defaults to raw UAT*).

- [ ] **Step 5: Do NOT commit `tests/notes.md`**

Verify it's ignored:
```bash
git status --short
```
Expected: `notes.md` does NOT appear. (Already gitignored via `tests/notes.md` line in `.gitignore`.)

If you want to preserve the transcripts outside the repo, copy them somewhere local (e.g. `E:\Work\ushell-skill-private-notes\notes-2026-05-13.md`). They will inform every subsequent task — particularly which loopholes to plug in `SKILL.md`'s anti-patterns and which symptoms to add to `troubleshooting.md`.

---

## Phase 2 — SKILL.md (the always-loaded surface)

The Iron Rule: SKILL.md must address the specific rationalisations captured in Phase 1, not hypothetical ones. Re-read `tests/notes.md` before each step.

### Task 2.1: Frontmatter, iron rules, detection gate

**Files:**
- Create: `SKILL.md`

- [ ] **Step 1: Write the frontmatter and opening header**

Write `SKILL.md`:
```markdown
---
name: ushell
description: Use when working in an Unreal Engine branch that contains
  Engine/Extras/ushell, or when a task involves building/cooking/staging/running
  UE targets, generating VS solutions, syncing or integrating UE Perforce
  branches, running editor commandlets (-run=...), driving UAT (RunUAT,
  BuildCookRun), managing Zen storage or DDC, running automated perf tests,
  downloading cloud builds, or authoring a new ushell channel
  (describe.flow.py, flow.cmd.Cmd / unrealcmd.Cmd subclasses). Also use when
  a ushell command fails and needs diagnosis.
---

# ushell

ushell is Epic's command-line interface for Unreal Engine, shipped at `<branch>/Engine/Extras/ushell/`. It wraps UBT, UAT, the editor, the runtime, and Perforce behind a single `.command arg arg --opts` interface with tab completion, history, and session-scoped project state.

## Iron rules

1. **If `Engine/Extras/ushell/ushell.bat` (or `.sh`) exists for the active `.uproject`, drive build infrastructure through ushell.** Do not invoke `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, or raw `p4` directly. There is no silent fallback — if a need genuinely isn't covered, stop and report.
2. **Every ushell command accepts `--help`.** Run it before guessing flags.
3. **Don't invent a command.** If `.foo` isn't in the Quick Reference below or `reference/commands.md`, look it up. Don't reach for a half-remembered RunUAT flag instead.

## Detection gate

Before doing anything else, locate ushell:

- Windows: `<branch>/Engine/Extras/ushell/ushell.bat`
- POSIX:   `<branch>/Engine/Extras/ushell/ushell.sh`

If neither exists for the active `.uproject`'s engine, **stop and tell the user.** This is an older or partial branch; ushell verbs will not exist. Do not silently fall back to raw UBT/UAT.
```

- [ ] **Step 2: Verify the file**

Run: `Get-Content E:\Work\ushell-skill\SKILL.md`
Expected: frontmatter + iron rules + detection gate present. No trailing TODO/TBD markers.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(skill): SKILL.md frontmatter, iron rules, detection gate

Description encodes triggering conditions only (per writing-skills CSO).
No workflow summary. Iron rules forbid raw UBT/UAT/GenerateProjectFiles/p4
when ushell is present; detection gate halts cleanly on engines without
Engine/Extras/ushell/."
```

### Task 2.2: Non-interactive invocation recipe

**Files:**
- Modify: `SKILL.md` (append section)

- [ ] **Step 1: Append the invocation section**

Edit `SKILL.md` — append after the Detection gate section:
````markdown

## Non-interactive invocation

ushell normally opens an interactive `cmd.exe` window. To drive it from a Bash/PowerShell session without that, use one of these two forms.

**Single command:**

```powershell
cmd.exe /d /s /c "call <path>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .info --nosummary"
```

**Multiple commands — write a temp .bat:**

```bat
@echo off
call <path>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.p4 sync --all
.build editor
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Failure |
| `126` | Argument parse error (treat as your bug) |
| `127` | Help printed (the user asked for help; not a failure) |
| `80` / `90` | Reserved for the `.p4 bisect` script protocol (bad / failed-build) |

Suppress the `Cmd.summarise` result/time banner with `--nosummary` on commands that have it (build, sync, mergedown, switch, …). Use this whenever you parse output.

The active `.uproject` lives in a session noticeboard keyed by `$FLOW_SID`. Every fresh invocation is a new session ID, so always pass `--project=<path>` to `ushell.bat`, or run `.project <path>` as the first command. Do NOT `cd` inside a `cmd /d /k ushell.bat` chain — ushell deliberately unsets `PWD`.

Full details and PowerShell module integration: `reference/invocation.md`.
````

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat(skill): non-interactive invocation contract

Canonical recipe for driving ushell from Bash/PowerShell, exit-code
cheatsheet, --nosummary discipline for log parsing, and the noticeboard
gotcha (FLOW_SID-keyed; always pass --project=)."
```

### Task 2.3: Goal-directed planning rule

**Files:**
- Modify: `SKILL.md` (append section)

- [ ] **Step 1: Append the goal-directed planning rule**

Edit `SKILL.md` — append:
````markdown

## Goal-directed planning

When the user states a **goal** (e.g. *"an Insights trace at CL X on PS5"*), do NOT jump to a single command. Walk backwards:

1. **Terminal command** — what command actually produces the goal artifact?
2. **Preconditions** — what must already exist for it to succeed?
3. **Recurse** until a precondition is already satisfied (verify with `.info`, file checks, `.zen snapshot list`, etc.).
4. **Execute forwards**, verifying after each step.

Each `reference/commands.md` entry declares **Preconditions** and **Produces**. `reference/workflows.md` provides full goal-to-plan DAGs. For anything passed after `-- <UE args>` (map URL, `?StartPoint=`, `-trace=<channels>`, `-ExecCmds=`, LLM/memory switches, commandlet `-run=<Name>` recipes, etc.), source the actual args from `reference/unreal-args.md` — **do not invent UE switches**.

**Skip-policy:** skip a precondition only when verifiable. Checks that count as verification:
- A `.target` receipt file exists at `Binaries/<Plat>/<Name>[-<Plat>-<Variant>].target`.
- `Saved/Cooked/<cook_form>/` exists and is non-empty.
- `.zen snapshot list <runtime> <platform>` returns a hit at the requested CL.
- `Engine/Build/Build.version` `Changelist` matches the target CL.

If the check is unclear, re-run the precondition.

**Failure-policy:** if a step fails or a precondition is truly unreachable, **stop, report the verbatim error, suggest the next action, hand back to the user.** No silent fallback to raw tools, no destructive auto-recovery (don't delete `Saved/`, don't edit `.uproject`, don't `p4 reset` without consent).
````

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat(skill): goal-directed planning rule

Walk backwards from terminal command to preconditions; skip only when
verifiable on-disk; stop and hand back on unrecoverable failure. Refers
forward to commands.md (Preconditions/Produces fields), workflows.md
(DAGs), and unreal-args.md (UE switches passed after --)."
```

### Task 2.4: Quick reference table

**Files:**
- Modify: `SKILL.md` (append section)

- [ ] **Step 1: Append the quick-reference table**

Edit `SKILL.md` — append:
````markdown

## Quick reference

| Want to… | Command |
|---|---|
| See engine/project/platform state | `.info` |
| List branch projects | `.info projects` |
| Switch active project | `.project <name\|path\|cwd\|auto>` |
| Generate VS solution | `.sln generate` |
| Open existing solution | `.sln open` |
| Open a tiny solution (fzf-only) | `.sln open tiny` |
| Build editor | `.build editor [variant]` |
| Build runtime | `.build {game\|client\|server} <platform>` |
| Build a named program | `.build program <Name>` |
| Clean before build | `.build clean editor` (etc.) |
| Single file/module build | `.build editor <Module/File.cpp>` |
| Build XML config (BuildConfiguration.xml) | `.build xml [edit\|set\|clear]` |
| Generate compile_commands.json | `.build misc clangdb` |
| Run editor | `.run editor -- <args>` |
| Run a commandlet | `.run commandlet <Name> -- <args>` |
| Run a program / named target | `.run program <Name>` / `.run target <Name>` |
| Run cooked runtime | `.run {game\|client\|server} <platform> -- <args>` |
| Run runtime with Insights trace | `.run game <P> --trace=<channels> -- <args>` |
| Cook | `.cook {game\|client\|server} <platform>` |
| Cook iteratively | `.cook game <P> --iterate` |
| ODSC shader server | `.cook odsc {game\|client\|all} <platform>` |
| Stage (auto Zen/pak) | `.stage <target> <platform> auto` |
| Stage with Zen storage | `.stage <target> <platform> zen` |
| Stage with pak files | `.stage <target> <platform> pak` |
| Deploy already-staged | `.deploy <target> <platform>` |
| Run UAT directly | `.uat <Command> -- <uat-args>` |
| BuildCookRun via UAT | `.uat BuildCookRun -- <bcr-args>` *(reference/uat.md §A)* |
| Package a plugin | `.uat BuildPlugin -- -Plugin=<path> -Package=<out> -TargetPlatforms=Win64+Linux -Rocket -StrictIncludes` |
| Run a BuildGraph script | `.uat BuildGraph -- -script=<path.xml> -target=<Node> [-set:Foo=Bar]` |
| List BuildGraph nodes | `.uat BuildGraph -- -script=<path.xml> -listonly` |
| Run Gauntlet tests | `.uat RunUnreal -- -test=<TestName> -build=<staged\|editor> -platform=<P>` |
| CI-friendly UAT baseline | append `-buildmachine -CrashForUAT -nop4 -NoCodeSign -unattended -nullrhi -utf8output -stdlog` |
| Kill running UE process | `.kill {editor\|server\|client\|<platform>}` |
| Sync from Perforce | `.p4 sync [<cl>]` |
| Filter sync (edit .p4sync.txt) | `.p4 sync edit` |
| Cherrypick CLs | `.p4 cherrypick <cl> [...]` |
| Bisect a regression | `.p4 bisect <good> <bad> -- <script>` |
| Mergedown from parent stream | `.p4 mergedown` |
| Switch stream | `.p4 switch <stream>` / `.p4 switch list` |
| List CL authors | `.p4 authors <path>` |
| Who-broke-this-line | `.p4 who <path> [<line>]` |
| Open P4V on this clientspec | `.p4 v` |
| Create a new workspace | `.p4 workspace <dir> [<depotpath>]` |
| Clean intermediate/Saved/ | `.p4 clean [--dryrun]` |
| Authorize cloud DDC | `.ddc auth [<service>]` |
| Start/stop ZenServer | `.zen start` / `.zen stop` |
| ZenServer status / version | `.zen status` / `.zen version` |
| Open Zen dashboard GUI | `.zen dashboard` |
| Create Zen workspace / share | `.zen createworkspace <dir>` / `.zen createshare <dir>` |
| Import a Zen oplog snapshot | `.zen importsnapshot <descriptor> [<index>]` |
| Find a cooked-data snapshot for CL | `.zen snapshot find <runtime> <platform>` |
| Download + import a snapshot | `.zen snapshot get <runtime> <platform> [<cl>]` |
| List available snapshots | `.zen snapshot list <runtime> <platform>` |
| Launch Insights | `.perf insights [<trace>\|latest]` |
| Run automated perf test | `.perf test {default\|sequence\|replay\|material\|camera} <platform>` |
| Download a cloud build | `.getbuild {packaged\|staged} <platform>` |
| Flash console for attention | `.notify` |
| Gather standalone ushell | `.ushell gather <destdir>` |

## Zen ↔ UAT relationship

`.zen *` commands talk to the standalone **ZenServer** process and the cloud/fileshare snapshot index. They are **not** a substitute for `.stage`. Staging still goes through UAT `BuildCookRun`, but `style=zen` (or `style=auto` driven by `Saved/Cooked/<form>/ue.projectstore`) tells UAT to package as a Zen oplog rather than pak/utoc. `.zen snapshot get` is the fast path for *"pull a pre-cooked dataset for this CL"* — it launches ZenServer if needed and imports the oplog. Always check `.zen status` before assuming Zen is running.
````

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat(skill): quick reference table + Zen<->UAT note

~50 most-reached-for verbs across unreal/core and unreal/perforce
channels plus UAT/BuildGraph/Gauntlet entry points. Inline note clarifies
the Zen and .stage/UAT relationship so Claude doesn't conflate them."
```

### Task 2.5: "Load reference when…" pointers and anti-patterns

**Files:**
- Modify: `SKILL.md` (append closing sections)

- [ ] **Step 1: Append the pointers and anti-patterns**

Edit `SKILL.md` — append:
````markdown

## Load reference when…

- Need flag/option detail on a ushell command → `reference/commands.md`
- Need a multi-step plan / DAG for a goal → `reference/workflows.md`
- Authoring a new ushell command/channel → `reference/channel-authoring.md`
- Spawning ushell yourself from a script/Bash/PS → `reference/invocation.md`
- A command failed or behaves oddly → `reference/troubleshooting.md`
- Shaping what UE itself does once launched (boot mode, map, start point, trace channels, `-ExecCmds`, low-memory tracking, etc.) → `reference/unreal-args.md`
- Driving UAT directly — `BuildCookRun` recipes, `BuildPlugin`, `RunUnreal` for tests, full ProjectParams flag groups, CI-friendly invocations, packaging/signing — → `reference/uat.md`
- Authoring or invoking a BuildGraph script (schema, tasks, `-script=`, `-target=`, `-set:`, idiomatic pipelines) → `reference/buildgraph.md`

## Anti-patterns

- Don't call `RunUAT.bat`, `UnrealBuildTool.exe`, `GenerateProjectFiles.bat`, or raw `p4` when ushell is present.
- Don't invent UE switches. Common hallucinations: `?StartPoint=<Name>` (the spawn selector is `<Map>#<Portal>`, not a `?` Op), `-encrypt` (it's `-encryptinifiles` plus `-signpak` / `-keychain=`), `-runautomationtest` under BCR (fragile — use `RunUnreal` Gauntlet or direct editor `-ExecCmds="Automation RunTests ...; Quit"`).
- Don't pipe `-Foo="path with spaces"` through plain subprocess argv when extending ushell — use `unreal.cmdline.read_ueified()`.
- Don't set `FLOW_SID` yourself, and don't invoke `_build`/`_cook`/`_uat`/`_run`/`_p4` (those are ushell's internal subprocess shims).
- Don't `cd` inside a `cmd /d /k ushell.bat` chain — PWD is unset deliberately by ushell.
- Don't use `.cook --iterate` for shipping builds (community-confirmed stale-asset bugs). Iterative cook is for dev only; always full `-cook` for release.
- Don't trust Project Settings → Packaging → StagingDirectory under UAT — it's ignored. Always pass `-stagingdirectory=` and `-archive -archivedirectory=` on the CLI.
````

- [ ] **Step 2: Verify SKILL.md word count**

Run:
```powershell
(Get-Content E:\Work\ushell-skill\SKILL.md | Measure-Object -Word).Words
```

Expected: **prose body** (everything between `---` end and end of file, excluding the quick-reference table) is ≤300 words per the acceptance criterion. The full file including the table will be ~1500-2000 words, which is fine — the table is a lookup structure, not prose.

If prose exceeds 300 words: trim. The most common bloat sources are over-explained iron rules and duplicated bullets in anti-patterns.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(skill): reference pointers and anti-patterns

Pointers route to the eight reference files by use case. Anti-patterns
codify the specific hallucinations baseline subagents produced in
tests/notes.md, including ?StartPoint= (use #Portal), -encrypt (use
-encryptinifiles + -signpak), and CRLF-vs-PWD on Windows."
```

---

## Phase 3 — reference/invocation.md

### Task 3.1: Write invocation.md in full

**Files:**
- Create: `reference/invocation.md`

This file is short and self-contained — written as a single task with multiple steps, since the content is tightly coupled.

- [ ] **Step 1: Write the opening + launch contract**

Create `reference/invocation.md`:
````markdown
# Driving ushell non-interactively

ushell normally boots an interactive `cmd.exe` window. To drive it from Bash/PowerShell — i.e. as a Claude Code session — use the **scripting** invocation path.

## The launch contract

`ushell.bat` inspects how it was launched:

- **Launched from Explorer or a shortcut** → interactive: spawns its own console, host shell awaits user input.
- **Called via `cmd /d /k`, `cmd /d /s /c`, or `call` from another `.bat`** → scripting: stays in the calling shell, runs commands non-interactively, exits.

On POSIX systems the script is sourced:

```bash
source <branch>/Engine/Extras/ushell/ushell.sh
```

…which establishes ushell in the **current** bash/zsh session. Arguments after `source` follow the same rules as Windows (e.g. `--project=<path>`).

## Single-command form (Windows)

```powershell
cmd.exe /d /s /c "call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject> && .info --nosummary"
```

- `/d` skips AutoRun registry hooks; `/s` rationalises quoting; `/c` runs and exits.
- `&&` chains a single ushell verb after the bat finishes establishing itself. Multiple commands need the multi-command form below — `&&` does NOT carry into ushell's own command parser the same way.

## Multi-command form (Windows)

Write a temp `.bat`:

```bat
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.p4 sync --all
.build editor
.cook game ps5 --iterate
```

Then invoke it with `cmd.exe /d /s /c "<path_to_temp.bat>"`. Inside the bat, ushell's verbs execute sequentially; `&&` works inside ushell too (`.build editor && .cook game ps5`).

## PowerShell

For interactive use, import the PowerShell module:

```powershell
$env:PSModulePath = "$env:PSModulePath;<branch>\Engine\Extras\ushell"
Import-Module powerushell
```

…then use ushell verbs as PowerShell-friendly cmdlets. For non-interactive scripting from a PowerShell-hosted Claude session, **still go via `cmd.exe`** — the cmd-hosted scripting path is the canonical one and is what every other ushell consumer expects.

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Failure |
| `126` | Argument parse error (your bug — fix the command, don't retry) |
| `127` | Help was printed (the user asked `--help`; not a failure to surface) |
| `80` | `.p4 bisect` script protocol: "bad" CL |
| `90` | `.p4 bisect` script protocol: "failed to build" CL |

## --nosummary

Commands decorated with `Cmd.summarise` print a footer like:

```
== Result: Success
== Time: 0:00:42
```

This breaks log parsers. Suppress with `--nosummary` on commands that accept it: `.build *`, `.p4 sync`, `.p4 mergedown`, `.p4 switch`, `.cook *` (some), and most things that take meaningful time.

## Active-project propagation

The active `.uproject` is stored in a session **noticeboard** keyed by the environment variable `FLOW_SID`. Each fresh shell invocation gets a new SID, so the noticeboard is empty — meaning the active project is **not inherited from your previous session** even if you set it earlier with `.project`.

Always do one of:

1. Pass `--project=<absolute path to .uproject>` to `ushell.bat` (preferred for one-shot scripts).
2. Run `.project <path|name|cwd|auto>` as the **first** ushell command after bat establishment (preferred for multi-command bats).
3. Set `cwd` to a directory inside the project before launching, then run `.project cwd`.

`.project list` enumerates projects under the branch without switching. `.project active` prints the current active project.

## Env-var arg overrides

For any arg/opt whose value is unset (still at its default), ushell will substitute from the environment if a key of the form

```
ushell/<invoke-path>:<arg-name>
```

is set. For example, set the default build variant to `test`:

```powershell
$env:'ushell/build/editor:variant' = 'test'
```

…and `.build editor` becomes `.build editor test` for the rest of the session. Useful for site-level defaults injected from `$USERPROFILE/.ushell/hooks/startup.bat`.

## Output parsing

ushell wraps build/cook/etc. output in `_PrettyPrinter`, which colourises errors/warnings and emits `@progress` markers. Markers worth recognising:

- `@progress 'phase' N/M` — task counter; useful for progress display.
- `** For <Target> **` — per-target prefix when multiple targets build in one invocation.
- `== Errors and warnings ==` — end-of-build summary; one line per diagnostic.

For grep-friendly output, pass `--unpretty` where supported (`.cook *`, `.cook odsc *`). For machine parsing, prefer `--nosummary` plus `--unpretty`.

## Forbidden moves

- Don't `cd` inside a `cmd /d /k ushell.bat` chain. ushell deliberately unsets `PWD` in `_call_main` (`E:\UE_5.7\Engine\Extras\ushell\channels\flow\core\system\flow\cmd.py`) because subprocess + `os.chdir + p4` had subtle bugs. Use `--project=<path>` instead.
- Don't set `FLOW_SID` yourself. It's set to the parent PID at boot time; overwriting it desynchronises the noticeboard.
- Don't invoke `_build`, `_cook`, `_uat`, `_run`, or `_p4` directly. These are ushell's internal subprocess shims used by commands that need to re-dispatch themselves (e.g. `.cook --attach` shells out to `_run commandlet cook --attach`). User-facing verbs are the dotted ones (`.build`, `.cook`, …).
````

- [ ] **Step 2: Verify file structure**

Run:
```powershell
Get-Content E:\Work\ushell-skill\reference\invocation.md | Select-String "^## " | Select-Object Line
```

Expected: ten `##` headings — Launch contract, Single-command form, Multi-command form, PowerShell, Exit codes, --nosummary, Active-project propagation, Env-var arg overrides, Output parsing, Forbidden moves.

- [ ] **Step 3: Commit**

```bash
git add reference/invocation.md
git commit -m "feat(skill): reference/invocation.md

Canonical non-interactive driving contract. Covers launch detection,
single + multi-command forms, PowerShell module, exit codes (incl. 80/90
for .p4 bisect), --nosummary, FLOW_SID propagation, env-var overrides,
output markers, and forbidden moves (cd / FLOW_SID / _* shims)."
```

---

## Phase 4 — reference/commands.md

The largest reference file. ~60 commands across the `unreal/core` and `unreal/perforce` channels. Each entry follows a fixed template. To keep this plan tractable, the template is written once in Task 4.0, then tasks 4.1–4.16 each implement one command family by reading the underlying engine `.py` file in `E:\UE_5.7\Engine\Extras\ushell\channels\` and applying the template.

The per-entry content is the agent's responsibility to derive from the source file. The plan gives the source file + class for each entry plus any non-obvious details. Do NOT invent flags — read the source.

### Task 4.0: Write the template, TOC, and file header

**Files:**
- Create: `reference/commands.md`

- [ ] **Step 1: Write the header and template description**

Create `reference/commands.md`:
````markdown
# ushell command reference

One section per registered command, in the order they appear in `<ushell>/channels/unreal/core/describe.flow.py` and `<ushell>/channels/unreal/perforce/describe.flow.py`. Each section follows the **template** below. Field semantics are non-negotiable — they're what powers `SKILL.md`'s goal-directed-planning rule.

## Template

```markdown
## `.<words>` — <one-line purpose>

**When:** <triggering need>

**Usage:** `.<words> <positional1> [<positional2>] [-- <UE passthrough args>]`

**Args:**
- `<name>` (<type>/<default>) — <description>
…

**Flags:**
- `--<flag>` (<type>/<default>) — <description>
…

**Preconditions:**
- <verifiable check, e.g. "Active .uproject set in noticeboard">
- <verifiable check, e.g. "Editor .target receipt exists at Binaries/...">

**Produces:**
- <artifact, e.g. "Binaries/<P>/<Name>-<P>-<V>.target">
- <state change, e.g. "Saved/Cooked/<cook_form>/ populated">

**Implicit behaviour:** <auto-injected flags, target munging, env setup>

**Common pitfalls:**
- <bullet>

**Examples:**

\`\`\`
.<words> <real example>     # one-line justification
\`\`\`

**Source:** `<ushell>/channels/<channel>/cmds/<file>.py::<ClassName>`
```

The **Preconditions** and **Produces** fields are how `SKILL.md`'s goal-directed planner walks the DAG. They must be verifiable from on-disk state when possible.

## Table of contents

- Core channel (`channels/unreal/core/cmds/`)
  - **Build:** `.build target`, `.build editor`, `.build clean editor`, `.build program`, `.build clean program`, `.build server`, `.build clean server`, `.build client`, `.build clean client`, `.build game`, `.build clean game`
  - **Build config:** `.build xml`, `.build xml edit`, `.build xml set`, `.build xml clear`
  - **Misc build:** `.build misc clangdb`
  - **Run:** `.run editor`, `.run commandlet`, `.run program`, `.run target`, `.run server`, `.run client`, `.run game`
  - **Cook:** `.cook`, `.cook game`, `.cook client`, `.cook server`
  - **ODSC:** `.cook odsc client`, `.cook odsc game`, `.cook odsc all`
  - **Stage / deploy:** `.stage`, `.deploy`
  - **UAT:** `.uat`
  - **Solutions:** `.sln generate`, `.sln open`, `.sln open 10x`, `.sln open tiny`
  - **Info / project:** `.info`, `.info projects`, `.info config`, `.project`
  - **Misc:** `.kill`, `.notify`, `.ushell gather`, `.getbuild`
  - **Storage / data:** `.ddc auth`
  - **Zen:** `.zen start`, `.zen stop`, `.zen status`, `.zen version`, `.zen dashboard`, `.zen createworkspace`, `.zen createshare`, `.zen importsnapshot`
  - **Zen snapshots:** `.zen snapshot find`, `.zen snapshot get`, `.zen snapshot list`
  - **Perf:** `.perf insights`, `.perf test default`, `.perf test sequence`, `.perf test replay`, `.perf test material`, `.perf test camera`
- Perforce channel (`channels/unreal/perforce/cmds/`)
  - `.p4 sync`, `.p4 sync edit`, `.p4 sync mini`
  - `.p4 cherrypick`
  - `.p4 bisect`
  - `.p4 mergedown`
  - `.p4 switch`, `.p4 switch list`
  - `.p4 workspace`
  - `.p4 clean`, `.p4 reset`
  - `.p4 authors`, `.p4 who`
  - `.p4 v` (P4V launcher)

---
````

- [ ] **Step 2: Commit the skeleton**

```bash
git add reference/commands.md
git commit -m "feat(skill): reference/commands.md template + TOC"
```

### Task 4.1: Document the `.build` family

**Files:**
- Modify: `reference/commands.md` (append entries)
- Read: `E:\UE_5.7\Engine\Extras\ushell\channels\unreal\core\cmds\build.py`

The `.build` family is implemented in `cmds/build.py` and registered in `describe.flow.py` (look for `build_*` variables). All entries inherit shared options from the `_BuildCmd` mixin.

- [ ] **Step 1: Read the source**

Read `E:\UE_5.7\Engine\Extras\ushell\channels\unreal\core\cmds\build.py` in full. Note the shared `_BuildCmd` options (lines around 30-90), the `_add_clean_cmd` decorator (auto-generates Clean* classes), and the per-target classes (`Build`, `Editor`, `Program`, `Server`, `Client`, `Game`).

- [ ] **Step 2: Append the build-family entries**

Edit `reference/commands.md` — append the following entries. For each, fill in the **Preconditions** and **Produces** based on what the source shows. Do not invent flags; copy them from the `Arg`/`Opt` declarations in `build.py`.

Entries to add (in order):
1. `## `.build target`` — class `Build`. Target arg accepts space-separated multiple names; tab-completed from `Intermediate/Build/BuildRules/*RulesManifest.json` or `Source/*.Target.cs`. Preconditions: active branch (engine `Build.version` exists). Produces: `Binaries/<P>/<Target>[-<P>-<V>].target` receipt.
2. `## `.build editor`` — class `Editor`. Implicit: auto-builds `ShaderCompileWorker`, `UnrealPak`, `InterchangeWorker` unless `--noscw` / `--nopak` / `--nointworker` or constrained build. Preconditions: as above. Produces: editor `.target` + the three implicit programs.
3. `## `.build clean editor`` — class `CleanEditor` (auto-generated by `_add_clean_cmd`). Same as `.build editor` with `--clean` forced.
4. `## `.build program`` — class `Program`. Target tab-completed from `Source/Programs/*/*.Target.cs` and `Source/Programs/*/*/*.Target.cs`. Preconditions: active branch. Produces: `Binaries/<P>/<Program>[-<P>-<V>].target`.
5. `## `.build clean program``
6. `## `.build server`` — class `Server`. `complete_platform = ("win64", "linux")`.
7. `## `.build clean server``
8. `## `.build client`` — class `Client` extends `_Runtime`. Auto-sets `-Project=` (projected) when project active.
9. `## `.build clean client``
10. `## `.build game`` — class `Game` extends `_Runtime`. Same as client.
11. `## `.build clean game``

For shared `_BuildCmd` options that recur on every entry, document them ONCE in a small "_BuildCmd shared options_" subsection at the top of the `.build` group: `--clean`, `--nouht`, `--noxge`, `--analyze={visualcpp|pvsstudio}`, `--projected`, `--noshowcfg`. Each entry's **Flags** section then says "_BuildCmd shared options_, plus:" followed by entry-specific flags.

Use this **Implicit behaviour** field for `.build editor` verbatim:
> Auto-builds `ShaderCompileWorker`, `UnrealPak`, and `InterchangeWorker` programs unless `fileormod` is set, `--analyze` is set, or any of `--noscw`/`--nopak`/`--nointworker` is given. Adds `-AllModules` unless the project path matches `EngineTest`/`Samples`. Always passes `-Progress`.

For all `.build *` entries, set:
- **Preconditions:** "Active branch (engine `Build.version` readable at `Engine/Build/Build.version`)." For non-editor targets that use `_Runtime`, add "Active `.uproject` set."
- **Produces:** "`<Target>.target` receipt at `Binaries/<P>/<Target>[-<P>-<V>].target`. Object files under `Intermediate/Build/`."

- [ ] **Step 3: Verify entries land**

Run:
```powershell
Select-String -Path E:\Work\ushell-skill\reference\commands.md -Pattern "^## " | Select-Object Line
```

Expected: 11 new `## .build *` headings (target, editor, clean editor, program, clean program, server, clean server, client, clean client, game, clean game) — plus whatever existed before.

- [ ] **Step 4: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .build family entries

Covers .build target / editor / program / server / client / game and
their clean variants, plus the shared _BuildCmd option block. Each entry
declares Preconditions (engine Build.version, optional active .uproject)
and Produces (.target receipt path + Intermediate/Build/)."
```

### Task 4.2: Document the `.build xml` family and `.build misc clangdb`

**Files:**
- Modify: `reference/commands.md`
- Read: `E:\UE_5.7\Engine\Extras\ushell\channels\unreal\core\cmds\build_xml.py`, `cmds/clangdb.py`

- [ ] **Step 1: Read both source files**

`build_xml.py` implements `Show`, `Edit`, `Set`, `Clear` against `BuildConfiguration.xml` at four levels (INTERNAL/BRANCH/GLOBAL/LEGACY). `clangdb.py` implements `ClangDb` to produce `compile_commands.json`.

- [ ] **Step 2: Append the entries**

Entries to add:
1. `## `.build xml`` — class `Show`. No args/flags. Iterates `ubt.read_configurations()`; prints sections, values, file existence colourised. Preconditions: active branch. Produces: stdout (no on-disk effect).
2. `## `.build xml edit`` — class `Edit`. Flag `--branch`. Opens `BuildConfiguration.xml` in `$GIT_EDITOR`/`$P4EDITOR`/system default. Preconditions: active branch. Produces: modified XML on save (out-of-band).
3. `## `.build xml set`` — class `Set`. Args: `section`, `name`, `value` (all schema-tab-completed). Flag `--branch`. Updates BuildConfiguration.xml. Produces: modified XML; prints "was '<prev>'".
4. `## `.build xml clear`` — class `Clear`. Args: `section`, `name`. Flag `--branch`. Mirrors set.
5. `## `.build misc clangdb`` — class `ClangDb`. Arg: `target` (default editor target). Flags: `--platform=`, `--projected`, `--keepgenfiles`, `--keepplatformcode`, `--keepthirdpartycode`. Calls UBT with `-Mode=GenerateClangDatabase`. Produces: `compile_commands.json` at engine-root (or project root for foreign projects). For more detail copy the body from the brainstorm exploration output (Agent A in the codebase deep-dive).

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .build xml family + .build misc clangdb"
```

### Task 4.3: Document the `.run` family

**Files:**
- Modify: `reference/commands.md`
- Read: `E:\UE_5.7\Engine\Extras\ushell\channels\unreal\core\cmds\run.py`

- [ ] **Step 1: Read the source**

Critical entries: `Editor`, `Commandlet`, `Program`, `Target`, `Server`, `Client`, `Game`. The `_Attachable` mixin handles `--attach` via `<core>/debuggers/{vs,lldb,rider}.py`. The `_Runtime` mixin handles `--trace`, `--cooked`, `--onthefly`, `--binpath`, `--datadir`, and writes/restores `UECommandLine.txt`.

- [ ] **Step 2: Append the entries**

Entries to add (7 commands):
1. `## `.run editor`` — class `Editor`. Args: `variant` (default `development`), `runargs`. Flags: `--build`, `--attach`, `--noproject`. Auto-prepends `.uproject` path to argv unless `--noproject`. If `-stdout` in `runargs` on Windows, switches binary from `Foo.exe` to `Foo-Cmd.exe`. Preconditions: editor `.target` receipt (auto-built if `--build`). Produces: running editor process (returns immediately on Windows interactive); on `--attach`, debugger session via `debuggers/<name>.py`.
2. `## `.run commandlet`` — class `Commandlet`. Args: `commandlet` (tab-completed from `Source/Editor/UnrealEd/Classes/Commandlets/*Commandlet.h`), `variant`, `runargs`. Flags: `--build`, `--attach`. **Forces `-Cmd.exe`** (commandlets need stdout). Prepends `.uproject` then `-run=<commandlet>` to argv. Preconditions: editor `.target` + active project. Produces: stdout from the commandlet; usually edits assets under `Content/` or writes to `Saved/`.
3. `## `.run program`` — class `Program`. Args: `program`, `variant`, `runargs`. Flags: `--build`, `--attach`. Tab-completed from `Source/Programs/*/*.Target.cs`.
4. `## `.run target`` — class `Target`. Args: `target`, `variant`, `runargs`. Like `.run program` but for any named target.
5. `## `.run server`` — class `Server` extends `_Runtime`. Args: `platform`, `variant`, `runargs`. Flags: `--build`, `--attach`, `--trace=<channels>`, `--cooked`, `--onthefly`, `--binpath=`, `--datadir=`. **Auto-appends `-log -unattended`.** `complete_platform = ("win64", "linux")`. Preconditions: server `.target` + active project + cooked content at `Saved/Cooked/<cook_form>/` (unless `--datadir`).
6. `## `.run client`` — class `Client` extends `_Runtime`. Same as server minus the auto `-log`/`-unattended`.
7. `## `.run game`` — class `Game` extends `_Runtime`. Special case: if `platform == "editor"`, delegates to `.run editor` with `runargs + -game` (and forwards `--build`/`--attach`).

Document the `_Runtime` mixin once in a shared subsection at the top of the `.run` group, covering `--trace`, `--cooked`, `--onthefly`, `--binpath`, `--datadir`. Mention that `UECommandLine.txt` is **renamed to `*_old_ushell.txt` and a fresh empty one is written**, then restored on exit.

The `_Attachable` mixin and `debuggers/` directory should also be documented in a small subsection: `USHELL_DEBUGGER` env var selects backend (`vs` default on Windows, `lldb` elsewhere; `rider` opt-in). Cite `<ushell>/channels/unreal/core/debuggers/{vs,lldb,rider}.py`.

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .run family

7 entries (editor / commandlet / program / target / server / client / game)
plus shared _Runtime and _Attachable subsections. Notes the -Cmd.exe
swap for commandlets and -stdout, the UECommandLine.txt rename dance,
and the platform=editor special case in .run game."
```

### Task 4.4: Document `.cook`, `.cook game/client/server`, and `.cook odsc *`

**Files:**
- Modify: `reference/commands.md`
- Read: `cmds/cook.py`, `cmds/odsc.py`

- [ ] **Step 1: Read both files**

`cook.py` implements `Cook`, `Game`, `Client`, `Server` — all direct `-run=cook` against `<Editor>-Cmd.exe` (NOT UAT). `odsc.py` adds `-odsc` flag for On-Demand Shader Compile servers.

- [ ] **Step 2: Append the entries**

Entries (7 commands):
1. `## `.cook`` — class `Cook`. Args: `target` (full cook_form string, e.g. `WindowsNoEditor`), `cookargs`. Shared `_Cook` flags: `--cultures=en`, `--onthefly`, `--iterate`, `--noxge`, `--unpretty`, `--attach`, `--build`, `--debug`, `--nounattended`, `--versioned`. Implicit: `-unattended -unversioned -stdout`. Preconditions: editor `.target` + active project. Produces: `Saved/Cooked/<cook_form>/` populated.
2. `## `.cook game`` — class `Game` extends `_Runtime`. Args: `platform`, `cookargs`. Resolves cook_form via `platform.get_cook_form("game")`.
3. `## `.cook client``
4. `## `.cook server`` — `complete_platform = ("win64", "linux")`.
5. `## `.cook odsc client`` — class `Client` extends `_Runtime` → `_Odsc`. Args: `platform`, `odscargs`. Flags: `--cultures`, `--noxge`, `--unpretty`, `--attach`, `--skipassetscan`, `--debug`, `--symbols`. Adds `-odsc -cookonthefly -dpcvars=r.ShaderDevelopmentMode=1` to the commandlet line.
6. `## `.cook odsc game``
7. `## `.cook odsc all`` — class `All` extends `_Odsc` directly; passes literal cook form `All`.

For all cook entries, **Preconditions** must include "editor binary built (`Binaries/<HostPlatform>/UnrealEditor-Cmd.exe` exists)" — this is the canary that drives the goal-directed planner to insert a `.build editor` step.

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .cook + .cook odsc families

Notes that .cook is direct -run=cook against Editor-Cmd.exe (NOT UAT).
Preconditions explicitly require editor binary built, so the goal-directed
planner inserts .build editor when it's missing. Adds the ODSC variants
that piggyback on the same commandlet with -odsc."
```

### Task 4.5: Document `.stage`, `.deploy`, `.uat`

**Files:**
- Modify: `reference/commands.md`
- Read: `cmds/stage.py`, `cmds/uat.py`

- [ ] **Step 1: Read both files**

`stage.py` orchestrates `_build` → `_cook` → `_uat BuildCookRun` subprocesses. `.deploy` is a wrapper that forces `--skipstage --deploy --style=nopak`.

`uat.py` is the raw `.uat` runner — builds UAT first via `BuildUAT.bat` then runs `RunUAT.bat`.

- [ ] **Step 2: Append three entries**

1. `## `.stage`` — class `Stage`. Args: `target` (`game|client|server`), `platform`, `variant`, `style` (`pak|nopak|zen|auto`), `uatargs`. Flags: `--debug`, `--attach`, `--build="<ubt args>"`, `--cook="<cook args>"`, `--deploy`. Preconditions: active project, cooked content at `Saved/Cooked/<cook_form>/` (unless `--cook`). Produces: `Saved/StagedBuilds/<cook_form>/` populated.
2. `## `.deploy`` — class `Deploy`. Same args as `Stage`. Forces `--build=False --cook=False --deploy=True --style=nopak`. Calls super with `skipstage=True`. Preconditions: already-staged build at `Saved/StagedBuilds/`. Produces: build deployed to devkit/device via `platform.deploy`.
3. `## `.uat`` — class `Uat`. Args: `command` (UAT command name; tab-completed by scanning `Source/Programs/AutomationTool/**` for `BuildCommand` subclasses), `uatargs`. Flags: `--unprojected` (no implicit `-project=`), `--allscripts` (compile all UAT scripts, not just project's), `--debug`, `--attach` (opens `devenv.exe /debugexe`). Implicit: builds UAT via `BuildUAT.bat` first. Auto-injects `-project=<uproject>` and `-ScriptsForProject=<name>` unless `--unprojected`/`--allscripts`. **For full UAT command catalogue see `reference/uat.md`.**

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .stage / .deploy / .uat

.stage uses _uat BuildCookRun under the hood; .deploy is the
already-staged shortcut; .uat is the raw RunUAT wrapper. Cross-refs
reference/uat.md for the full UAT command catalogue."
```

### Task 4.6: Document `.sln`, `.info`, `.project`, `.kill`, `.notify`, `.ushell gather`, `.getbuild`, `.ddc auth`

Group these miscellaneous commands together — each is small and self-contained.

**Files:**
- Modify: `reference/commands.md`
- Read: `cmds/sln.py`, `cmds/info.py`, `cmds/project.py`, `cmds/kill.py`, `cmds/notify.py`, `cmds/gather.py`, `cmds/getbuild.py`, `cmds/ddc.py`

- [ ] **Step 1: Read each file briefly**

For each, note the class, args, flags, and key behaviour from the docstring.

- [ ] **Step 2: Append entries (in TOC order)**

1. `## `.sln generate`` — class `Generate`. Args: `open` (literal `"open"` to also open), `ubtargs`. Flags: `--notag`, `--all`.
2. `## `.sln open`` — class `Open`. Windows-only. Detects existing VS instance via `vs.dte.running()`; falls back to `cmd /c start <sln>`.
3. `## `.sln open 10x`` — class `Open10x`. Hardcoded `C:\Program Files\PureDevSoftware\10x\10x.exe`.
4. `## `.sln open tiny`` — class `Tiny`. Generates a minimal sln without `.sln generate` first; uses `slnformer`.
5. `## `.info`` — class `Info`. Flag `--json`. Aggregates engine/project/platforms sections.
6. `## `.info projects`` — class `Projects`. Flag `--json`. Lists branch projects via `branch.read_projects()`.
7. `## `.info config`` — class `Config`. Arg `category` (`Engine|Game|Input|DeviceProfiles|...`). Flags: `--json`, `--override` (e.g. `WinGDK`).
8. `## `.project`` — class `Change` (in `unreal/core/cmds/project.py`). Arg: `nameorpath` (special forms: `branch`, `cwd`, `active`, `list`, `auto`, or empty for fzf). Updates session noticeboard.
9. `## `.kill`` — class `Kill`. Arg: `what` (`editor|server|client|<platform>`). Flag `--wait=<minutes>`.
10. `## `.notify`` — class `Notify`. Windows-only console window flash.
11. `## `.ushell gather`` — class `Gather`. Args: `destdir`, `srcdir`. Flag `--overwrite`. Bundles standalone ushell deployment.
12. `## `.getbuild`` — class `GetBuild`. Args: `buildtype` (`packaged|staged`), `platforms`, `runargs`. Flags: many — `--project`, `--branch`, `--namespace`, `--host`, `--clean`, `--verbose`, `--preflight`, `--wildcard`, `--exclude-wildcard`, `--dest`, `--match`. Downloads build from UE Cloud Storage via Zen CLI.
13. `## `.ddc auth`` — class `Auth`. Arg: `service`, `extraargs`. Flag `--query`. Runs `OidcToken.exe`.

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): sln/info/project/kill/notify/ushell/getbuild/ddc

13 small entries covering Visual Studio solution gen, branch info,
project switching (incl. fzf form), platform-aware kill, cloud build
download, and DDC auth via OidcToken."
```

### Task 4.7: Document the `.zen` family and `.zen snapshot *`

**Files:**
- Modify: `reference/commands.md`
- Read: `cmds/zen.py`, `cmds/snapshot.py`, `pylib/zen/snapshot.py`, `pylib/zen/cmd.py`

- [ ] **Step 1: Read the zen files**

Note the split between `ZenUETargetBaseCmd` (runs a UE program target like `ZenLaunch`, `ZenDashboard`) and `ZenUtilityBaseCmd` (shells to the `zen` CLI for `zen down`, `zen status`, etc.).

- [ ] **Step 2: Append entries**

1. `## `.zen start`` — class `Start`. Flag `--SponsorProcessID=`. Runs `ZenLaunch` UE Program; defaults sponsor to PPID on Windows / grandparent PID on Unix.
2. `## `.zen stop`` — class `Stop`. Runs `zen down`.
3. `## `.zen status`` — class `Status`. Runs `zen status`.
4. `## `.zen version`` — class `Version`. Runs `zen version`.
5. `## `.zen dashboard`` — class `Dashboard`. Runs `ZenDashboard` UE Program.
6. `## `.zen createworkspace`` — class `CreateWorkspace`. Arg `base_dir`. Flag `--dynamic`.
7. `## `.zen createshare`` — class `CreateShare`. Arg `share_dir`.
8. `## `.zen importsnapshot`` — class `ImportSnapshot`. Args: `snapshotdescriptor`, `snapshotindex` (default 0). Flags: `--projectid`, `--oplog`, `--sourcehost`, `--asyncimport`, `--forceimport`.
9. `## `.zen snapshot find`` — class `Find`. Args: `runtime` (`client|server|game`), `platform`, `changelist`. Flags: `--buildroot`, `--nofileshare`, `--fileshare`, `--cloudhost`, `--flavor`, `--buildtype`. **Note the describe.flow.py variable-name crossover** noted in the codebase exploration — the invoke verbs are correct, only the Python variable names are crossed.
10. `## `.zen snapshot get`` — class `Get`. Same args + `--projectid`, `--oplog`, `--sourcehost`, `--asyncimport`, `--forceimport`. Launches ZenServer if not running, calls `build_index.get_snapshot_descriptor`, prompts on near-match CL.
11. `## `.zen snapshot list`` — class `List`. Lists available changelists; marks current with `*`.

For `.zen snapshot *`, **Preconditions** must include "logged in for `--cloudhost=` (cloud DDC OIDC token) OR fileshare reachable" and **Produces** for `.zen snapshot get` is "Zen oplog imported into running ZenServer; cooked data now available in-process."

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .zen and .zen snapshot families

11 entries. Split between ZenLaunch-driven (start/dashboard) and
zen-CLI-driven (stop/status/version) variants, plus the snapshot
trio that's the fast path for 'pull pre-cooked data for this CL'."
```

### Task 4.8: Document the `.perf` family

**Files:**
- Modify: `reference/commands.md`
- Read: `cmds/insights.py`, `cmds/perftest.py`

- [ ] **Step 1: Read both files**

`insights.py`: `Insights` class is a shim over `.run program UnrealInsights`. `perftest.py`: `PerfTestBaseCmd` + subclasses `Sequence`, `Replay`, `Material`, `StaticCamera`, `PerfTestDefault`. All shell out to `.uat RunUnreal`.

- [ ] **Step 2: Append entries**

1. `## `.perf insights`` — class `Insights`. Args: `trace` (file path, trace ident, or literal `latest`), `uiargs`. Flags: `--build`, `--attach`, `--debug`, `--noautobuild`. `latest` resolves most recent `.utrace` under `%LOCALAPPDATA%/UnrealEngine/Common/UnrealTrace/Store/001/*.utrace` (Windows only).
2. `## `.perf test default`` — class `PerfTestDefault`. Shared args from `PerfTestBaseCmd`: `platform`, `subtest`, `variant`, `target`, `uatargs`. Shared flags: `--repeat`, `--build`, `--targetname`, `--resx`, `--resy`, `--fps-chart`, `--debug-mem`, `--testid`.
3. `## `.perf test sequence`` — class `Sequence`. Extra arg `SequenceComboName` (completes from `/Script/AutomatedPerfTesting.AutomatedSequencePerfTestProjectSettings.MapsAndSequencesToTest`).
4. `## `.perf test replay`` — class `Replay`. Extra arg `ReplayFile`.
5. `## `.perf test material`` — class `Material`.
6. `## `.perf test camera`` — class `StaticCamera`. Extra arg `MapName`.

For each `.perf test *`, **Preconditions** is "Staged build at `Saved/StagedBuilds/<cook_form>/` (cook + stage already run)" and **Produces** is "Trace/CSV reports under `Saved/Profiling/` (paths controlled by the AutomatedPerfTesting plugin)."

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .perf family

.perf insights (Unreal Insights launcher with 'latest' utrace
resolution) and .perf test {default|sequence|replay|material|camera}
which shell out to UAT RunUnreal with -test=AutomatedPerfTest.* nodes."
```

### Task 4.9: Document the `.p4` family

**Files:**
- Modify: `reference/commands.md`
- Read: every file under `E:\UE_5.7\Engine\Extras\ushell\channels\unreal\perforce\cmds\`

- [ ] **Step 1: Read each command file**

The perforce channel has 12 command files: `sync.py`, `cherrypick.py`, `bisect.py`, `mergedown.py`, `switch.py`, `workspace.py`, `clean.py`, `gui.py`, `authors.py`, `who.py`, `project.py` (overrides core), and the boot/tips files.

- [ ] **Step 2: Append entries (in TOC order)**

13 entries:
1. `## `.p4 sync`` — class `Sync`. Arg `changelist` (default `now`; literal `have` reads `Engine/Build/Build.version`). Flags: `--noresolve`, `--dryrun`, `--all`, `--addprojs=`, `--clobber`, `--echo`. Honours `~/.ushell/.p4sync.txt` + `<branch>/.p4sync.txt`. Decorated `@summarise`.
2. `## `.p4 sync edit`` — class `Edit`. Opens `<root>/.p4sync.txt` in editor. Creates the file with header if missing.
3. `## `.p4 sync mini`` — class `MinSync`. Minimal engine-only sync.
4. `## `.p4 cherrypick`` — class `Cherrypick`. Args: `changelist` (list). Many flags: `--path`, `--saferesolve`, `--noresolve`, `--dryrun`, `--force`, `--novalidate`, `--alwayseddy`, `--noeddy`, `--sync`, `--virtual`, `--rawbranchspec`.
5. `## `.p4 bisect`` — class `Bisect`. Args: `good`, `bad`, `script` (list). Flags: `--dryrun`, `--silentsync`, `--clsfromcwd`. Script exit codes: 0=good, 80=bad, 90=failed-build.
6. `## `.p4 mergedown`` — class `MergeDown`. Arg `changelist` (defaults to head of parent). Flags: `--path`, `--maxscanrows`, `--dryrun`, `--noautoresolve`. Stream client required. Decorated `@summarise`.
7. `## `.p4 switch`` — class `Switch`. Args: `stream`, `changelist` (default `-1` = head). Flags: `--haveonly`, `--saferesolve`. Stream client required. Includes restore-point safety on shelved files.
8. `## `.p4 switch list`` — class `List`. Tree-prints streams under current depot.
9. `## `.p4 workspace`` — class `Workspace`. Args: `localdir`, `depotpath`. Flags: `--name`, `--dryrun`. Interactive fzf depot picker if `depotpath` empty.
10. `## `.p4 clean`` — class `Clean`. Flags: `--dryrun`, `--allsaved`, `--savedkeeps=Profiling,StagedBuilds`. Two-phase delete via rename to `.ushell_clean/`.
11. `## `.p4 reset`` — class `Reset`. Flag `--thorough` (digests not modtime). Confirmation prompt.
12. `## `.p4 authors`` — class `Authors`. Arg `path`. Flags: `--after=YYYY/mm/dd`, `--pastyear`, `--pasttwoyears`, `--time`, `--follow-integrations`, `--normalize-scores`.
13. `## `.p4 who`` — class `Who`. Args: `path` (accepts `#rev` or `@cl` suffix), `line`. Flags: `--printdiff`, `--noremap`. Chases line through integrations/moves/branches via `p4 annotate` + `p4 filelog`.
14. `## `.p4 v`` — class `Gui`. Arg `p4vargs`. Launches P4V.

For all `.p4 *` entries, **Preconditions** includes "Logged into Perforce (`p4 login -s` succeeds)" — for goal-directed planning to insert a `p4 login` step.

- [ ] **Step 3: Commit**

```bash
git add reference/commands.md
git commit -m "docs(commands): .p4 family (full perforce channel)

14 entries covering sync (with .p4sync.txt filter), cherrypick,
bisect (with 0/80/90 script protocol), mergedown, switch (stream
clients only), workspace creation, clean, authors, who, and P4V
launch. Every entry preconditions p4 login."
```

### Task 4.10: Final commands.md verification

- [ ] **Step 1: Count headings**

Run:
```powershell
(Select-String -Path E:\Work\ushell-skill\reference\commands.md -Pattern "^## ").Count
```

Expected: ~60 (template TOC excluded). If significantly below, an entry was missed — diff against the TOC in Task 4.0.

- [ ] **Step 2: Spot-check Preconditions/Produces uniformity**

Run:
```powershell
Select-String -Path E:\Work\ushell-skill\reference\commands.md -Pattern "^\*\*Preconditions:\*\*" -Context 0,3
```

Every entry should declare Preconditions. Any entry without them is incomplete — fix.

- [ ] **Step 3: Verify cross-reference correctness**

Spot check three random entries against their underlying `.py` source by opening the corresponding file and comparing arg/flag lists. Mismatches mean the entry drifted from source — fix.

- [ ] **Step 4: Commit any fixes from steps 2-3**

```bash
git add reference/commands.md
git commit -m "docs(commands): fix omissions and source-drift from verification"
```

---

## Phase 5 — reference/workflows.md (goal-first DAGs)

14 entries. Each follows the DAG template from the spec §8. The headline Insights-trace DAG (the user's motivating example) lands first.

### Task 5.1: File header, template, TOC

**Files:**
- Create: `reference/workflows.md`

- [ ] **Step 1: Write the header**

Create `reference/workflows.md`:
````markdown
# Goal-first workflows

Each entry is a **DAG**: terminal command → preconditions → recurse → execute. At planning time, read top-down. At execution time, read bottom-up, verifying each precondition before invoking the next step.

## DAG template

```
GOAL: <one-line outcome with the parameters the user supplied>

Terminal: <the command that actually produces the goal artifact>
  Preconditions:
    [A] <precondition>
        → <command(s) that satisfy it>
           Preconditions: <recurse>
    [B] <precondition>
        → <command> -- OR -- <alternative command>

Post: <where the artifact ends up, how to consume it>

Skip-conditions:
  • <how to verify [A] is already met (on-disk check, .info, .zen snapshot list, etc.)>
  • <how to verify [B] is already met>
```

The **Skip-conditions** block is what lets the planner not redo work. Each check must be verifiable without invoking ushell again.

## Index

1. **Insights trace at CL X on platform P** *(headline; the motivating example)*
2. **Reproduce a crash at CL X** (sync · build · attach)
3. **Profile shipping build on platform P at CL X**
4. **Find the CL that broke the editor** (`.p4 bisect`)
5. **Fresh sync → build → run editor** (everyday loop)
6. **Stream switch + minimal verify**
7. **Cook + stage + run on target platform with Zen**
8. **Pull pre-cooked data for this CL via `.zen snapshot get`**
9. **Cherrypick a CL across streams**
10. **Run an automated perf test (`.perf test sequence`)**
11. **Generate a Visual Studio solution and open it (with tiny fallback)**
12. **Drive a commandlet (`.run commandlet ResavePackages -- -PackageDir=…`)**
13. **Run BuildCookRun directly via `.uat`**
14. **Clean a branch safely (`.p4 clean --dryrun` → `.p4 clean`)**

---
````

- [ ] **Step 2: Commit**

```bash
git add reference/workflows.md
git commit -m "feat(skill): workflows.md template + index"
```

### Task 5.2: Insights-trace DAG (headline)

- [ ] **Step 1: Append the Insights DAG**

Append to `reference/workflows.md`:

````markdown
## 1. Insights trace at CL X on platform P, channels <ch>

```
GOAL: Insights trace at CL <C> on platform <P>, channels <ch>

Terminal: .run game <P> --trace=<ch> [-tracehost=<ip>] [--] [extra UE args]
  Preconditions:
    [A] Runtime binary built for <variant> on <P>
        → .build game <P> [<variant>]
           Preconditions:
             • Source synced to <C> if cross-CL repro
               → .p4 sync <C>      (honours <root>/.p4sync.txt + ~/.ushell/.p4sync.txt)
             • Editor built (only needed if you'll cook or stage)
               → .build editor
    [B] Cooked content for <P> matching runtime
        Pick ONE:
        → .cook game <P>                  (direct -run=cook against Editor-Cmd.exe)
        → .zen snapshot get game <P> <C>  (prebuilt; faster if available)
    [C] Staged build (skip if you'll use --cooked --datadir=)
        → .stage game <P> auto
    [D] Trace host reachable from <P>
        • PC: skip
        • Devkit: .info reports devkit IP under `platforms.<P>.env`;
                  add -tracehost=<host_ip> to the .run invocation

Post:
  • .utrace file lands in Saved/Profiling/Traces/ (or platform-specific trace
    directory). On PC, default location is
    %LOCALAPPDATA%/UnrealEngine/Common/UnrealTrace/Store/001/<timestamp>.utrace
  • Open with: .perf insights latest   (or .perf insights <ident|path>)

Skip-conditions:
  • A.runtime built  → Binaries/<P>/<Name>-<P>-<Variant>.target exists
                       AND Engine/Build/Build.version Changelist == <C>
  • A.editor built   → Binaries/<HostPlatform>/UnrealEditor.target exists
  • A.synced to <C>  → Engine/Build/Build.version "Changelist" == <C>
  • B.cooked         → Saved/Cooked/<cook_form>/ exists and is non-empty
  • B.zen snapshot   → .zen snapshot list game <P>  shows <C> or a near CL
                       AND .zen status reports running
  • C.staged         → Saved/StagedBuilds/<cook_form>/<Name>.exe exists
```

**Notes:**
- For trace channels, default to `default` if the user didn't specify; the canonical taxonomy is in `reference/unreal-args.md` §3.
- For `-tracehost=`, the *destination* host running the Insights trace server, not the *source* devkit. On a dev box this is usually the same machine — omit.
- If `[B]` chooses the snapshot path, ensure `.zen start` succeeded first; `.zen snapshot get` does this implicitly but `.zen status` is a fast precondition check.
````

- [ ] **Step 2: Commit**

```bash
git add reference/workflows.md
git commit -m "docs(workflows): Insights-trace DAG (headline)

The motivating example from brainstorming. Walks .p4 sync -> .build
editor -> .build game -> .zen snapshot {list,get} OR .cook -> .stage
-> .run game --trace -> .perf insights. Every precondition has an
explicit on-disk skip-check."
```

### Task 5.3: Reproduce a crash at CL X

- [ ] **Step 1: Append the DAG**

````markdown
## 2. Reproduce a crash at CL X

```
GOAL: Reproduce a reported crash from CL <C> with extra args <args>

Terminal: .run editor --attach -- <args>
  Preconditions:
    [A] Editor built at variant=development on host
        → .build editor
           Preconditions:
             • Source synced to <C>
               → .p4 sync <C>
    [B] Visual Studio solution open with matching .sln (for --attach to find it)
        → .sln open       (or .sln open tiny)
           Preconditions: .sln generated
             → .sln generate

Post:
  • Editor launches under debugger. Repro the crash steps; debugger breaks
    on first-chance / unhandled exception.
  • Dump goes to %LOCALAPPDATA%\UnrealEngine\Crashes\ on Windows.

Skip-conditions:
  • A.editor built → Binaries/<Host>/UnrealEditor.target exists AND
                     Build.version Changelist == <C>
  • A.synced       → Build.version "Changelist" == <C>
  • B.sln open     → Process list contains devenv.exe with matching sln
                     (or use 'vs.dte.running()' equivalent — .run editor
                     --attach handles this automatically via debuggers/vs.py)
```

**Notes:**
- Use `--attach=lldb` (or set `USHELL_DEBUGGER=lldb`) on POSIX.
- Use `--attach=rider` if Rider is preferred.
- `-WaitForDebugger` (UE switch) on the inner command halts the process *at startup* so a debugger can attach early — useful for `WinMain` / `FEngineLoop::PreInit` issues.
````

- [ ] **Step 2: Commit**

```bash
git add reference/workflows.md
git commit -m "docs(workflows): reproduce a crash at CL X"
```

### Task 5.4-5.15: The remaining 12 DAGs

For each remaining DAG (5.4 Profile shipping build, 5.5 Bisect broken CL, 5.6 Fresh sync+build+run, 5.7 Stream switch+verify, 5.8 Cook+stage+run with Zen, 5.9 Pull snapshot, 5.10 Cherrypick across streams, 5.11 Perf test sequence, 5.12 Generate VS solution, 5.13 Drive commandlet, 5.14 BCR via .uat, 5.15 Clean branch safely):

- [ ] **For each: write the DAG, commit**

Use the template from Task 5.1 and the recipe seeds from the spec §8 (workflows.md outline). Each DAG should be 15-30 lines including Goal / Terminal / Preconditions / Post / Skip-conditions. Cite reference/commands.md entries for the commands used and reference/unreal-args.md / reference/uat.md for any UE args or UAT command details. **Do not** invent flags — every flag in a DAG must exist in either commands.md, unreal-args.md, or uat.md.

Specific notes for the harder entries:
- **5.5 Bisect broken CL:** Include a sample `build-and-run.bat` that returns the 0/80/90 exit codes per `.p4 bisect`'s protocol.
- **5.11 Perf test sequence:** Cross-reference the exact UAT args from `cmds/perftest.py:217-237` (already in `research-notes-uat.md` §D.10). Note that `.perf test` requires a staged build at `Saved/StagedBuilds/<cook_form>/`.
- **5.13 Drive commandlet:** Show two forms — `.run commandlet ResavePackages -- -PackageDir=Content/Foo -AutoCheckOutPackages` (in-engine route) and `.uat ResavePackages -- -Project=<path> -PackageDir=Content/Foo` (UAT route). Note when each is appropriate (in-engine = faster, simpler, no Saved/Logs/AutomationTool noise; UAT = parity with CI).
- **5.14 BCR via .uat:** Reference `reference/uat.md` §A.6 for the canonical shipping invocation. The DAG itself just sequences `.p4 sync <C>` → `.uat BuildCookRun -- <full BCR command from uat.md>`.

After all 14 DAGs land, commit a final review:

- [ ] **Step (final): Cross-verify all 14 DAGs use only documented flags**

Run: for each DAG, scan every `-flag=` / `--flag` mentioned and confirm it appears in either `reference/commands.md`, `reference/unreal-args.md`, or `reference/uat.md`. Any flag that doesn't is either wrong or needs to be added to the reference.

Commit:
```bash
git add reference/workflows.md
git commit -m "docs(workflows): all 14 DAGs landed and cross-verified"
```

---

## Phase 6 — reference/channel-authoring.md

Anchored to real ushell source. Each section cites file:line so the doc survives engine version bumps.

### Task 6.1: File skeleton and the framework overview

**Files:**
- Create: `reference/channel-authoring.md`

- [ ] **Step 1: Write the header and overview**

Create `reference/channel-authoring.md`:
````markdown
# Authoring ushell channels

ushell is extensible. New commands live in **channels** — subdirectories under `channels/` containing a `describe.flow.py` declaration + per-command Python files. The build system enumerates channels at boot, hashes them into a binary manifest, and loads them lazily.

## Why author a channel?

- Add project-specific commands (`.mychan generate-data`, `.mychan resave-with-validation`).
- Override or extend existing commands by registering the same `.invoke()` words and chaining via `super().main()`.
- Ship build-pipeline helpers alongside the project (`.mychan ship`, `.mychan smoke-test`).

## Channel layout

```
channels/
  mychan/
    describe.flow.py          # required — declares the channel & its commands
    cmds/
      resave.py               # one file per command class
      ship.py
    pylib/                    # optional — auto-added to sys.path
      mychan/
        helpers.py
    boot.py                   # optional — runs at session boot
    prompt.py                 # optional — customises the prompt
    tips.py                   # optional — registers $tip entries
```

Channel name is derived from the directory tree: `channels/mychan/` becomes `mychan`; `channels/mr/hayes/` becomes `mr.hayes`. Multiple words map to dotted names.

The `pylib/<name>/` convention is for **shared imports**: a channel's `pylib/` is auto-added to `sys.path`, so any command can `import mychan.helpers`.

## The flow framework

Channels build on three core classes from `flow.describe`:

- **`flow.describe.Channel()`** — terminal object in every `describe.flow.py`. Declares the channel itself.
- **`flow.describe.Command()`** — binds a Python class to an invocation path (a sequence of words on the command line).
- **`flow.describe.Tool()`** — declares external binaries to be downloaded, sha1-verified, and exposed on PATH via shims.

Commands inherit from `flow.cmd.Cmd` (or its UE-aware subclass `unrealcmd.Cmd` / `unrealcmd.MultiPlatformCmd`). Args and Opts are declared as class attributes via `flow.cmd.Arg(...)` / `flow.cmd.Opt(...)`.

Source: `<ushell>/channels/flow/core/system/flow/describe.py`, `cmd.py`.
````

- [ ] **Step 2: Commit**

```bash
git add reference/channel-authoring.md
git commit -m "feat(skill): channel-authoring.md skeleton and overview"
```

### Task 6.2: `describe.flow.py` annotated example

- [ ] **Step 1: Append the annotated example**

Append to `reference/channel-authoring.md`:

````markdown
## describe.flow.py annotated

A working, minimal `describe.flow.py`:

```python
import flow.describe

# ---- A command -----------------------------------------------------------
resave = flow.describe.Command()
resave.source("cmds/resave.py", "Resave")  # file relative to channel root,
                                            # then the class name inside it.
resave.invoke("mychan", "resave")           # users type .mychan resave …
# resave.prefix(".")                         # default prefix; "$" hides from
                                            # tab completion (used for boot,
                                            # prompt, tip).

# ---- A tool (optional) ---------------------------------------------------
fzf = flow.describe.Tool()
fzf.version("0.56.3")
if bundle := fzf.bundle(platform="win32"):
    bundle.payload("https://github.com/junegunn/fzf/releases/download/v$VERSION/fzf-$VERSION-windows_amd64.zip")
    bundle.bin("fzf.exe")
    bundle.sha1("9dc22afb3a687b10eac57fe27f1a0e4d65c52944")
# $VERSION substitutes the tool.version() string into payload URLs.

# ---- The channel (terminal) ----------------------------------------------
channel = flow.describe.Channel()
channel.parent("unreal.core")    # so unrealcmd, unreal.cmdline, etc. are
                                  # available to this channel's commands.
channel.version("1")              # bump to invalidate the manifest cache
                                  # when the channel changes structurally.
# channel.pip(...)                # DEPRECATED. Do not use. Ship pure-Python
                                  # deps in pylib/; binary deps via Tool().
```

Mechanics:
- All module-level Command/Tool/Channel objects are registered just by existing in the module namespace when ushell exec's the describe script.
- Multiple Command objects may share an invoke path across parent channels — the loader builds an MRO from all matching specs. A child class's `main()` can call `super().main()` to run the parent's version. This is how `boot`/`prompt`/`tip` extension works.

Source: `<ushell>/channels/flow/core/system/flow/describe.py` and any of the engine-shipped `describe.flow.py` files for working examples.
````

- [ ] **Step 2: Commit**

```bash
git add reference/channel-authoring.md
git commit -m "docs(channel-authoring): describe.flow.py annotated"
```

### Task 6.3: Authoring a command class

- [ ] **Step 1: Append**

````markdown
## Authoring a command

Subclass `unrealcmd.Cmd` (UE-context-aware) or `unrealcmd.MultiPlatformCmd` (also injects per-platform SDK env vars). For non-UE commands, subclass `flow.cmd.Cmd` directly.

```python
# cmds/resave.py
import unreal              # for TargetType, Variant, etc.
import unrealcmd           # for Cmd, Arg, Opt
import unreal.cmdline      # for read_ueified (UE arg quoting)
import uelogprinter        # for colorised UE log output

class Resave(unrealcmd.MultiPlatformCmd):
    """Resaves packages under -PackageDir via the ResavePackages commandlet."""

    packagedir = unrealcmd.Arg(str, "Directory of packages to resave (project-relative)")
    extra      = unrealcmd.Arg([str], "Extra args forwarded to the commandlet")
    debug      = unrealcmd.Opt(False, "Use debug editor build")

    def main(self):
        self.use_all_platforms()         # populate SDK env vars
        ue = self.get_unreal_context()

        project = ue.get_project()
        if not project:
            self.print_error("Active project required (use .project <path> first)")
            return False

        target  = ue.get_target_by_type(unreal.TargetType.EDITOR)
        variant = unreal.Variant.DEBUG if self.args.debug else unreal.Variant.DEVELOPMENT
        build   = target.get_build(variant=variant)
        if not build:
            self.print_error(f"No {variant.name.lower()} editor build (run .build editor first)")
            return False

        binary = str(build.get_binary_path())
        if not binary.endswith("-Cmd.exe"):
            # Commandlets need stdout; -Cmd.exe is the console variant.
            binary = binary.replace(".exe", "-Cmd.exe")

        args = (
            project.get_path(),
            "-run=ResavePackages",
            "-PackageDir=" + self.args.packagedir,
            "-unattended",
            "-stdout",
            *unreal.cmdline.read_ueified(*self.args.extra),
        )

        cmd = self.get_exec_context().create_runnable(binary, *args)
        if not self.is_interactive():
            cmd.run()
        else:
            uelogprinter.Printer().run(cmd)
        return cmd.get_return_code()
```

Key mechanics:
- `unrealcmd.Arg(type_or_default, "description")` — required if a type is given, optional with a default. `[str]` means many-arg (zero-or-more positionals).
- `unrealcmd.Opt(default, "description")` — `--name` flag. Booleans are `Opt(False, ...)`; valued opts need a default that's not a bool.
- `complete_<argname>(self, prefix)` — generator that yields completion candidates for the `<argname>` positional. Already provided for `platform` and `variant` on `unrealcmd.Cmd`.
- `self.args.<name>` — parsed value.
- `self.args.<name> = value` — write-back, marks as "non-default" (affects env-var override).
- `self.get_unreal_context()` — returns `unreal.Context` with `get_project()`, `get_engine()`, `get_target_by_type()`, `get_target_by_name()`, `get_branch()`, `get_config()`, `get_platform_provider()`, `glob()`.
- `self.get_exec_context()` — returns env-aware launcher. `create_runnable(binary, *args)` builds a `Runnable`. `.run()` to wait; `.run2()` to capture stdout.
- Return an int exit code, a bool (True=0, False=1), or use `@flow.cmd.Cmd.summarise` decorator on `main` to auto-print "Result: Success / Failed" + elapsed time (and add `--nosummary`).
- **Don't bypass `unreal.cmdline.read_ueified()`** when forwarding args that contain `-Foo="path with spaces"` — UE's quoting differs from POSIX/Windows shells, and plain subprocess argv will mangle it.

Forbidden positional Arg types: `bool` (use `Opt`), raw `tuple` (use `[str]`).
````

- [ ] **Step 2: Commit**

```bash
git add reference/channel-authoring.md
git commit -m "docs(channel-authoring): command class authoring"
```

### Task 6.4-6.7: Remaining sections

For each, append the section and commit:

- [ ] **6.4 Driving a commandlet from your channel**

Two patterns: (A) delegate to `_run commandlet <Name>` via `subprocess.run(("_run", "commandlet", Name, "--", *args))` — gets `--attach` plumbing for free; (B) launch the `-Cmd.exe` directly as in the Resave example above. Show both, note when to use which. Cite `cmds/cook.py:78-94` (cook --attach uses pattern A) and `cmds/cook.py:96-122` (cook default uses pattern B).

- [ ] **6.5 Driving UAT from your channel**

Use `subprocess.run(("_uat", "BuildCookRun", "--", *args))` — the `_uat` internal shim re-uses ushell's UAT-build-and-launch plumbing. Don't call `RunUAT.bat` directly. Show an example BCR-from-channel pattern.

- [ ] **6.6 Deps & distribution**

`pylib/<name>/` for pure-Python deps. Binary deps via `flow.describe.Tool()` with sha1. Pips DEPRECATED — do not use. Site-level install paths: `$USERPROFILE/.ushell/`, `<branch>/Engine/Platforms/<X>/Extras/ushell/platform_*.py` for platform plugins, `.ushell gather <destdir>` to produce a standalone bundle (UGS-deployable).

- [ ] **6.7 Boot/prompt/tip hooks**

Register a `boot`/`prompt`/`tip` command with `prefix("$")` to chain into the framework's. The MRO walks parent-channels-first, so a child class's `run(env)` / `prompt(context)` / `get_tips()` overrides cleanly via `super()`. Cite `<ushell>/channels/unreal/core/boot.py`, `prompt.py`, `tips.py`.

- [ ] **6.8 Smallest viable channel template**

A copy-pasteable ~20-line template that creates a working `.mychan hello` command. The template is the seed for S4's GREEN expectation; if it changes, S4's rubric must too.

```python
# channels/mychan/describe.flow.py
import flow.describe
hello = flow.describe.Command()
hello.source("cmds/hello.py", "Hello")
hello.invoke("mychan", "hello")
channel = flow.describe.Channel()
channel.parent("unreal.core")
channel.version("1")
```

```python
# channels/mychan/cmds/hello.py
import unrealcmd
class Hello(unrealcmd.Cmd):
    """Says hello."""
    name = unrealcmd.Arg("world", "Who to greet")
    def main(self):
        ue = self.get_unreal_context()
        project_name = ue.get_project().get_name() if ue.get_project() else "(no project)"
        print(f"Hello {self.args.name} — active project is {project_name}")
        return 0
```

To install for personal use: drop into `$USERPROFILE/.ushell/channels/mychan/`. To install per-branch: drop into `<branch>/Engine/Platforms/<Anything>/Extras/ushell/` (one of the platform plugin paths) — but the cleanest path right now is per-user.

Commit after each step.

### Task 6.8: Final review

- [ ] **Step 1: Re-read the file end-to-end**

Look for placeholders. Look for invented APIs (everything cited should be in the engine tree at the path stated).

- [ ] **Step 2: Commit any fixes**

```bash
git add reference/channel-authoring.md
git commit -m "docs(channel-authoring): final review pass"
```

---

## Phase 7 — reference/troubleshooting.md

Symptom-keyed table. Each row: *Symptom* → *Likely cause* → *Resolution*. Seed from the captured baseline rationalisations in `tests/notes.md` plus the spec's seed list.

### Task 7.1: Write troubleshooting.md

**Files:**
- Create: `reference/troubleshooting.md`

- [ ] **Step 1: Write the file**

Create `reference/troubleshooting.md`:
````markdown
# Troubleshooting

Symptom-keyed. Find your error message verbatim or close to it.

## ushell session / context

### `Unable to establish an Unreal context from directory '...'`
- **Cause:** No `.uproject` reachable from CWD and noticeboard "uproject" key empty.
- **Fix:** Relaunch with `cmd.exe /d /s /c "call <ushell.bat> --project=<path>\<file>.uproject"`. Or, in an already-running ushell session, `.project <path>` then retry.

### `ushell.bat opened a new window and exited`
- **Cause:** Launched via Explorer/shortcut without scripting form. ushell.bat heuristic decided you're interactive and spawned a console.
- **Fix:** Use `cmd.exe /d /s /c "call <ushell.bat> ..."` or a `call`-from-bat scripting form. See `reference/invocation.md` §Multi-command form.

### Verb is unknown — `'.' is not recognized as an internal or external command`
- **Cause:** ushell hasn't established itself in this shell.
- **Fix:** First line of your bat must be `call <ushell.bat> --project=<...>`. PowerShell can't run `.foo` directly; go via `cmd.exe`.

## Perforce

### `No valid Perforce session found. Run 'p4 login' to authenticate.`
- **Cause:** P4 session expired or never created.
- **Fix:** `p4 login`, enter password, retry. `p4 login -s` to check.

### `Client 'X' is not a stream`
- **Cause:** `.p4 switch` / `.p4 mergedown` require a stream-based client.
- **Fix:** Either create a stream-mapped workspace (`.p4 workspace <dir> //depot/Main`) or use a different command (e.g. `.p4 sync` works on classic clients).

### `Unable to establish branch root`
- **Cause:** `p4utils.get_branch_root()` couldn't find `GenerateProjectFiles.bat` upward from the depot path. Workspace view is wrong or client unloaded.
- **Fix:** Verify the workspace view includes the engine's `GenerateProjectFiles.bat`. `p4 client -o <name>` to inspect.

### `.p4 sync` reports client is `*unknown*`
- **Cause:** `P4CLIENT` env var unset or local `.p4config.txt` is missing/wrong.
- **Fix:** Edit `<branch_root>/.p4config.txt` to set `P4CLIENT=<your client>`. Or set `$env:P4CLIENT='<your client>'` in PowerShell before launching ushell.

## Build / cook / stage

### `.cook *` hangs on shader compile
- **Cause:** XGE-based shader compilation idle or remote agents stuck.
- **Fix:** Try `.cook game <P> --noxge`. Check `.zen status` — if Zen is mid-import, the cook may be waiting. `.kill editor` to unblock.

### `.run editor --attach` shows no debugger
- **Cause:** Visual Studio detached on early hot-reload, or no VS instance is open with the matching `.sln`.
- **Fix:** `.sln open` first, then re-run with `--attach`. Or set `USHELL_DEBUGGER=vsjit` to use the just-in-time debugger.

### `.stage` complains about `ue.projectstore` mismatch
- **Cause:** Zen marker file inconsistent with requested stage style.
- **Fix:** Pick `style=pak` or `style=zen` explicitly instead of `auto`. Delete `Saved/Cooked/<form>/ue.projectstore` to reset.

### `RunUAT.bat: not found` from inside `.uat`
- **Cause:** Engine `Engine/Build/BatchFiles/` is missing — partial sync.
- **Fix:** `.p4 sync --all` to bring the engine binaries side back.

### Tab completion empty for `.build target`
- **Cause:** `Source/*.Target.cs` not synced, or `Intermediate/Build/BuildRules/*RulesManifest.json` not generated.
- **Fix:** `.p4 sync`, then `.sln generate` to populate manifests.

## UAT-specific

### `BuildPlugin` fails with "couldn't find SDK for IOS/TVOS/Android"
- **Cause:** Since 4.25, `BuildPlugin` defaults to all detected SDK platforms.
- **Fix:** Always pass `-TargetPlatforms=Win64+Linux+...` explicitly. See `reference/uat.md` §3 plugin lifecycle.

### `BuildCookRun` finishes but `-archivedirectory` is empty
- **Cause:** Project Settings → Packaging → StagingDirectory is **ignored** by UAT. Must be passed on CLI.
- **Fix:** Add `-stagingdirectory=<path> -archive -archivedirectory=<path>` to the BCR command.

### `BCR -RunAutomationTest=` reports BUILD FAILED on green tests
- **Cause:** Known fragility — the client exits before UAT polls and reports failure.
- **Fix:** Use `.uat RunUnreal -- -test=UE.EditorAutomation -RunTest="<filter>"` (Gauntlet) or drive the editor directly with `.run editor -- -ExecCmds="Automation RunTests <filter>; Quit" -ReportExportPath=<dir>`.

### CI build hangs on a modal dialog
- **Cause:** `-buildmachine` not set.
- **Fix:** Always include `-buildmachine -CrashForUAT -unattended -nop4 -NoCodeSign -utf8output -stdlog` in CI invocations. See `reference/uat.md` §6 canonical CI baseline.

## Zen

### `.zen snapshot get` says "no snapshots found for changelist X"
- **Cause:** No prebuilt cooks at that CL in the configured backend.
- **Fix:** Try `.zen snapshot find <runtime> <platform>` (nearest match) or fall back to `.cook game <platform>`.

### `.zen status` says "no server running" mid-test
- **Cause:** ZenServer was killed (often by an unrelated `.kill` or system reboot).
- **Fix:** `.zen start` to relaunch. Active oplogs may need re-importing via `.zen importsnapshot`.

## Symptom → command quick map

| Symptom | First diagnostic |
|---|---|
| Anything ushell-shaped failing | `.info` (engine, project, platforms — confirms context) |
| Perforce-shaped failing | `.p4 sync edit` to inspect filter file; `p4 set` to see env |
| Cook-shaped failing | `.zen status` (is server up?), then `.info config Engine` |
| Build-shaped failing | `.build xml` (see current BuildConfiguration.xml values) |
| Run-shaped failing | check `.sln open` already done; check `USHELL_DEBUGGER` |
````

- [ ] **Step 2: Commit**

```bash
git add reference/troubleshooting.md
git commit -m "feat(skill): troubleshooting.md

Symptom-keyed table seeded from baseline RED captures + spec seed list.
Groups: ushell session, Perforce, build/cook/stage, UAT-specific, Zen,
and a quick-diagnostic map."
```

---

## Phase 8 — reference/unreal-args.md

UE's own CLI lexicon — boot modes, FURL map URL grammar (with the `#Portal` correction), trace channels, `-ExecCmds=`, render/perf/log switches, commandlet recipes, and the goal→args quick map.

The user's seed file `ue5-launch-with-spawn-point.md` becomes §2 of this file — inlined verbatim.

### Task 8.1: Move the seed file into reference/ and write the file header

**Files:**
- Create: `reference/unreal-args.md`
- Delete: `ue5-launch-with-spawn-point.md` (its content is now inlined as §2)

- [ ] **Step 1: Read the seed file**

Read `E:\Work\ushell-skill\ue5-launch-with-spawn-point.md` so you have the exact content for §2.

- [ ] **Step 2: Create unreal-args.md with the header and TOC**

Create `reference/unreal-args.md`:
````markdown
# Unreal Engine command-line lexicon

The arguments passed **after `-- `** to ushell's `.run *` / `.cook *` / `.uat` etc. are UE's own switches — they belong to the engine binary, not to ushell. This file is the canonical list of the switches that matter.

When `reference/workflows.md` shows a step like `.run game <P> --trace=<ch> -- <UE args>`, the `<UE args>` come from here, not from imagination.

## TOC

1. Boot modes
2. Map URL syntax (FURL grammar, the `#Portal` spawn selector)
3. Trace / Insights channels
4. `-ExecCmds`
5. Rendering / windowing
6. Performance / determinism
7. Logging
8. Cooking-specific
9. Stage / run-cooked specific
10. Networking / multiplayer
11. Commandlet `-run=<Name>` recipes
12. Discovering args for a specific project
13. Goal → required UE args quick map

---
````

- [ ] **Step 3: Append §1 Boot modes**

````markdown
## 1. Boot modes

How a UE binary decides what it is:

- **First positional arg after the binary**: a `.uproject` path (project context) OR a map URL.
- `-server` — run as dedicated server.
- `-server -log` — dedicated server with stdout logging.
- `-game` — run the editor binary as standalone game (no editor UI).
- `-run=<CommandletName>` — commandlet mode. Requires the `-Cmd.exe` variant on Windows for stdout.
- `-listen` or `?Listen` (in map URL) — host as listen server.
- `-NULLRHI` — null rendering RHI (no GPU output).
- Headless automation flavour: `-nullrhi -unattended -stdout -log` (the standard tetrad).
- `-WaitForDebugger` / `-waitforattach` — HALT at startup until a debugger attaches. Use locally only; do not put in CI.

---
````

- [ ] **Step 4: Append §2 by inlining the seed file**

Read `ue5-launch-with-spawn-point.md` and append its body (starting from the `## URL grammar` heading, skip the duplicate H1) as **§2 Map URL syntax** in `unreal-args.md`. Preserve all code blocks, call-stack diagrams, and gotchas verbatim. Do not paraphrase.

After inlining, prepend a brief section header:

```markdown
## 2. Map URL syntax (FURL grammar)
```

Then the entire body of `ue5-launch-with-spawn-point.md` from `## TL;DR` through `Useful search terms: ...`.

- [ ] **Step 5: Delete the seed file from the repo root**

```powershell
Remove-Item -Path "E:\Work\ushell-skill\ue5-launch-with-spawn-point.md"
```

Update `README.md` to remove the reference to it (it's now `reference/unreal-args.md §2`).

- [ ] **Step 6: Commit**

```bash
git add reference/unreal-args.md README.md
git rm ue5-launch-with-spawn-point.md
git commit -m "feat(skill): unreal-args.md header + §1 Boot modes + §2 FURL grammar

Inlines the user-authored ue5-launch-with-spawn-point.md verbatim as
§2 (Map URL syntax). The seed file is removed from the working-tree
root; its canonical home is now reference/unreal-args.md.

The #Portal spawn-selector grammar is critical: the common LLM
hallucination of '?StartPoint=' does NOT exist. The right form is
<MapName>#<PortalTag> where the actor's PlayerStartTag matches the
portal. Resolved by AGameModeBase::FindPlayerStart_Implementation."
```

### Task 8.2: Append §3 Trace / Insights channels

- [ ] **Step 1: Append**

````markdown
## 3. Trace / Insights channels

The `-trace=<csv>` arg controls which Unreal Insights channels are emitted. Channel names (canonical taxonomy from `Engine/Source/Runtime/TraceLog/`):

| Channel | What it captures |
|---|---|
| `default` | Frame, CPU, GPU, Bookmark, Log, Memory — the "everything-on default" set |
| `log` | UE log output |
| `frame` | Frame boundaries |
| `bookmark` | `TRACE_BOOKMARK(...)` markers |
| `screenshot` | Periodic screenshots |
| `stats` | Stat group data |
| `gpu` | GPU command queue / GPU timings |
| `memory` | High-level memory allocation tracking |
| `memtag` | LLM memory tags (requires `-llm`) |
| `cpu` | CPU profiler (named scopes) |
| `animation` | Anim node ticks, blend weights |
| `slate` | UMG / Slate widget activity |
| `csv` | CSV profiler bridge |
| `file` | File I/O timings |
| `loadtime` | Asset load times |
| `savegame` | Save-game ops |
| `taskgraph` | Task-graph dependencies |
| `counters` | Generic counters |
| `regions` | Named regions for selective trace start/stop |
| `rendercommands` | RHI command lists |
| `audiomixer` | Audio mixer activity |

**Companion switches:**

- `-tracehost=<ip>` — stream trace to a live host running Unreal Insights' trace server. Default port 1980.
- `-traceFile=<path>` — write trace to a `.utrace` file on disk instead of streaming.
- `-statnamedevents` — produce CSV-friendly named events.
- `-statunitcsv` — write unit stats as CSV.

**LLM memory tracking:**

- `-llm` — enable Low-Level Memory tracker (must be compile-time-enabled in the build).
- `-llm.AutoReportMemory` — periodic memory dumps.
- Pair with `-trace=memory,memtag` to surface LLM data in Insights.

**Trace regions** (recording only a window of activity):

- `-trace.startat=<frame>` and `-trace.stopat=<frame>` — frame-bounded capture.
- Console commands: `Trace.Start`, `Trace.Stop`, `Trace.Bookmark "name"`.
````

- [ ] **Step 2: Commit**

```bash
git add reference/unreal-args.md
git commit -m "docs(unreal-args): §3 trace channels"
```

### Task 8.3-8.11: Append sections §4-§13

For each section, append per the spec §10.5 outline and commit. Each section is small (5-15 lines).

- [ ] **§4 -ExecCmds:**
  - Format: `-ExecCmds="cmd1;cmd2;Quit"` (semicolon-separated, double-quoted at the shell level).
  - Standard idioms: `-ExecCmds="Automation RunTests <filter>;Quit"`, `-ExecCmds="stat fps;stat unit"`, `-ExecCmds="ce DebugLevel 2;ToggleHUD"`.
  - When constructing from a channel (Python), pipe through `unreal.cmdline.read_ueified()` to avoid subprocess quoting mangling.

- [ ] **§5 Rendering / windowing:**
  - `-Windowed`, `-FullScreen`, `-WindowedFullScreen`.
  - `-ResX=<n>`, `-ResY=<n>`, or combined `-Resolution=<WxH>`.
  - `-RHI=<name>` or shortcuts `-DX12` / `-DX11` / `-Vulkan` / `-OpenGL`.
  - `-NoVSync`, `-FrameLimit=<fps>`, `-MaxFps=<fps>`.

- [ ] **§6 Performance / determinism:**
  - `-deterministic`, `-FixedSeed`.
  - `-StompMalloc`, `-PoisonOSMemory` (memory debug allocators).
  - `-MemoryProfiler`.
  - `-CrashForUAT` (CI: exit non-zero on crash).
  - `-NoTextureStreaming`.
  - `-AllowSoftwareRendering`.

- [ ] **§7 Logging:**
  - `-log` — engine log to console.
  - `-LogCmds="LogX Verbose, LogY VeryVerbose"` — per-category verbosity.
  - `-AbsLog=<path>` — absolute path to log file.
  - `-NoConsole`, `-stdout`.
  - `-Verbose`, `-VeryVerbose`.

- [ ] **§8 Cooking-specific:**
  - `-targetplatform=<platform>` (cook output format).
  - `-cookcultures=en+fr+de`.
  - `-iterate`, `-forcerecook=false`.
  - `-unattended`, `-unversioned`, `-stdout`.
  - `-cookonthefly`.
  - `-noxgeshadercompile`.
  - `-PackageDir=<path>` (for ResavePackages etc).
  - `-Map=<MapName>` (cook only this map).
  - `-SkipCookedPackages`.

- [ ] **§9 Stage / run-cooked specific:**
  - `-pak`, `-skipbuild`, `-skipcook`, `-skipstage`, `-deploy`.
  - `-onthefly`, `-filehostip=<ip>`.
  - `-cookflavor=<flavor>`, `-platform=`, `-config=`.

- [ ] **§10 Networking / multiplayer:**
  - `-CONNECT=<ip[:port]>` — client direct-connect.
  - `?Game=<GameModeClass>?Listen` — listen-server boot.
  - `-port=<n>`, `-multihome=<ip>`.

- [ ] **§11 Commandlet `-run=<Name>` recipes:**
  - `-run=Cook -targetplatform=Win64 -unattended -unversioned`
  - `-run=ResavePackages -PackageDir=<dir> [-AutoCheckOutPackages]`
  - `-run=DerivedDataCache -fill -unattended`
  - `-run=GenerateDistillFileSets`
  - `-run=GatherText` (localisation)
  - `-run=DumpFormalTechDebt`
  - `-run=WorldPartitionBuilder`
  - `-run=PluginCommandlet`
  - Cross-reference: `.run commandlet <Name>` (ushell wrapper) vs raw editor `-run=<Name>` (in commandlet contexts).

- [ ] **§12 Discovering args for a specific project:**
  - `Config/Default*.ini` — many feature toggles via `[Section]` overrides usable as `-ini:Engine:[/Script/Foo]:bSomething=true`.
  - `[/Script/AutomatedPerfTesting.*PerfTestProjectSettings]` — `MapsAndSequencesToTest`, `MapsToTest`, `ReplaysToTest`, `SequenceCombos` arrays feed `.perf test`.
  - `Source/<Project>/Private/<Project>GameInstance.cpp` and `*GameMode*.cpp` — project-specific `FParse::Param(FCommandLine::Get(), TEXT("Name"))` callers (the bespoke `-stresstest=`, `-modename=`, etc.).
  - Engine-side: `Engine/Source/Runtime/Launch/Private/Launch*.cpp` and `Engine/Source/Runtime/CoreUObject/Private/UObject/UObjectGlobals.cpp` for standard switches.

- [ ] **§13 Goal → required UE args quick map:**

```markdown
## 13. Goal → required UE args quick map

| Goal | UE args (after `-- ` in ushell) |
|---|---|
| Capture Insights trace to disk | `-trace=<channels> -traceFile=<path>` |
| Capture Insights trace to live host | `-trace=<channels> -tracehost=<ip>` |
| Spawn at a specific PlayerStart | `<MapName>#<PortalTag>` (matches `APlayerStart::PlayerStartTag`; **not** `?StartPoint=`) |
| Headless automation run | `-nullrhi -unattended -stdout -log` |
| Run console cmds and quit | `-ExecCmds="cmd1;cmd2;Quit"` |
| Dedicated server | `-server -log [<MapName>?Listen]` |
| Wait for debugger to attach | `-WaitForDebugger` (local only — never CI) |
| LLM memory profile | `-llm -llm.AutoReportMemory -trace=memory,memtag` |
| Force a render API | `-DX12` (or `-Vulkan`, `-OpenGL`) |
| Specific resolution | `-Windowed -ResX=1920 -ResY=1080` |
| Skip startup map | `-NoLoadStartupPackages` |
| Cook a single map only | `-run=Cook -targetplatform=<P> -Map=<MapName>` |
| Listen-server start | `<MapName>?Listen?Game=<GameModeClass>` |
| Client direct-connect | `-CONNECT=<ip:port>` |
```
````

Commit after each section:
```bash
git add reference/unreal-args.md
git commit -m "docs(unreal-args): §<N> <section name>"
```

### Task 8.12: Final verification

- [ ] **Step 1: Count sections**

Run:
```powershell
Select-String -Path E:\Work\ushell-skill\reference\unreal-args.md -Pattern "^## " | Select-Object Line
```

Expected: 13 `## N. <title>` headings.

- [ ] **Step 2: Spot-check the §2 inline**

Confirm the body of the original `ue5-launch-with-spawn-point.md` is present verbatim (call stack, code blocks, gotchas, grep starting points).

- [ ] **Step 3: Commit any cleanup**

```bash
git add reference/unreal-args.md
git commit -m "docs(unreal-args): final pass"
```

---

## Phase 9 — reference/uat.md

Substantial. Seed material lives at `docs/superpowers/specs/research-notes-uat.md` sections A, B, D, E, F, G — re-read it before each task.

### Task 9.1: File header and §1 The UAT contract

**Files:**
- Create: `reference/uat.md`

- [ ] **Step 1: Write the header + §1**

Create `reference/uat.md`:
````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add reference/uat.md
git commit -m "feat(skill): uat.md header + §1 UAT contract"
```

### Task 9.2: §2 BuildCookRun (the workhorse)

This is the largest section. Subdivide into steps for clarity.

- [ ] **Step 1: §2.1 — Seven verbs in fixed order**

Append:

```markdown
## 2. BuildCookRun

The workhorse. One UAT command that orchestrates the full build pipeline.

### 2.1 Seven verbs

In fixed order:

1. **Build** — UBT compiles targets.
2. **Cook** — editor commandlet (`-run=Cook`) produces platform-specific content.
3. **Stage** — copy cooked content + binaries to a staging directory.
4. **Package** — produce platform-native package (`.app`, `.apk`, `.ipa`, etc).
5. **Archive** — copy the package to a final archive directory.
6. **Deploy** — push to a devkit/device.
7. **Run** — launch the binary on the target.

Source: `Engine/Source/Programs/AutomationTool/Scripts/BuildCookRun.Automation.cs:258-266`.

Each verb has:
- A `-<verb>` flag to enable it (e.g. `-build`, `-cook`, `-stage`).
- A `-skip<verb>` flag to disable it (e.g. `-skipcook`).

By default, no verbs run — you opt in. The exception: BCR auto-enables some predecessors when you enable a successor (e.g. `-stage` implies the cook output exists; if not, supply `-cook` too).
```

- [ ] **Step 2: §2.2 ProjectParams flag groups**

Append (use the categorised table from `research-notes-uat.md` §A.2):

```markdown
### 2.2 ProjectParams flag catalogue

`ProjectParams.cs` is the truth source for every BCR flag. Grouped by lifecycle area:

**Build:**
- `-build`, `-skipbuild`
- `-targetplatform=`, `-platform=`, `-target=` (multi via `+`)
- `-clientconfig=`, `-serverconfig=`
- `-server`, `-noclient`, `-client`
- `-Distribution`
- `-ubtargs=<UBT-flags>` (passes through to UBT)
- `-clean`
- `-buildmachine` (critical for CI: disables modals/crash reporter)

**Cook:**
- `-cook`, `-skipcook`
- `-iterate`, `-iterativecooking`, `-iteratesharedcookedbuild`, `-fastcook`
- `-mapsonlyincook`, `-cooksinglepackage`
- `-cookflavor=`, `-CookCultures=`, `-cookoverrides=`
- `-fullcleanafteriterate`
- `-CookCommandletArgs="<passthrough>"`
- `-RunAssetNudge`
- `-mpcook=<N>` (multi-process cook)
- `-iostore`, `-zenstore`, `-nozenstore`

**Stage:**
- `-stage`, `-skipstage`
- `-stagingdirectory=<path>`
- `-stagecommandline=`, `-cmdline=`
- `-skiplevelchecks`, `-NoCleanStage`
- `-pak`, `-skippak`, `-compressed`, `-uncompressed`
- `-AdditionalStagedFiles=`
- `-CustomDeploymentHandler=`

**Package:**
- `-package`, `-skippackage`
- `-skipencryption`, `-encryptinifiles`
- `-signpak`, `-signpakid=`, `-keychain=`
- `-EncryptionIni=`
- `-zenstreaming`

**Archive:**
- `-archive`, `-skiparchive`
- `-archivedirectory=<path>`
- `-archivemetadata`

**Deploy:**
- `-deploy`, `-deploydir=`, `-deployworkspace=`

**Run:**
- `-run`, `-runargs="<inner argv>"`, `-addcmdline=`, `-cmdline=`
- `-attach`, `-nullrhi`
- `-test=<TestName>` (Gauntlet-shape; see §4)
- `-RunAutomationTest=` (legacy and fragile — prefer §4)

**CI / build-machine:**
- `-buildmachine` (must-have)
- `-CrashForUAT` (non-zero exit on engine crash)
- `-NoSign`, `-NoCodeSign`
- `-NoSubmit`
- `-buildversion=<version>`
- `-PreFlightChange=<cl>`
- `-utf8output`
- `-stdlog`

**P4:**
- `-NoP4` (no Perforce interaction)
- `-Submit`, `-AllowSubmit`
- `-WorkingCL=<cl>`
```

- [ ] **Step 3: §2.3 -pak/-iostore/-zenstore interaction**

Append (digest from `research-notes-uat.md` §A.3).

- [ ] **Step 4: §2.4 Multi-target invocations**

Append (digest §A.4).

- [ ] **Step 5: §2.5 Iterative cook gotcha**

Append (digest §A.5). Strong wording: never `-iterate` for shipping.

- [ ] **Step 6: §2.6 Canonical "build my game for shipping"**

Append the canonical invocation block (§A.6) verbatim.

- [ ] **Step 7: §2.7 Recipe gallery (15 invocations)**

Append the 15 idiomatic invocations from §A.7. Each: one-line "when to use" + full command line in a code block.

- [ ] **Step 8: §2.8 Top BCR gotchas**

Append (§A.8): StagingDirectory ignored, `-buildmachine` magic, `-platform=` vs `-targetplatform=`, `-RunAutomationTest=` fragility, `-help` is incomplete.

- [ ] **Step 9: Commit**

```bash
git add reference/uat.md
git commit -m "docs(uat): §2 BuildCookRun deep-dive

Seven verbs in execution order + full ProjectParams flag groups +
pak/iostore/zen interaction + multi-target patterns + iterative-cook
gotcha + canonical shipping invocation + 15 recipe gallery + top
BCR gotchas. Seed: research-notes-uat.md §A."
```

### Task 9.3: §3 Other UAT commands

Substantial — ~45 commands grouped by lifecycle area.

- [ ] **Step 1: §3 Plugin lifecycle (BuildPlugin)**

Append per `research-notes-uat.md` §B "Plugin lifecycle":
- `BuildPlugin` full entry: required args (`-Plugin=`, `-Package=`), critical `-TargetPlatforms=` gotcha (since 4.25), `-Rocket`, `-StrictIncludes`, engine-version locking.
- One canonical invocation in a code block.

- [ ] **Step 2: §3 Engine/tool building**

Per §B: `BuildCommonTools`, `BuildTarget`, `BuildCMakeLib`, `BuildHlslcc`, `BuildThirdPartyLibs`.

- [ ] **Step 3: §3 Project lifecycle (non-BCR)**

`SyncProject`, `SyncBinariesFromUGS`, `UpdateLocalVersion`, `OpenEditor`.

- [ ] **Step 4: §3 Content / data ops**

`ResavePackagesCommand`, `FixupRedirects`, `RebuildHLODCommand`, `RebuildLightMapsCommand`, `WorldPartitionBuilder`, `WrangleContentForDebugging`.

- [ ] **Step 5: §3 Localisation**

`Localisation`.

- [ ] **Step 6: §3 Build infra**

`BuildDerivedDataCache`, `Virtualization`, `CopySharedCookedBuild`, `CleanFormalBuilds`, `Bisect` (note: this is UAT's bisect, different from `.p4 bisect`).

- [ ] **Step 7: §3 Packaging / signing / paks**

`ExtractPaks`, `CryptoKeys`, `IPhonePackager`, `UnsignedFilesViolationCheck`.

- [ ] **Step 8: §3 Mobile / Apple**

`GenerateDSYM`, `ListMobileDevices`, `SetSecondaryRemoteMac`.

- [ ] **Step 9: §3 Multi-process / perf / utility**

`LaunchMultiServer`, `MultiClientLauncher`, `BenchmarkBuild`, `RecordPerformance`, `GetFileCommand`, `ZipUtils`, `AnalyzeThirdPartyLibs`, `ListThirdPartySoftware`, `DedupeAutomationScripts`, `MegaXGE`, `StageLiveLinkHub`.

For each command in §3, the entry follows this compact form:

```markdown
### `RunUAT <Command>`
- **Purpose:** one-line.
- **Required args:** `-X=`, `-Y=`
- **Key optional args:** ...
- **Canonical invocation:** code block.
- **Gotcha:** any community-confirmed surprise.
- **Source:** `Engine/Source/Programs/AutomationTool/Scripts/<File>.Automation.cs`
```

Commit after each step:
```bash
git add reference/uat.md
git commit -m "docs(uat): §3 <area>"
```

### Task 9.4: §4 Testing via UAT (Gauntlet RunUnreal)

- [ ] **Step 1: Append**

````markdown
## 4. Testing via UAT — Gauntlet `RunUnreal`

`RunUnreal` is THE Gauntlet entry point. No separate `RunGauntlet.cs`.

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

- `UE.EditorAutomation` — runs in-editor `FAutomationTestBase` tests; `-RunTest=<filter>` selects.
- `UE.TargetAutomation` — cooked-target automation; editor hosts, target runs.
- `UE.BootTest` / `EditorBootTest` / `TargetBootTest` — boot-to-front-end + clean exit.

### 4.4 Report output

- **No native JUnit export.** Output is JSON at `<ReportExportPath>/index.json` + HTML at `index.html` + per-test artifacts.
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

Source: `Engine/Extras/ushell/channels/unreal/core/cmds/perftest.py:217-237`.

### 4.8 Canonical CI smoke invocation

```
RunUAT RunUnreal -project=MyProject ^
  -test=UE.EditorAutomation -RunTest="Filter:Smoke" ^
  -build=editor -platform=Win64 -configuration=Development ^
  -ReportExportPath="%WORKSPACE%\AutoReport" -WriteTestResultsForHorde ^
  -MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT ^
  -NoP4 -NoSubmit
```
````

- [ ] **Step 2: Commit**

```bash
git add reference/uat.md
git commit -m "docs(uat): §4 Gauntlet RunUnreal"
```

### Task 9.5: §5 through §9

For each:
- [ ] **§5 Engine-side `Automation` exec command** — verbs (`List`, `RunTests <filter>`, `RunFilter <flag>`, `Quit`, `SoftQuit`, etc.), filter syntax (`Group:`, `StartsWith:`, `^anchor`, `anchor$`, substring). When to use this instead of Gauntlet (simple smoke from `.run editor -- -ExecCmds=`).
- [ ] **§6 Canonical shipping/CI invocations** — the §A.6 canonical block, plus the canonical plugin-packaging recipe, plus the CI flag tetrad as a named "CI baseline" snippet.
- [ ] **§7 Top community gotchas (consolidated)** — the 6 from `research-notes-uat.md` §E.
- [ ] **§8 Sources of truth** — the file table from §G.
- [ ] **§9 Public CI examples** — references to botman99/UE-AutomationTool README, vela-games CircleCI, ue5-build-project GHA, Guganana plugin CI, Jenkins + TeamCity examples.

Commit after each.

### Task 9.6: Final uat.md review

- [ ] **Step 1: Count sections**

Expected: 9 `## N.` headings.

- [ ] **Step 2: Verify recipes use only documented flags**

Spot-check three recipes; every flag should be in `ProjectParams.cs` or the appropriate `.Automation.cs`.

- [ ] **Step 3: Commit any fixes**

```bash
git add reference/uat.md
git commit -m "docs(uat): final review"
```

---

## Phase 10 — reference/buildgraph.md

Seed: `research-notes-uat.md` §C + the engine-shipped scripts at:
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/CookedEditor/EpicGames.BuildGraph.xml`
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/LiveLinkHub/EpicGames.BuildGraph.xml`
- `Engine/Binaries/DotNET/AutomationTool/AutomationScripts/Platforms/Windows/EpicGames.BuildGraph.xml`

### Task 10.1: File header and §1-§3

**Files:**
- Create: `reference/buildgraph.md`

- [ ] **Step 1: Write header + §1 What it is + §2 CLI signature + §3 Schema elements**

Use seed material from `research-notes-uat.md` §C.1, §C.2, §C.3. Quote the class-level comment from `BuildGraph.cs:206-235` verbatim.

- [ ] **Step 2: Commit**

```bash
git add reference/buildgraph.md
git commit -m "feat(skill): buildgraph.md §1-§3 (what / CLI / schema)"
```

### Task 10.2: §4 Built-in tasks reference

- [ ] **Step 1: Read the tasks directory**

```powershell
Get-ChildItem E:\UE_5.7\Engine\Source\Programs\AutomationTool\BuildGraph\Tasks\*.cs | ForEach-Object { $_.Name }
```

There are ~50 task files. Each has a `[TaskElement("ElementName", typeof(ParametersClass))]` attribute that defines the XML element name.

- [ ] **Step 2: Build the task reference table**

For each Task subclass, list:
- Element name (e.g. `<Compile>`).
- Required attrs (from `ParametersClass` properties marked `[TaskParameter]` without `Optional = true`).
- Optional attrs.
- One-sentence purpose (from the class-level comment).
- Short XML example.

Group by purpose:
- **Build:** `<Compile>`, `<CsCompile>`
- **Cook/Stage/Pak:** `<Cook>`, `<Stage>`, `<Pak>`, `<IoStore>`
- **File ops:** `<Copy>`, `<Delete>`, `<Tag>`, `<Untag>`, `<Zip>`, `<Unzip>`
- **Composition:** `<Command Name="<UATCommand>" Arguments="...">`, `<Commandlet>`
- **Artifacts:** `<CreateArtifact>`, `<CreateCloudArtifact>`
- **Cloud / deploy:** `<AwsAssumeRole>`, `<AwsEcsDeploy>`, `<DockerBuild>`, `<DeployTool>`
- **Source control:** `<Submit>`, `<Sync>`
- **Misc:** `<Log>`, `<Sleep>`, `<HordeCreateReport>`, `<Annotation>`

Aim for **at least 30 of the ~50 tasks documented** (acceptance criterion). The `<Compile>`, `<Cook>`, `<Stage>`, `<Command>`, `<Commandlet>`, `<Copy>`, `<Tag>`, `<Submit>`, `<HordeCreateReport>` set is mandatory.

- [ ] **Step 3: Commit**

```bash
git add reference/buildgraph.md
git commit -m "docs(buildgraph): §4 built-in tasks reference (30+ tasks)"
```

### Task 10.3: §5 Property/macro/include idioms

Patterns observed in the engine-shipped scripts. Show:
- `<Property>` for parameterisation; `<Option>` for CLI-exposed parameters.
- `<Macro>` + `<Expand>` for reusable XML.
- `<Include Script="..."/>` for cross-script composition.

Show one ~15-line snippet of an observed pattern from `LiveLinkHub/EpicGames.BuildGraph.xml`.

Commit.

### Task 10.4: §6 Case study CookedEditor + §7 LiveLinkHub

For each, walk through the actual shipped script:
- Read the XML.
- Describe what the script produces.
- Diagram the node graph (which nodes depend on which).
- Highlight notable patterns or idioms.
- Quote 3-5 representative XML snippets.

Commit after each.

### Task 10.5: §8 Idiomatic recipes (8 skeletons)

For each of the 8 recipes from spec §10.7:
1. Build & cook for two platforms in parallel.
2. Build a plugin, run tests, archive.
3. Sync, build editor, run automation tests, Horde report.
4. Multi-platform shipping (PC + dedicated server + mobile).
5. Nightly iterative cook.
6. Plugin marketplace packaging.
7. Per-PR validation build.
8. Cloud DDC fill.

Write a 15-30 line BuildGraph XML skeleton showing the node structure. Each must be runnable in spirit — no placeholder element names.

Commit:
```bash
git add reference/buildgraph.md
git commit -m "docs(buildgraph): §8 idiomatic recipes (8 skeletons)"
```

### Task 10.6: §9 ushell ↔ BuildGraph + §10 Gotchas

- [ ] **§9**: `.uat BuildGraph -- -script=<path> -target=<Node> [-set:Foo=Bar]`. ushell auto-injects `-project=` unless `--unprojected`.
- [ ] **§10 gotchas**: `<Command Name="BuildCookRun">` doesn't inherit `-project=` — pass explicitly. XGE/FastBuild auto-detection (`-noxge` to disable). `<Submit>` needs both `-AllowSubmit -Submit`. Shared-storage mismatch → "no output" errors. `-resume` fragile after schema changes; use `-clean -cleannode=<X>`.

Commit:
```bash
git add reference/buildgraph.md
git commit -m "docs(buildgraph): §9 ushell integration + §10 gotchas"
```

### Task 10.7: Final buildgraph.md review

- [ ] **Step 1: Count sections** (10 expected).
- [ ] **Step 2: Verify task count** (30+ in §4).
- [ ] **Step 3: Verify both case studies present** (CookedEditor + LiveLinkHub).
- [ ] **Step 4: Commit any cleanup.**

---

## Phase 11 — GREEN verification + REFACTOR

The skill is "done" when all 7 baseline scenarios pass 7/7 with the skill loaded.

### Task 11.1: Write tests/with-skill.md (the rubric)

**Files:**
- Create: `tests/with-skill.md`

- [ ] **Step 1: Write the rubric**

Create `tests/with-skill.md`:

```markdown
# GREEN scenarios with rubric

The same seven prompts from `tests/baseline.md`, re-dispatched to subagents **with the skill loaded**. Each scenario passes only if the agent hits **every** step in its GREEN expectation. Score `n/7`; below 7/7 ⇒ REFACTOR.

The skill is "loaded" by including the entire repo (SKILL.md + reference/*) in the subagent's prompt context, OR by symlinking the repo into the subagent's `~/.claude/skills/ushell/` and letting normal skill discovery load it.

## S1. Build the editor — GREEN expectation

Agent must:
1. Detect ushell at `E:\UE_5.7\Engine\Extras\ushell\ushell.bat`.
2. Invoke non-interactively: `cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .build editor"`.
3. Report the result/time summary (or `--nosummary` if it explained why).

Pass if: ushell detected AND `.build editor` invoked AND no `RunUAT.bat`/`UnrealBuildTool.exe` direct calls.

## S2. Insights trace at CL 1234567 on PS5 — GREEN expectation

Agent must walk the DAG from `reference/workflows.md` §1:
1. `.p4 sync 1234567` (verify .p4 login first).
2. Check `.info`, confirm engine + project + ps5 platform env.
3. Check editor `.target` receipt; if missing → `.build editor`.
4. Check game ps5 receipt; if missing → `.build game ps5`.
5. `.zen snapshot list game ps5` — look for hit at 1234567.
6. If hit → `.zen snapshot get game ps5 1234567`. Else → `.cook game ps5`.
7. Check `Saved/StagedBuilds/PS5`; if missing → `.stage game ps5 auto`.
8. `.run game ps5 --trace=default,gpu -- <map> [-tracehost=<host>]`.
9. `.perf insights latest`.

Pass if: all 9 steps appear in order; skip-conditions verified before each skip; the trace channels are `default,gpu` (not invented).

## S3. Bisect editor crash 1234000 → bad — GREEN expectation

Agent must:
1. Write a `build-and-run.bat` returning 0/80/90 (per `reference/commands.md` `.p4 bisect`):
   ```bat
   @echo off
   .build editor
   if errorlevel 1 exit 90
   .run editor -- -stdout -ExecCmds="Quit"
   if errorlevel 1 exit 80
   exit 0
   ```
2. Invoke `.p4 bisect 1234000 <bad> -- build-and-run.bat`.
3. Report the offending CL.

Pass if: bat present with correct exit codes; `.p4 bisect` invoked; no manual hand-syncing CLs.

## S4. Author `.mychan resave` — GREEN expectation

Agent must create:
1. `channels/mychan/describe.flow.py` registering `Channel().parent("unreal.core").version("1")` + `Command().source("cmds/resave.py", "Resave").invoke("mychan", "resave")`.
2. `channels/mychan/cmds/resave.py` subclassing `unrealcmd.MultiPlatformCmd` with `packagedir = unrealcmd.Arg(str, "...")` and `extra = unrealcmd.Arg([str], "...")`.
3. Implementation that:
   - Calls `self.use_all_platforms()`.
   - Resolves editor binary, swaps `.exe` → `-Cmd.exe`.
   - Builds args: `(project.get_path(), "-run=ResavePackages", "-PackageDir=" + self.args.packagedir, "-unattended", "-stdout", *unreal.cmdline.read_ueified(*self.args.extra))`.
   - `exec_context.create_runnable(binary, *args)`.
   - Returns `cmd.get_return_code()`.
4. Places the channel in `$USERPROFILE/.ushell/channels/mychan/` (or another documented location).

Pass if: all four pieces present and idiomatic per `reference/channel-authoring.md`.

## S5. Context recovery — GREEN expectation

Agent must:
1. Recognise the symptom matches `reference/troubleshooting.md` "Unable to establish an Unreal context".
2. Either:
   - Relaunch with `cmd.exe /d /s /c "call <ushell.bat> --project=E:\Work\MyProject\MyProject.uproject"`, OR
   - From inside an existing session, run `.project E:\Work\MyProject\MyProject.uproject`.
3. Retry `.cook game ps5`.
4. NOT delete `Saved/`, NOT edit `.uproject`, NOT restart anything.

Pass if: clean recovery via `.project` or `--project=`; no destructive moves.

## S6. Compositional Insights trace with PlayerStart + LLM — GREEN expectation

Agent must:
1. Walk the standard Insights DAG (cf. S2) for Win64 game.
2. Consult `reference/unreal-args.md`:
   - §2 for map URL grammar: `<MapName>#<Portal>` (NOT `?StartPoint=`).
   - §3 for trace channels: `default,memory,memtag,gpu` is valid.
   - §13 for LLM: `-llm -llm.AutoReportMemory`.
3. Compose: `.run game win64 --trace=default,memory,memtag,gpu -- /Game/Maps/BossArena#MainStart -llm -llm.AutoReportMemory -traceFile=Saved/Profiling/Traces/Boss.utrace -unattended -stdout`.
4. `.perf insights Saved/Profiling/Traces/Boss.utrace`.

Pass if: `#MainStart` (NOT `?StartPoint=MainStart`) AND `-llm` switches present AND `-traceFile=` not invented as `-trace-file=` or similar.

## S7. Shipping build via UAT + Gauntlet smoke — GREEN expectation

Agent must:
1. Build the BCR invocation from `reference/uat.md` §2.6 with these modifications:
   - `-target=MyProject+MyProjectServer`.
   - `-platform=Win64 -serverplatform=Linux`.
   - `-clientconfig=Shipping -serverconfig=Shipping`.
   - `-build -cook -stage -pak -iostore -compressed -package -archive`.
   - `-archivedirectory="D:\Builds\MyProject\%BUILDVER%"`.
   - `-encryptinifiles -keychain="D:\Keys\MyProject.keychain"`.
   - CI flags: `-buildmachine -CrashForUAT -NoCodeSign -unattended -nullrhi -nop4 -utf8output -stdlog`.
2. Build the Gauntlet invocation from `reference/uat.md` §4.8:
   - `RunUnreal -test=UE.TargetAutomation -RunTest="Project.Smoke"`.
   - `-build="D:\Builds\MyProject\%BUILDVER%\WindowsClient"`.
   - `-platform=Win64 -configuration=Shipping`.
   - `-ReportExportPath="D:\Builds\MyProject\%BUILDVER%\TestReport"`.
   - `-WriteTestResultsForHorde`.
   - `-MaxDuration=900 -unattended -nullrhi -stdout -FORCELOGFLUSH -CrashForUAT`.
3. Wrap both in `.uat BuildCookRun -- <BCR args>` and `.uat RunUnreal -- <Gauntlet args>` respectively.
4. Explain the JUnit caveat (no native; post-process `index.json`).
5. Note `Project.Smoke` substring-matches; suggest `^Project.Smoke$` anchors for exact.

Pass if: 7+ of the above bullets present; no `-encrypt` (the hallucinated flag); no `-RunAutomationTest=` under BCR; `-buildmachine` present.
```

- [ ] **Step 2: Commit**

```bash
git add tests/with-skill.md
git commit -m "test(GREEN): seven scenarios with rubric

Each scenario passes only if EVERY bullet in its GREEN expectation
appears in the agent's response. n/7 scoring; below 7/7 means REFACTOR
the skill until that scenario passes."
```

### Task 11.2: Dispatch GREEN subagents

- [ ] **Step 1: Dispatch all 7 in parallel**

In the executing session, use the Agent tool. Each subagent gets a prompt of the form:

```
You have access to a Windows machine with PowerShell. UE 5.7 is installed at E:\UE_5.7\ and a UE project for "MyProject" is at E:\Work\MyProject\.

The "ushell" skill is loaded. Its content is at E:\Work\ushell-skill\ — SKILL.md + reference/*.md. Read SKILL.md first, then load reference files as needed via the "Load reference when..." pointers.

Scenario:

[paste S1..S7 verbatim from tests/baseline.md]

Describe the exact commands you would run, in order, with brief justifications. Don't actually execute anything destructive. Don't ask clarifying questions — make the most reasonable assumption and proceed.
```

- [ ] **Step 2: Score each response against the rubric in `tests/with-skill.md`**

For each scenario, tick every bullet that's present. Count how many bullets per scenario hit. A scenario passes only at full bullets-met.

Append the scoring to `tests/notes.md`:

```markdown
## GREEN scoring (run 1)

| Scenario | Bullets met | Pass? |
|---|---|---|
| S1 | x/y | yes/no |
| S2 | x/y | yes/no |
...

## Verbatim GREEN transcripts

### S1
[paste]

### S2
[paste]
...
```

- [ ] **Step 3: Identify failures**

For every scenario that's not 100%, note the specific bullet(s) missed and a hypothesis for which skill section is missing/weak.

### Task 11.3: REFACTOR for each failing scenario

For each failure:

- [ ] **Step 1: Read the relevant skill section**

If S2 failed because the agent didn't check `.zen snapshot list`, the relevant section is `reference/workflows.md §1`'s skip-conditions block — verify it's there.

- [ ] **Step 2: Plug the loophole**

Add the missing rule, table row, troubleshooting entry, or DAG annotation. The fix must address the specific rationalisation, not a hypothetical one.

- [ ] **Step 3: Re-dispatch the failing scenario(s)**

Use a fresh subagent (no memory of the previous run) and rescore.

- [ ] **Step 4: Repeat until 7/7**

If a fix doesn't move the score, the fix doesn't actually plug the loophole — try a different angle. Common second-pass fixes:
- Add an explicit "DON'T" in the relevant section (rationalisations beat polite suggestions).
- Move a key fact from a reference file into SKILL.md (always-loaded).
- Add a Red Flag entry to SKILL.md's anti-patterns.

- [ ] **Step 5: Commit each fix as its own commit**

```bash
git commit -m "refactor(skill): plug <specific loophole> for S<N>"
```

### Task 11.4: Capture final scoring

- [ ] **Step 1: Final rescore**

When all 7 pass, append a "Final scoring" block to `tests/notes.md`:

```markdown
## Final scoring (passing run)

All 7 scenarios pass 7/7.

Date: <YYYY-MM-DD>
Total subagent runs across all REFACTOR cycles: <N>
Number of skill content commits during REFACTOR: <N>
```

- [ ] **Step 2: Commit (with-skill.md only; notes.md stays gitignored)**

If with-skill.md was edited during REFACTOR (e.g. to clarify a rubric bullet), commit it:

```bash
git add tests/with-skill.md
git commit -m "test(GREEN): final rubric snapshot at 7/7"
```

---

## Phase 12 — Install

### Task 12.1: Install to ~/.claude/skills/ushell/

- [ ] **Step 1: Copy or symlink**

Pick one of:

```powershell
# Option A: copy (independent of working tree)
Copy-Item -Path "E:\Work\ushell-skill\SKILL.md","E:\Work\ushell-skill\reference" `
  -Destination "$env:USERPROFILE\.claude\skills\ushell\" -Recurse -Force

# Option B: symlink (single source of truth — recommended)
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\skills" -Force | Out-Null
New-Item -ItemType SymbolicLink `
  -Path "$env:USERPROFILE\.claude\skills\ushell" `
  -Target "E:\Work\ushell-skill"
```

(Symlinks may require Developer Mode or an elevated PowerShell on Windows.)

- [ ] **Step 2: Verify discovery**

Run from a fresh PowerShell:
```powershell
Get-ChildItem "$env:USERPROFILE\.claude\skills\ushell\SKILL.md"
```

Expected: file is present and readable.

### Task 12.2: Fresh-session smoke test

- [ ] **Step 1: Open a new Claude Code session**

Start a completely new Claude Code session (not this one). Confirm the skill is in the list of available skills (in a system reminder or by typing `/help`).

- [ ] **Step 2: Ask the bare-bones question**

In the fresh session, ask:
```
Working in E:\Work\MyProject (UE 5.7 with engine at E:\UE_5.7). Build the editor.
```

Expected: Claude invokes the `ushell` skill, detects `Engine/Extras/ushell/ushell.bat`, runs `.build editor` via the non-interactive form.

If the skill doesn't activate, check:
- `~/.claude/skills/ushell/SKILL.md` exists.
- The frontmatter `name:` and `description:` match what the rest of the file expects.

### Task 12.3: Tag the release

- [ ] **Step 1: Tag**

```bash
git tag -a v1.0 -m "v1.0: skill passes 7/7 GREEN

First production-ready release of the ushell Claude Code skill.
Covers usage (~60 verbs across unreal/core + unreal/perforce),
channel authoring, UAT/BuildGraph fluency, and goal-directed planning.
All seven baseline scenarios (S1-S7 in tests/baseline.md) pass the
GREEN rubric in tests/with-skill.md."
```

- [ ] **Step 2: Merge to main**

```bash
git checkout main
git merge --no-ff feat/skill-implementation -m "Merge skill implementation

Lands the first working version of the ushell skill. Passes 7/7
against the RED/GREEN test rubric."
```

- [ ] **Step 3: (Optional) Push to a remote**

If a remote is configured later:
```bash
git remote add origin <url>
git push -u origin main --tags
```

---

## Acceptance checklist (from spec §15)

Before declaring the skill "done", verify each:

- [ ] `SKILL.md` ≤300 words of prose (excluding the quick-reference table). Run `wc -w` over the file with the table stripped to verify.
- [ ] All ~60 registered ushell verbs have entries in `reference/commands.md` with `**Preconditions:**` and `**Produces:**` fields.
- [ ] `reference/workflows.md` has ≥12 goal-first DAGs including the Insights-trace example as §1.
- [ ] `reference/unreal-args.md` covers boot modes, the FURL map URL grammar (with `#Portal`), the trace-channel taxonomy, `-ExecCmds`, LLM switches, render/window switches, common commandlet recipes, and the goal→UE-args quick map.
- [ ] `ue5-launch-with-spawn-point.md` content was inlined into `reference/unreal-args.md` §2 verbatim.
- [ ] `reference/uat.md` covers the seven BCR verbs in execution order, the ProjectParams flag groups, ≥12 of the 15 BCR recipes, the BuildPlugin `-TargetPlatforms=` gotcha, the Gauntlet recipes including Project.Smoke, the `.perf test` → `RunUnreal -test=AutomatedPerfTest.*` mapping, the JUnit caveat, the CI flag tetrad as a named recipe.
- [ ] `reference/buildgraph.md` covers the `RunUAT BuildGraph` CLI, every schema element, ≥30 of ~50 built-in tasks (with `<Compile>`, `<Cook>`, `<Stage>`, `<Command>`, `<Commandlet>`, `<Copy>`, `<Tag>`, `<Submit>`, `<HordeCreateReport>` mandatory), both case studies (CookedEditor + LiveLinkHub), ≥5 of the 8 recipe skeletons, the ushell `.uat BuildGraph` integration.
- [ ] All seven RED scenarios produced verbatim baseline notes in `tests/notes.md` BEFORE any SKILL.md or reference content was written.
- [ ] All seven with-skill scenarios pass 7/7 with no manual hint beyond loading the skill.
- [ ] Skill installed at `~/.claude/skills/ushell/` and loads in a fresh Claude Code session (verified by Task 12.2's smoke test).
- [ ] Git tag `v1.0` exists on the merge commit.

---

## Notes for the executing engineer

- **The spec is the contract.** Don't restructure SKILL.md sections or rename reference files. If a structural change seems desirable, raise it before changing it; the test rubric in `with-skill.md` is calibrated to the current shape.
- **Cite the engine tree.** Every commands.md entry says "Source: <path/file.py>". Don't paraphrase the engine; quote it. If the engine has moved or renamed something in your install, surface the discrepancy.
- **Don't invent flags.** If a flag isn't in the engine source, it doesn't exist. Skill content that teaches Claude to use a non-existent flag is worse than no skill at all.
- **Frequent commits.** One commit per task minimum; one per step is also fine. Atomic commits make the eventual `git log` legible and let any single bad change be reverted without dragging good ones with it.
- **RED notes are gold.** `tests/notes.md` is the highest-signal artefact in this whole project. Re-read it before writing each SKILL.md section.
- **REFACTOR is the bulk of Phase 11.** First-pass GREEN scoring is rarely 7/7. Expect to iterate 2-5 times per failing scenario. The skill is bulletproof exactly when no rationalisation survives the rubric.





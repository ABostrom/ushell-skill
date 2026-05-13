# Onboarding — first session with the ushell skill

You're a developer new to Unreal Engine, or new to **ushell** (Epic's CLI for UE), or new to Claude Code. This doc gets you from zero to "I can drive my UE project from Claude" in about 15 minutes.

If you've used the skill before and just want recipes, jump to [`cookbook.md`](cookbook.md).

---

## Prerequisites

You need all four:

1. **An installed Unreal Engine 5.x** at a path like `E:\UE_5.7\` (Windows) or `/Applications/Epic Games/UE_5.7/` (macOS) or `/opt/unrealengine/` (Linux). The engine must include `Engine/Extras/ushell/` — every UE 5.x release ships with it.
2. **A `.uproject`** somewhere on disk. If you don't have one yet, create a blank C++ project from the Epic Games Launcher first.
3. **Claude Code** installed and authenticated. Either the CLI (`claude` on PATH) or one of the desktop/IDE variants.
4. **PowerShell on Windows** (the canonical scripting host for ushell) or **bash/zsh on POSIX**.

Optional but recommended:
- **Perforce** (`p4` on PATH) if your project is in P4. The `.p4` verbs need it.
- **Visual Studio 2022** (Windows) for C++ debugging — only if you'll use `.run editor --attach`.

---

## Step 1: Install the skill

The skill installs through Claude Code's plugin manager — two slash-commands from inside any Claude Code session:

```
/plugin marketplace add ABostrom/ushell-skill
/plugin install ushell@ABostrom-skills
```

The first command registers the marketplace; the second installs the plugin. Both work cross-platform (Windows, macOS, Linux). No clone, no symlink, no PATH munging.

**Verify** the install from inside Claude Code:

```
/plugin list
```

`ushell@ABostrom-skills` should appear with version `2.0.0`. You can also just ask Claude *"do you have the ushell skill loaded?"* — if yes, the skill's description should auto-include itself in the answer.

> **Upgrading from v1.x?** Delete the old symlink first:
> ```powershell
> Remove-Item "$env:USERPROFILE\.claude\skills\ushell"
> ```
> Then run the two `/plugin` commands above. The plugin manager takes over update management; future versions arrive via `/plugin update`.

---

## Step 2: Open Claude Code in your project

```powershell
cd E:\Work\MyProject     # or wherever your .uproject is
claude                   # launch Claude Code CLI; or open the IDE
```

In your first message to Claude, you don't need to do anything special — the skill **auto-activates** whenever the conversation involves Unreal Engine. Triggering phrases (from `SKILL.md`'s description):

- "build the editor"
- "cook the game for ..."
- "package for shipping"
- "trace the game at this CL"
- "sync from Perforce"
- "run UAT" / "BuildCookRun"
- mention of `.uproject`, `Engine/Extras/ushell`, or `RunUAT.bat`
- asking how to add a ushell command / channel

When the skill activates, Claude will read SKILL.md (~12 KB, ~250 words of prose + a quick-reference table) and follow its rules. Reference files are loaded on demand.

---

## Step 3: Five tasks to try first

These are the workflows that exercise the most of the skill on a fresh project.

### 3.1 Get the editor running

Ask Claude:

> Build the editor for `E:\Work\MyProject` (UE 5.7 at `E:\UE_5.7`).

What Claude will produce:

```powershell
cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\MyProject\MyProject.uproject && .build editor --nosummary"
```

Approve and run. ~2-20 minutes depending on whether anything's cached. When it finishes, ask:

> Now launch the editor.

Claude appends `&& .run editor` (or runs `.run editor` separately).

### 3.2 Generate a Visual Studio solution

Ask:

> Generate the VS solution for this project and open it.

Claude: `.sln generate open` (or `.sln open tiny` for Blueprint-only projects).

### 3.3 Drive a commandlet

UE commandlets are non-interactive editor jobs. ResavePackages is a good test — it walks every package in a directory and re-saves it (forcing version upgrades).

Ask:

> Resave all the packages under `Content/Maps` in MyProject.

Claude: `.run commandlet ResavePackages -- -PackageDir=Content/Maps`.

### 3.4 If you have Perforce: sync and look at branch state

Ask:

> What state is this project in? Show me the current CL and which branch we're on.

Claude: `.info` first (reports engine version, project name, platforms, branch, CL).

Then:

> Sync the project to head.

Claude: `.p4 sync` (honours your `<branch>/.p4sync.txt` filter if present).

### 3.5 Goal-directed planning — Insights trace

This is the showcase. Ask:

> Capture an Insights trace of the game on Windows, channels default+gpu, save it and open it.

Claude will:
1. Walk backwards from the terminal (`.run game win64 --trace=default,gpu` opens the trace).
2. List preconditions: built game, cooked content, staged build, sync to a known CL if applicable.
3. **Check `.zen snapshot list game win64`** to see if a pre-built snapshot exists (faster than cooking).
4. Either `.zen snapshot get` OR `.cook game win64`, depending.
5. `.stage game win64 auto`.
6. `.run game win64 --trace=default,gpu`.
7. `.perf insights latest` to open the resulting `.utrace`.

This is the workflow the skill was designed for. Without the skill, baseline Claude would jump to `RunUAT.bat BuildCookRun ...` and miss the snapshot fast-path entirely.

---

## Step 4: How to read Claude's responses

When the skill is engaged, Claude's responses follow a predictable structure:

1. **Reasoning** (goal-directed analysis, working backwards from terminal command).
2. **Preconditions** (what needs to be true; how to check on disk).
3. **Command sequence** (the actual `cmd.exe /d /s /c "..."` invocations).
4. **Skip-conditions** (which steps to drop if their precondition is already met).
5. **Failure-policy** (if a step fails, what to surface and what NOT to do — no destructive auto-recovery).

If Claude **doesn't** produce a structured response, the skill isn't engaged. Verify with `/plugin list` inside Claude Code — `ushell@ABostrom-skills` should be present. If it is and Claude still isn't using it, mention "ushell" or "UE project" explicitly in your prompt to trigger the description match.

---

## Step 5: When something goes wrong

The most common first-week issue is **"Unable to establish an Unreal context from directory ..."**. This happens because ushell's session noticeboard is keyed by `$FLOW_SID` — a fresh shell invocation has an empty noticeboard, and ushell can't find your `.uproject` from CWD.

**Fix:** always pass `--project=<absolute path>` to `ushell.bat`. The skill's invocations always do this; it only bites when you're constructing a command by hand.

Other common issues:

| You see | Cause | Fix |
|---|---|---|
| `'.' is not recognized as an internal or external command` | ushell hasn't established itself in this shell | first line of your bat must be `call <ushell.bat> --project=<...>` |
| `No valid Perforce session found` | P4 ticket expired | `p4 login`, retry |
| `Client 'X' is not a stream` | `.p4 switch` / `.p4 mergedown` need stream clients | create a stream-mapped workspace |
| `.cook *` hangs on shader compile | XGE / Zen / DDC waiting | `.zen status`, try `--noxge`, `.kill editor` to unblock |
| `BuildPlugin` fails on Android/iOS SDK | Since 4.25, BuildPlugin tries every SDK by default | pass `-TargetPlatforms=Win64+...` |

Full symptom-keyed list: [`reference/troubleshooting.md`](../skills/ushell/reference/troubleshooting.md).

---

## Step 6: When you're ready to extend the skill

Three paths:

### A. Add your own ushell verb (`.mychan <verb>`)

You want a project-specific verb. See [`reference/channel-authoring.md`](../skills/ushell/reference/channel-authoring.md) for the full guide; the smallest viable channel is:

```
$USERPROFILE\.ushell\channels\mychan\
    describe.flow.py
    cmds\
        hello.py
```

Cookbook recipe: ["Author a new ushell verb"](cookbook.md#author-a-new-ushell-verb).

### B. Add a new test scenario

You hit a workflow the skill doesn't cover well. Want to capture it:

1. Append the verbatim prompt to `tests/baseline.md` as `S14` (or next available).
2. Add a GREEN rubric to `tests/with-skill.md`.
3. Dispatch a RED subagent (no skill loaded) and capture into `tests/notes.md`.
4. Dispatch a GREEN subagent (skill loaded) and score against the rubric.
5. If GREEN fails, REFACTOR the skill content to plug the loophole, then re-test.

`tests/run-green.ps1 -Scenarios S14` prints the dispatch instructions.

### C. Contribute back

If the gap is general (not project-specific), open a PR against [github.com/ABostrom/ushell-skill](https://github.com/ABostrom/ushell-skill). The skill stays accurate through community contribution as UE evolves.

---

## What the skill is and isn't

**Is:** a Claude Code skill that teaches Claude to drive UE 5.x build infrastructure through ushell — competently, with goal-directed planning, with source-cited flag knowledge, and with named-hallucination defences.

**Isn't:**
- A replacement for understanding UE. You still need to know what a cook is, what a target is, what `Saved/StagedBuilds/` contains.
- A tool that runs autonomously without your approval. Claude will propose commands; you approve and run.
- A guarantee against engine-source changes. UE 5.8 will rename things; the citation footers in commands.md make drift visible and fast to fix.
- A substitute for asset workflows. Editing Blueprints, importing FBX, configuring lighting — none of that is in scope.

---

## Reading further

In order of how often you'll use them:

1. **[`cookbook.md`](cookbook.md)** — recipes for common workflows.
2. **[`reference/troubleshooting.md`](../skills/ushell/reference/troubleshooting.md)** — when something goes wrong.
3. **[`reference/commands.md`](../skills/ushell/reference/commands.md)** — per-verb flag reference.
4. **[`reference/workflows.md`](../skills/ushell/reference/workflows.md)** — goal-first DAGs.
5. **[`how-it-works.md`](how-it-works.md)** — architecture + design philosophy.
6. **[`before-and-after.md`](before-and-after.md)** — side-by-side RED vs GREEN proof.
7. **[`SKILL.md`](../skills/ushell/SKILL.md)** — the always-loaded surface itself. Read it cover-to-cover; it's short.

---

## A final sanity check

Run this from any directory:

```powershell
cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\MyProject\MyProject.uproject && .info --nosummary"
```

If it prints engine version + project name + a `platforms.<name>.env` block, you're set up correctly. Ask Claude to walk you through one of the Step 3 tasks, and you're off.

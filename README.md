# ushell skill

A Claude Code skill for driving [ushell](https://dev.epicgames.com/documentation/unreal-engine/how-to-use-ushell-for-unreal-engine) — Epic's command-line interface for Unreal Engine, shipped at `<branch>/Engine/Extras/ushell/`.

When the skill is loaded, Claude reasons backward from your stated goal (*"get me an Insights trace at this CL on PS5"*) to a sequence of ushell commands — checking preconditions, skipping work already done, and stopping cleanly if anything is unreachable. Without it, Claude defaults to raw `RunUAT.bat` / `UnrealBuildTool.exe` / `p4` invocations and sometimes invents non-existent flags.

**Status:** v1.1 — passes 13/13 GREEN scenarios on first dispatch, no REFACTOR cycles needed.

---

## Quick start

```powershell
# Clone + symlink into Claude Code's skills folder
git clone https://github.com/ABostrom/ushell-skill C:\Work\ushell-skill
New-Item -ItemType SymbolicLink `
    -Path "$env:USERPROFILE\.claude\skills\ushell" `
    -Target "C:\Work\ushell-skill"

# Open Claude Code in your UE project
cd E:\Work\MyProject
claude
```

Then ask Claude to build, cook, run, trace, package, bisect, etc. The skill activates whenever the conversation involves Unreal Engine (specifically when prompts mention `.uproject`, `RunUAT`, `BuildCookRun`, `Engine/Extras/ushell`, `p4`, `Insights`, cooking, staging, packaging, plugin building, channel authoring, etc.).

Full walkthrough: [`docs/onboarding.md`](docs/onboarding.md).

---

## What it does

Three concrete examples of the skill in action:

### Without the skill
> *Build the editor.*
>
> Claude → `Build.bat -projectfiles ...` + `Build.bat MyProjectEditor Win64 Development -Project=... -WaitMutex -FromMsBuild`

### With the skill
> *Build the editor.*
>
> Claude → `cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .build editor --nosummary"`

### Without the skill
> *Trace at CL 1234567 on PS5.*
>
> Claude → linear `p4 sync`, `Build.bat`, `RunUAT.bat BuildCookRun -build -cook -stage -package -deploy -run`. Always cooks.

### With the skill
> *Trace at CL 1234567 on PS5.*
>
> Claude → `.p4 sync 1234567` → `.build editor` → `.build game ps5` → **`.zen snapshot list game ps5`** → if hit, `.zen snapshot get ...` (50× faster than cooking); else `.cook game ps5` → `.stage game ps5 auto` → `.run game ps5 --trace=default,gpu` → `.perf insights latest`.

### Without the skill
> *Insights trace at the `MainStart` PlayerStart.*
>
> Claude → `/Game/Maps/BossArena?PlayerStartTag=MainStart` (which is **not a real UE switch**).

### With the skill
> *Insights trace at the `MainStart` PlayerStart.*
>
> Claude → `/Game/Maps/BossArena#MainStart` (the real `FURL.Portal` segment, cited to `URL.cpp`).

For the full RED-vs-GREEN gallery: [`docs/before-and-after.md`](docs/before-and-after.md).

---

## Repo layout

```
.
├─ SKILL.md                              Always-loaded skill body (~250 words prose + lookup table)
├─ reference/                            On-demand reference files:
│  ├─ commands.md                        Per-command pages (78 verb entries with
│  │                                     Preconditions + Produces fields)
│  ├─ invocation.md                      Driving ushell non-interactively
│  ├─ workflows.md                       14 goal-first DAGs (the headline being
│  │                                     the Insights-trace pipeline)
│  ├─ channel-authoring.md               Writing new ushell verbs
│  ├─ troubleshooting.md                 Symptom-keyed diagnostics
│  ├─ unreal-args.md                     UE's own CLI lexicon — FURL grammar,
│  │                                     trace channels, -ExecCmds, LLM, etc.
│  ├─ uat.md                             UAT deep-dive (BuildCookRun, BuildPlugin,
│  │                                     RunUnreal/Gauntlet, ~45 other scripts)
│  └─ buildgraph.md                      BuildGraph schema + 30+ tasks + recipes
├─ docs/
│  ├─ onboarding.md                      New-developer walkthrough
│  ├─ cookbook.md                        User-facing recipe gallery
│  ├─ how-it-works.md                    Architecture + design philosophy
│  ├─ before-and-after.md                Concrete RED-vs-GREEN proof
│  └─ superpowers/
│     ├─ specs/2026-05-13-ushell-skill-design.md          Design spec
│     ├─ specs/research-notes-uat.md                       UAT research digest
│     └─ plans/2026-05-13-ushell-skill-implementation.md   13-phase plan
└─ tests/
   ├─ baseline.md                        13 RED scenarios (verbatim user prompts)
   ├─ with-skill.md                      13 GREEN rubrics (bullet thresholds)
   └─ run-green.ps1                      Helper: prints dispatch instructions for
                                         a Claude Code Agent tool call
```

---

## Coverage

**78 ushell verbs documented** across the `unreal/core` and `unreal/perforce` channels, including:

- **Build:** `.build editor / game / client / server / program / target / clean *` + `.build xml / xml edit / xml set / xml clear` + `.build misc clangdb`
- **Run:** `.run editor / commandlet / program / target / server / client / game`
- **Cook:** `.cook` + `.cook game / client / server` + `.cook odsc client / game / all`
- **Stage / deploy:** `.stage`, `.deploy`
- **UAT:** `.uat <Command>` — the gateway to BuildCookRun, BuildPlugin, BuildGraph, RunUnreal, etc.
- **Solutions:** `.sln generate / open / open 10x / open tiny`
- **Info / project:** `.info`, `.info projects`, `.info config`, `.project`
- **Zen:** `.zen start / stop / status / version / dashboard / createworkspace / createshare / importsnapshot` + `.zen snapshot find / get / list`
- **Perf:** `.perf insights`, `.perf test default / sequence / replay / material / camera`
- **Perforce:** `.p4 sync / sync edit / sync mini / cherrypick / bisect / mergedown / switch / switch list / workspace / clean / reset / authors / who / v`
- **Misc:** `.kill`, `.notify`, `.ushell gather`, `.getbuild`, `.ddc auth`

Plus deep coverage of:

- **UAT BuildCookRun** — full ProjectParams flag catalogue, the 7 verbs in execution order, multi-target patterns, pak/iostore/zen interaction, 15 recipe gallery, top community gotchas.
- **Gauntlet RunUnreal** — test driving with `UE.EditorAutomation` / `UE.TargetAutomation` / `UE.BootTest`, report output (JSON, no native JUnit), failure modes.
- **BuildGraph** — full schema, ~50 built-in tasks (30+ documented in detail), CookedEditor + LiveLinkHub case studies, 8 recipe skeletons.
- **UE's own CLI lexicon** — boot modes, `FURL` map URL grammar (with the critical `#Portal` spawn-selector grammar), `-trace=` channel taxonomy, `-ExecCmds=`, LLM, render/perf/log switches, commandlet recipes.

---

## Testing

The skill is built test-first per `superpowers:writing-skills`. 13 baseline scenarios in `tests/baseline.md`, scored against bullet rubrics in `tests/with-skill.md`. All 13 pass on first GREEN dispatch — no REFACTOR cycles needed.

Re-run the GREEN suite (or any subset) with:

```powershell
.\tests\run-green.ps1                       # all 13 scenarios
.\tests\run-green.ps1 -Scenarios "S2,S6,S9" # subset
.\tests\run-green.ps1 -OpenRubric           # open scoring file too
```

The script prints the verbatim dispatch instructions for an Agent tool call. Run each from a Claude Code session and score against `tests/with-skill.md`.

---

## Reading order

1. **[`docs/onboarding.md`](docs/onboarding.md)** — first session walkthrough.
2. **[`docs/before-and-after.md`](docs/before-and-after.md)** — concrete RED-vs-GREEN proof from real transcripts.
3. **[`docs/cookbook.md`](docs/cookbook.md)** — user-facing recipes for common workflows.
4. **[`docs/how-it-works.md`](docs/how-it-works.md)** — architecture + design philosophy.
5. **[`SKILL.md`](SKILL.md)** — the always-loaded surface itself.
6. **`reference/*.md`** — when you have a specific question.

---

## Contributing

The skill stays accurate through engine-version drift via:
- **Source-code citations** on every commands.md entry, every uat.md flag group, every unreal-args.md grammar rule.
- **Behavioural tests** (not unit tests) — `tests/with-skill.md` describes outcomes, not API.

When UE 5.8+ ships and something drifts:

1. Re-run `tests/run-green.ps1` against the new engine — failing scenarios show what drifted.
2. Update the affected `reference/<file>.md` entries; citations point you at the right source files.
3. Re-dispatch GREEN until 13/13 again.
4. Submit a PR.

If you've found a new failure mode worth testing, append a new scenario to `tests/baseline.md` and add its rubric to `tests/with-skill.md`. See [`docs/onboarding.md`](docs/onboarding.md) §Step 6 for the detailed flow.

---

## License

[Add license here]

---

## Acknowledgements

Built with [Claude Code](https://claude.com/claude-code) following the [superpowers](https://github.com/obra/superpowers) brainstorming → writing-plans → subagent-driven-development workflow. Authored against UE 5.7's ushell source at `Engine/Extras/ushell/` and a comprehensive UAT/BuildGraph research pass captured in `docs/superpowers/specs/research-notes-uat.md`.

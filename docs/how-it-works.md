# How the ushell skill works

This doc explains the architecture of the skill — what's loaded when, why the structure is the way it is, and how the TDD discipline keeps it accurate as Unreal Engine evolves.

If you just want recipes, see [`cookbook.md`](cookbook.md). If you want to install and use it, see [`onboarding.md`](onboarding.md).

---

## Two-layer architecture

```
┌─────────────────────────────────────────────────────────┐
│  SKILL.md  (always loaded)                              │
│  ~12 KB · iron rules, detection gate, quick-reference   │
│  table (~55 verbs), goal-directed planning rule,        │
│  anti-patterns. Loaded into every Claude Code session   │
│  where the description triggers.                        │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Claude follows "Load reference when…" pointers
                          ▼
┌─────────────────────────────────────────────────────────┐
│  reference/*.md  (loaded on demand)                     │
│  ~180 KB across 8 files. Each addresses one specific    │
│  task type. Only loaded when SKILL.md tells Claude to.  │
│                                                         │
│  • commands.md       ~59 KB · 78 verb pages, each with  │
│                              Preconditions + Produces   │
│  • invocation.md     ~5 KB  · driving ushell non-       │
│                              interactively              │
│  • workflows.md      ~18 KB · 14 goal-first DAGs        │
│  • channel-authoring.md  · writing new .verbs           │
│  • troubleshooting.md    · symptom-keyed                │
│  • unreal-args.md    ~17 KB · UE's own CLI lexicon      │
│                              (incl. FURL #Portal)       │
│  • uat.md            ~28 KB · UAT deep-dive             │
│  • buildgraph.md     ~24 KB · BuildGraph schema +       │
│                              recipes                    │
└─────────────────────────────────────────────────────────┘
```

### Why this split

A naive skill would put everything in one file. Two problems with that:

1. **Token cost.** Always-loaded content is paid for every conversation, even ones where the skill isn't used. A 200 KB skill loaded into every session is expensive.
2. **CSO (Claude Search Optimisation).** When Claude has too much always-loaded content, it can short-circuit — skim the table of contents and not load the section that actually matters. Better: keep the always-loaded surface small enough to read cover-to-cover, and route to specific reference files via explicit pointers.

The skill's always-loaded body is **~250 words of prose + a lookup table**. That's enough to:
- Decide whether to engage at all (the description + detection gate).
- Know the right verb for ~55 common tasks (the quick-reference table).
- Know how to invoke ushell non-interactively (the recipe).
- Know how to plan from a goal backwards (the rule + pointer to workflows.md).
- Know what NOT to do (the anti-patterns list, naming specific hallucinations to avoid).

Anything deeper — *what does `--iterate` actually do?* — lives in a reference file and is loaded on demand.

---

## The goal-directed planning rule

The most important design decision in the skill. SKILL.md's "Goal-directed planning" section says:

> When the user states a **goal** (e.g. "an Insights trace at CL X on PS5"), do NOT jump to a single command. Walk backwards:
>
> 1. **Terminal command** — what command actually produces the goal artifact?
> 2. **Preconditions** — what must already exist for it to succeed?
> 3. **Recurse** until a precondition is already satisfied.
> 4. **Execute forwards**, verifying after each step.

Two artefacts make this computable:

### Preconditions and Produces fields on every command page

Open any entry in `reference/commands.md`. Every command has these two fields:

```markdown
**Preconditions:**
- Editor `.target` receipt at `Binaries/<HostPlatform>/UnrealEditor.target` exists
- Active `.uproject` in noticeboard

**Produces:**
- `Saved/Cooked/<cook_form>/` populated
```

These are verifiable from on-disk state. The planner walks the DAG by reading **Preconditions** to know what to do next; it skips a step by **verifying Produces with a file check**.

### Skip-conditions on every workflow DAG

`reference/workflows.md` lays out 14 goal-first DAGs. Each has a `Skip-conditions:` block that tells the planner how to verify a precondition is already met:

```
Skip-conditions:
  • A.runtime built  → Binaries/<P>/<Name>-<P>-<Variant>.target exists
                       AND Engine/Build/Build.version Changelist == <C>
  • B.cooked         → Saved/Cooked/<cook_form>/ exists and is non-empty
  • B.zen snapshot   → .zen snapshot list game <P>  shows <C> or a near CL
                       AND .zen status reports running
```

This is the difference between a skill that always cooks (slow) and a skill that checks `.zen snapshot list` first and uses a pre-built oplog if one exists (fast).

---

## Anti-patterns: named hallucinations

The most important section of SKILL.md isn't the iron rules — it's the **anti-patterns list**. Specifically:

> Common hallucinations to watch for:
> - `?StartPoint=<Name>` or `?PlayerStartTag=<Name>` — **does not exist as a UE switch**. The spawn selector is the URL `#Portal` segment.
> - `-encrypt` — use `-encryptinifiles` plus `-signpak`/`-signpakid=` and `-cryptokeys=<keychain.json>`.
> - `-RunAutomationTest=` under BCR — fragile. Use `.uat RunUnreal -- -test=UE.TargetAutomation`.
> - `.engine <path>`, `.platform list` — invented ushell verbs that don't exist.

These aren't hypothetical. They're the specific things RED-baseline Claude produces with confidence. Each entry was added after a baseline subagent produced the hallucination during testing.

The TDD discipline that drives this: **named hallucinations beat polite suggestions.** Saying *"prefer the right grammar"* doesn't change behaviour; saying *"`?PlayerStartTag=` does not exist"* does.

---

## TDD: RED → GREEN → REFACTOR

The skill was built test-first per `superpowers:writing-skills`. The cycle is:

```
        ┌─────────────────────────────────────┐
        │                                      │
        ▼                                      │
  ┌─ RED ─────────┐    ┌─ GREEN ──────┐   ┌─ REFACTOR ─┐
  │ Dispatch       │    │ Re-dispatch  │   │ Identify    │
  │ subagent       │    │ with skill   │   │ which       │
  │ with NO skill  │ →  │ loaded.      │ → │ rationali-  │
  │ loaded.        │    │ Score        │   │ sation      │
  │ Capture        │    │ against      │   │ slipped     │
  │ rationali-     │    │ rubric.      │   │ through.    │
  │ sations.       │    │              │   │ Patch.      │
  └────────────────┘    └──────────────┘   └─────┬───────┘
                                                  │
                                                  ▼
                                            Re-dispatch
                                            failing scenarios
```

### How scenarios were chosen

The 13 scenarios in `tests/baseline.md` aren't arbitrary. Each targets a specific known failure mode:

| Scenario | The failure mode it targets |
|---|---|
| S1 Build editor | Baseline reaches for `Build.bat` / `UnrealBuildTool.exe` |
| S2 Insights trace at CL on PS5 | Baseline goes linear; the skill must walk a DAG |
| S3 Bisect crash | Baseline does manual log₂(N) iteration; skill knows `.p4 bisect` protocol |
| S4 Channel authoring | Baseline invents `__init__.py` instead of `describe.flow.py` |
| S5 Context recovery | Baseline invents neighbour commands (`.engine`, etc.) |
| **S6 Compositional trace with PlayerStart** | **Baseline produces `?PlayerStartTag=` (doesn't exist)** |
| S7 Shipping + Gauntlet | Baseline uses `-sign` instead of `-signpak -cryptokeys=` |
| S8 Plugin packaging | The `-TargetPlatforms=` gotcha |
| S9 BuildGraph nightly | Tests BuildGraph schema fluency |
| S10 Cherrypick hotfix | Baseline reaches for raw `p4 integrate` |
| S11 WorldPartitionBuilder | Tests `.run commandlet` for non-ResavePackages verbs |
| S12 Cooked Editor | Uncertain UAT command + the niche workflow |
| S13 ODSC server | Uncertain flag (`-odschost=` vs `-filehostip=`) |

S6 is the most important. It's the scenario the user's seed doc (`ue5-launch-with-spawn-point.md`, now inlined as `reference/unreal-args.md` §2) was written for. Baseline confidently produces a fake flag with a confident-sounding C++ citation. The skill produces the real grammar with a real citation.

### Scoring and refactor

Each scenario has a bullet rubric in `tests/with-skill.md`. Thresholds use *"at least N of M bullets"* for DAG-shaped scenarios (S2, S9, S7) because hitting every literal bullet is too strict; full-bullet scoring for simpler scenarios (S1, S6).

The skill is "done" when all 13 pass. v1.0 passed S1-S7 on first GREEN dispatch (no REFACTOR). v1.1 added S8-S13, also passed first dispatch. **No REFACTOR cycle has been needed yet** — the spec's design discipline produced bulletproof first-pass skill content.

### How to re-run testing

The `tests/run-green.ps1` script prints each scenario's dispatch instructions for an Agent tool call. From a Claude Code session:

```powershell
.\tests\run-green.ps1                       # All 13 scenarios
.\tests\run-green.ps1 -Scenarios "S2,S6,S9" # Highest-value subset
.\tests\run-green.ps1 -OpenRubric           # Open scoring file too
```

Then dispatch each printed prompt as an Agent call, score against the bullets in `tests/with-skill.md`, and append the tally to `tests/notes.md` (gitignored).

---

## What's NOT in the skill

Three intentional omissions:

1. **Cross-platform parity beyond Windows.** The skill primarily targets Windows + UE 5.7 because that's the authoring environment. POSIX (`ushell.sh`) is mentioned but not exercised. Mac/Linux users will hit edge cases.
2. **Engine source modification.** The skill drives the engine, it doesn't help you change it. If you need to patch UBT or modify a commandlet's C++, the skill won't help — but it'll cite the file:line where you should look.
3. **Asset workflows.** The skill is build/cook/stage/test infrastructure. Editing Blueprints, importing FBX, configuring lighting — none of that is in scope.

These boundaries are deliberate. Scope creep would break the small-always-loaded design.

---

## How the skill stays accurate

Three mechanisms:

1. **Engine source citations.** Every commands.md entry ends with `**Source:** <ushell>/channels/...`. Every uat.md flag group cites `ProjectParams.cs`. Every unreal-args.md gotcha cites the engine code that implements it. If UE 5.8 renames something, the citations make the drift obvious and fast to fix.
2. **Behavioural tests, not unit tests.** The `tests/*.md` files describe behaviour, not API. As long as the GREEN expectations still make sense in UE 5.8, the tests don't need rewriting — only the skill content does.
3. **Research seeded into `docs/superpowers/specs/research-notes-uat.md`.** The five parallel research agents that captured UAT/BuildGraph patterns wrote their findings into a digest. That digest is the seed material for any future expansion (e.g. adding S14+ for new UE 5.x features).

---

## Reading order if you want to understand the whole thing

1. **`README.md`** — orient on what the skill does.
2. **`docs/onboarding.md`** — install + first session walkthrough.
3. **`docs/before-and-after.md`** — concrete proof from real transcripts (this is the most persuasive doc; read it before committing time to the rest).
4. **`SKILL.md`** — the always-loaded surface itself. Short.
5. **`docs/superpowers/specs/2026-05-13-ushell-skill-design.md`** — the original design spec. Long but exhaustive.
6. **`docs/superpowers/plans/2026-05-13-ushell-skill-implementation.md`** — the 13-phase plan that produced the skill.
7. **`docs/cookbook.md`** — user-facing recipes for the 14 most common workflows.
8. **`reference/*.md`** — only when you have a specific question.

---

## Open questions / risks

- **Engine version drift.** The skill is built against UE 5.7. Major version bumps will break some citations. Mitigation: tests are behavioural, so re-running `tests/run-green.ps1` against a new UE version surfaces drift quickly.
- **Always-loaded size.** SKILL.md is ~12 KB. If it grows much past 15 KB the always-loaded cost starts being noticeable. v1 absorbed some growth from the anti-patterns list (which is high-value). v2 should resist growth unless a new RED hallucination justifies it.
- **No POSIX testing.** All 13 scenarios run on Windows. POSIX paths through `ushell.sh` may have subtleties not surfaced.
- **No CI integration yet.** `run-green.ps1` prints dispatch instructions; it doesn't auto-run. A future v1.2 could add a GitHub Actions workflow that runs the GREEN suite on PR.

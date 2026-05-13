# CLAUDE.md — orientation for Claude sessions on this repo

## What this is
The authoring workspace for a Claude Code skill that teaches Claude to drive **ushell** (Epic's CLI for Unreal Engine) end-to-end — usage, channel authoring, UAT/BuildGraph fluency, and goal-directed planning from a stated outcome (e.g. "an Insights trace at CL X on PS5") backwards to a concrete command sequence.

## Read first
1. `docs/superpowers/specs/2026-05-13-ushell-skill-design.md` — the design spec. Everything in this repo is downstream of it.
2. `docs/superpowers/specs/research-notes-uat.md` — digested UAT/BuildGraph research. Seed material for `skills/ushell/reference/uat.md` and `skills/ushell/reference/buildgraph.md`. Do not silently paraphrase or drop content from this file when implementing those references.
3. `skills/ushell/reference/unreal-args.md` §2 (FURL grammar + PlayerStart Portal). The user-authored seed `ue5-launch-with-spawn-point.md` has been inlined verbatim here. **Do not invent `?StartPoint=` or `?PlayerStartTag=` — they do not exist.** The spawn selector is the URL `#Portal` segment.

## Reference engine tree
`E:\UE_5.7\Engine\Extras\ushell\` — the canonical ushell source. Every commands.md entry should cite the underlying file in the engine tree.

## Authoring discipline
The skill is being built TDD-style per the writing-skills meta-skill:
1. **RED first.** `tests/baseline.md` scenarios are dispatched to subagents *with no skill loaded* and their behaviour captured verbatim into `tests/notes.md` (gitignored) *before* SKILL.md or any reference file is written.
2. **GREEN.** Same prompts re-dispatched with the skill loaded. The rubric is `n/7` — anything below 7/7 ⇒ REFACTOR.
3. **REFACTOR.** Plug the loophole that lets a scenario score short of perfect, re-test.

The skill is "done" when all seven RED scenarios pass 7/7 GREEN with no manual hint to the subagent beyond loading the skill.

## Iron rules baked into the skill
- If `Engine/Extras/ushell/ushell.bat` (or `.sh`) exists for the active `.uproject`, prefer ushell over raw `RunUAT.bat` / `UnrealBuildTool.exe` / `GenerateProjectFiles.bat` / direct `p4`. **No silent fallback.**
- Goal-directed planning: walk backwards from the goal's terminal command, resolve preconditions, recurse, execute forwards. Skip preconditions only when verifiable. Stop and hand back on unrecoverable failure.
- UE switches passed via `-- <args>` come from `skills/ushell/reference/unreal-args.md`, never invented.

## Working tree vs install location
The skill is authored in this working tree (`E:\Work\ushell-skill\`) and installed by users via Claude Code's plugin manager:

```
/plugin marketplace add ABostrom/ushell-skill
/plugin install ushell@ABostrom-skills
```

There is no manual symlink step. Skill content lives at `skills/ushell/SKILL.md` and `skills/ushell/reference/*.md` — **not** at repo root. The `.claude-plugin/` directory at repo root holds the marketplace + plugin manifests that make this discoverable.

## Files not to commit
See `.gitignore`. Notably: `.claude/settings.local.json`, `tests/notes.md`, transcripts.

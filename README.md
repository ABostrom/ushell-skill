# ushell skill

A Claude Code skill for driving [ushell](https://dev.epicgames.com/documentation/unreal-engine/how-to-use-ushell-for-unreal-engine) — Epic's command-line interface for Unreal Engine (`Engine/Extras/ushell`).

The goal: when Claude is working in a UE-with-ushell branch, it should drive build infrastructure (build, cook, stage, run, p4, perf, Zen, DDC, UAT, BuildGraph, channel authoring) through ushell instead of inventing raw `RunUAT.bat` / `UnrealBuildTool.exe` / `p4` invocations. It should also be able to reason from a stated goal ("get me an Insights trace at this CL on PS5") backwards to a concrete command sequence, skipping work already done and stopping cleanly when a precondition is unreachable.

## Status

Spec written and reviewed. Implementation plan in progress.

## Repo layout

```
docs/superpowers/specs/
  2026-05-13-ushell-skill-design.md    The design spec (start here)
  research-notes-uat.md                Digest of UAT/BuildGraph research

SKILL.md                               Always-loaded skill body
reference/                             Layered on-demand reference files:
  commands.md                          per-command pages (all ~60 verbs)
  invocation.md                        driving ushell non-interactively
  workflows.md                         goal-first DAG catalogue
  channel-authoring.md                 writing new commands/channels
  troubleshooting.md                   symptom-keyed diagnostics
  unreal-args.md                       UE's own CLI lexicon
  uat.md                               UAT command catalogue
  buildgraph.md                        BuildGraph reference
tests/                                 (TBD)
  baseline.md                          RED prompts (subagent, no skill)
  with-skill.md                        GREEN prompts (subagent, skill on)
```

## Install (once implemented)

The working tree at `E:\Work\ushell-skill\` is the source of truth. After implementation passes 7/7 GREEN, copy or symlink the working tree's content into your Claude Code skills folder:

```powershell
# Windows
Copy-Item -Path "E:\Work\ushell-skill\SKILL.md","E:\Work\ushell-skill\reference" `
  -Destination "$env:USERPROFILE\.claude\skills\ushell\" -Recurse
```

## Authoring this skill

See `docs/superpowers/specs/2026-05-13-ushell-skill-design.md` for the design and `research-notes-uat.md` for the UAT/BuildGraph research that backs the harder sections. Tests live under `tests/`; per the writing-skills TDD discipline, the RED scenarios run **before** any skill content is authored, and `tests/notes.md` (gitignored) captures verbatim baseline rationalisations.

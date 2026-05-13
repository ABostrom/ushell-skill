# Phase 17 spec — repo polish + Claude Code install ergonomics (v2.0)

**Date:** 2026-05-13
**Status:** Spec ready; execution deferred to next session.
**Driving question (user):** *"How do other skills like superpowers do it?"*

## Goal

Make `ushell-skill` installable via Claude Code's plugin system in one line, the same way [superpowers](https://github.com/obra/superpowers) is:

```
/plugin marketplace add ABostrom/ushell-skill
/plugin install ushell@ABostrom-skills
```

Replaces the current clone-and-symlink instructions in `README.md`, which only work on Windows and require a manual sync after every release.

## Investigation findings

Cached superpowers install at `C:\Users\Aaron\.claude\plugins\cache\superpowers-marketplace\superpowers\5.1.0\` shows the layout that powers `/plugin install <repo>`:

```
<repo-root>/
├─ .claude-plugin/
│  ├─ marketplace.json      ← declares the marketplace (1 or more plugins)
│  └─ plugin.json           ← declares this specific plugin
├─ skills/<name>/
│  ├─ SKILL.md              ← skill body (not at repo root)
│  └─ reference/            ← reference files alongside SKILL.md
└─ (LICENSE, README.md, docs/, etc. stay at root)
```

Key insight: **skill content lives under `skills/<name>/`, not at repo root.** Claude Code's plugin manager scans `skills/*/SKILL.md` after install.

Superpowers' actual manifests, for reference:

**`.claude-plugin/marketplace.json`:**
```json
{
  "name": "superpowers-dev",
  "description": "Development marketplace for Superpowers core skills library",
  "owner": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "plugins": [
    {
      "name": "superpowers",
      "description": "Core skills library for Claude Code: TDD, debugging, ...",
      "version": "5.1.0",
      "source": "./",
      "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" }
    }
  ]
}
```

**`.claude-plugin/plugin.json`:**
```json
{
  "name": "superpowers",
  "description": "Core skills library for Claude Code: TDD, debugging, ...",
  "version": "5.1.0",
  "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["skills", "tdd", "debugging", "collaboration", "best-practices", "workflows"]
}
```

## Proposed restructure for ushell-skill

```
ushell-skill/                              ← what's at the repo root
├─ .claude-plugin/
│  ├─ marketplace.json                     NEW — declares ABostrom-skills marketplace
│  └─ plugin.json                          NEW — declares ushell plugin
├─ skills/
│  └─ ushell/
│     ├─ SKILL.md                          MOVED from repo root
│     └─ reference/                        MOVED from repo root
│        ├─ commands.md
│        ├─ invocation.md
│        ├─ workflows.md
│        ├─ channel-authoring.md
│        ├─ troubleshooting.md
│        ├─ unreal-args.md
│        ├─ uat.md
│        └─ buildgraph.md
├─ docs/                                   unchanged (specs, plans, before-and-after, etc.)
├─ tests/                                  unchanged (baseline.md, with-skill.md, learnings docs, run-green.ps1)
├─ LICENSE                                 unchanged (MIT)
├─ README.md                               install snippet rewritten
├─ CLAUDE.md                               note new layout (working tree vs install)
└─ .gitignore                              unchanged
```

## Files to create

### `.claude-plugin/marketplace.json`

```json
{
  "name": "ABostrom-skills",
  "description": "Aaron Bostrom's Claude Code skills",
  "owner": { "name": "Aaron Bostrom", "email": "aaron.bostrom1@gmail.com" },
  "plugins": [
    {
      "name": "ushell",
      "description": "Drives ushell (Epic's Unreal Engine CLI) end-to-end: build, cook, stage, package, trace, BuildGraph, UAT, goal-directed planning",
      "version": "2.0.0",
      "source": "./",
      "author": { "name": "Aaron Bostrom", "email": "aaron.bostrom1@gmail.com" }
    }
  ]
}
```

### `.claude-plugin/plugin.json`

```json
{
  "name": "ushell",
  "description": "Drives ushell (Epic's Unreal Engine CLI) end-to-end: build, cook, stage, package, trace, BuildGraph, UAT, goal-directed planning",
  "version": "2.0.0",
  "author": { "name": "Aaron Bostrom", "email": "aaron.bostrom1@gmail.com" },
  "homepage": "https://github.com/ABostrom/ushell-skill",
  "repository": "https://github.com/ABostrom/ushell-skill",
  "license": "MIT",
  "keywords": ["unreal-engine", "ushell", "ue5", "buildgraph", "uat", "epic", "gamedev"]
}
```

## File moves

Use `git mv` (preserves history):

```powershell
git mv SKILL.md           skills/ushell/SKILL.md
git mv reference/         skills/ushell/reference
```

`skills/ushell/SKILL.md`'s relative links to `reference/uat.md` etc. **continue to work without edits** — both files moved together by the same depth, so `reference/uat.md` still resolves correctly from the SKILL.md's new location.

## README.md install snippet rewrite

**Replace** this section:

```powershell
git clone https://github.com/ABostrom/ushell-skill C:\Work\ushell-skill
New-Item -ItemType SymbolicLink \
    -Path "$env:USERPROFILE\.claude\skills\ushell" \
    -Target "C:\Work\ushell-skill"
```

**With:**

```
/plugin marketplace add ABostrom/ushell-skill
/plugin install ushell@ABostrom-skills
```

Add a brief "Migrating from v1.x" callout:

> **Upgrading from v1.x?** Remove the symlink (`$env:USERPROFILE\.claude\skills\ushell`) and reinstall via the `/plugin` commands above. Claude Code's plugin manager now owns updates.

## CLAUDE.md updates

The "Working tree vs install location" section needs adjusting:

```diff
- The skill is authored in this working tree (`E:\Work\ushell-skill\`).
- Install to `~/.claude/skills/ushell/` only after 7/7 GREEN passes.
+ The skill is authored in this working tree (`E:\Work\ushell-skill\`).
+ Installs go through Claude Code's plugin manager via `/plugin install ushell@ABostrom-skills`
+ — there is no manual symlink step. Skill content lives at `skills/ushell/SKILL.md`,
+ not at repo root.
```

## tests/run-green.ps1

Quick scan needed for any hardcoded `SKILL.md` paths that need to become `skills/ushell/SKILL.md`. Probably one or two lines.

## Execution plan (~45 min total)

1. **Create `.claude-plugin/` + both manifests** (~5 min)
2. **`git mv SKILL.md skills/ushell/SKILL.md` + `git mv reference/ skills/ushell/reference/`** (~5 min)
3. **Rewrite README install section + add migration callout** (~10 min)
4. **Patch CLAUDE.md "Working tree vs install location"** (~5 min)
5. **Patch any test scripts referencing old paths** (~5 min)
6. **Commit, tag v2.0, push** (~5 min)
7. **Verify in a fresh Claude Code session:** `/plugin marketplace add ABostrom/ushell-skill` + `/plugin install ushell@ABostrom-skills` + dispatch S1 to confirm activation (~10 min)

## Risk

| Risk | Mitigation |
|---|---|
| Plugin install fails because of a manifest field typo | Cross-reference superpowers' manifests exactly. Small diff. Easy to fix-forward. |
| Internal links in SKILL.md break after move | They won't — both `SKILL.md` and `reference/` move by the same depth, so relative paths stay valid. Verify with one click after the move. |
| Anyone using the v1.x symlink install gets confused | README migration callout. v1.4 tag is preserved for the symlink-install audience. |
| Test scripts (`tests/run-green.ps1`) reference old path | Grep + fix during step 5. |
| `keywords` in `plugin.json` don't match Claude Code's plugin-search expectations | Cosmetic if so. Easy fix-forward. |

## Definition of done

- `git tag v2.0` exists and is pushed
- A clean Claude Code session can run `/plugin marketplace add ABostrom/ushell-skill` followed by `/plugin install ushell@ABostrom-skills` and have the skill activate
- S1 dispatch (baseline scenario 1) passes its GREEN rubric in that fresh session
- README's first install line is the one-line `/plugin install`, with v1.x migration noted underneath
- Phase 18 (LinkedIn announcement) becomes unblocked

## Pairing with the EngineTest content additions

Two viable sequences (decided at execution time):

**A. v1.5 → v2.0 → Phase 18** *(recommended in the proposal handed to user 2026-05-13)*
- v1.5: EngineTest MUST tier content (75 min)
- v2.0: Phase 17 restructure (45 min)
- Phase 18: LinkedIn announce

**B. v2.0 = both at once**
- Restructure + EngineTest MUST content in a single v2.0 release (~2 hours)
- Single tag, single announce-ready state
- Higher chance of mid-session scope creep

User outcome 2026-05-13: deferred decision to next session. Both options remain valid; this spec stays accurate either way.

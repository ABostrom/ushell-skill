# Engine-version support policy

ushell ships *with* Unreal Engine, at `Engine/Extras/ushell/`. There is no separate "ushell 5.7" that you install on top of UE 5.5 — you get whatever your engine version shipped with. This skill's `reference/*.md` files therefore implicitly target **one specific UE version's ushell**, and that target evolves as Epic ships new engines.

This page is the policy for what we support, how drift is handled, and when version numbers bump.

---

## Support matrix

| UE version | Status | What it means |
|---|---|---|
| **5.7** | ✅ Tested against | The 13 GREEN scenarios all ran here. `reference/*.md` citations point at `E:\UE_5.7\Engine\Extras\ushell\...`. |
| **5.6** | 🟡 Expected to work | Minor flag/verb-name differences possible. File an issue with the drift; we'll add an inline `> **UE 5.6:**` callout at the affected `reference/` entry. |
| **5.0 – 5.5** | ⚠️ Unverified | Older ushell has fewer verbs and some renamed flags. The skill may confidently recommend a command that doesn't exist in your tree. PRs welcome; otherwise treat at-your-own-risk. |
| **5.8+** | ⏳ Pending retest | Re-run `tests/run-green.ps1` against the new engine; patch drift on `main`; ship as the next minor (`v2.1`, `v2.2`, ...). The matrix above will grow accordingly. |
| **6.0+** | 🚧 Future major | Significant UE majors trigger a major plugin version bump (`v3.0`). |

The skill's `Detection gate` will tell you immediately if your branch has no `Engine/Extras/ushell/` at all — older partial UE 4.x branches, or stripped CI mirrors, will fail there before any commands are recommended.

---

## How drift is handled

Two patterns, depending on scope.

### Inline notes for small per-version differences

If a single flag was renamed, or a verb was added in a later version, the affected `reference/*.md` entry gets an inline blockquote:

```markdown
**Flag:** `-encryptinifiles`

> **UE 5.6 note:** this flag was named `-encryptini` in 5.6; renamed to `-encryptinifiles` in 5.7+. The skill emits the 5.7+ form.
```

These callouts cost very little in the always-loaded budget (they live in `reference/`, not `SKILL.md`), and they keep the trunk single-source-of-truth.

### A new release tag for material engine drift

When a UE minor (`5.8`, `5.9`) introduces enough new verbs / flag changes that the retest surfaces real drift in multiple `reference/` files:

1. Re-run `tests/run-green.ps1` against the new engine. Score against `tests/with-skill.md`.
2. Patch failing entries. Update citations.
3. Add the new UE version to the support matrix above as "✅ Tested against".
4. Cut a minor tag (`v2.1`, `v2.2`, ...) and a GitHub Release with notes that explicitly add the new UE version to the matrix.

When a UE major (`6.0`) introduces structural changes — new ushell module layout, renamed channels, deprecated `BuildCookRun`, whatever — that's a **breaking compat** event and warrants a major skill bump (`v3.0`).

---

## When to escalate to per-engine branches

Right now, the project runs on a single trunk plus a hotfix branch per major skill version (`release/v2.0`, `release/v3.0`, …). That's strategy D in the engine-versioning taxonomy: cheap, honest, scales to a solo maintainer.

**Escalate to per-engine branches (strategy A — `release/ue5.7`, `release/ue5.6`) when at least two of these are true:**

- Multiple external contributors are landing PRs against different UE versions.
- Inline drift callouts have grown to clutter more than one `reference/*.md` file.
- An older engine version has enough active users that they need a frozen, guaranteed-compatible content snapshot.

Until then, the single-trunk approach wins on maintenance cost.

If the escalation happens, the migration is trivial: `git branch release/ue5.6 v1.4` (or whichever tag was last-tested-against-5.6), `git push -u origin release/ue5.6`, update the support matrix, done. Strategy D doesn't paint over any path to A; it just defers the cost until it's earned.

---

## What you should not do

- **Don't fork `reference/*.md` per UE version on trunk.** That's strategy C, and it multiplies maintenance by the number of engine versions. Inline notes win.
- **Don't drop UE-5.7 citations to make older versions look better-supported.** The citations are how UE 5.8+ drift gets caught when it lands — they're load-bearing.
- **Don't bump the major skill version for a single retest pass.** Retesting against a new minor UE version is a minor skill bump. Majors are for structural breaks.

---

## Quick reference for the maintainer

| You want to… | Tag | Branch | Release notes mention |
|---|---|---|---|
| Re-test against UE 5.8, patch a few drift entries | `v2.1` | land on `main` | "Tested against: UE 5.7, 5.8" |
| Hotfix a v2.0 bug after `v2.1` has shipped | `v2.0.1` | `release/v2.0` (cherry-pick) | "Hotfix to the v2.0 line; same UE coverage as v2.0" |
| Land breaking content for UE 6 | `v3.0` | `main` (after cutting `release/v2.x` if needed) | "Targets UE 6.0+; UE 5.x users should pin v2.x" |
| First UE-5.6 user files real drift | inline `> **UE 5.6:**` callout, no tag bump | `main` | next release picks it up |

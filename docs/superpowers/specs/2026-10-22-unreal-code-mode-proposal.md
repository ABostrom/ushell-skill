# Unreal Code Mode — proposal to replace Unreal MCP

**Date:** 2026-10-22
**Status:** Proposal. Not yet approved; no implementation exists.
**Driving question (user):** *"I wanted to propose a replacement to unreal MCP that could be our own code mode that resolves these issues."*
**Prior art:** Cloudflare, *Code Mode: the better way to use MCP* (Sept 2025); Anthropic, *Code execution with MCP* (Nov 2025).
**Sibling of:** `2026-05-13-ushell-skill-design.md`. ushell covers everything **outside** the editor (sync, build, cook, stage, run). This proposal covers everything **inside** a running editor.

---

## 1. Purpose

Replace the "one MCP tool per editor operation" pattern used by Unreal MCP servers with a **Code Mode** design:

- Claude writes one short **Python script** against the editor's own `unreal` module.
- A thin bridge sends it to a running editor, or to a headless editor commandlet.
- Only a **capped, structured result** goes back into Claude's context.

The deliverable is a second skill in this marketplace (`unreal-code`) plus a small stdlib-only bridge CLI (`ucode`). It is deliberately **not** an MCP server. It follows the same philosophy as the ushell skill: a composable CLI plus a skill that teaches the surface, not a wall of tool schemas.

## 2. The problem with per-tool Unreal MCP

Unreal makes the general MCP problems that Code Mode fixes noticeably worse.

| # | Failure mode | Why Unreal makes it worse |
|---|---|---|
| P1 | **Tool-surface explosion.** Every operation needs a hand-written tool. | The reflected editor API has thousands of `UCLASS`/`UFUNCTION`/`UPROPERTY` entries. Servers either ship 50–100+ tools that fill the context window and still cover a sliver of the engine, or ship generic "call function by name / set property by path" tools that push the model into long stringly-typed chains. |
| P2 | **Round trip per step.** Each call's result goes back through the model before the next call. | Editor work is batch-shaped: "every actor using material X in 30 levels", "200 lights in a grid", "every texture over 2K without mips". Each loop iteration costs a model turn. |
| P3 | **Expensive steps.** | Calls cross a socket and land on the game thread. Some trigger asset loads, shader compiles or Blueprint recompiles. A 40-call chain is slow, and it is fragile. |
| P4 | **Partial failure.** | A failure halfway through a chain leaves the level half-edited, with no transaction around the whole operation. |
| P5 | **Context-flooding results.** | Actor lists, property dumps and asset registry queries are big. Per-tool servers usually return them raw. |
| P6 | **Version drift.** | Hand-written tools target one engine version and one plugin set. Project-specific classes (game-module `UCLASS`es, Blueprint-generated classes) are invisible unless someone writes a tool for them. |
| P7 | **Dead end for anything unanticipated.** | If the server author did not foresee an operation, the model cannot do it at all. |

## 3. Non-goals

- **Not a security sandbox.** Editor Python runs with full user privileges. The threat model is *a well-meaning model making mistakes*, not an adversary (see §8).
- **Not a replacement for ushell.** Build, cook, stage, package, run and source sync stay in the `ushell` skill. `unreal-code` only touches a live editor or a headless editor commandlet.
- **No runtime or packaged-game scripting.** Editor-time only.
- **No C++ code generation or hot reload.** Python only.
- **No GUI automation** (clicking Slate widgets). Everything goes through the scripting API.
- **No MCP server in v1.** A one-tool MCP shim for non-Claude-Code clients is a possible later follow-up (§12), not part of this proposal.

## 4. Why Unreal is ready for Code Mode

Cloudflare had to build three things: a code runtime, a typed API surface generated from tool schemas, and a sandbox. Unreal already ships the first two.

| Cloudflare Code Mode | Unreal equivalent (already ships) |
|---|---|
| V8 isolate started with the Worker Loader API | Embedded CPython in the editor (`PythonScriptPlugin`) |
| MCP schemas → TypeScript API | Reflection → `unreal` Python module; **Developer Mode** generates a full typed stub (`<Project>/Intermediate/PythonStub/unreal.py`) |
| Single "write and run code" tool | Python **remote execution** protocol (send a script to a running editor), or `-run=pythonscript` headless |
| Bindings (no network, credentials stay on host) | **Missing.** Replaced by guardrails, §8 |

So the proposal is mostly **glue, discovery and discipline**, not new engine code.

## 5. Architecture

```
 Claude Code
   │  writes script.py (Python against `unreal`)
   ▼
 ucode CLI  (stdlib-only Python, in this repo under tools/ucode/)
   │  1. lint      (AST guardrails, §8)
   │  2. wrap      (prepend ucode_rt prelude, inject mode = query|apply)
   │  3. transport ─┬─ live:     remote execution → running editor
   │                └─ headless: UnrealEditor-Cmd <uproject> -run=pythonscript -script=…
   │  4. collect   (JSON envelope; spill large payloads to disk)
   ▼
 stdout: capped JSON envelope  ───────────►  back into Claude's context
 Saved/ucode/<run-id>/          (full payload, log, script copy for audit)
```

### 5.1 Components

| Component | Location | Role |
|---|---|---|
| `ucode` CLI | `tools/ucode/ucode.py` | Entry point Claude calls via Bash. Subcommands in §6. Stdlib only, no pip, matching ushell's vendoring stance. |
| `ucode_rt` prelude | `tools/ucode/ucode_rt.py` | Injected ahead of every script. Provides `emit()`, `mode`, `transaction()`, `checkout()`, size capping and exception capture. |
| API index | `<Project>/Saved/ucode/index/` (generated) | Searchable index built from the engine's own generated stub plus live reflection. Never checked in, always matches the user's engine. |
| `unreal-code` skill | `skills/unreal-code/SKILL.md` + `reference/*.md` | Teaches when to use it, the query→apply loop, the subsystem map, recipes and pitfalls. |

### 5.2 Transports

1. **Live (default when an editor is running).** Uses the `PythonScriptPlugin` remote execution protocol (UDP multicast discovery plus a TCP command channel, `ExecuteFile` command). It needs *Project Settings → Plugins → Python → Enable Remote Execution*. `ucode doctor` checks for this and prints the exact setting if it is off.
2. **Headless (fallback, and the default for `--scratch` runs).** `UnrealEditor-Cmd.exe <uproject> -run=pythonscript -script=<wrapped.py> -unattended -nosplash -stdout`. Slower to start, but needs no running editor and never touches the user's open session. When ushell is present, the skill launches this through `.run commandlet` (iron rule from the ushell skill: no raw editor-binary invocation when ushell exists).

**Why not the Remote Control API (HTTP, port 30010)?** It is designed for calling individual functions and setting properties, which reproduces exactly the per-call pattern this proposal removes. It stays an option for a future "observe only" mode.

### 5.3 The result envelope

Every run prints exactly one JSON object to stdout:

```json
{
  "run_id": "2026-10-22T14-03-11-a1b2",
  "ok": true,
  "mode": "query",
  "transport": "live",
  "duration_ms": 842,
  "result": { "matches": 37, "levels": 12, "sample": ["..."] },
  "truncated": true,
  "full_payload": "Saved/ucode/2026-10-22T14-03-11-a1b2/result.json",
  "log_tail": ["LogPython: ..."],
  "error": null
}
```

- `result` is whatever the script passes to `emit()`. It is hard-capped (default 8 KB, `--max-bytes`). Anything bigger is written to `full_payload`, and `result` gets a summary plus a sample.
- On exception: `ok: false`, `error` holds the type, message and the script-relative traceback, plus the last N lines of `LogPython`. The prelude strips its own frames so line numbers match what Claude wrote.

This answers **P5**: Claude never sees a raw 4,000-row actor dump unless it chooses to read the spill file.

## 6. `ucode` CLI surface

| Command | Purpose |
|---|---|
| `ucode doctor` | Find the `.uproject`, engine version, Python plugin state, remote-execution setting, running editors, whether the stub exists. Prints the fix for each gap. |
| `ucode index [--rebuild]` | Generate or refresh the API index from the developer-mode stub, plus a live reflection pass for project classes. |
| `ucode find <term> [--kind class\|func\|prop] [--limit N]` | Search the index. Returns signatures with one-line docs, never whole files. |
| `ucode describe <unreal.Symbol>` | Full signature, docstring, members, and deprecation notes for one symbol. |
| `ucode run <script.py> [--apply] [--live\|--headless\|--scratch] [--max-bytes N] [--timeout S]` | Lint, wrap, send, collect. Without `--apply` the script runs in `query` mode (§8.2). |
| `ucode last [--full]` | Re-print the last envelope, or the spilled payload. |
| `ucode log <run-id>` | Script copy, envelope and editor log slice for a past run (audit trail). |

## 7. Discovery: how the model finds the API without loading it

The generated stub is far too large to put in context (hundreds of thousands of lines for a full editor build). Progressive discovery replaces "load every tool definition":

1. **Skill-level map (always loaded, small).** `SKILL.md` lists the dozen subsystems and libraries that cover most editor work: actors, assets, levels, the asset registry, materials, selection, transactions and source control. Each comes with one line on when to use it.
2. **`ucode find` / `ucode describe` (on demand).** These are for anything beyond the map. The model searches, reads the few signatures it needs, then writes the script.
3. **Live reflection (project-specific).** `ucode index` also asks the running editor which classes and functions are exposed for the *project's* modules and loaded plugins. This answers **P6**: game-specific `UCLASS`es and Blueprint-generated classes become discoverable without anyone writing a tool.
4. **Deprecation awareness.** The index records `deprecated` metadata from the stub, and `describe` surfaces it prominently, so Claude stops reaching for legacy entry points (for example the older `EditorLevelLibrary` functions that moved onto editor subsystems).

Because the index is generated from the user's own engine, there is no version drift between what the skill documents and what actually exists.

## 8. Guardrails (in place of a sandbox)

Cloudflare's isolate gives hard guarantees. Editor Python cannot. The design leans on **reversibility and two-phase execution** instead of isolation. It states plainly that none of this is a security boundary.

### 8.1 Static lint (before anything is sent)

`ucode run` parses the script with `ast` and **refuses** by default:

- `subprocess`, `os.system`, `os.exec*`, `ctypes`, `socket`, `urllib`/`http` clients.
- File deletion or moves (`os.remove`, `shutil.rmtree`, `pathlib.Path.unlink`, …).
- Direct `unreal.EditorAssetLibrary.delete_*`, or the subsystem equivalents, unless `--allow-delete` is passed.
- `exec`/`eval`/`__import__` of computed strings (this blocks the trivial bypasses; it is still not a boundary).

Each refusal names the rule and the flag that overrides it. The skill tells Claude to stop and ask the user before passing any override flag.

### 8.2 Query → apply (two-phase by default)

- Every script runs in **`query` mode** unless `--apply` is passed. `ucode_rt.mode` is `"query"`, and the prelude makes the mutation helpers (`transaction()`, `checkout()`, `save()`) raise immediately.
- The canonical pattern is **one script with both phases**: compute the change set, `emit()` it, then mutate only if `mode == "apply"`. Claude runs it once in query mode, shows the user the change set when it is non-trivial, then re-runs the **same file** with `--apply`. This answers **P4**: the plan the user saw is the plan that runs.

```python
from ucode_rt import emit, mode, transaction, checkout
import unreal

eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
old = unreal.load_asset("/Game/Materials/M_Old")
new = unreal.load_asset("/Game/Materials/M_New")

targets = []
for actor in eas.get_all_level_actors():
    for comp in actor.get_components_by_class(unreal.StaticMeshComponent):
        for i, mat in enumerate(comp.get_materials()):
            if mat == old:
                targets.append((actor, comp, i))

emit({"replacements": len(targets),
      "actors": sorted({a.get_actor_label() for a, _, _ in targets})[:50]})

if mode == "apply":
    with transaction("ucode: M_Old -> M_New"):
        for actor, comp, i in targets:
            comp.set_material(i, new)
```

### 8.3 Reversibility

- **Transactions.** `ucode_rt.transaction()` wraps `unreal.ScopedEditorTransaction`. Mutations in the live editor can be undone with a single Ctrl+Z.
- **Source control.** `ucode_rt.checkout(paths)` checks files out through the editor's source control provider before saving. If the provider is disconnected, the prelude refuses to save rather than making files writable behind source control's back.
- **`--scratch`.** This runs headless against the project in a disposable copy or worktree, for anything bulk or risky. Nothing touches the user's open session or workspace until they approve.
- **Audit.** Every run keeps the exact script, the envelope and the editor log slice in `Saved/ucode/<run-id>/`.

### 8.4 Liveness

Python in the editor runs on the game thread and cannot be pre-empted safely. Mitigations:

- `--timeout` applies to the *bridge*. When it fires, the CLI reports `ok: false, error: timeout` and tells Claude the editor may still be busy, so it never silently retries.
- The skill teaches chunking for long operations (`unreal.ScopedSlowTask` with cancel checks, batches of N).
- Very large jobs default to `--headless` or `--scratch`, so the user's editor is never frozen.

## 9. The `unreal-code` skill

### 9.1 Trigger (draft frontmatter)

```yaml
---
name: unreal-code
description: Use when a task needs to inspect or change content inside the
  Unreal Editor — actors, levels, assets, materials, Blueprints' defaults,
  the asset registry, selection, editor utilities — or when the user mentions
  editor Python, the `unreal` module, Editor Utility scripts, or an Unreal MCP
  server. Also use when an editor-side script fails and needs diagnosis.
---
```

### 9.2 Iron rules

1. **One script per intent, not one call per step.** Loops, filtering and chaining happen inside the script. Never drive the editor one property at a time across turns.
2. **Query before apply.** Mutating work always runs in query mode first. Non-trivial change sets go to the user before `--apply`.
3. **Discover, don't guess.** If a symbol is not in the skill's subsystem map, call `ucode find`/`describe` before using it. Never invent `unreal.*` names, which mirrors the ushell rule against inventing UE switches.
4. **Emit small.** Return counts, samples and summaries. Let the envelope spill the rest.
5. **No silent overrides.** Never pass `--allow-*` flags without the user's say-so.
6. **ushell owns the outside.** If the goal needs a build, cook, sync or launch, hand that part to the `ushell` skill, then come back.

### 9.3 Reference files

| File | Content |
|---|---|
| `reference/subsystems.md` | The subsystem and library map with when-to-use notes and deprecated → current mappings. Every entry is checked against the 5.7 stub. |
| `reference/recipes.md` | Query→apply recipes: bulk material swap, asset audits (texture size/mips/compression, unreferenced assets), actor placement and grids, renaming and redirector fix-up, data table and data asset edits, Blueprint CDO default changes, level streaming queries. |
| `reference/runtime.md` | `ucode_rt` API, envelope schema, CLI flags, transports, `doctor` fixes. |
| `reference/pitfalls.md` | Symptom-keyed: asset loading cost, GC and stale `UObject` references, saving vs dirtying, Blueprint recompile side effects, PIE active, World Partition (actors not loaded), Python plugin disabled, remote execution off or blocked by firewall/multicast. |
| `reference/ushell-handoff.md` | Combined goals, e.g. "change X in the editor, then cook and run on PS5". `unreal-code` does the edit, `ushell` does `.cook` / `.stage` / `.run`. |

## 10. How this resolves §2

| Problem | Resolution |
|---|---|
| P1 Tool explosion | One CLI and one script. API surface found on demand (§7), not shipped as schemas. |
| P2 Round trip per step | Loops run inside the script. One model turn per *intent* (two with query→apply). |
| P3 Expensive steps | One game-thread dispatch per script instead of one per call. Heavy jobs go headless. |
| P4 Partial failure | Query→apply against the same file, the whole apply wrapped in one transaction, source-control checkout before save. |
| P5 Context flooding | Capped envelope with disk spill (§5.3). |
| P6 Version drift | Index generated from the user's engine and project at runtime. |
| P7 Unanticipated ops | Anything the `unreal` module exposes is reachable without a server release. |

## 11. Testing strategy (RED → GREEN → REFACTOR)

Same discipline as the ushell skill. Scenarios go in `tests/unreal-code-baseline.md`. RED runs use no skill and record verbatim behaviour in `tests/notes.md`. For comparison, also run with a representative per-tool Unreal MCP server and record tool-call count, model turns, tokens and wall-clock. That comparison is the evidence for the proposal.

| # | Scenario | GREEN expectation |
|---|---|---|
| U1 | "Swap every use of `M_Old` for `M_New` in the open level." | One script, query then apply in one transaction. Reports count. Undoable. |
| U2 | "Which textures in `/Game/Environment` are over 2K and have no mips?" | Asset-registry query without loading every asset where possible. Capped result plus spill file. |
| U3 | "Spawn a 20×10 grid of point lights above the floor, 400 uu apart." | One apply script. No per-actor turns. |
| U4 | "Set `MaxHealth` to 150 on all our enemy Blueprints." *(project-specific class)* | Uses `ucode find`/`describe` and live reflection to find the project class. Never invents symbols. |
| U5 | "Delete every unreferenced asset in `/Game/Old`." | Lint refuses deletion without `--allow-delete`. Agent shows the query result and **asks** before overriding. |
| U6 | Same as U1, but no editor is running. | `doctor` → headless through ushell `.run commandlet`. No raw editor binary call when ushell exists. |
| U7 | "Rename `M_Old` to `M_Legacy`, then cook and run the game on Win64 to check it." | Edit in `unreal-code`, redirector fix-up, hand off to `ushell` for `.cook` / `.run`. |

Rubric: `n/7`, same as the ushell skill. Done when all seven pass 7/7 GREEN with no hints beyond loading the skill.

## 12. Implementation order

1. **Verify engine facts (§14) against `E:\UE_5.7`** before writing anything that depends on them.
2. Write `tests/unreal-code-baseline.md`. Run RED (no skill, and per-tool MCP for comparison). Record in `tests/notes.md`.
3. `tools/ucode/`: `doctor`, the headless transport, `run` with the envelope and spill. Headless first because it is deterministic and needs no editor settings.
4. Live transport (remote execution) plus `--timeout`.
5. `ucode_rt` prelude: `emit`, `mode`, `transaction`, `checkout`, traceback rewriting.
6. AST lint and `--allow-*` overrides.
7. `ucode index` / `find` / `describe`: stub parsing first, then the live reflection pass.
8. `skills/unreal-code/SKILL.md` and reference files.
9. GREEN runs, then REFACTOR until 7/7.
10. Register `unreal-code` as a second plugin in `.claude-plugin/marketplace.json`. Decide whether it ships as its own plugin or bundled with `ushell` (open question 3).
11. *(Optional, later)* A one-tool MCP shim (`run_unreal_python`) over the same CLI for non-Claude-Code clients.

## 13. Open questions

1. **Packaging.** Same repo and marketplace as `ushell` (proposed), or a separate repo? Proposed: same marketplace, separate plugin. The ushell spec lists asset workflows as a non-goal *for the ushell skill*, so this proposal is a separate skill rather than an expansion of that one.
2. **Remote execution on locked-down networks.** Multicast discovery may be blocked on studio networks. Is a direct-connect option (host:port from `doctor`) enough, or is a tiny editor-side plugin with a localhost socket worth it?
3. **One plugin or two?** Installing `ushell` and `unreal-code` together gives the handoff (§9.3) for free. Installing them separately keeps each skill's trigger cleaner.
4. **Scratch copies.** For large projects a full copy is too expensive. Is a P4 or git worktree of `Content/` plus a symlinked `DerivedDataCache` enough for `--scratch`?
5. **Comparison target.** Which existing Unreal MCP server should the RED comparison use as the "per-tool" baseline?

## 14. Engine facts to verify before implementation

Everything below is believed correct for UE 5.x but **has not yet been checked against `E:\UE_5.7`**. Per repo discipline, each gets a source citation from the engine tree before it is relied on:

- `PythonScriptPlugin` location, and that `remote_execution.py` ships in its `Content/Python/`, including the protocol commands (`ExecuteFile` / `ExecuteStatement` / `EvaluateStatement`) and default multicast group and port.
- The exact name and location of the *Enable Remote Execution* and *Developer Mode* settings, and the stub output path (`Intermediate/PythonStub/unreal.py`).
- `-run=pythonscript -script=` commandlet syntax (`UPythonScriptCommandlet`), and whether `-ExecutePythonScript=` on a normal editor launch is a better headless path.
- `unreal.ScopedEditorTransaction`, `unreal.ScopedSlowTask`, `unreal.SourceControl` (helpers) — names and signatures in 5.7.
- Current editor subsystem names (`EditorActorSubsystem`, `EditorAssetSubsystem`, `LevelEditorSubsystem`, `UnrealEditorSubsystem`) and which `EditorLevelLibrary` / `EditorAssetLibrary` functions are deprecated in 5.7.
- How ushell's `.run commandlet` passes arguments through, so the headless transport can route through it (cite `cmds/run.py::Commandlet`).

## 15. Acceptance criteria

- `ucode doctor`, `run` (both transports), `index`, `find`, `describe`, `last` and `log` work against the UE 5.7 reference project on Windows.
- Every envelope is valid JSON under the byte cap. Larger payloads spill to disk with the path reported.
- Lint refuses every pattern in §8.1 by default. Each refusal names its override flag.
- A query-mode run cannot mutate, save or check out (prelude-enforced, covered by a test).
- Every apply in the live editor is a single undoable transaction.
- `SKILL.md` is at most 300 words of prose, matching the ushell skill's budget.
- All seven RED scenarios have verbatim baseline notes, plus the per-tool MCP comparison numbers, recorded **before** skill content is written.
- All seven GREEN scenarios pass 7/7 with no hints beyond loading the skill.
- Every engine fact in §14 carries an engine-tree citation in the reference files.

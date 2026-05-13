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

---

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
                     (debuggers/vs.py uses vs.dte.running() to enumerate
                     and pick the right instance)
```

**Notes:**
- Use `--attach=lldb` (or set `USHELL_DEBUGGER=lldb`) on POSIX.
- Use `--attach=rider` if Rider is preferred (set `USHELL_DEBUGGER=rider`).
- `-WaitForDebugger` (UE switch, after `--`) halts the process *at startup* so a debugger can attach early — useful for `WinMain` / `FEngineLoop::PreInit` issues. **Don't use in CI** (it really halts).

---

## 3. Profile shipping build on platform P at CL X

```
GOAL: Capture a Test-config Insights trace + LLM memory profile on <P> at <C>

Terminal: .run game <P> test --trace=default,memory,memtag,gpu -- <map> -llm -llm.AutoReportMemory
  Preconditions:
    [A] Source synced to <C>
        → .p4 sync <C>
    [B] Game runtime built at variant=test for <P>
        → .build game <P> test
           Preconditions: Editor built (for cook).
             → .build editor
    [C] Cooked content (Test-config cooks differ from Development!)
        → .cook game <P> -- -unattended -unversioned
           -- OR --
        → .zen snapshot get game <P> <C>     (if Test-config snapshot exists)
    [D] Staged build
        → .stage game <P> auto

Post:
  • Trace + LLM data flow to Insights store. Open with .perf insights latest.

Skip-conditions:
  • Same as DAG #1, but with variant=test in the .target receipt name:
    Binaries/<P>/<Name>-<P>-Test.target
```

**Why Test, not Shipping:** Shipping strips trace + LLM instrumentation. Test config keeps them but otherwise matches Shipping perf characteristics.

---

## 4. Find the CL that broke the editor

```
GOAL: Identify the CL between <good>=<G> and <bad>=<B> that broke editor startup

Terminal: .p4 bisect <G> <B> -- build-and-run.bat
  Preconditions:
    [A] P4 login active
        → p4 login
    [B] build-and-run.bat exists in cwd or absolute path
        → write it (see below)

Post:
  • ushell reports the first-bad CL: "Bad at CL <N>"
  • Inspect: .p4 cherrypick --dryrun <N>  or  p4 describe -s <N>

Skip-conditions:
  • A.logged in   → p4 login -s reports "ticket expires in ..."
  • B.script      → file present and exit-code-protocol-compliant
```

**The script (canonical):**

```bat
@echo off
call <branch>\Engine\Extras\ushell\ushell.bat --project=<uproject>
.build editor --nosummary
if errorlevel 1 exit 90
.run editor -- -stdout -ExecCmds="Quit"
if errorlevel 1 exit 80
exit 0
```

**Exit codes:** 0 = good, 80 = bad, 90 = failed to build (ugly; bisect expands outward).

---

## 5. Fresh sync → build → run editor (everyday loop)

```
GOAL: Update workspace and get the editor running

Terminal: .run editor
  Preconditions:
    [A] Source synced to head
        → .p4 sync
    [B] Editor built
        → .build editor

Post: Editor open, project loaded.

Skip-conditions:
  • A.synced   → after .p4 sync runs to completion (idempotent)
  • B.built    → .build editor itself is idempotent if up-to-date (fast no-op)
```

**Optimisation:** Chain in one command via temp `.bat`:

```bat
@echo off
call <ushell.bat> --project=<uproject>
.p4 sync --nosummary && .build editor --nosummary && .run editor
```

---

## 6. Stream switch + minimal verify

```
GOAL: Switch to stream <S> at CL <C> (or head) and confirm engine compiles

Terminal: .build editor --nosummary
  Preconditions:
    [A] Switched to stream <S>
        → .p4 switch <S> [<C>]
           Preconditions: Stream client (use .p4 switch list to confirm
           stream is reachable from current depot)
    [B] Synced (implicit in .p4 switch)
    [C] If switch left files unresolved (output mentions conflicts):
        → resolve, then retry

Post: Editor builds clean. .info confirms branch + engine version match.

Skip-conditions:
  • A.on stream <S> → .info reports `engine.branch` ending in <S>
```

**Pitfall:** `.p4 switch` requires a stream client and shelves open files into a backup CL. If anything goes wrong mid-switch, a `_RestorePoint` attempts to unshelve back. Check `p4 changes -s pending -u <you>` if the switch errors out.

---

## 7. Cook + stage + run on target platform P with Zen

```
GOAL: Boot the cooked runtime on <P> with Zen-style packaging

Terminal: .run game <P> -- <map>
  Preconditions:
    [A] Game runtime built for <P>
        → .build game <P>
    [B] Cooked content + Zen oplog
        → .cook game <P>
           Preconditions: Editor built.
             → .build editor
    [C] Staged with style=zen
        → .stage game <P> zen
           Preconditions: ZenServer running.
             → .zen status   (and .zen start if down)

Post: Cooked game runs against ZenServer-backed content store.

Skip-conditions:
  • A.runtime built  → Binaries/<P>/<Name>-<P>-Development.target exists
  • B.cooked         → Saved/Cooked/<cook_form>/ exists AND
                       Saved/Cooked/<cook_form>/ue.projectstore exists
                       (marker indicating Zen-style cook)
  • C.staged         → Saved/StagedBuilds/<cook_form>/<Name>.exe exists
                       AND Saved/StagedBuilds/<cook_form>/<...>.uoplog exists
                       (vs. .pak/.utoc/.ucas for pak-style)
  • C.zen running    → .zen status reports OK
```

---

## 8. Pull pre-cooked data for this CL via `.zen snapshot get`

```
GOAL: Skip cooking; download a pre-built oplog for runtime=<R>, platform=<P>, CL=<C>

Terminal: .zen snapshot get <R> <P> <C>
  Preconditions:
    [A] ZenServer running
        → .zen start
    [B] OIDC token (only for cloud backend)
        → .ddc auth
    [C] At least one snapshot exists at-or-before <C>
        → .zen snapshot list <R> <P>    (verify before commit)

Post:
  • Oplog imported into ZenServer.
  • Subsequent .run game <P> / .stage game <P> can use this oplog instead
    of a local cook.

Skip-conditions:
  • A.zen running   → .zen status reports OK
  • B.authorized    → .ddc auth --query reports "valid token"
  • C.snapshot      → .zen snapshot list <R> <P> shows <C> or near CL with *

Failure mode:
  • If .zen snapshot find <R> <P> says "no snapshots found": fall back to
    .cook <R> <P>. Don't silently skip - report to user.
```

---

## 9. Cherrypick a CL across streams

```
GOAL: Pull CL <N> from another stream into current branch

Terminal: .p4 cherrypick <N>
  Preconditions:
    [A] P4 login
        → p4 login
    [B] Stream client and on the destination stream
        → .info reports engine.branch matching destination
    [C] No conflicts in <N>'s files vs your open files
        → .p4 cherrypick --novalidate would override the check

Post:
  • New pending CL with the cherrypicked changes.
  • If source/dest streams unrelated: integration records cleared automatically
    so the CL looks like a native edit (the "edigrate" step).
  • Resolve any conflicts via the prompt or `.p4 cherrypick --noresolve`
    then `p4 resolve` manually.

Skip-conditions: this command isn't typically "skipped" - it always produces
a new CL. The point of skip-conditions is the precondition checks.
```

**Specifying multiple CLs:** `.p4 cherrypick 1234567 1234568 1234569` — they integrate one after another.

**Path restriction:** `.p4 cherrypick <N> --path=Engine/Source/Runtime` — limits to a subtree.

---

## 10. Run an automated perf test (`.perf test sequence`)

```
GOAL: Run perf+LLM+Insights subtests against the configured <ComboName> sequence

Terminal: .perf test sequence <P> all <variant> game <ComboName>
  Preconditions:
    [A] Staged build at <project>/Saved/StagedBuilds/<cook_form>/
        → .stage game <P> auto
           Preconditions: cooked + built. (See DAG #7.)
    [B] AutomatedPerfTesting plugin is enabled in the project
        → Check <project>/Config/DefaultEngine.ini for
          [/Script/AutomatedPerfTesting.AutomatedSequencePerfTestProjectSettings]
          MapsAndSequencesToTest=(...,ComboName="<ComboName>",...)

Post:
  • CSV profiler output + .utrace files in <project>/Saved/Profiling/
  • Test ID stamped as <project>-<subtest>-autoperftest-ushell unless --testid

Skip-conditions:
  • A.staged   → as DAG #7
  • B.plugin   → DefaultEngine.ini section present with target combo name
```

**subtest=all** runs `perf`, `llm`, `insights`, and `gpuperf` sequentially and ANDs results. Use individual subtest names to isolate.

**.perf test mapping** (under the hood, ushell shells out to):

```
.uat RunUnreal -- -test=AutomatedPerfTest.SequenceTest -AutomatedPerfTest.DoPerf
   -platform=<P> -configuration=<variant> -iterations=6 -target=Game
   -build=<project>/Saved/StagedBuilds/<cook_form>
   -AutomatedPerfTest.SequencePerfTest.MapSequenceName=<ComboName>
   -resX=1920 -resY=1080 -LocalReports
   -AutomatedPerfTest.DoCSVProfiler
   -AutomatedPerfTest.TraceChannels=default,screenshot,stats
```

See `reference/uat.md` §4 for the full Gauntlet RunUnreal contract.

---

## 11. Generate a Visual Studio solution and open it

```
GOAL: Have <Project>.sln open in VS for the active project

Terminal: .sln open
  Preconditions:
    [A] Solution file exists
        → .sln generate
           Preconditions: Active branch. Source/Target.cs files present.

Post:
  • VS opens <Project>.sln (or branch-named variant).

Skip-conditions:
  • A.sln present → <Project>.sln exists in engine/project root AND
                    Intermediate/ProjectFiles/PrimaryProjectName.txt matches

Fallback for missing Source/:
  • If the project is Blueprint-only with no Source/ folder:
    → .sln open tiny
       Generates a minimal fzf-friendly sln in Intermediate/ProjectFiles/TinySln/
       without needing .sln generate first.
```

---

## 12. Drive a commandlet

```
GOAL: Run editor commandlet <Name> with args <args>

Terminal: .run commandlet <Name> -- <args>
  Preconditions:
    [A] Editor built (-Cmd.exe variant)
        → .build editor
    [B] Active .uproject (the commandlet attaches to a project)
        → .project <path>

Post: Whatever the commandlet writes (resaved assets, generated files, etc.)

Skip-conditions:
  • A.editor built → Binaries/<Host>/UnrealEditor.target exists
                     (.run commandlet auto-uses the -Cmd.exe variant)
  • B.project set  → .project active prints non-empty path
```

**Concrete examples:**

```
.run commandlet ResavePackages -- -PackageDir=Content/Foo -AutoCheckOutPackages
.run commandlet DerivedDataCache -- -fill -unattended
.run commandlet GatherText -- -config=Config/Localization/Game.ini
.run commandlet WorldPartitionBuilder -- /Game/Maps/MyMap -Builder=Minimap
.run commandlet ResavePackages --build -- -PackageDir=Content/Foo  # build editor first
```

**With debugger:** add `--attach` (re-enters via `_run commandlet <Name> --attach` for the debugger plumbing).

---

## 13. Run BuildCookRun directly via `.uat`

```
GOAL: Custom UAT BuildCookRun invocation (shipping pipeline, custom flags, etc.)

Terminal: .uat BuildCookRun -- <BCR args>
  Preconditions:
    [A] UAT compiled and runnable
        → .uat itself auto-builds UAT via BuildUAT.bat (no separate step needed)
    [B] Source synced if you're targeting a specific CL
        → .p4 sync <C>

Post: Whatever BCR produces (cooked + staged + packaged + archived per your verbs).

Skip-conditions: BCR is itself non-idempotent in general; rely on -skipbuild /
-skipcook / -skipstage / -skiparchive flags to skip individual phases.
```

**Canonical shipping invocation** (see `reference/uat.md` §2.6 for the full block):

```
.uat BuildCookRun -- ^
  -project=<full path>\MyGame.uproject ^
  -target=MyGame -platform=Win64 -clientconfig=Shipping ^
  -build -cook -stage -pak -iostore -compressed -package -archive ^
  -archivedirectory="<full path>\Out" ^
  -prereqs -nodebuginfo -utf8output -unattended -nop4 -nullrhi
```

**Append for CI:** `-buildmachine -CrashForUAT -NoCodeSign -nosound -stdlog`.

**For multi-target (client + server):** `-target=MyGame+MyGameServer -platform=Win64 -serverplatform=Linux -clientconfig=Shipping -serverconfig=Shipping`. (Split into two `.uat BuildCookRun` calls is often cleaner for CI archiving.)

---

## 14. Clean a branch safely

```
GOAL: Reclaim disk space; remove Intermediate/, DerivedDataCache/, Saved/ (mostly)

Terminal: .p4 clean
  Preconditions:
    [A] No running UE processes rooted in the branch
        → .kill editor; .kill <platform>; (manually check Task Manager for any
          UE-Cmd.exe, ZenServer.exe, etc.)
    [B] rg (ripgrep) on PATH
    [C] Dry-run check first
        → .p4 clean --dryrun

Post:
  • Intermediate/, DerivedDataCache/, Saved/ subdirs removed (except keeps).
  • Binaries/ unversioned files removed; P4-tracked binaries preserved.

Skip-conditions:
  • [A] is a hard precondition - .p4 clean refuses to proceed if a UE
    process is rooted in the branch (would mark unversioned files busy).
```

**Default keeps:** `Saved/Profiling`, `Saved/StagedBuilds`. Override with `--savedkeeps=<csv>` (e.g. `--savedkeeps=Profiling,StagedBuilds,Logs`).

**Wipe all of Saved/:** `--allsaved` (use with care).

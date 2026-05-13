# Troubleshooting

Symptom-keyed. Find your error message verbatim or close to it. Each entry: *Symptom* → *Likely cause* → *Resolution*.

## ushell session / context

### `Unable to establish an Unreal context from directory '...'`
- **Cause:** No `.uproject` reachable from CWD and the session noticeboard's `"uproject"` key is empty.
- **Fix:** Relaunch with `cmd.exe /d /s /c "call <ushell.bat> --project=<path>\<file>.uproject"`. Or, from an already-running ushell session, run `.project <path>` then retry the original command.
- **Why:** `.project` writes the `.uproject` path to a session noticeboard keyed by `FLOW_SID`. Each new bat invocation gets a fresh `FLOW_SID`, so the noticeboard is empty until you populate it (with `--project=` or `.project`).

### `ushell.bat opened a new window and exited`
- **Cause:** Launched via Explorer or a shortcut without scripting form. ushell.bat's heuristic decided you're interactive and spawned a fresh console.
- **Fix:** Use the scripting form: `cmd.exe /d /s /c "call <ushell.bat> ..."` or a `call`-from-bat. See `reference/invocation.md` §Multi-command form.

### Verb is unknown — `'.' is not recognized as an internal or external command`
- **Cause:** ushell hasn't established itself in this shell.
- **Fix:** First line of your bat must be `call <ushell.bat> --project=<...>`. PowerShell can't run `.foo` directly; go via `cmd.exe`.

### Hangs forever; no output
- **Cause:** Often XGE-based shader compile waiting on remote agents, or ZenServer mid-import. Could also be a UE process that crashed but the cmd shell didn't detect.
- **Fix:**
  1. `.zen status` (separate session) to check ZenServer.
  2. Try the command with `--noxge` (for `.cook` family) or `--unpretty` to see raw output.
  3. Use `.kill editor` / `.kill <platform>` to force-terminate, then retry.

### `--help` ran but command didn't run
- **Cause:** Exit code 127 — help was printed because you passed `--help` (or `-h` or `/?`).
- **Fix:** Not a failure; that's the help path. Treat 127 as "user asked for help".

---

## Perforce

### `No valid Perforce session found. Run 'p4 login' to authenticate.`
- **Cause:** P4 session expired (typical) or `P4USER` / `P4PORT` mismatch.
- **Fix:** `p4 login`, enter password, retry. `p4 login -s` to check ticket status.

### `Client 'X' is not a stream`
- **Cause:** `.p4 switch` / `.p4 mergedown` require a stream-based workspace, but the current client is classic-mapped.
- **Fix:** Either create a stream-mapped workspace (`.p4 workspace <dir> //depot/Main`) or use a different command (e.g. `.p4 sync` works on classic clients; `.p4 cherrypick` works on classic with `--rawbranchspec`).

### `Unable to establish branch root`
- **Cause:** `p4utils.get_branch_root()` couldn't find `GenerateProjectFiles.bat` upward from the depot path. Workspace view is wrong, or the client is unloaded server-side.
- **Fix:**
  1. Verify the workspace view includes the engine's `GenerateProjectFiles.bat`: `p4 client -o <name>` to inspect.
  2. If the client was unloaded: `p4 reload -c <name>`.

### `.p4 sync` reports client is `*unknown*`
- **Cause:** `P4CLIENT` env var unset, or the local `.p4config.txt` is missing / has wrong client name.
- **Fix:**
  1. Edit `<branch_root>/.p4config.txt` to set `P4CLIENT=<your client>`.
  2. Or set `$env:P4CLIENT='<your client>'` in PowerShell before launching ushell.
  3. `.p4 v` and `.p4 sync edit` will both fail with the same root cause; fixing this fixes both.

### `.p4 cherrypick` says "files already open for edit"
- **Cause:** Validation step refuses to integrate over files you have open.
- **Fix:** Either revert the open files, submit them, or run with `--novalidate` (you accept the risk).

### `.p4 mergedown` leaves a "still needs resolving" CL
- **Cause:** Designed behaviour. Auto-resolve worked for most files; some needed manual.
- **Fix:** Open the second CL (description includes `#nocheckin`), resolve the remaining files (P4V or `p4 resolve -am`), then move them back into the main CL.

---

## Build / cook / stage

### `.cook *` hangs on shader compile
- **Cause:** XGE-based shader compilation idle or remote agents stuck. Sometimes Zen mid-import.
- **Fix:**
  1. `.kill editor` to unblock if it's truly stuck.
  2. Try `.cook game <P> --noxge` to disable XGE shader compile.
  3. `.zen status` — if Zen is busy, give it time or restart with `.zen stop && .zen start`.

### `.run editor --attach` shows no debugger
- **Cause:** Visual Studio detached on early hot-reload, OR no VS instance is open with a matching `.sln`, OR `USHELL_DEBUGGER` env var set to something not installed.
- **Fix:**
  1. `.sln open` first, then re-run with `--attach`. Use the same VS that has the correct `.sln`.
  2. Check `$env:USHELL_DEBUGGER` — should be `vs`, `lldb`, or `rider`.
  3. Set `USHELL_DEBUGGER=vsjit` to use the just-in-time debugger as fallback (no DTE required).

### `.stage` complains about `ue.projectstore` mismatch
- **Cause:** Zen marker file inconsistent with the requested stage style. The cook produced Zen output but you asked for pak (or vice versa).
- **Fix:** Pick `style=pak` or `style=zen` explicitly (instead of `auto`). If you want to re-cook clean, delete `Saved/Cooked/<form>/ue.projectstore` first.

### `RunUAT.bat: not found` from inside `.uat`
- **Cause:** Engine `Engine/Build/BatchFiles/` is missing — partial sync, or you're pointed at a non-engine directory.
- **Fix:** `.p4 sync --all` to bring the engine binaries back. Verify with `.info` that `engine.path` is sensible.

### Tab completion empty for `.build target`
- **Cause:** `Source/*.Target.cs` not synced, or `Intermediate/Build/BuildRules/*RulesManifest.json` not generated.
- **Fix:** `.p4 sync`, then `.sln generate` to populate manifests. The completion source is `<branch>/Source/*.Target.cs` plus the manifest.

### `.build editor` says "No active project" but I have a .uproject
- **Cause:** Active project not set in the noticeboard for this session.
- **Fix:** Run `.project <path>` first, or relaunch ushell.bat with `--project=<path>`. (Same root cause as the "Unable to establish an Unreal context" symptom above.)

---

## UAT-specific

### `BuildPlugin` fails with "couldn't find SDK for IOS/TVOS/Android"
- **Cause:** Since 4.25, `BuildPlugin` defaults to **all** detected SDK platforms.
- **Fix:** Always pass `-TargetPlatforms=Win64+Linux+...` explicitly. See `reference/uat.md` §3 plugin lifecycle.

### `BuildCookRun` finishes but `-archivedirectory` is empty
- **Cause:** Project Settings → Packaging → StagingDirectory is **ignored** by UAT. Must be passed on the CLI.
- **Fix:** Add `-stagingdirectory=<path> -archive -archivedirectory=<path>` to the BCR command.

### `BCR -RunAutomationTest=` reports BUILD FAILED on green tests
- **Cause:** Known fragility — the client process exits before UAT polls and reports failure.
- **Fix:** Use `.uat RunUnreal -- -test=UE.EditorAutomation -RunTest="<filter>"` (Gauntlet) or drive the editor directly with `.run editor -- -ExecCmds="Automation RunTests <filter>; Quit" -ReportExportPath=<dir>`.

### CI build hangs on a modal dialog
- **Cause:** `-buildmachine` not set. UAT defaults to allowing dialog boxes for crash report, license prompts, etc.
- **Fix:** Always include `-buildmachine -CrashForUAT -unattended -nop4 -NoCodeSign -utf8output -stdlog` in CI invocations. See `reference/uat.md` §6 canonical CI baseline.

### `-iterate` left stale assets in the cook
- **Cause:** Known iterative-cook bugs. Some asset dependency chains don't trigger a re-cook even after content changes.
- **Fix:** **Never use `-iterate` for shipping.** For repro: full `-cook` (no `-iterate`). For dev iteration, accept the staleness risk and clear `Saved/Cooked/<form>/` periodically.

### `BuildPlugin` says "Engine version mismatch" against a Rocket install
- **Cause:** Binary plugins are engine-version-locked at the minor level. A plugin built for 5.4.x will not load in 5.5.x.
- **Fix:** Rebuild against the target minor version, or build for multiple engine versions if you ship to Marketplace.

---

## Zen

### `.zen snapshot get` says "no snapshots found for changelist X"
- **Cause:** No prebuilt cooks at that CL in the configured backend (cloud or fileshare).
- **Fix:** Try `.zen snapshot find <runtime> <platform>` to see the nearest match. Or fall back to `.cook game <platform>` to produce a fresh cook.

### `.zen status` says "no server running" mid-test
- **Cause:** ZenServer was killed (often by an unrelated `.kill` or system reboot).
- **Fix:** `.zen start` to relaunch. Active oplogs may need re-importing via `.zen importsnapshot` if they weren't persisted.

### `.zen snapshot get` prompts for "use closest CL?"
- **Cause:** No exact-match snapshot at the requested CL; one exists at a near CL.
- **Fix:** Type `p` (preceding) or Enter to accept. Ctrl-C to abort and either pick a different CL or cook from scratch.

### `.zen start` fails with port-in-use
- **Cause:** Another ZenServer (or another process on port 8558) is running.
- **Fix:** `.zen status` to confirm a server is already up — if so, you're done. If something else is on the port, `Get-Process | Where-Object Path -like '*Zen*'` and decide.

---

## DDC / cloud auth

### `.ddc auth` succeeds but `.zen snapshot get` says "401 Unauthorized"
- **Cause:** Token scope mismatch. The OIDC token authorized for one service doesn't authorize Cloud DDC operations.
- **Fix:** `.ddc auth <service>` with the right service name. The default service comes from `[StorageServers]Default.OAuthProviderIdentifier`; for Cloud DDC specifically you may need `[StorageServers]Cloud.OAuthProviderIdentifier`.

### OidcToken.exe not found
- **Cause:** The binary lives at `Engine/Binaries/DotNET/OidcToken/<host>/OidcToken.exe`. If your engine sync excluded `Binaries/DotNET/`, it's missing.
- **Fix:** `.p4 sync //...OidcToken/...` to fetch.

---

## Channel authoring

### `.mychan <verb>` not recognised after adding the channel
- **Cause:** Channel discovery hasn't picked up the new files. Likely places:
  1. Wrong directory (must be a discoverable channels path).
  2. `describe.flow.py` has a syntax error and silently fails.
  3. Manifest cache stale — happens when only changing command bodies, not channel structure.
- **Fix:**
  1. Verify path: `$USERPROFILE\.ushell\channels\mychan\describe.flow.py` (per-user) or your branch's ushell `channels/`.
  2. Syntax-check: `python <path-to-describe.flow.py>`.
  3. Bump `channel.version("N")` in `describe.flow.py` to invalidate the cache.

### `complete_<argname>` not being called
- **Cause:** Method name typo, or `<argname>` doesn't match an `Arg`.
- **Fix:** Method must be `complete_<exact arg name>(self, prefix)` and return an iterable.

---

## Symptom → command quick map

| Symptom | First diagnostic |
|---|---|
| Anything ushell-shaped failing | `.info` (engine, project, platforms — confirms context) |
| Perforce-shaped failing | `.p4 sync edit` to inspect filter file; `p4 set` to see env |
| Cook-shaped failing | `.zen status` (is server up?), then `.info config Engine` |
| Build-shaped failing | `.build xml` (see current BuildConfiguration.xml values) |
| Run-shaped failing | check `.sln open` already done; check `$env:USHELL_DEBUGGER` |
| UAT-shaped failing | `.uat` with `-help` won't reveal much; read `ProjectParams.cs` for canonical flags |
| Channel-shaped failing | syntax-check `describe.flow.py`; bump `channel.version()` |
| Zen-shaped failing | `.zen status` → `.zen version` → `.zen stop && .zen start` |

# ushell statusline — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore live cook/build/sync progress visibility for ushell commands wrapped by Claude (background-task output files we can't see directly), by surfacing them in the Claude Code statusline. Demo path: wire into `~/.claude/settings.json` for this session and run a real cook on ProjectGear with live progress visible. Ship path: roll the same wiring into `.claude-plugin/plugin.json` for zero-config plugin install (deferred to Phase B).

**Architecture:** Single-file JSON state (`~/.claude/ushell-state.json`) written by a `PreToolUse`/`PostToolUse` hook script when Claude invokes ushell-shaped commands; statusline script reads state + tails the harness background-task output file for verb-specific progress markers (`LogCook: Display: Cooked packages N`, UBT `[N/M]`, etc.) and renders 3 lines (context / in-flight / last). Atomic-rename state writes prevent torn reads.

**Tech Stack:** PowerShell 7+ (`pwsh`), JSON state file, Claude Code `statusLine` + `hooks` settings.

**Spec:** [`docs/superpowers/specs/2026-05-14-ushell-statusline-design.md`](../specs/2026-05-14-ushell-statusline-design.md)

---

## File structure

**New files in this plan:**

```
ushell-skill/
├── scripts/                                       (NEW dir)
│   ├── progress-patterns.json                     verb → regex table
│   ├── hook-update.ps1                            state-file writer (Pre+Post phases)
│   ├── statusline.ps1                             state-file reader + tail + render
│   └── lib/                                       (NEW dir)
│       ├── state.psm1                             atomic JSON read/write helpers
│       ├── ushell-detect.psm1                     parse Bash command, detect verb+project+engine
│       └── progress-tail.psm1                     incremental output-file tailing
├── tests/statusline/                              (NEW dir)
│   ├── fixtures/                                  (NEW dir)
│   │   ├── cook-output.txt                        snippet of real .cook output
│   │   ├── build-output.txt                       snippet of UBT [N/M] output
│   │   ├── uat-bcr-output.txt                     snippet of RunUAT BCR output
│   │   └── p4-sync-output.txt                     snippet of .p4 sync output
│   ├── test-progress-patterns.ps1                 unit tests over fixtures
│   ├── test-state-lifecycle.ps1                   pre+post hook integration test
│   └── test-statusline-render.ps1                 render-output assertions
└── docs/superpowers/plans/
    └── 2026-05-14-ushell-statusline.md            (this file)
```

**Files modified (Phase B only, after demo):**

```
.claude-plugin/plugin.json                         add statusLine + hooks fields
```

**Files modified to wire the demo (Phase A — outside the repo):**

```
~/.claude/settings.json                            add statusLine + hooks (local-dev path)
```

---

## Phase A — Demo-critical path

Goal of Phase A: live statusline working in **this** Claude Code session before the end of the implementation pass.

### Task A1: Verify Claude Code statusLine + hooks schema (research)

We have four genuine unknowns in the spec's Open Questions. Resolving them with current Claude Code docs unblocks everything else. Dispatch a `claude-code-guide` subagent rather than guessing.

**Files:**
- Create: `docs/superpowers/specs/2026-05-14-ushell-statusline-research.md` (research findings)

- [ ] **Step 1: Dispatch the claude-code-guide subagent**

Use the Agent tool with `subagent_type: claude-code-guide`. Prompt:

> Answer these four questions about current Claude Code config schema, with file/line references where possible:
>
> 1. **`statusLine` in `~/.claude/settings.json`:** what's the schema? What fields does the command object accept (`type`, `command`, `refreshInterval`?)? What's the minimum sensible `refreshInterval` value? Does the output support multi-line (one line per `\n`) or is it single-line only? If multi-line, how many lines render?
>
> 2. **`hooks` in `~/.claude/settings.json`:** confirm the structure for `PreToolUse` and `PostToolUse` arrays. What does the `matcher` field accept (regex? glob? exact tool name?)? What's the contract for the hook's input — JSON on stdin, env vars, or both? List the exact env var names or stdin schema if you can.
>
> 3. **Hook input details for `Bash` and `PowerShell` tools:** when a hook fires PreToolUse on a Bash/PowerShell call, does the hook receive the command string, the `run_in_background` flag, and (if running in background) the task-id or output-file path? List the exact field names.
>
> 4. **Plugin manifest extensions:** can `.claude-plugin/plugin.json` declare its own `statusLine` and `hooks` fields, or does the plugin need to ship `.claude-plugin/statusline.json` / `.claude-plugin/hooks.json` (or similar)? What's the `${PLUGIN_DIR}` template (or equivalent) that resolves to the plugin's install location?
>
> Save findings to `E:\Work\ushell-skill\docs\superpowers\specs\2026-05-14-ushell-statusline-research.md` with verbatim doc quotes where possible. Flag anything you can't find with `❓ NOT FOUND` so we know what we still need to discover empirically.

Expected output: a research file with answers (or honest "not found") for each of the four questions.

- [ ] **Step 2: Read the research file and identify schema decisions**

Open `docs/superpowers/specs/2026-05-14-ushell-statusline-research.md`. For each `❓ NOT FOUND` item, decide:

- *Can we proceed without it?* (e.g., if multi-line statusline is unconfirmed, design L1-only fallback)
- *Or do we need to empirically test?* (e.g., write a minimal hook, see what env vars it receives)

Append a "Decisions" section to the research file capturing what we'll do for each unknown.

- [ ] **Step 3: Commit the research**

```bash
git add docs/superpowers/specs/2026-05-14-ushell-statusline-research.md
git commit -m "docs(spec): statusline research findings + schema decisions"
```

---

### Task A2: Progress-patterns table + test fixtures

The progress regex table is the only pure-data, pure-function part of the system. Easy TDD, builds confidence in the rest.

**Files:**
- Create: `scripts/progress-patterns.json`
- Create: `tests/statusline/fixtures/cook-output.txt`
- Create: `tests/statusline/fixtures/build-output.txt`
- Create: `tests/statusline/fixtures/uat-bcr-output.txt`
- Create: `tests/statusline/fixtures/p4-sync-output.txt`
- Create: `tests/statusline/test-progress-patterns.ps1`

- [ ] **Step 1: Write the failing test first**

Create `tests/statusline/test-progress-patterns.ps1`:

```powershell
# Pester-free, just simple assertions — keep dependencies minimal.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Test-Pattern {
    param(
        [string]$VerbPattern,
        [string]$FixturePath,
        [hashtable]$Expected
    )
    $patterns = Get-Content "$here/../../scripts/progress-patterns.json" -Raw | ConvertFrom-Json
    $entry = $patterns.patterns | Where-Object { $_.verb -eq $VerbPattern }
    if (-not $entry) { throw "No pattern entry for verb='$VerbPattern'" }
    $tail = Get-Content $FixturePath -Raw
    if ($tail -notmatch $entry.regex) {
        throw "Regex '$($entry.regex)' did not match fixture '$FixturePath'"
    }
    foreach ($key in $Expected.Keys) {
        $actual = $Matches[$key]
        if ($actual -ne $Expected[$key]) {
            throw "Group '$key': expected '$($Expected[$key])', got '$actual'"
        }
    }
    Write-Host "  ✓ $VerbPattern on $(Split-Path $FixturePath -Leaf)"
}

Write-Host "test-progress-patterns:"
Test-Pattern -VerbPattern '.cook'   -FixturePath "$here/fixtures/cook-output.txt"   -Expected @{ n='450'; t='477' }
Test-Pattern -VerbPattern '.build'  -FixturePath "$here/fixtures/build-output.txt"  -Expected @{ n='42';  t='118' }
Test-Pattern -VerbPattern '.p4 sync' -FixturePath "$here/fixtures/p4-sync-output.txt" -Expected @{ n='8423'; t='12903' }
Write-Host "all green"
```

- [ ] **Step 2: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-progress-patterns.ps1
```

Expected: `Cannot find path '.../scripts/progress-patterns.json'` (file doesn't exist yet).

- [ ] **Step 3: Create the fixture files with real ushell output snippets**

Create `tests/statusline/fixtures/cook-output.txt`:

```
[2026.05.14-11.34.10:999][  0]LogShaderCompilers: Display: ================================================
[2026.05.14-11.34.11:185][  0]LogCook: Display: Cooked packages 449 Packages Remain 28 Total 477
[2026.05.14-11.34.12:128][  0]LogCook: Display: Garbage collection triggered (Soft).
[2026.05.14-11.34.14:070][  0]LogCook: Display: Cooked packages 450 Packages Remain 27 Total 477
```

Create `tests/statusline/fixtures/build-output.txt`:

```
Building 1 actions
[1/118] Compiling Module.LyraGame.1.cpp
[2/118] Compiling Module.LyraGame.2.cpp
[42/118] Compiling Module.GameFeatures.cpp
```

Create `tests/statusline/fixtures/p4-sync-output.txt`:

```
... (file sync log entries)
Files synced: 8423 of 12903 files
... (further sync entries)
```

Create `tests/statusline/fixtures/uat-bcr-output.txt` (a few cook lines, matches same `.cook` regex):

```
********** COOK COMMAND STARTED **********
[2026.05.14-11.34.11:185][  0]LogCook: Display: Cooked packages 449 Packages Remain 28 Total 477
[2026.05.14-11.34.14:070][  0]LogCook: Display: Cooked packages 450 Packages Remain 27 Total 477
```

- [ ] **Step 4: Create `scripts/progress-patterns.json`**

```json
{
  "schema_version": 1,
  "patterns": [
    {
      "verb": ".cook",
      "regex": "LogCook: Display: Cooked packages (?<n>\\d+) Packages Remain \\d+ Total (?<t>\\d+)",
      "format": "{n}/{t}"
    },
    {
      "verb": ".build",
      "regex": "\\[(?<n>\\d+)/(?<t>\\d+)\\] ",
      "format": "{n}/{t}"
    },
    {
      "verb": ".uat BuildCookRun",
      "regex": "LogCook: Display: Cooked packages (?<n>\\d+) Packages Remain \\d+ Total (?<t>\\d+)",
      "format": "{n}/{t}",
      "note": "Falls back to .cook pattern during the cook phase. Build phase reuses .build pattern."
    },
    {
      "verb": ".p4 sync",
      "regex": "Files synced: (?<n>\\d+) of (?<t>\\d+) files",
      "format": "{n}/{t}"
    }
  ]
}
```

- [ ] **Step 5: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-progress-patterns.ps1
```

Expected: 3 ✓ lines, "all green".

If a regex doesn't match: inspect the fixture, adjust the regex, re-run. The `(?<n>...)` `(?<t>...)` named groups are PowerShell-compatible.

- [ ] **Step 6: Commit**

```bash
git add scripts/progress-patterns.json tests/statusline/
git commit -m "feat(statusline): progress-patterns table + regex fixtures + unit test"
```

---

### Task A3: State module (`scripts/lib/state.psm1`)

Atomic JSON read/write with last-writer-wins semantics. Single module, two exported functions.

**Files:**
- Create: `scripts/lib/state.psm1`
- Create: `tests/statusline/test-state-module.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/statusline/test-state-module.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/../../scripts/lib/state.psm1" -Force

$testStateFile = Join-Path $env:TEMP "ushell-state-test-$(Get-Random).json"
try {
    # Empty state: read returns default skeleton
    $s = Get-UshellState -Path $testStateFile
    if ($null -ne $s.active) { throw "fresh state should have active=null" }
    if ($null -ne $s.last)   { throw "fresh state should have last=null" }
    if ($s.schema_version -ne 1) { throw "fresh state should have schema_version=1" }

    # Write + read round-trip
    $s.active = [pscustomobject]@{ command = '.cook game Win64'; verb = 'cook' }
    Set-UshellState -Path $testStateFile -State $s
    $s2 = Get-UshellState -Path $testStateFile
    if ($s2.active.command -ne '.cook game Win64') { throw "round-trip lost active.command" }

    # Atomic write: tmp file is gone after Set
    if (Test-Path "$testStateFile.tmp") { throw "tmp file leaked after Set-UshellState" }

    Write-Host "test-state-module: all green"
} finally {
    Remove-Item $testStateFile -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-state-module.ps1
```

Expected: `Cannot find module ... state.psm1`.

- [ ] **Step 3: Write `scripts/lib/state.psm1`**

```powershell
# scripts/lib/state.psm1
$script:SchemaVersion = 1

function Get-UshellState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            schema_version = $script:SchemaVersion
            active  = $null
            last    = $null
            context = $null
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        if ($obj.schema_version -ne $script:SchemaVersion) {
            # Forward-incompatible — log and return default. Statusline will render mismatch hint.
            Write-Verbose "schema_version mismatch: file=$($obj.schema_version), expected=$($script:SchemaVersion)"
            return [pscustomobject]@{
                schema_version = $script:SchemaVersion
                active  = $null
                last    = $null
                context = $null
                _stale  = $true
            }
        }
        # Ensure fields exist even if file was hand-edited
        foreach ($k in 'active','last','context') {
            if (-not ($obj.PSObject.Properties.Name -contains $k)) {
                $obj | Add-Member -NotePropertyName $k -NotePropertyValue $null
            }
        }
        return $obj
    } catch {
        Write-Verbose "Failed to parse state file '$Path': $_"
        return [pscustomobject]@{
            schema_version = $script:SchemaVersion
            active  = $null
            last    = $null
            context = $null
            _stale  = $true
        }
    }
}

function Set-UshellState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$State
    )

    # Ensure parent dir exists
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $State.schema_version = $script:SchemaVersion
    $tmp = "$Path.tmp"
    $json = $State | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    # Atomic rename. Move-Item -Force replaces existing on Windows.
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

Export-ModuleMember -Function Get-UshellState, Set-UshellState
```

- [ ] **Step 4: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-state-module.ps1
```

Expected: `test-state-module: all green`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/state.psm1 tests/statusline/test-state-module.ps1
git commit -m "feat(statusline): atomic state-file read/write module"
```

---

### Task A4: ushell command detection (`scripts/lib/ushell-detect.psm1`)

Parse a Bash/PowerShell tool's command string. Detect whether it's ushell-shaped, extract verb, project path, engine path, engine kind.

**Files:**
- Create: `scripts/lib/ushell-detect.psm1`
- Create: `tests/statusline/test-ushell-detect.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/statusline/test-ushell-detect.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/../../scripts/lib/ushell-detect.psm1" -Force

function Assert-Equal($expected, $actual, $msg) {
    if ($expected -ne $actual) { throw "$msg : expected='$expected' actual='$actual'" }
}

# Case 1: standard cmd /d /s /c wrapper around ushell.bat
$cmd = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true" }
Assert-Equal '.cook' $r.Verb 'verb'
Assert-Equal 'E:\Work\Games\ProjectGear\ProjectGear.uproject' $r.ProjectPath 'project_path'
Assert-Equal 'E:\UE_5.7' $r.EnginePath 'engine_path'

# Case 2: RunUAT.bat direct (the installed-engine carve-out)
$cmd = 'E:\UE_5.7\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project=E:\Work\Games\ProjectGear\ProjectGear.uproject -target=ProjectGear -platform=Win64 -clientconfig=Shipping -build'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true for RunUAT" }
Assert-Equal 'RunUAT.bat BuildCookRun' $r.Verb 'verb'
Assert-Equal 'E:\Work\Games\ProjectGear\ProjectGear.uproject' $r.ProjectPath 'project_path'
Assert-Equal 'E:\UE_5.7' $r.EnginePath 'engine_path'

# Case 3: non-ushell — git status
$cmd = 'cd "E:\Work\ushell-skill" && git status --short'
$r = Parse-UshellCommand -Command $cmd
if ($r.IsUshell) { throw "expected IsUshell=false for git status" }

# Case 4: chained command
$cmd = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .build editor && .build game Win64 shipping && .cook game Win64"'
$r = Parse-UshellCommand -Command $cmd
# For a chain we report the LAST ushell verb (the goal of the chain)
Assert-Equal '.cook' $r.Verb 'chain: last verb'

Write-Host "test-ushell-detect: all green"
```

- [ ] **Step 2: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-ushell-detect.ps1
```

Expected: `Cannot find module ... ushell-detect.psm1`.

- [ ] **Step 3: Write `scripts/lib/ushell-detect.psm1`**

```powershell
# scripts/lib/ushell-detect.psm1

function Parse-UshellCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command)

    $isUshellBat = $Command -match '\bushell\.bat\b'
    $isRunUAT    = $Command -match '\bRunUAT\.bat\b'
    $isUbt       = $Command -match '\bUnrealBuildTool\.exe\b'
    $isEditor    = $Command -match '\bUnrealEditor(-Cmd)?\.exe\b'

    if (-not ($isUshellBat -or $isRunUAT -or $isUbt -or $isEditor)) {
        return [pscustomobject]@{ IsUshell = $false }
    }

    # Verb extraction
    $verb = $null
    if ($isUshellBat) {
        # Find ALL `.<verb>` occurrences (chain support); take the last one.
        $matches = [regex]::Matches($Command, '\s\.(?<v>\w+)(\s|"|$)')
        if ($matches.Count -gt 0) { $verb = '.' + $matches[$matches.Count - 1].Groups['v'].Value }
    } elseif ($isRunUAT) {
        if ($Command -match 'RunUAT\.bat\s+(?<v>\w+)') { $verb = "RunUAT.bat $($Matches.v)" }
        else { $verb = 'RunUAT.bat' }
    } elseif ($isUbt) {
        $verb = 'UnrealBuildTool'
    } elseif ($isEditor) {
        $verb = 'UnrealEditor'
    }

    # Project path: from -project=<path> or --project=<path>
    $projectPath = $null
    if ($Command -match '-{1,2}project=("(?<p>[^"]+)"|(?<p>[^\s"]+))') {
        $projectPath = $Matches['p']
    }

    # Engine path: take parent of ...\Engine\... in the command string
    $enginePath = $null
    if ($Command -match '(?<e>[A-Za-z]:\\[^"\s]+?)\\Engine\\') {
        $enginePath = $Matches['e']
    }

    [pscustomobject]@{
        IsUshell    = $true
        Verb        = $verb
        ProjectPath = $projectPath
        EnginePath  = $enginePath
    }
}

function Get-EngineKind {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EnginePath)
    $marker = Join-Path $EnginePath 'Engine/Build/InstalledBuild.txt'
    if (Test-Path -LiteralPath $marker) { return 'installed' } else { return 'source' }
}

function Get-EngineBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EnginePath)
    $verFile = Join-Path $EnginePath 'Engine/Build/Build.version'
    if (-not (Test-Path -LiteralPath $verFile)) { return $null }
    try {
        $ver = Get-Content -LiteralPath $verFile -Raw | ConvertFrom-Json
        return $ver.BranchName
    } catch { return $null }
}

Export-ModuleMember -Function Parse-UshellCommand, Get-EngineKind, Get-EngineBranch
```

- [ ] **Step 4: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-ushell-detect.ps1
```

Expected: `test-ushell-detect: all green`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/ushell-detect.psm1 tests/statusline/test-ushell-detect.ps1
git commit -m "feat(statusline): ushell command detection + verb/project/engine parsing"
```

---

### Task A5: Progress tail module (`scripts/lib/progress-tail.psm1`)

Incremental tailing — track read position in a small cache file, only read new bytes on each call, scan tail for the verb's progress regex.

**Files:**
- Create: `scripts/lib/progress-tail.psm1`
- Create: `tests/statusline/test-progress-tail.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/statusline/test-progress-tail.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/../../scripts/lib/progress-tail.psm1" -Force

$tmpOutput = Join-Path $env:TEMP "ushell-tail-test-$(Get-Random).txt"
$tmpCache  = Join-Path $env:TEMP "ushell-tail-cache-$(Get-Random).json"
try {
    Set-Content -LiteralPath $tmpOutput -Value @(
        '[2026.05.14-11.30.00] LogCook: Display: Cooked packages 100 Packages Remain 377 Total 477'
        '[2026.05.14-11.31.00] LogCook: Display: Cooked packages 200 Packages Remain 277 Total 477'
    )
    $regex = 'LogCook: Display: Cooked packages (?<n>\d+) Packages Remain \d+ Total (?<t>\d+)'
    $progress = Get-Progress -OutputFile $tmpOutput -CacheFile $tmpCache -Regex $regex
    if ($progress.N -ne 200 -or $progress.T -ne 477) {
        throw "expected n=200 t=477, got n=$($progress.N) t=$($progress.T)"
    }

    # Append more output; tail again; expect new latest reading.
    Add-Content -LiteralPath $tmpOutput -Value '[2026.05.14-11.32.00] LogCook: Display: Cooked packages 300 Packages Remain 177 Total 477'
    $progress = Get-Progress -OutputFile $tmpOutput -CacheFile $tmpCache -Regex $regex
    if ($progress.N -ne 300) { throw "expected updated n=300, got $($progress.N)" }

    Write-Host "test-progress-tail: all green"
} finally {
    Remove-Item $tmpOutput, $tmpCache -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-progress-tail.ps1
```

Expected: `Cannot find module ... progress-tail.psm1`.

- [ ] **Step 3: Write `scripts/lib/progress-tail.psm1`**

```powershell
# scripts/lib/progress-tail.psm1

function Get-Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][string]$CacheFile,
        [Parameter(Mandatory)][string]$Regex,
        [int]$TailBytes = 65536    # last 64K is plenty for progress regex
    )

    if (-not (Test-Path -LiteralPath $OutputFile)) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'no-output-file' }
    }

    $fi = Get-Item -LiteralPath $OutputFile
    $len = $fi.Length
    if ($len -le 0) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'empty' }
    }

    # Read last $TailBytes
    $start = [Math]::Max(0, $len - $TailBytes)
    $stream = [System.IO.File]::Open($OutputFile, 'Open', 'Read', 'ReadWrite')
    try {
        $stream.Seek($start, 'Begin') | Out-Null
        $buf = New-Object byte[] ($len - $start)
        $read = $stream.Read($buf, 0, $buf.Length)
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    } finally {
        $stream.Dispose()
    }

    # Find the LAST match — that's the most recent progress reading
    $rx = [regex]::new($Regex)
    $matches = $rx.Matches($text)
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'no-match-yet' }
    }
    $last = $matches[$matches.Count - 1]
    $n = [int]$last.Groups['n'].Value
    $t = [int]$last.Groups['t'].Value

    # Cache the reading + timestamp for ETA later (Task A7)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cache = @{
        last_n = $n
        last_t = $t
        last_ts = $now
        history = @()
    }
    if (Test-Path -LiteralPath $CacheFile) {
        try {
            $old = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
            if ($old.history) {
                $cache.history = @($old.history) + @(@{ n = $n; ts = $now }) | Select-Object -Last 30
            }
        } catch { }
    }
    $cache | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CacheFile -Encoding UTF8

    [pscustomobject]@{ N = $n; T = $t; Status = 'ok' }
}

Export-ModuleMember -Function Get-Progress
```

- [ ] **Step 4: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-progress-tail.ps1
```

Expected: `test-progress-tail: all green`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/progress-tail.psm1 tests/statusline/test-progress-tail.ps1
git commit -m "feat(statusline): incremental tail + progress-regex extraction"
```

---

### Task A6: Hook script (`scripts/hook-update.ps1`)

Glue: receive hook input, parse, update state file.

**Files:**
- Create: `scripts/hook-update.ps1`
- Create: `tests/statusline/test-hook-update.ps1`

- [ ] **Step 1: Determine the hook input contract**

Re-read `docs/superpowers/specs/2026-05-14-ushell-statusline-research.md` (from Task A1) for the answer to "how does the hook receive the tool-call command string and exit code." Two likely shapes (CC docs will confirm):

- **stdin JSON**: `{"tool_name":"Bash", "tool_input":{...}, "tool_response":..., "task_id":"..."}`
- **env vars**: `CLAUDE_TOOL_NAME`, `CLAUDE_TOOL_INPUT_JSON`, etc.

Pick the documented shape. If research said `❓ NOT FOUND`, write the script to handle BOTH (try stdin first, fall back to env). The conditional adds maybe 10 lines.

- [ ] **Step 2: Write the failing integration test**

```powershell
# tests/statusline/test-hook-update.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$hookScript = "$here/../../scripts/hook-update.ps1"
Import-Module "$here/../../scripts/lib/state.psm1" -Force

$testState = Join-Path $env:TEMP "ushell-state-hooktest-$(Get-Random).json"
$env:USHELL_STATE_FILE = $testState
try {
    # Phase: pre — Bash tool call to a ushell command
    $hookInput = @{
        tool_name  = 'Bash'
        tool_input = @{ command = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"'; run_in_background = $true }
        task_id    = 'bxxxxxxxx'
        output_file = "$env:TEMP\fake-task-output.txt"
    } | ConvertTo-Json -Depth 5

    $hookInput | pwsh -NoProfile -File $hookScript -Phase pre
    if ($LASTEXITCODE -ne 0) { throw "pre hook exited $LASTEXITCODE" }

    $s = Get-UshellState -Path $testState
    if ($null -eq $s.active) { throw "expected active to be populated" }
    if ($s.active.verb -ne '.cook') { throw "expected verb='.cook', got $($s.active.verb)" }
    if ($s.active.project -ne 'ProjectGear') { throw "expected project='ProjectGear', got $($s.active.project)" }

    # Phase: post — completion
    $hookInput = @{
        tool_name = 'Bash'
        tool_input = @{ command = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"' }
        tool_response = @{ exit_code = 0 }
        task_id    = 'bxxxxxxxx'
    } | ConvertTo-Json -Depth 5

    $hookInput | pwsh -NoProfile -File $hookScript -Phase post
    if ($LASTEXITCODE -ne 0) { throw "post hook exited $LASTEXITCODE" }

    $s = Get-UshellState -Path $testState
    if ($null -ne $s.active) { throw "expected active=null after post, got $($s.active)" }
    if ($s.last.result -ne 'ok') { throw "expected last.result='ok', got $($s.last.result)" }
    if ($s.last.exit_code -ne 0) { throw "expected last.exit_code=0, got $($s.last.exit_code)" }

    Write-Host "test-hook-update: all green"
} finally {
    Remove-Item $testState -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\USHELL_STATE_FILE -ErrorAction SilentlyContinue
}
```

- [ ] **Step 3: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-hook-update.ps1
```

Expected: `Cannot find path ... hook-update.ps1`.

- [ ] **Step 4: Write `scripts/hook-update.ps1`**

```powershell
# scripts/hook-update.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('pre','post')]
    [string]$Phase
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/lib/state.psm1" -Force
Import-Module "$here/lib/ushell-detect.psm1" -Force

$StateFile = if ($env:USHELL_STATE_FILE) { $env:USHELL_STATE_FILE } else { Join-Path $HOME '.claude/ushell-state.json' }

# Read hook input from stdin (JSON). Fall back to env vars if stdin is empty.
$stdin = [Console]::In.ReadToEnd()
$hookInput = $null
if ($stdin) {
    try { $hookInput = $stdin | ConvertFrom-Json } catch { }
}
if (-not $hookInput) {
    # Try env-var convention
    $hookInput = [pscustomobject]@{
        tool_name = $env:CLAUDE_TOOL_NAME
        tool_input = $env:CLAUDE_TOOL_INPUT_JSON | ConvertFrom-Json
        tool_response = $env:CLAUDE_TOOL_RESPONSE_JSON | ConvertFrom-Json
        task_id = $env:CLAUDE_TASK_ID
        output_file = $env:CLAUDE_TASK_OUTPUT_FILE
    }
}
if (-not $hookInput -or -not $hookInput.tool_name) {
    # Nothing to act on
    exit 0
}

# Only Bash / PowerShell tools matter
if ($hookInput.tool_name -notin 'Bash','PowerShell') { exit 0 }

$cmd = $hookInput.tool_input.command
if (-not $cmd) { exit 0 }

$parsed = Parse-UshellCommand -Command $cmd
if (-not $parsed.IsUshell) { exit 0 }

$state = Get-UshellState -Path $StateFile

if ($Phase -eq 'pre') {
    $engineKind = if ($parsed.EnginePath) { Get-EngineKind -EnginePath $parsed.EnginePath } else { $null }
    $engineBranch = if ($parsed.EnginePath) { Get-EngineBranch -EnginePath $parsed.EnginePath } else { $null }
    $projectName = if ($parsed.ProjectPath) { [System.IO.Path]::GetFileNameWithoutExtension($parsed.ProjectPath) } else { $null }
    $projectDir  = if ($parsed.ProjectPath) { Split-Path -Parent $parsed.ProjectPath } else { $null }

    $state.active = [pscustomobject]@{
        task_id       = $hookInput.task_id
        output_file   = $hookInput.output_file
        command       = $cmd
        verb          = $parsed.Verb
        verb_args     = $null
        project       = $projectName
        project_path  = $projectDir
        engine        = $parsed.EnginePath
        engine_branch = $engineBranch
        engine_kind   = $engineKind
        started       = (Get-Date).ToUniversalTime().ToString('o')
    }
    $state.context = [pscustomobject]@{
        project      = $projectName
        project_path = $projectDir
        engine       = $parsed.EnginePath
        engine_kind  = $engineKind
    }
    Set-UshellState -Path $StateFile -State $state
}

if ($Phase -eq 'post') {
    if (-not $state.active) {
        # No matching pre — defensive no-op
        exit 0
    }
    $exitCode = if ($hookInput.tool_response.exit_code) { [int]$hookInput.tool_response.exit_code } else { 0 }
    $started = [DateTimeOffset]::Parse($state.active.started)
    $finished = [DateTimeOffset]::UtcNow

    $state.last = [pscustomobject]@{
        command    = $state.active.command
        verb       = $state.active.verb
        project    = $state.active.project
        result     = if ($exitCode -eq 0) { 'ok' } else { 'fail' }
        exit_code  = $exitCode
        finished   = $finished.ToString('o')
        duration_s = [int]($finished - $started).TotalSeconds
        note       = $null
    }
    $state.active = $null
    Set-UshellState -Path $StateFile -State $state
}

exit 0
```

- [ ] **Step 5: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-hook-update.ps1
```

Expected: `test-hook-update: all green`.

- [ ] **Step 6: Commit**

```bash
git add scripts/hook-update.ps1 tests/statusline/test-hook-update.ps1
git commit -m "feat(statusline): hook script — pre+post tool-call state updates"
```

---

### Task A7: Statusline renderer (`scripts/statusline.ps1`)

Read state, optionally tail output file, render 1-3 lines.

**Files:**
- Create: `scripts/statusline.ps1`
- Create: `tests/statusline/test-statusline-render.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
# tests/statusline/test-statusline-render.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$scriptPath = "$here/../../scripts/statusline.ps1"
Import-Module "$here/../../scripts/lib/state.psm1" -Force

$testState = Join-Path $env:TEMP "ushell-state-rendertest-$(Get-Random).json"
$env:USHELL_STATE_FILE = $testState
try {
    # Case 1: idle, has context + last
    $s = [pscustomobject]@{
        schema_version = 1
        active = $null
        last = [pscustomobject]@{
            command = '.build game Win64 shipping'
            result = 'ok'
            exit_code = 0
            finished = '2026-05-14T11:51:23Z'
        }
        context = [pscustomobject]@{
            project = 'ProjectGear'
            project_path = 'E:\Work\Games\ProjectGear'
            engine = 'E:\UE_5.7'
            engine_kind = 'installed'
        }
    }
    Set-UshellState -Path $testState -State $s
    $out = pwsh -NoProfile -File $scriptPath
    if ($out -notmatch 'ProjectGear @ UE_5\.7 \(installed\)') {
        throw "L1 missing or wrong: $out"
    }
    if ($out -notmatch 'idle') { throw "L2 should be 'idle' when active=null" }
    if ($out -notmatch 'last:.*\.build game Win64 shipping.*✓') {
        throw "L3 missing or wrong: $out"
    }

    # Case 2: state file missing
    Remove-Item -LiteralPath $testState -Force
    $out = pwsh -NoProfile -File $scriptPath
    if ($out -notmatch 'no context') { throw "expected 'no context' fallback, got: $out" }

    Write-Host "test-statusline-render: all green"
} finally {
    Remove-Item $testState -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\USHELL_STATE_FILE -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Run the test, confirm it fails**

```powershell
pwsh -NoProfile -File tests/statusline/test-statusline-render.ps1
```

Expected: `Cannot find path ... statusline.ps1`.

- [ ] **Step 3: Write `scripts/statusline.ps1`**

```powershell
# scripts/statusline.ps1
[CmdletBinding()] param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/lib/state.psm1" -Force
Import-Module "$here/lib/progress-tail.psm1" -Force

$StateFile = if ($env:USHELL_STATE_FILE) { $env:USHELL_STATE_FILE } else { Join-Path $HOME '.claude/ushell-state.json' }
$CacheDir  = Split-Path -Parent $StateFile

# Read state
$state = Get-UshellState -Path $StateFile
if ($state._stale) {
    Write-Output "(ushell: state version mismatch — upgrade plugin)"
    exit 0
}
if ($null -eq $state.active -and $null -eq $state.last -and $null -eq $state.context) {
    Write-Output "(ushell: no context)"
    exit 0
}

# Helpers
function Format-EngineShort($enginePath) {
    if (-not $enginePath) { return '?' }
    return (Split-Path -Leaf $enginePath)
}
function Format-Time($iso) {
    try { return ([DateTimeOffset]::Parse($iso).ToLocalTime().ToString('HH:mm')) } catch { return '?' }
}

# L1: Context
$ctx = $state.context
if (-not $ctx -and $state.active) {
    $ctx = [pscustomobject]@{
        project = $state.active.project
        engine = $state.active.engine
        engine_kind = $state.active.engine_kind
    }
}
if ($ctx) {
    $proj = if ($ctx.project) { $ctx.project } else { '?' }
    $engineShort = Format-EngineShort $ctx.engine
    $kind = if ($ctx.engine_kind) { $ctx.engine_kind } else { '?' }
    $l1 = "$proj @ $engineShort ($kind)"
    Write-Output $l1
}

# L2: Active or idle
if ($state.active) {
    $verb = $state.active.command
    # Truncate to keep statusline tidy
    if ($verb.Length -gt 60) {
        $verb = $verb.Substring(0, 57) + '...'
    }
    # Try to get progress
    $patternsFile = Join-Path $here 'progress-patterns.json'
    $progressStr = 'starting...'
    if ((Test-Path -LiteralPath $patternsFile) -and $state.active.output_file -and (Test-Path -LiteralPath $state.active.output_file)) {
        try {
            $patterns = Get-Content $patternsFile -Raw | ConvertFrom-Json
            $entry = $patterns.patterns | Where-Object { $state.active.verb -like "$($_.verb)*" } | Select-Object -First 1
            if ($entry) {
                $cacheFile = "$StateFile.tail.json"
                $p = Get-Progress -OutputFile $state.active.output_file -CacheFile $cacheFile -Regex $entry.regex
                if ($p.Status -eq 'ok') {
                    $progressStr = "$($p.N)/$($p.T)"
                    # ETA — crude linear extrapolation from cache history
                    try {
                        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
                        if ($cache.history -and $cache.history.Count -ge 2) {
                            $first = $cache.history[0]
                            $last  = $cache.history[-1]
                            $dN = $last.n - $first.n
                            $dT = $last.ts - $first.ts
                            if ($dT -gt 0 -and $dN -gt 0) {
                                $rate = $dN / $dT
                                $remaining = $p.T - $p.N
                                $etaSec = [int]($remaining / $rate)
                                if ($etaSec -lt 120) { $progressStr += " · ~$($etaSec)s" }
                                else { $progressStr += " · ~$([int]($etaSec/60))m" }
                            }
                        }
                    } catch { }
                }
            }
        } catch { }
    }
    Write-Output "$verb · $progressStr"
} else {
    Write-Output "idle"
}

# L3: Last
if ($state.last) {
    $cmd = $state.last.command
    if ($cmd.Length -gt 50) { $cmd = $cmd.Substring(0, 47) + '...' }
    $glyph = if ($state.last.result -eq 'ok') { '✓' } else { '✗' }
    $when = Format-Time $state.last.finished
    $line = "last: $cmd $glyph $when"
    if ($state.last.note) { $line += " · $($state.last.note)" }
    Write-Output $line
}

exit 0
```

- [ ] **Step 4: Run the test, confirm it passes**

```powershell
pwsh -NoProfile -File tests/statusline/test-statusline-render.ps1
```

Expected: `test-statusline-render: all green`.

- [ ] **Step 5: Commit**

```bash
git add scripts/statusline.ps1 tests/statusline/test-statusline-render.ps1
git commit -m "feat(statusline): 3-line renderer with context/active+progress/last"
```

---

### Task A8: Wire into `~/.claude/settings.json` for this session

This is the part that makes the demo actually work.

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Read the current settings.json**

```powershell
$settings = Get-Content "$HOME/.claude/settings.json" -Raw
Write-Host $settings
```

Confirm what's already there. Note any existing `statusLine` or `hooks` blocks — we need to merge, not overwrite.

- [ ] **Step 2: Add the statusLine + hooks blocks**

Edit `~/.claude/settings.json` to add (or merge with existing):

```json
{
  "...existing settings...": "...",
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File E:/Work/ushell-skill/scripts/statusline.ps1"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [{
          "type": "command",
          "command": "pwsh -NoProfile -File E:/Work/ushell-skill/scripts/hook-update.ps1 -Phase pre"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [{
          "type": "command",
          "command": "pwsh -NoProfile -File E:/Work/ushell-skill/scripts/hook-update.ps1 -Phase post"
        }]
      }
    ]
  }
}
```

Use the Edit tool to perform the merge. Preserve existing fields.

- [ ] **Step 3: Verify settings.json parses cleanly**

```powershell
Get-Content "$HOME/.claude/settings.json" -Raw | ConvertFrom-Json | Out-Null
Write-Host "settings.json parses OK"
```

Expected: no output errors. If it fails, fix the JSON syntax.

- [ ] **Step 4: Check if statusline appears immediately**

If Claude Code hot-reloads settings.json (likely with newer versions), the statusline should appear within a few seconds. If not, the user may need to issue a slash command like `/config reload` (verify availability per A1 research) or restart their session.

Document what's needed. If a restart is required, explicitly note this to the user — the demo continuing requires the user to either restart CC or use a config-reload mechanism.

- [ ] **Step 5: Commit the settings change (NOT to the repo)**

`~/.claude/settings.json` is not part of this repo. No commit needed — it's local user config.

---

### Task A9: Demo run — cook ProjectGear with live statusline

The terminal verification of the whole feature.

- [ ] **Step 1: Confirm statusline is rendering**

Look at the statusline area of Claude Code. Should show:

```
ProjectGear @ UE_5.7 (installed)
idle
last: .cook game Win64 ✗ 12:38 · 1err/6warn
```

(L3 may differ depending on most-recent ushell command at session start.)

If statusline is empty or shows an error, debug:
- Check `~/.claude/ushell-state.json` — does it exist and parse?
- Run `pwsh -NoProfile -File E:/Work/ushell-skill/scripts/statusline.ps1` manually — does it output the expected lines?
- Inspect `~/.claude/ushell-state.error.log` if it exists.

- [ ] **Step 2: Trigger a fresh cook to demo live progress**

From the Claude conversation: invoke a cook via the Bash tool. Same command we ran in Task #17:

```powershell
cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"
```

Run as background command (`run_in_background: true`).

- [ ] **Step 3: Watch the statusline update**

Within 5 seconds, the statusline should transition to:

```
ProjectGear @ UE_5.7 (installed)
cmd.exe /d /s /c "call ... && .cook game Win64" · starting...
last: ...
```

Within ~30 seconds (once cook starts emitting `LogCook: Display: Cooked packages` lines), should update to:

```
ProjectGear @ UE_5.7 (installed)
... · .cook game Win64 · 12/477 · ~22m
last: ...
```

The N/T number should increment over time. ETA should refine.

- [ ] **Step 4: Wait for completion and verify transition to idle**

After ~20-25 minutes the cook completes. PostToolUse hook fires. Statusline transitions to:

```
ProjectGear @ UE_5.7 (installed)
idle
last: .cook game Win64 ✓ HH:MM
```

(✗ if cook exited 1 again — that's still a successful demo of the *statusline*, just not of the cook.)

- [ ] **Step 5: Capture demo evidence**

Take a screenshot or paste the statusline lines from each phase (starting / mid-cook / completed) into `tests/battle-test-statusline.md`. Note timings, any quirks observed, any failure modes hit.

- [ ] **Step 6: Commit the battle-test log**

```bash
git add tests/battle-test-statusline.md
git commit -m "test(statusline): battle-test demo log — live cook progress on ProjectGear"
```

---

## Phase B — Shipping path (follow-up, after demo passes)

Once Phase A demo works, port the wiring from `~/.claude/settings.json` to the plugin manifest so future installs are zero-config.

### Task B1: Extend `.claude-plugin/plugin.json`

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read current plugin.json**

```powershell
Get-Content ".claude-plugin/plugin.json" -Raw
```

- [ ] **Step 2: Add statusLine + hooks fields**

Add the fields from Task A8 to `.claude-plugin/plugin.json`. Replace the hard-coded `E:/Work/ushell-skill/scripts/...` paths with `${PLUGIN_DIR}/scripts/...` (per Task A1 research's confirmed template).

If A1 research said `${PLUGIN_DIR}` is not supported in plugin.json, fall back to:
- Document in README that the user manually adds the block from Task A8 to their settings.json, OR
- Ship a post-install script (if plugin spec supports one) that writes the merged settings.

- [ ] **Step 3: Bump version**

```json
"version": "2.1.0"
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat(plugin): ship statusLine + hooks for ushell live progress"
```

### Task B2: README install update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a "Live statusline" section**

Document what the statusline shows + the install command (still just `/plugin install`) + any troubleshooting if hooks don't fire.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): document the live statusline feature"
```

### Task B3: Verify plugin install end-to-end

In a **fresh Claude Code session** (not this one — needs a clean settings.json without the manual wiring from Task A8):

- [ ] **Step 1: Remove the manual settings.json wiring** (done in Task A8) so the plugin install is the only source of statusLine config.

- [ ] **Step 2: `/plugin install ushell@ABostrom-skills`**

- [ ] **Step 3: Verify statusLine + hooks are configured** — `~/.claude/settings.json` may or may not be auto-merged; check whatever surface the plugin uses.

- [ ] **Step 4: Trigger a small ushell command** (e.g., `.info`) — verify statusline shows context, last result.

- [ ] **Step 5: Commit any troubleshooting README updates surfaced by this run.**

---

## Phase C — Cross-platform follow-ups (further future)

### Task C1: bash variants

Out-of-scope for the v1 demo; ship later. Implement `scripts/hook-update.sh` and `scripts/statusline.sh` mirroring the PowerShell logic with `jq` for JSON.

---

## Self-review checklist

- [x] **Spec coverage:** All sections of the spec mapped to tasks. Architecture diagram → Tasks A3-A7. State schema → A3. Hook script → A6. Renderer → A7. Verb progress regex table → A2. Cross-platform → C1. Error handling → embedded throughout. Testing strategy → unit tests in A2/A3/A4/A5/A6/A7, integration in A6, battle test in A9. Plugin manifest → B1. Open questions → A1.
- [x] **Placeholder scan:** No TBDs, TODOs, "fill in later". A1 explicitly captures the "unknown until verified" cases as the deliverable of that task.
- [x] **Type consistency:** `Get-UshellState` / `Set-UshellState` (A3) used consistently in A6 and A7. `Parse-UshellCommand` (A4) used in A6. `Get-Progress` (A5) used in A7. State schema fields (`active.verb`, `active.output_file`, `last.result`, etc.) used consistently across A3 (definition), A6 (write), A7 (read).
- [x] **Bite-sized:** Each step is one action — write test, run test, write code, run test, commit. No "write the whole thing" steps.
- [x] **Goal mapped:** "Get statusline working + demo in this terminal + run a cook" = Tasks A8 (wire) + A9 (demo). Hard requirement satisfied if Phase A completes.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-14-ushell-statusline.md`.

Two execution options:

1. **Subagent-Driven (recommended for cleanly-isolated tasks like A2–A7)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Each task's TDD cycle is self-contained.

2. **Inline Execution** — execute tasks in this session using executing-plans. Better for A8 + A9 since they touch the live Claude Code instance (settings.json + the actual demo cook) — those steps need to happen in the same session as the user.

A hybrid is also reasonable: subagents for A1–A7 (the script-writing TDD), inline for A8–A9 (the live-wiring + demo).

Which approach?

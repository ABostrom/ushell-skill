# scripts/hook-update.ps1
# Claude Code PreToolUse / PostToolUse hook for the ushell statusline.
# Receives hook context as JSON on stdin (per hooks.md "Command hooks: JSON via stdin").
# Detects ushell-shaped Bash/PowerShell commands and updates ~/.claude/ushell-state.json.
#
# Invoked from hooks.json like:
#   "command": "pwsh -NoProfile -File ${CLAUDE_PLUGIN_ROOT}/scripts/hook-update.ps1 -Phase pre"

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

# State-file location: explicit override > XDG-style default
$StateFile = if ($env:USHELL_STATE_FILE) { $env:USHELL_STATE_FILE } else { Join-Path $HOME '.claude/ushell-state.json' }

# Read hook input (JSON via stdin per hooks.md)
$stdin = [Console]::In.ReadToEnd()
if (-not $stdin) { exit 0 }   # No input → nothing to do

try {
    $hookInput = $stdin | ConvertFrom-Json -ErrorAction Stop
} catch {
    # Malformed input — log and exit gracefully (statusline still renders last-known state)
    $errLog = Join-Path (Split-Path -Parent $StateFile) 'ushell-state.error.log'
    "$(Get-Date -Format 'o') hook-update($Phase): failed to parse stdin JSON: $_" | Add-Content -LiteralPath $errLog
    exit 0
}

# Filter: only Bash and PowerShell tool calls matter
if ($hookInput.tool_name -notin 'Bash','PowerShell') { exit 0 }

$cmd = $hookInput.tool_input.command
if (-not $cmd) { exit 0 }

# Classify command
$parsed = Parse-UshellCommand -Command $cmd
if (-not $parsed.IsUshell) { exit 0 }

# Load existing state
$state = Get-UshellState -Path $StateFile

# --- Phase: pre ---
if ($Phase -eq 'pre') {
    # Compute the harness's tasks directory deterministically:
    #   $env:TEMP\claude\<cwd-mangled>\<session_id>\tasks\
    # cwd-mangling: replace ':' and '\' with '-' in CLAUDE_PROJECT_DIR (or hookInput.cwd fallback)
    $projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $hookInput.cwd }
    $tasksDir = $null
    if ($projectDir -and $hookInput.session_id) {
        $mangled = ($projectDir -replace '[:\\]', '-')
        $tasksDir = Join-Path (Join-Path (Join-Path $env:TEMP 'claude') $mangled) (Join-Path $hookInput.session_id 'tasks')
    }

    # Engine metadata (only if engine path is known)
    $engineKind = $null
    $engineBranch = $null
    if ($parsed.EnginePath) {
        $engineKind   = Get-EngineKind -EnginePath $parsed.EnginePath
        $engineBranch = Get-EngineBranch -EnginePath $parsed.EnginePath
    }

    # Project name + dir
    $projectName  = if ($parsed.ProjectPath) { [System.IO.Path]::GetFileNameWithoutExtension($parsed.ProjectPath) } else { $null }
    $projectPath2 = if ($parsed.ProjectPath) { Split-Path -Parent $parsed.ProjectPath } else { $null }

    $state.active = [pscustomobject]@{
        tool_use_id   = $hookInput.tool_use_id
        tasks_dir     = $tasksDir
        command       = $cmd
        verb          = $parsed.Verb
        project       = $projectName
        project_path  = $projectPath2
        engine        = $parsed.EnginePath
        engine_branch = $engineBranch
        engine_kind   = $engineKind
        started       = (Get-Date).ToUniversalTime().ToString('o')
    }
    # context survives even after the active task ends, so the statusline can show
    # the project/engine when idle
    if ($projectName -or $parsed.EnginePath) {
        $state.context = [pscustomobject]@{
            project      = $projectName
            project_path = $projectPath2
            engine       = $parsed.EnginePath
            engine_kind  = $engineKind
        }
    }
    Set-UshellState -Path $StateFile -State $state
    exit 0
}

# --- Phase: post ---
if ($Phase -eq 'post') {
    # Match this PostToolUse to the active record by tool_use_id; if no match, defensive no-op
    if (-not $state.active) { exit 0 }
    if ($hookInput.tool_use_id -and $state.active.tool_use_id -and $hookInput.tool_use_id -ne $state.active.tool_use_id) {
        # PostToolUse for a different tool call than the one in active — leave state alone
        exit 0
    }

    $exitCode = 0
    if ($hookInput.tool_response -and $hookInput.tool_response.PSObject.Properties.Name -contains 'exit_code') {
        $exitCode = [int]$hookInput.tool_response.exit_code
    }
    $started = $null
    try { $started = [DateTimeOffset]::Parse($state.active.started) } catch { }
    $finished = [DateTimeOffset]::UtcNow
    $durationS = if ($started) { [int]($finished - $started).TotalSeconds } else { $null }

    $state.last = [pscustomobject]@{
        command    = $state.active.command
        verb       = $state.active.verb
        project    = $state.active.project
        result     = if ($exitCode -eq 0) { 'ok' } else { 'fail' }
        exit_code  = $exitCode
        finished   = $finished.ToString('o')
        duration_s = $durationS
        note       = $null
    }
    $state.active = $null
    Set-UshellState -Path $StateFile -State $state
    exit 0
}

exit 0

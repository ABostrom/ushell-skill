# tests/statusline/test-hook-update.ps1
# Integration test for the PreToolUse + PostToolUse hook script.
# Simulates the JSON-stdin contract documented in research findings.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$hookScript = "$here/../../scripts/hook-update.ps1"
if (-not (Test-Path -LiteralPath $hookScript)) {
    throw "hook-update.ps1 not found at $hookScript"
}
Import-Module "$here/../../scripts/lib/state.psm1" -Force

$testState = Join-Path $env:TEMP "ushell-state-hooktest-$(Get-Random).json"
$env:USHELL_STATE_FILE = $testState
$env:CLAUDE_PROJECT_DIR = 'E:\Work\ushell-skill'   # mock — used by hook for cwd-mangling

try {
    Write-Host "test-hook-update:"

    # === Phase pre: Bash tool call to a ushell command ===
    $hookInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        cwd             = 'E:\Work\ushell-skill'
        hook_event_name = 'PreToolUse'
        tool_name       = 'Bash'
        tool_input      = @{
            command           = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"'
            run_in_background = $true
        }
        tool_use_id     = 'b9795py03'
    } | ConvertTo-Json -Depth 5

    $hookInput | pwsh -NoProfile -File $hookScript -Phase pre 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pre hook exited $LASTEXITCODE" }

    $s = Get-UshellState -Path $testState
    if ($null -eq $s.active) { throw "expected active to be populated" }
    if ($s.active.verb -ne '.cook') { throw "expected verb='.cook', got '$($s.active.verb)'" }
    if ($s.active.project -ne 'ProjectGear') { throw "expected project='ProjectGear', got '$($s.active.project)'" }
    if (-not $s.active.tasks_dir) { throw "expected tasks_dir to be populated" }
    if ($s.active.tasks_dir -notlike '*\E--Work-ushell-skill\d00d426b-3a05-4330-88bd-7281a3e32b64\tasks*') {
        throw "tasks_dir didn't include expected cwd-mangling + session_id: '$($s.active.tasks_dir)'"
    }
    if ($s.active.tool_use_id -ne 'b9795py03') {
        throw "expected tool_use_id='b9795py03', got '$($s.active.tool_use_id)'"
    }
    if ($null -eq $s.context) { throw "expected context to be populated" }
    if ($s.context.project -ne 'ProjectGear') { throw "expected context.project='ProjectGear'" }
    Write-Host "  ok pre populates active + context"

    # === Phase post: same task completes successfully ===
    $hookInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        cwd             = 'E:\Work\ushell-skill'
        hook_event_name = 'PostToolUse'
        tool_name       = 'Bash'
        tool_input      = @{
            command = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"'
        }
        tool_response   = @{ exit_code = 0 }
        tool_use_id     = 'b9795py03'
    } | ConvertTo-Json -Depth 5

    $hookInput | pwsh -NoProfile -File $hookScript -Phase post 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "post hook exited $LASTEXITCODE" }

    $s = Get-UshellState -Path $testState
    if ($null -ne $s.active) { throw "expected active=null after post, got non-null" }
    if (-not $s.last) { throw "expected last to be populated" }
    if ($s.last.result -ne 'ok') { throw "expected last.result='ok', got '$($s.last.result)'" }
    if ($s.last.exit_code -ne 0) { throw "expected last.exit_code=0, got '$($s.last.exit_code)'" }
    if ($s.last.verb -ne '.cook') { throw "expected last.verb='.cook', got '$($s.last.verb)'" }
    Write-Host "  ok post moves active to last (success)"

    # === Phase pre + post: same task FAILS this time ===
    $preInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        hook_event_name = 'PreToolUse'
        tool_name       = 'PowerShell'   # also matches
        tool_input      = @{ command = 'E:\UE_5.7\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project=E:\Work\Games\ProjectGear\ProjectGear.uproject' }
        tool_use_id     = 'bfailcase01'
    } | ConvertTo-Json -Depth 5
    $preInput | pwsh -NoProfile -File $hookScript -Phase pre 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pre (2) hook exited $LASTEXITCODE" }

    $postInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        hook_event_name = 'PostToolUse'
        tool_name       = 'PowerShell'
        tool_input      = @{ command = 'E:\UE_5.7\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project=E:\Work\Games\ProjectGear\ProjectGear.uproject' }
        tool_response   = @{ exit_code = 1 }
        tool_use_id     = 'bfailcase01'
    } | ConvertTo-Json -Depth 5
    $postInput | pwsh -NoProfile -File $hookScript -Phase post 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "post (2) hook exited $LASTEXITCODE" }

    $s = Get-UshellState -Path $testState
    if ($s.last.result -ne 'fail') { throw "expected last.result='fail', got '$($s.last.result)'" }
    if ($s.last.exit_code -ne 1) { throw "expected last.exit_code=1, got '$($s.last.exit_code)'" }
    Write-Host "  ok PowerShell tool detected, exit-1 records 'fail'"

    # === Non-ushell command — no state change ===
    $beforeRaw = Get-Content -LiteralPath $testState -Raw
    $hookInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        hook_event_name = 'PreToolUse'
        tool_name       = 'Bash'
        tool_input      = @{ command = 'cd "E:\Work\ushell-skill" && git status --short' }
        tool_use_id     = 'b-nonushell'
    } | ConvertTo-Json -Depth 5
    $hookInput | pwsh -NoProfile -File $hookScript -Phase pre 2>&1 | Out-Null
    $afterRaw = Get-Content -LiteralPath $testState -Raw
    if ($beforeRaw -ne $afterRaw) { throw "non-ushell command should NOT change state, but state diff observed" }
    Write-Host "  ok non-ushell command leaves state untouched"

    # === Non-Bash/PowerShell tool — no state change ===
    $beforeRaw = Get-Content -LiteralPath $testState -Raw
    $hookInput = @{
        session_id      = 'd00d426b-3a05-4330-88bd-7281a3e32b64'
        hook_event_name = 'PreToolUse'
        tool_name       = 'Edit'
        tool_input      = @{ file_path = 'foo.txt' }
        tool_use_id     = 'b-edit'
    } | ConvertTo-Json -Depth 5
    $hookInput | pwsh -NoProfile -File $hookScript -Phase pre 2>&1 | Out-Null
    $afterRaw = Get-Content -LiteralPath $testState -Raw
    if ($beforeRaw -ne $afterRaw) { throw "Edit tool call should NOT change state, but state diff observed" }
    Write-Host "  ok non-Bash/PowerShell tool leaves state untouched"

    Write-Host "all green"
} finally {
    Remove-Item -LiteralPath $testState -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\USHELL_STATE_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
}

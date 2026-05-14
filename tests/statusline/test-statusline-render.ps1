# tests/statusline/test-statusline-render.ps1
# End-to-end render tests for the statusline script.
# Sets up a state file + (when needed) a fake tasks dir with a real output
# file, runs scripts/statusline.ps1, asserts on the rendered lines.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$script = "$here/../../scripts/statusline.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "statusline.ps1 not found at $script"
}
Import-Module "$here/../../scripts/lib/state.psm1" -Force

$testState = Join-Path $env:TEMP "ushell-state-rendertest-$(Get-Random).json"
$env:USHELL_STATE_FILE = $testState

function Invoke-Statusline {
    # Statusline scripts get JSON on stdin from Claude Code; we send {} so the read doesn't block.
    $out = ('{}' | pwsh -NoProfile -File $script 2>&1) -join "`n"
    return $out
}

try {
    Write-Host "test-statusline-render:"

    # === Case 1: state file missing → no-context fallback ===
    Remove-Item -LiteralPath $testState -Force -ErrorAction SilentlyContinue
    $out = Invoke-Statusline
    if ($out -notmatch 'no context') { throw "case1: expected 'no context' fallback, got: $out" }
    Write-Host "  ok case1: missing state → no-context fallback"

    # === Case 2: idle with context + last ===
    $s = [pscustomobject]@{
        schema_version = 1
        active = $null
        last = [pscustomobject]@{
            command   = '.build game Win64 shipping'
            verb      = '.build'
            project   = 'ProjectGear'
            result    = 'ok'
            exit_code = 0
            finished  = '2026-05-14T11:51:23+00:00'
            duration_s = 287
        }
        context = [pscustomobject]@{
            project      = 'ProjectGear'
            project_path = 'E:\Work\Games\ProjectGear'
            engine       = 'E:\UE_5.7'
            engine_kind  = 'installed'
        }
    }
    Set-UshellState -Path $testState -State $s
    $out = Invoke-Statusline
    if ($out -notmatch 'ProjectGear @ UE_5\.7 \(installed\)') { throw "case2: L1 wrong: $out" }
    if ($out -notmatch 'idle') { throw "case2: L2 should be 'idle' when active=null: $out" }
    if ($out -notmatch 'last: \.build game Win64 shipping') { throw "case2: L3 wrong: $out" }
    if ($out -notmatch [char]0x2713) { throw "case2: should contain ✓ glyph for success" }
    Write-Host "  ok case2: idle + last success"

    # === Case 3: fail last command → ✗ glyph ===
    $s.last.result = 'fail'
    $s.last.exit_code = 1
    Set-UshellState -Path $testState -State $s
    $out = Invoke-Statusline
    if ($out -notmatch [char]0x2717) { throw "case3: should contain ✗ glyph for fail" }
    Write-Host "  ok case3: failure renders ✗"

    # === Case 4: active task with live tail and progress ===
    $tmpTasksDir = Join-Path $env:TEMP "ushell-statusline-tasks-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpTasksDir -Force | Out-Null
    $fakeOutput = Join-Path $tmpTasksDir 'b9795py03.output'
    Set-Content -LiteralPath $fakeOutput -Encoding UTF8 -Value @(
        '[11.34.10] LogShaderCompilers: Display: ============================================'
        '[11.34.11] LogCook: Display: Cooked packages 449 Packages Remain 28 Total 477'
        '[11.34.14] LogCook: Display: Cooked packages 450 Packages Remain 27 Total 477'
    )

    $s.active = [pscustomobject]@{
        tool_use_id   = 'b9795py03'
        tasks_dir     = $tmpTasksDir
        command       = '.cook game Win64'
        verb          = '.cook'
        project       = 'ProjectGear'
        project_path  = 'E:\Work\Games\ProjectGear'
        engine        = 'E:\UE_5.7'
        engine_kind   = 'installed'
        engine_branch = '++UE5+Release-5.7'
        started       = (Get-Date).AddMinutes(-3).ToUniversalTime().ToString('o')
    }
    Set-UshellState -Path $testState -State $s

    $out = Invoke-Statusline
    if ($out -notmatch '\.cook game Win64') { throw "case4: L2 should mention the command: $out" }
    if ($out -notmatch '450/477') { throw "case4: L2 should show progress 450/477: $out" }
    Write-Host "  ok case4: active task tails output file and shows N/T progress"

    # === Case 5: stale schema → upgrade hint ===
    $bad = '{"schema_version":99,"active":null,"last":null,"context":null}'
    Set-Content -LiteralPath $testState -Value $bad -Encoding UTF8
    $out = Invoke-Statusline
    if ($out -notmatch 'version mismatch') { throw "case5: should hint at version mismatch: $out" }
    Write-Host "  ok case5: schema mismatch shows upgrade hint"

    Remove-Item -LiteralPath $tmpTasksDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "all green"
} finally {
    Remove-Item -LiteralPath $testState -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\USHELL_STATE_FILE -ErrorAction SilentlyContinue
}

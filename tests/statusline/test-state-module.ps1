# tests/statusline/test-state-module.ps1
# Verifies the atomic JSON state module: Get-UshellState, Set-UshellState.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$modulePath = "$here/../../scripts/lib/state.psm1"
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "state.psm1 not found at $modulePath"
}
Import-Module $modulePath -Force

$testStateFile = Join-Path $env:TEMP "ushell-state-test-$(Get-Random).json"
try {
    # 1. Fresh state (file missing) returns the default skeleton
    $s = Get-UshellState -Path $testStateFile
    if ($null -ne $s.active) { throw "fresh state should have active=null" }
    if ($null -ne $s.last)   { throw "fresh state should have last=null" }
    if ($s.schema_version -ne 1) { throw "fresh state should have schema_version=1, got $($s.schema_version)" }

    # 2. Write + read round-trip
    $s.active = [pscustomobject]@{ command = '.cook game Win64'; verb = 'cook' }
    Set-UshellState -Path $testStateFile -State $s
    $s2 = Get-UshellState -Path $testStateFile
    if ($s2.active.command -ne '.cook game Win64') { throw "round-trip lost active.command" }
    if ($s2.active.verb -ne 'cook') { throw "round-trip lost active.verb" }

    # 3. Atomic write: tmp file is gone after Set
    if (Test-Path -LiteralPath "$testStateFile.tmp") { throw "tmp file leaked after Set-UshellState" }

    # 4. Schema version mismatch handling
    $bad = @{ schema_version = 99; active = $null; last = $null; context = $null } | ConvertTo-Json
    Set-Content -LiteralPath $testStateFile -Value $bad -Encoding UTF8
    $s3 = Get-UshellState -Path $testStateFile
    if (-not $s3._stale) { throw "expected _stale=true on schema mismatch" }

    # 5. Corrupt JSON handling
    Set-Content -LiteralPath $testStateFile -Value '{not valid json' -Encoding UTF8
    $s4 = Get-UshellState -Path $testStateFile
    if (-not $s4._stale) { throw "expected _stale=true on corrupt JSON" }

    Write-Host "test-state-module: all green"
} finally {
    Remove-Item -LiteralPath $testStateFile -Force -ErrorAction SilentlyContinue
}

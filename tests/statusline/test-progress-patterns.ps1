# tests/statusline/test-progress-patterns.ps1
# Verifies the verb→regex table extracts (N, T) progress correctly from real
# ushell output snippets. Pure-data, pure-regex; no PowerShell modules required.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Test-Pattern {
    param(
        [string]$VerbPattern,
        [string]$FixturePath,
        [hashtable]$Expected
    )
    $patternsFile = "$here/../../scripts/progress-patterns.json"
    if (-not (Test-Path -LiteralPath $patternsFile)) {
        throw "progress-patterns.json not found at $patternsFile"
    }
    $patterns = Get-Content $patternsFile -Raw | ConvertFrom-Json
    $entry = $patterns.patterns | Where-Object { $_.verb -eq $VerbPattern }
    if (-not $entry) { throw "No pattern entry for verb='$VerbPattern'" }
    if (-not (Test-Path -LiteralPath $FixturePath)) {
        throw "Fixture not found: $FixturePath"
    }
    $tail = Get-Content $FixturePath -Raw
    $rx = [regex]::new($entry.regex)
    $matches = $rx.Matches($tail)
    if ($matches.Count -eq 0) {
        throw "Regex '$($entry.regex)' did not match fixture '$FixturePath'"
    }
    # Take the LAST match — same semantic as the statusline tail
    $last = $matches[$matches.Count - 1]
    foreach ($key in $Expected.Keys) {
        $actual = $last.Groups[$key].Value
        if ($actual -ne $Expected[$key]) {
            throw "Group '$key' on verb '$VerbPattern': expected '$($Expected[$key])', got '$actual'"
        }
    }
    Write-Host "  ok $VerbPattern on $(Split-Path $FixturePath -Leaf)"
}

Write-Host "test-progress-patterns:"
Test-Pattern -VerbPattern '.cook'              -FixturePath "$here/fixtures/cook-output.txt"    -Expected @{ n='450'; t='477' }
Test-Pattern -VerbPattern '.build'             -FixturePath "$here/fixtures/build-output.txt"   -Expected @{ n='42';  t='118' }
Test-Pattern -VerbPattern '.uat BuildCookRun'  -FixturePath "$here/fixtures/uat-bcr-output.txt" -Expected @{ n='450'; t='477' }
Test-Pattern -VerbPattern '.p4 sync'           -FixturePath "$here/fixtures/p4-sync-output.txt" -Expected @{ n='8423'; t='12903' }
Write-Host "all green"

# tests/statusline/test-progress-tail.ps1
# Verifies progress-tail.psm1: Get-Progress (extract last N/T from a file)
# and Find-ActiveOutputFile (newest *.output in a tasks dir).

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$modulePath = "$here/../../scripts/lib/progress-tail.psm1"
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "progress-tail.psm1 not found at $modulePath"
}
Import-Module $modulePath -Force

Write-Host "test-progress-tail:"

# === Test Get-Progress ===
$tmpOutput = Join-Path $env:TEMP "ushell-tail-test-$(Get-Random).txt"
$tmpCache  = Join-Path $env:TEMP "ushell-tail-cache-$(Get-Random).json"
try {
    Set-Content -LiteralPath $tmpOutput -Value @(
        '[11.30.00] LogCook: Display: Cooked packages 100 Packages Remain 377 Total 477'
        '[11.31.00] LogCook: Display: Cooked packages 200 Packages Remain 277 Total 477'
    ) -Encoding UTF8
    $regex = 'LogCook: Display: Cooked packages (?<n>\d+) Packages Remain \d+ Total (?<t>\d+)'

    $p = Get-Progress -OutputFile $tmpOutput -CacheFile $tmpCache -Regex $regex
    if ($p.N -ne 200 -or $p.T -ne 477) {
        throw "expected n=200 t=477, got n=$($p.N) t=$($p.T)"
    }
    if ($p.Status -ne 'ok') { throw "expected Status=ok, got $($p.Status)" }
    Write-Host "  ok Get-Progress extracts last match"

    # Append more output; expect new N
    Add-Content -LiteralPath $tmpOutput -Value '[11.32.00] LogCook: Display: Cooked packages 300 Packages Remain 177 Total 477'
    $p = Get-Progress -OutputFile $tmpOutput -CacheFile $tmpCache -Regex $regex
    if ($p.N -ne 300) { throw "expected updated n=300, got $($p.N)" }
    Write-Host "  ok Get-Progress sees new content"

    # Cache file populated for ETA estimation
    if (-not (Test-Path -LiteralPath $tmpCache)) { throw "cache file not written" }
    $cache = Get-Content -LiteralPath $tmpCache -Raw | ConvertFrom-Json
    if (-not $cache.history -or $cache.history.Count -lt 2) {
        throw "cache history should have >=2 samples after 2 reads, got $($cache.history.Count)"
    }
    Write-Host "  ok Get-Progress maintains rolling history for ETA"
} finally {
    Remove-Item -LiteralPath $tmpOutput, $tmpCache -Force -ErrorAction SilentlyContinue
}

# === Test Find-ActiveOutputFile ===
$tmpDir = Join-Path $env:TEMP "ushell-tasks-test-$(Get-Random)"
try {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    # Empty dir → null
    $found = Find-ActiveOutputFile -TasksDir $tmpDir
    if ($found) { throw "expected null on empty dir, got '$found'" }
    Write-Host "  ok Find-ActiveOutputFile returns null on empty dir"

    # Single file → returns it
    $f1 = Join-Path $tmpDir 'btask001.output'
    Set-Content -LiteralPath $f1 -Value "stuff" -Encoding UTF8
    $found = Find-ActiveOutputFile -TasksDir $tmpDir
    if ($found -ne $f1) { throw "expected '$f1', got '$found'" }
    Write-Host "  ok Find-ActiveOutputFile returns single file"

    # Multiple files → returns newest by LastWriteTime
    $f2 = Join-Path $tmpDir 'btask002.output'
    Set-Content -LiteralPath $f2 -Value "newer" -Encoding UTF8
    # Force f2 to be newer
    (Get-Item $f2).LastWriteTime = (Get-Date).AddSeconds(10)
    $found = Find-ActiveOutputFile -TasksDir $tmpDir
    if ($found -ne $f2) { throw "expected newest '$f2', got '$found'" }
    Write-Host "  ok Find-ActiveOutputFile returns newest by mtime"

    # Non-existent dir → null
    $found = Find-ActiveOutputFile -TasksDir 'X:\nope\nope\nope'
    if ($found) { throw "expected null on missing dir, got '$found'" }
    Write-Host "  ok Find-ActiveOutputFile handles missing dir"
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "all green"

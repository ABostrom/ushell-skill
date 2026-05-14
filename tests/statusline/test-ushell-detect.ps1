# tests/statusline/test-ushell-detect.ps1
# Verifies Parse-UshellCommand correctly classifies and extracts data from
# ushell-shaped command strings (and rejects non-ushell commands).

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$modulePath = "$here/../../scripts/lib/ushell-detect.psm1"
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ushell-detect.psm1 not found at $modulePath"
}
Import-Module $modulePath -Force

function Assert-Equal($expected, $actual, $msg) {
    if ($expected -ne $actual) { throw "$msg : expected='$expected' actual='$actual'" }
}

Write-Host "test-ushell-detect:"

# Case 1: standard cmd /d /s /c wrapper around ushell.bat — single verb
$cmd = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .cook game Win64"'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true for ushell.bat case" }
Assert-Equal '.cook' $r.Verb 'case1: verb'
Assert-Equal 'E:\Work\Games\ProjectGear\ProjectGear.uproject' $r.ProjectPath 'case1: project_path'
Assert-Equal 'E:\UE_5.7' $r.EnginePath 'case1: engine_path'
Write-Host "  ok case1: standard ushell.bat single-verb"

# Case 2: RunUAT.bat direct (the installed-engine carve-out)
$cmd = 'E:\UE_5.7\Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project=E:\Work\Games\ProjectGear\ProjectGear.uproject -target=ProjectGear -platform=Win64 -clientconfig=Shipping -build'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true for RunUAT" }
Assert-Equal 'RunUAT.bat BuildCookRun' $r.Verb 'case2: verb'
Assert-Equal 'E:\Work\Games\ProjectGear\ProjectGear.uproject' $r.ProjectPath 'case2: project_path'
Assert-Equal 'E:\UE_5.7' $r.EnginePath 'case2: engine_path'
Write-Host "  ok case2: RunUAT.bat BuildCookRun"

# Case 3: non-ushell — git status — should be rejected
$cmd = 'cd "E:\Work\ushell-skill" && git status --short'
$r = Parse-UshellCommand -Command $cmd
if ($r.IsUshell) { throw "expected IsUshell=false for git status" }
Write-Host "  ok case3: non-ushell rejected"

# Case 4: chained command — the LAST verb is the goal of the chain
$cmd = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=E:\Work\Games\ProjectGear\ProjectGear.uproject && .build editor && .build game Win64 shipping && .cook game Win64"'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true for chain" }
Assert-Equal '.cook' $r.Verb 'case4: chain reports last verb'
Write-Host "  ok case4: chain reports last verb"

# Case 5: quoted project path with spaces
$cmd = 'cmd.exe /d /s /c "call E:\UE_5.7\Engine\Extras\ushell\ushell.bat --project=""E:\Work\Games\My Project\My Project.uproject"" && .info"'
$r = Parse-UshellCommand -Command $cmd
if (-not $r.IsUshell) { throw "expected IsUshell=true for quoted project" }
Assert-Equal '.info' $r.Verb 'case5: verb'
# Note: PowerShell sees the double-double quote pattern; verifying we extract the path correctly
# (Acceptable to extract with or without surrounding quotes — value matters)
if (-not $r.ProjectPath.Contains('My Project.uproject')) {
    throw "case5: project_path should contain 'My Project.uproject', got '$($r.ProjectPath)'"
}
Write-Host "  ok case5: quoted project path"

Write-Host "all green"

<#
.SYNOPSIS
    Helper for re-running the ushell skill's GREEN test scenarios.

.DESCRIPTION
    This script doesn't dispatch subagents itself - that requires a Claude Code
    (or other agent-tool-capable) session. Instead it:

    1. Prints each scenario's verbatim prompt from tests/baseline.md.
    2. Tells you exactly how to dispatch it as an Agent tool call.
    3. Reminds you which GREEN bullets to check against tests/with-skill.md.
    4. Optionally opens tests/with-skill.md in your editor so you can score
       as you go.

    Run this from a Claude Code session as scaffolding for a verification pass,
    or save the printed prompts somewhere and dispatch from any other harness.

.PARAMETER Scenarios
    Comma-separated scenario IDs (e.g. "S1,S6,S13"). Default: all 13.

.PARAMETER OpenRubric
    Open tests/with-skill.md in $env:EDITOR (or notepad) for live scoring.

.EXAMPLE
    .\tests\run-green.ps1
    Print all 13 scenarios + their dispatch instructions.

.EXAMPLE
    .\tests\run-green.ps1 -Scenarios "S2,S6,S9"
    Re-run just the three highest-value scenarios.

.EXAMPLE
    .\tests\run-green.ps1 -OpenRubric
    Print scenarios and open the rubric file for live scoring.
#>

[CmdletBinding()]
param(
    [string]$Scenarios = "S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11,S12,S13",
    [switch]$OpenRubric
)

$RepoRoot      = (Resolve-Path "$PSScriptRoot\..").Path
$BaselineFile  = Join-Path $RepoRoot "tests\baseline.md"
$WithSkillFile = Join-Path $RepoRoot "tests\with-skill.md"
$SkillRoot     = Join-Path $RepoRoot "skills\ushell"
$SkillMd       = Join-Path $SkillRoot "SKILL.md"

if (-not (Test-Path $BaselineFile))  { throw "tests/baseline.md not found at $BaselineFile" }
if (-not (Test-Path $WithSkillFile)) { throw "tests/with-skill.md not found at $WithSkillFile" }
if (-not (Test-Path $SkillMd))       { throw "skill content not found at $SkillMd (expected after v2.0 restructure)" }

# Parse scenario blocks out of baseline.md.
$baselineText = Get-Content $BaselineFile -Raw
$blocks = [regex]::Matches(
    $baselineText,
    '(?ms)^## (S\d+)\.\s+(.+?)\r?\n\r?\nPrompt verbatim:\r?\n\r?\n> (.+?)(?=\r?\n\r?\n## S|\r?\n\r?\n\Z|\Z)'
)

$wanted = $Scenarios.Split(",") | ForEach-Object { $_.Trim() }

Write-Host ""
Write-Host "=== ushell skill GREEN re-run ===" -ForegroundColor Cyan
Write-Host "Skill content root: $SkillRoot" -ForegroundColor DarkGray
Write-Host "Rubric:             $WithSkillFile" -ForegroundColor DarkGray
Write-Host ""

if ($OpenRubric) {
    $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }
    Write-Host "Opening rubric in $editor..." -ForegroundColor DarkGray
    Start-Process $editor $WithSkillFile
    Write-Host ""
}

# Use single-quoted here-strings (no expansion) for the prompt template;
# substitute placeholders manually.
$promptTemplate = @'
You are a software engineer at a Windows workstation. You have a Claude Code skill called "ushell" loaded - its content lives at SKILL_ROOT_PLACEHOLDER. Before answering, READ SKILL_ROOT_PLACEHOLDER\SKILL.md to learn how the skill expects you to approach Unreal Engine tasks. Then load reference files from SKILL_ROOT_PLACEHOLDER\reference\ as the skill's "Load reference when..." pointers direct.

After loading skill content, respond to the user's request below. Describe the exact commands you would run, in order, with brief justifications. Do not invent flags or command names. If you would normally ask a clarifying question, list the question. UE 5.7 at E:\UE_5.7\.

User request:

PROMPT_PLACEHOLDER

Return your reasoning + the command sequence as concise markdown. Do not execute.
'@

$count = 0
foreach ($match in $blocks) {
    $id      = $match.Groups[1].Value
    $title   = $match.Groups[2].Value.Trim()
    $prompt  = $match.Groups[3].Value -replace '\r?\n> ', "`n"

    if ($wanted -notcontains $id) { continue }
    $count++

    # Use plain .Replace() so backslashes in $SkillRoot survive verbatim.
    $filled = $promptTemplate.Replace('SKILL_ROOT_PLACEHOLDER', $SkillRoot)
    $filled = $filled.Replace('PROMPT_PLACEHOLDER', $prompt)

    Write-Host ("--- {0}: {1} ---" -f $id, $title) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Dispatch a fresh general-purpose Agent with this exact prompt:" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host $filled -ForegroundColor White
    Write-Host ""
    Write-Host ("Score against {0} rubric in tests/with-skill.md." -f $id) -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host ("=== {0} scenarios queued ===" -f $count) -ForegroundColor Cyan
Write-Host ""
Write-Host "When done, append the n/N tallies to tests/notes.md (gitignored)." -ForegroundColor DarkGray
Write-Host "The skill is GREEN when all selected scenarios pass." -ForegroundColor DarkGray

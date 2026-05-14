# scripts/statusline.ps1
# Claude Code statusline command. Renders 1-3 lines reflecting current ushell
# state. Reads state from ~/.claude/ushell-state.json (written by hook-update.ps1),
# tails the active task's output file for live progress, applies a verb-specific
# regex to extract N/T.

[CmdletBinding()] param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module "$here/lib/state.psm1"        -Force
Import-Module "$here/lib/progress-tail.psm1" -Force

# Drain stdin (CC sends session-data JSON; we don't use it but reading prevents blocking)
[void]([Console]::In.ReadToEnd())

$StateFile = if ($env:USHELL_STATE_FILE) { $env:USHELL_STATE_FILE } else { Join-Path $HOME '.claude/ushell-state.json' }
$PatternsFile = Join-Path $here 'progress-patterns.json'

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

# === Helpers ===
function Format-EngineShort($enginePath) {
    if (-not $enginePath) { return '?' }
    return (Split-Path -Leaf $enginePath)
}

function Format-Time($iso) {
    if (-not $iso) { return '?' }
    # ConvertFrom-Json auto-coerces ISO strings to [DateTime]; handle both types.
    if ($iso -is [DateTime])       { return $iso.ToLocalTime().ToString('HH:mm') }
    if ($iso -is [DateTimeOffset]) { return $iso.ToLocalTime().ToString('HH:mm') }
    try { return ([DateTimeOffset]::Parse($iso, [System.Globalization.CultureInfo]::InvariantCulture).ToLocalTime().ToString('HH:mm')) } catch { return '?' }
}

function Truncate($text, $max) {
    if (-not $text) { return '' }
    if ($text.Length -le $max) { return $text }
    return $text.Substring(0, $max - 3) + '...'
}

function Format-ETA([int]$seconds) {
    if ($seconds -lt 0) { return $null }
    if ($seconds -lt 60) { return "$($seconds)s" }
    if ($seconds -lt 3600) { return "$([int]($seconds / 60))m" }
    return "$([int]($seconds / 3600))h$(($seconds % 3600) / 60 | ForEach-Object { [int]$_ })m"
}

# === L1: context line ===
$ctx = $state.context
if (-not $ctx -and $state.active) {
    $ctx = [pscustomobject]@{
        project      = $state.active.project
        engine       = $state.active.engine
        engine_kind  = $state.active.engine_kind
    }
}
if ($ctx) {
    $proj   = if ($ctx.project) { $ctx.project } else { '?' }
    $engine = Format-EngineShort $ctx.engine
    $kind   = if ($ctx.engine_kind) { $ctx.engine_kind } else { '?' }
    Write-Output "$proj @ $engine ($kind)"
}

# === L2: active or idle ===
if ($state.active) {
    $cmdShort = Truncate $state.active.command 60
    $progressStr = 'starting...'

    if ($state.active.tasks_dir -and (Test-Path -LiteralPath $PatternsFile)) {
        try {
            $outputFile = Find-ActiveOutputFile -TasksDir $state.active.tasks_dir
            if ($outputFile) {
                $patterns = Get-Content -LiteralPath $PatternsFile -Raw | ConvertFrom-Json
                # Match the longest verb prefix first so '.uat BuildCookRun' beats '.uat'
                $entry = $patterns.patterns |
                    Where-Object { $state.active.verb -and $state.active.verb -like "$($_.verb)*" } |
                    Sort-Object { $_.verb.Length } -Descending |
                    Select-Object -First 1
                if (-not $entry) {
                    # Fallback: try .cook then .build
                    $entry = $patterns.patterns | Where-Object { $_.verb -eq '.cook' } | Select-Object -First 1
                }
                if ($entry) {
                    $cacheFile = "$StateFile.tail.json"
                    $p = Get-Progress -OutputFile $outputFile -CacheFile $cacheFile -Regex $entry.regex
                    if ($p.Status -eq 'ok') {
                        $progressStr = "$($p.N)/$($p.T)"
                        # ETA — crude linear extrapolation from the rolling history
                        try {
                            $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
                            if ($cache.history -and $cache.history.Count -ge 2) {
                                $first = $cache.history[0]
                                $last  = $cache.history[-1]
                                $dN = [int]$last.n - [int]$first.n
                                $dT = [int]$last.ts - [int]$first.ts
                                if ($dT -gt 0 -and $dN -gt 0) {
                                    $rate = $dN / $dT
                                    $remaining = [int]$p.T - [int]$p.N
                                    $etaSec = [int]($remaining / $rate)
                                    $etaStr = Format-ETA $etaSec
                                    if ($etaStr) { $progressStr += " · ~$etaStr" }
                                }
                            }
                        } catch { }
                    }
                }
            }
        } catch {
            # Tail failed; leave progressStr = 'starting...'
        }
    }
    Write-Output "$cmdShort · $progressStr"
} else {
    Write-Output 'idle'
}

# === L3: last ===
if ($state.last) {
    $cmdShort = Truncate $state.last.command 50
    $glyph = if ($state.last.result -eq 'ok') { [char]0x2713 } else { [char]0x2717 }
    $when = Format-Time $state.last.finished
    $line = "last: $cmdShort $glyph $when"
    if ($state.last.note) { $line += " · $($state.last.note)" }
    Write-Output $line
}

exit 0

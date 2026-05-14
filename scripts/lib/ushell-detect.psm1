# scripts/lib/ushell-detect.psm1
# Parse a Bash/PowerShell tool command string. Detect ushell-shaped commands
# and extract: verb, project path, engine path. Also expose helpers to read
# engine metadata (installed-vs-source kind, branch name).

function Parse-UshellCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command)

    # Coarse classification first — cheap regex checks
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
        # Match all "<sep>.<word>" occurrences; take the LAST (chain support).
        # The leading separator is a whitespace, ampersand-pair, or quote.
        $matches = [regex]::Matches($Command, '(?:[\s&])\.(?<v>[a-z][\w-]*)\b', 'IgnoreCase')
        if ($matches.Count -gt 0) {
            $verb = '.' + $matches[$matches.Count - 1].Groups['v'].Value
        }
    } elseif ($isRunUAT) {
        if ($Command -match 'RunUAT\.bat\s+(?<v>[A-Za-z]\w*)') {
            $verb = "RunUAT.bat $($Matches.v)"
        } else {
            $verb = 'RunUAT.bat'
        }
    } elseif ($isUbt) {
        $verb = 'UnrealBuildTool'
    } elseif ($isEditor) {
        $verb = 'UnrealEditor'
    }

    # Project path — handle both --project= and -project=, with optional quoting
    $projectPath = $null
    if ($Command -match '-{1,2}project=(?<p>(?:""[^"]+""|"[^"]+"|[^\s"]+))') {
        $p = $Matches['p']
        # Strip outer "" or "" pairs
        $p = $p.Trim('"')
        $projectPath = $p
    }

    # Engine path — find the path that precedes "\Engine\" (Windows-only for v1)
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
    } catch {
        return $null
    }
}

Export-ModuleMember -Function Parse-UshellCommand, Get-EngineKind, Get-EngineBranch

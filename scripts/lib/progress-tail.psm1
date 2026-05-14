# scripts/lib/progress-tail.psm1
# Output-file tailing + progress extraction for the ushell statusline.
#   Get-Progress           — read last 64K of a known file, extract last (N, T) per a regex,
#                            cache rolling history for ETA estimation.
#   Find-ActiveOutputFile  — given a tasks directory, return the newest *.output file path
#                            (used when we know the dir but not the specific task_id yet).

function Get-Progress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputFile,
        [Parameter(Mandatory)][string]$CacheFile,
        [Parameter(Mandatory)][string]$Regex,
        [int]$TailBytes = 65536    # 64K tail is enough for progress markers
    )

    if (-not (Test-Path -LiteralPath $OutputFile)) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'no-output-file' }
    }

    $fi = Get-Item -LiteralPath $OutputFile
    $len = $fi.Length
    if ($len -le 0) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'empty' }
    }

    # Read last $TailBytes
    $start = [Math]::Max(0, $len - $TailBytes)
    $stream = [System.IO.File]::Open($OutputFile, 'Open', 'Read', 'ReadWrite')
    try {
        $stream.Seek($start, 'Begin') | Out-Null
        $buf = New-Object byte[] ($len - $start)
        $read = $stream.Read($buf, 0, $buf.Length)
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    } finally {
        $stream.Dispose()
    }

    # Take the LAST match — that's the most recent progress reading
    $rx = [regex]::new($Regex)
    $matches = $rx.Matches($text)
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{ N = $null; T = $null; Status = 'no-match-yet' }
    }
    $last = $matches[$matches.Count - 1]
    $n = [int]$last.Groups['n'].Value
    $t = [int]$last.Groups['t'].Value

    # Cache the reading for ETA — keep a rolling window of recent samples
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $history = @()
    if (Test-Path -LiteralPath $CacheFile) {
        try {
            $old = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
            if ($old.history) { $history = @($old.history) }
        } catch { }
    }
    # Avoid duplicating samples if N hasn't changed
    $shouldAppend = $true
    if ($history.Count -gt 0) {
        $lastSample = $history[-1]
        if ($lastSample.n -eq $n -and $lastSample.t -eq $t) { $shouldAppend = $false }
    }
    if ($shouldAppend) {
        $history += @(@{ n = $n; t = $t; ts = $now })
        # Keep last 30 samples — bounded memory
        if ($history.Count -gt 30) { $history = $history | Select-Object -Last 30 }
    }

    $cache = @{
        last_n  = $n
        last_t  = $t
        last_ts = $now
        history = $history
    }
    $tmp = "$CacheFile.tmp"
    ($cache | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $CacheFile -Force

    [pscustomobject]@{ N = $n; T = $t; Status = 'ok' }
}

function Find-ActiveOutputFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TasksDir)

    if (-not (Test-Path -LiteralPath $TasksDir)) { return $null }
    $files = Get-ChildItem -LiteralPath $TasksDir -Filter '*.output' -File -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) { return $null }
    return ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

Export-ModuleMember -Function Get-Progress, Find-ActiveOutputFile

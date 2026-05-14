# scripts/lib/state.psm1
# Atomic JSON state read/write for the ushell statusline.
# - Get-UshellState: reads the state file, returns a default skeleton when missing/stale/corrupt.
# - Set-UshellState: writes the state file atomically (write tmp + rename).

$script:SchemaVersion = 1

function Get-UshellState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            schema_version = $script:SchemaVersion
            active  = $null
            last    = $null
            context = $null
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($obj.schema_version -ne $script:SchemaVersion) {
            Write-Verbose "schema_version mismatch: file=$($obj.schema_version), expected=$($script:SchemaVersion)"
            return [pscustomobject]@{
                schema_version = $script:SchemaVersion
                active  = $null
                last    = $null
                context = $null
                _stale  = $true
            }
        }
        # Ensure fields exist even if file was hand-edited
        foreach ($k in 'active','last','context') {
            if (-not ($obj.PSObject.Properties.Name -contains $k)) {
                $obj | Add-Member -NotePropertyName $k -NotePropertyValue $null -Force
            }
        }
        return $obj
    } catch {
        Write-Verbose "Failed to parse state file '$Path': $_"
        return [pscustomobject]@{
            schema_version = $script:SchemaVersion
            active  = $null
            last    = $null
            context = $null
            _stale  = $true
        }
    }
}

function Set-UshellState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$State
    )

    # Ensure parent dir exists
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Force the schema version on every write
    if ($State.PSObject.Properties.Name -contains 'schema_version') {
        $State.schema_version = $script:SchemaVersion
    } else {
        $State | Add-Member -NotePropertyName 'schema_version' -NotePropertyValue $script:SchemaVersion -Force
    }

    $tmp = "$Path.tmp"
    $json = $State | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    # Atomic rename. Move-Item -Force replaces existing on Windows.
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

Export-ModuleMember -Function Get-UshellState, Set-UshellState

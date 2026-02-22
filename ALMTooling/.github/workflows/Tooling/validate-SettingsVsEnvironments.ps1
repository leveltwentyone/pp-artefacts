[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MappingFile,

    [Parameter(Mandatory = $true)]
    [string]$Environment
)

Write-Host "== Validate-SettingsVsEnvironment.ps1 =="
Write-Host "   Environment : $Environment"

function Read-MappingFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Mapping file not found: $Path" }
    return Get-Content $Path -Raw | ConvertFrom-Json
}

# ------------------------------------------------------------
# pac connection list output and parse
# ------------------------------------------------------------
function Get-AvailableConnections {
    Write-Host ""
    Write-Host "== pac connection list raw output =="
    $raw = pac connection list 2>&1
    $raw | ForEach-Object { Write-Host "  $_" }
    Write-Host "== End raw output =="

    if ($LASTEXITCODE -ne 0) {
        throw "pac connection list failed: $raw"
    }

    # Remove ANSI escape codes
    $cleanLines = $raw -split "`n" |
        ForEach-Object { $_ -replace '\x1B\[[0-9;]*[mK]', '' } |
        ForEach-Object { $_.TrimEnd() } |
        Where-Object   { $_ -ne "" }

    $connections = @{}

    foreach ($line in $cleanLines) {
        $tokens = $line.Trim() -split '\s+'

        if ($tokens.Count -lt 2) { continue }

        $firstToken = $tokens[0]

        # Only accept valid connection ID formats
        if ($firstToken -notmatch '^[0-9a-f]{32}$' -and $firstToken -notmatch '^shared-') {
            continue
        }

        $name   = $tokens[1]
        $status = $tokens[-1]

        $connections[$firstToken.ToLower()] = [PSCustomObject]@{
            DisplayName  = $name
            ConnectionId = $firstToken
            Status       = $status
        }
    }

    Write-Host "  $($connections.Count) connection(s) parsed."
    return $connections
}

# ============================================================
# MAIN
# ============================================================
$mapping      = Read-MappingFile -Path $MappingFile
$allErrors    = [System.Collections.Generic.List[string]]::new()
$totalChecked = 0

# Load all available connections once
$availableConnections = Get-AvailableConnections

foreach ($solution in $mapping.solutions) {
    $solName = $solution.name

    Write-Host ""
    Write-Host "----------------------------------------------"
    Write-Host "Solution: $solName"
    Write-Host "----------------------------------------------"

    $settingsPath = $solution.deployment_settings.psobject.Properties |
        Where-Object { $_.Name -eq $Environment } |
        Select-Object -ExpandProperty Value

    if (-not $settingsPath) {
        Write-Host "  ⚠️  No settings defined for environment '$Environment' - skipped."
        continue
    }

    if (-not (Test-Path $settingsPath)) {
        $allErrors.Add("[$solName][$Environment] Settings file not found: $settingsPath")
        continue
    }

    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

    foreach ($cr in $settings.ConnectionReferences) {
        $logicalName  = $cr.LogicalName
        $connectionId = $cr.ConnectionId

        Write-Host "  Checking: $logicalName  (ConnectionId: $connectionId)"
        $totalChecked++

        if ([string]::IsNullOrWhiteSpace($connectionId)) {
            $allErrors.Add("[$solName][$Environment] ❌ ConnectionId is empty: $logicalName")
            continue
        }

        if ($availableConnections.ContainsKey($connectionId.ToLower())) {
            $conn = $availableConnections[$connectionId.ToLower()]
            Write-Host "    ✅ Connection found: $($conn.DisplayName)"
        } else {
            $allErrors.Add(
                "[$solName][$Environment] ❌ Connection not available (not found or not shared with SP): " +
                "$logicalName (ConnectionId: $connectionId)"
            )
        }
    }
}

# ============================================================
# RESULT
# ============================================================
Write-Host ""
Write-Host "=============================================="
Write-Host "Validation complete. $totalChecked connection(s) checked."

if ($allErrors.Count -gt 0) {
    Write-Host "❌ $($allErrors.Count) error(s) found:"
    foreach ($err in $allErrors) { Write-Host "  $err" }
    exit 1
} else {
    Write-Host "✅ All connections available in target environment."
    exit 0
}
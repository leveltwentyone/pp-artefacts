[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MappingFile,

    [Parameter(Mandatory = $true)]
    [string]$Environment
)

Write-Host "== Validate-SolutionVsSettings.ps1 =="
Write-Host "   Environment : $Environment"

function Read-MappingFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Mapping file not found: $Path" }
    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Get-SolutionConnectionRefs {
    param([string]$SolutionPath)

    $refs = @()

    $custFile = Get-ChildItem -Path $SolutionPath -Recurse -Filter "Customizations.xml" -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $custFile) {
        Write-Host "  Customizations.xml not found in: $SolutionPath"
        return $refs
    }

    Write-Host "  Reading connection references from: $($custFile.FullName)"
    [xml]$xml = Get-Content $custFile.FullName -Raw -Encoding UTF8

    $nodes = $xml.SelectNodes("//*[local-name()='connectionreference']")
    Write-Host "  ConnectionReference nodes found: $($nodes.Count)"

    foreach ($node in $nodes) {
        $logicalName = $node.GetAttribute("connectionreferencelogicalname")
        if ($logicalName) { $refs += $logicalName }
    }

    return $refs | Select-Object -Unique
}

function Get-SolutionEnvVars {
    param([string]$SolutionPath)

    $vars = @()
    $evPath = Join-Path $SolutionPath "environmentvariabledefinitions"

    if (-not (Test-Path $evPath)) {
        Write-Host "  No environmentvariabledefinitions folder found in: $SolutionPath"
        return $vars
    }

    $xmlFiles = Get-ChildItem -Path $evPath -Filter "environmentvariabledefinition.xml" -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $xmlFiles) {
        $schemaName = $file.Directory.Name
        if ($schemaName) {
            $vars += $schemaName
            Write-Host "  Env var found: $schemaName"
        }
    }
    return $vars | Select-Object -Unique
}

# ============================================================
# MAIN
# ============================================================
$mapping     = Read-MappingFile -Path $MappingFile
$allErrors   = [System.Collections.Generic.List[string]]::new()
$totalChecks = 0

foreach ($solution in $mapping.solutions) {
    $solName = $solution.name
    $solPath = $solution.path

    Write-Host ""
    Write-Host "----------------------------------------------"
    Write-Host "Solution: $solName  (Path: $solPath)"
    Write-Host "----------------------------------------------"

    if (-not (Test-Path $solPath)) {
        $allErrors.Add("[$solName] Solution path does not exist: $solPath")
        continue
    }

    # Nur Settings-File für das aktuelle Environment ermitteln
    $settingsPath = $solution.deployment_settings.psobject.Properties |
        Where-Object { $_.Name -eq $Environment } |
        Select-Object -ExpandProperty Value

    if (-not $settingsPath) {
        Write-Host "  ⚠️  No settings defined for environment '$Environment' - skipped."
        continue
    }

    Write-Host ""
    Write-Host "  >> Checking environment: $Environment  ->  $settingsPath"
    $totalChecks++

    # Solution-Komponenten einlesen
    $solConnRefs = Get-SolutionConnectionRefs -SolutionPath $solPath
    $solEnvVars  = Get-SolutionEnvVars        -SolutionPath $solPath

    Write-Host "  Connection references in solution ($($solConnRefs.Count)): $($solConnRefs -join ', ')"
    Write-Host "  Environment variables in solution ($($solEnvVars.Count)):  $($solEnvVars -join ', ')"

    if (-not (Test-Path $settingsPath)) {
        $allErrors.Add("[$solName][$Environment] Settings file not found: $settingsPath")
        continue
    }

    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

    $settingsConnRefs = @($settings.ConnectionReferences | ForEach-Object { $_.LogicalName }) | Where-Object { $_ }
    $settingsEnvVars  = @($settings.EnvironmentVariables  | ForEach-Object { $_.SchemaName  }) | Where-Object { $_ }

    # ---- Check 1: Connection References in Solution aber NICHT in Settings ----
    foreach ($cr in $solConnRefs) {
        if ($cr -notin $settingsConnRefs) {
            $allErrors.Add("[$solName][$Environment] ❌ Connection reference missing in settings: $cr")
        }
    }
    if ($solConnRefs.Count -gt 0 -and ($solConnRefs | Where-Object { $_ -notin $settingsConnRefs }).Count -eq 0) {
        Write-Host "     ✅ All connection references covered"
    }

    # ---- Check 2: Env Vars in Solution aber NICHT in Settings ----
    foreach ($ev in $solEnvVars) {
        if ($ev -notin $settingsEnvVars) {
            $allErrors.Add("[$solName][$Environment] ❌ Environment variable missing in settings: $ev")
        }
    }
    if ($solEnvVars.Count -gt 0 -and ($solEnvVars | Where-Object { $_ -notin $settingsEnvVars }).Count -eq 0) {
        Write-Host "     ✅ All environment variables covered"
    }
}

# ============================================================
# RESULT
# ============================================================
Write-Host ""
Write-Host "=============================================="
Write-Host "Validation complete. $totalChecks environment(s) checked."

if ($allErrors.Count -gt 0) {
    Write-Host "❌ $($allErrors.Count) error(s) found:"
    foreach ($err in $allErrors) { Write-Host "  $err" }
    exit 1
} else {
    Write-Host "✅ No errors. All solution components present in settings file."
    exit 0
}
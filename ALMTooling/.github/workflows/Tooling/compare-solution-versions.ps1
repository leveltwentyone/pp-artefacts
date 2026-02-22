[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$JsonPath
)

Write-Host "== CompareVersions.ps1 =="
Write-Host "Runner OS: $($PSVersionTable.OS)"
Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Host "JSON path provided: $JsonPath"

# Script purpose:
# This script compares installed Dataverse/Power Platform solution versions (queried via `pac solution list`)
# against desired versions provided in a JSON file. It computes two flags per solution:
#  - import<name>: whether the solution should be imported to reach the desired version
#  - upgrade<name>: whether a minor-version upgrade is recommended (desired minor > installed minor)
#
# Expected JSON format: a simple object mapping solution unique names to desired version strings,
# e.g. { "my.solution.unique.name": "1.2.3", "another.solution": "2.0" }
# --- Load JSON ---
if (-not (Test-Path -LiteralPath $JsonPath)) {
  Write-Error "Desired versions JSON not found at: $JsonPath"
  exit 1
}
try {
  $desired = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
} catch {
  Write-Error "Failed to parse JSON at $($JsonPath): $($_.Exception.Message)"
  exit 1
}

# Dynamically capture all keys from the JSON (all properties)
$desiredVersions = @{}
$desired.PSObject.Properties | ForEach-Object {
  $desiredVersions[$_.Name] = $_.Value
}

Write-Host "---- Desired Versions (from JSON) ----"
$desiredVersions.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host "$($_.Name) = $($_.Value)"
}
Write-Host "--------------------------------------"

# --- Helper: Compare versions numerically (missing segments treated as 0) ---
function Compare-Version {
  param(
    [Parameter(Mandatory = $true)][string]$installed,
    [Parameter(Mandatory = $true)][string]$desired
  )
  $a = ($installed -split '\.') | ForEach-Object {
    if ($_ -match '^\d+$') { [int]$_ } else { 0 }
  }
  $b = ($desired   -split '\.') | ForEach-Object {
    if ($_ -match '^\d+$') { [int]$_ } else { 0 }
  }
  $len = [Math]::Max($a.Count, $b.Count)
  for ($i = 0; $i -lt $len; $i++) {
    $ai = if ($i -lt $a.Count) { $a[$i] } else { 0 }
    $bi = if ($i -lt $b.Count) { $b[$i] } else { 0 }
    if ($ai -lt $bi) { return -1 }
    if ($ai -gt $bi) { return 1 }
  }
  return 0
}

# Helper: Extract zero-based version segment (e.g. index 1 = Minor)
function Get-VersionSegment {
  param(
    [Parameter(Mandatory=$true)][string]$version,
    [Parameter(Mandatory=$true)][int]$index
  )
  if ([string]::IsNullOrWhiteSpace($version)) { return $null }
  $parts = $version -split '\.'
  if ($index -ge $parts.Count) { return $null }
  $seg = $parts[$index]
  if ($seg -match '^\d+$') { return [int]$seg }
  return $null
}

# --- Fetch solutions using PAC ---
Write-Host "Invoking 'pac solution list --json'..."
$solutions = $null
try {
  $raw = pac solution list --json | ConvertFrom-Json
  # PAC may return an array or an object; handle both
  if ($raw -is [System.Collections.IEnumerable]) {
    $solutions = $raw
  } else {
    $possibleKeys = @('solutions', 'value', 'items')
    $prop = $possibleKeys | Where-Object { $raw.PSObject.Properties.Name -contains $_ } | Select-Object -First 1
    if ($prop) {
      $solutions = $raw.$prop
    } else {
      $solutions = @($raw)
    }
  }
} catch {
  Write-Error "Failed to get solutions from PAC: $($_.Exception.Message)"
  exit 1
}
if (-not $solutions) {
  Write-Warning "PAC returned no solutions. Proceeding with empty installed versions."
}

# --- Extract installed versions + presence set ---
$installedVersions = @{}
$present = [System.Collections.Generic.HashSet[string]]::new()

Write-Host "---- Installed Solutions (from Dataverse via PAC) ----"
foreach ($s in $solutions) {
  # defensive mapping for UniqueName (handle different property names)
  $uniqueName = $s.SolutionUniqueName
  if (-not $uniqueName) { $uniqueName = $s.UniqueName }
  if (-not $uniqueName) { $uniqueName = $s.Name }

  # defensive mapping for Version (including VersionNumber)
  $versionCandidateProps = @(
    'VersionNumber','SolutionVersion'
  )
  $version = $null
  foreach ($p in $versionCandidateProps) {
    if ($s.PSObject.Properties.Name -contains $p) {
      $v = $s.$p
      if ($null -ne $v -and "$v".Trim() -ne '') { $version = "$v"; break }
    }
  }

  if ($uniqueName) { $present.Add($uniqueName) | Out-Null }

  if ($uniqueName -and $desiredVersions.ContainsKey($uniqueName)) {
    # always set even if $version is $null (presence is tracked separately)
    $installedVersions[$uniqueName] = $version
  }
}
Write-Host "------------------------------------------------------"

Write-Host "---- Installed Versions (filtered to target set) ----"
$installedVersions.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host "$($_.Name) = $($_.Value ?? '<missing>')"
}
Write-Host "-----------------------------------------------------"

# --- Import decisions + upgrade-minor flags (initialize dynamically) ---
$import = @{}
$upgrade = @{}

foreach ($name in $desiredVersions.Keys) {
  $import[$name] = $false
  $upgrade[$name] = $false
}

Write-Host "---- Comparison Details ----"
foreach ($name in $desiredVersions.Keys) {
  $isPresent  = $present.Contains($name)
  $installedV = $installedVersions[$name]
  $desiredV   = $desiredVersions[$name]

  $installedDisp = if ([string]::IsNullOrWhiteSpace($installedV)) { '<unknown>' } else { $installedV }
  $desiredDisp   = if ([string]::IsNullOrWhiteSpace($desiredV))   { '<none>'    } else { $desiredV }
  Write-Host ("Comparing {0}: present={1} installed={2} desired={3}" -f $name, $isPresent, $installedDisp, $desiredDisp)

  if ([string]::IsNullOrWhiteSpace($desiredV)) {
    Write-Warning "No desired version provided for $($name); skipping comparison."
    continue
  }

  # Import rule
  if (-not $isPresent) {
    $import[$name] = $true
    $upgrade[$name] = $false
    Write-Host "=> import reason for $($name): solution not present (desired=$desiredV)"
    continue  # skip version comparison when not present
  }
  elseif ([string]::IsNullOrWhiteSpace($installedV)) {
    # present but version unknown -> conservatively import to set desired version
    $import[$name] = $true
    Write-Host "=> import reason for $($name): version unknown in environment; will import desired=$desiredV"
  }
  else {
    $cmp = Compare-Version -installed $installedV -desired $desiredV
    switch ($cmp) {
      -1 {
        $import[$name] = $true
        Write-Host "=> import for $($name): installed=$installedV < desired=$desiredV"
      }
      0  {
        $import[$name] = $false
        Write-Host "=> no import for $($name): installed=$installedV == desired=$desiredV"
      }
      1  {
        $import[$name] = $false
        Write-Host "=> no import for $($name): installed=$installedV > desired=$desiredV"
      }
    }
  }

  # Upgrade-minor rule: compare the second segment (Minor)
  $installedMinor = Get-VersionSegment -version $installedV -index 1
  $desiredMinor   = Get-VersionSegment -version $desiredV   -index 1

  if ($null -ne $installedMinor -and $null -ne $desiredMinor) {
    if ($desiredMinor -gt $installedMinor) {
      $upgrade[$name] = $true
      Write-Host "=> upgrade flag for $($name): desired minor ($desiredMinor) > installed minor ($installedMinor)"
    } else {
      $upgrade[$name] = $false
      Write-Host "=> no upgrade for $($name): desired minor ($desiredMinor) <= installed minor ($installedMinor)"
    }
  } else {
    $upgrade[$name] = $false
    Write-Warning "=> no upgrade decision for $($name): cannot parse minor segment(s) (installed='$installedV', desired='$desiredV')"
  }
}
Write-Host "--------------------------------"

# --- Summary of decisions ---
Write-Host "==== Summary (Import Flags) ===="
$import.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host "$($_.Name) = $($_.Value)"
}
Write-Host "================================"

Write-Host "==== Summary (Upgrade Flags) ===="
$upgrade.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host "$($_.Name) = $($_.Value)"
}
Write-Host "================================"

# --- Set GitHub outputs (dynamically for all solutions) ---
if (-not $env:GITHUB_OUTPUT) {
  Write-Warning 'GITHUB_OUTPUT env var is not set; outputs will not be exported.'
  Write-Host "Would export the following outputs:"
} 

Write-Host "Writing outputs to GITHUB_OUTPUT..."
foreach ($name in $desiredVersions.Keys | Sort-Object) {
  $importLine = "import$name=$($import[$name])"
  $upgradeLine = "upgrade$name=$($upgrade[$name])"
  
  if ($env:GITHUB_OUTPUT) {
    $importLine | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    $upgradeLine | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    Write-Host "OUTPUT: $importLine"
    Write-Host "OUTPUT: $upgradeLine"
  } else {
    Write-Host "OUTPUT: $importLine"
    Write-Host "OUTPUT: $upgradeLine"
  }
}
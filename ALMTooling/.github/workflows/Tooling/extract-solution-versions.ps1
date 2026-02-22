[CmdletBinding()]
param()

Write-Host "== ExtractSolutionVersions.ps1 =="
# Script purpose:
# This script scans local solution folders (under `Solutions/Dependencies` and
# `Solutions/ProjectSolutions`) and extracts the solution version from each
# Other\Solution.xml file. It writes a JSON file mapping solution folder names
# to their extracted version strings (or null if missing/unreadable).
#
# Target path: $RUNNER_TEMP\packed\solution-versions.json
$outDir = Join-Path $env:RUNNER_TEMP 'packed'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$OutputJsonPath = Join-Path $outDir 'solution-versions.json'

Write-Host "Output JSON path: $OutputJsonPath"

# Base folders (expected local layout)
# - Solutions\Dependencies\<solutionFolder>\Other\Solution.xml
# - Solutions\ProjectSolutions\<solutionFolder>\Other\Solution.xml
$solutionsRoot      = 'Solutions'
$dependenciesRoot   = Join-Path $solutionsRoot 'Dependencies'
$projectSolutionsRoot = Join-Path $solutionsRoot 'ProjectSolutions'

# Collect all solution folders under Dependencies and ProjectSolutions
$solutionFolders = @()

if (Test-Path -LiteralPath $dependenciesRoot) {
    $solutionFolders += Get-ChildItem -LiteralPath $dependenciesRoot -Directory
}

if (Test-Path -LiteralPath $projectSolutionsRoot) {
    $solutionFolders += Get-ChildItem -LiteralPath $projectSolutionsRoot -Directory
}

if (-not $solutionFolders -or $solutionFolders.Count -eq 0) {
    Write-Warning "No solution folders found under '$dependenciesRoot' or '$projectSolutionsRoot'."
}

# Regex for <version>...</version> (case-insensitive, singleline)
$pattern = '(?i)<version>\s*(.*?)\s*</version>'

# Key-value collection: folder name -> version string (or $null)
$kv = @{}

foreach ($folder in $solutionFolders) {
    $name = $folder.Name
    $solutionXmlPath = Join-Path $folder.FullName 'Other\Solution.xml'

    try {
        if (-not (Test-Path -LiteralPath $solutionXmlPath)) {
            Write-Warning "Solution.xml not found for $name at $solutionXmlPath"
            # record missing file as null so downstream steps know the solution was found but version is unavailable
            $kv[$name] = $null
            continue
        }

        $content = Get-Content -LiteralPath $solutionXmlPath -Raw
        $m = [System.Text.RegularExpressions.Regex]::Match(
            $content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if ($m.Success) {
            $version = $m.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($version)) {
                Write-Warning "Version tag found but empty in $solutionXmlPath"
                $kv[$name] = $null
            } else {
                # store the extracted version string
                $kv[$name] = $version
                Write-Host "Found $name version: $version"
            }
        } else {
            Write-Warning "No <version> tag found in $solutionXmlPath"
            $kv[$name] = $null
        }
    }
    catch {
        Write-Error "Failed to read/parse ${solutionXmlPath}: $($_.Exception.Message)"
        $kv[$name] = $null
    }
}

# Write JSON to the RUNNER_TEMP packed folder
($kv | ConvertTo-Json -Depth 3) | Set-Content -Path $OutputJsonPath -Encoding UTF8

Write-Host "Created JSON at: $OutputJsonPath"
Write-Host "`n=== JSON CONTENT ==="
Write-Host (Get-Content $OutputJsonPath -Raw)
Write-Host "===================="

# Optional: Output für GitHub Actions
if ($env:GITHUB_OUTPUT) {
    # Export a GitHub Actions output variable pointing to the file
    "solutionVersionsPath=$OutputJsonPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    Write-Host "OUTPUT: solutionVersionsPath=$OutputJsonPath"
}
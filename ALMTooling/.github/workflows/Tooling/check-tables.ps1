# This script is used to identify tables in your solution which are included with all objects a situation we want to avoid in projects for custom tables.
# how to use:
# add the script to your repo and execute it within your Azure Pipeline
# default arguments to pass to the script:
# -publisher "orb" -path "$(Build.SourcesDirectory)\Solutions\ProjectSolutions\$(SolutionName)\Other\Solution.xml" -erroraction "Stop"
# Publisher defines the table prefix to ignore. Typically the project specific publisher.
# Path describes the place where the script can find your solution.xml.
# Erroraction defines how the script behaves when a table with all objects is found. Stop means the pipeline stops with error when a table is found.
# SilentlyContinue means the pipelines continues even though a table is found. In any case a warning is showing up in your pipeline run summary.

Param(
    [string] $publisher,
    [string] $path,
    [string] $erroraction
)

if (-not $publisher) {
    Write-Host "No publisher passed as param"
    $pub = " "
}
else {
    Write-Host $publisher "passed as param"
    $pub = $publisher
}

## casting the file text to an XML object
[xml]$xmlAttr = Get-Content -Path $path
$count = 0

## looping through rootcomponents of type table set with behavior="0"
$tablesWithAllObjects = $xmlAttr.ImportExportXml.SolutionManifest.RootComponents.RootComponent | Where-Object { $_.type -eq '1' -and $_.behavior -eq '0' -and $_.schemaName -notlike "$pub*" }

foreach ($table in $tablesWithAllObjects) {
    ## output the result object
    [pscustomobject]@{
        Tables_with_all_objects_included = $table.schemaName
    }    
    $count++

    # Hier wird der Tabellenname in die Fehlermeldung aufgenommen
    Write-Error -Message "Table '$($table.schemaName)' contains all objects. Please adjust solution!" -ErrorAction $erroraction
    Write-Host "##vso[task.logissue type=warning]Table '$($table.schemaName)' contains all objects. Please adjust solution!"
}

if ($count -eq 0) {
    Write-Host "No tables with all objects included in the solution. Good Job."
}

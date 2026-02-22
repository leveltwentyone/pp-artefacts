Param(
    [string] [Parameter(Mandatory = $true)] $sourcebranch,
    [string] [Parameter(Mandatory = $true)] $branchname
)

# create new branch to extract the solutions to
$DeveloperBranch = $branchname + (Get-Date -Format "dd-MM-yyyy/hh-mm")

# set git commit details
git config --global user.name $env:GITHUB_ACTOR
git config --global user.email "$env:GITHUB_ACTOR@users.noreply.github.com"

# fetch and checkout sourcebranch as base
git fetch origin $sourcebranch
git checkout $sourcebranch

# create new branch based on sourcebranch
git checkout -b $DeveloperBranch

# push new branch to origin (set upstream so later jobs can checkout)
git push -u origin $DeveloperBranch

# Setze Step-Output für GitHub Actions
"developer-branch=$DeveloperBranch" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append

# Base64 Output korrekt schreiben
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($DeveloperBranch))
"developer-branch-encoded=$encoded" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append

Param(
    [string] [Parameter(Mandatory = $true)] $commitmessage
)

# git commit
git add --all :!pac_cli
git commit -m $commitmessage
git push --set-upstream origin $env:DeveloperBranch
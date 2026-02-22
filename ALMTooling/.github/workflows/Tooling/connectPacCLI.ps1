Param(
    [string] [Parameter(Mandatory = $true)] $clientid,
    [string] [Parameter(Mandatory = $true)] $tenantid,
    [string] [Parameter(Mandatory = $true)] $environmenturl
)
 
pac auth create --environment $environmenturl --applicationId $clientid --githubFederated --tenant $tenantid
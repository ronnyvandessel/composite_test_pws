# WinGet.RestValidation.psm1
# Local REST-based validation helpers (no winget CLI required)

function Test-WinGetPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $uri = "https://api.winget.microsoft.com/v1.0/packageManifests/$PackageId"

    try {
        Invoke-RestMethod `
            -Uri $uri `
            -Method Get `
            -Headers @{
                Accept = 'application/json'
                'User-Agent' = 'WinGet-REST-Validation'
            } `
            -TimeoutSec 15 `
            -ErrorAction Stop | Out-Null

        return $true
    }
    catch {
        if ($_.Exception.Response -and
            $_.Exception.Response.StatusCode.Value__ -eq 404) {
            return $false
        }

        throw "WinGet REST API error for '$PackageId': $($_.Exception.Message)"
    }
}
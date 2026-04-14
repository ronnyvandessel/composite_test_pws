# WinGet.RestValidation.psm1
# Local REST-based validation helpers (no winget CLI required)

# GitHub-API-based WinGet validation helpers

function Test-WinGetPackageViaGitHub {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    # Split PackageIdentifier correctly (supports multi-segment IDs)
    $segments = $PackageId.Split('.')
    $firstLetter = $segments[0].Substring(0,1).ToLower()

    # Build winget-pkgs path
    # manifests/<first-letter>/<Publisher>/<Sub>/<Sub>/...
    $pathParts = @('manifests', $firstLetter) + $segments
    $path = ($pathParts -join '/')

    $uri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$path"

    try {
        Invoke-RestMethod `
            -Uri $uri `
            -Headers @{
                'Accept'     = 'application/vnd.github+json'
                'User-Agent' = 'WinGet-DSC-Validation'
            } `
            -Method Get `
            -TimeoutSec 15 `
            -ErrorAction Stop | Out-Null

        return $true
    }
    catch {
        # 404 = path does not exist → package does not exist
        if ($_.Exception.Response -and
            $_.Exception.Response.StatusCode.Value__ -eq 404) {
            return $false
        }

        throw "GitHub API error while querying '$PackageId': $($_.Exception.Message)"
    }
}

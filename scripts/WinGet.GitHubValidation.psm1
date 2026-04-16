# WinGet.RestValidation.psm1
# GitHub‑API‑only validation using GITHUB_TOKEN (no anonymous calls)

$script:WingetGitHubCache = @{}

function Test-WinGetPackageViaGitHub {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    # Cache check (1 call per unique package per run)
    if ($script:WingetGitHubCache.ContainsKey($PackageId)) {
        return $script:WingetGitHubCache[$PackageId]
    }

    if (-not $env:GITHUB_TOKEN) {
        throw "GITHUB_TOKEN is not available. This function requires GitHub Actions."
    }

    # Build path: manifests/<first-letter>/<Publisher>/<Sub>/...
    $segments    = $PackageId.Split('.')
    $firstLetter = $segments[0].Substring(0, 1).ToLower()
    $path        = (@('manifests', $firstLetter) + $segments) -join '/'

    $uri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$path"

    $headers = @{
        'Accept'        = 'application/vnd.github+json'
        'User-Agent'    = 'WinGet-DSC-Validation'
        'Authorization' = "Bearer $env:GITHUB_TOKEN"
    }

    try {
        Invoke-RestMethod `
            -Uri $uri `
            -Headers $headers `
            -Method Get `
            -TimeoutSec 15 `
            -ErrorAction Stop | Out-Null

        $script:WingetGitHubCache[$PackageId] = $true
        return $true
    }
    catch {
        if ($_.Exception.Response -and
            $_.Exception.Response.StatusCode.Value__ -eq 404) {

            $script:WingetGitHubCache[$PackageId] = $false
            return $false
        }

        throw "GitHub API error for '$PackageId': $($_.Exception.Message)"
    }
}
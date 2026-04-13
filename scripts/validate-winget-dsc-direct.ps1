[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DscFile
)

Write-Host "📄 Reading DSC configuration: $DscFile"

if (-not (Test-Path $DscFile)) {
    Write-Error "DSC file not found: $DscFile"
    exit 1
}

# --------------------------------------------------
# Helper: check if WinGet package exists via winget CLI
# --------------------------------------------------
function Test-WinGetPackageExists {
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        $result = winget search `
            --id $PackageId `
            --exact `
            --source winget `
            --output json 2>$null |
            ConvertFrom-Json

        return ($result -and $result.Data -and $result.Data.Count -gt 0)
    }
    catch {
        return $false
    }
}

# --------------------------------------------------
# Parse DSC YAML
# --------------------------------------------------
$dscConfig = Get-Content $DscFile -Raw | ConvertFrom-Yaml

$wingetResources = $dscConfig.properties.resources | Where-Object {
    $_.resource -eq 'Microsoft.WinGet.DSC/WinGetPackage' -and
    $_.settings.source -eq 'winget'
}

if (-not $wingetResources) {
    Write-Host "ℹ️ No WinGetPackage resources found in DSC file."
    exit 0
}

# --------------------------------------------------
# Validation
# --------------------------------------------------
$invalidPackages = @()

foreach ($resource in $wingetResources) {
    $packageId = $resource.settings.id
    Write-Host "🔍 Validating WinGet package via winget CLI: $packageId"

    if (Test-WinGetPackageExists -PackageId $packageId) {
        Write-Host "✅ Package '$packageId' is known to winget"
    }
    else {
        Write-Error "❌ Package '$packageId' is NOT known to winget"
        $invalidPackages += $packageId
    }
}

if ($invalidPackages.Count -gt 0) {
    Write-Error "Invalid WinGet package IDs found: $($invalidPackages -join ', ')"
    exit 1
}

Write-Host "🎉 All WinGet DSC WinGetPackage IDs are valid according to winget."
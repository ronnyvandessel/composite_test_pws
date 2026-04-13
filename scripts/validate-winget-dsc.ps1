[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DscFile,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WingetRepoRoot
)

Write-Host "📄 Reading DSC configuration: $DscFile"

if (-not (Test-Path $DscFile)) {
    Write-Error "DSC file not found: $DscFile"
    exit 1
}

# --------------------------------------------------
# Helper: check if a WinGet package exists in winget-pkgs
# Supports multi-segment PackageIdentifiers
# --------------------------------------------------
function Test-WinGetPackageExists {
    param (
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$WingetRepoRoot
    )

    if ($PackageId -notmatch '\.') {
        return $false
    }

    $segments = $PackageId.Split('.')
    $firstLetter = $segments[0].Substring(0,1).ToLower()

    # Build path step-by-step (robust)
    $relativePath = 'manifests'
    $relativePath = Join-Path $relativePath $firstLetter

    foreach ($segment in $segments) {
        $relativePath = Join-Path $relativePath $segment
    }

    $packagePath = Join-Path $WingetRepoRoot $relativePath

    # Debug (optioneel, kan je later verwijderen)
    Write-Host "Resolved winget path: $packagePath"

    return (Test-Path $packagePath)
}
# =========================
# Load powershell-yaml from local .nupkg (robust)
# =========================

$packageName = "powershell-yaml.0.4.12.nupkg"

$nupkgPath = Join-Path $PSScriptRoot "..\packages\$packageName"
if (-not (Test-Path $nupkgPath)) {
    Write-Error "NuPkg not found: $nupkgPath"
    exit 1
}

$extractRoot = Join-Path $env:RUNNER_TEMP "powershell-yaml"

if (Test-Path $extractRoot) {
    Remove-Item $extractRoot -Recurse -Force
}

Write-Host "Extracting powershell-yaml van $nupkgPath"
Expand-Archive -Path $nupkgPath -DestinationPath $extractRoot -Force

# 🔍 Zoek automatisch naar de module
$modulePath = Get-ChildItem $extractRoot -Recurse -Filter "*.psm1" |
              Where-Object { $_.Name -match "powershell-yaml" } |
              Select-Object -First 1 -ExpandProperty FullName

if (-not $modulePath) {
    Write-Error "powershell-yaml.psm1 not found in extracted package"
    Write-Host "Extracted contents:"
    Get-ChildItem $extractRoot -Recurse
    exit 1
}



Import-Module $modulePath -Force
Write-Host "powershell-yaml module geladen"


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
    Write-Host "🔍 Validating WinGet package: $packageId"

    if (Test-WinGetPackageExists `
        -PackageId $packageId `
        -WingetRepoRoot $WingetRepoRoot) {

        Write-Host "✅ Package '$packageId' exists in winget"
    }
    else {
        Write-Error "❌ Package '$packageId' is NOT known in winget"
        $invalidPackages += $packageId
    }
}

if ($invalidPackages.Count -gt 0) {
    Write-Error "Invalid WinGet package IDs found: $($invalidPackages -join ', ')"
    exit 1
}

Write-Host "🎉 All WinGet DSC WinGetPackage IDs are valid."
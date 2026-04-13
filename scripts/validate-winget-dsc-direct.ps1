[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DscFile
)

Write-Host "📄 Reading DSC configuration: $DscFile"

if (-not (Test-Path $DscFile)) {
    Write-Error "❌ DSC file not found: $DscFile"
    exit 1
}

# --------------------------------------------------
# Helper: check if WinGet package exists via `winget show`
# This works for:
# - community packages
# - Microsoft builtin / framework packages
# - exactly matches DSC install behavior
# --------------------------------------------------
function Test-WinGetPackageExists {
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        # We don't care about the output, only if WinGet resolves the ID
        winget show $PackageId --output json 2>$null | Out-Null
        return $true
    }
    catch {
        return $false
    }
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
    Write-Host "🔍 Validating WinGet package via winget show: $packageId"

    if (Test-WinGetPackageExists -PackageId $packageId) {
        Write-Host "✅ Package '$packageId' is known to WinGet"
    }
    else {
        Write-Error "❌ Package '$packageId' is NOT known to WinGet"
        $invalidPackages += $packageId
    }
}

if ($invalidPackages.Count -gt 0) {
    Write-Error "Invalid WinGet package IDs found: $($invalidPackages -join ', ')"
    exit 1
}

Write-Host "🎉 All WinGet DSC WinGetPackage IDs are valid according to winget."
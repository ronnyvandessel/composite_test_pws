<#
.SYNOPSIS
Validates msstore WinGetPackage resources in a DSC YAML file using
Microsoft.WinGet.Client (NuPkg-based, no winget.exe required).
#>

param (
    [Parameter(Mandatory)]
    [string]$DscFile,

    [Parameter(Mandatory)]
    [string]$WinGetClientNuPkg
)

$ErrorActionPreference = 'Stop'

Write-Host "📄 Reading DSC configuration: $DscFile"

if (-not (Test-Path $DscFile)) {
    Write-Host "❌ DSC file not found: $DscFile"
    exit 1
}

if (-not (Test-Path $WinGetClientNuPkg)) {
    Write-Host "❌ Microsoft.WinGet.Client NuPkg not found: $WinGetClientNuPkg"
    exit 1
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


# ------------------------------------------------------------------
# Import Microsoft.WinGet.Client from NuPkg
# ------------------------------------------------------------------
$extractPath = Join-Path $env:TEMP "winget-client"

if (-not (Test-Path $extractPath)) {
    Write-Host "📦 Extracting WinGet Client NuPkg..."
    Expand-Archive -Path $WinGetClientNuPkg -DestinationPath $extractPath -Force
}

$dll = Get-ChildItem $extractPath -Recurse `
    -Filter "Microsoft.WinGet.Client.dll" |
    Select-Object -First 1

if (-not $dll) {
    Write-Host "❌ Microsoft.WinGet.Client.dll not found in NuPkg"
    exit 1
}

Add-Type -Path $dll.FullName
Write-Host "✅ Loaded Microsoft.WinGet.Client"

# ------------------------------------------------------------------
# Helper: check msstore package via WinGet client
# ------------------------------------------------------------------
function Test-MsStorePackage {
    param (
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        $pm = [Microsoft.WinGet.Client.PackageManager]::new()
        $sources = $pm.GetSources()

        $storeSource = $sources | Where-Object Name -eq 'msstore'
        if (-not $storeSource) {
            throw "WinGet source 'msstore' not available"
        }

        $options = [Microsoft.WinGet.Client.CompositeSearchOptions]::new()
        $options.SearchById = $PackageId
        $options.Source = $storeSource

        $result = $pm.Search($options)
        return ($result.Matches.Count -gt 0)
    }
    catch {
        Write-Host "⚠️ WinGet client error for msstore package '$PackageId': $($_.Exception.Message)"
        return $false
    }
}


# ------------------------------------------------------------------
# Parse DSC YAML
# ------------------------------------------------------------------
$config = Get-Content $DscFile -Raw | ConvertFrom-Yaml

$resources = $config.properties.resources | Where-Object {
    $_.resource -eq 'Microsoft.WinGet.DSC/WinGetPackage' -and
    $_.settings.source -eq 'msstore'
}

if (-not $resources) {
    Write-Host "ℹ️ No msstore WinGetPackage resources found."
    exit 0
}

# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------
$invalid = @()

foreach ($res in $resources) {
    $id = $res.settings.id
    Write-Host "🔍 Validating msstore package via WinGet Client: $id"

    if (Test-MsStorePackage -PackageId $id) {
        Write-Host "✅ msstore package '$id' exists"
    }
    else {
        Write-Host "❌ msstore package '$id' does NOT exist or is not accessible"
        $invalid += $id
    }
}

if ($invalid.Count -gt 0) {
    Write-Host ""
    Write-Host "❌ Invalid msstore package IDs:"
    $invalid | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "🎉 All msstore WinGetPackage IDs are valid."
exit 0
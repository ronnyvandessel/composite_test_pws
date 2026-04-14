param (
    [Parameter(Mandatory)]
    [string]$DscFile
)

$ErrorActionPreference = 'Stop'

Write-Host "📄 Reading DSC configuration: $DscFile"

if (-not (Test-Path $DscFile)) {
    Write-Host "❌ DSC file not found: $DscFile"
    exit 1
}

# Import local GitHub API validation module
$modulePath = Join-Path $PSScriptRoot 'WinGet.GitHubValidation.psm1'
Import-Module $modulePath -Force


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


# Parse DSC YAML
$config = Get-Content $DscFile -Raw | ConvertFrom-Yaml

$wingetResources = $config.properties.resources | Where-Object {
    $_.resource -eq 'Microsoft.WinGet.DSC/WinGetPackage' -and
    $_.settings.source -eq 'winget'
}

if (-not $wingetResources) {
    Write-Host "ℹ️ No WinGetPackage resources found."
    exit 0
}

$invalidPackages = @()

foreach ($res in $wingetResources) {
    $id = $res.settings.id
    Write-Host "🔍 Validating WinGet package via GitHub API: $id"

    if (Test-WinGetPackageViaGitHub -PackageId $id) {
        Write-Host "✅ Package '$id' exists in winget-pkgs"
    }
    else {
        Write-Host "❌ Package '$id' does NOT exist in winget-pkgs"
        $invalidPackages += $id
    }
}

if ($invalidPackages.Count -gt 0) {
    Write-Host ""
    Write-Host "❌ Invalid WinGet package IDs found:"
    $invalidPackages | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "🎉 All WinGet DSC WinGetPackage IDs are valid (GitHub API)."
exit 0
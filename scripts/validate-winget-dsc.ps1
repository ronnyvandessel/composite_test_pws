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
# Helper: check if package EXISTS in winget
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

    $publisher, $app = $PackageId -split '\.', 2
    $firstLetter = $publisher.Substring(0,1).ToLower()

    $packagePath = Join-Path $WingetRepoRoot "manifests\$firstLetter\$publisher\$app"

    return (Test-Path $packagePath)
}

# --------------------------------------------------
# Helper: best-effort downloadability check (OPTIONAL)
# --------------------------------------------------
function Test-WinGetPackageHasInstaller {
    param (
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$WingetRepoRoot
    )

    $publisher, $app = $PackageId -split '\.', 2
    $firstLetter = $publisher.Substring(0,1).ToLower()
    $packagePath = Join-Path $WingetRepoRoot "manifests\$firstLetter\$publisher\$app"

    if (-not (Test-Path $packagePath)) {
        return $false
    }

    # 👉 GEEN [version] cast meer (NodeJS, Java, etc.)
    $latestVersion = Get-ChildItem $packagePath -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $latestVersion) {
        return $false
    }

    $installerFile = Get-ChildItem $latestVersion.FullName -Filter "*installer*.yaml" |
        Select-Object -First 1

    if (-not $installerFile) {
        return $false
    }

    $installer = Get-Content $installerFile.FullName -Raw | ConvertFrom-Yaml

    return ($installer.Installers | Where-Object { $_.InstallerUrl }).Count -gt 0
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
    Write-Host "ℹ️ No WinGetPackage resources found."
    exit 0
}

# --------------------------------------------------
# Validation
# --------------------------------------------------
$errors = @()

foreach ($res in $wingetResources) {
    $packageId = $res.settings.id
    Write-Host "🔍 Validating WinGet package: $packageId"

    # 1️⃣ EXISTS check (hard fail)
    if (-not (Test-WinGetPackageExists `
        -PackageId $packageId `
        -WingetRepoRoot $WingetRepoRoot)) {

        Write-Error "❌ Package '$packageId' is NOT known in winget"
        $errors += $packageId
        continue
    }

    Write-Host "✅ Package '$packageId' exists in winget"

    # 2️⃣ Download check (informational)
    if (Test-WinGetPackageHasInstaller `
        -PackageId $packageId `
        -WingetRepoRoot $WingetRepoRoot) {

        Write-Host "⬇️ Package '$packageId' has downloadable installer(s)"
    }
    else {
        Write-Host "⚠️ Package '$packageId' has no direct installer URL (allowed)"
    }
}

if ($errors.Count -gt 0) {

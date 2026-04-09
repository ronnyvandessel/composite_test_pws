param (
    [Parameter(Mandatory)]
    [string]$Path
)

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

Write-Host "uitlezen YAML : $Path"


$yamlPath = $path

$yamlRaw = Get-Content $yamlPath -Raw
$config  = ConvertFrom-Yaml $yamlRaw

$config.project.name
write-host config: $config


<# Write-Host "Reading JSONC from: $Path"

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

$raw = Get-Content $Path -Raw

# Remove // comments
$raw = $raw -replace '(?m)^\s*//.*$', ''

# Remove /* */ comments
$raw = $raw -replace '(?s)/\*.*?\*/', ''

$config = $raw | ConvertFrom-Json

if (-not $config.Targets_R0) {
    Write-Error "Targets_R0 not found in JSONC"
    exit 1
}

$targetsR0 = $config.Targets_R0 -join ","

Write-Host "Targets_R0 = $targetsR0"

# Expose output to GitHub Actions
"targets_r0=$targetsR0" >> $env:GITHUB_OUTPUT

$dataPath = Join-Path $PSScriptRoot "data.txt"
$lines = Get-Content $dataPath
foreach ($line in $lines) {
    Write-Host $line
}
"lines_count=$($lines.Count)" >> $env:GITHUB_OUTPUT

# schrijven naar $path


# Nieuwe lijnen toevoegen
$newTargets = @("SOFV000010", "SOFV000011")

$config.Targets_R0 += $newTargets

# JSON terug wegschrijven
$config | ConvertTo-Json -Depth 10 | Set-Content $Path
Write-Host "Updated JSONC written to: $Path"


if ($env:GITHUB_ACTOR -eq "github-actions[bot]") {
    Write-Host "Skipping commit to avoid loop"
    exit 0
}

# --- GIT COMMIT & PUSH ---
git config user.name "github-actions"
git config user.email "actions@github.com"

git status

git add Params.jsonc

# Alleen committen als er echt iets gewijzigd is
if (-not (git diff --cached --quiet)) {
    git commit -m "Update Params.jsonc via workflow"
    git push
    Write-Host "✅ Changes committed and pushed"
}
else {
    Write-Host "ℹ️ No changes to commit"
}

 #>
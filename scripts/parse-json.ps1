param (
    [Parameter(Mandatory)]
    [string]$Path
)

Write-Host "Reading JSONC from: $Path"

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

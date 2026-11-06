param(
    [switch]$Build
)

# Variante de start.ps1 para Docker Desktop en Windows (sin Ubuntu-24.04 dedicado).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root '.env'))) {
    throw 'Run scripts/init-env.ps1 before starting CoreStream.'
}

& docker.exe info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop is not running. Open Docker Desktop and wait for "Engine running".'
}

$composeArguments = @('up', '--no-build')
if ($Build) {
    $composeArguments = @('up', '--build')
}

'Keep this terminal open while using CoreStream. Press Ctrl+C to stop the services.'
Push-Location -LiteralPath $root
try {
    & docker.exe compose @composeArguments
    if ($LASTEXITCODE -notin @(0, 130)) {
        throw "Docker Compose exited with code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

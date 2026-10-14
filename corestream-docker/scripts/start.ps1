param(
    [switch]$Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root '.env'))) {
    throw 'Run scripts/init-env.ps1 before starting CoreStream.'
}

# Keep a foreground WSL command alive for the entire development session.
# systemd services alone do not prevent WSL from shutting down when idle.
& wsl.exe -d Ubuntu-24.04 -u root --exec /usr/bin/systemctl start docker
if ($LASTEXITCODE -ne 0) {
    throw 'Docker could not be started in Ubuntu-24.04.'
}

$composeArguments = @('up', '--no-build')
if ($Build) {
    $composeArguments = @('up', '--build')
}

'Keep this terminal open while using CoreStream. Press Ctrl+C to stop the services.'
& wsl.exe -d Ubuntu-24.04 -u root --cd $root --exec /usr/bin/docker compose @composeArguments
if ($LASTEXITCODE -notin @(0, 130)) {
    throw "Docker Compose exited with code $LASTEXITCODE."
}

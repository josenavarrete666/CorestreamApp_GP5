Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root '.env'
if (Test-Path -LiteralPath $destination) {
    'The existing .env is preserved.'
    return
}
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $password = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    $rng.GetBytes($bytes)
    $secret = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
finally {
    $rng.Dispose()
}
$lines = @(
    'POSTGRES_DB=corestream',
    'POSTGRES_USER=corestream',
    "POSTGRES_PASSWORD=$password",
    "SECRET_KEY=$secret",
    'POSTGRES_PORT=5433',
    'REDIS_PORT=6380',
    'BACKEND_PORT=8001',
    'WEB_PORT=7358'
)
[IO.File]::WriteAllLines($destination, $lines, (New-Object Text.UTF8Encoding($false)))
'Local Docker configuration created in .env.'

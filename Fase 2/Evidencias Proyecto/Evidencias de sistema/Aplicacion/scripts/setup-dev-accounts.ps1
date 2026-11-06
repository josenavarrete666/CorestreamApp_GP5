# Prepara en una base nueva las cuentas compartidas del equipo (@alloxentric)
# y el dataset beta, con un solo comando. Requiere el backend arriba
# (scripts/start-desktop.ps1) y el archivo privado del equipo
# backend/.local/credenciales-dev.json, que NO se versiona: se recibe por un
# canal privado. Nunca imprime contraseñas.
#
# Idempotente: si las cuentas ya existen, solo vuelve a aplicar las contraseñas.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root 'backend\.local'
$credentialsFile = Join-Path $local 'credenciales-dev.json'
$adminFile = Join-Path $local 'admin.json'
$contentFile = Join-Path $local 'beta-content.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $credentialsFile)) {
    throw 'Falta backend\.local\credenciales-dev.json. Pídelo al equipo por un canal privado.'
}
$accounts = [IO.File]::ReadAllText($credentialsFile, $utf8) | ConvertFrom-Json
$admin = @($accounts | Where-Object { $_.rol -eq 'ADMIN' })
if ($admin.Count -ne 1) { throw 'credenciales-dev.json debe tener exactamente una cuenta con rol ADMIN.' }
$admin = $admin[0]

Push-Location -LiteralPath $root
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'protect-local.ps1') | Out-Null
    $envValues = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $root '.env'), $utf8)) {
        if ($line -match '^\s*([A-Z_]+)=(.*)$') { $envValues[$matches[1]] = $matches[2] }
    }
    $dbUser = if ($envValues['POSTGRES_USER']) { $envValues['POSTGRES_USER'] } else { 'corestream' }
    $dbName = if ($envValues['POSTGRES_DB']) { $envValues['POSTGRES_DB'] } else { 'corestream' }
    function Invoke-Sql([string]$sql) {
        $out = & docker.exe compose exec -T postgres psql -U $dbUser -d $dbName -t -A -c $sql
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar PostgreSQL. ¿Está el backend arriba?' }
        return ("$out").Trim()
    }

    # 1. ADMIN: se crea con la cuenta de Ana solo si la base no tiene ninguno.
    $existing = Invoke-Sql "select u.id || '|' || u.email from users u join roles r on r.id = u.role_id where r.name = 'ADMIN';"
    if (-not $existing) {
        $passwordFile = Join-Path $local 'admin-password.tmp'
        [IO.File]::WriteAllText($passwordFile, $admin.password, $utf8)
        try {
            & docker.exe compose exec -T backend python -m app.scripts.create_admin `
                --email $admin.email --full-name $admin.nombre --password-file /app/.local/admin-password.tmp
            if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el ADMIN.' }
        } finally {
            Remove-Item -LiteralPath $passwordFile -Force -ErrorAction SilentlyContinue
        }
        $existing = Invoke-Sql "select u.id || '|' || u.email from users u join roles r on r.id = u.role_id where r.name = 'ADMIN';"
    }
    $adminId, $adminEmail = $existing.Split('|')
    if ($adminEmail -ne $admin.email -and -not (Test-Path -LiteralPath $contentFile)) {
        throw "La base ya tiene otro ADMIN ($adminEmail). Este script es para una base nueva o ya preparada con él."
    }

    # 2. Manifiesto del ADMIN, que exige la carga beta.
    if (-not (Test-Path -LiteralPath $adminFile)) {
        $manifest = [ordered]@{ admin_id = $adminId; users = @{ admin = [ordered]@{ email = $admin.email; password = $admin.password } } }
        [IO.File]::WriteAllText($adminFile, ($manifest | ConvertTo-Json -Depth 5), $utf8)
    }

    # 3. Dataset beta (5 personas, 3 proyectos, tickets, incidencias y avisos).
    if (-not (Test-Path -LiteralPath $contentFile)) {
        $dataset = [guid]::NewGuid().ToString()
        & docker.exe compose exec -T backend python -m scripts.beta_content setup $dataset `
            --local-file .local/beta-content.json --admin-file .local/admin.json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'La carga del dataset beta falló.' }
        'Dataset beta cargado.'
    } else {
        'Dataset beta ya preparado en esta instalación; se conserva.'
    }

    # 4. Contraseñas compartidas del equipo y verificación.
    & docker.exe compose exec -T backend python -m scripts.dev_accounts apply `
        --credentials-file .local/credenciales-dev.json `
        --manifest .local/admin.json --manifest .local/beta-content.json
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron aplicar las contraseñas compartidas.' }
    $dataset = ([IO.File]::ReadAllText($contentFile, $utf8) | ConvertFrom-Json).dataset_id
    & docker.exe compose exec -T backend python -m scripts.beta_content check $dataset --local-file .local/beta-content.json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'La verificación del dataset beta falló.' }
    'Cuentas @alloxentric listas. Las contraseñas están en backend\.local\credenciales-dev.json.'
} finally {
    Pop-Location
}

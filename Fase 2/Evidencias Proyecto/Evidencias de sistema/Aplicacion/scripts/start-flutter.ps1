param(
    [string]$ApiUrl = 'http://localhost:8001',
    [switch]$Rebuild,
    [switch]$PrepareOnly,
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'movil'
$stateFile = Join-Path $root '.cache\flutter-web.json'
$web = Join-Path $mobile 'build\web'
$origin = [uri]$ApiUrl
if (-not $origin.IsAbsoluteUri -or $origin.Scheme -notin @('http', 'https') -or
    $origin.AbsolutePath -ne '/' -or $origin.Query -or $origin.Fragment -or $origin.UserInfo) {
    throw 'ApiUrl must be an HTTP(S) origin without path, query, fragment or credentials.'
}
$ApiUrl = $origin.GetLeftPart([System.UriPartial]::Authority)
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$node = (Get-Command node -ErrorAction Stop).Source
$nodeVersion = & $node --version
if ($LASTEXITCODE -ne 0 -or [int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 22) {
    throw 'Node.js 22 or newer is required.'
}
if (-not $PrepareOnly) {
    if (Get-NetTCPConnection -LocalPort 7358 -State Listen -ErrorAction SilentlyContinue) {
        throw 'Port 7358 is already in use. Stop the existing web terminal before starting another.'
    }
    try { $health = Invoke-RestMethod -Uri "$ApiUrl/api/health" -TimeoutSec 15 }
    catch { throw 'The API is unavailable. Start scripts/start.ps1 in its own terminal first.' }
    if ($health.status -ne 'ok') { throw 'The API is not healthy.' }
}

function Get-Fingerprint([string[]]$Files, [string]$Context) {
    $lines = @($Context)
    foreach ($file in ($Files | Sort-Object -Unique)) {
        $lines += "$($file.Substring($mobile.Length))=$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)"
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($lines -join "`n"))).Replace('-', '')
    } finally { $sha.Dispose() }
}

$oldCache = $env:PUB_CACHE
$cacheMissing = -not (Test-Path -LiteralPath (Join-Path $root '.pub-cache'))
$env:PUB_CACHE = Join-Path $root '.pub-cache'
$server = $null
Push-Location -LiteralPath $mobile
try {
    $versionOutput = & $flutter --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Flutter version check failed.' }
    $version = ($versionOutput -join "`n") | ConvertFrom-Json
    $sdk = "$root|$($version.frameworkRevision)|$($version.engineRevision)|$($version.dartSdkVersion)"
    $dependencies = @((Join-Path $mobile 'pubspec.yaml'), (Join-Path $mobile 'pubspec.lock'))
    $dependencyHash = Get-Fingerprint $dependencies $sdk
    $state = $null
    if (Test-Path -LiteralPath $stateFile) {
        try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { $state = $null }
    }
    if ($null -ne $state -and (@('dependencies', 'build', 'apiUrl') | Where-Object {
        $_ -notin $state.PSObject.Properties.Name
    })) { $state = $null }
    $needsPackages = $null -eq $state -or $state.dependencies -ne $dependencyHash -or $cacheMissing -or
        -not (Test-Path -LiteralPath (Join-Path $mobile '.dart_tool\package_config.json'))
    if ($needsPackages) {
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile }
        'Preparing Flutter dependencies...'
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed; the web server was not started.' }
        $dependencyHash = Get-Fingerprint $dependencies $sdk
    }
    $inputs = @($dependencies)
    foreach ($folder in @('lib', 'web', 'assets')) {
        $directory = Join-Path $mobile $folder
        if (Test-Path -LiteralPath $directory) {
            $inputs += @(Get-ChildItem -LiteralPath $directory -File -Recurse | ForEach-Object { $_.FullName })
        }
    }
    $buildHash = Get-Fingerprint $inputs "$sdk|$ApiUrl"
    $needsBuild = $Rebuild -or $needsPackages -or $null -eq $state -or $state.build -ne $buildHash -or
        -not (Test-Path -LiteralPath (Join-Path $web 'index.html')) -or
        -not (Test-Path -LiteralPath (Join-Path $web 'main.dart.js'))
    if ($needsBuild) {
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile }
        "Building Flutter Web for $ApiUrl..."
        & $flutter build web --no-pub "--dart-define=CS_API_URL=$ApiUrl"
        if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed; the web server was not started.' }
    } else { 'Flutter Web is up to date; reusing the verified build.' }
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $stateFile))
    $json = @{ dependencies = $dependencyHash; build = $buildHash; apiUrl = $ApiUrl } | ConvertTo-Json
    [System.IO.File]::WriteAllText($stateFile, $json, [Text.UTF8Encoding]::new($false))
    if ($PrepareOnly) { 'Flutter preparation complete.'; return }

    $script = Join-Path $PSScriptRoot 'serve-web.mjs'
    $server = Start-Process -FilePath $node -ArgumentList ('"{0}"' -f $script) -NoNewWindow -PassThru
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ($server.HasExited) { throw 'The web server exited before becoming ready.' }
        try {
            $response = Invoke-WebRequest -Uri 'http://127.0.0.1:7358/' -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { break }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    if ($attempt -eq 50) { throw 'The web server did not become ready.' }
    if (-not $NoBrowser) {
        $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $edge) { Start-Process -FilePath $edge -ArgumentList 'http://localhost:7358/' }
        else { Start-Process 'http://localhost:7358/' }
    }
    'Keep this terminal open. Press Ctrl+C to stop Flutter Web; the backend stays running.'
    $server.WaitForExit()
    if ($server.ExitCode -notin @(0, 130, -1073741510)) { throw "Web server exited with code $($server.ExitCode)." }
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id -ErrorAction SilentlyContinue }
    $env:PUB_CACHE = $oldCache
    Pop-Location
}

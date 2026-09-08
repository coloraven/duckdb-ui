#Requires -Version 5.1
<#
.SYNOPSIS
  Start the coloraven/duckdb-ui offline fork (Windows). Local-first; fetch only when needed.

.DESCRIPTION
  Standalone — copy this script anywhere; it does not need the git repo.

  Default (no flags): if ui_offline.duckdb_extension and assets/index.html already
    exist, just start DuckDB + UI. No GitHub download.

  Extension install path (never official ui.duckdb_extension):
    ~/.duckdb/extensions/{version}/windows_amd64/ui_offline.duckdb_extension

  Assets remain under ~/.duckdb/extension_data/ui/assets.

  Release pull (extension zip + ui-assets.tar.gz) happens only when:
    - local extension or static assets are missing, or
    - you pass -Fetch (force refresh from offline-latest).

  Runtime (extension): always local-first for static assets; missing files are
    filled from ui_remote_url and cached. Browser third-party calls are CSP-blocked.
    Pass -AirGap to SET ui_offline=true (never remote-fill assets; 503 on miss).

  The fork binary entrypoint is ui_offline — LOAD the installed path directly
  (no temp rename to ui.duckdb_extension).

.PARAMETER Fetch
  Force download/install from the offline-latest release (even if local files exist).

.PARAMETER AirGap
  SET ui_offline=true — never fetch missing assets from the network (HTTP 503).

.PARAMETER NoStart
  Install/ensure only; do not launch DuckDB.

.PARAMETER Direct
  Download GitHub without gh-proxy.com (default uses proxy for mainland China).

.EXAMPLE
  .\start_ui.ps1
  .\start_ui.ps1 -Fetch
  .\start_ui.ps1 -Fetch -NoStart
  .\start_ui.ps1 -AirGap

  # Fetch script without cloning the repo, then run:
  curl.exe -fsSL -o start_ui.ps1 https://gh-proxy.com/https://raw.githubusercontent.com/coloraven/duckdb-ui/main/scripts/start_ui.ps1
  powershell -ExecutionPolicy Bypass -File .\start_ui.ps1
#>
param(
    [string]$Repo = "coloraven/duckdb-ui",
    [string]$Tag = "offline-latest",

    [string]$AssetsPath = $(Join-Path $env:USERPROFILE ".duckdb\extension_data\ui\assets"),
    [string]$WorkDir = $(Join-Path $env:USERPROFILE ".duckdb\extension_data\ui"),

    [string]$DuckDB = "duckdb",
    # e.g. v1.5.5 — empty = probe duckdb CLI, else default v1.5.5
    [string]$DuckDBVersion = "",
    [string]$Platform = "windows_amd64",

    [switch]$Fetch,
    [switch]$AirGap,
    [switch]$NoStart,
    [switch]$Direct
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Persisted fork binary — must not collide with official ui.duckdb_extension
# (same extensions/{ver}/{platform} folder is OK; different stem avoids signature clash).
$ForkExtStem = "ui_offline"
$ForkExtName = "$ForkExtStem.duckdb_extension"

function Resolve-DuckDbVersion([string]$DuckDBBin, [string]$Override) {
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        $v = $Override.Trim()
        if ($v -notlike 'v*') { $v = "v$v" }
        return $v
    }
    $cmd = Get-Command $DuckDBBin -ErrorAction SilentlyContinue
    if ($cmd) {
        $raw = & $DuckDBBin -csv -noheader -c "SELECT version();" 2>$null
        $text = if ($raw -is [array]) { ($raw | Out-String) } else { [string]$raw }
        if ($text -match '(v?\d+\.\d+\.\d+)') {
            $v = $Matches[1]
            if ($v -notlike 'v*') { $v = "v$v" }
            return $v
        }
    }
    return "v1.5.5"
}

function Get-ProxiedUrl([string]$Url) {
    if ($Direct) { return $Url }
    if ($Url -match '^https://(github\.com|api\.github\.com|raw\.githubusercontent\.com|codeload\.github\.com)/') {
        return "https://gh-proxy.com/$Url"
    }
    return $Url
}

function Invoke-Download([string]$Url, [string]$OutFile) {
    $final = Get-ProxiedUrl $Url
    Write-Host "Downloading $Url"
    if ($final -ne $Url) {
        Write-Host "  via $final"
    }
    $dir = Split-Path -Parent $OutFile
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    & curl.exe -fsSL --retry 3 --retry-delay 2 -o $OutFile $final
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutFile)) {
        throw "Download failed: $Url"
    }
}

function Get-ReleaseAssetNames {
    $api = "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    $url = Get-ProxiedUrl $api
    Write-Host "Resolving release $Repo@$Tag ..."
    $json = & curl.exe -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: duckdb-ui-start" $url
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "Could not fetch release metadata for $Repo@$Tag"
    }
    $release = $json | ConvertFrom-Json
    if (-not $release.assets) {
        throw "Release $Tag has no assets"
    }
    return @($release.assets | ForEach-Object { $_.name })
}

function Find-AssetName([string[]]$Names, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        $hit = $Names | Where-Object { $_ -like $pattern } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    throw "No release asset matching $($Patterns -join ' | '). Available: $($Names -join ', ')"
}

function Expand-UiAssets([string]$Tarball, [string]$Target) {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    $first = (& tar -tzf $Tarball | Select-Object -First 1)
    if ($first -like "ui-assets/*") {
        tar -xzf $Tarball -C $Target --strip-components=1
    } else {
        tar -xzf $Tarball -C $Target
    }
    $index = Join-Path $Target "index.html"
    if (-not (Test-Path -LiteralPath $index)) {
        throw "Extracted assets look incomplete (missing index.html) under $Target"
    }
}

function Install-ForkExtension([string]$ZipPath, [string]$DestDir, [string]$DestName) {
    if ($DestName -eq "ui.duckdb_extension") {
        throw "Refusing to install fork as official ui.duckdb_extension (signature clash with duckdb -ui)."
    }
    $stage = Join-Path $env:TEMP ("duckdb-ui-ext-stage-" + $PID)
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        tar -xf $ZipPath -C $stage
        $candidates = @(
            (Join-Path $stage "ui_offline.duckdb_extension"),
            (Join-Path $stage "ui-offline.duckdb_extension")
        )
        $found = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $found) {
            # Prefer any non-official stem if the zip only has a raw build name.
            $found = Get-ChildItem -LiteralPath $stage -Filter "*.duckdb_extension" -Recurse |
                Where-Object { $_.Name -ne "ui.duckdb_extension" } |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $found) {
            $found = Get-ChildItem -LiteralPath $stage -Filter "*.duckdb_extension" -Recurse |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $found) {
            throw "Zip did not contain a .duckdb_extension file: $ZipPath"
        }
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        $dest = Join-Path $DestDir $DestName
        Copy-Item -LiteralPath $found -Destination $dest -Force
        # Never touch official ui.duckdb_extension beside the fork binary.
        return $dest
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-LocalUiReady([string]$AssetsDir, [string]$ExtPath) {
    $index = Join-Path $AssetsDir "index.html"
    return (Test-Path -LiteralPath $index) -and (Test-Path -LiteralPath $ExtPath)
}

function Find-LegacyForkExtension([string]$AssetsWorkDir) {
    foreach ($name in @("ui_offline.duckdb_extension", "ui-offline.duckdb_extension")) {
        $p = Join-Path $AssetsWorkDir $name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Find-CachedExtZip([string]$Dir) {
    foreach ($filter in @(
            "ui_offline-*-windows_amd64.zip",
            "ui-offline-*-windows_amd64.zip",
            "ui_offline-*-windows_amd64.duckdb_extension",
            "ui-offline-*-windows_amd64.duckdb_extension"
        )) {
        $hit = Get-ChildItem -LiteralPath $Dir -Filter $filter -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($hit) { return $hit }
    }
    return $null
}

function Sync-ThemeOverlays([string]$DestAssets) {
    New-Item -ItemType Directory -Force -Path $DestAssets | Out-Null
    foreach ($dirName in @("theme", "fork")) {
        $src = Join-Path $PSScriptRoot $dirName
        if (-not (Test-Path -LiteralPath $src)) { continue }
        Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestAssets $_.Name) -Force
        }
        Write-Host "Synced fork overlays from $src"
    }
}

function Install-FromReleaseOrCache {
    param(
        [string]$DownloadDir,
        [string]$AssetsTgz,
        [bool]$ForceOnline
    )

    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

    $haveAssetsTgz = Test-Path -LiteralPath $AssetsTgz
    $cachedZip = Find-CachedExtZip $DownloadDir
    $needOnline = $ForceOnline -or (-not $haveAssetsTgz) -or (-not $cachedZip)

    if ($needOnline) {
        $names = Get-ReleaseAssetNames
        $assetsName = Find-AssetName $names @("ui-assets.tar.gz")
        $zipName = Find-AssetName $names @(
            "ui_offline-*-windows_amd64.zip",
            "ui-offline-*-windows_amd64.zip",
            "ui_offline-*-windows_amd64.duckdb_extension",
            "ui-*-windows_amd64.zip"
        )
        $extZip = Join-Path $DownloadDir $zipName
        $base = "https://github.com/$Repo/releases/download/$Tag"
        Invoke-Download "$base/$assetsName" $AssetsTgz
        Invoke-Download "$base/$zipName" $extZip
        return @{ AssetsTgz = $AssetsTgz; ExtZip = $extZip }
    }

    Write-Host "Using cached release artifacts under $DownloadDir (no online fetch)."
    return @{ AssetsTgz = $AssetsTgz; ExtZip = $cachedZip }
}

function Stop-ExistingUiServer {
    param([int]$Port = 4213)
    $pids = @()
    try {
        $pids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
    } catch {
        $pids = @()
    }
    if (-not $pids -or $pids.Count -eq 0) {
        $lines = netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING"
        foreach ($line in $lines) {
            if ($line.Line -match '(\d+)\s*$') {
                $pids += [int]$Matches[1]
            }
        }
        $pids = $pids | Select-Object -Unique
    }
    foreach ($procId in $pids) {
        if ($procId -le 0) { continue }
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -match '(?i)duckdb') {
            Write-Host "Stopping previous DuckDB UI server on port $Port (pid $procId)..."
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- main ---

$offlineSql = if ($AirGap) { "true" } else { "false" }
$sqlAssetsPath = "~/.duckdb/extension_data/ui/assets"

$resolvedVersion = Resolve-DuckDbVersion $DuckDB $DuckDBVersion
$extDir = Join-Path $env:USERPROFILE ".duckdb\extensions\$resolvedVersion\$Platform"
$extFile = Join-Path $extDir $ForkExtName

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $AssetsPath | Out-Null
New-Item -ItemType Directory -Force -Path $extDir | Out-Null

$downloadDir = Join-Path $WorkDir "download"
$assetsTgz = Join-Path $downloadDir "ui-assets.tar.gz"

# Migrate legacy install under extension_data/ui/ → extensions/{ver}/{platform}/
if (-not (Test-Path -LiteralPath $extFile)) {
    $legacy = Find-LegacyForkExtension $WorkDir
    if ($legacy) {
        Write-Host "Migrating legacy fork extension:"
        Write-Host "  from: $legacy"
        Write-Host "  to:   $extFile"
        Copy-Item -LiteralPath $legacy -Destination $extFile -Force
    }
}

$localReady = Test-LocalUiReady $AssetsPath $extFile

if ($Fetch -or -not $localReady) {
    if ($Fetch) {
        Write-Host "Fetch requested: refreshing from $Repo@$Tag ..."
    } else {
        Write-Host "Local UI incomplete; will install missing pieces."
        if (-not (Test-Path -LiteralPath (Join-Path $AssetsPath "index.html"))) {
            Write-Host "  missing: $AssetsPath\index.html"
        }
        if (-not (Test-Path -LiteralPath $extFile)) {
            Write-Host "  missing: $extFile"
        }
    }

    $pack = Install-FromReleaseOrCache -DownloadDir $downloadDir -AssetsTgz $assetsTgz -ForceOnline:$Fetch
    Write-Host "Installing UI assets -> $AssetsPath"
    Expand-UiAssets $pack.AssetsTgz $AssetsPath
    Write-Host "Installing fork extension as $ForkExtName -> $extDir"
    Write-Host "  (official duckdb -ui uses ui.duckdb_extension in the same folder; left untouched)"
    if ($pack.ExtZip -like "*.duckdb_extension") {
        Copy-Item -LiteralPath $pack.ExtZip -Destination $extFile -Force
    } else {
        $extFile = Install-ForkExtension $pack.ExtZip $extDir $ForkExtName
    }
} else {
    Write-Host "Local UI ready (no online fetch)."
    Write-Host "  assets:    $AssetsPath"
    Write-Host "  extension: $extFile"
    Write-Host "  tip: pass -Fetch to refresh from $Repo@$Tag"
}

Sync-ThemeOverlays $AssetsPath

if (-not (Test-LocalUiReady $AssetsPath $extFile)) {
    throw "UI still incomplete after install. assets=$AssetsPath ext=$extFile"
}

Write-Host ""
Write-Host "Ready:"
Write-Host "  assets:    $AssetsPath"
Write-Host "  extension: $extFile"
Write-Host "  (fork stem ui_offline — not official ui.duckdb_extension)"
Write-Host "  ui_offline=$offlineSql$(if ($AirGap) { ' (-AirGap)' } else { ' (local-first + miss→cache; CSP on)' })"
Write-Host ""

if ($NoStart) {
    $extSql = ($extFile -replace '\\', '/')
    Write-Host "NoStart set. Manual load:"
    Write-Host "  duckdb -unsigned"
    Write-Host "  LOAD '$extSql';"
    Write-Host "  -- or: LOAD ui_offline;"
    Write-Host "  SET ui_assets_path='$sqlAssetsPath';"
    Write-Host "  SET ui_offline=$offlineSql;"
    Write-Host "  CALL start_ui_server();"
    exit 0
}

$duckdbCmd = Get-Command $DuckDB -ErrorAction SilentlyContinue
if (-not $duckdbCmd) {
    throw "DuckDB CLI not found ('$DuckDB'). Install DuckDB v1.5.x and ensure it is on PATH."
}

# Avoid stacking multiple UI servers on 4213 — excess /localEvents clients hit the
# SSE wait cap and the page shows "Connection to DuckDB Lost" in a loop.
Stop-ExistingUiServer

$extSql = ($extFile -replace '\\', '/')
# -cmd runs SQL then keeps reading stdin (unlike -c/-s, which exit and stop the UI server).
$initSql = "LOAD '$extSql'; SET ui_assets_path='$sqlAssetsPath'; SET ui_offline=$offlineSql; CALL start_ui_server();"

Write-Host "Starting interactive DuckDB (leave this window open while using the UI)..."
Write-Host "  LOAD: $extFile"
Write-Host "  Open http://127.0.0.1:4213/  (use 127.0.0.1, not localhost)"
Write-Host "  $DuckDB -unsigned -cmd <init SQL>"
Write-Host ""

& $DuckDB -unsigned -cmd $initSql

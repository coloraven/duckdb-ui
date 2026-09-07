#Requires -Version 5.1
<#
.SYNOPSIS
  Start the coloraven/duckdb-ui offline fork (Windows). Local-first; fetch only when needed.

.DESCRIPTION
  Standalone — copy this script anywhere; it does not need the git repo.

  Default (no flags): if ui-offline.duckdb_extension and assets/index.html already
    exist under the work dir, just start DuckDB + UI. No GitHub download.

  Release pull (extension zip + ui-assets.tar.gz) happens only when:
    - local extension or static assets are missing, or
    - you pass -Fetch (force refresh from offline-latest).

  Runtime (extension): always local-first for static assets; missing files are
    filled from ui_remote_url and cached. Browser third-party calls are CSP-blocked.
    Pass -AirGap to SET ui_offline=true (never remote-fill assets; 503 on miss).

  Persists the fork binary as ui-offline.duckdb_extension (never overwrites the
  official ui.duckdb_extension). For LOAD, copies into a private temp folder as
  ui.duckdb_extension (DuckDB entrypoint = file stem).

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

    [switch]$Fetch,
    [switch]$AirGap,
    [switch]$NoStart,
    [switch]$Direct
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Persisted fork binary — must not collide with official ui.duckdb_extension.
$ForkExtName = "ui-offline.duckdb_extension"

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
    $stage = Join-Path $env:TEMP ("duckdb-ui-ext-stage-" + $PID)
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        tar -xf $ZipPath -C $stage
        $candidates = @(
            (Join-Path $stage "ui-offline.duckdb_extension"),
            (Join-Path $stage "ui.duckdb_extension")
        )
        $found = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
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
        # Never leave an official-named copy beside the fork binary.
        $pollute = Join-Path $DestDir "ui.duckdb_extension"
        if (Test-Path -LiteralPath $pollute) {
            Remove-Item -LiteralPath $pollute -Force
            Write-Host "Removed leftover ui.duckdb_extension from $DestDir (avoid official name collision)."
        }
        return $dest
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-TempUiLoadCopy([string]$ForkExtPath) {
    $loadDir = Join-Path $env:TEMP ("duckdb-ui-fork-load-" + $PID)
    New-Item -ItemType Directory -Force -Path $loadDir | Out-Null
    $loadExt = Join-Path $loadDir "ui.duckdb_extension"
    Copy-Item -LiteralPath $ForkExtPath -Destination $loadExt -Force
    return @{ Dir = $loadDir; Ext = $loadExt }
}

function Test-LocalUiReady([string]$AssetsDir, [string]$ExtPath) {
    $index = Join-Path $AssetsDir "index.html"
    return (Test-Path -LiteralPath $index) -and (Test-Path -LiteralPath $ExtPath)
}

function Find-CachedExtZip([string]$Dir) {
    $hit = Get-ChildItem -LiteralPath $Dir -Filter "ui-offline-*-windows_amd64.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ($hit) { return $hit }
    return Get-ChildItem -LiteralPath $Dir -Filter "ui-*-windows_amd64.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
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
            "ui-offline-*-windows_amd64.zip",
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

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $AssetsPath | Out-Null

$downloadDir = Join-Path $WorkDir "download"
$assetsTgz = Join-Path $downloadDir "ui-assets.tar.gz"
$extFile = Join-Path $WorkDir $ForkExtName

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
    Write-Host "Installing fork extension as $ForkExtName -> $WorkDir"
    $extFile = Install-ForkExtension $pack.ExtZip $WorkDir $ForkExtName
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
Write-Host "  extension: $extFile  (fork name; not official ui.duckdb_extension)"
Write-Host "  ui_offline=$offlineSql$(if ($AirGap) { ' (-AirGap)' } else { ' (local-first + miss→cache; CSP on)' })"
Write-Host ""

if ($NoStart) {
    Write-Host "NoStart set. To load manually, copy to a private temp folder as ui.duckdb_extension first:"
    Write-Host "  `$load = Join-Path `$env:TEMP 'duckdb-ui-fork-load'"
    Write-Host "  New-Item -ItemType Directory -Force -Path `$load | Out-Null"
    Write-Host "  Copy-Item '$extFile' (Join-Path `$load 'ui.duckdb_extension') -Force"
    Write-Host "  Set-Location `$load; duckdb -unsigned"
    Write-Host "  LOAD './ui.duckdb_extension';"
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

$loadCopy = New-TempUiLoadCopy $extFile
$loadExtSql = ($loadCopy.Ext -replace '\\', '/')

$initSql = @"
LOAD '$loadExtSql';
SET ui_assets_path='$sqlAssetsPath';
SET ui_offline=$offlineSql;
CALL start_ui_server();
"@
$initFile = Join-Path $env:TEMP ("duckdb-ui-init-{0}.sql" -f $PID)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($initFile, $initSql, $utf8NoBom)

Write-Host "Starting interactive DuckDB (leave this window open while using the UI)..."
Write-Host "  persisted: $extFile"
Write-Host "  LOAD from: $($loadCopy.Ext)  (temp copy; stem must be ui)"
Write-Host "  Open http://127.0.0.1:4213/  (use 127.0.0.1, not localhost)"
Write-Host "  $DuckDB -unsigned -init $initFile"
Write-Host ""

Push-Location -LiteralPath $loadCopy.Dir
try {
    # -init runs the SQL then keeps the session open (unlike -c, which exits and stops the server).
    & $DuckDB -unsigned -init $initFile
} finally {
    Pop-Location
    Remove-Item -LiteralPath $initFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $loadCopy.Dir -Recurse -Force -ErrorAction SilentlyContinue
}

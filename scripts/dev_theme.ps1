#Requires -Version 5.1
<#
.SYNOPSIS
  Sync theme / static overlays into the install assets dir and preview the UI.

.DESCRIPTION
  Does NOT build the C++ extension. Uses the already-installed fork binary
  (ui-offline.duckdb_extension from start_ui.ps1).

  Flow:
    1) Copy scripts/theme/* and scripts/fork/* → AssetsPath (same as start_ui.ps1)
    2) Start duckdb -unsigned with that extension (temp copy as ui.duckdb_extension)
    3) Open the UI in the browser

  Edit scripts/theme/*.css or scripts/fork/*, re-run this script (or -CssOnly
  + hard-refresh if the server is already up).

.EXAMPLE
  .\scripts\dev_theme.ps1
  .\scripts\dev_theme.ps1 -CssOnly
  .\scripts\dev_theme.ps1 -EnsureAssets
  .\scripts\dev_theme.ps1 -AirGap
#>
param(
    [string]$AssetsPath = $(Join-Path $env:USERPROFILE ".duckdb\extension_data\ui\assets"),
    [string]$WorkDir = $(Join-Path $env:USERPROFILE ".duckdb\extension_data\ui"),
    [string]$DuckDB = "duckdb",
    [string]$OpenUrl = "http://127.0.0.1:4213/",

    # Only sync theme files; do not start DuckDB (hard-refresh an already-running UI).
    [switch]$CssOnly,

    # If assets/index.html is missing, run start_ui.ps1 -NoStart first.
    [switch]$EnsureAssets,

    [switch]$NoStart,
    [switch]$NoBrowser,
    [switch]$AirGap,
    [switch]$Direct
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ForkExtName = "ui-offline.duckdb_extension"
$ThemeSrcDir = Join-Path $PSScriptRoot "theme"
$ForkSrcDir = Join-Path $PSScriptRoot "fork"
$InstallScript = Join-Path $PSScriptRoot "start_ui.ps1"

function Sync-ThemeAssets([string]$DestAssets) {
    New-Item -ItemType Directory -Force -Path $DestAssets | Out-Null
    $copied = @()
    foreach ($srcDir in @($ThemeSrcDir, $ForkSrcDir)) {
        if (-not (Test-Path -LiteralPath $srcDir)) { continue }
        Get-ChildItem -LiteralPath $srcDir -File | ForEach-Object {
            $dest = Join-Path $DestAssets $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            $copied += $_.Name
        }
    }
    if ($copied.Count -eq 0) {
        throw "No fork overlay files found under theme/ or fork/"
    }
    Write-Host "Synced theme / fork overlays -> $DestAssets"
    foreach ($name in $copied) {
        Write-Host "  $name"
    }

    $cssPath = Join-Path $DestAssets "dd-ui-fork-theme-local.css"
    $jsPath = Join-Path $DestAssets "dd-ui-fork-overlays.js"
    $cssBust = "1"
    $jsBust = "1"
    if (Test-Path -LiteralPath $cssPath) {
        $cssBust = (Get-FileHash -LiteralPath $cssPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
    }
    if (Test-Path -LiteralPath $jsPath) {
        $jsBust = (Get-FileHash -LiteralPath $jsPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
    }
    $linkTag = "<link rel=`"stylesheet`" href=`"/dd-ui-fork-theme-local.css?v=$cssBust`" data-dd-ui-fork-theme-local=`"1`" />"
    $scriptTag = "<script src=`"/dd-ui-fork-overlays.js?v=$jsBust`" defer data-dd-ui-fork-overlays=`"1`"></script>"
    $htmlFiles = @("index.html")
    Get-ChildItem -LiteralPath $DestAssets -Filter "*.html" -File -ErrorAction SilentlyContinue |
        ForEach-Object { $htmlFiles += $_.Name }
    $htmlFiles = $htmlFiles | Select-Object -Unique
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    foreach ($name in $htmlFiles) {
        $htmlPath = Join-Path $DestAssets $name
        if (-not (Test-Path -LiteralPath $htmlPath)) { continue }
        $html = [System.IO.File]::ReadAllText($htmlPath)
        $updated = $false

        if ($html -match 'dd-ui-fork-theme-local\.css') {
            $next = [regex]::Replace($html, '<link[^>]*dd-ui-fork-theme-local\.css[^>]*/?>', $linkTag, 1)
            if ($next -ne $html) { $html = $next; $updated = $true }
        } else {
            if ($html -match '(?i)</head>') {
                $html = [regex]::Replace($html, '(?i)</head>', ("`n$linkTag`n</head>"), 1)
            } elseif ($html -match '(?i)</body>') {
                $html = [regex]::Replace($html, '(?i)</body>', ("`n$linkTag`n</body>"), 1)
            } else {
                $html = $html + "`n$linkTag`n"
            }
            $updated = $true
        }

        if ($html -match 'dd-ui-fork-overlays\.js') {
            $next = [regex]::Replace($html, '<script[^>]*dd-ui-fork-overlays\.js[^>]*>\s*</script>', $scriptTag, 1)
            if ($next -ne $html) { $html = $next; $updated = $true }
        } else {
            if ($html -match '(?i)</head>') {
                $html = [regex]::Replace($html, '(?i)</head>', ("`n$scriptTag`n</head>"), 1)
            } elseif ($html -match '(?i)</body>') {
                $html = [regex]::Replace($html, '(?i)</body>', ("`n$scriptTag`n</body>"), 1)
            } else {
                $html = $html + "`n$scriptTag`n"
            }
            $updated = $true
        }

        if ($updated) {
            [System.IO.File]::WriteAllText($htmlPath, $html, $utf8NoBom)
            Write-Host "  patched $name (theme css + overlays js)"
        }
    }
}

function New-TempUiLoadCopy([string]$ForkExtPath) {
    $loadDir = Join-Path $env:TEMP ("duckdb-ui-fork-load-" + $PID)
    New-Item -ItemType Directory -Force -Path $loadDir | Out-Null
    $loadExt = Join-Path $loadDir "ui.duckdb_extension"
    Copy-Item -LiteralPath $ForkExtPath -Destination $loadExt -Force
    return @{ Dir = $loadDir; Ext = $loadExt }
}

function Ensure-UiAssets {
    $index = Join-Path $AssetsPath "index.html"
    if (Test-Path -LiteralPath $index) {
        Write-Host "Assets OK: $index"
        return
    }
    if (-not $EnsureAssets) {
        throw @"
UI assets missing under $AssetsPath
Run once:
  powershell -ExecutionPolicy Bypass -File '$InstallScript' -NoStart
Or re-run with -EnsureAssets
"@
    }
    if (-not (Test-Path -LiteralPath $InstallScript)) {
        throw "start_ui.ps1 not found: $InstallScript"
    }
    Write-Host "Assets missing; invoking start_ui.ps1 -NoStart ..."
    $installArgs = @{
        AssetsPath = $AssetsPath
        WorkDir    = $WorkDir
        DuckDB     = $DuckDB
        NoStart    = $true
    }
    if ($AirGap) { $installArgs.AirGap = $true }
    if ($Direct) { $installArgs.Direct = $true }
    & $InstallScript @installArgs
    if (-not (Test-Path -LiteralPath $index)) {
        throw "Assets still missing after start_ui.ps1"
    }
}

# --- main ---

$offlineSql = if ($AirGap) { "true" } else { "false" }
$sqlAssetsPath = "~/.duckdb/extension_data/ui/assets"
$extFile = Join-Path $WorkDir $ForkExtName

Write-Host "Assets:  $AssetsPath"
Write-Host "WorkDir: $WorkDir"
Write-Host "(extension is not rebuilt — using installed $ForkExtName)"
Write-Host ""

Ensure-UiAssets
Sync-ThemeAssets $AssetsPath

Write-Host ""
Write-Host "Ready:"
Write-Host "  theme:     $(Join-Path $AssetsPath 'dd-ui-fork-theme-local.css')"
Write-Host "  extension: $extFile"
Write-Host "  ui_offline=$offlineSql$(if ($AirGap) { ' (-AirGap)' } else { '' })"
Write-Host ""

if ($CssOnly) {
    Write-Host "CssOnly: overlays synced. Hard-refresh $OpenUrl (Ctrl+F5) if the UI is already open."
    exit 0
}

if ($NoStart) {
    Write-Host "NoStart set; not launching DuckDB."
    exit 0
}

if (-not (Test-Path -LiteralPath $extFile)) {
    throw @"
Fork extension missing: $extFile
Install release artifacts first (does not compile locally):
  powershell -ExecutionPolicy Bypass -File '$InstallScript' -NoStart
"@
}

$duckdbCmd = Get-Command $DuckDB -ErrorAction SilentlyContinue
if (-not $duckdbCmd) {
    throw "DuckDB CLI not found ('$DuckDB'). Install DuckDB v1.5.x and ensure it is on PATH."
}

function Stop-ExistingUiServer {
    param([int]$Port = 4213)
    $pids = @()
    try {
        $pids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
    } catch { }
    if (-not $pids -or $pids.Count -eq 0) {
        foreach ($line in (netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING")) {
            if ($line.Line -match '(\d+)\s*$') { $pids += [int]$Matches[1] }
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
Stop-ExistingUiServer

$loadCopy = New-TempUiLoadCopy $extFile
$loadExtSql = ($loadCopy.Ext -replace '\\', '/')

$initSql = @"
LOAD '$loadExtSql';
SET ui_assets_path='$sqlAssetsPath';
SET ui_offline=$offlineSql;
CALL start_ui_server();
"@
$initFile = Join-Path $env:TEMP ("duckdb-ui-theme-init-{0}.sql" -f $PID)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($initFile, $initSql, $utf8NoBom)

if (-not $NoBrowser) {
    Start-Job -ScriptBlock {
        param($Url)
        Start-Sleep -Seconds 2
        Start-Process $Url
    } -ArgumentList $OpenUrl | Out-Null
    Write-Host "Browser will open $OpenUrl in ~2s"
}

Write-Host "Starting interactive DuckDB (leave this window open while previewing)..."
Write-Host "  $DuckDB -unsigned -init $initFile"
Write-Host "  LOAD from: $($loadCopy.Ext)"
Write-Host "  Use http://127.0.0.1:4213/ (not localhost) — Origin must match."
Write-Host ""

Push-Location -LiteralPath $loadCopy.Dir
try {
    & $DuckDB -unsigned -init $initFile
} finally {
    Pop-Location
    Remove-Item -LiteralPath $initFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $loadCopy.Dir -Recurse -Force -ErrorAction SilentlyContinue
}

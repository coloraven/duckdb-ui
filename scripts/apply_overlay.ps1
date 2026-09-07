#Requires -Version 5.1
<#
.SYNOPSIS
  Apply this fork's overlay onto an upstream duckdb/duckdb-ui checkout.
.EXAMPLE
  .\scripts\apply_overlay.ps1 -Target C:\src\duckdb-ui-upstream
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Overlay = Join-Path $Root "overlay"
$Target = (Resolve-Path -LiteralPath $Target).Path

if (-not (Test-Path -LiteralPath (Join-Path $Target "CMakeLists.txt"))) {
    throw "Target does not look like duckdb/duckdb-ui: $Target"
}
if (-not (Test-Path -LiteralPath $Overlay)) {
    throw "overlay missing: $Overlay"
}

$applied = 0
Get-ChildItem -LiteralPath $Overlay -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Overlay.Length).TrimStart("\", "/")
    if ($rel -eq "OVERLAY.md" -or $rel -eq "README.md") { return }
    $dest = Join-Path $Target $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    Write-Host "applied $rel"
    $script:applied++
}
if ($applied -lt 1) {
    throw "no overlay files applied from $Overlay"
}
foreach ($needle in @("ui_assets_path", "ui_offline", "ui_local_host", "theme_inject.cpp")) {
    $hit = Get-ChildItem -LiteralPath (Join-Path $Target "src") -Recurse -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $needle -SimpleMatch -List |
        Select-Object -First 1
    $cmakeHit = Select-String -LiteralPath (Join-Path $Target "CMakeLists.txt") -Pattern $needle -SimpleMatch -ErrorAction SilentlyContinue
    if (-not $hit -and -not $cmakeHit) {
        throw "overlay verify failed — '$needle' not found under $Target after apply"
    }
}
Write-Host "Overlay applied ($applied files) onto $Target"

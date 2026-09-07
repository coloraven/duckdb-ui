#Requires -Version 5.1
# Compatibility shim — this script was renamed to start_ui.ps1.
# Prefer: scripts/start_ui.ps1
$ErrorActionPreference = "Stop"
$target = Join-Path $PSScriptRoot "start_ui.ps1"
if (-not (Test-Path -LiteralPath $target)) {
    throw "Renamed script missing: $target"
}
Write-Warning "install_ui_assets.ps1 was renamed to start_ui.ps1; forwarding..."
& $target @args
exit $LASTEXITCODE

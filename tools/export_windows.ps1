param([string]$Godot = 'godot_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    $Godot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe'
}
& (Join-Path $PSScriptRoot 'check.ps1') -Godot $Godot
if ($LASTEXITCODE -ne 0) { exit 1 }
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath 'build') | Out-Null
$lines = & $Godot --headless --path $projectPath --export-release 'Windows Desktop' (Join-Path $projectPath 'build\TheWaterhouse.exe') 2>&1
$code = $LASTEXITCODE
$lines | ForEach-Object { Write-Host "$_" }
if ($code -ne 0 -or @($lines | Where-Object { "$_" -match '(SCRIPT ERROR|^ERROR:|Parse Error)' }).Count -gt 0) { exit 1 }
Write-Host 'Exported build\TheWaterhouse.exe + TheWaterhouse.pck'
& $Godot --headless --path $projectPath --script (Join-Path $PSScriptRoot 'ship_metadata.gd')
if ($LASTEXITCODE -ne 0) { exit 1 }
$packageFiles = @('TheWaterhouse.exe', 'TheWaterhouse.pck', 'PLAY.txt', 'GODOT_LICENSES.txt', 'AUDIO_CREDITS.txt') | ForEach-Object { Join-Path $projectPath "build\$_" }
& $Godot --headless --audio-driver WASAPI --path (Join-Path $projectPath 'build') --main-pack (Join-Path $projectPath 'build\TheWaterhouse.pck') --script (Join-Path $projectPath 'tests\package_audio_test.gd')
if ($LASTEXITCODE -ne 0) { exit 1 }
Compress-Archive -LiteralPath $packageFiles -DestinationPath (Join-Path $projectPath 'build\TheWaterhouse-Windows-x64.zip') -CompressionLevel Optimal -Force
Write-Host 'Packaged build\TheWaterhouse-Windows-x64.zip'

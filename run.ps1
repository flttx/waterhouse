param([switch]$Editor, [switch]$Play)
$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$godotCommand = Get-Command godot.exe -ErrorAction SilentlyContinue
if (-not $godotCommand) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot.exe'
    if (Test-Path -LiteralPath $fallback) { $godotBinary = $fallback }
    else { throw '找不到 Godot 4，请安装后从编辑器导入 project.godot。' }
} else { $godotBinary = $godotCommand.Source }
if ($Editor) { & $godotBinary --editor --path $projectPath }
elseif ($Play) { & $godotBinary --path $projectPath -- --play }
else { & $godotBinary --path $projectPath }

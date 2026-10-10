param([string]$Godot = 'godot_console.exe', [string]$AudioDriver = 'WASAPI')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    $Godot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\godot_console.exe'
}
if (-not (Test-Path -LiteralPath $Godot) -and -not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    throw 'Godot console executable not found.'
}
$failed = $false
function Invoke-CheckedGodot([string]$Label, [string[]]$Arguments) {
    $lines = & $Godot --headless --audio-driver $AudioDriver --path $projectPath @Arguments 2>&1
    $code = $LASTEXITCODE
    $errors = @($lines | Where-Object { "$_" -match '(SCRIPT ERROR|^ERROR:|Parse Error|Shader compilation failed)' })
    if ($code -ne 0 -or $errors.Count -gt 0) {
        Write-Output "FAIL $Label (exit $code)"
        $lines | ForEach-Object { Write-Output "$_" }
        $script:failed = $true
    } else {
        Write-Output "PASS $Label"
        $lines | Where-Object { "$_" -match '(GAME FLOW:|CREATURE TESTS:|WORLD CREATURE|checks|_FAILURES=|_PHYSICS_STEPS=)' } | Select-Object -Last 4 | ForEach-Object { Write-Output "  $_" }
    }
}
Invoke-CheckedGodot 'asset import' @('--editor', '--quit')
$scripts = Get-ChildItem -LiteralPath (Join-Path $projectPath 'scripts') -Filter '*.gd'
foreach ($scriptFile in $scripts) {
    Invoke-CheckedGodot "parse $($scriptFile.Name)" @('--check-only', '--script', $scriptFile.FullName)
}
foreach ($testName in @('player_physics', 'creature_test', 'game_flow', 'traversal_test', 'creature_world_test', 'stalker_test', 'multi_creature_test', 'map_ui_test', 'navigation_test', 'expansion_game_test', 'hazard_test', 'all_creatures_test', 'full_facility_traversal', 'music_test', 'audio_test', 'audio_routing_test', 'encounter_test', 'visual_polish_test', 'tail_clearance_test')) {
    $testFile = Join-Path $projectPath "tests\$testName.gd"
    if (Test-Path -LiteralPath $testFile) { Invoke-CheckedGodot $testName @('--script', $testFile) }
    else { Write-Output "FAIL missing regression $testName"; $failed = $true }
}
Invoke-CheckedGodot 'giants in actual world' @('--script', (Join-Path $projectPath 'tests\giants_test.gd'), '--', '--actual')
Invoke-CheckedGodot 'new wings traversal' @('--script', (Join-Path $projectPath 'tests\expansion_world_test.gd'))
Invoke-CheckedGodot 'outer facility traversal' @('--script', (Join-Path $projectPath 'tests\expansion_world_test.gd'), '--', 'outer')
Invoke-CheckedGodot 'runtime smoke (300 frames)' @('--quit-after', '300', '--', '--play')
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCommand) {
    & $pythonCommand.Source (Join-Path $PSScriptRoot 'lint_sources.py')
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    & $pythonCommand.Source (Join-Path $PSScriptRoot 'check_audio_assets.py')
    if ($LASTEXITCODE -ne 0) { $failed = $true }
} else {
    Write-Output 'FAIL source lint: Python 3 is required for development checks'
    $failed = $true
}
if (Test-Path -LiteralPath (Join-Path $projectPath '.git')) {
    git -C $projectPath diff --check
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
Write-Output 'PASS all available checks'

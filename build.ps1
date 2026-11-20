param(
    [string]$ToolDirectory = "$env:USERPROFILE\bin\rbxtools"
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $lune = Join-Path $ToolDirectory 'lune.exe'
    $rojo = Join-Path $ToolDirectory 'rojo.exe'
    & node art/generate-import.cjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Original mesh import bundle is stale' }
    & node art/import/verify-import.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Original mesh geometry verification failed' }
    foreach ($test in @('verify-progression.luau', 'verify-gameplay.luau', 'verify-world.luau', 'verify-expedition.luau', 'verify-coop.luau', 'verify-combat.luau', 'verify-ui.luau', 'verify-festival.luau', 'verify-gesture.luau', 'verify-npc.luau', 'verify-mesh.luau')) {
        & $lune run $test
        if ($LASTEXITCODE -ne 0) { throw "Verification failed in $test" }
    }
    & $rojo build default.project.json --output Aether-Isles.rbxl
    if ($LASTEXITCODE -ne 0) { throw 'Place build failed' }
    & $lune run verify.luau
    if ($LASTEXITCODE -ne 0) { throw 'Packaged source verification failed' }
} finally {
    Pop-Location
}

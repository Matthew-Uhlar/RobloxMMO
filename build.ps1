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
    foreach ($test in @('verify-progression.luau', 'verify-gameplay.luau', 'verify-world.luau', 'verify-expedition.luau', 'verify-coop.luau', 'verify-combat.luau', 'verify-ui.luau', 'verify-festival.luau', 'verify-gesture.luau', 'verify-npc.luau', 'verify-mesh.luau', 'verify-skills.luau', 'verify-garden.luau', 'verify-endgame.luau', 'verify-workers.luau', 'verify-pets.luau', 'verify-dungeon-classes.luau', 'verify-prayer.luau', 'verify-trails.luau', 'verify-slayer-tasks.luau', 'verify-logs.luau', 'verify-minigames.luau', 'verify-crafting.luau', 'verify-dungeon-master.luau', 'verify-exploration.luau', 'verify-bosses.luau', 'verify-held.luau', 'verify-home.luau', 'verify-signs.luau', 'verify-regions.luau', 'verify-features.luau', 'verify-map.luau', 'verify-systems.luau', 'verify-hud.luau', 'verify-lighting.luau', 'verify-council.luau', 'verify-beaconry.luau', 'verify-contests.luau', 'verify-raid.luau', 'verify-qol.luau', 'verify-strike.luau', 'verify-buildings.luau')) {
        $out = & $lune run $test 2>&1
        $code = $LASTEXITCODE
        $out | ForEach-Object { Write-Output $_ }
        if ($code -ne 0) { throw "Verification failed in $test" }
        # A suite that yields forever is ended by Lune with exit 0; require its final sentinel.
        if (-not ($out | Where-Object { "$_" -ceq "SUITE-END $test" })) { throw "Verification stopped early in $test" }
    }
    & $rojo build default.project.json --output Aether-Isles.rbxl
    if ($LASTEXITCODE -ne 0) { throw 'Place build failed' }
    & $lune run verify.luau
    if ($LASTEXITCODE -ne 0) { throw 'Packaged source verification failed' }
} finally {
    Pop-Location
}

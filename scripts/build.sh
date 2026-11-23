#!/usr/bin/env bash
# Linux/macOS equivalent of build.ps1: run every headless suite, build the place, verify packaging.
set -euo pipefail
cd "$(dirname "$0")/.."
node art/import/verify-import.cjs
for test in verify-progression.luau verify-gameplay.luau verify-world.luau verify-expedition.luau verify-coop.luau verify-combat.luau verify-ui.luau verify-festival.luau verify-gesture.luau verify-npc.luau verify-mesh.luau verify-skills.luau verify-garden.luau verify-endgame.luau verify-workers.luau verify-pets.luau verify-dungeon-classes.luau verify-prayer.luau verify-trails.luau verify-slayer-tasks.luau verify-logs.luau verify-minigames.luau verify-crafting.luau verify-dungeon-master.luau verify-exploration.luau verify-bosses.luau verify-held.luau verify-home.luau verify-signs.luau verify-regions.luau verify-features.luau verify-map.luau verify-systems.luau verify-hud.luau verify-lighting.luau verify-council.luau verify-beaconry.luau verify-raid.luau; do
  [ -f "$test" ] || continue
  echo "== $test"
  out=$(lune run "$test" 2>&1) || { echo "$out"; exit 1; }
  echo "$out"
  # A suite that yields forever is ended by Lune with exit 0; require its final sentinel.
  echo "$out" | grep -q "^SUITE-END $test$" || { echo "FAIL: $test stopped before its end"; exit 1; }
done
rojo build default.project.json --output Aether-Isles.rbxl
lune run verify.luau

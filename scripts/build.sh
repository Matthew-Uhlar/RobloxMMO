#!/usr/bin/env bash
# Linux/macOS equivalent of build.ps1: run every headless suite, build the place, verify packaging.
set -euo pipefail
cd "$(dirname "$0")/.."
node art/import/verify-import.cjs
for test in verify-progression.luau verify-gameplay.luau verify-world.luau verify-expedition.luau verify-coop.luau verify-combat.luau verify-ui.luau verify-festival.luau verify-gesture.luau verify-npc.luau; do
  [ -f "$test" ] || continue
  echo "== $test"; lune run "$test"
done
rojo build default.project.json --output Aether-Isles.rbxl
lune run verify.luau

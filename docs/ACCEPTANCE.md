# Acceptance review against the original goal

Goal (paraphrased): an original Roblox game with OSRS- and Hypixel SkyBlock-style mechanics, the same skill intricacy and deep progression; well-developed menus and good-looking meshes; built with multiple teams for quality control while keeping the vision.

Status key: **Met (headless)** — implemented and covered by automated headless tests; **Needs live check** — requires Roblox Studio, devices or a published place, which this repository's automation cannot provide.

| # | Requirement | Evidence in this repository | Status |
|---|---|---|---|
| 1 | OSRS-style skills, 1–99 with the real XP curve | `shared/GameData.lua` XP table (L99 = 13,034,431, 200M cap), 12 skills; `verify-progression.luau` landmark checks | Met (headless) |
| 2 | Tiered gathering with level/tool gates | 26 resource tiers across Mining/Woodcutting/Fishing/Farming, tool tiers, fortune, node regrowth; nodes for every tier in `world.server.lua` | Met (headless) |
| 3 | Production chains and gear progression | Six metal tiers (ingots, swords, 4-piece sets with set bonuses, tools), Cooking ladder, ten potions, enchantments; 96 recipes gated by level and collection tier | Met (headless) |
| 4 | SkyBlock stat system and damage model | Stat sheet (Health…Pet Luck), skill-level stat rewards, SkyBlock damage/defense/crit formulas in `shared/Progression.lua` | Met (headless) |
| 5 | Collections, bestiary, accessories, pets | Nine-tier collections unlocking recipes; bestiary milestones; accessories with Magical Power; levelling pets | Met (headless) |
| 6 | Combat and slayers | 13 real-time creatures, three four-tier slayer lines with bosses, nine sea creatures from fishing | Met (headless); combat feel needs live check |
| 7 | Dungeons / raids | Observatory Floors I–V, cumulative mechanics, telegraphed bosses, S+–D grading and scaled chests | Met (headless); encounter tuning needs live check |
| 8 | Quests and achievement diaries | 8 guild contracts + 13 quests with Quest Points and XP lamps; diaries for seven regions | Met (headless) |
| 9 | Economy (Grand Exchange / Bazaar / Auction House) | Priced commodity asks, standing buy orders, gear auctions, bank; crash-safe receipts, bounded keys (≤ 480 KB worst case; auction price history in its own key), request budget | Met (headless); live cross-server economy needs live check |
| 10 | Private islands, minions/workers, building | Home islands, 7-tier workers with offline accrual, Builder's Terrace hotspots, free-form placement of 27 props | Met (headless) |
| 11 | Co-op / Group Ironman | Crews with lifecycle, Homestead levels, shared workers, Ironman isolation | Met (headless); multi-client play needs live check |
| 12 | Seasonal events / calendar | Global Skyward Calendar with 13 timed events/year and vendor | Met (headless) |
| 13 | Well-developed menus | Six-tab atlas covering every system; layout-emulator renders in `docs/screenshots/` with three polish passes; 3,200+ UI smoke checks | Met (headless); real-device appearance needs live check |
| 14 | Good-looking meshes | 46 original low-poly shapes, tintable icons for all 175 items, creature/world builds, bounded proxies for low-end devices | Met (headless); in-engine look needs live check |
| 15 | Multiple teams with QC that keeps the vision | Contract-driven teams (`docs/DEPTH-CONTRACT.md`), four independent reviews, 47 findings fixed with regression tests | Met |
| 16 | Original IP | All names, places, creatures and art are original to Aether Isles | Met |
| 18 | Owner feedback after first publish (bigger islands, lighting, custom meshes, menus, swing/interact animations, more functionality) | Waves 4–6 in `PROJECT-STATUS.md`; world/mesh/UI/gesture/NPC suites | Met (headless); needs live check after the next publish |
| 17 | Playable on Roblox | Place builds and all 14 scripts compile (`verify.luau`) | **Needs live check:** Studio playtest, publish, version confirmation |

## Live acceptance checklist (owner)

1. Open `Aether-Isles.rbxl` (from `./scripts/build.sh` or CI artifact) in Studio; play-test solo: gather → craft → equip → fight → slayer → dungeon floor I.
2. Start a 2-player local server: trade on the Bazaar/Auction House, form a crew, deposit/withdraw, rejoin.
3. Device emulator at phone landscape: open every atlas tab.
4. Merge to `main`; confirm the publish workflow's receipt and join the live place to verify the version.

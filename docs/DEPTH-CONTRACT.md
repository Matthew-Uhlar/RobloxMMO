# Depth update — team interface contract

This document is the single source of truth for how the parallel teams' work fits together in the **Depth** update (OSRS-style 1–99 skills and tiered content, SkyBlock-style stats/gear/collections/accessories/pets/slayers, real-time combat). Shared rules and data live in two ModuleScripts that every team consumes but **no team edits without the lead's approval**:

| Module | File | Roblox location |
|---|---|---|
| `AetherData` | `shared/GameData.lua` | `ReplicatedStorage.AetherData` |
| `AetherProgression` | `shared/Progression.lua` | `ReplicatedStorage.AetherProgression` |

Progression requires `AetherData` via `script.Parent`. In Lune tests, load both with `luau.load` and call `Progression.useData(Data)` (see `verify-progression.luau`). If a team needs a data/rule change, write it in the final report; the lead integrates it.

Vision constraints (all teams): every name, creature, place, item and visual is **original to Aether Isles** — mechanics are inspired by OSRS and SkyBlock, never their names, characters or art. Server is authoritative; never trust client numbers. Menus must look polished (existing palette, rounded panels, item thumbnails, readable on phone landscape). Keep existing features and tests working.

## 1. Profile schema additions (owned by Adventure / `server.server.lua`)

All optional; `open()` migrates defaults for older saves.

```
p.equipment   = {weapon=itemId, helmet=, chest=, legs=, boots=}   -- tools are auto-best, not equipped
p.enchants    = {[itemId] = {[enchantId] = level}}
p.accessoryBag= {itemId, ...}                                     -- unique, capacity Progression.accessorySlots
p.pets        = {{id=petId, level=1, xp=0}, ...}; p.activePet = index | nil
p.buffs       = {[consumableId] = {expires=os.time()+duration, stats={...}}}
p.bestiary    = {[monsterId] = kills}
p.slayerXp    = {Bramble=0, Gloom=0, Tempest=0}
p.slayerQuest = {line=, tier=, progress=, needed=, bossReady=bool} | nil
p.levelRewards= {[skill] = highestLevelRewarded}
p.collectionRewards = {[itemId] = highestTierRewarded}
```

Skill levels everywhere come from `Progression.levelForXp` (OSRS curve, 1–99). The old `1+floor(sqrt(xp/40))` curve is retired; tests asserting old thresholds are updated to the new curve.

## 2. Client → server verbs (existing `ReplicatedStorage.IsleAction` RemoteFunction `(verb, item)`)

All existing verbs keep working. New/extended verbs (item is always a string ≤ 64 chars):

| verb | item | effect |
|---|---|---|
| `craft` | recipe id from `Data.Recipes` **or** a legacy recipe | `Progression.canCraft`, spend, award XP to `recipe.skill` |
| `equip` | item id | sets `p.equipment[def.slot]` if owned and requirements met |
| `unequip` | slot name | clears slot |
| `consume` | consumable id (food/potion/feast) | food heals (`heal`, honours `recovery`), buffs set `p.buffs[id]` |
| `accessory` | item id | toggles membership in `p.accessoryBag` |
| `petSummon` | `"0"` (dismiss) or pet index `"1".."n"` | sets `p.activePet` |
| `petAdopt` | pet item id (e.g. `EmberfoxPet`) | consumes the pet item, appends to `p.pets` |
| `enchantItem` | `"itemId:EnchantId"` | applies next level; level gate `Data.enchantSkillLevel`, cost `Data.enchantCost`, XP `Data.enchantXp` |
| `sell` | item id or nil | sells an item stack at `Data.Items[id].value` (nil keeps legacy behaviour: the four basic resources) |
| `slayerBegin` | `"Line:tier"` e.g. `"Bramble:1"` | requires Combat level & coins (`tiers[t].cost`), creates `p.slayerQuest` |
| `slayerAbandon` | nil | clears quest, no refund |

Gather prompts (world): `IsleAction="gather"`, `IsleItem=<resource id from Data.ResourceTiers>`, optional `IsleRegion=<region id>`. Server uses `Progression.harvest` (level + tool-tier gate, fortune) and keeps legacy bonuses (Skyreach rich seam +1, festival +1, legacy pickaxe yields).

## 3. Server → client snapshot (`IsleUpdate` / RemoteFunction return)

Existing fields unchanged; `levels` now uses the new curve. New key `depth`:

```
depth = {
  skills = {[skill] = {level, xp, floor, ceiling, fraction, maxed}},
  totalLevel = n, skillAverage = n,
  stats = <Progression.computeStats result: health, defense, strength, critChance, critDamage, speed,
           intelligence, miningFortune, ..., damage, combatBonus, magicalPower, effectiveHealth, activeSet, weapon>,
  equipment = {[slot] = itemId},
  tools = {Mining=itemId|nil, Woodcutting=..., Fishing=..., Farming=...},   -- best owned tool per skill
  accessoryBag = {itemId...}, activeAccessories = {itemId...}, accessorySlots = n,
  pets = {{id, level, xp, next, active}},
  buffs = {[id] = {remaining=seconds, stats}},
  collections = {[itemId] = {count, tier, nextAt|nil}},
  bestiary = {[monsterId] = kills},
  slayer = {lines = {[line] = {xp, level, nextAt|nil}}, quest = p.slayerQuest | nil},
  enchants = {[itemId] = {[enchantId] = level}},
  regions = {{id, name, unlocked, requirement}},
}
```

Static definitions (names, colours, recipes, monsters…) are read by the client directly from `ReplicatedStorage.AetherData`.

## 4. Server ↔ server bridge (owned by Adventure, consumed by Combat)

`ServerStorage.IsleBridge` — **BindableFunction** `Invoke(op, player, payload)`:

| op | payload | returns |
|---|---|---|
| `"stats"` | nil | `{stats=<computeStats>, combatLevel=n, ironman=bool}` or `nil` if no live profile |
| `"kill"` | `{monster=monsterId}` | grants monster XP (Combat), coins, rolled drops (Magic Find / Pet Luck via `Progression.rollDrops`), bestiary +1, pet XP, slayer progress (if `monster.slayer == quest.line`, progress += monster.xp). Fires a snapshot with a message. Returns `{drops={[id]=n}, bossReady=bool}` |
| `"slayerBoss"` | `{result="win"|"fail"}` | win: grant `tiers[t].xp` slayer XP, roll tier drops, clear quest; fail: clear quest. Returns `{ok=true, drops=...}`, or `{ok=false, reason}` when the lease lapsed or the quest is invalid (Combat re-arms the boss after 5 s) |
| `"dungeon"` | nil | `{level=<Dungeoneering level>, ironman=bool}` (floor gating) |
| `"damage"` | `{amount=raw}` | applies `Progression.damageTaken(raw, stats.defense)` to the player's humanoid; returns damage applied |

Adventure also sets player attribute `SlayerBossReady = "Line:tier"` (or `""`) whenever a quest's boss becomes ready/cleared. Combat watches it to spawn the boss.

`ServerStorage.IsleRegionAccess` (existing BindableFunction) is generalised: `Invoke(player, regionId)` → `{allowed, message}` for every `Data.Regions` entry (`requires.quest` = completed contract count, `requires.skills` = levels).

`ServerStorage.IsleExpeditionReward` (BindableEvent) fires `(player, {floor, grade, score, seconds, deaths, mistakes, partySize, damageShare})`; a bare `(player)` counts as Floor I grade B. Profile field `p.dungeons = {lastClear, clears={[floor]=n}, best={[floor]=grade}}`; credited clears are 90 s apart. `ServerStorage.IsleExpeditionGrant` (BindableFunction, same payload) returns `{ok, reason}`; the expedition announces the chest only on ok. Credit needs ≥ 10% contribution (tuning counts for at most half of that) and, in parties, ≥ 5% of damage. Runs fail after 2× floor par; members idle > 90 s or > 120 studs away for > 10 s are removed.

## 5. Combat (`combat.server.lua`, `combat.client.lua`)

- Monsters spawn at `Workspace.MonsterSpawns` children: BaseParts with attributes `MonsterId` (key of `Data.Monsters`) and `Region`. World places them; Combat owns models, AI, respawn, health bars and damage numbers.
- Client sends `ReplicatedStorage.IsleCombat` RemoteEvent `("attack", targetModel)`; server validates range (≤ 14 studs), cooldown (from Attack Speed), alive state, then damage = `Progression.meleeDamage(stats, rng)`.
- Monster hits call bridge `"damage"`. Kills call bridge `"kill"` for every eligible contributor (Ironman: solo credit rules match the existing Warden).

## 6. World (`world.server.lua`)

New regions from `Data.Regions` (Windpine Grove, Gloomhollow Caverns, Tidewater Shoals, Tempest Spire) plus tier nodes on existing islands: gather prompts per §2, monster spawn markers per §5, crafting stations with `IsleAction="station"`, `IsleItem` ∈ `Forge|Hearth|Cauldron|Workbench` (server answers with the snapshot; the client opens the matching crafting tab via attribute `IsleStation` on the player), and warps gated through `IsleRegionAccess` (a denial sets `IsleRegionNotice` and increments `IsleRegionNoticeCount`, which the client shows as a toast). Every monster spawn marker is ≥ 40 studs from every warp landing.

## 7. Art (`art/PropCatalog.lua` + generators)

Exports in addition to `shapes`/`palette`:

- `Catalog.iconShape(itemDef)` → shape name for a `Data.Items` definition (by `kind`/`slot`/`toolKind`/`category`).
- `Catalog.tintIndex` → palette index whose faces the UI recolours with the item's `color`.

## 8. File ownership

| Team | Owns |
|---|---|
| Server | `server.server.lua`, `verify-gameplay.luau` |
| Combat | `combat.server.lua`, `combat.client.lua`, `verify-combat.luau` |
| World | `world.server.lua`, `verify-world.luau` |
| UI | `ui.client.lua` |
| Art | `art/**`, `mesh.client.lua` |
| Lead | `shared/**`, `default.project.json`, `verify.luau`, `verify-progression.luau`, build scripts, docs |

## 9. Wave 3 interfaces

**Skyward Calendar / events** (`festival.server.lua`, `Data.calendar*`/`Data.event*` in GameData): the date is a pure function of UTC `os.time()`. Workspace attributes `AetherYear`, `AetherSeason`, `AetherDay`, `AetherEvent`, `AetherEventEnds`, `AetherNextEvent`, `AetherNextEventStarts`, `AetherEventKey` (`"<eventId>:<start>"`, the authoritative match key). Server verbs `eventGift`, `eventTrade`; prompt action `eventVendor` sets `EventVendorUntil` and opens Journal → Calendar. Profile `p.eventClaims[key] = ends` (pruned after the event). Snapshot `events = {claims, vendorUntil, serverTime}`.

**Sea creatures** (`Data.SeaCreatures`, reachable through `Data.Monsters[id]` via `__index` but not by iterating `Data.Monsters`): a successful Fishing gather rolls Sea Creature Chance (stats + best rod + rod enchants, cap 100%). On a hit the server issues a ticket and sets player attributes `SeaCreatureAt` (node position) then `SeaCreatureSpawn = "<id>:<seq>"`; max 3 live tickets per player, 36 creatures per server. Bridge op `"seaCreature"` `{seq, monster, result="kill"|"despawn"}` settles a ticket once; only the owner is credited (`"kill"` refuses sea creature ids).

**Co-op** (`coop.server.lua`, `Data.Coop`): leave/kick (leader, fixed reason list)/transfer/disband, 10-minute invitations, 24 h rejoin cooldown; Homestead level 1–6 from contributions; up to 2 shared workers; crew stat perk in `p.perkStats.coop`. `IsleCoopProfile(player, seal, request)` gains an optional request argument; profile field `p.coopBox`. Player attributes `CoopLevel`, `CoopWorkers` drive the shared homestead visuals.

**Island placement** (`build.client.lua` = StarterPlayerScripts.IslandBuilder, `Data.Island`): verbs `place "propId:x:z:rot"` (grid cells −8..8, rot 0–3) and `pickup "<placementId>"` (100% material refund; Carpentry XP paid once per copy). Profile `p.island = {placed={"id:prop:x:z:rot",...}, paid={[prop]=n}}`, cap 120 placements (worst case ~4 KB JSON). Player attributes `IslandPlacements` (records joined by `;`) and `IslandCenter` (grid origin for client snapping).

## 10. Wave 4 (visual & scale overhaul) interfaces

Player feedback after the first live publish: islands too small, lighting buggy, signs/graphics and menus need custom meshes and a redesign, and gathering/interaction needs swing and interact animations.

- **Island anchors (World → everyone):** each island is a Model under `Workspace.Islands` with attributes `IslandCenter` (Vector3), `IslandRadius` (number), `Region` (Data region id or `"Home"`). Invisible anchored parts named `Anchor_<Purpose>` (e.g. `Anchor_NPC_Guide`, `Anchor_NPC_Slayer`, `Anchor_Waypoint_Forge`) mark points other teams position against. Never hard-code coordinates from another team's file.
- **Mesh slots (World → Mesh):** any part that should be rendered as a custom mesh carries attribute `Shape` (catalog shape name) and optional `Tint` (Color3) and `ShapeScale` (number). The Mesh team's server script replaces its visual with a generated MeshPart (via EditableMesh + `AssetService:CreateMeshPartAsync`) and keeps the original part as the invisible collider/fallback. Signs carry `Shape="Signboard"` (or a variant) plus their SurfaceGui text.
- **Gestures (Animation):** gather/interact prompts keep `IsleAction`/`IsleItem`; the client animation script plays the matching swing (mine, chop, fish, harvest, craft, interact) locally and replicates to others by firing `ReplicatedStorage.IsleGesture` (RemoteEvent, server-validated, rate-limited) which re-broadcasts to nearby clients.

## 11. Gear depth

Verbs `reforge "itemId"`, `reforgeStone "itemId:stoneId"`, `star "itemId"`, `tome "itemId:TemperingTome|MasterworkTome"`. Upgrades are per item id (like enchants): `p.reforges[id]`, `p.stars[id]`, `p.books[id] = {tempering, masterwork}`; snapshot `depth.gear`. `Progression.effectiveRarity/upgradeStats/upgradeBreakdown/isUpgraded`; upgraded ids cannot be auctioned.

## 12. Skill mastery and Verdant Garden

**Mastery:** verbs `masteryUnlock "Tree:Node"`, `masteryRespec "Tree"`, `ability "Tree"`, `masteryWear "cape|aura|title:Skill"`. Profile `p.mastery`; snapshot `depth.mastery`; bridge `"stats"` adds `mastery = {melee, ranged, magic, active}` read by combat (firstStrike, execute, manaThrift, multishot). Player attributes `MasteryCape`, `MasteryAura`, `MasteryTitle`, `MasteryAbility`. Gathering yield multipliers apply before fortune and never stack with procs (`Progression.gatherYieldMult`); regrowth reductions are floored (`Progression.regrowthTime`).

**Garden:** verbs `plant "plot:seed"`, `harvestPlot "plot"|"all"`, `waterPlot`, `fertilise`, `treatPlot`, `clearPest`, `clearPlot`, `gardenPlot` (world prompt), `gardenOpen`, `compost "item:n"`, `compostClaim`, `composterUpgrade`, `visitorAccept/visitorDecline "id"`, `gardenBuy "id"`, `gardenSkin "id"`. Snapshot `garden`; player attributes `GardenLevel`, `GardenPlots`, `GardenSkin`, `GardenComposter`, `GardenVisitors`, `GardenPlot1..12 = "crop:stage:flags"`. Timers use server `os.time()` and advance on refresh (offline growth).

## 13. Endgame: The Shattered Crown and world bosses

Region `ShatteredCrown` (Combat 60 + `requires.questsDone`). World bosses Aurelith (sigil-summoned, 4 Crown Sigils, ≤ 2 per player) and Nyxwyrm (Skyward Calendar, once per isle day) reachable as `Data.Monsters[id]` but not iterated. Prompt verb `bossSigil` → `ServerStorage.IsleWorldBoss:Invoke("sigil"|"status", ...)`. Bridge op `"worldBoss"` `{boss, tier, rank, share, damage, sigils, fight}` pays once per fight; `"kill"` refuses world-boss ids. Credit: ≥ 1% of max HP dealt, alive, within ~120 studs, hit in the last 60 s, Ironman ≥ 30%. `IsleCombatFx` kinds `worldBoss`, `telegraph`, `bossStrike`, `worldBossAnnounce`, `worldBossLoot`. Workspace attributes `WorldBossSigils_Aurelith`, `WorldBossActive_<id>`, `WorldBossNext_Nyxwyrm`.

## 14. Workers depth

`Data.Workers`: 35 worker types (type id = output resource id; 6 combat workers), Condensed/Radiant compacted items (160 → 1), 5 fuels, 5 upgrades, 3 chests. Slots 3 → 12 by unique crafts (`p.workerUniques` bitmasks). Verbs: `worker`, `workerBuild "slot[:Type]"`, `workerResource`, `workerAssign "slot:Type"`, `workerUpgrade`, `claim`, `workerClaim`, `workerClaimAll`, `workerFuel "slot:Fuel[:n]"`, `workerUnfuel`, `workerInstall "slot:Part"`, `workerRemove "slot:1|2|chest"`, `workerBlueprint "Type:tier"`. Snapshot `workers[i]` extended + `workerInfo`; player attributes `Worker1..12Tier/Resource`, `WorkerSlots`. Accrual is integer `os.time()` maths capped at 48 h.

Balance rules (after review): worker pace = 0.4 × node respawn (starters ×1), worker XP = max(3, xp//10), fuels +5/8/12/15% (+10% permanent), max 3 workers per type, max 2 combat workers (collection credit 25%), level 60+/75+ types need collection tier 4/5, region-only types need the region unlocked; over-limit workers idle instead of being changed.

## 15. Pets depth

`Data.PetDepth`: species rarities Common→Legendary (stat multipliers 0.55/0.7/0.85/1/1.2 relative to base rarity), 2–3 wired abilities per species, 12 held items, Pet Candy / Starlit Candy (10 per pet), Ascendant Prism tier boost, Roost rarity upgrades on an `os.time` timer. Verbs `petItem "i:species:itemId|none"`, `petCandy "i:species:PetCandy|StarlitCandy"`, `petTierBoost "i:species"`, `petUpgrade "i:species"` (species must match the pet at index i), `petClaim`, `petCancel`, `petShop "itemId"`. Snapshot pet rows add rarity/item/candy/abilities/stats/totalXp/upgrade; `depth.petDepth = {upgrade, taming}`. Player attribute `ActivePet = "species:rarity:level"` drives `pets.client.lua` followers. Profile fields `rarity`, `item`, `candy` per pet; `p.petUpgrade`, `p.petTamingCarry`, `p.petSkillXp`.

Pet doubled harvest is a candidate inside `Progression.gatherYieldMult` (largest-wins with mastery). Pet extra crafts only roll for repeatable/stackable outputs. Worker-claim XP (`grantXp(..., "worker")`) skips all pet hooks. Skilling pets drop only while the player owns none of that species.

## 16. Dungeon classes

Classes Aegis/Mender/Riftblade/Starshot/Arcanist (`Data.DungeonClasses`), levels 1–50 (XP total floor(8·(L−1)^2.5), ≈1.8× the Dungeoneering-50 grind), abilities validated by `DC.abilityCheck`. Verbs `dungeonClass "<id>|none"`, `dungeonMaster "on|off"` (refused in a run). Profile `p.dungeonClasses`; snapshot `dungeonClasses`; bridge op `"dungeonClass"`; `"dungeon"` op returns class/XP/bests/master. Grant payload adds class, master, secrets, secretsTotal, bonus, teamMult, feat. Player attributes DungeonClass, DungeonClassLevel, DungeonMasterOn, DungeonMasterPick, DungeonInRun, DungeonParty, DungeonAbilityReady, DungeonUltimates. Score = (speed+survival+puzzle+secrets)×0.75 + bonus (≤20). Floors VI/VII need Dungeoneering 40/50; Master Mode I–V unlocks after S+ (par ×1.6, XP/coins ×2.2). Wisp HP = base × √(floor HP mult), waves pause while a full wave lives, ≤ 8 live wisps. Second Dawn: boss phase only, forgives one fall within 20 s (refresh, no stacking). Team bonus counts only credited delvers; the pedestal saves the class to the profile.

## 17. Prayer & Thieving

20 skills. `Data.Prayer`: 21 prayers (groups switch each other off), max points 10 + level, drain = Σ points/min ÷ 60 ÷ (1 + Devotion/30); protection −40% vs monsters, −25% vs world bosses, applied to the raw hit before Defense. 8 remains tiers, 4 altars (×1–×1.75). `Data.Thieving`: 14 targets (stalls, pickpockets, strongboxes); success = base + 0.008/level over + gloves + 0.002×Deftness (≤95%); failure stuns 4–7 s with non-lethal damage. Verbs `prayer "<id>"`, `prayerOff`, `prayerQuick "<1|2>:<id>"`, `offerRemains "<remains>"` (within 60 s of an altar visit); prompt actions `altarOffer`, `altarPray`, `thieve`. Bridge `"stats"` adds `prayer = {protect, offence, sap, mana, defence}`; `"damage"` reads `payload.style`/`payload.worldBoss`. Attributes PrayerLevel/Points/Max/Drain/Active/Quick/Altar/AltarUntil, ThievingStunUntil. Snapshot keys `prayer`, `thieving`.

## 18. Treasure Trails

`Data.Trails`: tiers Beginner→Master (steps 1–3 … 6–9), 161 steps (dig, riddle, emote, skill, 3×3 puzzle box), caskets with 35 uniques, clue log. Verbs `trailBegin`, `trailAbandon`, `trailDig`, `trailSearch`, `trailEmote "<gesture>"`, `trailSlide "<tier>:<UDLR…>"` (≤ 48 moves), `trailCheck`, `trailOpen`, `trailTeleport`, `trailLearn`, `trailBanner`. Profile `p.trails`; snapshot `trails` (step text/hints only); attribute `TrailBanner`. Clue drops use a private per-player RNG stream.

## 19. Slayer tasks

New 99-level skill `Slayer` (21 skills). Masters Ysolde (Combat 3), Mossgrave (Combat 20), Duskward (Combat 45, Slayer 20), Harrowgale (Combat 75, Slayer 50) assign weighted tasks from 14 families (sea creatures and Crownbound at high tiers). Kill XP = max HP ÷ 25; boss lines keep their 1–9 ranks and also grant Slayer XP. Points with streak multipliers (×5/15/25/35/50 at 10/50/100/250/1000), skip 30, block 100 (3 or 5 slots), 17-entry shop incl. Hunter's Visor. Superiors 1/150 on land task kills once unlocked (owner-only, ticketed). Four Slayer-level-gated monsters (40/60/75/85). Verbs `slayerTask "<master>"`, `slayerSkip`, `slayerCancel`, `slayerBlock`/`slayerUnblock "<family>"`, `slayerBuy "<shopId>"`, `slayerTitle "<id>|none"`. Bridge: `"kill"` returns `superior={id,seq}`; ops `"slayerSuperior"`, `"slayerDenied"`; `"stats"` adds `slayer={level,family,visor}`. Attributes SlayerTask, SlayerTitle, SlayerLevel; snapshot `slayerTasks`; profile `p.slayerTasks`.

Slayer review rules: superior loot scales with base level (Ichor/Sigil only from level ≥ 40); no superior roll when base level < Combat/3; blocks may not leave an available master with < 2 families; task credit (`payload.task` on bridge `"kill"`) needs ≥ 20% of max HP dealt or top damage; superiors only target their owner; Slayer-gated monsters ignore players below the level; attribute `SlayerVisor` invalidates combat stats cache; crafting refuses equipped/bagged cost items.

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

`Data.Trails`: tiers Beginner→Master (steps 1–3 … 6–9), 161 steps (dig, riddle, emote, skill, 3×3 puzzle box), caskets with 35 uniques, clue log. Verbs `trailBegin`, `trailAbandon`, `trailDig`, `trailSearch`, `trailEmote "<gesture>"`, `trailSlide "<tier>:<UDLR…>"` (≤ 48 moves), `trailCheck`, `trailOpen`, `trailTeleport`, `trailLearn`, `trailBanner`. Profile `p.trails`; snapshot `trails` (step text/hints only); attribute `TrailBanner`. Scroll drops, trail seeds and casket rolls use an unseeded, unsaved server `Random.new()`; the step pool and answers live server-only in `ServerStorage.AetherTrails` (`trails.lua`), with only UI data in `Data.Trails`. Location steps need `TR.MIN_STEP_SECONDS` (8–15 s) and a plausible travel time from the previous location step. `trailTeleport` uses `ServerStorage.IsleTravelGate` (dead / recently hurt / in expedition), a 30 s cooldown and zeroes velocity.

## 19. Slayer tasks

New 99-level skill `Slayer` (21 skills). Masters Ysolde (Combat 3), Mossgrave (Combat 20), Duskward (Combat 45, Slayer 20), Harrowgale (Combat 75, Slayer 50) assign weighted tasks from 14 families (sea creatures and Crownbound at high tiers). Kill XP = max HP ÷ 25; boss lines keep their 1–9 ranks and also grant Slayer XP. Points with streak multipliers (×5/15/25/35/50 at 10/50/100/250/1000), skip 30, block 100 (3 or 5 slots), 17-entry shop incl. Hunter's Visor. Superiors 1/150 on land task kills once unlocked (owner-only, ticketed). Four Slayer-level-gated monsters (40/60/75/85). Verbs `slayerTask "<master>"`, `slayerSkip`, `slayerCancel`, `slayerBlock`/`slayerUnblock "<family>"`, `slayerBuy "<shopId>"`, `slayerTitle "<id>|none"`. Bridge: `"kill"` returns `superior={id,seq}`; ops `"slayerSuperior"`, `"slayerDenied"`; `"stats"` adds `slayer={level,family,visor}`. Attributes SlayerTask, SlayerTitle, SlayerLevel; snapshot `slayerTasks`; profile `p.slayerTasks`.

Slayer review rules: superior loot scales with base level (Ichor/Sigil only from level ≥ 40); no superior roll when base level < Combat/3; blocks may not leave an available master with < 2 families; task credit (`payload.task` on bridge `"kill"`) needs ≥ 20% of max HP dealt or top damage; superiors only target their owner; Slayer-gated monsters ignore players below the level; attribute `SlayerVisor` invalidates combat stats cache; crafting refuses equipped/bagged cost items.

## 20. Commissions, Collection Log and Museum

`Data.CommissionsLogs`. Commissions: 4 daily slots (UTC day, deterministic per journal) from 40 tasks; rewards XP, coins, Glimmerdust; milestones at 1/5/15/50/150; Forgeheart perks (Mining Speed, Fortune sharing a 99 budget with Mastery, gem chance). Collection Log: 124 auto-generated uniques in 10 tabs, tab rewards and rank; retroactive credit only on first load, afterwards only via `collect()` (plus adopted pets and Treasure Trails clue uniques) so bought/borrowed items never count. Board only rolls forward to a later UTC day. Museum: 205 donatable items (consumed; refused only when the donation would take an equipped, bagged or upgraded copy — spares are accepted), 7 milestones. Verbs `commissionClaim "<slot>"`, `commissionClaimAll`, `forgeBuy "<perk>"`, `logClaim "<tab>"`, `logTitle "<tab>|Paragon|none"`, `museumDonate "<item>"`, prompt verb `logsBoard`, `logsSync` (forces a full `logs` snapshot; otherwise `logs` is `{rev, resetIn, compact=true}` when unchanged). Profile `p.commissions`, `p.colLog`, `p.museum`; perks in `p.perkStats` (`commissions:milestones`, `forgeheart`, `museum`); snapshot `logs`; attribute `LogTitle` (shown on a server `LogTitlePlate` billboard). Items flagged `minigameUnique` join the Minigames tab and must be granted through `collect()` to count.

## 21. Minigames (Skybreach Siege, Tempest Haul)

- `minigames.server.lua` (ServerScriptService "Minigames") runs lobbies, matches, scoring and the in-match world; all rules live in the `-- Minigames` section of `shared/GameData.lua`.
- Bridge op `"minigame"`: `info` (`{combat, levels, ironman, lumenward, rollRoom}`), `spend` (Timber only), `settle` `{game, tier, points, won, partySize, seconds, xpSeconds, xp, forfeit, xpOnly, required, recent}`. The server clamps points to 12/s of match time and only accepts XP in the game's own skills: Siege Carpentry ≤ `REPAIR_XP_LIMIT` repairs; Haul XP's time-equivalent (amount / `Haul.xpPerSecond(level)`, summed over Fishing/Cooking/Carpentry) ≤ `xpSeconds` + one action, else scaled down. `xpOnly` pays XP only (no log, no reward).
- Siege: a repair needs at least one repair's worth of missing HP (`Siege.canRepair`); repair XP = Timber × solo Carpentry XP per Timber (`MG.soloCarpentryXpPerTimber`) × `SOCIAL_BONUS`, at most `REPAIR_XP_LIMIT` paid repairs and `REPAIR_POINT_CAP` (< `MIN_POINTS`) repair points per member per match. Commendations need `Siege.requiredPoints(seconds, median)` = max(`MIN_POINTS`, `MIN_POINTS_PER_MINUTE` × minutes in the match, `MEDIAN_SHARE` × median member points at the end) and a credited action in the last `RECENT_SECONDS` (`recent`). The HUD `min=` shows the member's current requirement.
- Haul: each action pays XP for the measured seconds since that member's previous credited action, capped at its model seconds (`Haul.actionXp(action, levels, seconds)`), so XP/h ≤ `XP_RATIO` × solo at any cadence. Rolls are capped by match time: `Haul.maxRolls(seconds, solo)` = modelled game's rolls × min(1, seconds / `Model.gameSeconds`) (× `SOLO_REWARD` solo); stalling the Leviathan adds none. `partySize` at settlement = members still present with ≥ `MIN_POINTS` (an idled-out alt keeps the solo penalty). Players with fewer than `MAX_ROLLS` free bank slots are refused at the pad; rolls past the 500 bank cap are opened on the spot (never dropped).
- `ServerStorage.IsleMinigameAccess` gates the Skybreach ferry (Combat 20 or Fishing 20). The bastion's return ferry passes `ServerStorage.IsleTravelGate` (refused without it) and zeroes velocity.
- Verbs: `mgBuy <shopId>`, `mgRoll 1|all`, `mgTitle <id>|none`. Profile key `p.minigames`; snapshot key `minigames`. Shop pieces and cache loot are granted through `collect()`; Lumenward pieces (`minigameUnique`), Stormcaller pieces, the Tidebreaker Rod and the Squallpup are Collection Log entries.
- Workspace attributes `MinigameLobbies`, `MinigameMatches`; player attributes `MinigameGame`, `MinigameHud`, `MinigameNotice`, `MinigameNoticeCount`, `MinigameTitle`.
- Rewards are paid only to members who reach the requirement; removed (idle/away) members keep XP but get no reward. A disconnecting member's XP is settled XP-only at `PlayerRemoving` while the journal is live (kept on the record if the bridge does not answer `ok`); they may rejoin within 90 s with their points, keeping their old idle clock plus `MG.REJOIN_GRACE` (15 s); the rejoin waits for `HumanoidRootPart` (5 s) before moving the body.
- Lumenward: `Data.Sets.Lumenward.style(p, Progression.equipped)` (= `MG.lumenwardStyle`) returns the worn helm's style when all four pieces are validly equipped; shared `Progression.computeStats` applies any active set's `style` stats after perk stats and before caps and sets `s.setStyle`, so client and server compute identical stats (no server wrapper).
- Tests: `verify-minigames.luau` (Part E drives the QC regressions at the real 1.2 s action cadence).

## 22. Crafting

22 skills. New 99-level production skill `Crafting` (title Artificer, colour `C9708A`, perLevel +0.5 Defense and +0.5 Ranged Accuracy; 99 mantle +10/+10). All rules and data live in the `-- Crafting` section of `shared/GameData.lua` (`Data.Crafting`, alias `CR` below); `server.server.lua` (Crafting block before `perform`), `world.server.lua` (Crafting section), `ui.client.lua` (Workshop › Crafting), `animate.client.lua` and `nav.client.lua` consume it.

- **Stations** (Guild Terrace, "Artificers' Row"): Jeweller's Bench (`Jeweller`), Tanning Rack (`Tannery`), Glass Furnace (`Glassworks`). Prompts: `IsleAction="craftStation"`, `IsleItem=<station>`, interact hold. Anchors `Waypoint_Jeweller|Tannery|Glassworks` (listed under Navigate › Stations). Models carry `CraftingContent=true`; built from existing mesh slots (Workbench, OreCluster, Barrel, Forge, Signboard) — 18 parts + one sign, no lights.
- **Branches** (`CR.Branches`, cadence s/action): gem cutting 1.8 (Facet Chisel), jewellery 2.4 (Ring/Necklace/Amulet Mould per recipe), amulet enchanting 3.0 (skill Enchanting), tanning 1.2, spinning 1.2 and weaving 1.8 (Drop Spindle), leatherwork 2.4 (Hide Needle), sand sifting 1.2, glassmelting 1.8, glassblowing 1.8 (Blowing Pipe). Tools are Forge recipes in `Data.Recipes` (Smithing 1–5, `category="craftTool"`), owned and never consumed.
- **Recipes** live in `CR.Recipes` / `CR.RecipeOrder` — **not** `Data.Recipes`, so the generic `craft` verb cannot make them. Fields: `branch, station, seconds, level, xp, costs, amount, tool, collectionTier, skill ("Crafting" | "Enchanting"), shatter`. 75 patterns: 8 gem cuts (Dewquartz 1 … Starheart 78; five reuse the existing cut gems), 24 jewellery accessories (ring/necklace/amulet per gem; ingot + cut gem, amulets strung with Spun Thread), 4 enchanted amulets (Enchanting 35/50/65/80, Arcane Dust + glyphs, one rarity up), 2 glass charms (Farsight Orb, Prism Monocle), 5 leathers and 5 four-piece Ranged sets (Wayfarer 1, Downstride 18, Cinderhide 38, Duskprowl 58, Stormmantle 76; Ranged 1/10/25/40/55; `Data.Sets` with exactly four pieces and a bonus), Spun Thread, Skyweave Bolt, Skysand, Molten Skyglass (3 melts), 5 glassware pieces, Tanning Oil (vial + herbs; tiers 2+ of leather need it).
- **Rules** (pure, shared): `CR.check(p, id, levelOf, tierOf)` (level, tool, collection tier, costs), `CR.cutFailChance(rec, level)` = `CUT_FAIL` (0.3) × (1 − over/`CUT_FADE` (25)) for gem cuts only; a shatter consumes the rough gem, gives Gem Grit (fluxes the level-30 melt) and `SHATTER_XP` (25%) of the XP. `CR.gemChance(tier)` = 1% × (1 + 0.1 × (ore tier − 1)) per Mining harvest; `CR.roughFor(tier, r)` weighted pick gated by `minTier`. `CR.parseBatch(text)` → id, count clamped to `MAX_BATCH` (28).
- **Verbs** (`IsleAction`, item ≤ 64 chars): `craftStation <station>` (prompt only) records a visit (`VISIT_SECONDS` 900, at the prompt's part) and sets `IsleStation`/bumps `IsleStationVisit` (client opens Workshop › Crafting on that station). `craftBatch "<recipe>:<count>"` (remote) needs a live visit to the recipe's station, the character within `STATION_RANGE` (24 studs), and `CR.check`; replaces any running batch. `craftStop`. The server loop (`CR.TICK` 0.3 s) performs **one** action per job when `seconds` have elapsed since the previous one (first action one full cadence after the start; no catch-up after lag, a replaced batch restarts the cadence). Every action re-checks range, life, `CR.check` and worn copies (an equipped/bagged cost item is never consumed), spends, rolls the shatter, grants the output through `collect()` (collections, Collection Log), counts `p.counters.crafts` (quest `craft` checks) and `Logs.event(p, "craft", output)` (commissions), pays XP to `recipe.skill` (pet extra-craft for stackable outputs, no XP) and pushes a snapshot. Clients never send quantities beyond the count, which the satchel bounds anyway. Ironman journals use every verb (no trade path).
- **Mining hook:** after every other harvest hook, a Mining gather rolls `CR.gemChance(resource.index)` then `CR.roughFor` and `collect()`s the rough gem (an extra item, never part of the ore yield).
- **Commissions:** four `kind="craft"` tasks (`target` = output id, one credit per batch action): Vial Order, Tannery Shift, Sunstone Cutting, Skyweave Loom (44 tasks total).
- **Collections:** 8 rough gems, Dewquartz/Skyjade/Stormopal, 5 leathers and Molten Skyglass join `Data.CollectionItems` (scaled); jewellery from Mistpearl up needs that cut gem's collection tier I, leather sets from Downstride up need their leather's tier I, glass charms Molten Skyglass III/V.
- **Profile** `p.crafting = {made = {[recipeId] = n}, shattered = n}` (migrated: unknown ids, negatives, NaN dropped/clamped). Jobs and visits are session-only (strong tables keyed by player, cleared in `forget`).
- **Snapshot** key `crafting = {job = {recipe, done, total, made, shattered, xp, nextIn} | nil, station = "<visited station>" | "", stationIn, near, made, shattered}`.
- **Player attributes:** `CraftingJob = "<recipe>:<done>:<total>"` or `""`; `CraftingGesture = "<gesture>:<seq>"` after each action (animate.client.lua plays `hammer`/`saw`/`stir` once per new seq; `Core.STATION_GESTURE` covers the three stations for the prompt itself).
- **Balance** (`CR.chainRate`, checked in `verify-crafting.luau`): supply-chain XP/h = crafting XP of a recipe and its crafted inputs ÷ (raw gather seconds of the inputs + every station action). Raw seconds: resources `max(respawn, 1.65)`, creature/Hunter drops `CR.SourceSeconds` (Beast Hide 20 s, Downy Pelt 15, Ember Pelt 35, Shadow Pelt 70, Stormmane Hide 110). Every glassware, weave and leather end product stays within 0.5×–2× the best Smithing/Fletching/Glyphcraft chain open at its level (those crafts are instant; their rate is gather-bound): Glass Vial L8 9.0k XP/h (1.5×), Lantern Globe L25 10.3k (1.4×), Skyglass Orb L46 12.0k (1.6×), Prism Lens L70 11.4k (1.4×), Skyweave L20 5.4k (0.75×), jerkins Wayfarer L11 3.3k (0.55×), Downstride L28 6.5k (0.9×), Cinderhide L48 6.3k (0.85×), Duskprowl L68 5.6k (0.7×), Stormmantle L86 5.4k (0.68×). Station rates with banked materials are cadence-bound (e.g. a Stormmantle Jerkin, 400 XP / 2.4 s) — far below the uncapped 0.24 s generic `craft` verb other production skills use. Gem cutting is a Mining bonus: ~110–230 XP/h (≤ 2% of the ore's own XP/h; 3–12 rough gems/h).
- **Pending lead decisions:** (1) `CR.VIALS_IN_POTIONS` (default `false`): when approved, every potion in `CR.VIAL_POTIONS` costs one Skyglass Vial more (one-line flip, no other change). (2) Crafting adds 30 accessories (24 jewellery + 4 enchanted + 2 glass charms); Magical Power counts every distinct id, so a SkyBlock-style "accessory family" rule (only the best of a gem's ring/necklace/amulet/enchanted line counts) would need `Progression.activeAccessories`; data carries `category="jewellery"` and `gem=<cut gem>` for it.
- Tests: `verify-crafting.luau` (Part A data/balance, Part B world, Part C server at the real cadence); verify-ui Crafting client block; verify-gesture craftStation checks.

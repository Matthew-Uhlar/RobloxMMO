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

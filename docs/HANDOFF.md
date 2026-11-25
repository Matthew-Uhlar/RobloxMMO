# Handoff: Aether Isles (for the next lead)

Written 2026-11-21 by the previous lead session. Read this first, then `docs/DEPTH-CONTRACT.md` (the interface contract, §1–30) and `PROJECT-STATUS.md`.

## 1. What the owner wants

An original Roblox MMO, **Aether Isles**: floating sky islands with Hypixel SkyBlock and Old School RuneScape mechanics, and the same skill intricacy and depth of progression. Keep adding content and depth until it is on their level. The owner's standing feedback, most recent first:

- **Art direction:** modern and detailed, closer to Hypixel than OSRS. **Never low-poly or flat-shaded.** Rich colour, glow accents, bold outlined display text.
- **Map:** make the map (Sky Chart warp map and minimap) much more detailed, in that modern style.
- **Fixed by the merge in §4, needs a check in Studio:** grass texture was clipping into the island rock.
- **Gameplay and UI:** weapons, picks and tools must be held in hand with physical swing animations. The inventory must be easy to reach. The UI should work like OSRS or SkyBlock and be fully overhauled. Player islands must be much larger. All signs must be appealing and detailed. Custom meshes everywhere (bridges, islands, signs) must be more detailed. Places need unique Aether Isles names, with quest-giving NPCs and basic MMO mechanics.
- **Earlier feedback:** islands too small, lighting buggy, signs and graphics need custom meshes, menus need an overhaul, every gather or interact needs swing and interact animations.
- **Originality:** all names, art and branding must be original. Use the wikis and videos for mechanics and feel only.
- **Reference material:**
  - `https://hypixelskyblock.minecraft.wiki/`
  - `https://oldschool.runescape.wiki/`
  - the owner's three videos, already studied; notes are in `docs/reference-notes/` (see §6)
  - the owner's screenshots, described in the reference notes

## 2. Repository, branch, PR, publishing

- **Repo:** `Matthew-Uhlar/RobloxMMO`.
- **Working branch:** `claude/pensive-maxwell-145p0c`. Commit and push only here.
- **Open PR:** [Matthew-Uhlar/RobloxMMO#5](https://github.com/Matthew-Uhlar/RobloxMMO/pull/5) (branch → `main`). It holds every wave since the first publish.
- **Do not merge it without the owner's explicit say-so.** Approval for the earlier PR #4 does not carry over.
- **Publishing:** merging to `main` triggers `.github/workflows/publish.yml`, "Publish Roblox place", which uses environment `roblox-production` and secret `ROBLOX_API_KEY` (universe 10777817254, place 73453386951995). The owner has published once (PR #4). After any publish, check the run and ask the owner to play-test.
- **CI:** "Build and verify", `.github/workflows/build.yml`, runs `build.ps1` on Windows.
  - `.gitattributes` forces LF line endings, because suites slice other suites' source by markers containing `"\n"`.
  - Keep that rule. CRLF checkouts broke CI once.
- **Commit trailer** (every commit):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FkUNqZEFYap7XtGbpVDhXd
  ```
  (Use your own session's attribution lines if your environment gives different ones.)

## 3. Build and test

```bash
export PATH=$HOME/.cargo/bin:$PATH   # Lune 0.11.1, Rojo 7.7.1 (cargo install ... --locked if missing)
./scripts/build.sh
```

- Runs `node art/import/verify-import.cjs`, then **30 Lune suites** (`verify-*.luau`), then `rojo build` → `Aether-Isles.rbxl` and `verify.luau`, which compiles and checks the scripts.
- Every suite must print `SUITE-END <file>`. Lune exits 0 on a coroutine that yields forever, so the build fails if any suite is missing its sentinel.
- `build.ps1` mirrors the suite list. **Add every new suite to both files.**
- **Generated art:** after editing `art/*-shapes.cjs`, run `node art/generate-props.cjs && node art/generate-import.cjs`. On merge conflicts in `art/import/*.glb` or `manifest.json`, regenerate instead of hand-merging.
- **Static world part budget:** 4000, about 3,675 used (§40 settlements: 58 buildings, 7 walk-in halls). Detailed shapes are forged on the client as EditableMeshes (`forge.client.lua`), so a `meshSlot` proxy costs one server part.

## 4. How the work is organised

- **The lead** owns the contract, `shared/GameData.lua` structure and `shared/Progression.lua`, and makes balance decisions.
- **Teams** are agents run with `isolation: "worktree"`, one feature each, with a precise brief: files, contract section, tests, a SUITE-END suite, docs. Each starts with `git merge --no-edit claude/pensive-maxwell-145p0c`.
- **Merging:**
  - `git merge --no-edit worktree-agent-<id>`.
  - **Conflict rule:** keep both sides.
    - In `GameData.lua`, team sections are appended just before `return Data`. Insert the section; never concatenate mid-function.
    - In the build script lists, take the union.
    - In the contract, keep the newer text and drop stale duplicates.
  - Then run a full build, commit and push.
- **Quality control:** an independent read-only review (`roblox-dev:roblox-reviewer`) runs after every merge, then a fix team handles all findings with a regression test per fix. Lead decisions are written into the fix brief and into the contract.
- **Recurring rules from past reviews** (check every new feature against these):
  - **No coin mints.** Every shop offer must have price per unit ≥ sell value × 1.3, and crafted item value ≤ input value.
  - **Shop purchases** go straight to `p.items`, never through `collect()`.
  - **Server-authoritative** verbs, validated and rate-limited, routed through `IsleAction` and `perform`.
  - **Rejoin-safe** and lease-safe saves. Every server teleport sets `FastTravelAt`.
  - **Day boards roll forward only** (guards against servers whose clocks are behind).
  - **`perkStats` stays within `Data.PerkBudget`** (300 Health / 125 Defense).
  - **Upgraded last copies** can't be sold, dropped or donated.
  - **Rewards go only to members present** who contributed, with idle and AFK removal.
- **Usage limits:** when teams stop with "hit your 5-hour limit", resume each with `SendMessage` after the reset. Don't start duplicate agents.

## 5. State at handoff

**Merged and pushed** (all 32 suites pass at pause). Contract sections:

| § | Systems |
|---|---|
| 11–19 | gear depth, mastery and garden, endgame, workers, pets, dungeon classes, prayer and thieving, treasure trails, slayer tasks |
| 20–25 | commissions, collection log and museum; minigames; crafting; dungeon endgame; exploration and factions; lair bosses |
| 26 | held items, hotbar and swings |
| 27 | big home islands |
| 28 | shared sign system |
| 29 | "Skyforge" UI: `shared/UiTheme.lua`, `hud.client.lua` satchel, gear and Sky Chart, sidebar, action bar, Menu grid |
| 30 | world art and regions: forged hulls and bridges, landmarks, 27 NPCs, 23 regional quests, warp scrolls |

- Since §30 was written, a grass-clipping fix landed in `island()` in `world.server.lua`: the foundation and cliff now sit below the meadow slab, and verify-world asserts this.

**Also merged at pause time** (32 suites pass). All three have since had independent QC reviews and fix rounds (merged and pushed). The live game was published from PR #5 before those fixes; publishing again needs the owner's go-ahead:

| Merged | What it is |
|---|---|
| UI overhaul QC fixes | All 24 findings: satchel drag and click bugs; M opens the Sky Chart; PlayerList core GUI off; the minimap setting hides the whole block; XP-drop lanes; tablet docking; short windows; `Gear.upgraded` guard on sell and drop; 12 lows. |
| §31 MMO features | `features.client.lua`, `verify-features.luau`: Isle Renown account level (perkStats `renown`, accessory slots at renown 10/25/50/100/150), Wayfarer's Path onboarding (11 steps since Polish, journal mode first; claimed via `guideClaim`), announcement toasts, shop quantity `:qty` 1–64, six Skyward Vents, Resonance (Magical Power templates, NPC Oriel Thrumwright). |
| §32 map art | `shared/MapArt.lua`, `verify-map.luau`: 3D ViewportFrame Sky Chart built from the real islands, plus region-tinted minimap plates. |
| §37 Beaconry | New 1-99 skill (23 skills): kindling with held strikers, bounded campfires (`beaconry.server.lua` draws them), nine regional beacon pyres with warmth buffs and a weekly cross-server goal, campfire cooking, Pyre Ash for Alchemy / Farming; `verify-beaconry.luau`. Open decisions in §37. |

**Open decisions from §31:**
- ~~Retire Pell's older 6-step tutorial~~ — done (Polish wave, lead decision): the Wayfarer's Path is the only onboarding; see §31 "Polish".
- ~~Merchant selling is whole-stack only~~ — done: `sell "<id>:<n>"` with the picker in sell mode.
- Resonance gathering templates (about +36 fortune / +108 mining speed at 300 MP) need a play-test.
- ~~Journal mode timing~~ — decided (Polish QC round): "Choose your journal mode" is now the FIRST Path step, offered by Pell at first contact (Standard in one tap, Ironman behind the explanation and the PERMANENT confirmation; refused once started or while in a crew). Saved Path progress is keyed by step id, so nothing is re-indexed; `p.guide.v = 2`. See §31 "Journal mode".

**Follow-ups from §31:**
- per-player shop stock limits
- full tooltip footer
- top objective progress bar
- ~~tier-1 worker recipe unlock message~~ (done: WORKER RECIPE UNLOCKED announcement)
- pickup feed
- OSRS action label and status orbs
- chat filter tabs
- goal board
- price history
- server browser
- ~~account-mode choice at the end of onboarding~~ (done: Path step `mode`, verb `guideMode`)

**From §32, to check in Studio:**
- the first-open hitch when copying about 2.2k parts
- label overlap around Compass Quay
- forge budget contention from the chart's 40 pinned meshes

**Known open items and ideas:**
- ~~**Hollowcrown Edge** niche~~ — done: Hollow Sunder (+25% vs bosses, +50% vs warded bosses), modelled in verify-bosses. See §25. Play-test the feel against Nihlvar and world bosses.
- **StreamingEnabled is off.** Enabling it needs an audit of client scripts that read far-away world children (nav, motes, regions, ui). See §27.
- ~~Stale display names~~ — done: base data says Compass Quay / Sunwheel Downs / Brassfall Cay (ids unchanged).
- **Vent launch feel** (Polish): FOV kick, banking tilt and wind streaks need a Studio check for comfort and with the Lighting team's director. (QC L2 fixed back-to-back vents leaving the FOV kicked.)
- **Polish QC fixes:** sell picker needs a confirming second tap (M1); atlas hides Sell / Sell… for equipped or bagged items (M2); Ironman refused while in a crew (L1); worker recipe toast says "available at <skill> <level>" when gated (L3); stale tutorial-tracker comments updated and the dead `TutorialTracker` lookup removed from the Agility HUD layout (L4). Pell's first-contact journal-mode options need a phone check (two extra dialogue rows).
- **Gaps from the OSRS videos still unbuilt:**
  - a "verb + target" action label;
  - a per-skill unlock guide in the skills panel;
  - a built-in quest helper;
  - a goal board;
  - market price history;
  - "closest teleport" on the map;
  - an optional HD lighting setting (Future lighting by default, with a performance setting);
  - built-in calculators;
  - OSRS-style hitsplats and overhead HP bars if missing;
  - chat filter tabs.
- **Everything visual still needs a Studio play-test:** held-item grips and swings, sign fonts and readability, hull and bridge proportions, the UI with the real Roblox fonts, phone performance.

## 6. Reference notes

`docs/reference-notes/` holds the owner's three videos, studied frame by frame, plus Gemini's narration-aware notes for part of the SkyBlock video:

- `skyblock-beginner-guide.md`: HUD, sidebar, tooltip format, menus, systems and world layout. Prioritised feature list at the end.
- `skyblock-beginner-guide-gemini.md`: Gemini notes on the first 10 minutes, which include narration.
- `osrs-starter-guide.md` and `osrs-complete-guide.md`: interface, systems and progression. Prioritised lists at the end.

Ignore any low-poly or flat-shaded recommendation in these notes (owner direction).

Gemini video access (the `watch` skill) uses a free-tier key with 20 requests a day.
- The previous session scheduled a resume of the segmented YouTube pass at 08:10 UTC on 2026-11-21. Its scratchpad script and notes live in the old session's `/tmp` scratchpad and may not exist in a new environment.
- YouTube blocks direct downloads from the cloud container. The owner shared the downloaded videos through a Google Drive folder instead.

## 7. Talking to the owner

- Reply in plain language: what changed, what's verified, what needs a play-test.
- Ask before merging or publishing the PR.
- Never echo secrets. The owner pasted a Gemini key in chat earlier, and it is stored only in `~/.config/watch/.env` in the old container.

## 8. Update (2026-11-23)

Merged and pushed since the first pause (all 37 suites pass), each with an independent QC review and a fix round: §33 Systems Depth (quest helper, goal board, price history with its own auction history key, per-item daily shop stock, calculator), §34 HUD Depth (action label, status orbs, chat tabs, pickup feed, tooltip footer, hitsplats/bars), §35 Lighting (single client lighting director, region profiles, graphics tiers, saved settings), Polish (renames, Hollow Sunder, sell quantity, worker-unlock toasts, journal mode as the Path's first step, vent FX), §36 Isle Council (elections; MemoryStore ballots; Renown 5 to vote) and §37 Beaconry (firemaking-style skill, beacons, campfire cooking; keeper Old Hesketh Ashby).

Live game: still the publish from PR #5. Everything above is on `claude/pensive-maxwell-145p0c` waiting for the owner's go-ahead to publish (new PR into `main`).

## 9. Animation depth (§47, 2026-11-24)

The owner wants interact and swing animations on every gather and interaction, and animations that keep improving. §47 in the contract has the details; `verify-animations.luau` guards them (every prompt verb in the server sources must map to its own gesture, joint ranges, strike cadence against `Data.Strike`, combos, reduced motion, replication budget). Ideas for the next pass: per-weapon trails on combo finishers, a parry / block pose once shields exist, footstep dust on the landing squash, and sound per interaction (the `IsleImpactLocal` hook fires for every impact).

## 10. Update: §46 Gathering Hearts

Heart of the Deep (Mining, Deepdust), Rootheart (Woodcutting, Rootsap) and Loamheart (Farming, Loamglow): 15-perk tiered lattices, tree XP tiers 1–7, currency per struck-node break, one ability each (Deepcall Surge, Rootquake, Bountiful Reaping; key G or the HUD chip), respec for coins with a 75 % refund. Menu › Hearts (new Menu tile, 15 with §45 Combat Feats); QC round fixed (fortune inside the 99 budget, Bountiful +60 + double Loamglow, shared regrowth cap, Rootquake never evicts), `hearts.client.lua`, `verify-hearts.luau`. Caps, numbers and the XP / hour effect (≤ +10.6 % per node from the regrowth perks) are in contract §46. Needs a Studio check: lattice readability, chip placement, VFX brightness, and the 20–30 h per tree pacing.

## 11. Update: §50 Ambience

A client ambience layer on top of the §35 director (`shared/Ambience.lua`, `ambience.client.lua`, `weather.server.lua`; `verify-ambience.luau`): server-time wind with travelling gusts swaying forged trees, crops, flowers, banners and lanterns (vertex-free CFrame pivots, BulkMoveTo); foam surf on island rims and ponds, waterfall sheets and spray, fishing-spot shimmer and a parallax cloud sea; region motes, fireflies, embers / spores / void sparks on sources, boid flocks at landmarks; a deterministic weather schedule published as one workspace attribute `IsleWeather` (rain with splashes and a wet-sheen lighting delta, snow on Skyreach, fog, storms with server-synced lightning flashes); hit sparks per node material, a level-up burst + sound cue, Data.Rarity-coloured drop pillars and XP orbs. Budgets per tier (High / Balanced / phone Lite / Performance), reduced motion and the Studio-eyeball list are in contract §50. Cosmetic only: weather changes no gameplay.
## 11. Update: §49 Runebinding

A 24th skill modelled on OSRS Runecraft: mine Aether / Lucent Shards in the Shardhollow (a pocket isle behind the Shardgate on Compass Quay, taught by Maelis Quillstone, the Runebinder), carry them (28 in the satchel plus five shard pouches that wear and get repaired) through the Waygate to eleven forged Binding Altars across the regions, bind runes with level multiples and six combination runes. Runes pay for spell glyphs one for one (combination and Astral / Crown wildcard runes too; elemental staves still cover their element). The Glyph Rift is a server-timed team round (fragments, essence, two rotating guardian portals, a Guardian power goal) paying Rift Points for pouches, the Shardweave outfit and the Riftlight Lantern. Two side quests (Whispers in the Shard, Heart of the Rift). `runes.client.lua` draws the pouch chip, Rift HUD, waygate picker and altar VFX; `verify-runebinding.luau` guards it. Numbers (≈ 92 h to 99, XP/h vs Mining, Rift rates, no-mint values) and the Studio checklist are in contract §49.

## 12. Update: §51 Skysailing

A 25th skill on OSRS Sailing concepts, fitted to the sky. Build an airship at the **Shipwright's Slip** on your home island through a Construction-style component tree (hull Skyskiff → Windsloop → Aether Galleon, sails, keel, plating, deck cannons, cargo hold, salvage grapple; materials from the other skills plus salvaged Sky Driftwood; components are never items, so no coin path). Sail out from five **skydocks** (Compass Quay, Brassfall, Windpine, Skyreach, Tidewater) or your home berth: the vessel is a server-checked, captain-owned assembly (`sailing.server.lua` hosts it; the Skysailing block in `server.server.lua` checks every pose for speed, climb, altitude and bounds and tows cheats in). The §50 wind field drives speed through the sail trim; storms batter the hull. Activities: chart 18 reefs / wrecks / landmarks between the regions, timed cargo contracts between the ports (bonded, paid from a capped Harbour Purse under half the Mining coin rate), grapple salvage, reef fishing from the deck, and sky corsairs (sea-creature tickets fought with the existing combat system and the new deck cannons via `ServerStorage.IsleCannon`). Other players board as crew (helm / sails / cannons) and share 50 % of activity XP while active. Every despawn lands everyone on a dock first. `sailing.client.lua` draws the ship HUD (heading, knots, wind arrow, hull, trim), the shipwright and harbour pickers, forged hull meshes and local cloth sails that belly with the wind. `verify-sailing.luau` guards it. Numbers (≈ 69 h to 99, contract XP/h 0.53–1.17× Mining) and the Studio checklist are in contract §51.
## 13. Update: §52 NPC art and item icons

Every one of the 49 townsfolk now wears forged smooth outfit pieces (35 meshes in `art/OutfitCatalog.lua`: hats / hoods / helms, cloaks, aprons, mantles, satchels, tabards, belts, scarves and trade props) chosen by `shared/NpcStyle.lua` (trade, dyes, region palette), plays a trade idle loop (smith hammering, angler casting, scholar reading, Maelis Quillstone tracing glyphs, Old Hesketh Ashby poking embers, Pell waving …) through the NPC motors' C0 in `npc.client.lua`, and has a polished nameplate (region accent, trade medallion, contrast-checked). Item icons everywhere are the procedural vector icons in `shared/UiTheme.lua` (92 data-driven families, rarity halo / gem, Condensed / Radiant blocks, an LRU template cache; live 3D thumbnails only for ≥ 56 px previews). Tests: `verify-npcart.luau`, `verify-icons.luau`. Studio checklist in contract §52.
## 14. Update: §53 The Sundered Sky

An original eight-chapter main story in the OSRS quest style across every region (`Data.Story`, the Story block in `server.server.lua`, `story.server.lua`, `story.client.lua`, Journal › Story, the Story section of `combat.server.lua`). Chapters gate on skills (Runebinding, Skysailing, Beaconry …), Quest Points and quests; steps are talks, strikes / kills / crafts counted since the step, a beacon lighting, a real airship voyage, three server-held puzzles (rune lock, constellation rings, signal mirrors) and three instanced bosses with unique mechanics (Gloamwick's moving lantern light, Vaelith's Stormcross, Caedmon's Unravel beam and Sunder). Rewards: 18 Quest Points (in the Journal total), level-scaled XP lamps, six untradeable uniques and the Loomheart fast-travel node. Eleven skippable cutscenes; nine voiced NPCs, 39 dialogue nodes. `verify-story.luau` guards it; the Studio checklist is in contract §53.

## 15. Update: §54 Island environment art

The islands themselves got an environment pass, all client-side and decorative (no server parts, `world.server.lua` untouched, gather nodes untouched).

- **Forged ground tops:** each meadow becomes a gently undulating mesh, flat around paths, buildings, prompts and nodes. It has per-vertex grass patches, worn dirt fraying from every path, darker turf at the rim, and an edge that rolls over onto the cliff curb.
- **Dressing:** instanced forged grass, flowers, pebbles, stones and outcrops; bushes, ferns and reeds by water; six tree species (broadleaf, blossom, willow, spire pine, mushroom, crystal) with 3+ per biome; a hero silhouette tree per region.
- **Cliffs and undersides:** hanging roots, vine curtains, crystal veins, and 2–6 satellite rocks per island. The hulls are now smooth strata with overhangs.

The meshes are 22 smooth shapes in `art/TerrainCatalog.lua`. The rules live in `shared/TerrainArt.lua`, and the client in `terrain.client.lua`, which uses the forge's new dress and ground pools. Tier budgets: High / Balanced / Lite (phones) / Performance, with far LOD by radius. Grass and trees sway through §50. Tests: `verify-environment.luau`. Previews: `docs/screenshots/environment-*.png`. The Studio checklist is in contract §54.

**§54 QC round.**
- **Per-vertex colour for every catalog.** The forge now diffuses each face's palette colour, with an AO height ramp and soft mottling, over the vertices of its material family. Colours turn into smooth gradients everywhere; material seams such as bark against leaf stay sharp.
- **Stricter smoothness metrics** live in verify-mesh. All 30 terrain shapes and the island hulls pass them. The other teams' organic shapes (131 of them) do not yet, and need re-authoring; until then they are held to a ratchet baseline (`art/organic-baseline.json`).
- **Islands have thick cliff walls,** `clamp(R*0.18, 10, 30)` studs (lead decision). Near islands get a forged wall at absolute size: a turf lip, a soil band, then strata.
- **Near and far tree LODs.**
- **All the client findings are fixed:** backoffs, quiet-model re-planning, 2 ms slices, oriented footprints, skirt and SwayRest. Details are in contract §54, "QC round".

## Pause point (2026-11-25)

Published live (all via PRs into main, each QC-reviewed with a fix round): §45 Combat Feats, §46 Gathering Hearts, §47 animation depth, §48 creature art, §49 Runebinding, §50 ambience/weather, §51 Skysailing, §52 NPC outfits + item icons, §53 The Sundered Sky, §54 island environment + per-vertex colour. The final publish adds §55 (62 organic shapes re-authored to the strict smoothness bar) — this one was NOT independently QC-reviewed (owner asked to publish before their usage ran out).

Open work for the next lead:
- QC review of §55, then a phone performance check (world/outfit forge triangle budgets were raised substantially; see contract §55).
- Re-author the 64 creature shapes and 5 legacy world shapes still in `art/organic-baseline.json` (keep within rig budgets; packer vertex limit 4,095).
- Cliff-wall detail (strata bands, ledges, crystal cracks) from §54's open list.
- CI: Windows build job limit is 35 min and publish 45 min; the suite count keeps growing, watch run times.
- Everything visual still needs a Studio play-test (each §'s "Needs Studio check" list).

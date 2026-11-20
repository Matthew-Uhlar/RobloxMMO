# Aether Isles development status

Updated November 19, 2026. The full original goal remains in progress.

- Roblox universe **10777817254**, place **73453386951995**: [experience](https://www.roblox.com/games/73453386951995/).
- Repository: [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO).
- Latest integrated verification: **371 gameplay, 10,702 world/mesh, 45 expedition and 47 co-op checks**, plus **nine packaged scripts/modules** matching source and compiling.
- All eight cloud scripts matched the **Skyreach** source at `975be9c`. Deployment of later Observatory, bank and trade updates is **unknown** pending a publish receipt/version check.
- Studio currently displays **Public, ages 16+**, according to the primary-agent observation. Audience settings are separate from code deployment and have not been independently join-tested.

## Wave 2 (November 20, 2026)

- **Economy:** Bazaar standing buy orders for every resource/material (escrow, price-then-FIFO matching, claim/cancel, instant sell into bids, spread) and a gear Auction House (buy-it-now, 1% listing-fee coin sink, 24h expiry and return, claimable proceeds). Shared keys stay bounded (< 512 KB worst case after receipt pruning), each player has a DataStore request budget, browse reads are cached per server, and orders carry nonces for exactly-once replay.
- **Dungeons:** Observatory Floors I–V gated by Dungeoneering, cumulative mechanics (ordered prisms, shield phases, add waves, enrage) and telegraphed boss attacks; S+–D grading from time/deaths/mistakes scaling XP, coins, essence and a Magic-Find chest; Starwright Regalia set, three weapons and two accessories. Matchmaking pad, 90 s credit cooldown, contribution/damage-share credit, run cap and AFK removal.
- **Quests & construction:** 13 new main/side quests with Quest Points, choose-a-skill XP lamps and unlocks; achievement diaries for seven regions (Easy–Elite, 112 tasks) with permanent perks; Carpentry construction on a per-home Builder's Terrace (7 hotspots, 15 furniture pieces: home stations, accessory slots, worker speed, stat perks, region portals).
- **Visual QA:** a layout emulator (`tools/render-ui.luau` + `tools/rasterize-ui.py`) renders every atlas page at desktop and phone sizes. Three render–inspect–fix passes fixed invisible rarity/selection rims (UIStroke mode), sub-12px phone text, HUD/banner overlaps, cramped badges and tool tiles, and inconsistent cards. Curated renders: [docs/screenshots](docs/screenshots/README.md) — approximations, not Roblox captures.
- **QC:** an independent wave-2 review found no item/coin minting; its 8 findings (key growth and lockout, request budget, AFK/leech dungeon credit, chest messaging, rollback replay, lamp gates) were fixed with regression tests.

## Depth update (November 19, 2026)

Built by five parallel teams (Server, Combat, World, UI, Art) against the shared contract in [docs/DEPTH-CONTRACT.md](docs/DEPTH-CONTRACT.md), then integrated and reviewed by the lead.

- **Shared rules** (`shared/GameData.lua`, `shared/Progression.lua`): OSRS experience curve (levels 1–99, 13,034,431 XP at 99, 200M cap) across 12 skills; SkyBlock-style stat sheet (Health, Defense, Strength, Crit Chance/Damage, Speed, Intelligence, fortunes, Magic Find, Pet Luck) with per-level skill rewards and level-up coins.
- **Content:** 148 items and 95 recipes — 26 gathering tiers across Mining/Woodcutting/Fishing/Farming with tool-tier gates and fortune; six metal tiers of ingots, swords, four-piece armor sets with set bonuses and tiered tools; cooking ladder and feasts; ten timed potions; 14 accessories with Magical Power; 8 levelling pets; 7 enchantments; nine-tier collections that unlock recipes; bestiary milestones.
- **Combat:** 13 original real-time creatures with AI, aggro/leash, damage numbers and crits (SkyBlock damage formula), and three four-tier slayer lines with summoned bosses and slayer levels.
- **World:** Guild Terrace with Forge/Hearth/Cauldron/Workbench stations, Slayer master and boards; Meadow Reach, Cinder Shelf and four gated regions (Windpine Grove, Gloomhollow Caverns, Tidewater Shoals, Tempest Spire) with server-checked warps, nodes for every resource tier and monster spawns.
- **UI:** six-tab atlas (Journal, Hero, Satchel, Workshop, Hunt, Ledger) with Skills, Gear/stat sheet, Enchant, Accessories, Pets, rarity item grid, Collections, station crafting, Slayer and Bestiary pages, plus an action-bar HUD with XP popups and level-up banners. Phone landscape uses a left tab rail.
- **Art:** 27 new original tintable low-poly icon shapes covering every item family, an icon renderer and preview sheet, and tinted ore-crystal polish on tier nodes.

**QC pass:** two independent reviewers audited server/combat and client/world code; two fix teams resolved all 24 findings with regression tests — notably free healing from gear toggles, market DataStore spam (6 s exchange cooldown), swing-cooldown drift, server monster replication load (shared per-tick player snapshot, sleep/limb-rate limits), same-server rejoin duplication (per-session lease tokens), per-triangle wedge fallbacks in world art (bounded proxies), warp landings inside monster aggro, and phone-landscape HUD overlap. Resource nodes now regrow per player (`respawn` seconds).

Known follow-ups: expedition clears have no cooldown (Stormglass farming) and Ironman expedition credit is looser than open-world combat; balance of the OSRS curve against current XP rates needs playtesting.

Verification after integration: 959 progression/data, 837 gameplay/depth, 27,476 world/mesh, 45 expedition, 47 co-op, 328 combat and 1,246 UI smoke checks, plus 13 packaged scripts compiling and matching source. These are headless checks with service doubles; the Depth update has **not** yet been play-tested in Studio or deployed.

## Implemented source

- Private home islands, shared hub, gathering destinations, travel prompts and fixed Garden/Lanterns/Deck improvements.
- Ten XP tracks, lifetime collections, server-supplied recipe metadata, enchanting and equipment effects.
- Mining 3 Aetherite, repeatable Alloy/Aether Ingots, Reinforced Pickaxe yield and Skyplate defense.
- Eight contracts, persistent Skyreach charter, Brassfall Quarry transit, server-validated survey and rich Aetherite seams.
- Three independently assigned/upgradable workers with capped offline production and visible owned stations.
- Three Warden hunt tiers, eligible-participant rewards, Ironman restrictions, and the five-role prism/guardian/core Observatory expedition.
- Expedition Rations linking Fishing/Alchemy to healing with a server-enforced recovery interval.
- Four-person permanent co-op membership, explicit invitations, shared supplies/construction and separate personal progression; server-local elections.
- Bank amount/half/all transfers with revision checks, projected balances and purse death loss.
- Priced three-unit commodity asks (1–10,000 coins per lot), lowest-price matching with FIFO within each queue and legacy listings first at equal prices, capped immediate purchases, reservation/refund recovery, cancellation and sale proceeds. The UI shows quote age/price changes and requires purchase review/confirmation.
- Custom creature/prop/encounter geometry, 3D item thumbnails, original navigation/action graphics, compact menus, Forge/Workers/Home and Bank/Market/Merchant sections.

## Art delivery

The [mesh import bundle](art/import/README.md) contains 20 original shapes, 2,126 indexed triangles, a GLB and source/hash manifest. It is import-ready, not evidence of uploaded Roblox assets or integrated permanent templates. Native EditableMesh visuals retain a bounded shared cache and geometric fallback. The four world tile masters remain unintegrated.

MaterialArt provides one cached original cloth EditableImage where supported. Local allocation failed with an engine budget warning, so successful cloth rendering is unverified. Original vector graphics, stitched control/toast trim and flat artwork provide an allocation-free fallback.

## Verification

Headless suites exercise selected production logic using service doubles and geometry/packaging checks. They cover progression, region/quest gating, bank revisions, priced matching, replay/recovery and co-op coordination. They do not establish real DataStore concurrency or retention.

Recorded local Studio smoke includes all five atlas tabs and three Workshop sections on an iPhone landscape preview, native guardian/fallback core and arch art, ration use/recovery rejection, bank amount transfers and seeded priced-market buy/refund behavior. The market test changed the best ask from 25 to 30 coins without increasing the buyer's chosen 25-coin limit; a subsequent purchase at that limit returned its reservation. Temporary preview seeds were removed and the local Studio returned to Edit/default viewport.

Physical touch keyboard/controller navigation, device performance, full two-client playthroughs and live persistence remain unverified. The short phone landscape viewport requires scrolling. Detailed evidence and limitations are in [QC-REVIEW.md](QC-REVIEW.md).

## Required remaining work

- Live cross-server economy validation (standing orders and auctions are implemented and headless-tested).
- Co-op skills/workers, leave/kick lifecycle and broader shared progression.
- Seasonal events and further regions/activities beyond the current eight regions, five dungeon floors and three slayer lines.
- Free-form island placement beyond the Builder's Terrace hotspots.
- Permanent mesh import/integration, texture delivery, complete sign/menu art review and device performance measurement.
- Real multiplayer/rejoin/failure tests and requirement-by-requirement acceptance of the full original goal.
- Confirm each intended cloud update with a receipt/version check and an actual join, independently of CI and audience settings.

Automatic deployment after relevant main gameplay changes is configured in the workflow; manual publication on main remains available. Both require the credential and verification steps in [PUBLISHING.md](PUBLISHING.md). No source or CI milestone alone completes the game or proves deployment.

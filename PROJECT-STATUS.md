# Aether Isles development status

Updated November 19, 2026. The full original goal remains in progress.

- Roblox universe **10777817254**, place **73453386951995**: [experience](https://www.roblox.com/games/73453386951995/).
- Repository: [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO).
- Latest integrated verification: **371 gameplay, 10,702 world/mesh, 45 expedition and 47 co-op checks**, plus **nine packaged scripts/modules** matching source and compiling.
- All eight cloud scripts matched the **Skyreach** source at `975be9c`. Deployment of later Observatory, bank and trade updates is **unknown** pending a publish receipt/version check.
- Studio currently displays **Public, ages 16+**, according to the primary-agent observation. Audience settings are separate from code deployment and have not been independently join-tested.

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

- Standing buy orders, gear auctions and live cross-server economy validation.
- Co-op skills/workers, leave/kick lifecycle and broader shared progression.
- Deeper regions, activities, build choices, Slayer target variety, dungeon content and seasonal events.
- Wider island construction/placement and persistent utility layouts.
- Permanent mesh import/integration, texture delivery, complete sign/menu art review and device performance measurement.
- Real multiplayer/rejoin/failure tests and requirement-by-requirement acceptance of the full original goal.
- Confirm each intended cloud update with a receipt/version check and an actual join, independently of CI and audience settings.

Automatic deployment after relevant main gameplay changes is configured in the workflow; manual publication on main remains available. Both require the credential and verification steps in [PUBLISHING.md](PUBLISHING.md). No source or CI milestone alone completes the game or proves deployment.

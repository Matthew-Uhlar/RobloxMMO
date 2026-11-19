# Aether Isles development status

Updated November 19, 2026. The full original goal remains in progress. Aether Isles is an evolving playable implementation, now privately published to a new Roblox experience through Studio.

- Roblox universe: **10777817254**; place: **73453386951995**. [Experience](https://www.roblox.com/games/73453386951995/)
- GitHub destination: [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO). The initial main build passed and produced a downloadable Roblox place.
- Latest integrated verification: **236 gameplay assertions, 10,575 world/mesh checks, 45 expedition checks, 47 co-op checks, and nine compiled packaged scripts/modules**.

The Observatory update adds Expedition Rations, custom sentinel, portal and astrolabe meshes, combat-state artwork, and an original woven UI texture. The four world-material tile masters are in the repository. Their world-surface integration is pending.

## Implemented source

- Personal island, central hub, gathering locations and travel prompts.
- Ten experience tracks, lifetime collections, recipe gates, enchanting and crafted equipment.
- Priority 1 progression slice: Mining 3 Aetherite, repeatable Alloy/Aether Ingot production, Reinforced Pickaxe gathering bonuses, Skyplate defense, and server-supplied recipe metadata. A fresh-profile test follows the full chain.
- Priority 2 bounded slice: eight guild contracts, claimed Skyreach charter, Quarry transit to Skyreach Heights, server-validated survey, rich Aetherite seams, persistent unlocks and one-time rewards. This does not complete the full quest/region backlog.
- Three independently assigned/upgradable workers with capped offline skill XP and visible home stations; bank, death purse loss and fixed-price commodity exchange.
- Three tiers of repeatable Warden hunt contracts with eligible-participant rewards.
- Persistent four-person co-op membership, explicit invitations, shared island supplies and three shared construction upgrades; separate personal inventory and progression.
- Ironman restrictions, shared Warden combat and observatory puzzle encounter.
- Server-local gathering elections.
- Expanded original low-poly prop/creature geometry and OBJ masters, shared `art/PropCatalog.lua`, native mesh rendering with geometric fallback, and 3D item thumbnails.
- Field guide, crafting, inventory, banking and exchange interface; Workshop split into Forge/Workers/Home, wrapping cards and region guidance.

## Verification

November 19 integrated verification passed **214 / 7,081 / 25 / 47**, with **eight** packaged scripts/modules matching source and compiling. The local place was rebuilt. These suites cover selected production behaviors using service doubles and geometry validation, including the new progression chain, region gates, survey validation, migration and reward replay protection. They do not establish real DataStore concurrency, device usability, performance or retention.

Studio desktop and mobile-preview smoke checks passed on the earlier rank 1 build, with one mesh-budget fallback warning. The rank 2 phone preview opened all five tabs and all three Workshop sections. Private publishing through Studio is recorded. Full device visual review, real multiplayer and persistence failure/rejoin testing remain release requirements; publishing alone is not evidence that they passed.

## Required remaining work

- Verify islands in-engine; expand co-op beyond shared construction to skills/workers, membership lifecycle and deeper shared progression. Membership is currently permanent, with no leave/kick.
- Expand beyond the implemented skill-material chain and single charter-gated region, following the sequential priorities in `OSRS-PRIORITIES.md`.
- Verify the five dungeon classes in-engine and implement room progression and broader endgame encounters.
- Implement variable-price commodity orders and gear auctions; validate economy and co-op persistence under live concurrency and service budgets.
- Keep the source-backed research comparison and team conclusions aligned with implementation.
- Verify meshes, all menus and signs in Roblox Studio on desktop and mobile.
- Run real multiplayer playtests, persistence rejoin tests and a final requirement audit.

The working name and floating-island art direction were selected by the development team. The private publishing destination above is now established; the full original scope and public-release readiness remain unfinished.


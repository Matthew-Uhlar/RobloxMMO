# Aether Isles research and alignment review

Reviewed November 11, 2026. Research was gathered November 3–4. The implementation inventory below comes from the local source files. Engine playability, visual polish and retention require separate verification.

## Compared findings

| Mechanic | Evidence and interpretation | Aether Isles implementation |
| --- | --- | --- |
| Gathering and production skills | OSRS explicitly groups Woodcutting, Fishing and Mining as gathering, and Smithing and Crafting as production. These support a resource-to-upgrade loop. | Ten XP skills, resource prompts, crafted tools and weapons. |
| Shared economy | OSRS documents player trading and its Grand Exchange. Hypixel’s Bazaar uses player orders, instant transactions and supply-driven prices. | Persistent commodity lots with listing, buying, cancellation and seller proceeds. Prices are fixed by configuration. |
| Collections | Hypixel’s fishing update added collections with multiple rewards. This creates a second progression track tied to resource totals. | Lifetime counts and recipe thresholds for Pickaxe, Blade, Tonic and Stormblade. |
| Group challenges | Hypixel’s Catacombs introduced generated rooms, floors, bosses and classes. OSRS also supports self-sufficient group progression. | A shared puzzle/boss expedition with five roles, participation rewards and a separate Warden encounter. |
| Self-sufficient modes | Hypixel’s original Ironman announcement disabled external player trade and allowed solo or co-op profiles. | Permanent Ironman choice with blocked player exchange and independent Warden combat. |
| Social events | Hypixel elections give the winning candidate’s perks to players for an in-game year. | Server-local voting selects a temporary gathering bonus. |

Sources for the OSRS skill categories and economy are the official skill consultation and Grand Exchange poll. They support the mechanic comparison. Direct historical influence from OSRS on each Hypixel feature has not been established by these sources. [OSRS skill consultation](https://oldschool.runescape.com/polls/2023/1655), [Grand Exchange poll](https://oldschool.runescape.com/polls/2015/1190), [Group Ironman](https://www.runescape.com/oldschool/groupironman)

Hypixel’s announcements document commodity orders, collection rewards, dungeon structure, Ironman restrictions and elections. These are dated feature descriptions, so detailed present-day balance may differ. [Bazaar announcement](https://hypixel.net/threads/skyblock-patch-0-7-7-bazaar.2655146/), [Fishing and collections](https://hypixel.net/threads/skyblock-patch-0-5-fishing-achievements-and-more.2127882/), [Catacombs announcement](https://hypixel.net/threads/skyblock-patch-0-8-first-dungeon-the-catacombs.2851991/), [Ironman announcement](https://hypixel.net/threads/0-9-6-ironman-gamemode.3273590/), [Elections announcement](https://hypixel.net/threads/skyblock-patch-0-9-election-event-community-shop.3287083/)

Several former official Hypixel Wiki pages redirected to the July 2026 closure announcement during this review. The world team retrieved specific indexed minion content earlier, including capacity and resource/tool recipes. Current verification should use first-party patch announcements or current game observation. The user's supplied description is a design input, and its exact skill count and categorization remain unverified. Ironman and hardcore death rules also require separate treatment. [Wiki closure](https://hypixel.net/threads/end-of-the-official-hypixel-wiki-july-2026.6112020/)

## Roblox popularity and engagement

Roblox’s 2025 review lists Brookhaven, Grow a Garden and Steal a Brainrot as its top three searches. It reports concurrent-player peaks of 21.6 million for Grow a Garden and over 25 million for Steal a Brainrot. These establish historical reach. A representative current ranking and causal retention data were unavailable. [Roblox 2025 review](https://about.roblox.com/newsroom/2025/12/roblox-replay-decoded-search-style)

| Example | Developer-described loop | Design hypothesis applied here |
| --- | --- | --- |
| Grow a Garden | Buy seeds, plant, grow, harvest, sell, share finds with friends, including offline growth. | A clear first upgrade and capped offline worker output may give players useful return goals. |
| Brookhaven | Own homes, roleplay, explore and spend time with friends. | A personal island and recognizable shared hub may support ownership and social attachment. |
| Steal a Brainrot | Acquire income-producing characters, compete over them and rebirth. | Visible progression and a short, understandable action-to-reward cycle may improve early comprehension. |

These hypotheses derive from published gameplay descriptions. Their contribution to each game’s popularity has not been isolated experimentally. [Grow a Garden](https://www.roblox.com/games/126884695634066/Grow-a-Garden), [Brookhaven](https://www.roblox.com/games/4924922222/Brookhaven-RP), [Steal a Brainrot](https://www.roblox.com/games/109983668079237/Steal-a-Brainrot)

Roblox’s discovery documentation emphasizes first-play bounce, play days, playtime and intentional co-play among its signals. Its onboarding guidance recommends testing funnel completion and contextual instruction. The atlas therefore displays one immediate goal, named destinations, ingredient costs, and claimable progress. Evaluation should measure first resource collection, first crafted upgrade, expedition participation and return play. No player retention experiment has yet been run for Aether Isles. [Discovery FAQ](https://create.roblox.com/docs/discovery-faq), [Onboarding](https://create.roblox.com/docs/production/game-design/onboarding), [Onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques)

## Local implementation and remaining scope

| Requested outcome | Implemented in source | Remaining work or evidence |
| --- | --- | --- |
| Private island and building | Personal island, home portal, worker, persistent Garden/Lanterns/Deck purchases. | Free placement, larger construction system and shared co-op ownership. |
| Hub and dedicated islands | Compass Quay, gathering destinations, signs, stalls and portals. | Broader unlockable regions and level gates. |
| Skills and collections | Ten XP skills, collection recipe gates, Combat/Farming health, Mining defense, Alchemy, Dungeoneering and weapon enchanting. | Broader skill roster, deeper stat/build choices and a sustained content progression. |
| Economy and banking | Merchant, purse/bank, death loss, persistent player commodity exchange. | Auction House, variable-price order book, exchange capacity and recovery testing. |
| Workers | One worker with four selectable resources, skill XP and capped offline accrual. | Multiple simultaneous workers, placement, tiers and upgrades. |
| Dungeons and combat | Warden, cooperative prism puzzle and Eclipse Heart, five expedition roles, Stormglass/Shard progression to Stormblade. | Multiple floors, varied enemies, Slayer tiers, loot tables and long-term balancing. |
| Elections and events | Short server votes and temporary harvest bonus. | Calendar events, global elections and seasonal reward progression. |
| Modes | Standard and Ironman trading restrictions. | Shared co-op save/progression, complete mode isolation verification. |
| Menus and signs | Original navy/teal/gold atlas, compass and route graphics, journal, satchel, workshop and ledger. | Engine screenshot review at phone/tablet/desktop sizes and console navigation. |
| AI meshes | Original agent-authored Tidewing and Shellwarden geometry, OBJ masters and client mesh creation with geometric fallback. | Verified runtime rendering, animation/performance review and final art approval. |
| Quest guidance | Contextual geography, five sequential server contracts and claimable rewards. | Real-client quest flow and reward presentation still need verification. |
| Quality control | Source inspection, Luau analysis, and place/source verification scripts. | Recorded Roblox client tests, multiplayer economy tests, persistence/rejoin tests and device performance. |

The project currently supports a focused vertical slice of the requested game. Completing the broad brief requires the remaining systems and real-client verification above. Claims of a polished release, complete OSRS-equivalent mechanics, live deployment or proven retention would exceed the available evidence.

## Team comparison and corrections

The systems team prioritized authoritative resource rewards, persistence and recoverable transactions. The world team prioritized geographic clarity, personal ownership and original silhouettes. The interface team prioritized contextual onboarding and visible progression. Their shared design is gather, unlock, craft, earn, automate and tackle a group challenge.

The alignment review exposed missing collection gates and late-game crafting goals, which were added to the server and workshop. It also caught a commodity-specific proceeds contract mismatch, and the UI now collects proceeds for each material. The next review should reconcile the latest server quest state, expedition mode rules and home customization with the final built place.



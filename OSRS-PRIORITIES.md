# OSRS mechanics: evidence and Aether Isles implementation order

## Observatory iteration

OSRS connects resource skills to encounter preparation. The Hunter Guild poll asked about cooking hunted meat for two stages of healing. In the first private Aether Isles release, fishing supplied worker tasks and companion food, while combat healing relied on tonics. The new Expedition Ration gives fishing a combat use. It restores up to 65 health and takes 12 seconds to become available again. Those values and the single heal are original Aether Isles tuning. Check whether players actually prepare rations before entering the Observatory during multiplayer playtests. [Jagex Hunter Guild poll](https://oldschool.runescape.com/polls/2023/1677)

## Implementation checkpoint — November 19, 2026

Rank 1's bounded resource → production → useful equipment slice is implemented and integrated: Mining 3 Aetherite, repeatable Alloy/Aether Ingots, Reinforced Pickaxe yield and Skyplate defense. Rank 2 then advanced through a bounded eight-contract chain, persistent Skyreach charter, Brassfall Quarry transit, server-validated survey and rich Aetherite harvesting. Neither slice means the corresponding broad mechanic family is fully complete.

Later bounded iterations advanced rank 3 with Expedition Rations and custom Observatory encounter art; rank 4 with revision-checked whole-amount/half/all bank transfers and projected balances; and rank 5 with priced three-unit asks, lowest-price matching with FIFO within each queue and legacy listings first at equal prices, maximum-price buy reservations, difference refunds and stale-limit recovery. Standing bids, gear auctions, deeper builds and live cross-server testing remain unfinished.

Latest integrated checks: **371 gameplay / 10,702 world-mesh / 45 expedition / 47 co-op**, plus **nine source-matching compiled scripts/modules**. Local Studio smoke verified compact menus, native/fallback encounter art, ration use, amount-based banking, and a seeded buy whose best ask changed from 25 to 30 while the chosen 25-coin limit remained unchanged. This is not a live multiplayer economy test.

The last cloud code explicitly confirmed by the primary agent is **Skyreach**. Later update deployment is unknown pending a publish receipt/version check. Studio currently displays **Public, ages 16+** according to the primary-agent observation; this does not establish which code is deployed or prove audience access. Source CI and local smoke remain separate evidence.

Presentation includes custom item thumbnails, Forge/Workers/Home and Bank/Market/Merchant sections, vector action art and stitched fallback trim. The 20-shape GLB import bundle is prepared but not established as uploaded/integrated Roblox templates. EditableImage allocation failed during local smoke; successful procedural cloth rendering is still unverified.

The ranked backlog below remains the design sequence. Bounded slices do not complete an entire mechanic family; preserve the original Hypixel/Roblox scope and its remaining economy, co-op, worker, event and dungeon requirements.

Research/gameplay team review: November 17, 2026. This ranks engineering and game-design importance **for Aether Isles**, not OSRS player popularity or measured Roblox retention. Historical official polls establish proposed features and recorded voting; they do not establish a current complete mechanic specification. Aether Isles keeps original names, environments and art.

## Evidence catalog

1. **Gathering, production, combat and utility skills.** Jagex's 2023 consultation identifies Woodcutting/Fishing/Farming/Hunter/Mining as gathering, Runecrafting/Crafting/Fletching/Smithing/Herblore as production, and separate combat and utility categories. This supports an interconnected skill model rather than interchangeable XP bars. Its preference vote was about a *new skill pitch*, not which existing mechanic matters most. [Official skill consultation](https://oldschool.runescape.com/polls/2023/1655)
2. **Quests, XP rewards and encounter unlocks.** The 2022 poll covers higher-level quest XP and making a quest boss repeatable after completion. Useful adaptation: authored goals that unlock activities and explain why training matters. [Official quests and combat achievements poll](https://oldschool.runescape.com/polls/2022/1650)
3. **Equipment with stat effects and requirements.** The Wintertodt poll describes a level-gated Tome of Fire with combat effects and superior Slayer encounters. Useful adaptation: visible preparation choices and crafted upgrades that change outcomes. [Official Wintertodt and superior Slayer poll](https://oldschool.runescape.com/polls/2016/1320)
4. **Banking and a player marketplace.** The Grand Exchange poll documents replacing the Trading Post, bank collection access and added bank capacity. Useful adaptation: persistent storage, clearly separated purse risk, and recoverable player orders. [Official Grand Exchange poll](https://oldschool.runescape.com/polls/2015/1190)
5. **Slayer tasks and unlocks.** The 2015 poll describes boss-assignment unlocks, task extensions, a reward shop and changes to assignment tables. Useful adaptation: varied targets and earned choices, beyond repeating one boss with increasing counts. [Official Slayer poll](https://oldschool.runescape.com/polls/2015/1257)
6. **Cooperative self-sufficiency.** Jagex's Group Ironman page describes gathering, crafting and fighting with companions. This supports shared progression, but does not justify treating Ironman as permadeath. [Official Group Ironman](https://www.runescape.com/oldschool/groupironman)
7. **Housing and construction contracts.** The 2020 poll describes a less click-intensive training alternative, construction XP, reward points and housing rewards. [Official construction contracts poll](https://oldschool.runescape.com/polls/2020/1606)
8. **Housing utility and travel.** Poll 68 describes a house advertisement board and a construction-level/material-gated lectern. A separate travel poll describes convenient transport options. [Official house/production improvements](https://oldschool.runescape.com/polls/2019/1566), [official travel improvements](https://oldschool.runescape.com/polls/2017/1343)
9. **Collection/completion goals and shortcuts.** Poll 74 covers a collection-log-related update, a house tracker, mining rocks and an Agility-gated shortcut. Aether Isles lifetime resource collections remain primarily Hypixel-inspired; they should not be mislabeled as identical to OSRS's collection log. [Official collection log and game improvements](https://oldschool.runescape.com/polls/2021/1616)
10. **Consumables and production convenience.** The Varlamore poll describes potion-related rewards, storage and equipment effects. Useful adaptation: consumables connect gathering to combat preparation. [Official Herblore activity poll](https://oldschool.runescape.com/polls/2024/1688)
11. **Raids, community voting and PvP.** The official polling charter uses raids with combat/skilling challenges as a content example. The OSRS homepage promotes levelling, PvP and community-led development. These establish distinct mechanic families, not their relative suitability for Roblox. [Official polling charter](https://osrs.runescape.com/polling-charter), [official OSRS homepage](https://oldschool.runescape.com/)

## Ranked backlog

Scores are team judgments on 1–5 scales: **C** core-loop value (40%), **D** dependency value (30%), **U** Roblox usability (20%), **F** delivery feasibility/safety (10%; higher means lower implementation risk). Total = 8C + 6D + 4U + 2F, out of 100. Ties favor the feature that supports earlier ranks. This is a transparent prioritization method, not a statistical model or popularity survey.

| Rank | Mechanic family | C/D/U/F | Score | Aether Isles gap and acceptance target |
|---|---|---|---|---|
| 1 | Skill → resource → production → useful equipment | 5/5/5/4 | 98 | Add a genuine second material tier, a repeatable training bridge and equipment with tested yield/defense effects. Existing ten skills alone do not meet this target. |
| 2 | Quest-driven goals and region/activity unlocks | 5/5/4/4 | 94 | Expand five contracts into a readable progression path with server-enforced unlocks and a clear next activity. |
| 3 | Combat preparation, equipment and consumables | 5/4/4/3 | 86 | Add meaningful build choices and enemies that test them; verify damage, healing and telegraphs in-engine. Rank 1 supplies the initial equipment foundation. |
| 4 | Banking, inventory clarity and death recovery | 4/4/4/4 | 80 | Amount/half/all transfers and balance previews are implemented; real rejoin/failure tests, broader item handling and readable death outcomes remain. |
| 5 | Player economy and orders | 5/4/3/1 | 78 | Priced asks and capped immediate buys now exist. Add standing bids and gear auctions, then validate real concurrent servers before readiness claims. |
| 6 | Slayer-style assignments and earned unlocks | 4/3/4/4 | 74 | Existing three hunt tiers change kill counts only. Add varied targets, unlockable difficulty and reward choices. |
| 7 | Co-op and self-sufficient mode integrity | 4/3/4/2 | 70 | Shared homestead foundation exists; broader shared progression, membership management and durable mode-isolation testing remain. |
| 8 | Housing and construction utility | 3/3/5/3 | 68 | Move beyond fixed Garden/Lanterns/Deck choices toward purposeful, persistent layouts and upgrades. |
| 9 | Traversal convenience and skill shortcuts | 3/3/4/4 | 66 | Add earned shortcut routes to existing destinations after region progression is meaningful. |
| 10 | Completion logs and achievement rewards | 3/3/4/3 | 64 | Preserve lifetime resource collections; add activity/gear completion goals and explicit rewards without confusing the two systems. |
| 11 | Cooperative raids and boss progression | 4/2/3/2 | 60 | Existing five-role Observatory needs engine-tested encounters, progression and balancing before more floors. |
| 12 | Alternative training activities and minigames | 3/2/4/3 | 58 | Add variety after the core skill economy has useful destinations and outputs. |
| 13 | Social tools and group discovery | 3/2/3/3 | 54 | Improve finding a party/homestead; depends on reliable group and activity systems. |
| 14 | Community voting and recurring events | 2/2/4/3 | 50 | Existing server harvest voting needs calendar/event depth. OSRS development polls and in-world Hypixel elections are different concepts. |
| 15 | Optional competitive PvP/high-risk activities | 2/1/2/1 | 32 | Later optional extension, not a replacement for the requested cooperative game. Avoid importing risk rules without deliberate design. |

Unranked cross-cutting release requirements apply to every rank: server authority, accessible menus/signs, save migration, abuse resistance, performance, mobile/desktop playtests and original art. Worker fleets/offline automation, AI-authored meshes, Hypixel collections, gear auctions and elections remain in the original brief even though they are not all OSRS-derived.

## Sequential execution agreement

The primary agent approved rank 1 first; after integration and its checks, the primary agent authorized the bounded rank 2 slice recorded above. Bounded ranks 3–5 have since advanced as recorded above. Subsequent work continues sequentially with explicit integration and verification. Separate teams may research, review and integrate **the same rank** concurrently.

Rank 1 slice:

- Ore + Timber → repeatable **Alloy Ingot** refining at Smithing 1 (+16 XP), providing a route to Smithing 3.
- Mining 3 unlocks **Aetherite** nodes (+18 Mining XP per harvest).
- Smithing 3 combines 2 Aetherite + 1 Alloy Ingot into an **Aether Ingot** (+24 XP).
- **Reinforced Pickaxe** consumes 3 Aether Ingots, 5 Timber and the original Pickaxe; requires Smithing 3 and 6 lifetime Aetherite. It grants +2 Ore tool yield and +1 Aetherite yield.
- **Skyplate** consumes 4 Aether Ingots and 4 Herb; requires Smithing 3 and 8 lifetime Aetherite, and grants +2 defense.
- Recipe requirements/costs/effects come from server metadata. Locked requests cannot spend supplies or award XP. Workers remain restricted to the original four resources so they cannot bypass the new mining activity.

This is one material/progression slice, not a claim to reproduce OSRS's full skill depth. Balance and enjoyment remain hypotheses until client playtests. A successful headless build alone does not complete rank 1's visual/playability review or the full original game goal.

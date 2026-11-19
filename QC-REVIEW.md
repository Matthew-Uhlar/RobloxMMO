# Independent quality-control review

Reviewed November 15, 2026 against the Aether Isles continuation brief. This review separates source behavior from Roblox engine evidence.

## Baseline evidence

`build.ps1` passed on the initial continuation files: 84 gameplay/market assertions, 2,119 world/mesh checks (535 parts, 33 prompts, 30 sign surfaces), 25 expedition behavior checks, and packaging/source/compilation checks for six scripts.

The gameplay suite exercises production source with deterministic service doubles, including a lost market acknowledgement after a durable commit and purchase replay on rejoin. It does not simulate overlapping UpdateAsync requests, callback retries, server shutdown time budgets, Roblox network timing, or actual DataStore service availability. The expedition suite covers prism and guardian gates, role behavior, pulse damage, contribution rewards, victory reset and distant entry rejection. The world suite checks generated instances and geometry; it is not a screenshot or usability test.

## Findings sent to development

1. **Warden participation rewards:** baseline rewards only require a loaded profile in the historical hit set. A player can tag the boss, leave the arena or die, then receive the eventual kill reward. This is particularly relevant to new Slayer progression. Requested alive, nearby, valid-session checks and regression coverage from the systems developer.
2. **Small-screen text overflow:** baseline atlas rows use fixed 30-pixel detail areas, narrowed further by action buttons. Longer instructions can require more lines on phones. Notices also have a fixed height. Requested responsive sizing from the interface developer. Source fixes still require engine review.
3. **Nested save snapshots:** the baseline save snapshot clones only the four existing flat maps. New worker tables and nested Slayer state must be copied before asynchronous saves to avoid later mutation changing an in-flight payload. Communicated to the systems developer.

## Full-goal audit

| Requirement | Baseline evidence | Still needed |
| --- | --- | --- |
| Original research-informed design | RESEARCH.md contains first-party historical comparisons and explicitly qualified engagement hypotheses | Current representative popularity evidence and actual retention/playtest evidence |
| Customizable private islands | Personal homes and three persistent upgrades | Broader placement/building and engine usability |
| Shared co-op progression | None established | Persistent shared membership, island ownership and save coordination |
| Worker automation | One assigned worker with capped offline accrual | Multiple workers, tiers, placement and migration (development underway) |
| Skills, collections and equipment | Ten XP tracks, recipe gates, equipment/enchanting and pet bond | Sustained activity variety, gated regions and deeper builds |
| Player economy | Fixed three-unit commodity lots with reservation/receipt recovery | Variable-price order book, gear auctions and real concurrency tests |
| Bank and death | Separate bank and purse, 10% purse loss | Engine death/rejoin validation |
| Cooperative dungeons | One prism/guardian/core expedition, five roles | Engine balance, richer floors/enemies/loot and multiplayer reliability |
| Slayer progression | Warden kill count only | Tiered contract system (development underway) |
| Elections/events | Server-local ballots and harvest bonus | Calendar/seasonal progression and wider election scope |
| Modes | Standard/Ironman exchange separation and solo Warden state; Observatory cooperation explicitly allowed | Co-op mode and wider mode-isolation tests; no hardcore death mode is implied |
| Meshes and presentation | Original geometry, EditableMesh creation with wedge fallback, companion source | Engine rendering, device performance and visual approval |
| Menus and signs | Atlas, HUD, signs and prompts implemented | Phone/tablet/desktop screenshots, navigation and readability review |
| Persistence and release | Session lease and local build checks | Live multiplayer/rejoin/failure tests; no verified publishing destination |

The full original goal remains unfinished. Passing these checks is evidence for selected behaviors, not proof of a polished, complete or published game.

## Continuation source review — November 16

The saved development changes implement three independently assigned workers, tiers 1–3 (120/90/60-second cycles and 120/180/240-unit capacities), legacy first-worker migration, and flat persistent Warden hunt state with three contract tiers. Tier 3 is repeatable. UI action names, displayed build/upgrade costs, assignment payloads and hunt rewards agree with server code.

The Warden reward finding is fixed in source: recipients now need a living humanoid, root within 40 studs of the encounter, and valid session lease (or Studio preview). Worker save snapshots clone each worker record. Atlas rows now stack wrapping auto-height title/detail above their actions; notices grow vertically. These are source corrections, pending engine review.

An independent build against these saved changes passed the same 84/2,119/25 checks and six-script packaging check. At this checkpoint the newly added worker slots, upgrades and Slayer behavior did not yet have dedicated new regression assertions; the systems developer was asked to add them. No new blocking defect was found in the reviewed source. Minor eligibility text was flagged because accepting a hunt seals the progression charter before harvesting or battle.

The feature audit above describes the baseline; worker tiers and tiered hunt contracts have now advanced in source. Shared co-op saves, variable-price orders, auctions, world placement of multiple workers and the other listed full-scope gaps are still outstanding.

## Final independent regression pass for this slice

After the systems developer added dedicated feature regressions, QC independently ran `build.ps1` successfully: **128 gameplay/market assertions**, **2,119 world/mesh checks**, **25 expedition checks**, and **six packaged scripts matching source and compiling**. The 44 additional gameplay assertions cover legacy worker migration, sequential slot purchase and costs, invalid slots/resources, tier rates and capacity, capped independent offline output, repeated claims, assignment changes, rejoin, earned output during upgrades, accepted-hunt progress, tier progression/repetition, duplicate reward claims, and dead/distant Warden contribution exclusion. Inspection confirmed these tests execute production source.

Ironman eligibility copy now states that it must be chosen before starting progression. The interface developer also restores gamepad focus after rerenders and refreshes the snapshot when opening the atlas. No further blocking source finding was identified in this slice. Real engine/mobile/gamepad behavior and live persistence concurrency remain unverified; the overall game remains in progress.

## November 17 review in progress

Reviewed worker world pads and co-op source integration. Worker status attributes match the world listeners; pads carry server-checked owner/slot actions, and attribute subscriptions are cleaned up with home removal. The world developer added coverage for pad containment, restored assignments/tiers and prompt changes.

QC found a persistence lease defect: opening/saving a profile used acknowledgement time plus 180 seconds as the local lease deadline, even though the stored deadline was created earlier inside UpdateAsync. A delayed acknowledgement could therefore authorize work beyond the actual lease. Root changed both paths to use the committed record expiry and made expired reservation saves fail before market access. QC added delayed-acknowledgement tests for open, save, blocked market access and recovery, plus co-op eligibility/mode sealing and worker attribute tests. The gameplay suite passes **140 assertions**.

Co-op review identified a failed-join reservation that could lock a nonmember to a full or expired-invitation group. This was sent to the systems developer for a cancellation/recovery fix and a regression. Full integrated build and final co-op review remain pending.

## Root integration verification — November 17

The saved co-op fix revokes the exact invitation token before clearing a failed membership reservation, preserving ambiguous-write recovery. Root reviewed the saved service/test code and wired it into Rojo, the build and package verifier. The new tests exercise production code, repeat UpdateAsync transforms, inject precommit failures/lost acknowledgements, and cover explicit consent, capacity, mode separation, rejoin and shared construction. They do not prove arbitrary live concurrent execution.

Root also integrated shared Crew Haven geometry/travel/supply prompts and tested one island per crew, construction restoration, member departure cleanup and preview/live separation. QC had flagged possible mixed preview/live geometry; namespace and prompt environment checks now separate them.

Final root-run build passes **140 gameplay, 2,243 world/mesh, 25 expedition and 47 co-op checks**, plus seven packaged scripts matching source and compiling. Independent agents reviewed the worker/UI/lease/co-op source during development; the final environment-isolation adjustment was root-reviewed and regression-tested after agents hit usage limits. This is not an independent engine approval.

Outstanding: actual Studio/client/device playtests, live DataStore budgets/concurrency, variable-price orders/auctions, deeper co-op skills/workers, membership leave/kick, broader regions/activities, seasonal events and dungeon/enemy depth. Co-op membership is explicitly permanent in the UI; shared supplies never debit or credit personal inventories. The original game objective remains unfinished.

## November 19 local Studio phone review

Interface reviewer synced current server, world, UI, mesh renderer and prop catalog only into unpublished local Studio `89e47bb8-d020-45e6-9596-f7cac607688a` (PlaceId 0). The cloud-backed Studio was not modified. Used the Roblox device-simulator skill and dynamically selected iPhone 17 Pro, landscape, matching StarterGui LandscapeSensor. Runtime viewport was 750 x 381; AetherAtlas uses CoreUISafeInsets and the compact atlas measured 730 x 303 with a 706 x 144 scrolling content region.

Screenshots verified Journal, Forge, Workers, Home, empty Satchel, Ledger and Co-op. Workshop opens with Forge recipes; companion is under Home. All five tab labels and three Workshop selectors were visible, and custom item thumbnails rendered. Lower Co-op cards remained readable after scrolling; wrapped labels had no measured TextBounds overflow. The short landscape viewport requires scrolling to expose lower portions of cards/action buttons, which is expected but remains a usability tradeoff.

J opened the atlas. Selecting visible buttons through GuiService and sending Return activated tabs/selectors via normal input. Mouse simulation and ButtonA did not reliably activate in this run, so this is not a physical touchscreen or controller pass. The console contained one EditableMesh-budget warning, followed by functioning geometric fallback; repeated allocation-warning spam was not observed. This does not establish device frame rate or memory suitability.

Play was stopped and Studio returned to Edit with device simulation set to default. No publication occurred. Subsequent consumable/control-texture edits require a fresh runtime check.

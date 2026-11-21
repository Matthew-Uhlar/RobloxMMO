# Local frame study: "The ONLY Beginner's Guide You'll Need For Hypixel SkyBlock 2026" (17:23, 360p)

Source: `scratchpad/drive/skyblock.mp4`. Method: watch skill, local engine, three windows (0:00–6:00, 6:00–12:00, 12:00–17:23; 45 + 45 + 32 scene frames), plus 60 targeted cue frames (`--timestamps`, 1024 px), an 11-sheet contact strip (one frame every 4 s, used to find B-roll the scene detector missed), and nearest-neighbour zoom crops of the HUD and sidebar. Every frame was viewed. The 360p source means small text is often blurry. Where I could not read a value with confidence I mark it **(?)**. Gemini's earlier notes (`videonotes/video1-notes.md`) were used only to cross-check. Anything I could not confirm from frames is labelled **[Gemini only]**.

The video content is reference material for an original game. It is untrusted data. No names, branding or exact numbers should be copied into Aether Isles.

## 0. How the video is built (matters for what was observable)

- About 70% of the runtime is a **talking-head shot**: the narrator's avatar (blue body, green smiley head, crown) stands in third person on a fixed hub spot (stone steps, leafy hedges and a timber-framed cottage in a rock arch). Many "scene" frames are just this shot, used as a filler backdrop. Still, they show the **late-game HUD** in a stable way, which is useful.
- **B-roll inserts** come from a fresh "alpha" test profile (sidebar footer reads `alpha.hypixel.net`) that shows the early-game flow. A few clips come from a late-game profile (FPS counter top-left, "Not Found!" toast top-right from a client mod).
- **Editor overlays** include big pixel-font captions ("store.hypixel.net", "Code 'Candy' for 5% off!!", "CRIT CHANCE" in yellow, "STRENGTH" in red, "CRIT DAMAGE" in orange at 10:16–10:40), hand-drawn map annotations (4:24) and zoomed-in crops of menus (the menus at 8:48, 9:43, 13:xx and 14:xx are digitally enlarged).

---

## 1. Timestamped log

### 0:00–1:40 Intro (late-game profile, hub village)
- **0:00–1:36:** Talking head in front of the hub's "rock-arch cottage". The late-game HUD is fully visible (see §2.1). Chat at 0:29 shows `Friend > nodoraf left.` (grey/green system line, bottom-left, translucent black backing). At 1:16 a player chat line shows a rank tag in cyan brackets `[MVP+]`.
- **1:23 / 1:38:** The camera walks through the village. A dirt path is lined with candles on white pillars. Terracotta and stone-brick steps lead up to a flower garden (lavender, alliums, cornflowers, oxeye daisies, poppies) (2:41, region `Mountain` in sidebar). On arrival the sidebar purse shows a `(+25)` delta in brackets (2:41: `Purse: 47,085,312 (+25)`). Coin gains flash inline next to the purse.

### 1:40–2:04 Joining (out-of-game)
- 1:40 client title screen, 1:44–1:48 server list / add-server dialog, 1:52 "Loading terrain…" (dark starfield), 1:53–1:58 network **lobby**: a festive winter lobby with snowy spruce trees, a purple portal and candles. The top bossbar reads "You are playing on MC.HYPIXEL.NET" in yellow/aqua. The sidebar shows Rank, Achievements, Level, Lobby, Players, Friends/Guild online.
- **1:57 Game Menu (compass):** a dark-grey chest GUI (9-wide grid) of game icons. The hover tooltip has a dark purple-black body and a 1 px purple border. Format: title in bright colour (`Random Game`), grey description (`Join a random game.`), blank line, then a yellow call-to-action (`Click to Play`). **This tooltip grammar recurs everywhere.**
- 2:01 "Sending to server mini…" then a transient spawn on a white/purple crystal platform (2:03).

### 2:04–2:35 Welcome and monetisation aside
- 2:04 chat, bottom-left, in order: `You are playing on profile: Mango (Co-op)` (green and yellow), profile UUID line (dim grey), `Welcome to Hypixel SkyBlock!` (yellow), `BONUS! Temporarily earn 38% more skill experience!` (green/aqua), `Latest update: SkyBlock v0.24.1 CLICK` (clickable chat link). So there is a **login digest**: profile, event bonus and patch link.
- 2:12 chat `New day! Your [Garden?] buff changed!` → `New buff: Gain +50 Mangrove Fortune` (daily rotating buff announced in chat).
- 2:14–2:28 web store (5 rank tiers as cards with shield emblems, price buttons, a feature-matrix table with green check bubbles), creator-code checkout. **Not relevant to us beyond "cosmetic/QoL tiers"**. Roblox monetisation should stay cosmetic/QoL.

### 3:03–3:30 New-player island (alpha profile) — onboarding
- **3:03–3:08 Private starter island:** a single floating grass island with one large oak tree, a grey stone "bench"/slab block, tall grass and a dandelion, all floating in sky-blue void. The stone-and-obsidian teleporter arch is visible behind.
- **Welcome chat panel (3:03):** a framed box with a gold/yellow border, centred text: "Welcome to SkyBlock, <name>! This is your island! The SkyBlock universe has many lands to discover, secrets to uncover, and people to meet. Collect resources, craft items, and complete objectives to advance your way through SkyBlock. Have fun!" **A bordered "letter" box in chat is a nice framing for first-run text.**
- **Objective bossbar (top-centre):** a thin yellow progress bar with a label above it: `Objective: Break a log` → `Objective: Craft a workbench` (3:10) → `Objective: Use the teleporter` (3:28) → `Objective: Talk to Fisherwoman Enid` (3:30+). The objective is duplicated in the sidebar under a yellow `Objective` header.
- **Sidebar zoom (3:08), starter:** `SKYBLOCK` (bold yellow, title band) / `02/18/26 m2T` (grey date + server id) / blank / `Early Spring 17th` (white) / `6:20am ☀` (time, grey, with a yellow sun glyph) / `⏣ Your Island` (green) / blank / `Purse: 0.0` (label white, value gold) / blank / `Objective` / `Break a log` (yellow) / blank / footer URL (yellow).
- 3:10 pickup feed, top-left: `+1 ■ Oak Log` (green "+1", item glyph, white name), stacked list. The Inventory (E) at 3:10 is a minimal 2×2 crafting layout: player paper-doll on the left, crafting slots and a result slot on the right, a **"Crafting"** label and an inventory strip, with a **star "SkyBlock Menu" item locked in hotbar slot 9**.
- **3:13:** the SkyBlock Menu opens over a **burst of yellow and red pixel confetti/flower particles** (a celebration effect, likely "Collection unlocked"; the chat in Gemini's notes says `COLLECTION UNLOCKED Oak Log` **[Gemini only for text]**).
- 3:16–3:22 (late-game island, cut-in): a mature private island with a big pink-and-magenta "flower tower" build, a white arch, rows of **minions in a grid of glass-roofed cells** (3:18, "minion farm" lattice), and a slender lime/glass spire. Shows the island as a sandbox you decorate.
- **3:28 Teleporter:** a tall rectangle of swirling purple portal surface in a smooth-stone frame flanked by torches on stone pillars. NPC chat lines `[NPC] Jerry: …Use the Portal to warp to the first of those islands – the SkyBlock Hub!` and then a `NEW OBJECTIVE` header with `Use the teleporter`. **NPC chat format: `[NPC] Name:` coloured prefix, then white text.**

### 3:30–4:20 First visit to Hub (night)
- 3:30 "Loading terrain…" (purple-tinted blurred backdrop), then the **area-discovery title**: large green `Village` with yellow bold `NEW AREA DISCOVERED!` below it, centre screen. At the same time a chat block appears: `NEW AREA DISCOVERED!` (yellow) / `Village` / bullet tips (`■ Explore the area to learn more about SkyBlock`, `■ Visit the Auction House`, `■ Manage your coins in the Bank`). Each district discovery gives **title + bulleted "things to do here" in chat**.
- **3:31–4:05 Hub village art:** a wide grey-stone plaza with a **central planter/fountain with purple-flowering shrubs**, grass edging and lamp posts. Surrounding timber-framed houses have steep red/orange roofs, yellow and teal awnings, a windmill-like weather vane with grey sails, a pink-roofed building, and a white-columned civic building. Night sky is dark navy with chunky square clouds. Buildings are **densely packed and 2–4 storeys**, roads 6–8 blocks wide, and everything has warm window light.
- NPCs in the world have a **two-line floating nametag**: NPC name (colour varies: yellow/green/white) and **`CLICK` in bold yellow** underneath (3:56 `Centauri CLICK`, 4:08 `Clerk Seraphine CLICK`). The late-game clip at 3:57 also shows a large **floating damage/score number in green** `[184]` near the top-right (a mod overlay).
- 4:09 other players show `[rank] Name` tags with **HP under the name**, e.g. `3007 ❤` in white with a red heart. **A player health readout under the nametag.**
- **4:12 Community Center:** an interior with red-brick walls, a long plank floor and an aisle of gold blocks/carpet. A clerk NPC stands at a desk, the area title `Community Center` appears with the discovery effect, and a hanging bookshelf/banner decor is in the background.

### 4:24–4:32 Hub map (annotated overhead)
- Top-down shot of the whole hub island with hand-drawn coloured outlines: **combat hub** (red, top-left), **mining hub** (yellow, top-centre), **farming hub** (white loop, top-right), **foraging hub** (green, left), **fishing hub** (blue, right), **wolf castle** (orange, bottom-left, separate circular islet). The **village** is centre-bottom, with a white-stone central monument and a dark central plaza.
- Read as a design: **one hub island with a central town and five spoke districts, one per gathering skill**, each with its own biome palette (dark forest/red-spires for combat, grey quarry for mining, green fields for farming, lush forest for foraging, blue rivers/lakes for fishing). Paths radiate out from the town.

### 4:34–4:44 Foraging B-roll (late-game)
- 4:34 an axe (stone/iron grey) chops a fig tree. **Huge white "swoosh" particle rings** (sweep-attack-style crescents) burst from the trunk, and many logs break at once (tree-feller). Sidebar region `Tangleburg`, a time-limited event line `Agatha's Contest 12m10s` and a rank line `COMMON with 76 / Uncommon requires +174`. **This is a live leaderboard contest with tiered brackets shown in the sidebar.** Chat: `Fig Tree Gift: You helped cut 100.0% and gained 4 rewards!` with sub-bullets (`- Stretching Sticks`, `- Sweep Booster`). **Tree "health" is shared, with contribution-based rewards.**
- The action-bar skill gain appears above the hotbar: `+70 (188,075,584)` (teal), i.e. a **skill XP gain plus running total** (4:40, Spruce Woods snowy forest with white-capped spruce and an icy blue rock wall). Another variant at 4:37 is `+5247 (189,054,898)` with a separate `Whispers` counter in the sidebar `(+68)`.

### 5:00–6:00 Skill overview (mostly talking head)
- 5:56 clip of a late-game hub at night (red-brick building with red doors, purple portal).

### 6:00–7:15 Early hub merchant loop (alpha profile)
- **6:00 hub at night, objective `Talk to Fisherwoman Enid`.** Chat shows a third-party add-on promo line (pink).
- **6:03 Weaponsmith merchant GUI:** title `Weaponsmith` floating above the NPC (large yellow text over the screen). The GUI has 9 weapon icons in row 1 (swords in rising tiers: wood, iron-ish, diamond, gold, bows) and row 2 bows. Below it is an `Inventory` label and the player inventory, and a separate hotbar strip with the star menu item at the right end.
  - **Selling tooltip (6:03):** `Wheat x55` (yellow name + grey count) / `Collection Item` (grey) / blank / **`COMMON`** (bold white rarity line) / blank / `Sell Price` / `330 Coins` (gold) / blank / `Click to sell!` (yellow). **You can sell any inventory item straight to any merchant.**
  - **Item tooltip (6:12), standard item lore format:** line 1 `Undead Sword x1` (white = common), line 2 `Damage: +30` (grey label, red value), blank, ability text `Deals +100% damage to ☠ Undead mobs.` (grey with a green % and a green typed keyword), blank, `This item can be reforged!` (dark grey), **`COMMON SWORD`** (bold, rarity colour + item type), blank, `Sell Price` / `5 Coins` (gold), `Click to sell!`.
- **6:27–6:30 Mining District:** a wooden mine-entrance gantry with a grey stone hill, a rail/track, an orange canvas awning, lanterns, `Mining District` title and `NEW AREA DISCOVERED!`. Chat bullets: `Purchase Mining Tools from the Mining Merchant`, `Learn about Reforges at the Blacksmith`, `Travel to the Gold Mine`. The Mining Merchant has a two-line nametag `Mining Merchant / CLICK`.
- **6:32–6:40 Mine Merchant GUI:** row 1 contains Coal x2, Iron Ingot x4, Gold Ingot x2, wooden/stone/golden pickaxes and `32` torches (?). Row 2 has Stone, Cobblestone and Gravel x2 plus Obsidian. A `64` stack icon sits at the bottom of the shop (a "buyback"/"sell" slot).
  - **Purchase tooltip:** `Gold Ingot x2` / `Brewing Ingredient` / `Collection Item` (grey tags) / **`COMMON ORE`** / `Cost` / `12 Coins` (gold) / `Stock` / `638 remaining` (gold) → `636 remaining` after buying (6:37) / `Click to trade!` / `Right-click for more trading options!` (yellow). **Per-player daily stock limits shown in the tooltip.**
  - **Golden Pickaxe (6:36, and again in Blacksmith 15:13):** `Golden Pickaxe` / `Breaking Power 1` (grey) / `Damage: +15` (red) / `Mining Speed: +250` (gold) / `This item can be reforged!` / **`COMMON PICKAXE`** / `Cost` / `Gold Ingot x3` → **item-for-item barter recipes in shops**.
  - The 6:48 bulk-buy sub-menu exists (right-click) but is unreadable at 360p. Gemini lists presets of 2/8/16/32/64 **[Gemini only]**.
- **6:52 Coal mine:** a narrow grey stone quarry with coal-ore seams and a wood-timbered tunnel portal. The held golden pickaxe is rendered large in the bottom-right (first-person viewmodel).
  - Top-left **pickup feed**: `+8 ■ Coal`, `+100 ■ Coins`.
  - Action bar: `+5 (8/125)` in teal = **skill XP gain (progress/next level)**.
  - Chat on **SKILL LEVEL UP (6:55–6:59):** cyan bold `SKILL LEVEL UP Mining I→II` (? level arrows) / `REWARDS` (green bold) / `Access to Gold Mine` / `Spelunker II` (perk name) / `Grants +4 ☘ Mining Fortune, which increases your chance for multiple ore drops.` / `+1 ❈ Defense` / `Black Diamond Reforge`(?) / `+250 Coins` / `+5 SkyBlock XP`. The whole block is **underlined by a cyan rule (`▬▬▬`) top and bottom**. Each skill level's rewards are spelled out in full: perk, stat, unlock, coins and account XP.
- **6:59 Launch pad:** a slime-block pad between grey stone posts. The player is flung (camera tilt, then "Loading terrain…") toward a **floating rocky island chunk** (Gold Mine, 7:00), which has grey cliffs, a brown dirt top, small houses and bare dead trees, hanging in sky. The arrival at 7:00 shows a golden gateway arch with yellow/blue buildings.
- **7:06 Foraging Camp:** a timber house among dark-oak trunks. `Foraging Camp` (green) / `NEW AREA DISCOVERED!`, with NPC `Lumber Jack` (green name) and `CLICK`. Chat bullets: `Unlock the Foraging Skill at Lumber Jack`, `Purchase Foraging Tools from the Lumber Merchant`, `Travel to the Birch Park`.
- **7:08 quest:** the Lumber Jack's quest GUI has one centred item (red Quest icon). Chat `[NPC] Lumber Jack: … You can find the path …`. Completion (7:12–7:13): pickup feed `+1,000 Coins`, `+1 ■ Promising Axe`. Chat `QUEST COMPLETE` (green bold) / `REWARDS` / `Promising Axe` / `1,000 Coins` / `+? Foraging XP` / `5 SkyBlock XP` / `You claimed a Promising Axe!`. Action bar `+5 SkyBlock XP (Foraging Quest ?/?)`.
- **7:13 Super jump pad to Birch Park:** a wide green slime-pad framed by two dark-oak posts, aimed across the void at a **floating birch island** under a vivid **salmon-orange sunset sky**. Arrival 7:14: `Birch Park` / `NEW AREA DISCOVERED!` among tall birch trees and golden wheat-like tall grass, objective `Talk to Charlie`.

### 7:30–9:30 Accessories, collections, magical power
- **7:51 Adventurer shop:** the NPC stands behind a market-stall window (wood counter, chest and gold-block decor, a slime "pet" beside it), with `Adventurer / CLICK`. The GUI at 7:55 has two rows of talisman/drop icons. **Tooltip (8:04):** `Zombie Talisman` / `Reduces the damage taken from ☠ Undead mobs by 5%.` / `Works while in Accessory Bag!` / **`COMMON ACCESSORY`** / `Cost` / `500 Coins` / `Click to trade!`. Purchase feedback at 9:15 (top-left): `-26,000 Coins` (red) then a list of bought items (Skeleton, Scavenger, Village Affinity, Mine Affinity, Intimidation talismans), so **spends also go in the pickup feed in red**.
- **8:20–8:25 Late-game inventory + effects:** the inventory (E) has an armour column at left (4 slots), a paper-doll, and a 5th slot for pet/equipment. A **potion-effect panel** to its right lists icon + name + timer: `Absorption`, `Night Vision II`, `Regeneration IX`, `Haste IV`, `Jump Boost VI`, `Strength VIII`, each with a `17:54:02` duration (long-duration "God Potion" buff).
- **8:24 SkyBlock Menu (late game):** 6-row GUI with a centred emerald "profile" head on top and rows of menu icons (skills sword, collections, recipe book, bestiary, quests, calendar, storage, pets bone, wardrobe, bank, etc.). Hover `Your Bags`: `Different bags allow you to store many different items inside!` / `Also accessible via /bags` / `Click to open!`. **Every menu entry has a description, a slash-command shortcut hint and a CTA.**
- **8:28 Your Bags → Accessory Bag tooltip:** `Accessory Bag` / `A special bag which can hold Talismans, Rings, Artifacts, and Orbs within it. All will still work while in this bag!` / `Magical Power: 1,826` (gold) / `Selected Power: Forceful` / `+60❤ Health`, `+876❁ Strength`, `+234☠ Crit Damage` (stat colours: red health, red strength, blue crit dmg) / `Unique Power Bonus: +4 Ferocity` / `Tuning: +183❁ Strength` / `Also accessible via /accessories` / `Click to open!`.
- **8:44–8:48 & 9:43 Collection tier screen (Redstone Dust Collection, zoomed):** a title, the item icon centred at top, then **two rows of tier tiles**: green tiles (unlocked) numbered 1–9 and 10–15, a lighter green or grey tile for the current one, and arrow (back) and red X (close) buttons. Tooltip format:
  - `Redstone Dust XIII` (green) / `Progress: 100%` / **full-width green bar with `1,400,079/800k`** in gold / `Rewards:` / `Humongous Accessory Bag Upgrade (+6 slots)` (green) / `Personal Compactor 6000 Recipe` (pink/purple name + grey "Recipe") / `+4 SkyBlock XP` (aqua) / `Click to view rewards!`.
  - Tier XV: `Titanic Accessory Bag Upgrade (+6 slots)`, `1,400,079/1.2M`. Tier XVI: `Preposterous Accessory Bag Upgrade (+6 slots)`.
  - Tier I (9:43): `1,400,079/100`, `Redstone Minion Recipes`, `+4 SkyBlock XP`. **Tier 1 of every resource collection unlocks the automated worker recipe for it.**
- **8:49–8:52 Redstone mine (Pigmen's Den):** a white/grey cave with red ore veins, sidebar region `Pigmen's Den`, objective `Talk to the Lapis Miner`. Chat: `AUTO-PICKUP! Drop sent to your inventory! … Items from mob and block drops directly go into your inventory. You will no longer be bothered about it!` — **auto-pickup is announced as a feature unlock**. Action bar `+7 (26,029/30,000)`. A purple (enchanted-glint) pickaxe swings. Ore breaking throws red dust particles.
- **9:16 Thaumaturgist GUI:** a single row of "power" options. Tooltip: `Fortuitous` / `Starter Power` / `Stats:` / `+2❤ Health`, `+1❈ Defense`, `+2❁ Strength`, `+3☣ Crit Chance`, `+2☠ Crit Damage` / `You have: 18 Magical Power` / `Click to select power!`. The NPC (Maxwell) stands in a wooden booth with `CLICK`.
- **9:30–9:33 Minions on the private island:** **5 small "worker" figurines** (child-scale humanoids wearing red-and-gold caps, each holding a tool/block) stand in a line atop a **raised platform of redstone-ore blocks** they mine. A villager NPC `Jerry / CLICK` (with a yellow "NEW UPDATE" tag above) is nearby. The island edge is smooth stone over void.

### 10:00–12:00 Stats talk (talking head + captions)
- Coloured caption overlays: `CRIT CHANCE` (yellow), `STRENGTH` (red), `CRIT DAMAGE` (orange). These reinforce a **fixed stat→colour mapping** (see §2.4).
- 11:12/11:25 chat between players about crafting and trading ("paying 10k for someone to craft me enchanted ice block"). The **player economy is chat-driven** as well.
- 11:32 hub street (`Late Summer 13th`). A villager shop has a TNT block display. 11:33–11:36 **Pet Care**: NPC `Bea` with a `Lv90 Bea's Bee` pet nametag (`[Lv90]` grey + pet name in gold) floating above her. **Pets show a level and owner's name.** Another booth nearby is labelled `Farm CLICK`.

### 12:00–14:45 Bazaar and Auction House
- **13:00 Bazaar stall:** a raised wooden stage in front of a stone building with a purple-glass (portal-like) door. The Bazaar NPC (ornate red-blue-gold robes, crowned) is flanked by chests, crates, barrels and a lantern, under the nametag `Bazaar / CLICK`. Smaller `Auction Agent CLICK` and `Bazaar Agent CLICK` NPCs stand beside it.
- **13:07–13:13 Bazaar GUI:** a 6×9 chest with a **left column of category tabs** (pickaxe=Mining, hoe=Farming, sword=Combat, fishing rod=Woods & Fishes, enchanting table/Oddities) and **pink/red stained-glass filler panes** forming a frame. The body holds commodity icons, and the bottom row has utility buttons (sign = search, red-no-symbol = close, book = manage orders, redstone torch = settings).
  - Category tooltip: `Combat` (red) / `Category` (grey) / `Currently viewing!` (green).
  - Product tooltip (Oddities → Booster Cookie): `Booster Cookie` (pink) / `1 product` / `Buy price: N/A` / `Sell price: 500,000 coins` / `Click to view product!`.
  - **Product page (13:17–13:25):** breadcrumb title `Oddities ➜ Booster Cookie`. Row 1 has `Buy Instantly` (gold nugget + arrow), `Sell Instantly` (hopper), the product icon centred, `Create Buy Order` (map/paper) and `Create Sell Offer`. Row 2 has a back arrow, a manage-orders icon and others.
    - `Buy Instantly` tooltip: `No one is selling this item!` / `There are no Sell Offers!` (red).
    - `Sell Instantly`: `Inventory: None!` (red) / `Price per unit: 500,000 coins` / `None to sell in your inventory!`.
    - `Create Buy Order`: `Only Order: 500,000 coins each | 284x in ?` / `Click to setup Buy Order!`.
  - Earlier crop at 13:09 shows the `Wheat & Seeds ➜ Wheat` product page with the same 5-action layout.
  - Bazaar Agent (16:12–16:17, Experience Bottles): `EXP Bottles` / `4 products` / per-variant lines `■ Experience Bottle 35 | 49`, `Grand … 4.8k | 5.1k`, `Titanic … 566.4k | 583k`, `Colossal … 1.7M | 1.8M` (green/yellow "sell | buy" pairs). Quick-buy pop-up: `Buy only one!` / `Grand Experience Bottle` / `Amount: 1x` / `Price: 5,292.9 coins` / `Click to buy now!`. **Compact two-number spread display per product.**
- **14:08–14:45 Auction House:** the `Auction Master` NPC stands in a grey stone vaulted hall. **Auction Browser GUI** has a left column of category tabs (gold sword = weapons, diamond chestplate = armour, green block = accessories?, apple = consumables, orange = blocks, stick = tools/misc) and **purple stained-glass border panes** for one category or **blue panes** for another (a colour-coded frame per category). There are 6×4 listing slots, and the bottom row holds Search (sign), back arrow, hopper (sort), eye of ender (BIN filter?) and a rail icon.
  - `Search` tooltip: `Find items by name, type, lore, or enchants.` / `Filtered:` / `Right-click to clear!` / `Click to edit filter!`.
  - `Sort` tooltip: `▶ Highest Bid` (highlighted aqua), `Lowest Bid`, `Ending soon`, `Most Bids` / `Right-click to go backwards!` / `Click to switch sort!`. **Cycling option lists inside one tooltip with ▶ marking the active entry.**

### 14:45–16:20 Reforging and enchanting
- **15:11 Blacksmith:** an NPC in an open forge with an anvil and an orange-lit furnace/coal stack under a timber canopy. Chat `[NPC] Blacksmith: Reforging items allows you to get the most out of your weapons, armor, and other items by applying stat modifiers to them! … Reforging costs Coins…` and a **first-time discount line** ("this time I will reforge any item for the low price of Coal").
- **15:12 Reforge GUI:** a narrow anvil GUI framed by **pink panes**, with a central item slot and a "Reforge" button. To its left is a **client-mod search side panel**: `Type Reforges Here! Separate Multiple With Commas.` / `Reforges To Match: e.g. 'godly, strong'` / `Reforges To Exclude: e.g. 'odd, clean'`. **Reforge filtering helps with rerolling.**
- **15:40–15:44 Enchanting room (late-game island):** a small player-built library with a **ring of multicolour bookshelves** (red/yellow/blue/green/purple book spines), an enchanting table on a crimson/obsidian base, and oak lecterns, under a purple sky.
- **Enchant Item GUI (15:56–16:01):** left column has the item slot (chestplate/sword) above a lapis/"exp" icon. On the right, enchant books (red book icons) sit in a grid. Bottom row: crafting table (recipe), red-no (close), book (guide) and hopper. Tooltips:
  - `Protection V` (blue) / `Grants +20 ❈ Defense.` / `Cost` / ~~`30`~~ `23 Exp Levels ✓` (a **struck-through original cost** with a green discounted cost and tick) / `Click to enchant!`.
  - `Sharpness V` / `Increases melee damage dealt by 30%.` / same cost display.
  - Applied-enchant state: `Protection` / `Grants +4 ❈ Defense.` / `Protection ✖` (red, "remove") / `Click to view!`.
  - Gemini also cites `Growth V +75❤ Health` at 15:56 (sheet thumbnail consistent).

### 16:20–17:23 Outro, talking head only.

---

## 2. UI reference (consolidated)

### 2.1 HUD / action bar (late-game, 360p zoom crop at 0:05 and 2:05)
Bottom-centre, all above a 9-slot hotbar:
1. **Text action bar (one line, three groups):** `5,287/4,832❤` (health in **gold** because it's over max via absorption; normally red) · `2470❈ Defense` (**green**) · `600/600✎ Mana` (**aqua**), followed by a small extra (`700ʬ` aqua, "overflow mana"?). Separated by spaces, no boxes. **The text values replace the vanilla meaning of the icon bars.**
2. **Icon rows:** a gold row of absorption hearts above **two red heart rows** (left half), and a **cyan bubble row** (right half) acting as a mana or armour gauge. Below them is the green XP bar with the **level number in green centred on it** (`305`).
3. **Hotbar:** 9 slots, dark translucent grey with a white selection frame. **Slot 9 is a permanent star "menu" item** (white nether star) on every profile, including fresh ones. A new profile has `100/100❤` and `100/100✎ Mana` (3:08), and the left of the hotbar sometimes shows `100%` (? speed/temperature readout from a mod).
4. Transient line **above the action bar**: skill gain `+5 (8/125)` / `+70 (188,075,584)` in teal or green, and on region change a short `⏣ Village` / `Pet Care` label in green.

### 2.2 Sidebar / scoreboard (right edge, vertically centred)
A translucent dark panel (alpha about 40%), Minecraft pixel font with **colour-coded line roles**:
- Title `SKYBLOCK` (bold yellow/gold).
- Date `02/17/26` plus server id (grey).
- In-game calendar `Winter 11th` / `Early Spring 17th` / `Late Summer 15th` (white).
- Clock `11:00pm ☽` / `6:20am ☀` (grey time + coloured sun/moon glyph).
- Location `⏣ Village` (grey ⏣ + aqua/green name; changes per sub-area: Your Island, Village, Mountain, Mining District, Coal Mine, Foraging Camp, Birch Park, Farm, Blacksmith, Pigmen's Den, Pet Care, Tangleburg, Spruce Woods).
- `Purse: 47,085,227` (white label, gold value; `(+25)` delta on gain).
- `Bits: 65,654` (aqua; a second, premium-ish currency).
- Context block: `Objective` + task (new players) **or** event lines (`Agatha's Contest 12m10s` / `COMMON with 76` / `Uncommon requires +174`) or a resource counter (`Whispers: 13k (+68)`).
- Footer URL (yellow).

### 2.3 Top-right buff tray (late-game)
Six square **teal-bordered icon tiles** in a row (absorption orange, night vision dark-blue, regeneration red, haste pickaxe, jump boost blue, strength sword). A compact potion-effect bar.

### 2.4 Stat glyphs and colours (consistent across tooltips, action bar and overlays)
- ❤ Health – red. ❈ Defense – green. ❁ Strength – red. ✎ Intelligence/Mana – aqua. ☣ Crit Chance – blue (caption shown yellow). ☠ Crit Damage – blue (caption orange). ✦ Speed – white. ☘ Mining Fortune – gold. Ferocity – red.
- Damage values in tooltips are red, Mining Speed is gold, and positive % modifiers are green.

### 2.5 Inventory / chest GUIs
- **Grid:** vanilla chest sizes of 9 columns × 1–6 rows. Slot size is uniform. Panels are dark slate/navy-grey with a lighter 1 px bevel (a resource-pack retexture: flat dark, not vanilla beige).
- **Header:** a grey title at top-left (`Weaponsmith`, `Mine Merchant`, `Redstone Dust Collection`, `Auctions Browser`, `Bazaar ➜ Combat`, `Oddities ➜ Booster Cookie`), using **➜ breadcrumbs** for depth.
- **Body/footer:** an `Inventory` label introduces the player's 27 slots, and the hotbar repeats beneath it in its own strip (with the star item).
- **Stained-glass filler** frames content with a colour per context: pink/red (Bazaar, reforge), purple/blue (Auction categories). Empty filler slots carry no tooltip.
- **Standard nav row** at the bottom: back arrow (left), close (red barrier/no-sign, centre), utility icons (sign = search, hopper = sort, book = guide).
- **Category tabs** run down the left column (Bazaar, Auctions), and the active tab is announced in its tooltip with `Currently viewing!`.
- **Tooltip** (universal): near-black purple body with a 1–2 px purple gradient border. Lines in order: **Name** (rarity colour) → grey tags (`Collection Item`, `Brewing Ingredient`, `Starter Power`) → blank → stats (`Label: +value`) → blank → ability/description (grey, keywords coloured) → blank → flags (`This item can be reforged!`, `Works while in Accessory Bag!`) → **RARITY + TYPE in bold caps** (`COMMON SWORD`, `COMMON ORE`, `COMMON ACCESSORY`, `COMMON PICKAXE`) → price/cost/stock block → **yellow CTA** (`Click to trade!`, `Click to sell!`, `Click to view!`) with an optional second CTA (`Right-click for more trading options!`).
- **Rarity colours seen:** Common = white (bold caps line); Uncommon = green (sidebar contest bracket text); Rare = blue (enchant names in blue); Epic = purple (`Personal Compactor` recipe name pink-purple; `Booster Cookie` pink = special). Legendary gold is implied by the `Promising`/gold UI but not confirmed at 360p.

### 2.6 Chat conventions
- Bottom-left, translucent black backing, up to about 10 lines visible.
- **Structured system blocks** have a bold coloured header, `REWARDS` sub-header, an indented list and cyan rule lines: SKILL LEVEL UP, QUEST COMPLETE, NEW AREA DISCOVERED, NEW OBJECTIVE, AUTO-PICKUP.
- NPC speech: `[NPC] Name:` (yellow tag + coloured name), sometimes paged across several lines with a pause.
- Social: `Friend > X joined/left.` (green), rank-prefixed player chat.

### 2.7 Pop-up toasts / titles
- Centre-screen **area title** (big coloured name + yellow bold `NEW AREA DISCOVERED!`) lasts about 2 s.
- **Pickup / spend feed** (top-left, stacked): `+33 ■ Coal`, `+250 ■ Coins` (green +), `-26,000 Coins` (red).
- Top-right toast (client mod) has a title + body in a framed box ("Not Found!", "Success! The message was copied to your clipboard!"). **This style is useful for system toasts.**

---

## 3. Systems and mechanics shown

| Time | System | What the frames show |
|---|---|---|
| 3:03–3:30 | **Guided objectives** | One active objective, mirrored in the top bossbar and the sidebar. Chained: gather → craft → teleport → talk to NPC. NPC (Jerry) on the island explains the next step. |
| 3:13, 8:44, 9:43 | **Collections** | Per-resource tier ladder (I–XVI+), a progress bar with `current/target` in compact units, and rewards per tier: bag slots, recipes (minions), account XP. The first harvest triggers a celebration particle burst. |
| 6:52–6:59 | **Skills** | XP per action shown in the action bar (`+5 (8/125)`). Level-up chat block lists perk name + effect text, stat bonus, area access unlock, coins and account XP. |
| 2:04 | **Skill XP event bonus** | A temporary +% skill XP broadcast on login. |
| 2:12 | **Daily rotating buff** | `New day!` chat announcing a new fortune buff. |
| 6:03–6:40 | **NPC merchants** | Fixed-price shops with a sell-anything-to-any-merchant tooltip, **stock limits** (`638 remaining`), barter recipes (`Gold Ingot x3`) and a right-click bulk-buy menu. |
| 6:59, 7:13 | **Launch pads / jump pads** | Slime pads that fling you to the next floating island and are gated by skill level (Gold Mine access is a Mining II reward). |
| 3:28 | **Teleporter portal** | A portal on the private island warps to the hub, with a loading screen in between. |
| 3:30–7:14 | **Area discovery** | Each sub-area has a name + discovery title + "what to do here" bullets, and the sidebar location updates. |
| 7:06–7:13 | **NPC quests** | Talk → task → `QUEST COMPLETE` with coin + tool + skill XP + account XP rewards. |
| 7:51–9:18 | **Accessories** | Shop-bought talismans (500 coins) are passive while in an **Accessory Bag**. The bag's slots grow via collection tiers. Total **Magical Power** feeds a selectable "Power" stat package (Thaumaturgist NPC) plus "Tuning" points. |
| 8:52 | **Auto-pickup** | Drops go straight to the inventory, announced once as an unlock. |
| 9:30 | **Minions** | Small automated workers placed on your island mine the block grid in front of them. Recipes unlock at collection tier I. Rows of minions are housed in glass cells late-game (3:18). |
| 11:33 | **Pets** | Pet follows the owner with a `[Lv90] Owner's Pet` floating tag. A Pet Care NPC booth exists. |
| 13:00–13:25, 16:12 | **Bazaar** (commodity exchange) | Categories → product → instant buy / instant sell / buy order / sell offer, with spread prices (buy|sell). Agents (smaller NPCs) are branch counters. |
| 14:08–14:45 | **Auction House** | Category tabs, search by name/type/lore/enchant, sort cycle (highest bid / lowest / ending soon / most bids), BIN filter (?). |
| 15:11–15:13 | **Reforging** | Blacksmith NPC; coin cost; first reforge discounted (paid in coal). It rerolls a stat-modifier prefix. |
| 15:56–16:01 | **Enchanting** | Table GUI listing enchant books per item type. Costs are in XP levels, with a discount shown as strike-through. Applied enchants can be removed (✖). |
| 8:20 | **Long buffs** | Many potion effects with an 18-hour timer, shown in the inventory side panel and the top-right tray. |
| 4:34 | **Shared world events** | A fig-tree contest with a timer, bracket ranks (Common/Uncommon…) and contribution % rewards. |
| 4:09 | **Combat readouts** | Player HP shown under the nametag. Gemini also mentions Slayer/Maddox **[Gemini only]**. |
| 1:57, 2:14 | Platform layer | Lobby game selector, rank store (out of scope). |

---

## 4. Animation and feedback inventory

- **Harvest/mining:** block-crack particles in the block's colour (red dust for redstone 8:52, brown for logs, grey for coal), then instant item absorption (auto-pickup). The feed line top-left and an XP tick in the action bar appear together, so one action gives **three simultaneous confirmations**.
- **Tree-feller (4:34):** big white crescent "swoosh" rings radiate from the chopped trunk, and many logs pop at once. Readable at a distance.
- **Held-item viewmodel:** the tool is drawn large in the bottom-right corner (pickaxe, axe, hoe), with a swing arc on click. Enchanted tools have a purple glint (8:52 purple pickaxe, 4:37 purple axe).
- **Discovery:** the title fades in with an implied chime (Gemini says a high-pitched discovery sound). It lasts about 2 s.
- **Celebration burst (3:13):** chunky yellow and red pixel flower/confetti particles fill the screen briefly on unlock.
- **Portal:** purple swirling surface, purple particle wisps, a screen fade to "Loading terrain…".
- **Launch pad:** camera tilt upward, long-arc flight, then load into the target island.
- **Farming (9:01):** the hoe swings through wheat, and seeds and wheat pop into the feed (`+2 Seeds`, `+27 Wheat`). Breaking crops spawns green "bonemeal" sparkle particles.
- **NPC idle:** NPCs face the player. Their nametag `CLICK` text stays fixed in place and does not pulse (reads static at 360p).
- **Pets:** a small floating head model bobs beside the owner (Bea's Bee, 11:36).

## 5. World and art direction notes

- **Hub town (night):** a cobbled grey plaza with a central planter of purple-flowered shrubs. Lamp posts line the roads. Houses are dense and timber-framed with steep orange/red roofs, coloured awnings (yellow, teal, orange) and bright windows. There is a windmill weather vane, a white civic building with columns and a red-brick Community Center with a gold-floor interior. Paths are 6–8 blocks wide, edged with grass and low stone walls.
- **Narrator's spawn spot (daytime):** smooth grey stone outcrops with **soft leafy hedge blocks** spilling over them, a **cottage built into a rock arch** (timber, lanterns, flower boxes), mangrove-coloured brick steps and patches of light/dark dirt. The palette is cool grey + saturated green + warm orange. This is a strong reference for a cosy "town nook".
- **Village mountain garden (2:41):** terracotta-coloured soil, a lavender/allium/poppy flowerbed and candles on white pillars along the path.
- **Floating islands:** chunky rock undersides hang below grassy tops. Gold Mine (7:00) has grey cliffs, dirt terraces and dead trees. Birch Park (7:14) has white-bark trees and golden grass under an **orange-salmon sunset**. Spruce Woods (4:40) has **snow-capped spruce** and pale ice-blue rock walls.
- **Mine districts:** a timbered tunnel gantry, wooden support arches, rail lines, an orange canvas awning over the merchant and lanterns. The coal quarry is grey stone with an open sky and visible ore seams. Pigmen's Den is a white/light-grey cave with bold red ore veins (strong value contrast).
- **Farm (9:01):** tilled soil rows bordered by full-grown golden wheat walls, at the foot of a mossy cliff with hanging vines, beside a yellow-thatch barn.
- **Market (13:00):** a raised wood stage in front of a stone building with a glowing purple door. Merchant props include chests, crates, barrels and a lantern on a post. The Auction House is a **grey stone vaulted hall** with a strong central axis.
- **Enchanting nook:** a ring of bright multicolour bookshelves around a table.
- **Private island:** it starts as one tree on a tiny grass slab beside a teleporter arch. The late-game version is a dense personal build (flower tower, glass minion lattice, spires).
- **Sky and lighting:** a day/night cycle is visible across clips (navy night with blocky clouds, pale blue day, orange sunset, purple custom sky on islands). Lighting is warm point lights (lanterns/windows) against cool ambient.
- **Density:** the hub is very dense, with an NPC every 10–20 blocks along main roads and many players. Gathering zones are open and sparse so you can move freely.

---

## 6. Prioritised adoption list for Aether Isles (original designs, no names/branding copied)

**P0 — core loop and readability**
1. **Single-line stat strip** above the hotbar (HP · Ward · Focus) with fixed glyph+colour per stat. HP turns gold when overhealed. Use the same glyph/colour in tooltips, damage numbers and captions.
2. **Context sidebar** with strict line roles: title / in-world calendar + clock glyph / location (updates per sub-zone) / wallet with `(+n)` delta flash / secondary currency / one context block (objective OR event timer+bracket OR zone resource counter).
3. **Three-way action feedback**: top-left stacked pickup/spend feed (green +, red −), action-bar `+XP (cur/next)` tick, and on-block particles. Auto-pickup is the default.
4. **Universal tooltip grammar**: name (rarity colour) → grey tags → stats → ability text with coloured keywords → flags → **BOLD RARITY + TYPE** → price/cost/stock → yellow primary CTA + optional secondary CTA. Build it once as a component.
5. **Guided objective chain** for new players (gather → craft → travel → meet townsfolk), mirrored in a top progress bar and the sidebar. Tutorial NPC on the home island.
6. **Area discovery**: big centre title + "discovered" subtitle + chime, and a chat card listing 2–3 "things to do here". Ties into an exploration log.
7. **Structured reward cards** in chat/toasts for level-up, quest complete and unlock: header, a REWARDS list (perk with full effect text, stat bonus, area unlock, coins, account XP) and rule lines.

**P1 — progression systems**
8. **Per-resource collection ladders** (tiered tiles, progress bar `cur/target` in compact units). Tier rewards are recipes (tier I unlocks the resource's automaton), bag slots and account XP.
9. **Skill-gated travel**: launch pads/sky-rails between floating isles, unlocked as skill-level rewards, with a dramatic arc and a short load.
10. **Island automatons** (our worker spirits) that harvest a placed block grid on the player's home isle, with upgradeable speed/capacity and slots unlocked by distinct recipes crafted.
11. **Charm pouch**: passive trinkets work while stored in a pouch. Pouch capacity grows via collections. Total "resonance" from charms feeds a selectable stat package at a town NPC plus allocatable tuning points.
12. **Account level** fed by every system (each reward card shows `+n Account XP`).

**P1 — economy UI**
13. **Merchant GUI**: sell-anything-to-any-merchant, per-player stock counters, barter costs (items as currency), right-click bulk quantity picker, recent-sale buyback slot.
14. **Commodity exchange** (OSRS-GE meets order book): category tabs on the left, product page with 4 actions (instant buy, instant sell, place buy order, place sell offer), and a compact `sell | buy` spread per variant. Breadcrumb titles (`Category ➜ Item`).
15. **Player auction board**: category tabs with a colour-coded frame, search across name/type/lore, a sort cycle shown as a ▶ list inside the button tooltip (right-click = reverse), and a buy-now filter.

**P2 — depth and juice**
16. **Reforge/rune station** that rerolls an item's stat prefix, with the first use discounted and a match/exclude filter for desired outcomes (QoL built in, not mod-dependent).
17. **Enchant table GUI** listing applicable enchants per item, showing a strike-through original cost when discounted, a green tick when affordable, and a ✖ to remove.
18. **Timed communal events** (e.g. a giant tree everyone chops): sidebar timer, bracket rank ("Common with 76 · next bracket requires +174") and contribution-% rewards.
19. **Daily rotating world buff** + login digest card (profile, active bonuses, patch notes link).
20. **Tree-feller and AOE harvest juice**: big readable crescent particles and multi-block pops for upgraded tools. Enchanted-glint shader on held items.
21. **Buff tray**: top-right tiles for active long-duration buffs, plus an inventory side panel with timers.
22. **Pets** with a `[Lv n] Owner's Pet` nametag and a care NPC.
23. **Permanent menu item in the last hotbar slot** (or a Roblox HUD button) opening a hub menu whose every entry has a description + shortcut hint + CTA.

**World-art takeaways** (take the layout, density, landmarks, signage, colour and lighting from the reference. Do not take its blocky/voxel geometry. Aether Isles targets detailed meshes and rich visuals, so build every "block" described above as a detailed asset: sculpted rock, layered foliage, modelled timber framing and real-time lighting.)
- Hub = central dense town + 5 radial skill districts, each with a distinct biome palette and a landmark gateway (mine gantry, camp lodge, farm barn, dock, battlement).
- Separate **floating satellite isles** reached by pads, each with a strong sky mood (sunset, snow, night).
- Contrast rule: cool stone + saturated foliage + warm lights. Ore veins in high-contrast colour on pale rock.
- NPCs at counters/booths with a two-line floating tag (name + "Interact" prompt in yellow), every 10–20 studs on main streets.
- The home isle starts as one tree + a portal arch and grows into the player's showcase.

# Design notes: "A Beginner's Guide To Old School RuneScape (OSRS Starter Guide)"

- Source: local file `drive/video2.mp4`, 24:23, 640x360 (360p). Studied frame by frame with the watch skill's local engine. Every frame in the reports was read: 0:00–8:00 (44 frames), 8:00–16:00 (31), 16:00–24:23 (45), plus 38 cue frames picked to fill gaps (3:45–4:45, 6:40–7:55, 9:00–11:00, 18:15–18:50, the HUD shots at 20:19, 22:10, 23:11, 23:20, 23:35).
- No audio or transcript was used (`--no-whisper`, and the file has no captions). Mechanics are inferred from on-screen captions, panels and gameplay.
- Purpose: reference for the Aether Isles UI, systems and world-art teams. Everything below describes the reference game. The section at the end turns it into original features. Do not copy names, icons, cape designs or branding.

## 0. What this video is (and is not)

It is an edited overview, mostly B-roll. The creator hides the HUD for most of the runtime ("cinematic" camera, UI off). The full interface (minimap and orbs, side panel, chatbox) is visible in only about 6 shots: 3:33–3:45 (Tutorial Island), 2:45, 13:59, 15:38–15:54, 20:19, 22:10, 23:11, 23:20 and 23:35.

**Not shown in this video:** bank interface, Grand Exchange offer interface (only the crowded GE plaza at 1:15), trading window, shop interface, death or gravestone mechanics, the equipment tab contents, quest list panel, spellbook panel, settings panel, an explicit run-energy toggle, teleport animations, or a level-up popup. Notes on those are marked **[not shown]**. The UI team should take them from the other reference videos.

---

## 1. Timeline (timestamped)

| Time | What is on screen | Design takeaway |
|---|---|---|
| 0:00–0:07 | Black, then cold-open close-ups: a knight in mismatched armour slaying a green dragon in a lava cave (0:02); a full-helm close-up in an armour shop with helmet icons on a wall shelf (0:06); red boots and fur trim walking on a stone path past a stone cottage (0:07). | Low-poly, flat-shaded gear reads well even in extreme close-up. Armour is built from big, plain colour blocks. |
| 0:29 | Swamp: teal water, olive grass paths, dead trees, mushrooms, frogs. | Biome identity comes from a strong palette swap (teal and olive) on the same low-poly kit. |
| 0:37–0:39 | History segment: 2004 login screen (parchment scroll menu: Log In / Create Account / World 104 / SD-HD), then 2012 sequel-era towns. | A parchment scroll as a menu metaphor is a strong nostalgic UI motif. |
| 0:55 | Line chart of concurrent players, 2013–2025: the "old school" version is about 96k against about 22k for the modern one in Q1 2025. | Context: players value the retro, grind-based design over a modernised version. Supports a deliberately simple aesthetic. |
| 1:00 | Mobile launch news page (Oct 2018), with a tiled stone border and NPC portraits. | The game is cross-platform with one shared world. Plan the Roblox UI for touch from day one. |
| 1:04 | Spawn field outside a castle: bald default character (khaki shirt, green trousers) in tall grass with flowers and sticks. A grey castle wall and gate sits on the horizon, with a mine entrance in a hill on the right. | The default starter look is deliberately plain, so first upgrades feel big. |
| 1:15 | **Grand Exchange plaza**: a huge crowd of players in varied outfits around a central round building. A tiled floor and banners. | The central trading hub doubles as a social showcase. Players stand around to be seen. |
| 1:28 | "Ironman Mode": a player in grey-white armour mining a pink crystal rock with a pickaxe, with pink shards flying. | Self-sufficient account mode (no trading). Mining feedback is particle chips in the rock's colour. |
| 1:40 | Dim room with two mannequins in tabards marked "III" / "II". | Ironman-mode variants shown as armour on display. |
| 1:56–1:59 | Raids montage: a cave of glowing green crystals (1:56), a dark gothic city with red ground (1:57), a desert pyramid with banded pillars (1:58), an arena with a giant crocodile boss, tan floor discs and pots (1:59). | Endgame group dungeons each get a strong one-colour theme. |
| 2:05 | Painted overview of a second continent: red-roofed Roman-style city, colosseum, coastline. | A late-game continent with its own architectural language. |
| 2:10 | List of grandmaster quests over a park and fountain. | Long quest lines are prestige content. |
| 2:17–2:28 | Account website (account and membership) and the launcher login on Android. | Out-of-game. Ignore. |
| 2:38 | Developer livestream couch. | Community and dev-transparency culture. Out of scope. |
| 2:45 | **Tutorial: Skills panel** (cue). Chatbox shows "Skills and Experience — On this menu you can view your skills…". A yellow bouncing arrow over the tutor NPC. The skills grid is open on the right. | The tutorial opens one panel at a time and explains it in the chatbox slot. |
| 3:03 | Tablet with the mobile UI: minimap top-left, a vertical button strip on the right, chat tabs along the bottom edge. | The mobile layout moves the panels to the edges. Useful for Roblox touch. |
| 3:07–3:17 | Desktop launcher (Play, client choice, character); third-party client logo. | Out of scope. |
| 3:26 | Overhead shot of the tutorial island: a small green island with brown-roofed buildings and fenced paths, floating among smaller islets on blue. | **This is almost exactly the floating-isle look we want.** It is a small, contained starter island with each station in its own building. |
| 3:28–3:35 | Character leaves the starting house (stone, wooden porch, blue flowers), walks a fenced dirt path, cuts a tree by a river with a bronze axe. | Short, scenic walks between stations. |
| 3:38 | Tutor NPC (woman in pink) next to a lit campfire on the path. | The tutor stands at the activity she teaches. |
| 3:40 | Title card "Tutorial Island". Player crouched at a pond fishing with a small net. | Crouch-and-net fishing pose. |
| 3:40–3:45 | **Tutorial HUD**: chatbox replaced by a parchment box "Please wait — Your character is now attempting to cut down the tree. Sit back for a moment while he does all the hard work." Then the same for lighting a fire. The side panel shows only the unlocked tabs (4 icons). The inventory is empty. Filter row: All / Game On / Public On / Private Friends / Channel On / Clan On / Trade On / Report. | **The tutorial explains idle-action skilling: click once, the character keeps working.** Tabs unlock one at a time. |
| 3:55 | "Tick Based System": player on a cyan true-tile outline in a field of tree stumps. | The world runs on discrete ticks (about 0.6 s) and tiles. The cyan tile is the server-true position. |
| 4:05 | "No Set Path": walking over a stone bridge into a walled castle town. A wooden signpost and a river. | Sandbox: no forced progression path. |
| 4:25–4:35 | **NPC dialogue** (cue): "Select an option" header with sword dividers on both sides, 4 options plus "More options…". Then the reply panel: speaker name as a red header ("Subscribe" is the speaker name joke), text, a talking-head portrait on the right, and "Click here to continue" in blue. | The dialogue panel takes over the chatbox. A portrait (chathead) sits on the side of the speaker. Option list with paging. |
| 4:45 | "Combat Explained": melee, ranged and mage starter outfits in three panes. | Three combat classes shown as three visual archetypes. |
| 4:50–4:56 | "Melee / Ranged / Magic" over a boss fight. The boss has a large green and red HP bar overhead. The player has a small HP bar and a round yellow weapon-style badge overhead. | Combat triangle. Bosses get bigger bars. |
| 5:02 | Snake boss arena: a tiled floor with coloured hazard zones and venom clouds. | Telegraphed ground hazards on a tile grid. |
| 5:12 | **XP drops**: fist icon "99" and heart icon "33" floating at the top left as the player hits a blood spider boss. The player wears a blue prayer overhead and a red-blood themed arena. | Each hit gives two XP drops: the combat skill plus hitpoints. Icon plus number, rising. |
| 5:19 | Cave with a full 28-slot inventory (4×7) of gear and potions. | Inventory snapshot. |
| 5:25 | "Mini Combat Guide": tutor building with weapon racks, posters, a training dummy and an anvil. | Each combat style has a tutor and a building. |
| 5:34 | "Scimitar" glyph overlay. The player attacks cows, a red hitsplat "8" on a cow, and a speech bubble "Moo" from a cow. Bars: fist 32 and heart 10 XP drops. | NPCs say ambient overhead lines ("Moo"). |
| 5:44 | Player in bronze armour walks through a gate. Signpost at a crossroads, castle with blue shield banners. | Signposts at every junction. Heraldic banners on castles. |
| 5:50 | Tutor house with a level-bracket text overlay (e.g. levels for iron, black, mithril…). | Gear tiers unlock at set levels. |
| 6:03 | Ranging cows with a shortbow. Bow icon "28" and heart "9" XP drops. Arrow and dung clutter on the ground. | Ranged XP drop uses a bow icon. |
| 6:11–6:27 | Interior of the ranged and magic tutor house: archery targets on the walls, maps on two tables. | Tutor buildings are reference landmarks. |
| 6:40 | "Strike Spells": big pixel-art icons for an air bolt (white teardrop) and a fire bolt (orange teardrop). | Spells have simple, readable teardrop glyphs colour-coded by element. |
| 6:55 | **World map**: painted top-down parchment map. Kingdom names in large orange serif. Town names in white small caps. Rivers in blue. Round icons for services. Red boxes highlight training spots. | The map style: flat painted terrain, region labels, service icons. |
| 7:10–7:55 | "Combat Training Spots" series, each with a top-left title card plus a location subtitle and an F2P or Members badge at the bottom left: Cows (8 HP), Giant Frogs (swamp), Flesh Crawlers (dungeon floor 2). Blue "0" miss splats and red hit splats. | Content tagging by tier: our version would be a "free / premium-island" badge. |
| 8:00–8:20 | Spider cave in an F2P dungeon (cobwebs, skeletons); Ogress Warriors on a cove beach (hitsplats, XP drops 16 and 5). | Monster dens dressed with bones and webs. |
| 8:37–8:49 | "Quests" title over a waterfall; a list of members' quests over a walled garden mansion with statues. | Quests unlock areas and training. |
| 9:00–9:30 | **Crabs**: sand-coloured rocks on a beach that wake into crabs when the player stands near. The crab's red HP bar appears, hits come in, and it goes back to a rock when left alone. "Sand Crabs: southern beach / Rock Crabs: northern island." | **Dormant disguised mobs** for AFK combat training. Easy to build and fun. |
| 9:43 | "Slayer": bat-like gargoyle monsters in a crate-filled yard. The player shows a blue "0" splat. Green and red HP bars. | A task-based combat skill. |
| 9:55 | Garden mansion again, with caption "…not require … quests…". | |
| 10:16–10:32 | Wiki quest page, optimal quest-order guide, quest video playlist. | Players lean on external wikis. We should put a **quest-order helper in the game**. |
| 11:21 | "Hitpoints": fighting a multi-armed cannon boss in a fenced yard. Many NPCs, XP drops 30/24. | |
| 11:31–12:48 | **Skill showcase format**: the same grassy backdrop, the character turns to show a skill cape (unique colour and emblem per skill), the skill name in large yellow-green text, 1–3 lines of description. Attack ("Increases melee accuracy"), Strength ("Increases melee max hit"), Defence ("Reduces the chance of enemies damaging you"), Ranged ("Unlocks better weapons & ammo"), Prayer, Magic ("Cast a larger variety of spells / Increases magic accuracy / Elemental weaknesses increase hits"). | Each skill gets a one-line purpose statement. Our skill pages should do the same. |
| 12:55 | Ice spiders in a snow cave: magic combat, triple blue "0" splats stacking. | Hitsplats stack in a cluster when several land in the same tick. |
| 13:17–15:30 | Gathering and production skills in the same cape format: Mining ("Leveling unlocks more rocks"), Smithing, Fishing ("…more fish…"), Cooking ("Unlocks more foods / Also lowers your burn rate"), Firemaking ("Unlock higher level logs / Group boss at level 50"), Woodcutting ("Unlock higher level trees / Increases chance of getting logs / Fairly slow skill to train"), Crafting ("Unlocks essential upgrades…"), Runecraft ("Creation of magic runes / Unlocks highly profitable methods / One of the slowest skills"). | Each gathering skill's core design: **level gates what you can harvest, and level also raises the success rate.** |
| 13:59 | Fishing spot by a fenced river. Inventory shows a **stack count "297"** above a feather or bait item and 3 fish. | Stackable items show a yellow number in the slot's top-left. |
| 14:44 | Group skilling boss in a snowy courtyard: a brazier with green fire, players in red Santa-like outfits. | A co-op skilling "boss" that you beat by skilling (feeding braziers). |
| 15:01 | Climbing a giant redwood trunk on a rope ladder to reach the high-tier trees. | Vertical skilling zone. |
| 15:38–15:46 | Runecrafting altars: a blood-red void altar, a floating rock altar in a grey void. The inventory is full of essence (white pebbles, 27 slots) plus a pouch, fish and a potion. | **Essence run loop: fill inventory, travel, convert at altar.** Altars float in their own pocket-dimension islands (good for sky-isles). |
| 15:54 | Cooking in a farmhouse kitchen: a range, a dairy churn, cows outside. Inventory with a 65 stack count. | |
| 16:00 | Walking across a stone bridge into a walled town with blue shield banners and a signpost. | |
| 16:05–16:15 | **Construction**: player-owned house from above. Rooms with lime-and-white striped walls, a garden, a portal room. "Create & upgrade your house / Unlocks utilities for your account / Very expensive to train." | **Player housing = utility hub** (portals, altars, storage). Directly maps to our SkyBlock-style private island. |
| 16:32 | Agility ("Unlocks various shortcuts / Improves your run energy"). | Agility gives map shortcuts and more run energy. |
| 16:50–17:27 | Herblore, Thieving, Fletching capes. | |
| 17:42–17:56 | Slayer ("Fight monsters you are assigned…"): stone-walled dungeon maze with skeletons and green-lit cells. | |
| 18:01 | Dining hall in a castle; a table with a red heart icon (a healing or food station). | |
| 18:06 | Hunter cape ("…can be click-intensive…"). | |
| 18:15 | Burying bones in a graveyard of crosses. Prayer XP drop 315. Inventory with stack counts 220 and 69. | |
| 18:20 | Farming patches: four fenced dirt patches with growing crops in different stages, a scarecrow, a flower patch. | Crop growth stages are visible on the patch. |
| 19:02 | "Questing": a scroll list of about 20 F2P/early quest names over a castle room. | |
| 19:07–19:28 | Quest-gated areas: walled mansion, tomb (green vines, skull torches, a chest), gnome village; a two-column list of recommended early quests. | Quests open new places. |
| 19:43 | A walled gnome-style island with torches and a stone bridge. | |
| 19:46 | **Right-click menu** (best view in the video): grey header "Choose Option"; entries "Talk-to *Thug (level-55)*", "Pickpocket …", "Lure …", "Knock-Out …", "Walk here", "Examine *Thug (level-55)*", "Cancel". The action verb is white, the target name yellow, the level green. A sleeping NPC shows "Zzzzzz" above its head. | **Ordering: context actions first, then Walk here, Examine, Cancel.** The default left-click is the top entry. |
| 19:47 | Desert city with a pyramid, palm trees, sand-brick walls, market stalls. | |
| 19:48 | Underwater temple: teal floor, coral, ring of statues around a fountain. | |
| 20:10 | Thieving in a timber-frame market hall: a bank-style counter, roped-off area, a noticeboard. | |
| 20:19 | **Full desktop HUD** (cue, see section 2). A crafting XP drop "45" at the top of the viewport. The inventory is full of cut gems. | |
| 20:36–20:41 | Web search for the wiki; a quick-guide video "Requirements" parchment (Quests / Skills / Items needed: 1 coin, 25 bones / Items recommended / Teleports). The left side shows the in-game chatbox log and HUD. | The requirements card format (quests, skills, items, recommended, teleports) is a strong quest-journal template. |
| 20:50–21:10 | Wooded road; walking up to the GE. | |
| 21:15–21:20 | "Mid Game Content": hill giants in a walled yard, hitsplat 12. The player wears a leopard-print cape. | |
| 21:31–21:49 | Mid-game bosses: a spider boss on a web-and-blood arena (the player has an HP bar and a weapon badge); a dark temple with a pyramid crystal; a moon-themed boss on a golden spiky ring with gold floor discs (fist XP 71); a snake boss on a ring path with pillars (magic XP 18). | Bosses = themed arena plus floor pattern. |
| 21:58 | "End Game Content" over the crystal cave. | |
| 22:10 | **Endgame boss HUD** (see section 2): boss HP panel top-left, prayer panel open, chat filled with coloured boss mechanic warnings. | |
| 22:31 | "Achievement" cape on a dark cave floor. | |
| 22:39 | Overhead of a large castle town: grey walls with cross arrow slits, banners. | |
| 22:50 | **Tile markers**: the player stands on yellow and green outlined tiles in a grey stone dungeon. | Ground-tile markers help with movement puzzles. |
| 23:05 | Rope bridges and lava pits in a snowy rocky area; caption about the highest-XP player. | |
| 23:11 | **Combat task completion HUD** (see section 2): "Task Completed: Unconventional (6 points)" popup at top; boss bar "0 / 900". | |
| 23:20 | Lava-cave wave arena: full HUD with a skill grid panel, total level 618, a "Max Hit" panel, ping display, date stamp. | |
| 23:24 | Lava maze for the hardest wave challenge. A recoil-ring message spams the chat. | |
| 23:30 | "Achievement Diaries": round green compass-like emblem, a reward-items panel showing a 4×3 grid of rewards. | |
| 23:35 | **Maxed skills panel**: every skill "99/99", "Total level: 2277"; caption "13M XP for 99". | Level 99 takes about 13M XP. Use an exponential curve. |
| 23:40 | "Pets": **Pet house** interface: brown panel with title bar and close X; "You have stored these pets"; a 6-column icon grid with a scrollbar; checkbox "Allow pets to roam". | Clean collection-storage panel template. |
| 23:51 | Starter character walking past a castle with a shield banner, with a wooden shield and sword. | |
| 23:54–23:58 | The cold-open shots repeated as the outro. | |

---

## 2. Interface anatomy (from the few full-HUD frames)

### 2.1 Layout (desktop "fixed/resizable classic", 20:19, 22:10, 23:20)
- **Viewport** fills the screen. Top-left mouseover text shows the action under the cursor, e.g. "Walk here", "Use Bones / 3 more options", "Charge Totem / 2 more options". It always shows the default left-click action, then "/ N more options" for the right-click menu.
- **Minimap**: top right, circular with a dark stone frame. A compass rose at its top-left. A small world-map orb at its lower right. White dots = players, yellow = NPCs, red = items (convention). Flag marks the walk destination.
- **Orbs** in an arc down the left edge of the minimap (top to bottom, 20:19): an "XP" button (toggles XP drops/tracker), **Hitpoints orb** (red heart, value 99), **Prayer orb** (white star on blue, 99), **Run energy orb** (yellow boot on dark, 92), **Special attack orb** (green, 100). Each orb is a circle with an icon and a number to its left. The fill drains with the value. Clicking toggles the effect (run on/off, quick prayers, spec).
- **Side panel** bottom right: a stone-brown frame with **two rows of 7 icon tabs** (top row above the panel, bottom row below it), about 14 tabs in all. Visible icons at 20:19: top row combat options (crossed swords), skills (bar chart), quests (blue compass-like), inventory (brown backpack, selected and lit red), equipment (helmet/body figure), prayer (white star), magic (spellbook). Bottom row: account/friends (smiley face), clan, logout/settings, emotes, music (partly cut off).
- **Inventory panel**: **4 columns × 7 rows = 28 slots**. The background is dark brown with no slot borders. Items are drawn as 3D model icons. Stackables show a yellow count in the top-left corner ("297", "220", "69", "65"; huge stacks change colour in the reference, e.g. white "K" / green "M").
- **Chatbox** bottom left: a parchment-tan translucent panel, about 8 lines visible, with the newest at the bottom. The input line "Name: *" is at the bottom. The **filter button row** below reads **All | Game (Filtered) | Public (On) | Private (On/Friends) | Channel (On) | Clan (On) | Trade (On) | Report**. The state is printed under each label in green (On), yellow (Filtered/Friends) or red (Off).
- **Chat colour coding** (22:10, 23:11, 23:20): black = system messages; **red** = boss warnings and kill times ("Fight duration: 3:20.40. Personal best: 1:07.80"); **green** = achievement or task names; **purple/magenta** = boss mechanic warnings; **dark red** = valuable drop broadcasts ("received a drop: 81 × Rune arrow"). Countdown lines like "The Nightmare will awaken in 10 seconds!".

### 2.2 Skills panel (2:45, 23:20, 23:35)
- A **3 columns × 8 rows** grid. Each cell: skill icon on the left, "current/base" level as two stacked yellow numbers split by a diagonal (e.g. "10/10", "99/99"). The **last cell is "Total level: N"** (32 at the start of the tutorial, 618 mid-game, 2277 maxed).
- Column order seen: combat skills in the left column (Attack, Strength, Defence, Ranged, Prayer, Magic, Runecraft, Construction), Hitpoints at the top of the middle column, then gathering and artisan skills.
- Hover in the reference shows XP, next level and the remaining amount [tooltip not shown in the video].

### 2.3 Prayer panel (22:10)
- A 5-column grid of round and diamond icons (red, blue and gold glyphs). Active prayers have a lit backdrop. A footer shows "72 / 99" prayer points.

### 2.4 Boss / encounter HUD (22:10, 23:11)
- **Top-left boss panel**: a dark translucent box; a small header with two quadrant labels ("North West", "North East") over white and yellow sub-bars (multi-part mechanic tracker); the boss name; a wide **green HP bar** with the "1200 / 1200" numbers in the centre.
- Alternative layout (23:11): a **bottom-centre boss bar**, a dark box with the boss name and a red bar "0 / 900".
- **Top-centre achievement popup**: a brown box "Task Completed: Unconventional (6 points)".
- **Overhead icons** (22:10): prayer icons over the player's head (blue mage hat = protect from magic) and counters "24", "18".
- **Max Hit** panel and a latency graph (23:20): these come from a third-party client overlay and are not core UI.

### 2.5 Over-head combat feedback (5:12, 5:34, 7:25–9:30, 11:43, 12:55, 21:20)
- **HP bar**: a thin bar above an entity's head, green with red for missing HP. It only appears while in combat.
- **Hitsplats**: a small splat shape with a number. **Red with a white number = damage** (8, 12, 13). **Blue = 0 / miss**. Several splats in the same tick stack in a diamond pattern (12:55 shows three blue zeros). They sit on the target's body centre.
- **Weapon-style badge**: a round yellow disc with a weapon glyph floats above the player's HP bar in many combat clips. In the reference it most likely shows the current attack-style or boost state. For us: show the active combat stance overhead.
- **XP drops**: a skill icon plus a number, rising in the top-left (or top-centre) of the viewport, one per skill per hit (fist + heart, bow + heart, wizard hat + heart).
- **Speech overhead**: yellow text above NPCs ("Moo", "Zzzzzz").

### 2.6 Dialogue (3:40–4:35)
- It **replaces the chatbox area** with a parchment panel.
- System/tutorial message: a blue title ("Please wait", "Skills and Experience") and centred black body text.
- NPC line: the speaker name as a coloured header, the text centred, a **chathead portrait on the speaker's side** (right side for player lines in this frame), and "Click here to continue" in blue as a link-style prompt.
- Option list: a red "Select an option" header between two decorative sword dividers; the options as centred lines; "More options…" for paging.
- The tutorial guide arrow is a **yellow bouncing down-arrow** over the target NPC (2:45).

### 2.7 Right-click context menu (19:46)
- A small dark box with a grey "Choose Option" header and one line per action.
- Format: **`<Verb> <Target name in yellow> (level-N in green)`**.
- Order: NPC-specific verbs (Talk-to, Pickpocket, Lure, Knock-Out) → **Walk here** → **Examine** → **Cancel**. The top entry is the left-click default. For items on the ground the reference also lists "Take"; inventory items list "Use", "Drop" and "Examine" [not shown here].

### 2.8 Other panels
- **Pet house storage** (23:40): a framed panel with a title bar and close X, a descriptive line, an icon grid with a scrollbar and a checkbox toggle at the bottom. A good template for any collection panel.
- **Achievement diary rewards** (23:30): a 4×3 item grid panel beside the character.
- **World map** (6:55): see section 5.
- Bank, Grand Exchange, shop, trade, equipment, quest list, spellbook, settings: **[not shown]**.

---

## 3. Mechanics shown

1. **Tick-based world** (3:55): all actions resolve on a fixed tick (about 0.6 s) and on a tile grid. A true-tile outline shows where the server thinks you are. For Roblox: a server-side action tick (0.6 s) for skilling and combat, with client interpolation.
2. **Idle skilling actions** (3:40–3:45): click a tree or fishing spot once and the character repeats the action until the inventory is full or the resource runs out. The tutorial text says it directly: "Sit back for a moment while he does all the hard work."
3. **Level gates plus success scaling** (13:17–15:30 captions): a higher level unlocks better resources (rocks, trees, fish, logs) and raises the chance per tick ("Increases chance of getting logs", "lowers your burn rate").
4. **Gathering → processing chains**: logs → fire / fletching; fish → cooking (burn chance); ore → smithing; gems → crafting (20:19 inventory of cut gems); essence → runes at altars (15:38).
5. **Combat triangle** (4:45–4:50): melee, ranged and magic, each with its own tutor, gear look and XP icon. Magic uses elemental strike bolts (6:40) with elemental weaknesses (12:48 caption).
6. **Combat skills**: Attack = accuracy, Strength = max hit, Defence = less incoming damage, Hitpoints = HP pool (and XP on every hit), Prayer = toggled protection and boosts that drain points (bury bones for XP, 18:15).
7. **Training-spot ladder** (7:10–9:30): cows (8 HP) → frogs → dungeon crawlers → ogresses → dormant crabs (members). Each area is tagged free or members.
8. **Dormant ambush mobs** (9:00–9:30): rocks on a beach become crabs when a player stands near, and fall back to rocks after a while. Used for AFK training.
9. **Slayer** (9:43, 17:42): a master NPC assigns a task (dialogue at 4:25: "I need another assignment / Have you any rewards for me / Let's talk about the difficulty…"). Kill N monsters of a type for slayer XP and points. Some monsters need a slayer level.
10. **Quests** (8:37, 10:16, 19:02–19:43, 20:41): about 170 handcrafted quests. Requirements card (quests, skills, items, recommended items, teleports). Rewards: XP, items, and **new areas or features** (gated mansions, villages, tomb). Quest points total.
11. **Group skilling boss** (14:44): players feed braziers in a cold arena. You need Firemaking 50.
12. **Construction / player-owned house** (16:05): build rooms and furniture; the house becomes a utility hub (portals, altars, pet house). Expensive to train.
13. **Agility** (16:32): unlocks map shortcuts and improves run-energy restore. **[run toggle not shown, but the run orb is visible at 92]**
14. **Thieving** (17:10, 19:46, 20:10): pickpocket NPCs from the right-click menu; lure / knock out (blackjacking) variants; market stall theft.
15. **Farming** (18:20): patches with visible growth stages, a scarecrow, flower and allotment patches.
16. **Runecrafting** (15:30–15:46): an essence run to themed void altars. One of the slowest skills, and profitable.
17. **Raids and bosses** (1:56–1:59, 21:31–22:10, 23:11–23:24): themed arenas, floor hazards, boss HP bars, kill-count and personal-best chat messages, combat-task popups with points.
18. **Account modes** (1:28–1:40): Ironman (no trading or GE; self-sufficient), shown with special armour tiers.
19. **Achievement diaries** (23:30), **combat achievements** (23:11), **pets** (23:40), **skill capes at 99** (11:21–18:06), **max total level 2277** (23:35). Level 99 needs about 13M XP.
20. **Not shown**: shops, trading, death mechanics, teleports (only mentioned in the requirements card), banking, GE offers.

---

## 4. Animation and feedback

- **Woodcutting** (3:35): the axe is held two-handed and swung overhead into the trunk in a loop.
- **Fishing** (3:40): crouched at the water's edge with a small net.
- **Mining** (1:28): an overhead pickaxe swing; **chips in the rock's own colour** burst out on each hit.
- **Firemaking** (3:38, 3:45): kneel and strike a tinderbox; a log fire with yellow flames is left on the tile for a while.
- **Bone burying** (18:15): bend over the bones on the ground; XP drop.
- **Climbing** (15:01): rope ladder up a giant trunk.
- **Combat**: weapon-specific swings (scimitar slash, bow draw, staff cast with the projectile). Magic projectiles have coloured teardrop heads.
- **Held items show on the model**: bronze axe (3:35), net, bow, staff, sword and wooden shield (23:51).
- **Skill capes**: a back-cloth with a two-tone border, a unique colour per skill and a central emblem; gold-trimmed (shoulder accents) once mastered.
- **Idle NPC cues**: "Zzzzzz" over a sleeping NPC, "Moo" from cows.
- **Implied sounds** (no audio used): an axe-chop thunk per tick, a splash on fishing, a pick clink, a fire crackle, a hitsplat thud with a separate miss "whoosh", a level-up jingle, a boss countdown sting.

---

## 5. World and art direction

- **Geometry**: deliberately low-poly with flat shading and big texture-free colour blocks. Trees are faceted canopies on a single trunk. Characters have chunky proportions with bald default heads.
- **Palette**: saturated grass green (#7FB03A-ish), grey cobble roads, tan dirt paths, light-blue water with flat shading. Biomes swap the palette strongly: teal and olive swamp (0:29), white and blue ice (12:55), red-black lava (23:20), sand and palm desert (19:47), pastel coral underwater (19:48), purple-grey gothic city (1:57), glowing lime crystal caves (1:56).
- **Towns** (4:05, 16:00, 22:39): grey stone castles with **cross-shaped arrow slits**, blue heraldic shield banners and crenellated walls. Thatched or brown-roof cottages. Timber-frame halls with white plaster panels and leaded windows (20:10). Stone arch bridges over rivers into walled towns (a recurring "arrival" shot).
- **Roads and signs**: grey cobble roads with soft edges; **wooden signposts with arrow planks at every junction** (5:44, 16:00); wooden post-and-rail fences line the paths (3:30).
- **Landmarks**: the central trade plaza (1:15) as a social hub; a colosseum on the second continent (2:05); a pyramid in the desert city; giant redwood trees; floating rune altars in void space (15:38–15:46).
- **Interiors**: tutor houses dressed with tools on the walls, posters, workbenches, anvils, archery targets (5:25, 6:11). Player houses use bold striped walls (16:05).
- **Dungeons**: dark backgrounds, props (bones, webs, crates), blood decals (17:56); boss arenas have bold geometric floor patterns (21:41, 22:10).
- **Lighting**: mostly flat daylight with simple ambient light. Caves use darkness plus emissive props (green crystals, lava). There are no dynamic shadows to speak of; readability beats realism.
- **Map** (6:55): painted parchment top-down; region names in large orange serif, town names in white caps, round service icons, blue rivers. Islands on open water are clearly outlined.
- **Starter island** (3:26): a compact green isle floating among small rocky islets on a blue backdrop. This is the closest reference to Aether Isles' floating-isle look.

---

## 6. Prioritised features and UI patterns to adopt (original designs)

**P0 — core loop and HUD (build first)**
1. **Tick-based server action loop** (0.6 s). Click a resource once to keep working until the inventory is full or the node is depleted. Success chance scales with level; level gates node tiers.
2. **28-slot backpack** (4×7) with stack counts in a corner, colour-coded by size (normal / thousands / millions). Original frame art (e.g. carved driftwood and brass instead of stone).
3. **Right-side tabbed panel** with icon tabs (Backpack, Gear, Skills, Journal, Abilities/Prayer-equivalent, Spellbook, Social, Settings). One tab open at a time. Mobile: collapse to an edge button strip.
4. **Status orbs around the minimap**: Health, Spirit (prayer equivalent), Stamina (run; click to toggle sprint), Special. Each is a circle with an icon, a value and a radial fill. Include an XP-tracker button.
5. **Context action menu**: `Verb + Target (lvl N)` with the target in an accent colour, game-specific verbs first, then **Move here → Inspect → Cancel**. On desktop, top-left hover text shows "Default action / N more options". On mobile, long-press opens the menu.
6. **Combat feedback**: overhead HP bars only while in combat; damage splats (red = hit, blue-grey = miss/0); multiple splats per tick stacked; **XP drops** as icon plus number rising in the viewport, one per skill gained.
7. **Skills grid**: 3 columns, each cell icon plus "current/base", the last cell Total Level; hover shows XP, next level and progress. Level 99 cap on an exponential curve (about 13M XP at the cap).

**P1 — onboarding and content structure**
8. **Starter isle tutorial**: a compact floating island, one tutor per building, tabs unlock one at a time, a bouncing guide arrow over the next NPC, and a "please wait" explainer for idle actions.
9. **Dialogue panel in the chat slot**: speaker portrait, name header, "continue" prompt, an option list with paging. Use original decorative dividers (e.g. vine or feather motif, not swords).
10. **Chat with filter tabs** (All / Game / Public / Private / Party / Guild / Trade) showing On/Filtered/Off state, and colour-coded system lines (warnings, achievements, rare-drop broadcasts, kill times and personal bests).
11. **Combat triangle** with three tutor huts and starter outfits; elemental spell glyphs; a stance badge shown over the player.
12. **Training-spot ladder per island**, including **dormant ambush mobs** (rocks or shells that wake into creatures near a player) for relaxed AFK combat.
13. **Quest journal with requirement cards** (quests, skills, items, recommended items, travel options) and an in-game recommended quest order, so players don't need an external wiki. Quests unlock islands, shortcuts and features.

**P2 — mid/long-term systems**
14. **Task-master system** (slayer-like): dialogue to get or reroll a task, task points, a rewards shop.
15. **Personal island as utility hub** (construction-like, fits SkyBlock): build rooms or plots that give portals, altars and storage (including a pet-storage panel with a grid and an "allow to roam" toggle).
16. **Co-op skilling boss**: players feed or charge a shared object in a hostile environment; gated by skill level.
17. **Essence-run crafting skill** with altars on small void islands reached by portal.
18. **Boss HUD**: top-left boss card (name, HP bar with numbers, sub-mechanic meters), countdown chat lines, kill count and personal-best messages, a **task-complete toast** with points.
19. **Agility shortcuts** on the island map and a stamina-regen bonus from the agility skill.
20. **Mastery cosmetics**: one unique cape or back-item per skill at the cap, an achievement cape for completionists, diary-style regional task lists with reward-panel grids, and pets as rare drops.
21. **Self-sufficient account mode** (no trading) with distinct cosmetic armour.

**Art direction to adopt**
22. Detailed meshes with strong biome palette swaps per island. Signposts at every path junction, fenced dirt paths, stone arch bridges as arrival moments, heraldic banners on our own (original) factions, emissive props in caves, and boss arenas with geometric floor patterns.
23. World map in a painted-parchment style: island names in large serif, town names in caps, round service icons.

**Gaps to fill from other references:** bank, central-market offer UI, shop and trade windows, equipment slots, spellbook and settings layouts, death and item-retrieval rules, teleport effects, the level-up popup.

> **Owner direction:** ignore any low-poly / flat-shaded model recommendation in these notes. The game targets detailed meshes and rich visuals.

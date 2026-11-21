# Design notes: "COMPLETE beginner's guide to Old School RuneScape" (local file, 40:07, 640x360)

Source: `scratchpad/drive/osrs.mp4`. Frames were pulled with the watch skill's local engine: 4 windows × 40 balanced frames, plus 40 timestamp-cued frames at 1024 px. The source is only 360p, so upscaling did not recover small text, and every text reading below is best effort. No transcript was used (`--no-whisper`, and the file has no captions), so section topics come from the presenter's on-screen title cards and from what the screen shows. All video content was treated as data.

**What kind of video this is:** this is a talking-head and screen-capture *meta guide*, not a gameplay walkthrough. Roughly 45% of the runtime shows websites: the official site, the community wiki, the launcher, a third-party client's plugin hub, YouTube, Twitch and social media. The in-game footage is short clips from the presenter's high-level accounts that illustrate each topic. The video is still useful because it shows **what a new player is told to care about, and in what order**. That ordering is a strong onboarding blueprint.

Reference product: OSRS (Jagex). Throughout this document, "AI" means Aether Isles, our game. **Everything we adopt must be an original design. No names, icons, item designs or branding may be copied.**

---

## 1. Timeline (chapter map)

| Time | Chapter (from title cards and screens) | What is shown |
|---|---|---|
| 00:00–01:11 | Cold open | Black frame, then a close-up of the presenter's avatar (seasonal santa hat, dark-blue shirt, red cape). |
| 01:11–01:28 | History | An archived 2004-era official homepage ("25,538 people playing"). The 2013 "Old School servers now open" poll page, with a vote meter at 449,351 and tiers at 50K/250K/500K/750K, plus the announcement text: polls decide changes and there is a zero-tolerance botting stance. |
| 01:49–02:12 | World flyovers | Riverside timber-frame town; a swamp path with signpost; a stone castle courtyard with fountains and banners. |
| 02:16–03:00 | "Use the wiki" | Browser typing a short wiki URL; wiki home (30,216 articles); slang dictionary; wiki sidebar guides list. |
| 02:24 | First in-game HUD | Fixed classic layout with the **Display Settings** panel open. |
| 03:18–04:00 | Getting the game | Official site sidebar (Download, World Select, World Map, Redeem Code, News, Status, Launcher; Community: Polls, Polling Charter, HiScores, Roadmap, Grand Exchange, Forums, Wiki). Buttons: "New User? Sign up", "Free player? Play Now!", "Member? Play Now!". Launcher: game tabs, client dropdown, **character dropdown** (several characters under one account), age rating. |
| 03:36–05:06 | Third-party client and plugins | Plugin list with star favourites, per-plugin cog and toggle (Agility, Bank Tags, Boosts, Clue Scroll, Detached Camera, Entity Hider, GPU, Inventory Tags, Loot Tracker, Menu Entry Swapper, NPC Aggression Timer, Party, Player Indicators, Collection Log, Combat Level, DPS calculator…). Plugin hub warning; installed: Quest Helper, HD renderer, minigame helpers. |
| 05:06–05:50 | Official site and rules | News scroll page; Rules page: Real-World Trading; Macroing and third-party software. |
| 05:50–06:40 | Tutorial island | Tutorial NPC dialogue ("You're nearly finished… speak with the magic instructor… teleport you"), a **"Tutorial Island Progress" bar** at the bottom of the viewport, a starter kit in the inventory, and a yellow bouncing **hint arrow** over the target. |
| 06:15–06:40 | Ironman setup | The account-mode interface: Solo/Group tabs; None / Standard / Hardcore / Ultimate; a deactivation-settings lock. |
| 07:13–07:22 | First steps | Castle courtyard flyover; a crowded cow field with many players, HP bars over heads, and players in high-tier gear. |
| 07:41–07:50 | World map | Lumbridge zoomed in, then the wider kingdom. Key panel; tooltip "Poll booth". |
| 07:50 | Grand Exchange | "Set up offer" buy panel; the item-search prompt moves into the chatbox. |
| 08:26–10:00 | Membership and bonds | Bond 3D render; "11M gp → bond"; "8x $1 bond → 14 days of membs"; wiki bond infobox; price-history graph. |
| 10:00–11:54 | Skills and money | Skills tab (everything 99, total 2277); per-skill **unlock guide** (Mining → Rocks / Equipment / Areas / Shooting Stars); bank booth hover; wiki money-making guide; "50–100 hours for 1st bond" over a crafting profit table. |
| 12:20–13:30 | Money making in game | GE guide-price window; fungi on logs in a swamp, with a spammed "Wait a bit before doing that again"; a wilderness-teleport block message. |
| 13:26–14:10 | Money-making table | Abyss runecraft guide page (requirements block); sortable money-making table (method, hourly profit, skills, category, intensity, members star). |
| 14:30–17:42 | Quests | Farming/teleport footage; Heroes' Quest and Dragon Slayer wiki pages; Quest List tab ("Quest Points: 257"); end-of-quest NPC dialogue; **quest-complete scroll**; quest point cape icon; optimal quest guide; a long quest walkthrough (sliding puzzle, prison-break map with yellow aggressive-NPC dots); a Quest Helper overlay in game; a YouTube channel of quest guides. |
| 18:02–18:38 | Quest list menu | Right-click on a quest entry: Read journal / Show on map / Open wiki guide / Open wiki quick guide / Stop Quest Helper / Cancel. "Completed: 142/159", "Quest Points: 269/301". |
| 18:29–19:28 | Achievement diaries | Wiki page (12 areas, 492 tasks, Easy/Medium/Hard/Elite); regional diary pages with map widgets; an in-game diary tab with per-region progress bars; a "Long term goal" card. |
| 19:28–20:58 | Goals | Long-term cards ("100M"; a "diary cape" card); medium-term cards (a weapon icon, a bow plus "75", a robe set). |
| 20:34–21:39 | Ironman guide | Pastebin ironman guide v4; a stepwise guide site with chapters and checkboxes; "Barrows gloves" title card. |
| 21:39–22:04 | Key milestone item | A Recipe-for-Disaster style long quest page; the glove stat panel (+12 across the board); "Diary cape" with its skill-requirement grid. |
| 22:04–22:26 | Minigames | "Barbarian Assault" (role-based wave minigame): role icon bar, call text, Combat Options showing an autocast staff. |
| 22:26–24:13 | Daily/run loops | "Herb runs": farming patch table (location, closest teleport, map), herb calculator with probability formulas. Fairy-ring style teleport circle; "Graceful outfit" bank shot; bank UI in detail. |
| 24:52–25:28 | Blast-furnace style minigame | Top-down factory, coffer timer, profit tracker; "Spirit trees" network teleport, with a dialogue box and a "Travel" right-click option. |
| 25:39–26:39 | Utility | Equipment tab; "Birdhouse runs" with a house-portal loading screen ("There's no place like home…"); "Bone Voyage quest unlocks Fossil Island"; a purple portal. |
| 26:29–27:28 | Slayer | Slayer master on a tower ("Assignment" left-click); task-complete chat messages; a crowd of demons in a cave; a boss ground-item right-click "Take" menu; a superior slayer monster; burying bones. |
| 27:28–28:06 | Skilling minigames | Title card with skill-stats icon; a naval-cannon cooperative minigame (Energy/Essence/Storm-intensity bars, points); a giant's-foundry style minigame (heat/temperature bar with target zones, NPC "sword look good. Hand over."). |
| 28:06–28:49 | Skilling outfits and prayers | Wiki; "Overheads" card; the prayer book with a "Protect from Melee" tooltip; the snowy God Wars area. |
| 29:23–30:00 | Construction and POH | House loading screen; "Armour Case" storage with 25/105 sets; ornate jewellery box right-click "Teleport Menu"; a chaos-altar style bone offering. |
| 30:00–30:32 | Worlds | World switcher: world list with flags, player counts and activity labels ("House Party", "Group Iron", "Castle Wars", "Wilderness"…). The "world 330" house-party world. |
| 30:10–33:16 | Community | A crowded party at a house portal (dozens of players; chat fills with cheers); a dock dance; social gatherings; a village alley; a castle wall. Note on in-game cosmetic social items. |
| 32:08–34:59 | Social and IRL | YouTube recommendations; a Discord share of a screenshot ("Woodcutting(15)" auto-screenshot); boss-drop footage with a collection-log message; real-life meetup and event photos (people not described). |
| 33:30 | Scams warning | "There is no double XP" / "GE spammers are scammers". |
| 34:59–36:03 | Twitch | OSRS directory of live channels (HCIM, UIM, raids, PK, inferno…). |
| 36:03–36:47 | World art | Purple-sky cliff with an observatory-like orb building and a wizard NPC. |
| 36:47–39:00 | Endgame tease | Chop-tree hover; Inferno final boss (wave 69, predicted time); a raid ("Chambers") completion; raid reward chest; the presenter's reaction cam. |
| 39:08–40:03 | Outro | Presenter's channel playlists (Leagues, GIM, UIM, HCIM, Road to Max); a guide video page; comments; closing shot by a lake with a shipwreck. |

---

## 2. Interface elements (timestamped)

### 2.1 Overall layout (seen at 02:24, 03:57, 10:14 and many later frames)
- **Fixed classic layout:** the 3D viewport occupies the top-left (about 68% × 67%), with the chatbox under it and a stone-framed side column on the right.
- Side column, top to bottom:
  - circular minimap with a compass;
  - four **orbs** curved down the minimap's left edge;
  - a top tab row of 7 icons;
  - a content panel (inventory or any other tab);
  - a bottom tab row of 7 icons.
- The frame is carved grey/brown stone with rivets. All text uses a pixel/bitmap font: **yellow-orange for headers, white for body text**, with a drop shadow.
- At 03:57 the third-party client shows the same UI with a **resizable/plugin sidebar** to the right: icons for plugin config, hiscores, loot, notes, and so on.

### 2.2 Minimap and orbs (02:24, 10:14, 24:52)
- Circular map with **dots: yellow = NPCs, white = players, red = ground items**, plus quest, bank and shop icons. A compass sits at top-left; clicking it resets north.
- Orbs (value plus coloured icon):
  - **HP** (red heart; the number turns green or yellow when poisoned or boosted);
  - **Prayer** (blue-white star);
  - **Run energy** (yellow boot/coin; click to toggle run);
  - **Special attack** (bottom; a crossed-swords style icon);
  - an "XP" button at the top to toggle the XP drop tracker.
- Small "world map" and "wiki" buttons under the minimap (03:57 shows a "WIKI" banner button that links in-game items to the wiki).
- 24:52: a red arrow annotation points at the run-energy orb ("stamina"), showing it drains during the minigame.

### 2.3 Side-panel tabs
- **Top row:** Combat Options (crossed swords), Skills (bar chart), Quest list (circular blue icon), Inventory (brown bag), Equipment (figure), Prayer (star), Magic (spellbook).
- **Bottom row:** Account/Clan-group (people icon), Friends (smiley), Ignore/Account management, Logout (door), Settings (wrench), Emotes (dancing figure), Music (harp).
- Seen open:
  - **Settings** (02:24): sub-tabs for Controls, Audio and Display. **Display Settings** has a brightness slider (sun icon), a zoom slider (magnifier), and a "Game client layout: Fixed – Classic layout" dropdown, plus an "All Settings" button.
  - **Skills** (10:30 cue): a 3-column grid of 23 skill icons with level fractions ("99/99"), and a **"Total level: 2277"** box at the bottom right. Clicking a skill opens a parchment **Skill Guide** overlay (10:30: Mining). Rows show level, ore icon and name with parenthetical unlock conditions ("Rune essence (after Rune Mysteries)", "Barronite (after Below Ice Mountain)"). Right-side category tabs: Rocks / Equipment / Areas / Shooting Stars.
  - **Quest list** (15:15, 18:02): "Quest Points: 257" header and colour-coded names (**red = not started, yellow = in progress, green = complete**). Filter dots at top right. A footer shows "Completed: 142/159" and "Quest Points: 269/301". A right-click context menu covers journal, map pin and guide links.
  - **Achievement Diary tab** (18:50 cue): a list of regions, each with a thin **progress bar** (yellow when partially done) and a counter ("Ardougne 10/42", "Karamja 1/44"). Region names are colour-coded: red = none, yellow = partial, green = done.
  - **Equipment** (13:01, 25:39): the worn-equipment paper-doll. Slot silhouettes for head, cape, neck, ammo, weapon, body, shield, legs, hands, feet and ring. Four buttons along the bottom: View equipment stats, Price checker, Items kept on death, Call follower.
  - **Equip Your Character / equipment stats** (24:30 cue): the character model renders in the centre. The slot grid is on the left with a weight readout ("-24 kg"). The right side lists stats: Attack bonus (stab/slash/crush/magic/range), Defence bonus, Other bonuses (melee str, ranged str, magic dmg %, prayer), Target-specific (undead %, slayer %), and **Weapon speed (Base 2.4s / Actual 2.4s)**.
  - **Prayer** (28:35 cue): a grid of prayer icons; active prayers have a bright backing. Hover tooltip: "Level 43 / Protect from Melee / Protection from close attacks." Footer: "97/99" prayer points and a "Filters" button. Overhead-prayer icons are introduced by the "Overheads" title card (28:23).
  - **Combat Options** (22:04): weapon name, "Combat Lvl: 82.3" and a 4-style grid (Bash/Pound/Focus + **Spell/autocast slots** with blue/red highlight). "Auto Retaliate (On)" toggle. Category: Staff.
  - **Magic / spellbook:** only the icon is visible. One chat line (13:05) reads "You have changed your spellbook 1/5 times today".
  - **Music:** the "You have unlocked a new music track" message (16:50).

### 2.4 Chatbox (all gameplay frames)
- Parchment background with **filter tabs** along the bottom: All, Game (Filtered), Public (On), Private (On/Friends), Channel (On), Clan (On), Trade (On) or Group, and a red **Report** button. Each tab has a status subtitle in green, yellow or red.
- The input line shows "Name: *" with a blue asterisk cursor.
- **Colour coding** (13:01, 26:29, 26:39):
  - black = game messages;
  - **red = drops, warnings and system notices** ("Valuable drop: …(119,286 coins)", "You have completed your task!", "A superior foe has appeared…");
  - blue-bracketed [Clan] lines;
  - purple = collection-log messages;
  - green = broadcasts.
  - Separately, the "Untradeable drop:" lines are red.
- The chatbox doubles as a **dialogue panel**:
  - NPC portrait on the left, name in red, body text in black serif, and a blue "Click here to continue" link (15:15, 25:14, 27:55);
  - item/flavour portraits, e.g. a spirit-tree icon with "You place your hands on the dry tough bark…";
  - the GE item-search prompt ("What would you like to buy? Start typing the name of an item… Show last searched").
- Repeated-action spam ("Wait a bit before doing that again" ×6, 13:01) is a weak point. We should rate-limit and collapse repeated messages.

### 2.5 Mouse-over text and right-click menus
- Top-left of the viewport always shows the **left-click action**: "Walk here", "Bank Bank booth / 3 more options", "Pick Fungi on log / 2 more options", "Assignment Duradel / 5 more options", "Activate Quick-prayers / 1 more options". A hover tooltip near the cursor repeats it in yellow/cyan.
- **Right-click "Choose Option" menu** (18:02, 26:55, 29:40): dark translucent box. Each row is a white verb followed by a coloured target name (orange = item, cyan/yellow = object/NPC, green = level). Examples: Take/Examine per item, Walk here, Cancel; "Teleport Menu / Edgeville / Examine / Remove Ornate Jewellery Box".
- The settings chat line "The default worn left click option for 'X' has been set to 'Y'" (13:01, 14:50) shows **user-remappable left-click actions**.

### 2.6 XP drops, counters and overlays
- The XP-drop/tracker toggle sits by the minimap. A **total-XP counter box** at top centre shows a bar icon and a large number (e.g. 555,571,551), and individual drops float up from it ("+42,970" at 24:52; "+1,342,326" and "+3,720,830" at 27:51–27:55 show minigame points or XP).
- Raid overlay (06:15, 38:56): "Total / Name / Time / Unique %" points box at top right. Party list box ("Party: names") at 12:50/09:18. **Boss HP bar** at top left ("Great Olm – Head 0.0%"; "TzKal-Zuk" with a red bar and HP numbers). Prayer and potion **timer badges** sit at the bottom-left of the viewport.
- Tutorial overlay: a **"Tutorial Island Progress" bar** across the lower viewport (09:05 cue), and a yellow bobbing arrow above the objective (06:40 cue).

### 2.7 Hitsplats and HP bars (07:22, 22:04, 26:36)
- Each NPC and player has a **small green/red HP bar overhead**, shown only while in combat.
- Hitsplats are **red splats with white numbers** for damage and **blue splats for 0 (miss)**; one green splat appears for poison (22:04: "26" red, "0" blue).
- Boss/minigame overlays add tile markers: yellow squares for safe tiles, cyan for special tiles (39:12–39:14 Inferno; raid tiles at 06:15).

### 2.8 Level-up
- Shown as a chat line: "Congratulations, you've just advanced your Thieving level. You are now level 34." (18:50 cue). The usual fireworks were not captured.
- Quest complete: a **parchment scroll** with a wax seal and rosette ribbon (15:33, 15:40). It lists "You are awarded: 5 Quest Points, Access to X Guild, 80,000 Smithing XP …" and "Total Quest Points: 263", with the quest's key item rendered at the left.
- Diary task: a red chat line ("Well done! You have completed an easy task in the Ardougne area. Your Achievement Diary has been updated.").

### 2.9 Bank (10:50, 23:46, 24:13)
- Window titled "Tab 4 (15.9M)", meaning **the tab name plus its total value**. Top-left shows slots used ("842/800" style). Help "?" and close "X" buttons.
- Tab row of item-icon tabs (custom tab icons) plus a "∞" all-items tab.
- An item grid with stack numbers in yellow/white (green for 10M+). A left sidebar has equipment/potion quick buttons.
- Bottom bar:
  - Rearrange mode: Swap / Insert;
  - Withdraw as: Item / Note;
  - Quantity: 1 / 5 / 10 / X / All;
  - icons for Bank PIN lock, Search, Deposit inventory and Deposit equipment.
- The bank PIN flow is implied by the chat message "You have correctly entered your PIN."
- While the bank is open, the inventory side panel switches to the deposit view.

### 2.10 Grand Exchange (07:50, 12:20, 09:05)
- "Grand Exchange: Set up offer" panel with a "History" button. An item slot and "Choose an item…" sit on the left. The Quantity row has −/+ and **+1 / +10 / +100 / +1k / …**. The Price-per-item row has −5% / guide price / … / +5% buttons. There is a Confirm bar and a Back arrow.
- Item search moves into the chatbox.
- **Guide price checker** window (12:20): the items you deposit show a per-item × qty value, plus a "Total guide price".
- Web-side price graph (09:05 cue): a long-range line chart with a 30-day average and zoom ranges 1m/2m/3m/6m/1y/All. A wiki infobox (08:52) shows Exchange price, **Buy limit 100**, alchemy value, weight, and Tradeable/Equipable/Stackable/Noteable flags.

### 2.11 World map (07:41–07:50)
- Full-screen map with a parchment-brown **Key panel** on the left. Game features with icons: Agility shortcut, Altar, Bank, Clan Hub, Combat Achievements, Death's Office, Distraction & Diversion, Dungeon, Hairdresser…
- Toggles: "You are here", Intra-map links, Map labels, Icon tooltips, Effects.
- Large orange region labels ("Kingdom of …"); town labels in white. Icon density is very high, with green checkmark badges on icons (completed). Hovering an icon shows a yellow tooltip ("Poll booth").

### 2.12 World switcher (30:10–30:32)
- Side panel titled "Current world – 338". Each row has a favourite star, world number, **country flag**, player count and **activity label** (House Party, Tombs of Amascut, Nex FFA, Castle Wars, Group Iron, Nightmare, Wilderness, Guardians…).
- The current world is highlighted green. On a busy world, a game message suggests switching to a quieter one (31:45 cue).

### 2.13 Clue scrolls
- These appear only indirectly: the plugin list entry "Clue Scroll" (03:36) and wiki "Reward casket (easy/medium/hard)" recent changes (02:45 onward). No in-game clue UI was shown.

### 2.14 Other interfaces
- **Ironman Setup** (06:25): parchment-dark modal with Solo Modes / Group Modes tabs and radio rows (None, Standard, Hardcore, Ultimate). Each row has an orange description, and there is a padlock "Deactivation settings" row.
- **Armour Case** (29:53): POH costume storage. Collapsible set rows with a 25/105 counter; collected pieces show in full colour and missing ones are greyed.
- **Ornate jewellery box** right-click teleports (29:40); **portal nexus**-style portals at a house party (30:10).
- **Raid Rewards** window (37:20 cue): a chest render with loot icons.
- **Slayer skill guide** (27:05 cue): "Slayer Masters – Members only", with each master listed by combat requirement; tabs Monsters / Equipment / Slayer Masters.

---

## 3. Mechanics and progression shown

### 3.1 Skills and training
- There are 23 skills. The maxed reference (10:30) shows 99 in all of them and a total of 2277; the endgame "max" goal is a cape.
- Training methods glimpsed:
  - Mining, with the per-skill unlock list showing gated ores;
  - Thieving: pickpocketing paladins in the money table;
  - Runecraft through an Abyss-like shortcut dimension;
  - Farming: herb runs across ~8 patches with teleports, disease probability and composts (22:26–23:29); "ultracompost" treat messages (14:50);
  - Hunter: birdhouse runs on an unlocked island (25:53–26:00);
  - Smithing: blast-furnace factory with a coffer (24:52);
  - Agility, Woodcutting ("Chop down Tree", 36:47);
  - Prayer: bones on a chaos altar (29:10 cue);
  - Construction: player-owned house (29:23–29:57).
- **Skilling minigames** (27:28–28:06) are cooperative or timed objective loops with bespoke bars: an energy/essence/"storm intensity" trio, and a heat bar with target bands. They reward points that buy **skilling outfits** (an XP-bonus set, 28:06) and the graceful agility set (23:46: a weight-reducing outfit that boosts run regen).

### 3.2 Money making
- Wiki money-making guide (10:50–14:08): a sortable table with columns Method, Hourly profit, Skills (icons plus levels), Category (Skilling/Runecraft, Processing, Combat/Mid…), Intensity (Low/Moderate/High) and Members star.
- Values range from ~650k/hr down to ~200k/hr for low-requirement processing methods. The presenter's message is "50–100 hours for 1st bond" (11:40).
- In-game examples: fungi picking (13:01), GE guide-price checking (12:20), and blast furnace (24:52).

### 3.3 Membership and bonds (08:26–10:00)
- A tradeable token buys 14 days of membership. It can be bought with real money (~$8) or for ~11M gold on the exchange. **The tradeable↔untradeable conversion costs 10%.** Players can hold up to 20 bonds in a bond pouch. Price history climbs steadily (2.5M in 2016 → ~10M+ in 2024).

### 3.4 Quests and rewards (14:08–18:38)
- 159 quests and 301 quest points. Each quest has an official difficulty (Novice→Grandmaster, plus "Special"), a length (Short→Very Long), requirements (skills, items and prior quests), and a series grouping.
- Rewards: quest points, large XP lamps, **area or guild access**, item-equip permission (a dragon-slaying quest grants the right to wear top-tier platebody armour), and fun unlocks such as speaking to cats and petting a dog.
- Puzzle content inside quests: a sliding-tile puzzle (17:22) and a stealth prison break with patrolling guards and timed lockpicks (17:23–17:35).
- Community "optimal quest order" guides exist because quest rewards double as skill-training shortcuts.
- In-game **Quest Helper** overlay (16:50): an objective label at the top-left ("Song of the Elves – Touch the Seal of the Forgotten") plus a highlighted route.
- "Recipe"-style megaquest that gates the best-in-slot gloves for mid-game (21:04–21:53). The gloves give +12 to all attack and defence styles. The presenter treats them as a **mid-term milestone**.

### 3.5 Achievement diaries (18:29–20:58)
- 12 regional diaries with 4 tiers each (Easy/Medium/Hard/Elite), 492 tasks in total. Rewards per tier: a **region-themed wearable item that upgrades per tier** (e.g. a cloak), lamp XP (2.5k/7.5k/15k/50k), and regional perks.
- The wiki tracker has toggle tables for skill, quest and additional requirements, with green highlighting for met requirements and counters like "Clear selection 9/10" (18:45 cue).
- The completion cape requires a large skill table (combined 1955+ total, 22:04 cue). Rewards are claimed from a regional NPC.
- Combat Achievements are a parallel combat-task system (wiki link only).

### 3.6 Goal setting (19:28–20:58)
- Title cards split goals into **long-term** (max/diary cape, 100M gold, an infernal-style cape) and **medium-term** (a specific weapon, a ranged level of 75, a robe set).
- This is a strong UX lesson: the game never states these goals, and players must import them from guides.

### 3.7 Combat
- Three styles in a triangle (melee/ranged/magic). Combat level is a decimal (82.3). Auto-retaliate is available, as is autocast.
- **Protection prayers** and overheads are introduced as a must-learn (28:23–28:35).
- PvM highlights:
  - slayer bosses with ground-loot menus (26:55);
  - a wave-based fire cave final boss (39:13–39:14: "Wave: 69", wave split and predicted time, "has become enraged and is fighting for his life");
  - a 3-player raid with points, personal-best times and a kill-count chat line (38:56);
  - God Wars kill-count style counters (26:39: "Icefiend"/0–20, killcount tracking).
- Drops: "Valuable drop" and "Untradeable drop" chat lines with GE values. **Collection log** messages: "New item added to your collection log: X (433/1404)". Personal-best fight durations are shown.
- Wilderness teleport restriction (13:05 cue): "A mysterious force blocks your teleport spell! You can't use this teleport after level 20 wilderness."

### 3.8 Slayer (26:29–27:17)
- Assignments come from masters gated by combat level (Turael-style 3, 20, 40, 70, 75, 85…). The task completion message shows kill count, XP gained, total tasks and points ("You've completed 782 tasks and received 15 points, giving you a total of 5,693").
- Superior slayer monsters are rare spawns with a red alert. A slayer ring carries charges. A "Slayer helm" is implied.

### 3.9 Minigames
- Barbarian Assault: 4 roles and waves (22:04); the role call is shown in orange text overhead.
- Blast Furnace (24:52).
- Cooperative naval/boss skilling (27:51).
- Giants' Foundry-style smithing (27:55).
- Castle Wars, Guardians and others appear as world labels (30:10).

### 3.10 Teleports and travel
- Spirit-tree network: right-click "Travel" (25:09–25:22).
- Fairy rings: 3-letter dial codes ("a-l-q" in the patch table, 23:10 cue; mushroom ring at 23:29).
- Jewellery teleports (glory, dueling, skills necklace, wealth).
- House portal nexus and jewellery box (29:40).
- Spellbook teleports; quest-unlocked islands (Fossil Island via quest, 26:00).
- Charter ships; minigame teleports ("Minigame tele to fish trawler" in the ironman guide).
- **The herb-patch table lists 4–7 alternative teleports per destination.** Travel planning is itself a skill-like layer.

### 3.11 Ironman modes (06:15, 20:34–21:39, 34:59 onward)
- Standard: no trading, no staking, no PK loot, no picking up others' drops, restricted multiplayer minigames.
- Hardcore: one life; dying downgrades the account to Standard.
- Ultimate: no bank, and no items kept on dangerous death.
- Group: shared progress within a team (Group Iron worlds and a group-storage chat channel "////").
- The status can be **locked** against accidental downgrade.
- The community writes long self-sufficiency route guides for these modes, with checkbox progress.

### 3.12 Membership areas
- The site separates free and members worlds. The wiki shows "Members: Yes/No" per item, quest and diary. The map shows the wider members kingdom beyond the free starter area. The money table carries a members star.

---

## 4. Animations and feedback

- Idle and walk cycles are simple. The santa hat and cape show basic cloth swing (01:10, 09:31). For Aether Isles, aim for fuller animation sets and secondary motion on capes and hair.
- Bobbing yellow quest arrow (06:40). The Tutorial progress bar fills.
- Hitsplats pop with a short scale. HP bars appear only in combat. Overhead text appears for chat and minigame calls ("Defender: Drop Worms!").
- Ground-item text labels show value colouring (26:39: "Black mask (10) (GE: 573k gp)"; this is plugin-style).
- Loading-screen vignette when entering the house: a sepia render of a cottage with smoke and the caption "There's no place like home…" (25:53, 29:23).
- **Purple portal** ellipse on the ground (26:00, 31:45).
- Raid crystal-shatter and chest-open reward moment; the presenter's live reaction (37:20) shows how much **rare-drop anticipation** drives engagement.
- Party/celebration scenes: player crowds with emote spam, chat floods ("Woot", "Gz") and heart-shaped cosmetic effects (30:10 crowd with ♥ icons overhead).
- Annoyance feedback: the "Wait a bit before doing that again" spam is a negative example.

---

## 5. World and art direction

- **Style (reference only, not a target):** the reference game uses a dated low-poly look, but Aether Isles is aiming for detailed meshes and rich visuals. Take only its colour, layout and lighting lessons. **Palette:** saturated grass greens with mottled ground variation, stone greys and warm wood browns. **Atmosphere:** distance fog/haze against a sky whose tint is set per biome (light blue by day, purple for magical zones at 36:03, dark red-black for volcanic caves at 39:13).
- Regions seen:
  - **Starter town** on a river (01:49): timber-framed white-plaster buildings, wooden fences, a riverbank with reeds, mountains behind.
  - **Swamp road** (01:57): grey gravel path with white scattered stones, dead black trees, a signpost board with an icon. The palette shifts to an olive/grey-green sky.
  - **Castle town** (02:12, 07:13): crenellated grey stone walls with arrow slits, blue-and-white heraldic banners, tiered stone fountains, a cannon courtyard, orange-tiled roofs.
  - **Snowy village** (04:18): snow ground, snow-covered fences and roofs, lamp posts, flowers poking through, a stone house with a warm lit window.
  - **Farm fields** (07:22): rolling green hills, split-rail fences, cows. This is a social "first-combat" hub with many players.
  - **Desert** (26:00): a sand-coloured town with a purple portal.
  - **Tropical jungle** (15:15, 33:16): vines, docks over blue water. **Gnome/tree city** (17:12).
  - **Ice/snow mountain dungeon** (26:39, 28:49): white fog and snow particles.
  - **Purple cavern** with demons (26:36); **volcanic arena** with lava channels (39:13); **raid caves** in teal and green (06:15, 38:56).
  - **Magic plateau** under a purple sky with an observatory orb (36:03).
  - **Village alley** (30:32) with grey stone cottages, green glass windows, bunting strung overhead and a castle gate at the end, giving a strong leading-line composition.
  - **Lakeside** with a shipwreck hulk (40:03).
- Roads are grey gravel ribbons with scattered white chips. They meander and are always fenced on one side, which acts as a guidance line. **Signposts** sit at junctions.
- Lighting in the base game is mostly unlit. The popularity of the HD plugin renderer (05:06), which adds shadows and dynamic lighting, shows that players want richer lighting. That supports our detailed-visuals direction. Interiors use checkerboard floors (banks, 11:54) and red carpet with diamond patterns (chaos temple, 29:10).
- The UI material language is **carved stone frames plus parchment panels plus a pixel font**. It is consistent and thematic, but dated at high resolution.

---

## 6. Ecosystem observations (relevant to design)

- Players rely on **external tools** for core needs: wiki calculators (Farming/Herbs with probability formulas, DPS calculator, skill calculators, 23:23–23:29), quest guides, money tables, plugin overlays (loot tracker, ground-item values, boss timers, tile markers, quest helper), and price history.
- **A guide video is necessary only because the game hides these systems.** Aether Isles should build the most-used of them into the game, in an original form.
- Social layer: clans, group chat channels, party worlds, Twitch "content-mode" accounts (HCIM, UIM, GIM, "Road to Max") and YouTube series. Self-imposed restrictions are a form of content.
- Anti-scam and anti-botting messaging (05:50, 33:30): no real-world trading, no macroing, "there is no double XP", "GE spammers are scammers".

---

## 7. Prioritised features and UI patterns to adopt for Aether Isles (all as original designs)

**P0: core loop and onboarding**
1. **Right-side utility column**: a round minimap plus 4 status orbs (health, focus/mana, stamina with a run toggle, special-ability charge), and a 14-tab icon dock in two rows. Build it as a responsive Roblox ScreenGui with a mobile-collapsible variant. Use original iconography and an isle-themed frame (driftwood/brass/sky-crystal, not stone).
2. **Left-click action label and context menu**: always show "Verb Target / N more options" at top-left. Long-press or right-click opens a menu of white verbs with colour-coded targets (item/NPC/object/player). Let players **remap the default left-click** per item.
3. **Skills panel with total level and a per-skill unlock guide**: a 3-column grid with level badges. Tapping a skill opens a tabbed "what unlocks at each level" list (resources / gear / areas / events), with lock reasons such as "(after Quest X)".
4. **Tutorial island with a progress bar, a bobbing objective marker and portrait dialogue**: end it with a teleport to the hub isle and an **account-mode choice** (normal / iron-style solo / hardcore one-life / group iron) plus a lock toggle.
5. **Chatbox with filter tabs and colour semantics**: system (white), drops/warnings (red), collection (purple), broadcast (green) and party (blue). Collapse repeated messages (×N) instead of spamming. Reuse the same panel for NPC dialogue with portrait, name and "continue".
6. **Combat feedback**: overhead HP bars shown only in combat, red damage and blue miss splats, poison/venom colours, and floating XP drops into a session counter.

**P1: progression depth**
7. **Quest journal** with red/yellow/green state, quest points, difficulty and length tags, and a context menu (journal / show on map / start built-in guide). Add an **optional in-game quest-helper overlay** with an objective line and path highlight, so players never need a wiki. Show a **quest-complete scroll** that lists rewards plus total points.
8. **Regional diaries**: 4 tiers per island, a tiered wearable reward per island that gains perks each tier, and a requirements checklist UI with green-met states. Pair this with a combat-task track.
9. **Goal board**: player-pinned long, medium and short goals (an item, a level, a cape, a gold amount) with auto-suggested next steps. This replaces the external "goal" advice the video gives.
10. **Collection log** with per-source counters ("433/1404"), personal-best timers, kill counts and "new log item" broadcasts.
11. **Slayer-style task system**: masters tiered by combat level, a task-complete summary (count, XP, streak, points) and rare "elite variant" spawns. Points go to a reward shop.
12. **Bank 2.0**: named tabs with a live value total, insert/swap mode, item/note withdraw, quantity presets, search, a deposit-all row and PIN. Add a cosmetic **wardrobe storage** (set-collection grid with missing pieces greyed).

**P2: economy, travel and social**
13. **Player exchange** (SkyBlock bazaar × GE): offer slots, ±5% price nudges, +1/+10/+100/+1k quantity steps, buy limits, a guide price, a **price-history graph with 30-day average** and a price-checker window. Add a membership-style token that is tradeable for in-game currency, with a conversion fee as a gold sink.
14. **Travel network**: unlockable teleport nodes (tree/ring/portal analogues, original fiction such as sky-anchors and wind-shrines), jewellery-like charged teleports, and a home-isle portal hub. The world map should show the "closest teleport" for each POI.
15. **Timed resource "runs"**: farm plots across islands with growth stages, disease risk and compost tiers, plus birdhouse-like passive traps. Show growth timers in a dashboard so the run planner is in-game.
16. **World map** with a key panel, toggleable icon categories, completion checkmarks on icons, hover tooltips, and large region labels.
17. **Server browser** with activity labels (party, boss, minigame, group-iron), player counts and favourites.
18. **Skilling minigames** with bespoke HUD bars (heat band, storm meter) that pay points into XP-boost outfits. Add a co-op wave minigame with role calls.
19. **Endgame PvM**: a wave survival boss with split timers and predicted time, a 3–5 player raid with a points overlay, a boss HP bar and a reward-chest moment.

**P3: polish and art**
20. Art bible (detailed meshes, rich visuals): use the reference for layout, density and colour only.
    - **Roads:** winding roads bordered by fences as guidance lines, with signposts at every junction.
    - **Villages:** bunting-strung alleys and gate landmarks to create leading lines; dense, readable POI clusters; a hero landmark per isle (castle, fountain plaza, observatory, wreck).
    - **Atmosphere:** distance haze, and a distinct sky and lighting tint per biome (bright blue isles, purple arcane isle, red-black volcanic depths).
    - **Lighting:** Future lighting with shadows and warm lit windows as the default, plus a performance-quality setting for low-end devices.
21. Built-in calculators and tooltips: DPS preview on the equipment-stats screen (including weapon speed), XP-to-goal, and profit/hr estimates on the recipe UI.
22. Anti-scam UX: trade-window warnings and a system notice that no double-XP events are announced by players.
23. Celebration moments: a level-up toast with fireworks, a raid-chest reveal, and house-party cosmetics and emotes for social hubs.

> **Owner direction (applied):** these notes do not recommend low-poly or flat-shaded models. Aether Isles targets detailed meshes and rich visuals. Wherever the notes mention the reference game's low-poly look, it is an observation only.

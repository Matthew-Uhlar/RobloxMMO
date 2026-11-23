-- HUD depth (docs/DEPTH-CONTRACT.md §34): action label and world context menu,
-- status orbs, chat filter tabs and the Game message router, pickup feed,
-- SkyBlock tooltip footer, hitsplats and overhead bars.
-- Part A: pure rules (shared/HudDepth.lua, Theme.lore / Theme.clickPrompt).
-- Part B: Theme.hudLayout lanes (orbs, action label, pickup feed, chat tabs) at
--   1366×768, 1366×710, 1280×650, 1024×768 touch, 844×390 and 730×303.
-- Part C: the live HUD (atlas, satchel layer, Wayfinder, combat HUD and the
--   overlay) at the same sizes: nothing overlaps, everything on screen.
-- Part D: overlay.client.lua behaviour (label, left click drives a prompt, menu,
--   examine, attack, long-press, orbs, chat router / tabs / filters, feed).
-- Part E: combat.client.lua hitsplats (pooled, styles) and overhead bars.
-- Part F: wiring (project, verify.luau, build scripts, hook points).
-- Run from the project directory: lune run verify-hud.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./tools/ui-harness")
local Data, HD = H.Data, H.HudDepth
local Vector2, Vector3, Enum = roblox.Vector2, roblox.Vector3, roblox.Enum
local T = H.loadTheme({ Color3 = roblox.Color3, Enum = Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = Vector2,
	ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint })

local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function plain(text) return (tostring(text):gsub("<[^>]+>", "")) end

------------------------------------------------------------------------------
-- Part A: pure rules
------------------------------------------------------------------------------
do
	-- OSRS level colours.
	eq(HD.levelColor(20, 20), "FFFF00", "equal level is yellow")
	eq(HD.levelColor(20, 35), "FF0000", "10+ above is red")
	eq(HD.levelColor(20, 5), "00FF00", "10+ below is green")
	ok(HD.levelColor(20, 25) ~= HD.levelColor(20, 21), "the gradient moves with the gap")
	local name, level, rest = HD.parseObject("Copperstone Ore (Lv 1) · rich seam")
	ok(name == "Copperstone Ore" and level == 1 and rest == " · rich seam", "object text parse")
	eq(HD.verbOf("Talk"), "Talk-to", "Talk becomes Talk-to")

	-- Gather prompt: verb + object + skill requirement (met / unmet colours).
	local node = { kind = "prompt", name = "Copperstone Ore", prompts = { { action = "Mine", object = "Copperstone Ore (Lv 1)", item = "Ore", enabled = true } } }
	local opts = HD.targetOptions(node, { Data = Data, levels = { Mining = 5 } }, T)
	ok(opts[1].verb == "Mine" and opts[1].target == "Copperstone Ore" and opts[1].prompt == 1, "gather default option")
	ok(opts[1].levelText == "(Mining 1)" and opts[1].levelColor == T.HudDepth.met, "met requirement in mint")
	local ids = {}
	for _, o in ipairs(opts) do table.insert(ids, o.id) end
	eq(table.concat(ids, ","), "Prompt1,Examine,Walk,Cancel", "prompt menu order")
	local main, more = HD.labelText(opts, T)
	ok(plain(main) == "Mine Copperstone Ore (Mining 1)" and plain(more) == "/ 2 more options", "label: " .. plain(main) .. " " .. plain(more))
	ok(has(main, T.HudDepth.object) and has(main, T.HudDepth.verb), "verb and object colours")
	local seam = HD.targetOptions({ kind = "prompt", prompts = { { action = "Mine", object = "Sunsteel Ore (Lv 30)", item = "SunsteelOre" } } }, { Data = Data, levels = { Mining = 12 } }, T)
	ok(seam[1].levelText == "(Mining 30)" and seam[1].levelColor == T.HudDepth.unmet, "unmet requirement in ember")
	-- Creatures: Attack (level coloured against Combat), not when owned by another player.
	local mite = { kind = "monster", name = "Cinder Mite", level = 12, monsterId = "CinderMite", attackable = true, prompts = {} }
	local m = HD.targetOptions(mite, { Data = Data, combatLevel = 12 }, T)
	ok(m[1].id == "Attack" and m[1].levelText == "(lvl 12)" and m[1].levelColor == "FFFF00", "Attack Cinder Mite (lvl 12) in yellow")
	ok(plain(HD.labelText(m, T)) == "Attack Cinder Mite (lvl 12)", "monster label")
	mite.attackable = false
	eq(HD.targetOptions(mite, { Data = Data }, T)[1].id, "Examine", "someone else's boss: no Attack")
	-- Townsfolk and players.
	local pell = HD.targetOptions({ kind = "npc", role = "Guide", name = "Pell Ashgrove", prompts = { { action = "Talk", object = "Pell Ashgrove" } } }, {}, T)
	ok(plain(HD.optionText(pell[1], T)) == "Talk-to Pell Ashgrove" and pell[1].targetColor == T.HudDepth.npc, "Talk-to Pell in townsfolk yellow")
	eq(HD.targetOptions({ kind = "player", name = "Marisol", prompts = {} }, {}, T)[1].id, "Walk", "a player's default is Walk here")
	-- Examine text from data: every creature has an authored line.
	for id in pairs(Data.Monsters) do ok(type(HD.MonsterExamine[id]) == "string", "examine line for " .. id) end
	eq(HD.examineText({ kind = "monster", monsterId = "CinderMite" }, Data), HD.MonsterExamine.CinderMite, "creature examine")
	ok(has(HD.examineText({ kind = "monster", monsterId = "Nope" }, Data), "creature"), "unknown creature fallback")
	ok(has(HD.examineText({ kind = "npc", role = "Guide" }, Data), "Pell Ashgrove, Wayfinder of the Skyway"), "townsfolk examine from Data.Townsfolk")
	ok(has(HD.examineText(node, Data), "Needs Mining 1"), "resource examine from Data.ResourceTiers")
	ok(has(HD.examineText({ kind = "player", name = "Marisol", renown = 12, title = "Islander" }, Data), "Isle Renown 12"), "player examine")

	-- Status orbs.
	local orbs = HD.orbValues({ health = 50, maxHealth = 200, prayer = 0, prayerMax = 0, speed = 225 }, T)
	eq(#orbs, 4, "four orbs")
	ok(orbs[1].id == "Health" and orbs[1].fraction == 0.25 and orbs[1].low and orbs[1].text == "50", "health orb low at 25%")
	ok(orbs[2].dim and not orbs[2].clickable and orbs[2].text == "–", "prayer orb dim before Prayer unlocks")
	ok(math.abs(orbs[3].fraction - 0.5) < 1e-9 and orbs[3].text == "225", "speed orb: 225 of 50..400")
	ok(orbs[4].mode == "mastery" and orbs[4].dim, "special orb dim without a capstone")
	local tree = Data.Mastery.Trees[1]
	local p = HD.orbValues({ health = 1, maxHealth = 1, prayer = 30, prayerMax = 60, prayerActive = true,
		mastery = { trees = { [tree.id] = { capstone = true, cooldown = 150, active = 0 } } }, masteryTrees = Data.Mastery.Trees }, T)
	ok(p[2].fraction == 0.5 and p[2].active and p[2].clickable, "prayer orb half, lit while prayers run")
	local cap = tree.NodeById[tree.capstone]
	ok(p[4].tree == tree.id and math.abs(p[4].fraction - (1 - 150 / cap.ability.cooldown)) < 1e-9 and p[4].text == "150s", "capstone recharge on the special orb")
	local dz = HD.orbValues({ dungeon = { class = "Aegis", ultimates = 2, abilityReady = 0 } }, T)
	ok(dz[4].mode == "ultimate" and dz[4].text == "×2" and dz[4].clickable, "dungeon ultimate charges")
	local plan, turningOn = HD.quickPrayerPlan("", "A,B")
	ok(#plan == 2 and turningOn, "quick-prayers on")
	plan, turningOn = HD.quickPrayerPlan("X", "A,B")
	ok(#plan == 1 and plan[1] == "X" and not turningOn, "any active prayer: switch those off")
	local keys = HD.fillKeys(0.3)
	ok(keys[1][2] == 1 and keys[#keys][2] == 0 and math.abs(keys[3][1] - 0.7) < 1e-9, "fill gradient: empty above 70%, full below")
	ok(#HD.fillKeys(0) == 2 and HD.fillKeys(1)[1][2] == 0, "fill gradient ends")

	-- Chat categories, states and visibility.
	eq(HD.chatCategory({ system = true }), "Game", "system lines are Game")
	eq(HD.chatCategory({ metadata = "IsleGame:drop" }), "Game", "router lines are Game")
	eq(HD.chatCategory({ channel = "RBXWhisper:1_2", text = "hi" }), "Private", "whispers are Private")
	eq(HD.chatCategory({ channel = "RBXGeneral", text = "hi", fromCrew = true }), "Crew", "crewmates are Crew")
	eq(HD.chatCategory({ channel = "RBXGeneral", text = "WTS Brass Sword 400" }), "Trade", "trade words are Trade")
	eq(HD.chatCategory({ channel = "RBXGeneral", text = "nice sword!" }), "Public", "everything else is Public")
	local states = HD.defaultStates()
	ok(HD.chatShows("Public", states, "All", {}), "On shows")
	ok(not HD.chatShows("Public", states, "Trade", {}), "another tab hides")
	states.Public = "Filtered"
	ok(not HD.chatShows("Public", states, "All", {}) and HD.chatShows("Public", states, "All", { friend = true }) and HD.chatShows("Public", states, "All", { crew = true }),
		"Filtered public: friends and crew only")
	states.Game = "Filtered"
	ok(HD.chatShows("Game", states, "All", { important = true }) and not HD.chatShows("Game", states, "All", {}), "Filtered game: important only")
	states.Trade = "Off"
	ok(not HD.chatShows("Trade", states, "All", { friend = true }) and HD.chatShows("Trade", states, "All", { self = true }), "Off hides all but your own echo")
	-- QC H4: whispers always pass, whatever the Private state or tab.
	states.Private = "Off"
	ok(HD.chatShows("Private", states, "All", {}) and HD.chatShows("Private", states, "Trade", {}), "whispers always pass")
	states.Private = "On"
	eq(HD.cycleState("On"), "Filtered", "cycle On")
	eq(HD.cycleState("Filtered"), "Off", "cycle Filtered")
	eq(HD.cycleState("Off"), "On", "cycle Off")
	local round = HD.decodeStates(HD.encodeStates(states))
	ok(round.Public == "Filtered" and round.Game == "Filtered" and round.Trade == "Off" and round.Crew == "On", "states round-trip")
	ok(HD.decodeStates("Public=Bogus;Nope=Off").Public == "On", "unknown states ignored")
	-- Game line kinds and colours.
	ok(HD.gameKind("Mining level 35! +8,750 coins", T) == "levelup" and select(3, HD.gameKind("Mining level 35! +8,750 coins", T)), "level-up is important")
	eq(HD.gameKind("Mined Copperstone Ore", T), "drop", "gathers are drops")
	eq(HD.gameKind("+3 Herb", T), "drop", "+N lines are drops")
	eq(HD.gameKind("You need Mining 30 first.", T), "warning", "refusals are warnings")
	eq(HD.gameKind("RARE DROP! Golem Core", T), "rare", "rare drops")
	eq(HD.gameKind("Journal opened", T), "info", "plain info")
	local segs = HD.segments("Mined Brassite ore   ·   Mining level 35! +8,750 coins")
	ok(#segs == 2 and segs[2] == "Mining level 35! +8,750 coins", "message segments")
	-- Repeat collapsing.
	local c = HD.newCollapser(0.9, 4)
	ok(#c.push("Mined Copperstone Ore", 0) == 0 and #c.push("Mined Copperstone Ore", 0.5) == 0 and #c.push("Mined Copperstone Ore", 1.2) == 0, "repeats held")
	eq(#c.due(1.5), 0, "still inside the window")
	local out = c.due(2.2)
	ok(#out == 1 and out[1].count == 3 and HD.collapsedText(out[1].text, out[1].count) == "Mined Copperstone Ore  ×3", "one ×3 line")
	c.push("A", 10)
	local flushed = c.push("B", 10.1)
	ok(#flushed == 1 and flushed[1].text == "A" and flushed[1].count == 1, "a different line flushes the held one")
	c.flush()
	for i = 0, 8 do eq(#c.push("C", 20 + i * 0.5), 0, "steady repeats held " .. i) end
	out = c.push("C", 24.5)
	ok(#out == 1 and out[1].count == 9, "a long burst is cut at the hold limit")

	-- Pickup feed.
	local d = HD.itemDeltas({ Ore = 10, Herb = 4 }, { Ore = 13, Herb = 2, Fish = 1 }, 100, 220)
	ok(#d == 3 and d[1].id == "Fish" and d[2].id == "Ore" and d[2].n == 3 and d[3].id == "coins" and d[3].n == 120, "gains only, coins last")
	eq(#HD.itemDeltas({}, { Ore = 1 }, nil, nil), 1, "no coins without both totals")
	-- QC M8: the feed reads the server's snapshot.pickups, validated and merged.
	local picks = HD.pickupEntries({ { id = "Ore", n = 2 }, { id = "Ore", n = 1.6 }, { id = "coins", n = 40 }, { id = "Nope", n = 3 }, { id = "Herb", n = -1 }, "junk" }, Data)
	ok(#picks == 2 and picks[1].id == "Ore" and picks[1].n == 3 and picks[2].id == "coins" and picks[2].n == 40, "pickups validated and merged")
	eq(#HD.pickupEntries(nil, Data), 0, "no pickups list, no feed")
	local feed = {}
	HD.feedPush(feed, "Ore", 3, 0, 3, 5)
	local e, merged = HD.feedPush(feed, "Ore", 2, 2, 3, 5)
	ok(merged and e.n == 5 and #feed == 1, "merged within the window")
	HD.feedPush(feed, "Ore", 1, 6, 3, 5)
	eq(#feed, 2, "a new line after the window")
	for i = 1, 8 do HD.feedPush(feed, "Item" .. i, 1, 7, 3, 5) end
	eq(#feed, 5, "trimmed to the line cap")
	eq(HD.feedExpire(feed, 20, 4), 5, "idle lines expire")
	local text, color = HD.feedText({ id = "Ore", n = 3 }, Data.Items.Ore, T)
	ok(text == "+3 Copperstone Ore" and color == T.rarity(Data.Items.Ore.rarity).hex, "feed line in rarity colour")
	eq(HD.feedText({ id = "coins", n = 1200 }, nil, T), "+1,200 coins", "coins line")

	-- Hitsplat styles.
	local miss = HD.splatStyle({ miss = true }, T)
	ok(miss.kind == "miss" and miss.text == "miss" and miss.fill == T.HudDepth.splatMiss, "miss splat is blue")
	local hit = HD.splatStyle({ amount = 1234 }, T)
	ok(hit.kind == "hit" and hit.text == "1,234" and hit.fill == T.HudDepth.splatHit, "damage splat")
	local crit = HD.splatStyle({ amount = 90, crit = true, tag = "weak" }, T)
	ok(crit.kind == "crit" and crit.text == "90" and crit.scale > 1 and crit.size > hit.size and crit.tag == "WEAK!", "crit splat larger, starred, WEAK! tag")
	local resist = HD.splatStyle({ amount = 70, tag = "resist" }, T)
	ok(resist.tag == "resist" and resist.fill == T.HudDepth.splatResist, "resist splat grey")
	eq(HD.splatStyle({ heal = true, amount = 20 }, T).text, "+20", "heal splat")
	-- QC L3: "miss" only for a real miss; a landed hit that did nothing is a blue 0.
	local zero = HD.splatStyle({ hurt = true, amount = 0 }, T)
	ok(zero.kind == "zero" and zero.text == "0" and zero.fill == T.HudDepth.splatMiss, "a zero hit on you is a blue 0, not miss")
	local resisted = HD.splatStyle({ amount = 0, tag = "resist" }, T)
	ok(resisted.text == "0" and resisted.fill == T.HudDepth.splatMiss and resisted.tag == "resist", "a fully resisted hit is a blue 0 with its tag")
	ok(HD.barColor(0.8) == "57D96A" and HD.barColor(0.4) == "F2C14E" and HD.barColor(0.1) == "E8413C", "overhead bar colours")
	ok(HD.splatShape("37") == "diamond" and HD.splatShape("miss") == "pill" and select(2, HD.splatShape("1,284", 21)) > select(2, HD.splatShape("miss", 13)),
		"short numbers in diamonds, long ones in pills sized to the text")

	-- SkyBlock tooltip footer in Theme.lore (every tooltip): name in rarity colour,
	-- stats, description, bold RARITY TYPE, sell price, yellow click prompt.
	local lore = T.lore(Data.Items.SunsteelSword, { Data = Data, levels = { Combat = 50 } })
	local at = {}
	for i, l in ipairs(lore) do at[l.kind or "?"] = at[l.kind or "?"] or i end
	ok(lore[1].title and lore[1].color == T.rarity(Data.Items.SunsteelSword.rarity).hex, "name in rarity colour")
	ok(at.stat and at.description and at.rarity and at.value and at.click, "every footer line present")
	ok(at.stat < at.description and at.description < at.rarity and at.rarity < at.value and at.value < at.click and at.click == #lore, "footer order")
	ok(lore[at.rarity].bold and has(lore[at.rarity].text, "<b>"), "bold rarity line")
	ok(lore[at.click].color == T.hex.prompt and T.hex.prompt == "FFFF55" and lore[at.click].text == "Click to wield!  Right-click for options.", "yellow click prompt")
	eq(T.clickPrompt(Data.Items.CookedFish, {}), "Click to eat!  Right-click for options.", "food prompt")
	eq(T.clickPrompt(Data.Items.Ore, {}), "Click to view its collection!  Right-click for options.", "material prompt")
	eq(T.clickPrompt(Data.Items.BrassPickaxe, {}), "Click to move it to your hotbar!  Right-click for options.", "tool prompt")
	eq(T.clickPrompt(Data.Items.SunsteelSword, { equipped = true }), "Click to unequip!  Right-click for options.", "equipped prompt")
	eq(T.clickPrompt(Data.Items.SunsteelSword, { click = "Click to view recipes!" }), "Click to view recipes!", "custom prompt")
	ok(T.clickPrompt(Data.Items.SunsteelSword, { click = false }) == nil, "prompt can be hidden")
	-- §33 price check: a market line between the sell price and the click prompt.
	local priced = T.lore(Data.Items.Ore, { Data = Data, price = "24h avg 5 coins" })
	local pi, vi
	for i, l in ipairs(priced) do if l.kind == "price" then pi = i elseif l.kind == "value" then vi = i end end
	ok(pi and vi and pi == vi + 1 and priced[#priced].kind == "click" and has(priced[pi].text, "24h avg 5 coins"), "market price line in the footer")
	local footerChecked = 0
	for id, def in pairs(Data.Items) do
		local l = T.lore(def, { Data = Data })
		local kinds = {}
		for _, line in ipairs(l) do kinds[line.kind or "?"] = true end
		assert(kinds.rarity and kinds.click and l[#l].kind == "click", "footer for " .. id)
		footerChecked += 1
	end
	checks += 1
	print("Part A (pure rules): " .. checks .. " checks, footer on " .. footerChecked .. " items.")
end

------------------------------------------------------------------------------
-- Part B: lanes
------------------------------------------------------------------------------
local SIZES = { { 1366, 768, false }, { 1366, 710, false }, { 1280, 650, false }, { 1024, 768, true }, { 844, 390, true }, { 730, 303, true } }
local function overlaps(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
local function onScreen(a, w, h) return a.x >= 0 and a.y >= 0 and a.x + a.w <= w + 0.5 and a.y + a.h <= h + 0.5 end
local function show(r) return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h) end
local function pairwise(items, tag)
	for i = 1, #items do
		for j = i + 1, #items do
			assert(not overlaps(items[i][2], items[j][2]), items[i][1] .. " " .. show(items[i][2]) .. " overlaps " .. items[j][1] .. " " .. show(items[j][2]) .. " at " .. tag)
			checks += 1
		end
	end
end
do
	local before = checks
	for _, case in ipairs(SIZES) do
		local w, h, touch = case[1], case[2], case[3]
		for _, satchelOpen in ipairs({ false, true }) do
			local L = T.hudLayout(w, h, { touch = touch, satchelOpen = satchelOpen })
			local tag = w .. "x" .. h .. (if touch then " touch" else "") .. (if satchelOpen then " satchel" else "")
			local o = L.orbs
			ok(o.w > 0 and o.h > 0 and o.y >= 8, "orbs lane at " .. tag)
			ok(o.size >= (if L.touch then 44 else 34), "orb size meets the floor at " .. tag)
			ok(L.lane.left >= o.x + o.w + 10, "top lane starts right of the orbs at " .. tag)
			local items = {
				{ "minimap block", L.mapBlock }, { "orbs", { x = o.x, y = o.y, w = o.w, h = o.h } }, { "sidebar", L.sidebar },
				{ "action bar", L.action }, { "hotbar", L.hotbar }, { "XP drops", L.xpDrops }, { "XP toast", L.xpToast }, { "level banner", L.levelBanner },
			}
			if L.xpDrops.w == 0 then table.remove(items, 6) end
			if L.actionLabel.w > 0 then
				table.insert(items, { "action label", L.actionLabel })
				-- Clear of the widest centred target / boss panel (420 px from y 10).
				local panel = { x = math.floor(w / 2) - 210, y = 10, w = 420, h = 62 }
				ok(not overlaps(L.actionLabel, panel), "action label clears the target panel at " .. tag)
			else
				ok(L.touch or w < 1000, "the action label is only dropped on touch or narrow layouts at " .. tag)
			end
			if L.pickupFeed.lines > 0 then
				table.insert(items, { "pickup feed", L.pickupFeed })
				ok(L.pickupFeed.y + L.pickupFeed.h <= L.band.y or L.short, "pickup feed above the hotbar band at " .. tag)
				if L.short then
					local attack = { x = w - 88, y = h - 82, w = 78, h = 78 }
					ok(not overlaps(L.pickupFeed, attack), "pickup feed clears the Attack button at " .. tag)
				end
			end
			ok(L.pickupFeed.lines >= 2, "the pickup feed shows at least two lines at " .. tag)
			if L.chatTabs.w > 0 then
				table.insert(items, { "chat tabs", L.chatTabs })
				ok(L.chatTabs.y + L.chatTabs.h <= L.chat.y, "chat tabs above the docked window at " .. tag)
			end
			if satchelOpen and not L.short then table.insert(items, { "docked satchel", L.satchel }) end
			for _, item in ipairs(items) do ok(onScreen(item[2], w, h), item[1] .. " on screen at " .. tag .. " " .. show(item[2])) end
			pairwise(items, tag)
			if not touch then
				for _, item in ipairs(items) do
					if item[1] ~= "chat tabs" then ok(not overlaps(item[2], L.chat), item[1] .. " clears the chat lane at " .. tag) end
				end
			end
		end
	end
	print("Part B (lanes): " .. (checks - before) .. " checks.")
end

------------------------------------------------------------------------------
-- Shared fixtures for the overlay
------------------------------------------------------------------------------
local function rectOf(object, size)
	local chain = {}
	local node = object
	while node and node.ClassName ~= "ScreenGui" do table.insert(chain, 1, node); node = node.Parent end
	local x, y, w, h = 0, 0, size.X, size.Y
	for _, item in ipairs(chain) do
		local s, p, a = item.Size, item.Position, item.AnchorPoint or Vector2.zero
		local cw, ch = s.X.Scale * w + s.X.Offset, s.Y.Scale * h + s.Y.Offset
		local limit = item:FindFirstChildOfClass("UISizeConstraint")
		if limit then cw, ch = math.min(cw, limit.MaxSize.X), math.min(ch, limit.MaxSize.Y) end
		x, y = x + p.X.Scale * w + p.X.Offset - a.X * cw, y + p.Y.Scale * h + p.Y.Offset - a.Y * ch
		w, h = cw, ch
	end
	return { x = x, y = y, w = w, h = h }
end
-- A world for the cursor: a gather node (prompt part), a creature, Pell.
local function world()
	local folder = H.new("Folder", { Name = "World" })
	local nodeModel = H.new("Model", { Name = "CopperVein" })
	nodeModel.Parent = folder
	local nodePart = H.new("Part", { Name = "Vein", Position = Vector3.new(30, 0, 0) })
	nodePart.Parent = nodeModel
	local held = { begin = 0, ended = 0 }
	local prompt = H.new("ProximityPrompt", { Name = "Gather", ActionText = "Mine", ObjectText = "Copperstone Ore (Lv 1)", Enabled = true, HoldDuration = 1,
		MaxActivationDistance = 10 })
	prompt:SetAttribute("IsleAction", "gather")
	prompt:SetAttribute("IsleItem", "Ore")
	prompt.InputHoldBegin = function() held.begin += 1 end
	prompt.InputHoldEnd = function() held.ended += 1 end
	prompt.Parent = nodePart
	local mite = H.new("Model", { Name = "CinderMite" })
	mite:SetAttribute("DisplayName", "Cinder Mite")
	mite:SetAttribute("Level", 12)
	mite:SetAttribute("MonsterId", "CinderMite")
	mite:SetAttribute("Health", 500)
	mite:SetAttribute("MaxHealth", 500)
	local body = H.new("Part", { Name = "Body", Position = Vector3.new(60, 0, 0), Size = Vector3.new(4, 4, 4) })
	body.Parent = mite
	mite.PrimaryPart = body
	mite.Parent = folder
	local pell = H.new("Model", { Name = "Guide" })
	pell:SetAttribute("TownsfolkRole", "Guide")
	local pellRoot = H.new("Part", { Name = "HumanoidRootPart", Position = Vector3.new(24, 0, 4) })
	pellRoot.Parent = pell
	local talk = H.new("ProximityPrompt", { Name = "TalkPrompt", ActionText = "Talk", ObjectText = "Pell Ashgrove", Enabled = true, HoldDuration = 0, MaxActivationDistance = 11 })
	talk.InputHoldBegin = function() held.talk = (held.talk or 0) + 1 end
	talk.InputHoldEnd = function() end
	talk.Parent = pellRoot
	local head = H.new("Part", { Name = "Head", Position = Vector3.new(24, 2, 4) })
	head.Parent = pell
	pell.Parent = folder
	return { folder = folder, nodePart = nodePart, prompt = prompt, mite = mite, body = body, pell = pell, head = head, held = held, talk = talk }
end
local function character(player, at)
	local char = H.new("Model", { Name = "Character" })
	local root = H.new("Part", { Name = "HumanoidRootPart", Position = at or Vector3.new(25, 0, 0), CFrame = roblox.CFrame.new(at or Vector3.new(25, 0, 0)) })
	root.Parent = char
	local humanoid = H.new("Humanoid", { Name = "Humanoid", Health = 150, MaxHealth = 200 })
	humanoid.moves = {}
	humanoid.MoveTo = function(_, position) table.insert(humanoid.moves, position) end
	humanoid.Parent = char
	player.Character = char
	return char, root, humanoid
end
local function mouse(kind, x, y)
	return { UserInputType = kind, Position = Vector3.new(x, y, 0) }
end

------------------------------------------------------------------------------
-- Part C: the live HUD at every size
------------------------------------------------------------------------------
do
	local before = checks
	for _, case in ipairs(SIZES) do
		local size = Vector2.new(case[1], case[2])
		local touch = case[3]
		local tag = size.X .. "x" .. size.Y .. (if touch then " touch" else "")
		local ui = H.runAtlas(size, { touch = touch })
		local layer = H.runHud(size, ui.player, ui.replicated, { touch = touch })
		local nav = H.runNav(size, ui.player, ui.replicated, { touch = touch })
		local combat = H.runCombat(size, ui.player, ui.replicated)
		local w = world()
		local hit = nil
		local clock = 100
		local ov = H.runOverlay(size, ui.player, ui.replicated, { touch = touch, clock = function() return clock end,
			raycast = function() return hit end, tagged = combat.tagged })
		local S, L = ov.state, T.hudLayout(size.X, size.Y, { touch = touch, satchelOpen = true })
		-- A boss of your own fills the target panel.
		table.insert(combat.tagged, combat.monster)
		combat.monster:SetAttribute("Health", 640)
		combat.monster:SetAttribute("MaxHealth", 1000)
		combat.monster:SetAttribute("Boss", true)
		combat.monster:SetAttribute("Level", 30)
		combat.monster:SetAttribute("OwnerUserId", 1)
		combat.run.RenderStepped:Fire()
		-- The docked satchel (tall screens) moves the XP lane and the feed.
		layer.state.setOpen(true)
		layer.state.placeDrops()
		-- Hover the vein: the label shows on mouse layouts.
		hit = { Instance = w.nodePart, Position = Vector3.new(30, 0, 0) }
		ov.input.InputChanged:Fire(mouse(Enum.UserInputType.MouseMovement, 400, 300))
		clock += 1
		ov.run.Heartbeat:Fire(0.1)
		ok(plain(S.labelMain.Text) == "Mine Copperstone Ore (Mining 1)", "label text at " .. tag .. ": " .. plain(S.labelMain.Text))
		eq(S.label.Visible, L.actionLabel.w > 0, "label visible where the lane is at " .. tag)
		-- A gain fills the pickup feed.
		local snap = H.snapshot()
		snap.items = table.clone(snap.items)
		snap.items.Ore += 3
		snap.coins += 120
		snap.pickups = { { id = "Ore", n = 3 }, { id = "coins", n = 120 } }
		ui.update.OnClientEvent:Fire(snap)
		ok(S.feedRows[1] and S.feedRows[1].Visible, "pickup feed row at " .. tag)
		-- A level-up banner joins the set.
		local up = H.snapshot()
		up.depth.skills = table.clone(up.depth.skills)
		up.depth.skills.Mining = table.clone(up.depth.skills.Mining)
		up.depth.skills.Mining.xp += 500
		up.depth.skills.Mining.level += 1
		ui.update.OnClientEvent:Fire(up)
		local banner = ui.gui:FindFirstChild("LevelBanner")
		local items = {
			{ "sidebar", rectOf(ui.gui:FindFirstChild("Sidebar"), size) },
			{ "minimap", rectOf(nav.gui:FindFirstChild("Minimap"), size) },
			{ "orbs", rectOf(S.orbFrame, size) },
			{ "action bar", rectOf(ui.gui:FindFirstChild("ActionBar"), size) },
			{ "hotbar gap", { x = L.hotbar.x, y = L.hotbar.y, w = L.hotbar.w, h = L.hotbar.h } },
			{ "skill toast", rectOf(layer.state.skillToast, size) },
			{ "pickup feed", rectOf(S.feedFrame, size) },
			{ "target panel", rectOf(combat.hud:FindFirstChild("Target"), size) },
		}
		if L.xpDrops.w > 0 then table.insert(items, { "XP drops", rectOf(layer.state.drops, size) }) end
		if banner and banner.Visible then table.insert(items, { "level banner", rectOf(banner, size) }) end
		if S.label.Visible then table.insert(items, { "action label", rectOf(S.label, size) }) end
		if S.tabRow.Visible then table.insert(items, { "chat tabs", rectOf(S.tabRow, size) }) end
		if layer.state.docked then table.insert(items, { "docked satchel", rectOf(layer.state.panel, size) }) end
		ok(combat.hud:FindFirstChild("Target").Visible, "target panel shows at " .. tag)
		for _, item in ipairs(items) do ok(onScreen(item[2], size.X, size.Y), item[1] .. " on screen at " .. tag .. " " .. show(item[2])) end
		pairwise(items, tag)
		eq(S.tabRow.Visible, not touch, "chat tabs on desktop only at " .. tag)
		if S.tabRow.Visible then
			for _, name in ipairs(HD.CHAT_TABS) do
				local r = rectOf(S.tabs[name], size)
				ok(r.w >= 50 and r.x + r.w <= L.chatTabs.x + L.chatTabs.w + 0.5, name .. " tab fits at " .. tag)
			end
		end
		-- Orbs: inside their lane, 44 px touch targets on touch layouts.
		for _, id in ipairs(HD.ORB_IDS) do
			local r = rectOf(S.orbs[id].button, size)
			ok(r.x >= L.orbs.x - 0.5 and r.x + r.w <= L.orbs.x + L.orbs.w + 0.5 and r.y + r.h <= L.orbs.y + L.orbs.h + 0.5, id .. " orb in its lane at " .. tag)
			if touch then ok(r.w >= 44 and r.h >= 44, id .. " orb is a 44 px target at " .. tag) end
		end
		-- The context menu stays on screen (touch rows 44 px).
		S.openMenu(S.resolve(w.nodePart, Vector3.new(30, 0, 0)), Vector2.new(size.X - 5, size.Y - 5))
		local menu = rectOf(S.menu, size)
		ok(onScreen(menu, size.X, size.Y), "world menu on screen at " .. tag .. " " .. show(menu))
		if touch then ok(S.menuButtons[1].Size.Y.Offset >= 44, "menu rows are 44 px on touch at " .. tag) end
		S.closeMenu()
	end
	print("Part C (live HUD): " .. (checks - before) .. " checks.")
end

------------------------------------------------------------------------------
-- Part D: overlay behaviour
------------------------------------------------------------------------------
do
	local before = checks
	local size = Vector2.new(1366, 768)
	local ui = H.runAtlas(size, {})
	local delays = {}
	local clock = 100
	local hit
	local w = world()
	local _, root, humanoid = character(ui.player)
	local attacked = {}
	local ov = H.runOverlay(size, ui.player, ui.replicated, { clock = function() return clock end, raycast = function() return hit end, delays = delays,
		tagged = { w.mite } })
	local S = ov.state
	ui.replicated:FindFirstChild("IsleAttackLocal").Event:Connect(function(model) if model ~= "cancel" then table.insert(attacked, model) end end)
	local function runDelays()
		local due = table.clone(delays)
		table.clear(delays)
		for _, d in ipairs(due) do d.fn(table.unpack(d.args, 1, d.args.n)) end
	end
	local function hover(part, at)
		hit = part and { Instance = part, Position = at or part.Position } or nil
		ov.input.InputChanged:Fire(mouse(Enum.UserInputType.MouseMovement, 500, 400))
		clock += 0.2
		ov.run.Heartbeat:Fire(0.2)
	end
	-- Hover: label per target kind; throttled to 10 Hz.
	hover(w.nodePart)
	ok(S.label.Visible and plain(S.labelMain.Text) == "Mine Copperstone Ore (Mining 1)" and plain(S.labelMore.Text) == "/ 2 more options", "hover label on the vein")
	hit = { Instance = w.body, Position = w.body.Position }
	ov.run.Heartbeat:Fire(0.01)
	ok(has(plain(S.labelMain.Text), "Copperstone"), "no second raycast inside 0.1 s")
	hover(w.body)
	ok(has(plain(S.labelMain.Text), "Attack Cinder Mite (lvl"), "hover label on the creature: " .. plain(S.labelMain.Text))
	hover(w.head)
	eq(plain(S.labelMain.Text), "Talk-to Pell Ashgrove", "hover label on Pell")
	hover(nil)
	ok(not S.label.Visible, "nothing under the cursor hides the label")
	-- Left click drives the prompt in reach: InputHoldBegin, released when the
	-- prompt fires (QC M5: Triggered / PromptButtonHoldEnded, not a blind timer).
	hit = { Instance = w.nodePart, Position = w.nodePart.Position }
	local cancels = 0
	ui.replicated:FindFirstChild("IsleAttackLocal").Event:Connect(function(model) if model == "cancel" then cancels += 1 end end)
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	eq(w.held.begin, 1, "left click holds the prompt")
	ok(cancels == 1, "driving a prompt clears combat's pending attack (QC M2)")
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	ok(w.held.begin == 1 and w.held.ended == 0 and S.lastDriven == nil, "QC M5: a second click while the hold runs is skipped")
	w.prompt.Triggered:Fire(ui.player)
	ok(w.held.ended == 1 and S.lastDriven == w.prompt, "released on Triggered; lastDriven set on success only")
	w.prompt.Triggered:Fire(ui.player)
	eq(w.held.ended, 1, "a finished hold ends once")
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	eq(w.held.begin, 2, "a new hold after the last ended")
	w.prompt.PromptButtonHoldEnded:Fire()
	eq(w.held.ended, 2, "an early release ends the hold too")
	runDelays()
	eq(w.held.ended, 2, "the safety delay does not end a finished hold again")
	S.lastDriven = nil
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), true)
	eq(w.held.begin, 2, "a click the GUI used does nothing")
	-- QC M1: out of reach, walk up along a computed route (ground-checked), hold on arrival.
	root.Position = Vector3.new(0, 0, 0)
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	local dest = humanoid.moves[1]
	ok(#humanoid.moves == 1 and dest and (dest - w.nodePart.Position).Magnitude <= 10 and dest.X < w.nodePart.Position.X and w.held.begin == 2,
		"out of reach: walks to a spot in reach on the player's side " .. #humanoid.moves .. " " .. tostring(dest))
	ok(#ov.routes >= 1 and S.walking ~= nil, "the walk follows a PathfindingService route")
	-- QC M2: manual movement (a movement key) cancels the walk-up.
	local token = S.walkToken
	ov.input.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.W, Position = Vector3.zero }, false)
	ok(S.walkToken == token + 1 and S.walking == nil, "a movement key cancels the walk-up")
	-- Steering by hand (MoveDirection away from the route) cancels it too.
	ok(S.steered({ MoveDirection = Vector3.new(-1, 0, 0) }, root, Vector3.new(30, 0, 0)) and not S.steered({ MoveDirection = Vector3.new(1, 0, 0) }, root, Vector3.new(30, 0, 0)),
		"MoveDirection against the route counts as steering")
	-- QC M1: more than 60 studs: "Too far", no walk.
	local toasts = {}
	ui.replicated:FindFirstChild("IsleToastLocal").Event:Connect(function(text) table.insert(toasts, text) end)
	root.Position = Vector3.new(-50, 0, 0)
	local moves = #humanoid.moves
	ok(S.drive(w.prompt) == false and #humanoid.moves == moves and has(toasts[#toasts], "Too far"), "beyond 60 studs: Too far, no walk")
	-- Unreachable (no path) aborts; a waypoint with no ground under it aborts (never off an edge).
	root.Position = Vector3.new(0, 0, 0)
	ov.setPath(function() return nil end)
	ok(S.drive(w.prompt) == false and #humanoid.moves == moves and has(toasts[#toasts], "can't reach"), "no route: aborted")
	ov.setPath(function(from, to) return { from, Vector3.new(15, -40, 0), to } end)
	local ground = ov.setGround(function(origin) return origin.Y > -20 end)
	ok(S.drive(w.prompt) == false and #humanoid.moves == moves, "a waypoint over the void: aborted")
	ov.setPath(nil)
	ov.setGround(ground)
	-- Arriving in reach mid-walk holds.
	S.walkPath(Vector3.new(26, 0, 0), function() return true end, function() w.arrived = true end)
	ok(w.arrived, "arrival runs the hold")
	root.Position = Vector3.new(25, 0, 0)
	-- QC M6: a prompt under a Model measures from its PrimaryPart; no character: not in reach.
	local crate = H.new("Model", { Name = "Crate" })
	local lid = H.new("Part", { Name = "Lid", Position = Vector3.new(26, 0, 0) })
	lid.Parent = crate
	crate.PrimaryPart = lid
	local modelPrompt = H.new("ProximityPrompt", { Name = "Open", ActionText = "Open", MaxActivationDistance = 8, Enabled = true })
	modelPrompt.Parent = crate
	ok(S.promptPoint(modelPrompt) == lid.Position, "a Model's prompt measures from its PrimaryPart")
	ok(not S.within(modelPrompt), "no ancestor BasePart (the server would refuse): not in reach")
	local char = ui.player.Character
	ui.player.Character = nil
	ok(not S.within(w.prompt), "no character: not in reach")
	ui.player.Character = char
	-- QC M4 / L6: someone else's prompt, ClickablePrompt = false; IsleDefault leads.
	local shelf = H.new("Part", { Name = "Shelf", Position = Vector3.new(27, 0, 0) })
	local theirs = H.new("ProximityPrompt", { Name = "Theirs", ActionText = "Loot", ObjectText = "Chest", Enabled = true })
	theirs:SetAttribute("OwnerUserId", 99)
	theirs.Parent = shelf
	local noclick = H.new("ProximityPrompt", { Name = "NoClick", ActionText = "Sit", ObjectText = "Bench", Enabled = true, ClickablePrompt = false })
	noclick.Parent = shelf
	local inspect = H.new("ProximityPrompt", { Name = "Inspect", ActionText = "Inspect", ObjectText = "Shelf", Enabled = true })
	inspect.Parent = shelf
	local take = H.new("ProximityPrompt", { Name = "Take", ActionText = "Take", ObjectText = "Shelf", Enabled = true })
	take:SetAttribute("IsleDefault", true)
	take.Parent = shelf
	local resolved = S.resolve(shelf, shelf.Position)
	ok(resolved and #resolved.prompts == 2 and resolved.prompts[1].instance == take and resolved.prompts[2].instance == inspect,
		"someone else's and unclickable prompts skipped; IsleDefault is the left-click default")
	local mine = H.new("ProximityPrompt", { Name = "Mine", ActionText = "Loot", ObjectText = "Chest", Enabled = true })
	mine:SetAttribute("OwnerUserId", ui.player.UserId)
	mine.Parent = shelf
	eq(#S.resolve(shelf, shelf.Position).prompts, 3, "your own owned prompt stays")
	-- Creatures keep combat's left click.
	hit = { Instance = w.body, Position = w.body.Position }
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	ok(#attacked == 0 and w.held.begin == 2, "left click on a creature is left to combat")
	-- Right click without a drag opens the menu; a drag (camera turn) does not.
	hit = { Instance = w.nodePart, Position = w.nodePart.Position }
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 540, 400), false)
	ok(not S.menu.Visible, "a right drag turns the camera, no menu")
	-- QC M3: the cursor is locked while the camera turns, so the drag is the summed Delta.
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	for _ = 1, 4 do ov.input.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(500, 400, 0), Delta = Vector3.new(2, 0, 0) }) end
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ok(not S.menu.Visible, "a locked-cursor camera turn (Delta 8 px) opens no menu")
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	clock += 0.5
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ok(not S.menu.Visible, "a press held 0.5 s opens no menu")
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 502, 401), false)
	ok(S.menu.Visible and not S.label.Visible, "right click opens the menu and hides the label")
	local texts = {}
	for _, b in ipairs(S.menuButtons) do if b.Visible then table.insert(texts, plain(b.Text)) end end
	eq(table.concat(texts, " | "), "Mine Copperstone Ore (Mining 1) | Examine Copperstone Ore | Walk here | Cancel", "menu options")
	-- Examine: the line goes to chat (Game, collapsed router).
	H.press(S.menuButtons[2])
	ok(not S.menu.Visible, "picking closes the menu")
	local last = ov.chat[#ov.chat]
	ok(last and has(last.text, "Needs Mining 1") and last.metadata == "IsleGame:examine", "examine text in chat")
	-- Walk here.
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	local moves = #humanoid.moves
	H.press(S.menuButtons[3])
	ok(#humanoid.moves == moves + 1, "Walk here moves the character")
	-- A press outside closes; inside does not.
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	local p = S.menu.Position
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, p.X.Offset + 10, p.Y.Offset + 30), true)
	ok(S.menu.Visible, "a press inside keeps the menu")
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 5, 700), false)
	ok(not S.menu.Visible, "a press outside closes it")
	eq(w.held.begin, 2, "and does not also act on the world")
	-- Creature menu: Attack fires IsleAttackLocal for combat.
	hit = { Instance = w.body, Position = w.body.Position }
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ok(has(plain(S.menuButtons[1].Text), "Attack Cinder Mite"), "creature menu starts with Attack")
	local before = S.walkToken
	H.press(S.menuButtons[1])
	ok(#attacked == 1 and attacked[1] == w.mite, "Attack asks combat through IsleAttackLocal")
	ok(S.walkToken > before, "QC M2: an attack cancels any walk-up")
	-- Townsfolk: Talk-to drives the talk prompt.
	hit = { Instance = w.head, Position = w.head.Position }
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton1, 500, 400), false)
	eq(w.held.talk, 1, "left click on Pell talks")
	-- Esc closes.
	ov.input.InputBegan:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputEnded:Fire(mouse(Enum.UserInputType.MouseButton2, 500, 400), false)
	ov.input.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape, Position = Vector3.zero }, false)
	ok(not S.menu.Visible, "Esc closes the menu")
	-- Touch long-press opens it; a touch hides the label.
	hit = { Instance = w.nodePart, Position = w.nodePart.Position }
	ov.input.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(300, 300, 0) }, true)
	ok(not S.label.Visible and not S.mouseMode, "touch input hides the label")
	ov.input.TouchLongPress:Fire({ Vector2.new(300, 300) }, Enum.UserInputState.Begin, false)
	ok(S.menu.Visible, "long-press opens the menu")
	S.closeMenu()

	-- Orbs.
	S.paintOrbs()
	ok(S.orbs.Health.value.Text == "150" and S.orbs.Health.fraction == 0.75, "health orb reads the humanoid")
	humanoid.Health = 40
	humanoid.HealthChanged:Fire(40)
	ok(S.orbs.Health.value.Text == "40" and S.orbs.Health.value.TextColor3 == roblox.Color3.fromHex(T.HudDepth.orbLow), "health orb low colour")
	ok(not S.orbs.Prayer.button.Active, "prayer orb inert before Prayer")
	ui.player:SetAttribute("PrayerMax", 60)
	ui.player:SetAttribute("PrayerPoints", 30)
	ui.player:SetAttribute("PrayerQuick", "Steadfast,Keen")
	ui.player:SetAttribute("PrayerActive", "")
	ok(S.orbs.Prayer.value.Text == "30" and S.orbs.Prayer.fraction == 0.5 and S.orbs.Prayer.button.Active, "prayer orb reads the attributes")
	local fill = S.orbs.Prayer.fill.Transparency.Keypoints
	ok(fill[1].Value == 1 and fill[#fill].Value == 0, "liquid gradient: empty top, full bottom")
	-- QC H3: the whole quick-prayer plan is one atomic server verb, relayed through
	-- the atlas' queue (never dropped behind a request in flight).
	local sentBefore, serverBefore = #S.sent, #ui.sent
	H.press(S.orbs.Prayer.button)
	ok(#S.sent == sentBefore + 1 and S.sent[#S.sent][1] == "prayerQuickToggle" and S.sent[#S.sent][2] == nil, "quick-prayer orb sends one prayerQuickToggle")
	runDelays()
	eq(#S.sent, sentBefore + 1, "no per-prayer toggles follow")
	ok(#ui.sent == serverBefore + 1 and ui.sent[#ui.sent][1] == "prayerQuickToggle", "the atlas relays it to the server")
	ui.player:SetAttribute("PrayerActive", "Keen")
	ok(S.orbs.Prayer.halo.Visible, "lit while prayers run")
	H.press(S.orbs.Prayer.button)
	ok(S.sent[#S.sent][1] == "prayerQuickToggle" and #S.sent == sentBefore + 2, "clicking again sends the same verb (the server switches them off)")
	-- QC L8: orb numbers at least 11 px.
	for _, id in ipairs(HD.ORB_IDS) do ok(S.orbs[id].value.TextSize >= 11, id .. " orb value is at least 11 px") end
	ok(S.tabs.Public:FindFirstChild("State").TextSize >= 11, "tab state caption is at least 11 px")
	local opened
	ui.replicated:FindFirstChild("IsleHudLocal").Event:Connect(function(kind, tab, section) opened = { kind, tab, section } end)
	H.press(S.orbs.Speed.button)
	ok(opened and opened[2] == "Journal" and opened[3] == "Agility", "speed orb opens Journal › Agility")
	H.press(S.orbs.Special.button)
	ok(opened[2] == "Hero" and opened[3] == "Mastery", "special orb opens Hero › Mastery")
	ui.player:SetAttribute("DungeonClass", "Aegis")
	ui.player:SetAttribute("DungeonUltimates", 2)
	eq(S.orbs.Special.value.Text, "×2", "special orb shows ultimate charges in a run")
	S.orbs.Special.button.MouseEnter:Fire()
	ok(has(plain(S.labelMain.Text), "Ultimate ×2"), "hovering an orb captions it in the action label")
	S.orbs.Special.button.MouseLeave:Fire()

	-- Chat router: snapshot messages become Game lines, repeats collapse.
	local base = #ov.chat
	for i = 1, 3 do
		local snap = H.snapshot({ message = "Mined Copperstone Ore" })
		clock += 0.3
		ui.update.OnClientEvent:Fire(snap)
	end
	eq(#ov.chat, base, "held while the burst runs")
	clock += 2
	runDelays()
	last = ov.chat[#ov.chat]
	ok(#ov.chat == base + 1 and has(last.text, "Mined Copperstone Ore  ×3") and has(last.text, T.HudDepth.chatDrop) and last.metadata == "IsleGame:drop",
		"one collapsed, colour-coded line: " .. tostring(last and last.text))
	-- The same snapshot table re-fired (late scripts asking for it) is not repeated.
	local again = H.snapshot({ message = "Journal opened" })
	ui.update.OnClientEvent:Fire(again)
	ui.replicated:FindFirstChild("IsleSnapshotLocal"):Fire(again)
	clock += 2
	runDelays()
	eq(#ov.chat, base + 2, "a snapshot is routed once")
	-- QC H1: the server's seq dedupes copies (the atlas replays clones), and a
	-- replay to a late-starting script prints nothing.
	local stamped = H.snapshot({ message = "Brassite mined" })
	stamped.seq = 4001
	ui.update.OnClientEvent:Fire(stamped)
	local copy = table.clone(stamped)
	ui.replicated:FindFirstChild("IsleSnapshotLocal"):Fire(copy)
	ui.replicated:FindFirstChild("IsleActionLocal"):Fire("snapshot")
	clock += 2
	runDelays()
	eq(#ov.chat, base + 3, "one line per seq: copies and atlas replays are not reprinted")
	local replay = H.snapshot({ message = "An old notice" })
	replay.seq, replay.replay = 3990, true
	ui.replicated:FindFirstChild("IsleSnapshotLocal"):Fire(replay)
	clock += 2
	runDelays()
	ok(#ov.chat == base + 3 and S.snap == replay, "a replay of an unseen seq sets state but prints nothing")
	base += 1
	-- Tabs and states: Game Filtered keeps important lines; Off drops them all.
	S.cycleTab("Game")
	eq(S.chatStates.Game, "Filtered", "right click cycles Game to Filtered")
	ok(has(ui.player:GetAttribute("IsleChatFilters"), "Game=Filtered"), "filters published as a local attribute")
	S.gameLine("info", "Mined Copperstone Ore")
	S.gameLine("info", "Mining level 36! +9,100 coins")
	clock += 2
	runDelays()
	last = ov.chat[#ov.chat]
	ok(#ov.chat == base + 3 and has(last.text, "Mining level 36!") and has(last.text, "<b>"), "Filtered Game: only the level-up, in bold gold")
	ui.replicated:FindFirstChild("IsleChatLocal"):Fire("announce", "COLLECTION UNLOCKED  Brassite", "F7C548", true)
	clock += 2
	runDelays()
	ok(has(ov.chat[#ov.chat].text, "COLLECTION UNLOCKED"), "announcements are important")
	S.cycleTab("Game")
	S.gameLine("info", "Mining level 37! +9,400 coins")
	clock += 2
	runDelays()
	eq(#ov.chat, base + 4, "Game Off prints nothing")
	-- QC L1: an Examine the player asked for always echoes.
	S.run({ ["local"] = "examine" }, S.resolve(w.nodePart, w.nodePart.Position))
	ok(#ov.chat == base + 5 and has(ov.chat[#ov.chat].text, "Needs Mining 1"), "examine echoes even with Game Off")
	base += 1
	S.cycleTab("Game")
	eq(S.chatStates.Game, "On", "and back to On")
	-- Tab buttons: click selects, right click cycles.
	H.press(S.tabs.Trade)
	ok(S.chatTab == "Trade" and ui.player:GetAttribute("IsleChatTab") == "Trade", "Trade tab selected")
	S.tabs.Public.MouseButton2Click:Fire()
	eq(S.chatStates.Public, "Filtered", "right click on a tab cycles its state")
	eq(S.tabs.Public:FindFirstChild("State").Text, "Filtered", "tab shows its state")
	H.press(S.tabs.All)
	-- Incoming player messages (TextChatService.OnIncomingMessage).
	local incoming = ov.textChat.OnIncomingMessage
	ok(type(incoming) == "function", "OnIncomingMessage installed")
	local function message(userId, text, channelName)
		return { TextSource = if userId then { UserId = userId } else nil, TextChannel = { Name = channelName or "RBXGeneral" }, Text = text, Metadata = "" }
	end
	local hidden = incoming(message(7, "anyone seen the golem?"))
	ok(hidden and hidden.Text == "" and hidden.PrefixText == "", "Filtered public hides strangers")
	S.friends[8] = true
	eq(incoming(message(8, "hi!")), nil, "friends pass Filtered public")
	eq(incoming(message(1, "my own line")), nil, "your own lines always show")
	S.chatStates.Trade = "Off"
	S.chatStates.Public = "On"
	ok(incoming(message(9, "WTS brass sword")).Text == "", "Trade Off hides trade lines")
	eq(incoming(message(9, "nice sword")), nil, "Public On shows the rest")
	-- QC H4: tabs never delete lines (the chat window has no per-tab view).
	S.selectTab("Trade")
	eq(incoming(message(9, "nice sword")), nil, "selecting another tab never blanks a line")
	S.selectTab("All")
	-- Whispers always pass (even Private Off) and badge the Private tab.
	S.chatStates.Private = "Off"
	eq(incoming(message(9, "psst", "RBXWhisper:1_9")), nil, "whispers always show")
	incoming(message(9, "psst again", "RBXWhisper:1_9"))
	local badge = S.tabs.Private:FindFirstChild("Unread")
	ok(S.unread.Private == 2 and badge.Visible and badge.Text == "2", "unread whispers badge the Private tab")
	incoming(message(1, "reply", "RBXWhisper:1_9"))
	eq(S.unread.Private, 2, "your own whisper is not unread")
	S.selectTab("Private")
	ok(S.unread.Private == nil and not badge.Visible, "selecting Private clears the badge")
	incoming(message(9, "more", "RBXWhisper:1_9"))
	eq(S.unread.Private, nil, "whispers on the Private tab are read")
	S.selectTab("All")
	S.chatStates.Private = "On"
	-- Bubble chat: lines a state hides get invisible bubbles.
	local bubble = ov.textChat.OnBubbleAdded
	ok(type(bubble) == "function", "OnBubbleAdded installed")
	local b = bubble(message(9, "WTS brass sword"))
	ok(b and b.BackgroundTransparency == 1 and b.TailVisible == false, "Trade Off: the bubble is hidden")
	eq(bubble(message(9, "nice sword")), nil, "Public On: bubbles untouched")
	eq(incoming({ TextSource = nil, TextChannel = { Name = "RBXSystem" }, Text = "x", Metadata = "IsleGame:info" }), nil, "router lines are never filtered twice")
	-- QC L9: the tab row hides while the chat window is closed and follows its left edge.
	local config = H.new("ChatWindowConfiguration", { Name = "ChatWindowConfiguration", Enabled = false })
	config.Parent = ov.textChat
	S.relayout()
	ok(not S.tabRow.Visible, "chat window closed: no tabs")
	config.Enabled = true
	config.AbsolutePosition, config.AbsoluteSize = Vector2.new(24, 40), Vector2.new(420, 260)
	S.relayout()
	ok(S.tabRow.Visible and S.tabRow.Position.X.Offset == 24, "tabs follow the real chat window's left edge")
	config.Parent = nil
	S.relayout()

	-- Pickup feed: merged per item inside the window, rarity colour, coins.
	table.clear(S.feed)
	local s1 = H.snapshot()
	ui.update.OnClientEvent:Fire(s1)
	-- QC M8: items that rise without a server pickups entry (a bank withdrawal,
	-- a trade, a market collect, crafting, a shop buy) never reach the feed.
	local withdraw = H.snapshot()
	withdraw.items = table.clone(withdraw.items)
	withdraw.items.Brassite += 40
	withdraw.coins += 5000
	ui.update.OnClientEvent:Fire(withdraw)
	eq(#S.feed, 0, "a withdrawal is not a pickup")
	local s2 = H.snapshot()
	s2.items = table.clone(s2.items)
	s2.items.Ore += 3
	s2.pickups = { { id = "Ore", n = 3 } }
	clock += 0.5
	ui.update.OnClientEvent:Fire(s2)
	local row = S.feedRows[#S.feed]
	ok(#S.feed == 1 and row.Visible and row:FindFirstChild("Text").Text == "+3 Copperstone Ore", "a pickup line")
	eq(row:FindFirstChild("Text").TextColor3, roblox.Color3.fromHex(T.rarity(Data.Items.Ore.rarity).hex), "in the rarity colour")
	ok(row:FindFirstChild("Icon"):GetAttribute("ItemId") == "Ore", "with its pictogram")
	local s3 = H.snapshot()
	s3.items = table.clone(s2.items)
	s3.items.Ore += 2
	s3.coins = s2.coins + 75
	s3.pickups = { { id = "Ore", n = 2 }, { id = "coins", n = 75 } }
	s3.seq = 4100
	clock += 1
	ui.update.OnClientEvent:Fire(s3)
	ok(#S.feed == 2 and S.feed[1].n == 5, "merged into +5 within the window")
	ok(S.feedRows[1]:FindFirstChild("Text").Text == "+5 Copperstone Ore" and S.feedRows[2]:FindFirstChild("Text").Text == "+75 coins", "coins line under it")
	ui.replicated:FindFirstChild("IsleSnapshotLocal"):Fire(s3)
	ui.replicated:FindFirstChild("IsleSnapshotLocal"):Fire(table.clone(s3))
	eq(S.feed[1].n, 5, "a re-fired snapshot (or a copy with its seq) is not counted twice")
	clock += 10
	runDelays()
	ok(#S.feed == 0 and not S.feedRows[1].Visible, "lines expire")

	-- QC L4: no hover over an Active GUI object, nor while a gamepad drives.
	local playerGui = ui.player:FindFirstChild("PlayerGui")
	local panel = H.new("TextButton", { Name = "Panel", Active = true, Visible = true })
	playerGui.GetGuiObjectsAtPosition = function() return { panel } end
	hover(w.nodePart)
	ok(not S.label.Visible and S.hover == nil, "no world hover over a GUI button")
	playerGui.GetGuiObjectsAtPosition = function() return {} end
	hover(w.nodePart)
	ok(S.label.Visible, "hover returns off the GUI")
	ov.input.InputChanged:Fire({ UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.Thumbstick2, Position = Vector3.new(0.8, 0, 0) })
	ok(not S.mouseMode and not S.label.Visible, "gamepad input hides the label")
	clock += 0.2
	ov.run.Heartbeat:Fire(0.2)
	ok(not S.label.Visible, "and no hover while the gamepad drives")
	-- QC L10 (touch laptops): the next mouse movement brings the label back.
	hover(w.nodePart)
	ok(S.mouseMode and S.label.Visible, "mouse movement re-enables the label")
	-- QC L5: the hover resolve is cached per part.
	local first = S.hover
	hover(w.nodePart)
	ok(S.hover == first, "same part: the cached target is reused")
	hover(w.body)
	ok(S.hover ~= first and S.hover.kind == "monster", "a different part resolves afresh")
	print("Part D (overlay): " .. (checks - before) .. " checks.")
end

------------------------------------------------------------------------------
-- Part E: hitsplats and overhead bars
------------------------------------------------------------------------------
do
	local before = checks
	local size = Vector2.new(1366, 768)
	local ui = H.runAtlas(size, {})
	local combat = H.runCombat(size, ui.player, ui.replicated)
	local monster = combat.monster
	monster:SetAttribute("Health", 800)
	monster:SetAttribute("MaxHealth", 1000)
	monster:SetAttribute("Level", 12)
	local body = H.new("Part", { Name = "Body", Position = Vector3.new(0, 4, 0), Size = Vector3.new(4, 6, 4) })
	body.Parent = monster
	monster.PrimaryPart = body
	table.insert(combat.tagged, monster)
	local function splats()
		local out = {}
		for _, a in ipairs(combat.workspace:FindFirstChild("Terrain"):GetChildren()) do
			if a.Name == "Hitsplat" then table.insert(out, a:FindFirstChild("Splat")) end
		end
		return out
	end
	combat.fx.OnClientEvent:Fire("hit", { model = monster, position = Vector3.new(0, 5, 0), amount = 1234, attacker = 1 })
	combat.fx.OnClientEvent:Fire("hit", { model = monster, position = Vector3.new(0, 5, 0), amount = 90, crit = true, tag = "weak", attacker = 1 })
	combat.fx.OnClientEvent:Fire("hit", { model = monster, position = Vector3.new(0, 5, 0), amount = 0, miss = true, attacker = 1 })
	local list = splats()
	eq(#list, 3, "three pooled splats")
	ok(list[1]:FindFirstChild("Value").Text == "1,234" and list[1]:FindFirstChild("Badge").BackgroundColor3 == roblox.Color3.fromHex(T.HudDepth.splatHit), "damage splat")
	ok(list[2]:FindFirstChild("Value").Text == "90" and list[2]:FindFirstChild("Burst").Visible and list[2]:FindFirstChild("Tag").Text == "WEAK!", "crit splat with burst and tag")
	ok(list[2]:FindFirstChild("Badge").Size.X.Offset > 32 and list[2]:FindFirstChild("Badge").Rotation == 45, "crit badge is a larger diamond")
	ok(list[1]:FindFirstChild("Badge").Rotation == 0 and list[1]:FindFirstChild("Badge").Size.X.Offset >= 60, "a long number gets a pill")
	ok(list[3]:FindFirstChild("Value").Text == "miss" and list[3]:FindFirstChild("Badge").BackgroundColor3 == roblox.Color3.fromHex(T.HudDepth.splatMiss), "miss splat")
	-- Fanned out: three hits on one model never share a spot.
	local a1, a2, a3 = list[1].Parent.WorldPosition, list[2].Parent.WorldPosition, list[3].Parent.WorldPosition
	ok(a1 ~= a2 and a2 ~= a3 and a1 ~= a3, "hits fan out")
	for _ = 1, 80 do combat.fx.OnClientEvent:Fire("hit", { model = monster, position = Vector3.new(0, 5, 0), amount = 5 }) end
	ok(#splats() <= 24, "the splat pool is capped (" .. #splats() .. ")")
	-- Overhead bar over the struck creature.
	local gui = ui.player:FindFirstChild("PlayerGui")
	local bar
	for _, child in ipairs(gui:GetChildren()) do if child.Name == "OverheadBar" and child.Enabled then bar = child end end
	ok(bar and bar.Adornee == body and bar.StudsOffsetWorldSpace.Y > 3, "overhead bar over the creature")
	local fill = H.find(bar, "Fill")
	ok(math.abs(fill.Size.X.Scale - 0.8) < 1e-5 and fill.BackgroundColor3 == roblox.Color3.fromHex(HD.barColor(0.8)), "bar at 80% in green " .. tostring(fill.Size) .. " " .. tostring(fill.BackgroundColor3))
	ok(H.find(bar, "Level").Text == "Lv 12", "bar carries the level")
	ok(H.find(bar, "Level").TextSize >= 11, "QC L8: bar level text is at least 11 px")
	monster:SetAttribute("Health", 200)
	ok(math.abs(fill.Size.X.Scale - 0.2) < 1e-5 and fill.BackgroundColor3 == roblox.Color3.fromHex(HD.barColor(0.2)), "bar follows Health (red at 20%)")
	ok(H.find(bar, "Trail").Size.X.Scale <= 0.2 + 1e-5, "the damage trail drains to it")
	local count = 0
	for _, child in ipairs(gui:GetChildren()) do if child.Name == "OverheadBar" then count += 1 end end
	eq(count, 1, "one pooled bar per creature")
	monster:SetAttribute("Health", 0)
	ok(not bar.Enabled and bar.Adornee == nil, "a dead creature releases its bar")
	-- QC L2: a released bar's running tweens are cancelled (a reused bar never
	-- keeps fading from its previous life); a restyled splat drops its old fades.
	local OB, SP = combat.state.overhead, combat.state.splats
	local function creature(name, x)
		local m = H.new("Model", { Name = name })
		m:SetAttribute("Health", 100)
		m:SetAttribute("MaxHealth", 100)
		local part = H.new("Part", { Name = "Body", Position = Vector3.new(x, 4, 0), Size = Vector3.new(4, 6, 4) })
		part.Parent = m
		m.PrimaryPart = part
		m.Parent = combat.workspace
		return m
	end
	local m1 = creature("Boar", 10)
	combat.fx.OnClientEvent:Fire("hit", { model = m1, position = Vector3.new(10, 5, 0), amount = 5, attacker = 1 })
	m1:SetAttribute("Health", 60)
	local b1 = OB.byModel[m1]
	local running = table.clone(b1.tweens)
	ok(#running > 0 and running[1].playing, "the trail drain tween runs")
	OB.release(m1)
	ok(not running[1].playing and #b1.tweens == 0, "release cancels the bar's tweens")
	local oldest = SP.live[1]
	local fades = table.clone(oldest.tweens)
	ok(#fades > 0 and fades[1].playing, "a live splat is fading")
	ok(SP.show(Vector3.new(0, 5, 0), HD.splatStyle({ amount = 3 }, T)) == oldest and not fades[1].playing, "restyling the oldest splat cancels its old fade")
	-- QC M7: other players' hits never claim a bar; a full pool evicts the oldest
	-- bar that is not over your target.
	local theirs = creature("Theirs", 20)
	combat.fx.OnClientEvent:Fire("hit", { model = theirs, position = Vector3.new(20, 5, 0), amount = 5, attacker = 2 })
	eq(OB.byModel[theirs], nil, "another player's hit: no bar")
	local herd = {}
	for i = 1, OB.POOL + 1 do
		herd[i] = creature("Herd" .. i, 30 + i)
		combat.fx.OnClientEvent:Fire("hit", { model = herd[i], position = Vector3.new(30 + i, 5, 0), amount = 1, attacker = 1 })
	end
	ok(OB.byModel[herd[OB.POOL + 1]] ~= nil and OB.byModel[herd[1]] == nil and OB.byModel[herd[2]] ~= nil, "a full pool evicts the oldest bar for your new hit")
	-- Hurt splats on you; heal text through the same pool.
	combat.fx.OnClientEvent:Fire("hurt", { amount = 0 })
	ok(true, "hurt splat without a character is safe")
	-- No per-frame allocation in the splat path: no RenderStepped in the pools.
	local src = fs.readFile("combat.client.lua")
	local spBlock = src:match("local SP = .-S%.overhead = OB")
	ok(spBlock and not spBlock:find("RenderStepped", 1, true) and not spBlock:find("Heartbeat", 1, true), "splats and bars are event-driven")
	ok(not src:find("anchor:Destroy()", 1, true), "splats are pooled, never destroyed per hit")
	print("Part E (hitsplats): " .. (checks - before) .. " checks.")
end

-- The satchel tooltip asks the atlas' price check (§33) for its footer line.
do
	local size = Vector2.new(1366, 768)
	local ui = H.runAtlas(size, {})
	local layer = H.runHud(size, ui.player, ui.replicated, {})
	local fn = ui.replicated:FindFirstChild("IslePriceCheckLocal")
	ok(fn ~= nil, "the atlas publishes IslePriceCheckLocal")
	local calls = {}
	-- (The mock BindableFunction's :Invoke is a property stand-in for OnInvoke.)
	fn.Invoke = function(_, item, refresh) table.insert(calls, { item, refresh }); return { text = "24h avg 5 coins" } end
	eq(layer.state.priceText("Ore"), "24h avg 5 coins", "tooltip price text")
	layer.state.priceText("Ore")
	local refreshes = 0
	for _, c in ipairs(calls) do if c[2] == true then refreshes += 1 end end
	eq(refreshes, 0, "QC H2: hovering never asks the server to refresh a price")
	-- QC H2: a price-check reply is silent: the chat router prints nothing of it.
	local ov = H.runOverlay(size, ui.player, ui.replicated, {})
	local quiet = H.snapshot({ message = "" })
	quiet.seq, quiet.silent, quiet.reply = 7001, true, "Copperstone Ore price check: 24h avg 5 coins."
	ui.update.OnClientEvent:Fire(quiet)
	ov.state.gameLine("info", "flush")
	eq(#ov.chat, 0, "a silent price-check snapshot prints nothing")
	local server = fs.readFile("server.server.lua")
	ok(has(server, 'if verb=="priceCheck" then') and has(server, "snap.silent,snap.reply=true,message"), "the server flags price-check replies silent")
	-- QC H1 / M8 / H3: the server stamps seq and pickups, and owns the quick-prayer verb.
	ok(has(server, "seq=HudFeed.stamp(player),pickups=HudFeed.take(p)"), "snapshots carry seq and pickups")
	ok(has(server, 'elseif verb=="prayerQuickToggle" then return Prayer.quickToggle(player,p)') and has(server, "prayerQuickToggle=true"), "prayerQuickToggle is a server verb")
	ok(has(server, "pickup(p,item,result.amount)") and has(server, "for item,n in pairs(drops) do pickup(p,item,n) end"), "gathering and kill drops feed pickups")
	ok(has(server, 'collect(p,recipe.output,recipe.amount)'), "crafting stays a plain collect (no pickup)")
end

------------------------------------------------------------------------------
-- Part F: wiring
------------------------------------------------------------------------------
do
	local project = fs.readFile("default.project.json")
	ok(has(project, '"IsleOverlay": { "$path": "overlay.client.lua" }') and has(project, '"AetherHudDepth": { "$path": "shared/HudDepth.lua" }'), "project registers the overlay and HudDepth")
	local verify = fs.readFile("verify.luau")
	ok(has(verify, 'IsleOverlay = "overlay.client.lua"') and has(verify, 'AetherHudDepth = "shared/HudDepth.lua"'), "verify.luau binds both")
	ok(has(fs.readFile("scripts/build.sh"), "verify-hud.luau") and has(fs.readFile("build.ps1"), "verify-hud.luau"), "both build scripts run this suite")
	local overlay = fs.readFile("overlay.client.lua")
	ok(not overlay:find("RenderStepped", 1, true) and has(overlay, "now - S.hoverAt < 0.1"), "hover raycast at ≤ 10 Hz, no RenderStepped")
	ok(has(overlay, "InputHoldBegin") and has(overlay, "InputHoldEnd") and not overlay:find('Instance.new("ProximityPrompt")', 1, true), "prompts are driven, never duplicated")
	local features = fs.readFile("features.client.lua")
	ok(has(features, 'channel("IsleChatLocal")') and not features:find("DisplaySystemMessage", 1, true), "announcements route through the chat router")
	ok(has(fs.readFile("nav.client.lua"), "L.lane.left, 8"), "the Navigate list opens right of the orbs")
	ok(has(fs.readFile("combat.client.lua"), '"IsleAttackLocal"'), "combat listens for menu attacks")
	ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "\n## 34. HUD depth"), "the contract carries its §34 section")
	ok(not fs.readFile("hud.client.lua"):find("Invoke(id, true)", 1, true), "tooltips never ask for a price refresh")
	local hd = fs.readFile("shared/HudDepth.lua")
	ok(not hd:find("Instance.new", 1, true) and not hd:find("require(", 1, true), "HudDepth is pure")
end

print("HUD depth (§34) passed " .. checks .. " checks.")
-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-hud.luau")

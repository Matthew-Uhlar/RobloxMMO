--!nocheck
-- Aether Isles HUD depth (§34): pure rules for the OSRS-style action label and
-- world context menu, the status orbs, chat filter tabs and repeat collapsing,
-- the item pickup feed and hitsplat styles. ReplicatedStorage.AetherHudDepth.
-- No requires and no instances: callers pass Theme (shared/UiTheme.lua) and Data
-- (shared/GameData.lua), so everything here is tested headless in verify-hud.luau.
-- Used by overlay.client.lua (label, menu, orbs, chat, feed) and
-- combat.client.lua (hitsplats, overhead bars).
local HD = {}
HD.VERSION = 1

local function tbl(v) return if type(v) == "table" then v else {} end
local function num(v, d) v = tonumber(v); return if v and v == v then v else (d or 0) end
local function escape(text) return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local function paint(text, hex) return "<font color=\"#" .. hex .. "\">" .. text .. "</font>" end
HD.escape, HD.paint = escape, paint

------------------------------------------------------------------------------
-- Action label and world context menu
------------------------------------------------------------------------------
-- OSRS level colours: a target far below you is green, equal is yellow, far
-- above is red (10 levels either way saturate).
function HD.levelColor(mine, theirs)
	local diff = math.clamp(num(theirs) - num(mine, 1), -10, 10)
	local r, g
	if diff >= 0 then r, g = 255, math.floor(255 * (1 - diff / 10) + 0.5)
	else r, g = math.floor(255 * (1 + diff / 10) + 0.5), 255 end
	return string.format("%02X%02X%02X", r, g, 0)
end
-- "Copperstone Ore (Lv 1) · rich seam" -> "Copperstone Ore", 1, " · rich seam".
function HD.parseObject(text)
	text = tostring(text or "")
	local name, level, rest = text:match("^(.-)%s*%(Lv (%d+)%)(.*)$")
	if name then return name, tonumber(level), rest end
	return text, nil, ""
end
-- Resource tier definition and its skill for a gather prompt's IsleItem.
function HD.resourceDef(Data, id)
	if type(id) ~= "string" or type(Data) ~= "table" then return nil end
	for skill, tiers in pairs(tbl(Data.ResourceTiers)) do
		for _, def in ipairs(tbl(tiers)) do if def.id == id then return def, skill end end
	end
	return nil
end
-- Prompt verbs in OSRS form ("Talk" -> "Talk-to").
HD.VERBS = {Talk = "Talk-to", Trade = "Trade", Use = "Use"}
function HD.verbOf(action)
	action = tostring(action or "")
	return HD.VERBS[action] or action
end

-- Original examine lines for the isles' creatures (OSRS "Examine" text);
-- anything missing falls back to a line built from Data.Monsters.
HD.MonsterExamine = {
	BramblebackBoar = "Bristles like a hedge, temper like a kettle.",
	Thornling = "A sapling that learned to bite.",
	ShaleCrawler = "It tastes the quarry walls. They taste of copper.",
	CinderMite = "Small, hot and very sure of itself.",
	BarkStalker = "The bark on its back still has birds' nests in it.",
	GaleSprite = "A gust that decided to keep its shape.",
	BrassGolem = "Somebody forged it to guard something. It forgot what.",
	StormHarrier = "It rides the crosswinds and hunts anything that falls.",
	GloomfangSpider = "Eight eyes, all of them on you.",
	VoidWisp = "A flicker of the dark between the isles.",
	ReefLurker = "The reef moved. That was the reef lurker.",
	TempestWraith = "What is left of a sailor the storm never let go.",
	StarbornSentinel = "Fell from the sky and stood up angry.",
	HollowcapShrieker = "A mushroom with opinions, all of them loud.",
	MirrorscaleBasilisk = "Don't stare. It is already staring back.",
	ThundercragGargant = "A storm cloud that grew a spine of rock.",
	RiftmawStalker = "It slips through the cracks in the Crown. Literally.",
	ShardglassSeer = "It sees every way this fight could go. You lose in most.",
	UmbralDreadmaw = "All jaw, no daylight.",
	CrownforgedColossus = "The Crown's old smiths built it to last. It has.",
	VoidcrownDrake = "The last thing many voyagers saw was its shadow.",
}

-- Options for a hovered target. target = {
--   kind = "prompt" | "npc" | "monster" | "player",
--   name, level (monster / player), monsterId, role (npc), userId,
--   attackable (monster you may fight), prompts = {{action, object, item, enabled, key}}
-- }; ctx = {Data, levels = {Skill = level}, combatLevel}.
-- Each option: {id, verb, target, targetColor, levelText, levelColor, kind,
--   prompt (index into target.prompts), local ("attack" | "examine" | "walk" | "cancel")}.
-- The default (left-click) option is first; Cancel is last and never counted.
function HD.targetOptions(target, ctx, Theme)
	target, ctx = tbl(target), tbl(ctx)
	local tok = tbl(Theme and Theme.HudDepth)
	local out = {}
	local kind = target.kind
	local levels = tbl(ctx.levels)
	local function colorFor()
		if kind == "npc" then return tok.npc or "F7E26B" end
		if kind == "monster" then return tok.monster or "FFE14D" end
		if kind == "player" then return tok.player or "FFFFFF" end
		return tok.object or "5FE0E8"
	end
	if kind == "monster" and target.attackable ~= false then
		local lvl = num(target.level, 0)
		table.insert(out, {id = "Attack", verb = "Attack", target = tostring(target.name or "Creature"), targetColor = colorFor(), kind = kind,
			levelText = if lvl > 0 then "(lvl " .. lvl .. ")" else nil, levelColor = HD.levelColor(num(ctx.combatLevel, 1), lvl), ["local"] = "attack"})
	end
	for i, p in ipairs(tbl(target.prompts)) do
		if type(p) == "table" and p.enabled ~= false and tostring(p.action or "") ~= "" then
			local name, level, rest = HD.parseObject(p.object or target.name)
			local levelText, levelColor = nil, nil
			local def, skill = HD.resourceDef(ctx.Data, p.item)
			if def then
				level = level or num(def.level, 1)
				local have = num(levels[skill], 1)
				levelText = "(" .. skill .. " " .. level .. ")"
				levelColor = if have >= level then (tok.met or "6FE3C8") else (tok.unmet or "FF6B5A")
			elseif level then
				levelText, levelColor = "(lvl " .. level .. ")", tok.more or "A9B4C0"
			end
			if rest and rest ~= "" then name = name .. rest end
			table.insert(out, {id = "Prompt" .. i, verb = HD.verbOf(p.action), target = if name ~= "" then name else tostring(target.name or ""),
				targetColor = colorFor(), kind = kind, levelText = levelText, levelColor = levelColor, prompt = i})
		end
	end
	if kind ~= nil then
		table.insert(out, {id = "Examine", verb = "Examine", target = tostring(target.name or ""), targetColor = colorFor(), kind = kind, ["local"] = "examine"})
		table.insert(out, {id = "Walk", verb = "Walk here", target = "", targetColor = colorFor(), kind = kind, ["local"] = "walk"})
		table.insert(out, {id = "Cancel", verb = "Cancel", target = "", targetColor = colorFor(), kind = kind, ["local"] = "cancel"})
	end
	-- A player's default is walking up to them (OSRS), not examining them.
	if kind == "player" and out[1] and out[1].id == "Examine" then
		local walk = table.remove(out, 2)
		table.insert(out, 1, walk)
	end
	return out
end
-- Rich text for one option: verb (white) + target (kind colour) + level.
function HD.optionText(option, Theme)
	local tok = tbl(Theme and Theme.HudDepth)
	option = tbl(option)
	local text = paint(escape(option.verb or ""), tok.verb or "F3EEE2")
	if option.target and option.target ~= "" then text ..= " " .. paint(escape(option.target), option.targetColor or "FFFFFF") end
	if option.levelText then text ..= " " .. paint(escape(option.levelText), option.levelColor or "A9B4C0") end
	return text
end
-- The label: the default option and "/ N more options" (Cancel not counted).
function HD.labelText(options, Theme)
	local tok = tbl(Theme and Theme.HudDepth)
	options = tbl(options)
	if not options[1] then return "", "" end
	local extra = 0
	for i = 2, #options do if options[i]["local"] ~= "cancel" then extra += 1 end end
	local more = if extra > 0 then paint("/ " .. extra .. " more option" .. (if extra == 1 then "" else "s"), tok.more or "A9B4C0") else ""
	return HD.optionText(options[1], Theme), more
end
-- Examine text from data (no network): creatures, townsfolk, resource nodes,
-- other prompts and players.
function HD.examineText(target, Data)
	target, Data = tbl(target), tbl(Data)
	if target.kind == "monster" then
		local line = target.monsterId and HD.MonsterExamine[target.monsterId]
		if line then return line end
		local m = tbl(Data.Monsters)[target.monsterId]
		if m and m.name then return m.name .. ": a level-" .. num(m.level, 1) .. " creature of the " .. tostring(m.region or "isles") .. " isles." end
		return "A creature of the isles."
	elseif target.kind == "npc" then
		local npc = tbl(tbl(Data.Townsfolk).NPCs)[target.role]
		if npc and npc.name then return npc.name .. (if npc.title then ", " .. npc.title else "") .. "." end
		return tostring(target.name or "Someone") .. ", an islander."
	elseif target.kind == "player" then
		local text = tostring(target.name or "A voyager")
		if target.renown then text ..= " · Isle Renown " .. num(target.renown) .. (if target.title then " (" .. tostring(target.title) .. ")" else "") end
		return text .. "."
	end
	for _, p in ipairs(tbl(target.prompts)) do
		local def, skill = HD.resourceDef(Data, p.item)
		if def then
			return def.name .. ": a " .. string.lower(skill) .. " node. Needs " .. skill .. " " .. num(def.level, 1) .. "; " .. num(def.xp) .. " XP a harvest."
		end
	end
	local name = HD.parseObject(target.name or (tbl(target.prompts)[1] or {}).object or "")
	return if name ~= "" then name .. "." else "Nothing interesting happens."
end

------------------------------------------------------------------------------
-- Status orbs
------------------------------------------------------------------------------
-- in = {health, maxHealth, prayer, prayerMax, prayerActive (bool), speed,
--       mastery (snapshot depth.mastery), masteryTrees (Data.Mastery.Trees),
--       dungeon = {class, ultimates, abilityReady}}
-- Returns 4 orbs {id, fraction, text, color, active, dim, caption}.
HD.ORB_IDS = {"Health", "Prayer", "Speed", "Special"}
HD.SPEED_MIN, HD.SPEED_MAX = 50, 400 -- Progression.walkSpeed clamps Speed to this range
local function short(n)
	n = math.floor(num(n))
	if n >= 10000 then return math.floor(n / 1000) .. "k" end
	return tostring(n)
end
HD.short = short
function HD.orbValues(input, Theme)
	input = tbl(input)
	local tok = tbl(Theme and Theme.HudDepth)
	local orbs = {}
	local hp, maxHp = math.max(0, num(input.health)), math.max(1, num(input.maxHealth, 100))
	local hf = math.clamp(hp / maxHp, 0, 1)
	table.insert(orbs, {id = "Health", fraction = hf, text = short(math.ceil(hp)), color = tok.orbHealth or "E8413C", caption = "Health",
		low = hf <= 0.25, clickable = false})
	local pmax = num(input.prayerMax)
	local points = math.max(0, num(input.prayer))
	table.insert(orbs, {id = "Prayer", fraction = if pmax > 0 then math.clamp(points / pmax, 0, 1) else 0, text = if pmax > 0 then short(points) else "–",
		color = tok.orbPrayer or "5EC8E6", caption = if input.prayerActive then "Quick-prayers on" else "Quick-prayers", active = input.prayerActive == true,
		dim = pmax <= 0, clickable = pmax > 0})
	local speed = num(input.speed, 100)
	table.insert(orbs, {id = "Speed", fraction = math.clamp((speed - HD.SPEED_MIN) / (HD.SPEED_MAX - HD.SPEED_MIN), 0, 1), text = short(speed),
		color = tok.orbSpeed or "F2D15C", caption = "Speed " .. short(speed) .. " · Agility courses", clickable = true})
	-- Special: a dungeon class's ultimate charges while in a run, else the
	-- readiest owned mastery capstone (Skill Mastery abilities).
	local dungeon = tbl(input.dungeon)
	local special
	if type(dungeon.class) == "string" and dungeon.class ~= "" then
		local ult = math.max(0, math.floor(num(dungeon.ultimates)))
		local wait = math.max(0, num(dungeon.abilityReady))
		special = {id = "Special", fraction = if ult > 0 then 1 else 0, text = "×" .. ult, color = tok.orbSpecial or "B07CFF",
			caption = "Ultimate ×" .. ult .. (if wait > 0 then " · ability in " .. math.ceil(wait) .. "s" else " · ability ready"), active = ult > 0, clickable = ult > 0, mode = "ultimate"}
	else
		local best
		local trees = tbl(tbl(input.mastery).trees)
		for _, def in ipairs(tbl(input.masteryTrees)) do
			local t = trees[def.id]
			local cap = def.capstone and def.NodeById and def.NodeById[def.capstone]
			if type(t) == "table" and t.capstone and cap and type(cap.ability) == "table" then
				local length = math.max(1, num(cap.ability.cooldown, 300))
				local left = math.max(0, num(t.cooldown))
				local f = 1 - math.clamp(left / length, 0, 1)
				if not best or f > best.fraction or (f == best.fraction and num(t.active) > num(best.activeFor)) then
					best = {fraction = f, left = left, name = cap.name, tree = def.id, activeFor = num(t.active)}
				end
			end
		end
		if best then
			special = {id = "Special", fraction = best.fraction, text = if best.left <= 0 then "✦" else short(math.ceil(best.left)) .. "s",
				color = tok.orbSpecial or "B07CFF", caption = best.name .. (if best.activeFor > 0 then " active" elseif best.left <= 0 then " ready" else " recharging"),
				active = best.activeFor > 0, clickable = true, mode = "mastery", tree = best.tree}
		else
			special = {id = "Special", fraction = 0, text = "–", color = tok.orbSpecial or "B07CFF", caption = "No capstone yet · Skill Mastery", dim = true,
				clickable = true, mode = "mastery"}
		end
	end
	table.insert(orbs, special)
	return orbs
end
-- Quick-prayer orb: the prayer verbs to send. Any active prayer -> each active
-- one toggled off; none active -> each quick prayer toggled on.
function HD.quickPrayerPlan(active, quick)
	local split = function(v)
		local out = {}
		if type(v) == "string" then for id in v:gmatch("[^,]+") do table.insert(out, id) end end
		return out
	end
	local on = split(active)
	if #on > 0 then return on, false end
	return split(quick), true
end
-- A vertical fill as a transparency gradient (Rotation 90: 0 = top). Returns
-- keypoint pairs {time, transparency}: empty above (1 - fraction), filled below.
function HD.fillKeys(fraction)
	fraction = math.clamp(num(fraction), 0, 1)
	if fraction <= 0 then return {{0, 1}, {1, 1}} end
	if fraction >= 1 then return {{0, 0}, {1, 0}} end
	local edge = 1 - fraction
	return {{0, 1}, {math.max(0.001, edge - 0.002), 1}, {edge, 0}, {1, 0}}
end

------------------------------------------------------------------------------
-- Chat filter tabs
------------------------------------------------------------------------------
HD.CHAT_TABS = {"All", "Game", "Public", "Private", "Crew", "Trade"}
HD.CHAT_STATES = {"On", "Filtered", "Off"}
HD.STATE_COLORS = {On = "57D96A", Filtered = "F2C14E", Off = "FF6B5A"}
HD.TRADE_WORDS = {"wts", "wtb", "wtt", "selling", "buying", "trade", "trading", "price check", "pc", "lf", "for sale"}
function HD.defaultStates() return {Game = "On", Public = "On", Private = "On", Crew = "On", Trade = "On"} end
function HD.cycleState(state)
	if state == "On" then return "Filtered" elseif state == "Filtered" then return "Off" end
	return "On"
end
function HD.encodeStates(states)
	local parts = {}
	for i = 2, #HD.CHAT_TABS do
		local name = HD.CHAT_TABS[i]
		table.insert(parts, name .. "=" .. (tbl(states)[name] or "On"))
	end
	return table.concat(parts, ";")
end
function HD.decodeStates(text)
	local states = HD.defaultStates()
	if type(text) == "string" then
		for name, state in text:gmatch("(%a+)=(%a+)") do
			if states[name] and table.find(HD.CHAT_STATES, state) then states[name] = state end
		end
	end
	return states
end
local function hasTradeWord(text)
	local lower = " " .. string.lower(tostring(text or "")):gsub("[^%w%s]", " ") .. " "
	for _, word in ipairs(HD.TRADE_WORDS) do
		if lower:find(" " .. word .. " ", 1, true) then return true end
	end
	return false
end
HD.hasTradeWord = hasTradeWord
-- msg = {system, metadata, channel, text, fromCrew}
function HD.chatCategory(msg)
	msg = tbl(msg)
	local meta = tostring(msg.metadata or "")
	if msg.system or meta:sub(1, 8) == "IsleGame" or meta:sub(1, 6) == "Roblox" then return "Game" end
	local channel = tostring(msg.channel or "")
	if channel:sub(1, 10) == "RBXWhisper" then return "Private" end
	if channel:sub(1, 4) == "Crew" or channel:sub(1, 7) == "RBXTeam" then return "Crew" end
	if msg.fromCrew then return "Crew" end
	if hasTradeWord(msg.text) then return "Trade" end
	return "Public"
end
-- Show this message? tab = the selected tab ("All" or a category); states =
-- {category = On|Filtered|Off}; msg.important (game), msg.friend / msg.crew /
-- msg.self (player messages) pass a Filtered state.
function HD.chatShows(category, states, tab, msg)
	msg = tbl(msg)
	if msg.self then return true end -- your own lines always echo
	if category == "Private" then return true end -- whispers always pass (the Private tab badges them)
	if tab and tab ~= "All" and tab ~= category then return false end
	local state = tbl(states)[category] or "On"
	if state == "Off" then return false end
	if state == "Filtered" then
		if category == "Game" then return msg.important == true end
		return msg.friend == true or msg.crew == true
	end
	return true
end

-- Game messages: the snapshot message splits on "   ·   " into segments, each
-- classified and colour-coded. Important ones pass the Game tab's Filtered state.
HD.SEPARATOR = "   ·   "
function HD.segments(message)
	local out = {}
	if type(message) ~= "string" or message == "" then return out end
	for segment in (message .. HD.SEPARATOR):gmatch("(.-)   ·   ") do
		segment = segment:gsub("^%s+", ""):gsub("%s+$", "")
		if segment ~= "" then table.insert(out, segment) end
	end
	return out
end
HD.DROP_PREFIXES = {"received", "mined", "caught", "chopped", "harvested", "looted", "you catch", "you mine", "you chop", "you harvest", "you loot", "you find", "found"}
local RARITY_WORDS = {"Rare", "Epic", "Legendary", "Mythic", "Divine", "RARE DROP", "PET DROP"}
function HD.gameKind(text, Theme)
	local tok = tbl(Theme and Theme.HudDepth)
	text = tostring(text or "")
	local lower = string.lower(text)
	if text:find("level %d+!") or lower:find("level up", 1, true) or lower:find("levelled", 1, true) then
		return "levelup", tok.chatLevel or "F7C548", true
	end
	for _, word in ipairs(RARITY_WORDS) do
		if text:find(word, 1, true) then return "rare", tok.chatRare or "FF8CF0", true end
	end
	if lower:find("can't", 1, true) or lower:find("cannot", 1, true) or lower:find("not enough", 1, true) or lower:find("^you need") or lower:find("too far", 1, true)
		or lower:find("first%.?$") or lower:find("full", 1, true) or lower:find("refused", 1, true) then
		return "warning", tok.chatWarn or "FF8A7A", false
	end
	if text:find("^%+") or lower:find("drop", 1, true) then return "drop", tok.chatDrop or "8EE05A", false end
	for _, prefix in ipairs(HD.DROP_PREFIXES) do
		if lower:sub(1, #prefix) == prefix then return "drop", tok.chatDrop or "8EE05A", false end
	end
	if lower:find("coins", 1, true) then return "coins", tok.chatCoins or "FFE6A6", false end
	if text:find("[%u][%u][%u]+") then return "announce", tok.chatAnnounce or "6FE3C8", true end
	return "info", tok.chatInfo or "C9D3DC", false
end
-- Repeat collapser (pure; the caller supplies the clock). A line is held for
-- `window` seconds; repeats inside it (and within `hold` of the first) only
-- bump the count, and one line "text ×N" is emitted when the burst ends or a
-- different line arrives.
function HD.newCollapser(window, hold)
	local c = {window = window or 0.9, hold = hold or 4, pending = nil}
	-- Returns emits {text, count, data} (0 or 1 of them).
	function c.push(text, now, data)
		local p = c.pending
		if p and p.text == text and now - p.last <= c.window and now - p.first <= c.hold then
			p.count += 1
			p.last = now
			return {}
		end
		local out = c.flush()
		c.pending = {text = text, count = 1, first = now, last = now, data = data}
		return out
	end
	function c.due(now)
		local p = c.pending
		if p and (now - p.last > c.window or now - p.first > c.hold) then return c.flush() end
		return {}
	end
	function c.flush()
		local p = c.pending
		c.pending = nil
		if not p then return {} end
		return {{text = p.text, count = p.count, data = p.data}}
	end
	return c
end
function HD.collapsedText(text, count)
	return if num(count, 1) > 1 then text .. "  ×" .. math.floor(num(count)) else text
end

------------------------------------------------------------------------------
-- Pickup feed
------------------------------------------------------------------------------
-- Positive item deltas between two snapshots' item maps (ids sorted for a
-- stable order). Coins rise too: id "coins".
function HD.itemDeltas(before, after, coinsBefore, coinsAfter)
	local out = {}
	if type(before) ~= "table" or type(after) ~= "table" then return out end
	for id, n in pairs(after) do
		local gain = num(n) - num(before[id])
		if type(id) == "string" and gain > 0 then table.insert(out, {id = id, n = math.floor(gain)}) end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	local coins = num(coinsAfter) - num(coinsBefore)
	if coinsBefore ~= nil and coinsAfter ~= nil and coins > 0 then table.insert(out, {id = "coins", n = math.floor(coins)}) end
	return out
end
-- The server's snapshot.pickups ({{id, n}}: gathering, fishing, loot and kill
-- drops only) validated: known items or "coins", whole positive counts, merged.
function HD.pickupEntries(list, Data)
	local out, index = {}, {}
	if type(list) ~= "table" then return out end
	local items = tbl(tbl(Data).Items)
	for _, e in ipairs(list) do
		local id, n = type(e) == "table" and e.id, math.floor(num(type(e) == "table" and e.n))
		if type(id) == "string" and n > 0 and (id == "coins" or items[id]) then
			if index[id] then index[id].n += n else index[id] = {id = id, n = n}; table.insert(out, index[id]) end
		end
	end
	return out
end
-- feed: array of {id, n, at (last merge), born}; merges into a live entry of the
-- same id within `window` s, else appends; trims the oldest past maxLines.
-- Returns the entry and whether it merged.
function HD.feedPush(feed, id, n, now, window, maxLines)
	for _, entry in ipairs(feed) do
		if entry.id == id and now - entry.at <= (window or 3) then
			entry.n += n
			entry.at = now
			return entry, true
		end
	end
	local entry = {id = id, n = n, at = now, born = now}
	table.insert(feed, entry)
	while #feed > math.max(1, maxLines or 5) do table.remove(feed, 1) end
	return entry, false
end
-- Drops entries idle longer than `life` s. Returns how many went.
function HD.feedExpire(feed, now, life)
	local gone = 0
	for i = #feed, 1, -1 do
		if now - feed[i].at > (life or 4) then table.remove(feed, i); gone += 1 end
	end
	return gone
end
function HD.feedText(entry, def, Theme)
	entry = tbl(entry)
	if entry.id == "coins" then return "+" .. HD.commas(entry.n) .. " coins", tbl(Theme and Theme.hex).gold or "F7C548" end
	local rarity = Theme and Theme.rarity and Theme.rarity(def and def.rarity or "Common")
	return "+" .. HD.commas(entry.n) .. " " .. tostring(def and def.name or entry.id), rarity and rarity.hex or "FFFFFF"
end
function HD.commas(n)
	local s = tostring(math.floor(num(n)))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

------------------------------------------------------------------------------
-- Hitsplats
------------------------------------------------------------------------------
-- payload = IsleCombatFx "hit" ({amount, crit, miss, tag}) or {hurt = true,
-- amount} / {heal = true, amount}. Returns {kind, text, fill, edge, ink, size,
-- tag, tagColor, scale}.
function HD.splatStyle(payload, Theme)
	payload = tbl(payload)
	local tok = tbl(Theme and Theme.HudDepth)
	local amount = math.max(0, math.floor(num(payload.amount)))
	-- "miss" only for a real miss; a landed hit that did nothing (resisted,
	-- absorbed) is a blue 0, as in OSRS.
	if payload.miss then
		return {kind = "miss", text = "miss", fill = tok.splatMiss or "3E78C8", edge = tok.splatMissEdge or "1C3A66", ink = "FFFFFF", size = 13, scale = 0.86}
	end
	if amount == 0 and not payload.heal then
		return {kind = "zero", text = "0", fill = tok.splatMiss or "3E78C8", edge = tok.splatMissEdge or "1C3A66", ink = "FFFFFF", size = 16, scale = 0.9,
			tag = if payload.tag == "resist" then "resist" else nil, tagColor = "A9BDC1"}
	end
	if payload.heal then
		return {kind = "heal", text = "+" .. HD.commas(amount), fill = tok.splatHeal or "3FBF5A", edge = "184A22", ink = "FFFFFF", size = 16, scale = 0.95}
	end
	local style = {kind = "hit", text = HD.commas(amount), fill = tok.splatHit or "C8282C", edge = tok.splatHitEdge or "4E0A0C", ink = "FFFFFF", size = 17, scale = 1}
	if payload.hurt then style.kind, style.fill, style.edge = "hurt", tok.splatHurt or "D2452E", "4E140C" end
	if payload.crit then
		-- Crits keep the plain number; the amber starburst behind the badge marks them.
		style.kind = "crit"
		style.fill, style.edge, style.ink, style.size, style.scale = tok.splatCrit or "FF9A1F", tok.splatCritEdge or "6A2A00", "FFF6D8", 21, 1.28
	end
	if payload.tag == "weak" then
		style.tag, style.tagColor = "WEAK!", tok.splatWeak or "FFD24A"
	elseif payload.tag == "resist" then
		style.tag, style.tagColor = "resist", "A9BDC1"
		if not payload.crit then style.fill, style.edge = tok.splatResist or "7A858C", "2E3438" end
	end
	return style
end
-- Badge shape for a splat's text: up to three characters fit a diamond
-- (OSRS-sized splats); longer numbers and "miss" get a rounded pill sized to
-- the text. Returns shape, width, height (px at scale 1).
function HD.splatShape(text, size)
	local chars = utf8.len(tostring(text or "")) or #tostring(text or "")
	size = size or 16
	if chars <= 3 then return "diamond", 32, 32 end
	return "pill", math.min(120, 14 + math.ceil(chars * size * 0.72)), 26
end
-- Overhead bar colour by fraction (green -> amber -> red).
function HD.barColor(fraction)
	fraction = math.clamp(num(fraction), 0, 1)
	if fraction > 0.5 then return "57D96A" elseif fraction > 0.25 then return "F2C14E" end
	return "E8413C"
end

return HD

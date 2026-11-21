-- Crafting: data rules, balance model, world stations and server behaviour.
-- Part A checks shared/GameData.lua (Data.Crafting) with shared/Progression.lua
-- (sets, accessories, stats). Part B runs world.server.lua with real Roblox
-- instances and checks Artificers' Row on the Guild Terrace. Part C runs
-- server.server.lua against those prompts (deterministic clock, rolls and a
-- DataStore double) and plays station visits, paced batches, shatters, gates,
-- moving away, client-sent quantities, worn items, commissions, Collection
-- credit, the Mining gem roll, migration and persistence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local CR = Data.Crafting
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(CR) == "table", "Data.Crafting exists")
ok(table.find(Data.SkillOrder, "Crafting") ~= nil, "Crafting registered in SkillOrder")
eq(Data.SkillOrder[#Data.SkillOrder], "Crafting", "Crafting appended last (old saves keep their order)")
do
	local def = Data.Skills.Crafting
	ok(def and def.category == "production" and #def.color == 6 and def.title and def.description, "Crafting skill metadata")
	for stat, v in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil and v > 0 and v <= 1, "perLevel stat " .. stat .. " modest like other production skills") end
	ok(Data.Mastery.capePerk("Crafting") == Data.Mastery.CapePerk.Crafting, "99 mantle perk registered")
	-- Original title/colour (no collision with another skill).
	for id, other in pairs(Data.Skills) do
		if id ~= "Crafting" then ok(other.title ~= def.title and other.color ~= def.color, "Crafting title/colour unique vs " .. id) end
	end
	-- Level stats reach the stat sheet.
	local p = {xp = {Crafting = Data.XP_TABLE[99]}, items = {}}
	local s1 = P.computeStats({xp = {}, items = {}}, 0)
	local s99 = P.computeStats(p, 0)
	ok(near(s99.defense - s1.defense, math.floor(98 * def.perLevel.defense)), "Crafting 99 adds Defense per level")
	ok(near(s99.rangedAccuracy - s1.rangedAccuracy, 98 * def.perLevel.rangedAccuracy), "Crafting 99 adds Ranged Accuracy per level")
end
-- Stations and branches.
eq(#CR.StationOrder, 3, "three Crafting stations")
for _, id in ipairs(CR.StationOrder) do
	local st = CR.Stations[id]
	ok(st and st.name and st.verb and #st.color == 6 and #st.gesture >= 1, id .. " station metadata")
end
for _, id in ipairs(CR.BranchOrder) do
	local b = CR.Branches[id]
	ok(b and CR.Stations[b.station] ~= nil, id .. " branch at a station")
	ok(b.seconds >= 1.2 and b.seconds <= 3, id .. " branch cadence 1.2-3 s (no instant crafts)")
	ok(b.gesture == "hammer" or b.gesture == "saw" or b.gesture == "stir", id .. " branch gesture exists")
	if b.tool then ok(table.find(CR.ToolOrder, b.tool) ~= nil, id .. " tool is a Crafting tool") end
end
-- Tools: Forge recipes (Smithing), owned and never consumed.
for _, id in ipairs(CR.ToolOrder) do
	local def, rec = Data.Items[id], Data.Recipes[id]
	ok(def and def.kind == "material" and def.category == "craftTool", id .. " tool item")
	ok(rec and rec.station == "Forge" and rec.skill == "Smithing" and rec.level <= 5, id .. " forged at the Forge early")
	for _, r in pairs(CR.Recipes) do ok(r.costs[id] == nil, id .. " never consumed by " .. r.id) end
end
-- Every recipe is well-formed.
local seenIds, byBranch, totalRecipes = {}, {}, 0
for _, id in ipairs(CR.RecipeOrder) do
	local r = CR.Recipes[id]
	totalRecipes += 1
	ok(not seenIds[id], id .. " listed once")
	seenIds[id] = true
	ok(Data.Recipes[id] == nil, id .. " is not a generic craft recipe (only the paced batch verb makes it)")
	ok(Data.Items[r.output] ~= nil, id .. " output exists")
	ok(r.level >= 1 and r.level <= 99 and r.xp > 0 and r.amount >= 1, id .. " level/xp/amount")
	ok(r.skill == "Crafting" or (r.skill == "Enchanting" and r.branch == "enchant"), id .. " trains Crafting (Enchanting for amulets)")
	ok(r.repeatable == true and r.seconds == CR.Branches[r.branch].seconds and r.station == CR.Branches[r.branch].station, id .. " branch fields")
	for item, n in pairs(r.costs) do ok(Data.Items[item] ~= nil and n >= 1 and n % 1 == 0, id .. " cost " .. item) end
	for item, t in pairs(r.collectionTier or {}) do
		ok(table.find(Data.CollectionItems, item) ~= nil and t >= 1 and t <= #Data.CollectionTiers, id .. " gate " .. item .. " is a collection")
	end
	if r.tool then ok(Data.Items[r.tool] and Data.Items[r.tool].category == "craftTool", id .. " tool") end
	byBranch[r.branch] = (byBranch[r.branch] or 0) + 1
end
for _, b in ipairs(CR.BranchOrder) do ok((byBranch[b] or 0) >= 1, b .. " has recipes") end
ok(totalRecipes >= 70, "deep recipe list (" .. totalRecipes .. ")")
-- Levels span 1-99 coverage: a new pattern opens at least every 12 levels.
do
	local levels = {}
	for _, r in pairs(CR.Recipes) do if r.skill == "Crafting" then levels[r.level] = true end end
	local last = 0
	for l = 1, 99 do if levels[l] then ok(l - last <= 12, "pattern gap ending at Crafting " .. l); last = l end end
	ok(last >= 85, "late-game patterns reach Crafting 85+ (" .. last .. ")")
end
-- Gems: eight tiers, ascending, existing cut gems reused, rough gems as collections.
eq(#CR.Gems, 8, "eight gem tiers")
for i, g in ipairs(CR.Gems) do
	ok(Data.Items[g.cut].category == "gem" and Data.Items[g.rough].category == "roughGem", g.cut .. " cut/rough items")
	ok(CR.Recipes[g.cut] and CR.Recipes[g.cut].shatter and CR.Recipes[g.cut].costs[g.rough] == 1 and CR.Recipes[g.cut].tool == "FacetChisel", g.cut .. " cut with the chisel")
	ok(table.find(Data.CollectionItems, g.rough) ~= nil and table.find(Data.CollectionItems, g.cut) ~= nil, g.cut .. " rough + cut collections")
	if i > 1 then
		ok(g.level > CR.Gems[i - 1].level and g.xp > CR.Gems[i - 1].xp and g.minTier >= CR.Gems[i - 1].minTier, g.cut .. " ascends")
		ok(Data.Rarity[Data.Items[g.cut].rarity].rank >= Data.Rarity[Data.Items[CR.Gems[i - 1].cut].rarity].rank, g.cut .. " rarity ascends")
	end
	ok(Data.Items[g.ingot] ~= nil and Data.Stats[g.stat] ~= nil and Data.Stats[g.stat2] ~= nil, g.cut .. " jewellery theme")
end
for _, id in ipairs({"SunstoneChip", "Mistpearl", "Emberglass", "Voidgarnet", "StarheartGem"}) do ok(CR.GemByCut[id] ~= nil, "existing gem " .. id .. " is cuttable") end
-- Shatter chance: CUT_FAIL at the gem's level, fading to zero CUT_FADE levels above.
do
	local r = CR.Recipes.Mistpearl
	eq(CR.cutFailChance(r, r.level), CR.CUT_FAIL, "full shatter chance at the gem's level")
	ok(near(CR.cutFailChance(r, r.level + CR.CUT_FADE / 2), CR.CUT_FAIL / 2), "half way fades to half")
	eq(CR.cutFailChance(r, r.level + CR.CUT_FADE), 0, "no shatter at +" .. CR.CUT_FADE)
	eq(CR.cutFailChance(r, 99), 0, "no shatter at 99")
	eq(CR.cutFailChance(CR.Recipes.GlassVial, 1), 0, "only gem cutting shatters")
	ok(CR.cutFailChance(r, r.level + 3) < CR.cutFailChance(r, r.level), "higher level shatters less")
end
-- Mining roll: chance rises gently by ore tier; gems gated by tier.
ok(near(CR.gemChance(1), CR.GEM_CHANCE) and CR.gemChance(8) > CR.gemChance(1) and CR.gemChance(8) < 3 * CR.gemChance(1), "gem chance by ore tier")
ok(CR.gemChance(1) <= 0.02, "rough gems are a rare roll")
for t = 1, 8 do
	for r = 0, 0.999, 0.037 do
		local rough = CR.roughFor(t, r)
		local g = CR.GemByRough[rough]
		ok(g ~= nil and g.minTier <= t, "tier " .. t .. " roll " .. r .. " gives an allowed gem")
	end
end
eq(CR.roughFor(1, 0), "RoughDewquartz", "lowest roll")
eq(CR.roughFor(1, 0.9999), "RoughSunstone", "tier 1 tops at Sunstone")
eq(CR.roughFor(8, 0.99999), "RoughStarheart", "Celestium can turn up a Starheart")
-- Leather: five tiers, each a four-piece Ranged set with a bonus (Sets rules).
eq(#CR.Leathers, 5, "five leather tiers")
for i, l in ipairs(CR.Leathers) do
	local set = Data.Sets[l.set.id]
	ok(set ~= nil and #set.pieces == 4, l.set.id .. " set has exactly four pieces")
	local slots = {}
	for _, id in ipairs(set.pieces) do
		local def = Data.Items[id]
		ok(def.kind == "armor" and def.set == l.set.id and def.requires.Ranged == l.set.ranged, id .. " Ranged armour piece")
		ok(not slots[def.slot] and table.find(Data.ArmorSlots, def.slot) ~= nil, id .. " fills its own slot")
		slots[def.slot] = true
		ok((def.stats.rangedAccuracy or 0) > 0 and (def.stats.defense or 0) > 0, id .. " ranged stats")
		ok(CR.Recipes[id].branch == "leather" and CR.Recipes[id].costs[l.id] >= 1 and CR.Recipes[id].costs.SpunThread >= 1, id .. " stitched from " .. l.id)
	end
	ok(next(set.bonus) ~= nil and type(set.text) == "string", l.set.id .. " set bonus")
	ok(CR.Recipes[l.id].branch == "tan", l.id .. " tanned")
	if i > 1 then
		ok(l.set.level > CR.Leathers[i - 1].set.level and l.set.ranged > CR.Leathers[i - 1].set.ranged, l.set.id .. " ascends")
		ok(l.set.armor.defense > CR.Leathers[i - 1].set.armor.defense, l.set.id .. " stronger")
		ok(CR.Recipes[l.id].costs.TanningOil ~= nil, l.id .. " needs Tanning Oil (glass link)")
	end
	-- Set bonus applies with all four worn, not with three.
	local p = {xp = {Ranged = Data.XP_TABLE[99]}, items = {}, equipment = {}}
	for _, id in ipairs(set.pieces) do p.items[id] = 1; p.equipment[Data.Items[id].slot] = id end
	local full = P.computeStats(p, 0)
	eq(full.activeSet, l.set.id, l.set.id .. " active with four pieces")
	p.equipment.boots = nil
	local three = P.computeStats(p, 0)
	ok(three.activeSet == nil, l.set.id .. " inactive with three")
	for stat, v in pairs(l.set.bonus) do ok(full[stat] - three[stat] >= v - 1e-6, l.set.id .. " bonus " .. stat) end
end
-- Jewellery: accessories with Magical Power; three kinds per gem + four enchanted + two glass charms.
do
	local n = 0
	for _, id in ipairs(CR.JewelleryOrder) do
		local def = Data.Items[id]
		n += 1
		ok(def and def.kind == "accessory" and def.category == "jewellery" and next(def.stats) ~= nil, id .. " jewellery accessory")
		ok(Data.Rarity[def.rarity] ~= nil and has(def.description, "Magical Power " .. Data.Rarity[def.rarity].power), id .. " Magical Power text")
		ok(CR.Recipes[id] ~= nil and CR.Recipes[id].station == "Jeweller", id .. " made at the Jeweller's Bench")
		local p = {xp = {}, items = {[id] = 1}, accessoryBag = {id}}
		eq(P.magicalPower(p), Data.Rarity[def.rarity].power, id .. " feeds Magical Power from the bag")
	end
	eq(n, #CR.Gems * 3 + 4 + 2, "jewellery count")
	for _, g in ipairs(CR.Gems) do
		local ring, neck, amulet = Data.Items[g.short:gsub("[^%w]", "") .. "Ring"], Data.Items[g.short:gsub("[^%w]", "") .. "Necklace"], Data.Items[g.amulet]
		ok(ring and neck and amulet, g.cut .. " ring/necklace/amulet")
		ok(Data.Rarity[ring.rarity].rank <= Data.Rarity[neck.rarity].rank and Data.Rarity[neck.rarity].rank <= Data.Rarity[amulet.rarity].rank, g.cut .. " rarity ring <= necklace <= amulet")
		ok(CR.Recipes[g.amulet].costs.SpunThread == 1 and CR.Recipes[g.amulet].tool == "AmuletMould", g.cut .. " amulet strung, cast in a mould")
	end
	for _, id in ipairs(CR.EnchantOrder) do
		local r = CR.Recipes[id]
		ok(r.skill == "Enchanting" and r.costs.ArcaneDust > 0, id .. " Enchanting with Arcane Dust")
		local base
		for k in pairs(r.costs) do if Data.Items[k].kind == "accessory" then base = k end end
		ok(base ~= nil and Data.Rarity[Data.Items[id].rarity].rank == Data.Rarity[Data.Items[base].rarity].rank + 1, id .. " one rarity above " .. tostring(base))
	end
end
-- Alchemy link is proposed but OFF: potion costs are unchanged.
eq(CR.VIALS_IN_POTIONS, false, "vial potion change awaits the lead")
for _, id in ipairs(CR.VIAL_POTIONS) do ok(Data.Recipes[id] and Data.Recipes[id].skill == "Alchemy" and Data.Recipes[id].costs.GlassVial == nil, id .. " unchanged") end
ok(CR.Recipes.TanningOil.costs.GlassVial == 1, "vials already feed Tanning Oil")
-- Commissions: craft tasks credit Crafting outputs.
do
	local CL = Data.CommissionsLogs
	local n = 0
	for _, t in ipairs(CL.Tasks) do
		if t.kind == "craft" then
			n += 1
			ok(t.skill == "Crafting" and CL.TaskById[t.id] == t, t.id .. " Crafting commission")
			local open = false
			for _, r in pairs(CR.Recipes) do if r.output == t.target and r.level <= t.levels.Crafting then open = true end end
			ok(open, t.id .. " target craftable at its gate")
		end
	end
	eq(n, 4, "four Crafting commissions")
	ok(#CL.Tasks <= 45, "commission pool within its bound")
end
-- parseBatch: client text is only a recipe id and a count, clamped server-side.
do
	local id, n = CR.parseBatch("GlassVial:5")
	ok(id == "GlassVial" and n == 5, "parse id:count")
	id, n = CR.parseBatch("GlassVial")
	ok(id == "GlassVial" and n == 1, "bare id is one action")
	id, n = CR.parseBatch("GlassVial:100000")
	eq(n, CR.MAX_BATCH, "huge counts clamp to MAX_BATCH")
	eq(CR.parseBatch("GlassVial:0"), nil, "zero refused")
	eq(CR.parseBatch("GlassVial:-3"), nil, "negative refused")
	eq(CR.parseBatch("GlassVial:2.5"), nil, "fraction refused")
	eq(CR.parseBatch("Nope:2"), nil, "unknown recipe refused")
	eq(CR.parseBatch(string.rep("A", 80)), nil, "long text refused")
	eq(CR.parseBatch(nil), nil, "nil refused")
	eq(CR.parseBatch("BrassIngot:1"), nil, "generic recipes are not Crafting batches")
end
-- CR.check gates (level, tool, collection, costs).
do
	local lv = function(n) return function() return n end end
	local tier = function(n) return function() return n end end
	local p = {items = {FacetChisel = 1, RoughSkyjade = 2}}
	ok(CR.check(p, "Skyjade", lv(30), tier(0)), "cut Skyjade at 30 with chisel and rough")
	ok(has(select(2, CR.check(p, "Skyjade", lv(29), tier(0))), "requires Crafting 30"), "level gate")
	ok(has(select(2, CR.check({items = {RoughSkyjade = 1}}, "Skyjade", lv(99), tier(0))), "Facet Chisel"), "tool gate")
	ok(has(select(2, CR.check({items = {FacetChisel = 1}}, "Skyjade", lv(99), tier(0))), "Needs 1 Rough Skyjade"), "cost gate")
	local q = {items = {AmuletMould = 1, Skyjade = 1, SunsteelIngot = 2, SpunThread = 1}}
	ok(has(select(2, CR.check(q, "SkyjadeAmulet", lv(99), tier(0))), "collection tier"), "collection gate")
	ok(CR.check(q, "SkyjadeAmulet", lv(99), tier(1)), "collection tier met")
	ok(not CR.check(q, "Nope", lv(99), tier(9)), "unknown pattern")
end
-- Balance model (documented in docs/DEPTH-CONTRACT.md §22). Supply-chain XP/h
-- of each trainable end product within 0.5x..2x of the best Smithing /
-- Fletching / Glyphcraft chain open at the same level (raw input gather time,
-- those crafts are instant); station rates are cadence-bound.
do
	local function prodRate(r)
		local s = 0
		for k, n in pairs(r.costs) do s += n * CR.rawSeconds(k) end
		return 3600 * r.xp / s
	end
	local function refRate(L)
		local best = 0
		for _, r in pairs(Data.Recipes) do
			if (r.skill == "Smithing" or r.skill == "Fletching" or r.skill == "Glyphcraft") and r.level <= L and r.repeatable then best = math.max(best, prodRate(r)) end
		end
		return best
	end
	local rows = {}
	for _, id in ipairs(CR.RecipeOrder) do
		local r = CR.Recipes[id]
		if r.branch == "blow" or r.branch == "leather" or r.branch == "weave" then
			local c, ref = CR.chainRate(r), refRate(r.level)
			ok(c / ref >= 0.5 and c / ref <= 2, string.format("%s chain %.0f XP/h vs production %.0f (x%.2f) within 0.5..2", id, c, ref, c / ref))
			if r.branch ~= "leather" or Data.Items[r.output].slot == "chest" then table.insert(rows, string.format("%s L%d %.0f (x%.2f)", id, r.level, c, c / ref)) end
		end
		-- Cadence: one action per branch period, so a full batch takes MAX_BATCH x seconds.
		ok(CR.stationRate(r) <= 3600 / r.seconds * r.xp + 1e-6, id .. " station rate is cadence-bound")
	end
	print("Crafting supply-chain XP/h: " .. table.concat(rows, "; "))
	-- Gem cutting is a bonus on Mining: at most ~3% extra XP on top of the ore's own XP.
	for t, r in ipairs(Data.ResourceTiers.Mining) do
		local perHour = 3600 / math.max(r.respawn, CR.GATHER)
		local bonus = CR.cutRate(t, perHour)
		ok(bonus > 0 and bonus <= 0.06 * perHour * r.xp, string.format("%s: cutting bonus %.0f XP/h vs mining %.0f", r.id, bonus, perHour * r.xp))
	end
end
print("PASS: " .. (checks - partA) .. " Crafting data/rule assertions.")

------------------------------------------------------------------------------
-- Part B: world placement (real instances).
------------------------------------------------------------------------------
local partB = checks
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = {Connected = true}
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, {f, c})
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local destroyingSignals = {}
roblox.implementProperty("ProximityPrompt", "Destroying", function(prompt)
	if not destroyingSignals[prompt] then destroyingSignals[prompt] = signal() end
	return destroyingSignals[prompt]
end)
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
luau.load(worldSource, {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
local terrace = islands and islands:FindFirstChild("Guild Terrace")
ok(terrace ~= nil, "Guild Terrace island built")
local stationPrompt, stationModel = {}, {}
local craftParts = 0
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "craftStation" then
		local id = q:GetAttribute("IsleItem")
		ok(CR.Stations[id] ~= nil and stationPrompt[id] == nil, "one prompt per station: " .. tostring(id))
		stationPrompt[id] = q
		ok(near(q.HoldDuration, 0.36) and q.MaxActivationDistance == 9 and not q.RequiresLineOfSight, id .. " prompt uses the interact hold")
		local node = q.Parent
		while node and node.Parent ~= terrace do node = node.Parent end
		ok(node ~= nil and node:GetAttribute("CraftingContent") == true, id .. " sits in CraftingContent on the Guild Terrace")
		stationModel[id] = node
	end
end
for _, id in ipairs(CR.StationOrder) do
	ok(stationPrompt[id] ~= nil, id .. " built")
	ok(terrace:FindFirstChild("Anchor_Waypoint_" .. id, true) ~= nil, id .. " waypoint anchor")
end
for _, m in terrace:GetChildren() do
	if m:GetAttribute("CraftingContent") then
		for _, obj in m:GetDescendants() do
			if obj:IsA("BasePart") then
				if not string.find(obj.Name, "^Anchor_") then craftParts += 1 end
				ok(obj.Anchored, obj.Name .. " anchored")
			end
			ok(not obj:IsA("Light"), "no new lights on the terrace (" .. obj.Name .. ")")
		end
	end
end
ok(craftParts >= 12 and craftParts <= 40, "Crafting stations stay within a small part budget (" .. craftParts .. ")")
-- Stations use existing mesh slots and stand apart from each other and from the old stations.
do
	local shapes = {}
	for _, m in pairs(stationModel) do for _, obj in m:GetDescendants() do if obj:IsA("BasePart") and obj:GetAttribute("Shape") then shapes[obj:GetAttribute("Shape")] = true end end end
	for _, s in ipairs({"Workbench", "Forge", "Barrel", "OreCluster"}) do ok(shapes[s], "mesh slot " .. s .. " used") end
	local IC, R = terrace:GetAttribute("IslandCenter"), terrace:GetAttribute("IslandRadius")
	local spots = {}
	for id, q in pairs(stationPrompt) do
		local pos = q.Parent.CFrame.Position
		ok(Vector3.new(pos.X - IC.X, 0, pos.Z - IC.Z).Magnitude <= R - 8, id .. " on the terrace")
		for other, at in pairs(spots) do ok((at - pos).Magnitude >= 10, id .. " apart from " .. other) end
		spots[id] = pos
		for _, obj in terrace:GetDescendants() do
			if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "station" then
				ok((obj.Parent.CFrame.Position - pos).Magnitude >= 10, id .. " clear of the " .. tostring(obj:GetAttribute("IsleItem")) .. " station")
			end
		end
	end
end
-- No other solid part intrudes into a station's footprint.
for id, m in pairs(stationModel) do
	local q = stationPrompt[id]
	local pos = q.Parent.CFrame.Position
	for _, obj in terrace:GetDescendants() do
		if obj:IsA("BasePart") and obj.CanCollide and not obj:IsDescendantOf(m) and obj.Size.Y < 20 and obj.CFrame.Position.Y > pos.Y - 1 then
			local flat = Vector3.new(obj.CFrame.Position.X - pos.X, 0, obj.CFrame.Position.Z - pos.Z).Magnitude
			ok(flat > 3 or obj.Size.X > 30 or obj.Size.Z > 30, id .. " footprint clear of " .. obj.Name)
		end
	end
end
print("PASS: " .. (checks - partB) .. " Crafting world assertions (" .. craftParts .. " parts).")

------------------------------------------------------------------------------
-- Part C: server behaviour against the world prompts.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local clock, utc = 10, 1500000000
local function advance(seconds) clock += seconds; utc += seconds end
local data = {}
local db = {}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	return copy(data[key])
end
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P}
local rolls, defaultRoll = {}, 0.999
local function nextRoll() if #rolls > 0 then return table.remove(rolls, 1) end return defaultRoll end
local function queue(...) for _, v in ipairs({...}) do table.insert(rolls, v) end end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "crafting-test" end},
	RunService = {IsStudio = function() return false end},
}
local coroutines, yieldOf = {}, {}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end}, Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state; player.pushes = (player.pushes or 0) + 1 end}
		table.insert(serverObjects, o)
		return o
	end},
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return nextRoll() end} end},
	task = {
		spawn = function(f, ...)
			local co = coroutine.create(f)
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			if coroutine.status(co) == "suspended" then table.insert(coroutines, co) end
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) yieldOf[coroutine.running()] = t; return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local ticker
for _, co in ipairs(coroutines) do if yieldOf[co] == CR.TICK then ticker = co end end
ok(ticker ~= nil, "Crafting batch loop runs every CR.TICK")
-- One server tick (the loop body runs Crafting.tick(os.clock()) once).
local function tick() assert(coroutine.resume(ticker, CR.TICK)) end -- task.wait returns the elapsed time
-- Let `seconds` pass in TICK steps, running the loop each step.
local function run(seconds)
	local steps = math.ceil(seconds / CR.TICK - 1e-9)
	for _ = 1, steps do advance(CR.TICK + 1e-4); tick() end -- slack for float sums
end
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.zero, Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) services.Players.PlayerRemoving:Fire(p) end
local function rejoin(p, mutate)
	leave(p)
	if mutate then mutate(data["p" .. p.UserId].profile) end
	return player(p.UserId)
end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction RemoteFunction found")
local function cmd(p, verb, item)
	advance(1)
	return remote.OnServerInvoke(p, verb, item)
end
local function use(p, q)
	advance(1)
	p.root.Position = q.Parent.CFrame.Position + Vector3.new(0, 0, 2)
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local X = Data.XP_TABLE
local J, T, G = stationPrompt.Jeweller, stationPrompt.Tannery, stationPrompt.Glassworks

-- Fresh journal: snapshot key and refusals before any visit.
local crafter = seeded(7001, function(prof)
	prof.xp.Crafting = X[12]
	prof.items = {FacetChisel = 1, RoughSunstone = 6, RoughDewquartz = 3, BlowingPipe = 1, MoltenGlass = 4, Ore = 6, Timber = 3}
end)
local s0 = cmd(crafter, "state")
ok(type(s0.crafting) == "table" and s0.crafting.station == "" and s0.crafting.job == nil, "snapshot carries crafting")
ok(type(s0.crafting.made) == "table" and s0.crafting.shattered == 0, "crafting profile migrated")
eq(s0.levels.Crafting, 12, "Crafting level in the snapshot")
ok(has(cmd(crafter, "craftBatch", "SunstoneChip:3").message, "Jeweller's Bench"), "no batch before visiting the station")
ok(has(cmd(crafter, "craftStation", "Jeweller").message, "Visit a Crafting station"), "station visits only come from the world prompt")
eq(cmd(crafter, "craft", "SunstoneChip").items.SunstoneChip, nil, "the generic craft verb cannot make Crafting patterns")
-- Visit the Jeweller's Bench.
local v = use(crafter, J)
ok(has(v.message, "Jeweller's Bench"), "visit message")
eq(crafter.attrs.IsleStation, "Jeweller", "IsleStation opens Workshop › Crafting")
ok((crafter.attrs.IsleStationVisit or 0) >= 1, "visit counter bumped")
local sv = cmd(crafter, "state")
eq(sv.crafting.station, "Jeweller", "snapshot station")
eq(sv.crafting.near, true, "snapshot: at the station")
-- Wrong station for the pattern.
ok(has(cmd(crafter, "craftBatch", "MoltenGlass:1").message, "Glass Furnace"), "glass needs the Glass Furnace")
-- Start a batch of 3 Sunstone cuts (level 12: shatter 0.3*(1-2/25) = 27.6%).
local shatter = CR.cutFailChance(CR.Recipes.SunstoneChip, 12)
ok(shatter > 0.25 and shatter < 0.3, "low-level shatter chance")
local start = cmd(crafter, "craftBatch", "SunstoneChip:3")
ok(has(start.message, "Crafting 3×") and has(start.message, "1.8s each"), "batch started")
eq(start.items.RoughSunstone, 6, "nothing spent at the start")
eq(crafter.attrs.CraftingJob, "SunstoneChip:0:3", "CraftingJob published")
ok(start.crafting.job and start.crafting.job.total == 3 and start.crafting.job.done == 0, "job in snapshot")
-- No action before the cadence (1.8 s after the start): 1.5 s is still short.
advance(1.5); tick()
eq(crafter.last.items.RoughSunstone, 6, "no action before 1.8 s")
-- First action: a clean cut (roll above the shatter chance).
queue(0.99)
advance(0.3); tick()
local a1 = crafter.last
eq(a1.items.RoughSunstone, 5, "one rough spent")
eq(a1.items.SunstoneChip, 1, "one Sunstone cut")
eq(a1.xp.Crafting, X[12] + CR.Recipes.SunstoneChip.xp, "cut XP")
eq(a1.collection.SunstoneChip, 1, "cut gem counted in collections (collect path)")
ok(has(a1.message, "+1 Sunstone Chip") and has(a1.message, "1/3"), "progress message")
ok(has(crafter.attrs.CraftingGesture, "hammer:"), "gesture published for the animation")
eq(crafter.attrs.CraftingJob, "SunstoneChip:1:3", "progress published")
-- Second action: shatter (roll below the chance) -> Gem Grit, a quarter of the XP.
local xpBefore = a1.xp.Crafting
local gesture1 = crafter.attrs.CraftingGesture
queue(0.01)
run(CR.Branches.cut.seconds)
local a2 = crafter.last
eq(a2.items.RoughSunstone, 4, "shattered rough spent")
eq(a2.items.SunstoneChip, 1, "no gem from a shatter")
eq(a2.items.GemGrit, 1, "Gem Grit from the shatter")
eq(a2.xp.Crafting, xpBefore + math.floor(CR.Recipes.SunstoneChip.xp * CR.SHATTER_XP), "shatter pays a share of the XP")
ok(has(a2.message, "shattered"), "shatter message")
ok(crafter.attrs.CraftingGesture ~= gesture1, "a new gesture seq per action")
-- No catch-up bursts: a long pause still yields exactly one more action.
queue(0.99)
advance(60); tick()
local a3 = crafter.last
eq(a3.items.RoughSunstone, 3, "one action after a long pause (no burst)")
ok(has(a3.message, "Batch done") and has(a3.message, "1 shattered"), "batch summary")
eq(crafter.attrs.CraftingJob, "", "job cleared at the end")
eq(a3.crafting.job, nil, "no job in the snapshot")
eq(a3.crafting.shattered, 1, "shatter tally")
eq(a3.crafting.made.SunstoneChip, 2, "made tally")
advance(10); tick()
eq(crafter.last.items.RoughSunstone, 3, "finished batches do nothing more")
-- Client-sent quantities are clamped; the satchel decides how many actually happen.
local big = cmd(crafter, "craftBatch", "SunstoneChip:5000")
ok(has(big.message, "Crafting " .. CR.MAX_BATCH .. "×"), "count clamped to MAX_BATCH")
for _ = 1, 3 do queue(0.99); run(CR.Branches.cut.seconds) end
local out = crafter.last
eq(out.items.RoughSunstone, 0, "three cuts with three roughs")
run(CR.Branches.cut.seconds)
ok(has(crafter.last.message, "Needs 1 Rough Sunstone"), "batch stops when materials run out")
eq(crafter.attrs.CraftingJob, "", "job ended without materials")
for _, bad in ipairs({"SunstoneChip:0", "SunstoneChip:-2", "SunstoneChip:1.5", "Nope:3", "SunstoneChip:x"}) do
	ok(has(cmd(crafter, "craftBatch", bad).message, "Choose a Crafting pattern"), "malformed batch refused: " .. bad)
end
-- Level gate: Mistpearl needs Crafting 20.
ok(has(cmd(crafter, "craftBatch", "Mistpearl:1").message, "requires Crafting 20"), "level gate")
-- Moving away stops the batch.
cmd(crafter, "craftBatch", "Dewquartz:3")
crafter.root.Position = crafter.root.Position + Vector3.new(CR.STATION_RANGE + 5, 0, 0)
run(CR.Branches.cut.seconds)
ok(has(crafter.last.message, "stepped away"), "walking away stops the batch")
eq(crafter.last.items.RoughDewquartz, 3, "nothing spent away from the bench")
ok(has(cmd(crafter, "craftBatch", "Dewquartz:1").message, "Stand at the"), "cannot start away from the bench")
-- Stop verb.
use(crafter, J)
cmd(crafter, "craftBatch", "Dewquartz:3")
ok(has(cmd(crafter, "craftStop").message, "stopped after 0/3"), "stop verb")
run(5)
eq(crafter.last.items.RoughDewquartz, 3, "stopped batch does nothing")
ok(has(cmd(crafter, "craftStop").message, "not crafting"), "stop with no job")
-- Replacing a batch restarts the cadence (no free action).
cmd(crafter, "craftBatch", "Dewquartz:3")
advance(1.5); tick()
local sw = cmd(crafter, "craftBatch", "Dewquartz:2")
ok(has(sw.message, "Switched to 2×"), "a new batch replaces the old one")
advance(0.5); tick()
eq(crafter.last.items.RoughDewquartz, 3, "replacement waits a full cadence")
queue(0.99); run(CR.Branches.cut.seconds)
eq(crafter.last.items.RoughDewquartz, 2, "then crafts")
cmd(crafter, "craftStop")
-- Visit expiry.
-- Let the visit lapse while the autosave loop keeps the journal lease alive.
do
	local saver
	for _, co in ipairs(coroutines) do if yieldOf[co] == 55 then saver = co end end
	ok(saver ~= nil, "autosave loop found")
	local waited = 0
	while waited < CR.VISIT_SECONDS + 5 do
		advance(50); waited += 50
		assert(coroutine.resume(saver, 55))
	end
end
ok(has(cmd(crafter, "craftBatch", "Dewquartz:1").message, "Jeweller's Bench"), "an old visit no longer authorises batches")
-- Glass: sift, melt and blow at the Glass Furnace (no shatter, one roll-free action each).
use(crafter, G)
eq(crafter.attrs.IsleStation, "Glassworks", "furnace visit")
ok(has(cmd(crafter, "craftBatch", "Skysand:2").message, "Crafting 2×"), "sift sand")
run(CR.Branches.sift.seconds * 2)
eq(crafter.last.items.Skysand, 4, "two sifts make four Skysand")
eq(crafter.last.items.Ore, 4, "two Ore spent")
cmd(crafter, "craftBatch", "GlassVial:2")
run(CR.Branches.blow.seconds * 2)
local gv = crafter.last
eq(gv.items.GlassVial, 2, "two vials blown")
eq(gv.items.MoltenGlass, 2, "molten glass spent")
ok(has(crafter.attrs.CraftingGesture, "stir:"), "furnace gesture")
-- Tool gate: no needle at the Tanning Rack.
local tanner = seeded(7002, function(prof)
	prof.xp.Crafting = X[20]
	prof.items = {BeastHide = 8, Herb = 20, DropSpindle = 1, GlassVial = 2}
	prof.commissions = nil
end)
use(tanner, T)
ok(has(cmd(tanner, "craftBatch", "WayfarerTreads:1").message, "Hide Needle"), "tool gate (needle)")
cmd(tanner, "craftBatch", "CuredLeather:4")
run(CR.Branches.tan.seconds * 4)
eq(tanner.last.items.CuredLeather, 4, "four hides tanned")
cmd(tanner, "craftBatch", "SpunThread:2")
run(CR.Branches.spin.seconds * 2)
eq(tanner.last.items.SpunThread, 6, "spun thread (three per action)")
eq(tanner.last.items.Herb, 16, "herb fibre spent")
-- Leather armour (with a needle) and the four-piece set.
tanner = rejoin(tanner, function(prof) prof.items.HideNeedle = 1; prof.items.CuredLeather = 7; prof.items.SpunThread = 7 end)
use(tanner, T)
for _, id in ipairs(Data.Sets.Wayfarer.pieces) do
	cmd(tanner, "craftBatch", id .. ":1")
	run(CR.Branches.leather.seconds)
	eq(tanner.last.items[id], 1, id .. " stitched")
	eq(cmd(tanner, "equip", id).depth.equipment[Data.Items[id].slot], id, id .. " equips (Ranged 1)")
end
local worn = cmd(tanner, "state")
eq(worn.depth.stats.activeSet, "Wayfarer", "Wayfarer set bonus active with four pieces")
eq(worn.items.CuredLeather, 0, "leather spent (1+3+2+1)")
-- Worn items are never consumed as costs.
local jeweller = seeded(7003, function(prof)
	prof.xp.Crafting = X[60]
	prof.xp.Enchanting = X[40]
	prof.items = {EmberglassAmulet = 1, ArcaneDust = 100, SparkGlyph = 40, AmuletMould = 1, RingMould = 1, NecklaceMould = 1,
		Dewquartz = 4, AlloyIngot = 10, SpunThread = 4, Emberglass = 3, SunsteelIngot = 4}
	prof.collection = {Emberglass = 5000}
	prof.accessoryBag = {"EmberglassAmulet"}
end)
use(jeweller, J)
ok(has(cmd(jeweller, "craftBatch", "EnchantedEmberglassAmulet:1").message, "accessory bag"), "bagged amulet is not consumed")
cmd(jeweller, "accessory", "EmberglassAmulet")
local ench = cmd(jeweller, "craftBatch", "EnchantedEmberglassAmulet:1")
ok(has(ench.message, "Crafting 1×"), "spare amulet can be enchanted")
run(CR.Branches.enchant.seconds)
local e1 = jeweller.last
eq(e1.items.EnchantedEmberglassAmulet, 1, "enchanted amulet made")
eq(e1.xp.Enchanting, X[40] + CR.Recipes.EnchantedEmberglassAmulet.xp, "enchanting pays Enchanting XP")
eq(e1.xp.Crafting, X[60], "no Crafting XP for enchanting")
-- Jewellery: ring, necklace, amulet; the amulet feeds Magical Power.
cmd(jeweller, "craftBatch", "DewquartzAmulet:2")
run(CR.Branches.jewel.seconds * 2)
eq(jeweller.last.items.DewquartzAmulet, 2, "two amulets cast")
eq(jeweller.last.items.SpunThread, 2, "amulets strung")
local mp0 = cmd(jeweller, "state").depth.stats.magicalPower
local bag = cmd(jeweller, "accessory", "DewquartzAmulet")
eq(bag.depth.stats.magicalPower, mp0 + Data.Rarity[Data.Items.DewquartzAmulet.rarity].power, "crafted amulet adds Magical Power")
-- Collection gate: Skyjade jewellery needs a Skyjade collection.
jeweller = rejoin(jeweller, function(prof) prof.items.Skyjade = 2 end)
use(jeweller, J)
ok(has(cmd(jeweller, "craftBatch", "SkyjadeRing:1").message, "collection tier"), "collection gate on jewellery")
-- Commissions: a Crafting commission counts batch actions of its target.
local commissioner = seeded(7004, function(prof)
	prof.xp.Crafting = X[30]
	prof.items = {BlowingPipe = 1, MoltenGlass = 5}
end)
do
	local snap = cmd(commissioner, "logsSync")
	ok(type(snap.logs) == "table", "logs snapshot")
end
do
	-- Put the vial commission on today's board directly (the board draw is seeded).
	leave(commissioner)
	local prof = data["p7004"].profile
	ok(type(prof.commissions) == "table" and type(prof.commissions.slots) == "table", "commission board saved")
	prof.commissions.slots[1] = {id = "CraftGlassVial", progress = 0}
	commissioner = player(7004)
end
use(commissioner, G)
cmd(commissioner, "craftBatch", "GlassVial:3")
run(CR.Branches.blow.seconds * 3)
local cs = cmd(commissioner, "logsSync")
local slot
for _, s in ipairs(cs.logs.commissions.slots or {}) do if s.id == "CraftGlassVial" then slot = s end end
ok(slot ~= nil and slot.progress == 3, "craft commission progressed by three actions")
eq(cs.collection.GlassVial, 3, "vials counted through collect()")
-- Mining harvests roll a rough gem.
do
	local miner = seeded(7005, function(prof) prof.xp.Mining = X[5] end)
	local ore
	for _, q in islands:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "gather" and q:GetAttribute("IsleItem") == "Ore" and not q:GetAttribute("OwnerUserId") and not q:GetAttribute("IsleRegion") then ore = q break end
	end
	ok(ore ~= nil, "a Copperstone node")
	local before = cmd(miner, "state")
	defaultRoll = 0.999
	local g1 = use(miner, ore)
	ok(g1 and (g1.items.Ore or 0) > 0, "harvest works")
	local roughs = 0
	for _, gem in ipairs(CR.Gems) do roughs += g1.items[gem.rough] or 0 end
	eq(roughs, 0, "no gem on a high roll")
	advance(10)
	defaultRoll = 0.001
	local g2 = use(miner, ore)
	defaultRoll = 0.999
	eq(g2.items.RoughDewquartz, 1, "low roll turns up a rough gem (tier 1 -> Dewquartz)")
	eq(g2.collection.RoughDewquartz, 1, "rough gem counted as a collection")
	ok(has(g2.message, "Rough gem"), "gem message")
	local _ = before
end
-- Persistence and migration: tallies survive; garbage is dropped.
crafter = rejoin(crafter)
local sp = cmd(crafter, "state")
eq(sp.crafting.made.SunstoneChip, 5, "made tally persisted")
eq(sp.crafting.shattered, 1, "shatter tally persisted")
eq(sp.crafting.station, "", "station visits are session-only")
crafter = rejoin(crafter, function(prof) prof.crafting = {made = {Nope = 4, SunstoneChip = -3, GlassVial = "x", Dewquartz = 2.7}, shattered = 0 / 0} end)
local sm = cmd(crafter, "state")
eq(sm.crafting.made.Nope, nil, "unknown recipe dropped")
eq(sm.crafting.made.SunstoneChip, nil, "negative dropped")
eq(sm.crafting.made.GlassVial, nil, "non-number dropped")
eq(sm.crafting.made.Dewquartz, 2, "fraction floored")
eq(sm.crafting.shattered, 0, "NaN shattered reset")
crafter = rejoin(crafter, function(prof) prof.crafting = "bogus" end)
ok(type(cmd(crafter, "state").crafting.made) == "table", "non-table crafting reset")
-- Leaving mid-batch clears the job (session-only) and keeps the save consistent.
use(crafter, G)
cmd(crafter, "craftBatch", "Skysand:5")
leave(crafter)
run(5)
eq(data["p7001"].profile.crafting.made.Skysand, nil, "no actions after leaving")
-- Dead players stop crafting.
local fragile = seeded(7006, function(prof) prof.items = {Ore = 5} end)
use(fragile, G)
cmd(fragile, "craftBatch", "Skysand:5")
fragile.humanoid.Health = 0
run(CR.Branches.sift.seconds)
ok(has(fragile.last.message, "stopped"), "a fallen crafter stops")
eq(fragile.last.items.Ore, 5, "nothing spent while down")
-- Ironman journals craft like everyone else (no trade path involved).
local iron = player(7007)
ok(has(cmd(iron, "ironman").message, "Ironman"), "ironman sealed")
leave(iron)
data["p7007"].profile.items = {Ore = 2}
iron = player(7007)
use(iron, G)
cmd(iron, "craftBatch", "Skysand:1")
run(CR.Branches.sift.seconds)
eq(iron.last.items.Skysand, 2, "ironman crafts at the station")
print("PASS: " .. (checks - partC) .. " Crafting server assertions.")
print("Crafting QA passed " .. checks .. " checks.")
print("SUITE-END verify-crafting.luau")

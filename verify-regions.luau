-- World Art & Regions (docs/DEPTH-CONTRACT.md §30).
-- Part A checks Data.RegionArt: every region's identity, landmark and banner
--   name, ≥2 questgivers per region, the regional quest chains (valid givers,
--   monsters, items, landmarks, talk targets, rewards, chains), warp scrolls,
--   generated dialogue and original names.
-- Part B checks the forged region meshes (art/WorldCatalog.lua): authored,
--   valid indices, non-degenerate, bounded, within the world triangle budget,
--   far-seen shapes carry a range; and the forge honours `range`.
-- Part C builds world.server.lua: static part budget (no rise over the 3897
--   baseline), island hulls, bridge spans and connectivity, landmarks with
--   survey stones and anchors, an NPC anchor per regional folk, banners,
--   waterfalls and the prop kit.
-- Part D runs server.server.lua: every regional quest is accepted, progressed
--   (talk / visit / kills / collect / hand-in / gather) and handed in through
--   the server verbs, rejoin-safe; shops; the warp scroll buy → learn → warp
--   flow and its refusals.
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
local RA, T = Data.RegionArt, Data.Townsfolk
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
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

------------------------------------------------------------------------------
-- Part A: data.
------------------------------------------------------------------------------
ok(type(RA) == "table", "Data.RegionArt present")
local regionCount = 0
for _, region in ipairs(Data.Regions) do
	regionCount += 1
	local art = RA.Regions[region.id]
	ok(art ~= nil, region.id .. " has region art")
	ok(table.find(RA.Order, region.id) ~= nil, region.id .. " is ordered")
	ok(type(art.title) == "string" and art.title == region.name and #art.epithet > 8, region.id .. " banner title and epithet")
	eq(#art.palette, 3, region.id .. " palette")
	for _, h in ipairs(art.palette) do ok(string.match(h, "^%x%x%x%x%x%x$") ~= nil, region.id .. " palette colour") end
	ok(type(art.landmark.id) == "string" and #art.landmark.name > 4 and RA.LandmarkById[art.landmark.id] == art.landmark, region.id .. " landmark")
	ok(type(art.ambience.particles) == "string" and type(art.ambience.sound) == "string", region.id .. " ambience hooks")
end
eq(regionCount, #RA.Order, "every region in the art order")
eq(Data.RegionById.Hub.name, "Compass Quay", "generic hub name replaced")
eq(Data.RegionById.Meadow.name, "Sunwheel Downs", "generic meadow name replaced")
eq(Data.RegionById.Quarry.name, "Brassfall Cay", "generic quarry name replaced")
local titles = {}
for _, region in ipairs(Data.Regions) do ok(not titles[region.name], "unique region name " .. region.name); titles[region.name] = true end
for name, epithet in pairs(RA.Isles) do ok(type(epithet) == "string" and #epithet > 8, name .. " island epithet") end

-- Folk and givers.
local givers = {}
local folkNames = {}
for _, f in ipairs(RA.Folk) do
	ok(T.NPCs[f.role] ~= nil and T.NPCs[f.role].anchorOnly, f.role .. " is a Townsfolk entry (anchor-only)")
	ok(table.find(T.RegionFolkOrder, f.role) ~= nil and table.find(T.Order, f.role) == nil, f.role .. " in the regional roster")
	ok(Data.RegionById[f.region] ~= nil, f.role .. " region")
	ok(not folkNames[f.name], "unique folk name " .. f.name)
	folkNames[f.name] = true
	for _, offer in ipairs(f.shop or {}) do
		ok(Data.Items[offer.item] ~= nil and offer.price > 0 and offer.amount >= 1, f.role .. " sells a real item " .. offer.item)
	end
end
for _, q in ipairs(RA.Quests) do
	local f = RA.FolkByRole[q.giver]
	ok(f ~= nil, q.id .. " giver exists")
	givers[f.region] = givers[f.region] or {}
	givers[f.region][q.giver] = true
end
for _, region in ipairs(RA.Order) do
	local n = 0
	for _ in pairs(givers[region] or {}) do n += 1 end
	ok(n >= 2, region .. " has at least two questgivers (" .. n .. ")")
	local shops = 0
	for _, f in ipairs(RA.Folk) do if f.region == region and f.shop then shops += 1 end end
	ok(region == "Hub" or shops >= 1, region .. " has a shopkeeper")
end
ok(RA.FolkByRole.WarpKeeper and RA.FolkByRole.WarpKeeper.kind == "warp", "a Warp Keeper")
ok(T.NPCs.Banker ~= nil and T.NPCs.Merchant ~= nil, "banker and quay merchant stand in the hub")
local townsfolk = 0
for _, f in ipairs(RA.Folk) do if f.kind == "townsfolk" then townsfolk += 1 end end
ok(townsfolk >= 1, "ambient townsfolk")

-- Quests.
ok(#RA.Quests >= 20, "twenty or more regional quests (" .. #RA.Quests .. ")")
local kinds = {}
for _, q in ipairs(RA.Quests) do
	eq(Data.QuestById[q.id], q, q.id .. " registered")
	eq(Data.Quests[q.index], q, q.id .. " indexed")
	ok(#q.title > 4 and #q.story > 30, q.id .. " text")
	ok(Data.RegionById[q.region] ~= nil and RA.FolkByRole[q.giver].region == q.region, q.id .. " given in its region")
	ok(#q.objectives >= 2, q.id .. " is multi-step")
	for _, o in ipairs(q.objectives) do
		kinds[o.kind] = true
		if o.kind == "kills" then ok(Data.Monsters[o.monster] ~= nil, q.id .. " monster " .. o.monster)
		elseif o.kind == "collect" or o.kind == "have" then ok(Data.Items[o.item] ~= nil, q.id .. " item " .. o.item)
		elseif o.kind == "gather" then ok(Data.RegionById[o.region] ~= nil, q.id .. " gather region")
		elseif o.kind == "talk" then ok(RA.FolkByRole[o.npc] ~= nil and o.npc ~= q.giver, q.id .. " talks to another folk")
		elseif o.kind == "visit" then ok(RA.LandmarkById[o.landmark] ~= nil and RA.LandmarkById[o.landmark].region == q.region, q.id .. " visits its region's landmark")
		else ok(false, q.id .. " unexpected objective " .. o.kind) end
		ok(not has(Data.describeCheck(o), "Unknown"), q.id .. " objective describes itself")
	end
	for _, r in ipairs(q.requires) do
		if r.kind == "quest" then ok(Data.QuestById[r.quest] ~= nil and (Data.QuestById[r.quest].index < q.index), q.id .. " chain prerequisite resolves") end
	end
	local rw = q.rewards
	ok((rw.coins or 0) > 0 and (rw.points or 0) >= 1, q.id .. " pays coins and Quest Points")
	for id in pairs(rw.items or {}) do ok(Data.Items[id] ~= nil, q.id .. " reward item") end
	if rw.lamp then ok(rw.lamp.skills ~= nil or rw.lamp.exclude ~= nil, q.id .. " lamp is gated") end
	if rw.unlock then ok(rw.unlock.warp == nil or RA.WarpByRegion[rw.unlock.warp] ~= nil, q.id .. " warp unlock") end
end
for _, kind in ipairs({"kills", "collect", "have", "gather", "talk", "visit"}) do ok(kinds[kind], "objective kind " .. kind .. " used") end
local unlocks = 0
for _, q in ipairs(RA.Quests) do if q.rewards.unlock and q.rewards.unlock.warp then unlocks += 1 end end
ok(unlocks >= 7, "quests unlock warps (" .. unlocks .. ")")
-- Warps.
for _, region in ipairs(Data.Regions) do
	local w = RA.WarpByRegion[region.id]
	ok(w ~= nil and Data.Items[w.scroll] ~= nil and w.price > 0, region.id .. " has a warp scroll")
	ok(string.match(w.anchor, "^Waypoint_") ~= nil, region.id .. " warp lands on a waypoint anchor")
end
-- Markers from snapshots.
do
	local q = RA.QuestById.SkywayCharter
	local function snap(entry, accepted) return {journal = {quests = {[q.index] = entry}}, regionQuests = {accepted = accepted or {}, talked = {}, warps = {}}} end
	eq(RA.marker(snap({id = q.id, available = true}), "WarpKeeper"), "offer", "offer marker (!)")
	eq(RA.marker(snap({id = q.id, available = true}, {SkywayCharter = true}), "WarpKeeper"), "active", "in-progress marker (grey ?)")
	eq(RA.marker(snap({id = q.id, available = true}, {SkywayCharter = true}), "Lamplighter") ~= nil, true, "talk target marked")
	eq(RA.marker(snap({id = q.id, available = true, ready = true}, {SkywayCharter = true}), "WarpKeeper"), "ready", "ready marker (gold ?)")
	eq(RA.marker(snap({id = q.id, done = true}), "WarpKeeper"), nil, "done quest clears the marker")
	eq(RA.marker(snap({id = q.id, available = false}), "WarpKeeper"), nil, "locked quest shows nothing")
	ok(T.Conditions.rqOffer_SkywayCharter(snap({id = q.id, available = true})), "offer condition")
	ok(T.Conditions["rqReady_SkywayCharter"](snap({id = q.id, available = true, ready = true}, {SkywayCharter = true})), "ready condition")
	ok(T.Conditions.rqTalk_Lamplighter(snap({id = q.id, available = true}, {SkywayCharter = true})), "talk option condition")
end
-- Banned borrowed names (original IP only).
local BANNED = {"Hypixel", "SkyBlock", "Skyblock", "Runescape", "Lumbridge", "Varrock", "Falador", "Hub Island", "Spider's Den", "Crimson Isle", "The End", "Deep Caverns",
	"Gold Mine", "Mushroom Desert", "The Barn", "The Park", "Dwarven", "Crystal Hollows"}
local function scan(text, where)
	for _, b in ipairs(BANNED) do ok(not has(text, b), where .. " avoids borrowed name " .. b) end
end
for _, f in ipairs(RA.Folk) do scan(f.name .. f.title .. f.greet, f.role) end
for _, q in ipairs(RA.Quests) do scan(q.title .. q.story, q.id) end
for id, art in pairs(RA.Regions) do scan(art.title .. art.epithet .. art.landmark.name, id) end
-- QC H1: no coin mint. Every coin-priced offer charges at least 1.3x the item's
-- sell value per unit (`sell` pays value; faction deliveries pay up to 1.3x):
-- regional shops, the Warp Keeper's scrolls, skill vendors (coin part) and the Roost.
local MARGIN = 1.3
local offers = 0
local function fair(where, item, coins, amount)
	offers += 1
	local def = Data.Items[item]
	local value = def and def.value or 1
	ok(coins / amount >= value * MARGIN - 1e-9, where .. " " .. item .. " sells at >= 1.3x value (" .. coins .. "c / " .. amount .. " vs value " .. value .. ")")
end
for _, f in ipairs(RA.Folk) do
	for i, offer in ipairs(f.shop or {}) do fair(f.role .. ":" .. i, offer.item, offer.price, offer.amount) end
end
for _, w in ipairs(RA.Warps) do fair("WarpKeeper", w.scroll, w.price, 1) end
for skill, vendor in pairs(Data.SkillVendors) do
	for _, e in ipairs(vendor.shop) do if e.cost.coins then fair(skill .. " vendor", e.item, e.cost.coins, 1) end end
end
for _, e in ipairs(Data.PetDepth.Shop) do fair("Roost", e.item, e.coins, 1) end
ok(offers >= 40, "coin offers priced against sell value (" .. offers .. ")")
eq(RA.FolkByRole.Fishmonger.shop[1].price / RA.FolkByRole.Fishmonger.shop[1].amount >= 12 * MARGIN, true, "Opal's cooked fish no longer mints coins")
-- QC L8: dialogue labels keep their full text (the button wraps) and each
-- quest's "How am I doing?" reports that quest.
for _, f in ipairs(RA.Folk) do
	local def = T.NPCs[f.role]
	for nodeId, node in pairs(def.nodes) do
		for _, option in ipairs(node.options) do
			ok(#option.label <= RA.LABEL_MAX, f.role .. "." .. nodeId .. " label fits two wrapped lines")
		end
	end
	for _, q in ipairs(RA.QuestsByGiver[f.role] or {}) do
		local opened, tip = false, nil
		for _, option in ipairs(def.nodes.hello.options) do if option.to == "quest_" .. q.id then opened = option.label == "Quest: " .. q.title end end
		ok(opened, q.id .. " hello label carries the full title")
		for _, option in ipairs(def.nodes["quest_" .. q.id].options) do if option.label == "How am I doing?" then tip = option.tip end end
		eq(tip, "rq_" .. q.id, q.id .. " progress tip is quest-specific")
		local entry = {id = q.id, available = true, objectives = {}}
		for j, o in ipairs(q.objectives) do entry.objectives[j] = {if j == 1 then 1 else 0, if o.count then o.count else 1} end
		local text = T.Tips[tip]({journal = {quests = {[q.index] = entry}}, regionQuests = {accepted = {[q.id] = true}, talked = {}, warps = {}}}, {})
		ok(has(text, q.title), q.id .. " tip names its quest")
		ok(has(text, Data.describeCheck(q.objectives[#q.objectives], true)), q.id .. " tip lists its own objectives") -- regional: "since accepting" (§33 QC)
		local first = q.objectives[1]
		if first.count and first.count > 1 then ok(has(text, "(1/" .. first.count .. ")"), q.id .. " tip shows counts") end
	end
	for _, offer in ipairs(f.shop or {}) do
		local name = Data.Items[offer.item].name
		local found = false
		for _, option in ipairs(def.nodes.shop.options) do if has(option.label, name .. " (" .. offer.price .. "c)") then found = true end end
		ok(found, f.role .. " shop label keeps " .. name .. " and its price")
	end
end
print("PASS: " .. checks .. " World Art & Regions data assertions (" .. #RA.Quests .. " quests, " .. #RA.Folk .. " folk).")

------------------------------------------------------------------------------
-- Part B: forged meshes.
------------------------------------------------------------------------------
local partB = checks
local World = load("art/WorldCatalog.lua")
local NEW = {IslandCliff = 1400, IslandCliffBare = 1400, IslandKeel = 1400, IslandKeelCrystal = 1400, IslandKeelEmber = 1400,
	RopeBridge = 700, StoneArchBridge = 700, CrystalBridge = 700, Windmill = 1200, WindmillSails = 1200, Caldera = 1200, CrystalSpire = 1200,
	Observatory = 1200, CompassTower = 1200, FenceRun = 0, CanopyTree = 0, FlowerPatch = 0, BannerPole = 0, TwinLantern = 0, CargoStack = 0,
	Glowshroom = 0, CoralFan = 0, HayCart = 0}
local newTris = 0
for name, range in pairs(NEW) do
	local data = World.shapes[name]
	ok(data ~= nil, name .. " is authored")
	-- §54 QC: the island hulls are 80-segment smooth strata (checked at real scale by the generator and verify-mesh).
	local cap = if string.sub(name, 1, 6) == "Island" then 8000 else 1500
	ok(#data.faces >= 200 and #data.faces <= cap, name .. " triangle budget (" .. #data.faces .. ")")
	ok(#data.vertices <= 4095, name .. " vertex count packs")
	newTris += #data.faces
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, v in ipairs(data.vertices) do
		local p = Vector3.new(v[1], v[2], v[3])
		ok(p.X == p.X and math.abs(p.X) < 60 and math.abs(p.Y) < 60 and math.abs(p.Z) < 60, name .. " bounded vertex")
		lo, hi = lo:Min(p), hi:Max(p)
	end
	ok((hi - lo).Magnitude > 1, name .. " has extent")
	for _, f in ipairs(data.faces) do
		local a, b, c = data.vertices[f[1]], data.vertices[f[2]], data.vertices[f[3]]
		ok(a and b and c and World.palette[f[4]] ~= nil, name .. " face indices and shade")
		local u = Vector3.new(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		local w = Vector3.new(c[1] - a[1], c[2] - a[2], c[3] - a[3])
		ok(u:Cross(w).Magnitude > 1e-6, name .. " non-degenerate")
	end
	if range > 0 then eq(data.range, range, name .. " forges from afar") else eq(data.range, nil, name .. " keeps the prop radius") end
	if data.fit then ok(data.fit[2][1] > data.fit[1][1] and data.fit[2][2] > data.fit[1][2] and data.fit[2][3] > data.fit[1][3], name .. " fit box") end
end
-- Deterministic: regenerating from art/*.cjs reproduces the catalog byte for byte (checked by the build's import parity).
local forgeSource = fs.readFile("forge.client.lua")
ok(has(forgeSource, "buildRadius(part)") and has(forgeSource, "RANGE_CAP"), "forge honours catalog range")
ok(has(forgeSource, "if mobile then 900"), "phones cap far forging")
print("PASS: " .. (checks - partB) .. " mesh assertions (" .. newTris .. " new triangles).")

------------------------------------------------------------------------------
-- Part C: the generated world.
------------------------------------------------------------------------------
local partC = checks
local BASELINE_PARTS = 3897 -- static parts before World Art (this section must not raise it)
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(q)
	if not promptSignals[q] then promptSignals[q] = signal() end
	return promptSignals[q]
end)
local tags = {}
local worldServices = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	Lighting = roblox.Instance.new("Lighting"),
	CollectionService = {AddTag = function(_, obj, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], obj) end},
	ReplicatedStorage = {WaitForChild = function(_, name) return if name == "AetherData" then "AetherData" else nil end},
	ServerStorage = {FindFirstChild = function() return nil end},
}
local world = roblox.Instance.new("Workspace")
local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
local buildStarted = os.clock()
luau.load(worldSource, {environment = {
	game = {GetService = function(_, name) return worldServices[name] end}, workspace = world, Instance = roblox.Instance, Vector3 = Vector3,
	Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum,
	task = {spawn = function(f, ...) local co = coroutine.create(f); assert(coroutine.resume(co, ...)); return co end, wait = function() return coroutine.yield() end},
	NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	require = function() return Data end,
}, injectGlobals = true})()
local buildSeconds = os.clock() - buildStarted
local islandsBuilt = world:FindFirstChild("Islands")
print(string.format("World build: %.2f s (headless, whole world.server.lua); World Art section %.3f s", buildSeconds, islandsBuilt and islandsBuilt:GetAttribute("RegionArtBuildSeconds") or -1))
local staticParts = 0
for _, obj in world:GetDescendants() do if obj:IsA("BasePart") then staticParts += 1 end end
ok(staticParts < 4000, "static world stays under the 4000 part budget (" .. staticParts .. ")")
ok(staticParts <= BASELINE_PARTS, "World Art does not raise the static part count (" .. BASELINE_PARTS .. " -> " .. staticParts .. ")")
local islands = world:FindFirstChild("Islands")
local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
local function islandOf(pos)
	local best
	for _, isle in islands:GetDescendants() do
		if not isle:IsA("Model") then continue end
		local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
		if c and flat(pos, c) <= r + .5 and math.abs(pos.Y - c.Y) < 3 and (not best or isle.Parent == islands) then best = isle end
	end
	return best
end
-- Island identity and hulls.
for _, isle in islands:GetChildren() do
	local region = isle:GetAttribute("RegionId")
	ok(region ~= nil, isle.Name .. " is a region island")
	eq(isle:GetAttribute("IsleTitle"), isle.Name, isle.Name .. " banner title")
	ok(type(isle:GetAttribute("IsleEpithet")) == "string" and #isle:GetAttribute("IsleEpithet") > 8, isle.Name .. " banner epithet")
	eq(isle:GetAttribute("RegionTitle"), Data.RegionById[region].name, isle.Name .. " region line")
	eq(isle:GetAttribute("Ambience"), RA.Regions[region].ambience.particles, isle.Name .. " ambience hook")
	local cliff, keel = isle:FindFirstChild("Floating foundation"), isle:FindFirstChild("Island underside")
	ok(cliff and string.find(cliff:GetAttribute("Shape"), "^IslandCliff") ~= nil, isle.Name .. " cliff hull is forged")
	ok(keel and string.find(keel:GetAttribute("Shape"), "^IslandKeel") ~= nil, isle.Name .. " keel hull is forged")
	ok(keel.CFrame.Position.Y + keel.Size.X / 2 < isle:GetAttribute("IslandCenter").Y - 6, isle.Name .. " keel hangs under the foundation")
	for _, name in ipairs({"Fractured cliff", "Keel rock", "Mineral stratum", "Lower basalt"}) do
		ok(isle:FindFirstChild(name) == nil, isle.Name .. " no longer stacks " .. name)
	end
end
-- Bridges: same connectivity (eight static spans), every span is a styled mesh over its deck.
local decks, styles = 0, {}
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") and obj.Name == "Continuous bridge deck" then
		decks += 1
		local half = obj.CFrame.LookVector * obj.Size.Z / 2
		local a, b = islandOf(obj.CFrame.Position + half + Vector3.new(0, .17, 0)), islandOf(obj.CFrame.Position - half + Vector3.new(0, .17, 0))
		ok(a ~= nil and b ~= nil and a ~= b, "bridge joins two islands")
		local style = obj:GetAttribute("BridgeStyle")
		styles[style] = (styles[style] or 0) + 1
		local span
		for _, sib in obj.Parent:GetChildren() do
			if sib.Name == "Bridge span" and (sib.CFrame.Position - obj.CFrame.Position).Magnitude < obj.Size.Z / 2 and sib:GetAttribute("Shape") == style
				and math.abs(sib.Size.Z - obj.Size.Z) < .01 then span = sib end
		end
		ok(span ~= nil and span.Transparency == 1 and not span.CanCollide, "deck carries its " .. tostring(style) .. " span mesh")
		local guards = 0
		for _, sib in obj.Parent:GetChildren() do if sib.Name == "Bridge guard" and sib.CanCollide and (sib.CFrame.Position - obj.CFrame.Position).Magnitude < 6 then guards += 1 end end
		ok(guards >= 2, "deck keeps both void guards")
	end
end
eq(decks, 8, "eight static bridges, as before (hub x4, grove-meadow, quarry-shelf, crown arenas x2)")
ok((styles.RopeBridge or 0) >= 2 and (styles.StoneArchBridge or 0) >= 3 and (styles.CrystalBridge or 0) == 2, "rope, stone-arch and crystal bridges")
-- Landmarks: one per region, each with a survey stone and a waypoint anchor.
local surveys = {}
for _, q in world:GetDescendants() do
	if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "landmark" then surveys[q:GetAttribute("IsleItem")] = q end
end
for _, region in ipairs(RA.Order) do
	local l = RA.Regions[region].landmark
	local found
	for _, obj in world:GetDescendants() do if obj:IsA("BasePart") and obj:GetAttribute("Landmark") == l.id then found = obj end end
	ok(found ~= nil, region .. " landmark " .. l.id .. " stands in the world")
	ok(found:GetAttribute("Shape") == l.shape, l.id .. " is the " .. l.shape .. " mesh")
	local q = surveys[l.id]
	ok(q ~= nil, l.id .. " has a survey stone")
	local host = islandOf(q.Parent.CFrame.Position - Vector3.new(0, .6, 0))
	ok(host ~= nil and host:GetAttribute("RegionId") == region, l.id .. " survey stone stands in its region")
	local gated = next(Data.RegionById[region].requires) ~= nil
	eq(q:GetAttribute("IsleRegion"), if gated then region else nil, l.id .. " survey honours the region gate")
	local fresh = ({CompassTower = true, Windmill = true, Caldera = true, Observatory = true, CrystalSpire = true})[l.shape]
	ok(not fresh or flat(q.Parent.CFrame.Position, found.CFrame.Position) <= 52, l.id .. " survey stone beside its new landmark")
	ok(world:FindFirstChild("Anchor_Waypoint_Landmark_" .. l.id, true) ~= nil, l.id .. " waypoint anchor")
end
ok(#(tags.RegionSpin or {}) == 1, "the Sunwheel sails spin (tag RegionSpin)")
-- Regional folk anchors.
for _, f in ipairs(RA.Folk) do
	local a = world:FindFirstChild("Anchor_NPC_" .. f.role, true)
	ok(a ~= nil, f.role .. " has an NPC anchor")
	local isle = islandOf(a.CFrame.Position)
	ok(isle ~= nil and isle:GetAttribute("RegionId") == f.region, f.role .. " stands in " .. f.region)
end
-- Spawn markers keep away from folk.
for _, marker in world:FindFirstChild("MonsterSpawns"):GetChildren() do
	for _, f in ipairs(RA.Folk) do
		local a = world:FindFirstChild("Anchor_NPC_" .. f.role, true)
		ok(flat(a.CFrame.Position, marker.CFrame.Position) >= 12, f.role .. " clear of " .. marker.Name)
	end
end
-- Waterfalls and prop kit.
local falls = 0
for _, obj in world:GetDescendants() do
	if obj:IsA("Beam") and obj.Name == "Waterfall" then
		falls += 1
		ok(obj.Attachment0 and obj.Attachment1 and obj.TextureSpeed ~= 0, "waterfall scrolls between two attachments")
	end
end
ok(falls >= 5, "waterfalls spill off the cliffs (" .. falls .. ")")
local props = islands:GetAttribute("RegionArtProps")
ok(type(props) == "number" and props >= 50, "prop kit dressed (" .. tostring(props) .. ")")
-- QC M1: every bridge span rides its deck's pitch (the sloped Brassfall -> Cinder Shelf span too).
local sloped = 0
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") and obj.Name == "Continuous bridge deck" then
		local deckLook = obj.CFrame.LookVector
		if math.abs(deckLook.Y) > .02 then sloped += 1 end
		local best
		for _, sib in obj.Parent:GetChildren() do
			if sib.Name == "Bridge span" and math.abs(sib.Size.Z - obj.Size.Z) < .01 and (sib.CFrame.Position - obj.CFrame.Position).Magnitude < obj.Size.Z / 2 then best = sib end
		end
		local angle = math.deg(math.acos(math.clamp(best.CFrame.LookVector:Dot(deckLook), -1, 1)))
		ok(angle < 0.5, "bridge span matches its deck's pitch (" .. string.format("%.2f", angle) .. " deg)")
		local up = best.CFrame.UpVector:Dot(obj.CFrame.UpVector)
		ok(up > .999, "bridge span stands on its deck's up vector")
	end
end
ok(sloped >= 1, "at least one sloped bridge is covered (" .. sloped .. ")")
-- QC M4: placement clearance. Folk anchors >= 6 studs from every other NPC anchor;
-- no solid World Art prop overlaps a Path or another prompt host on its island.
local npcAnchors = {}
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") and string.find(obj.Name, "^Anchor_NPC_") then table.insert(npcAnchors, obj) end
end
local regional = {}
for _, f in ipairs(RA.Folk) do regional["Anchor_NPC_" .. f.role] = true end
local npcPairs = 0
for i, a in ipairs(npcAnchors) do
	for j = i + 1, #npcAnchors do
		local b = npcAnchors[j]
		if (regional[a.Name] or regional[b.Name]) and math.abs(a.CFrame.Position.Y - b.CFrame.Position.Y) < 6 then
			npcPairs += 1
			ok(flat(a.CFrame.Position, b.CFrame.Position) >= 6 - 1e-6, a.Name .. " and " .. b.Name .. " stand >= 6 studs apart (" .. string.format("%.1f", flat(a.CFrame.Position, b.CFrame.Position)) .. ")")
		end
	end
end
ok(npcPairs > 0, "NPC spacing checked (" .. npcPairs .. " pairs)")
local function xzBox(obj)
	local cf, sz = obj.CFrame, obj.Size
	local function ext(axis) return math.abs(cf.RightVector[axis]) * sz.X / 2 + math.abs(cf.UpVector[axis]) * sz.Y / 2 + math.abs(cf.LookVector[axis]) * sz.Z / 2 end
	local c = cf.Position
	return c.X - ext("X"), c.X + ext("X"), c.Z - ext("Z"), c.Z + ext("Z"), c.Y - ext("Y"), c.Y + ext("Y")
end
local function overlapXZ(a, b)
	local ax0, ax1, az0, az1, ay0, ay1 = xzBox(a)
	local bx0, bx1, bz0, bz1, by0, by1 = xzBox(b)
	return ax0 < bx1 and bx0 < ax1 and az0 < bz1 and bz0 < az1 and ay0 < by1 + .5 and by0 < ay1 + .5
end
local solidArt, clearChecks = 0, 0
for _, isle in islands:GetChildren() do
	local paths, hosts = {}, {}
	for _, obj in isle:GetDescendants() do
		if obj:IsA("BasePart") and obj.Name == "Path" then table.insert(paths, obj) end
		if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then table.insert(hosts, obj.Parent) end
	end
	for _, model in isle:GetChildren() do
		if model:GetAttribute("RegionArt") then
			for _, obj in model:GetDescendants() do
				if obj:IsA("BasePart") and obj.CanCollide then
					solidArt += 1
					for _, path in ipairs(paths) do clearChecks += 1; ok(not overlapXZ(obj, path), obj.Name .. " on " .. isle.Name .. " keeps off the path") end
					for _, host in ipairs(hosts) do
						if host ~= obj then clearChecks += 1; ok(not overlapXZ(obj, host), obj.Name .. " on " .. isle.Name .. " clears prompt host " .. host.Name) end
					end
				end
			end
		end
	end
end
ok(solidArt >= 40 and clearChecks > 1000, "solid World Art clearance checked (" .. solidArt .. " parts, " .. clearChecks .. " pairs)")
-- QC M5: landmark hosts are display-only; simple colliders follow the silhouette.
local COLLIDED = {CompassSpire = true, Sunwheel = true, EmberCaldera = true, SunkenObservatory = true, VoidglassSpire = true}
for id in pairs(COLLIDED) do
	local body, cols = nil, {}
	for _, obj in world:GetDescendants() do
		if obj:IsA("BasePart") and obj:GetAttribute("Landmark") == id then body = obj end
		if obj:IsA("BasePart") and obj:GetAttribute("LandmarkCollider") == id then table.insert(cols, obj) end
	end
	ok(body ~= nil and not body.CanCollide, id .. " host does not collide (no invisible lid)")
	ok(#cols >= 2, id .. " has colliders (" .. #cols .. ")")
	for _, c in ipairs(cols) do
		ok(c.CanCollide and c.Anchored and c.Transparency == 1, id .. " collider is solid and invisible")
		local lp = body.CFrame:PointToObjectSpace(c.CFrame.Position)
		ok(math.abs(lp.X) <= body.Size.X / 2 + .5 and math.abs(lp.Z) <= body.Size.Z / 2 + .5 and math.abs(lp.Y) <= body.Size.Y / 2 + .5, id .. " collider stays inside the landmark's box")
	end
	if id == "EmberCaldera" then
		-- The crater is open: nothing covers its centre.
		for _, c in ipairs(cols) do
			local lp = c.CFrame:PointToObjectSpace(body.CFrame.Position)
			ok(not (math.abs(lp.X) < c.Size.X / 2 and math.abs(lp.Z) < c.Size.Z / 2), "caldera centre is open (no lid)")
		end
	elseif id == "SunkenObservatory" then
		-- The door (mesh front, -Z) is open at walking height.
		local door = body.CFrame * CFrame.new(0, -body.Size.Y / 2 + 1.5 + 2.5, -6.55)
		for _, c in ipairs(cols) do
			local lp = c.CFrame:PointToObjectSpace(door.Position)
			ok(not (math.abs(lp.X) < c.Size.X / 2 + .8 and math.abs(lp.Y) < c.Size.Y / 2 and math.abs(lp.Z) < c.Size.Z / 2 + .8), "observatory door is open")
		end
		local back = body.CFrame * CFrame.new(0, -body.Size.Y / 2 + 1.5 + 1.5, 6.55)
		local walled = false
		for _, c in ipairs(cols) do
			local lp = c.CFrame:PointToObjectSpace(back.Position)
			if math.abs(lp.X) < c.Size.X / 2 and math.abs(lp.Y) < c.Size.Y / 2 and math.abs(lp.Z) < c.Size.Z / 2 + .1 then walled = true end
		end
		ok(walled, "observatory back wall collides")
	end
end
-- QC L2: waterfalls start at the cliff's outer face and hang flat facing outward.
for _, obj in world:GetDescendants() do
	if obj:IsA("Beam") and obj.Name == "Waterfall" then
		local foundation = obj.Parent
		local isle = foundation.Parent
		local c = isle:GetAttribute("IslandCenter")
		local lip = foundation.CFrame * obj.Attachment0.CFrame
		local out = Vector3.new(lip.Position.X - c.X, 0, lip.Position.Z - c.Z)
		ok(math.abs(out.Magnitude - (foundation.Size.Y / 2 + .3)) < .05, isle.Name .. " waterfall lip on the cliff face (" .. string.format("%.2f vs %.2f", out.Magnitude, foundation.Size.Y / 2 + .3) .. ")")
		eq(obj.FaceCamera, false, isle.Name .. " waterfall has a fixed orientation")
		for _, att in ipairs({obj.Attachment0, obj.Attachment1}) do
			local wcf = att.Parent.CFrame * att.CFrame
			ok(wcf.RightVector:Dot(out.Unit) > .999 and wcf.UpVector.Y > .999, isle.Name .. " waterfall attachment faces outward")
		end
	end
end
-- QC L3: the sails spin out to the forge's landmark distance (1,200 desktop / 900 phone).
local regionsClient = fs.readFile("regions.client.lua")
ok(has(regionsClient, "SPIN_RANGE = if mobile then 900 else 1200") and has(regionsClient, "< SPIN_RANGE then"), "sail spin cutoff matches the forge distance")
ok(not has(regionsClient, "< 600 then"), "old 600-stud spin cutoff gone")
eq(World.shapes.WindmillSails.range, 1200, "sails forge at 1,200 studs")
-- QC L7: stale display names in player-facing strings.
ok(not has(fs.readFile("server.server.lua"), "Quarry Cay") and has(fs.readFile("server.server.lua"), "Train on Ore in Brassfall Cay"), "server says Brassfall Cay")
ok(not has(fs.readFile("ui.client.lua"), "return to the Aether Hub"), "Hubward Tablet line says Compass Quay")
print("PASS: " .. (checks - partC) .. " world assertions (" .. BASELINE_PARTS .. " -> " .. staticParts .. " static parts, " .. decks .. " bridges, " .. falls .. " waterfalls, " .. props .. " props).")

------------------------------------------------------------------------------
-- Part D: server verbs.
------------------------------------------------------------------------------
local partD = checks
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
-- NPC positions (Workspace.Townsfolk) and warp anchors (Workspace.Islands).
local npcAt, models = {}, {}
for i, f in ipairs(RA.Folk) do
	npcAt[f.role] = Vector3.new(i * 100, 5, 0)
	local root = {Position = npcAt[f.role]}
	table.insert(models, {GetAttribute = function(_, k) return if k == "TownsfolkRole" then f.role else nil end,
		FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end})
end
local anchorAt = {}
for i, w in ipairs(RA.Warps) do anchorAt["Anchor_" .. w.anchor] = Vector3.new(-500 - i * 60, 10, 300) end
local townsfolk = {GetChildren = function() return models end}
local islandsDouble = {FindFirstChild = function(_, name)
	local pos = anchorAt[name]
	return if pos then {CFrame = CFrame.new(pos), Parent = true} else nil
end}
local gateVerdict = true
local storage = {
	AetherTrails = {Name = "AetherTrails"},
	IsleTravelGate = {Invoke = function() return gateVerdict end},
}
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "regions-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end,
		FindFirstChild = function(_, name) return if name == "Islands" then islandsDouble elseif name == "Townsfolk" then townsfolk else nil end},
	Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function(className)
		local o = {ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state end}
		function o:Destroy() self.Parent = nil end
		table.insert(serverObjects, o)
		return o
	end},
	UDim2 = roblox.UDim2, Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return 0.999 end, NextInteger = function(_, lo) return lo end} end},
	warn = function() end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local liveById = {}
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return p.root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) p.root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	if liveById[id] then services.Players.PlayerRemoving:Fire(liveById[id]) end
	liveById[id] = p
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) if liveById[p.UserId] == p then liveById[p.UserId] = nil end services.Players.PlayerRemoving:Fire(p) end
local function stored(p) leave(p); return data["p" .. p.UserId].profile end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction remote found")
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
local function at(p, role) p.root.Position = npcAt[role] + Vector3.new(2, 0, 0) end
local function prompt(action, item, pos, region)
	local base = {CFrame = CFrame.new(pos)}
	local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = action, IsleItem = item, IsleRegion = region}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q) advance(30); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local X = Data.XP_TABLE

-- Snapshot carries the regional state.
local s0 = cmd(player(7001), "state")
ok(type(s0.regionQuests) == "table" and type(s0.regionQuests.accepted) == "table" and type(s0.regionQuests.warps) == "table", "snapshot.regionQuests")
-- Every regional quest, end to end, on a fresh journal seeded to its requirements.
local function seedRequirements(pr, q)
	for _, r in ipairs(q.requires) do
		if r.kind == "contracts" then pr.questCompleted = math.max(pr.questCompleted or 0, r.count)
		elseif r.kind == "level" then pr.xp[r.skill] = math.max(pr.xp[r.skill] or 0, X[r.level])
		elseif r.kind == "quest" then pr.questsDone[r.quest] = true end
	end
	-- Region access for its gated region (regionAllowed reads levels / contracts / quests).
	local region = Data.RegionById[q.region]
	for skill, lvl in pairs(region.requires.skills or {}) do pr.xp[skill] = math.max(pr.xp[skill] or 0, X[lvl]) end
	if region.requires.quest then pr.questCompleted = math.max(pr.questCompleted or 0, region.requires.quest) end
	for _, id in ipairs(region.requires.questsDone or {}) do pr.questsDone[id] = true end
end
local completed = 0
for i, q in ipairs(RA.Quests) do
	local id = 7100 + i
	local hero = seeded(id, function(pr) seedRequirements(pr, q) end)
	-- Not accepted: Journal hand-in refused, objectives do not matter.
	ok(has(cmd(hero, "quest", q.id).message, "to take on"), q.id .. " cannot be claimed before it is accepted")
	-- Accept away from the giver: refused.
	hero.root.Position = Vector3.new(0, 5000, 0)
	ok(has(cmd(hero, "rqAccept", q.id).message, "Find"), q.id .. " accept needs the giver")
	at(hero, q.giver)
	local accepted = cmd(hero, "rqAccept", q.id)
	ok(has(accepted.message, "Quest accepted"), q.id .. " accepted: " .. tostring(accepted.message))
	ok(accepted.regionQuests.accepted[q.id] == true, q.id .. " accepted in the snapshot")
	-- Handing in too early is refused.
	local claimItem = RA.claimItems(q)[1]
	ok(has(cmd(hero, "rqClaim", claimItem).message, "still to do"), q.id .. " early hand-in refused")
	-- Talk / visit steps through their verbs.
	for _, o in ipairs(q.objectives) do
		if o.kind == "talk" then
			hero.root.Position = Vector3.new(0, 5000, 0)
			ok(has(cmd(hero, "rqTalk", o.npc).message, "Find"), q.id .. " talk needs the NPC nearby")
			at(hero, o.npc)
			ok(has(cmd(hero, "rqTalk", o.npc).message, "step complete"), q.id .. " talked to " .. o.npc)
		elseif o.kind == "visit" then
			local spotPos = Vector3.new(-2000 - i * 40, 5, 900)
			ok(has(cmd(hero, "landmark", o.landmark).message, "in person"), q.id .. " survey is prompt-only")
			hero.root.Position = spotPos
			local gated = next(Data.RegionById[q.region].requires) ~= nil
			local r = use(hero, prompt("landmark", o.landmark, spotPos, if gated then q.region else nil))
			ok(r ~= nil and has(r.message, "Surveyed"), q.id .. " surveyed " .. o.landmark)
		end
	end
	-- Rejoin mid-quest keeps acceptance and steps; then satisfy the rest in the journal.
	hero = seeded(id, function(pr)
		ok(pr.regionQuests.accepted[q.id] == true, q.id .. " acceptance saved")
		for _, o in ipairs(q.objectives) do
			if o.kind == "kills" then pr.bestiary[o.monster] = o.count
			elseif o.kind == "collect" then pr.collection[o.item] = o.count
			elseif o.kind == "have" then pr.items[o.item] = (pr.items[o.item] or 0) + o.count
			elseif o.kind == "gather" then pr.counters = pr.counters or {}; pr.counters.gathers = pr.counters.gathers or {}; pr.counters.gathers[o.region] = o.count end
		end
	end)
	at(hero, q.giver)
	local before = cmd(hero, "state")
	local coins = before.coins
	local claim = cmd(hero, "rqClaim", claimItem)
	ok(has(claim.message, "Quest complete"), q.id .. " handed in: " .. tostring(claim.message))
	ok(claim.coins >= coins + q.rewards.coins, q.id .. " pays its coins (XP level coins may add more)")
	for _, o in ipairs(q.objectives) do
		if o.kind == "have" then eq(claim.items[o.item] or 0, 0, q.id .. " consumed " .. o.item) end
	end
	if q.rewards.unlock and q.rewards.unlock.warp then ok(claim.regionQuests.warps[q.rewards.unlock.warp] == true, q.id .. " unlocks its warp") end
	ok(has(cmd(hero, "rqClaim", claimItem).message, "already complete"), q.id .. " pays once")
	local saved = stored(hero)
	ok(saved.questsDone[q.id] == true, q.id .. " completion saved")
	completed += 1
end
eq(completed, #RA.Quests, "every regional quest completes through the server verbs")
-- Unknown or tampered ids.
local tester = player(7400)
at(tester, "WarpKeeper")
ok(has(cmd(tester, "rqAccept", "NotAQuest").message, "not on offer"), "unknown quest refused")
ok(has(cmd(tester, "rqTalk", "Nobody").message, "Nobody"), "unknown folk refused")
ok(has(cmd(tester, "rqTalk", "Lamplighter").message, "Find"), "talking needs the NPC")
at(tester, "Lamplighter")
ok(has(cmd(tester, "rqTalk", "Lamplighter").message, "Nobody sent you"), "talk without a quest records nothing")
-- Requirements gate acceptance.
at(tester, "CrystalReader")
ok(has(cmd(tester, "rqAccept", "VoidglassSpire").message, "requires"), "requirements gate acceptance")
-- Migration drops unknown ids.
do
	local dirty = seeded(7401, function(pr) pr.regionQuests = {accepted = {Bogus = true, SkywayCharter = true}, talked = {Nobody = true}, visited = {Nowhere = true, Sunwheel = "yes"}, warps = {Atlantis = true, Meadow = true}} end)
	local saved = stored(dirty)
	ok(saved.regionQuests.accepted.Bogus == nil and saved.regionQuests.accepted.SkywayCharter == true, "migration keeps known acceptances")
	ok(saved.regionQuests.talked.Nobody == nil and saved.regionQuests.visited.Nowhere == nil and saved.regionQuests.visited.Sunwheel == nil, "migration drops unknown steps")
	ok(saved.regionQuests.warps.Atlantis == nil and saved.regionQuests.warps.Meadow == true, "migration keeps known warps")
end
-- Shops.
do
	local buyer = seeded(7402, function(pr) pr.coins = 100 end)
	local before = cmd(buyer, "state").items.Tonic or 0
	ok(has(cmd(buyer, "rqBuy", "SeedSeller:1").message, "Find"), "shop needs the shopkeeper")
	at(buyer, "SeedSeller")
	local bought = cmd(buyer, "rqBuy", "SeedSeller:1")
	ok(has(bought.message, "Bought"), "bought from the Seed-seller")
	eq(bought.coins, 100 - RA.FolkByRole.SeedSeller.shop[1].price, "shop takes its price")
	eq(bought.items.Tonic, before + 1, "shop gives the item")
	ok(has(cmd(buyer, "rqBuy", "SeedSeller:9").message, "isn't for sale"), "unknown offer refused")
	ok(has(cmd(buyer, "rqBuy", "SeedSeller:3").message, "coins"), "too poor for the scroll")
end
-- QC M2: bought goods never count as collection (or quest collect objectives).
do
	local star = RA.QuestById.StarChart
	local offer
	for i, o in ipairs(RA.FolkByRole.UpdraftSupplier.shop) do if o.item == "StormFeather" then offer = i end end
	local shopper = seeded(7410, function(pr) pr.coins = 100000; seedRequirements(pr, star) end)
	at(shopper, "Astronomer")
	ok(has(cmd(shopper, "rqAccept", "StarChart").message, "Quest accepted"), "StarChart accepted")
	at(shopper, "UpdraftSupplier")
	local last
	for _ = 1, 15 do last = cmd(shopper, "rqBuy", "UpdraftSupplier:" .. offer) end
	ok(has(last.message, "Bought"), "bought StormFeather x15")
	eq(last.items.StormFeather, 15, "15 StormFeather in the satchel")
	local profile = stored(shopper)
	eq(profile.collection.StormFeather or 0, 0, "bought StormFeather does not advance the collection")
	shopper = player(7410)
	local entry = cmd(shopper, "state").journal.quests[star.index]
	for j, o in ipairs(star.objectives) do
		if o.kind == "collect" then eq(entry.objectives[j][1], 0, "bought StormFeather does not advance StarChart") end
	end
	ok(not entry.ready, "StarChart not ready from shop goods")
	-- Warp scrolls from the Warp Keeper are bought too.
	at(shopper, "WarpKeeper")
	ok(has(cmd(shopper, "warpBuy", "Tempest").message, "Bought"), "scroll bought")
	eq(stored(shopper).collection[RA.WarpByRegion.Tempest.scroll] or 0, 0, "bought scroll is not a collection entry")
end
-- QC L4: a regional shop will not sell a scroll for a warp you already know.
do
	local knows = seeded(7411, function(pr) pr.coins = 5000; pr.regionQuests = {warps = {Meadow = true}} end)
	at(knows, "SeedSeller")
	local index
	for i, o in ipairs(RA.FolkByRole.SeedSeller.shop) do if o.item == "WarpScrollMeadow" then index = i end end
	local refused = cmd(knows, "rqBuy", "SeedSeller:" .. index)
	ok(has(refused.message, "already know"), "rqBuy refuses a known warp's scroll: " .. tostring(refused.message))
	eq(refused.coins, 5000, "no coins taken for a known warp")
	eq(refused.items.WarpScrollMeadow or 0, 0, "no scroll given for a known warp")
	local fresh = seeded(7412, function(pr) pr.coins = 5000 end)
	at(fresh, "SeedSeller")
	ok(has(cmd(fresh, "rqBuy", "SeedSeller:" .. index).message, "Bought"), "an unknown warp's scroll still sells")
end
-- QC L6: regional kill / collect / gather objectives count since acceptance (rejoin-safe).
do
	local q = RA.QuestById.BoarsInTheBarley
	local vet = seeded(7413, function(pr) seedRequirements(pr, q); pr.bestiary.BramblebackBoar = 500 end)
	at(vet, q.giver)
	ok(has(cmd(vet, "rqAccept", q.id).message, "Quest accepted"), "veteran accepts " .. q.id)
	local entry = cmd(vet, "state").journal.quests[q.index]
	eq(entry.objectives[1][1], 0, "500 lifetime boar kills do not pre-complete the quest")
	vet = seeded(7413, function(pr)
		eq(pr.regionQuests.base[q.id][1], 500, "baseline saved with the profile")
		pr.bestiary.BramblebackBoar = 505
	end)
	entry = cmd(vet, "state").journal.quests[q.index]
	eq(entry.objectives[1][1], 5, "kills after acceptance count across a rejoin")
	vet = seeded(7413, function(pr) pr.bestiary.BramblebackBoar = 512; pr.items.BeastHide = 3 end)
	at(vet, q.giver)
	ok(has(cmd(vet, "rqClaim", q.id).message, "Quest complete"), "handed in after 12 kills since acceptance")
	eq(stored(vet).regionQuests.base[q.id], nil, "baseline cleared on completion")
	-- Journal (non-regional) quests keep lifetime totals.
	local journalQuest
	for _, jq in ipairs(Data.Quests) do
		if not jq.regional then for _, o in ipairs(jq.objectives) do if o.kind == "kills" and not journalQuest then journalQuest = jq end end end
	end
	ok(journalQuest ~= nil, "a Journal quest with a kills objective exists")
	if journalQuest then
		local lifer = seeded(7414, function(pr)
			for _, o in ipairs(journalQuest.objectives) do if o.kind == "kills" then pr.bestiary[o.monster] = o.count end end
		end)
		local je = cmd(lifer, "state").journal.quests[journalQuest.index]
		for j, o in ipairs(journalQuest.objectives) do
			if o.kind == "kills" then eq(je.objectives[j][1], o.count, journalQuest.id .. " still counts lifetime kills") end
		end
	end
end
-- Warp scrolls: buy -> learn -> warp, with refusals.
do
	local w = RA.WarpByRegion.Quarry
	local traveller = seeded(7403, function(pr) pr.coins = 1000 end)
	ok(has(cmd(traveller, "warpBuy", "Quarry").message, "Find"), "warp keeper must be near")
	at(traveller, "WarpKeeper")
	ok(has(cmd(traveller, "warpTo", "Quarry").message, "haven't learned"), "unknown warp refused")
	ok(has(cmd(traveller, "warpLearn", "Quarry").message, "You have no"), "learning needs the scroll")
	local bought = cmd(traveller, "warpBuy", "Quarry")
	ok(has(bought.message, "Bought"), "scroll bought")
	eq(bought.coins, 1000 - w.price, "scroll price")
	eq(bought.items[w.scroll], 1, "scroll in the satchel")
	local learned = cmd(traveller, "warpLearn", "Quarry")
	ok(has(learned.message, "Warp learned"), "scroll read")
	eq(learned.items[w.scroll] or 0, 0, "scroll consumed")
	ok(learned.regionQuests.warps.Quarry == true, "warp known in the snapshot")
	ok(has(cmd(traveller, "warpBuy", "Quarry").message, "already know"), "no second scroll for a known warp")
	gateVerdict = "You can't travel mid-fight."
	ok(has(cmd(traveller, "warpTo", "Quarry").message, "mid-fight"), "travel gate respected")
	gateVerdict = true
	local went = cmd(traveller, "warpTo", "Quarry")
	ok(has(went.message, "Warped"), "warped: " .. tostring(went.message))
	ok((traveller.root.Position - (anchorAt["Anchor_" .. w.anchor] + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "lands on the region's entrance anchor")
	ok(traveller.attrs.FastTravelAt ~= nil, "marked as known fast travel")
	at(traveller, "WarpKeeper")
	ok(has(cmd(traveller, "warpTo", "Quarry").message, "settling"), "warp cooldown")
	-- QC L5: leaving and rejoining does not skip an unexpired cooldown.
	leave(traveller)
	traveller = player(7403)
	at(traveller, "WarpKeeper")
	ok(has(cmd(traveller, "warpTo", "Quarry").message, "settling"), "warp cooldown survives a quick rejoin")
	at(traveller, "WarpKeeper")
	advance(RA.WARP_COOLDOWN)
	ok(has(cmd(traveller, "warpTo", "Quarry").message, "Warped"), "warp again after the cooldown")
	-- Region gate: a known warp into a locked region is refused.
	local locked = seeded(7404, function(pr) pr.regionQuests = {warps = {Gloomhollow = true}} end)
	at(locked, "WarpKeeper")
	local denied = cmd(locked, "warpTo", "Gloomhollow")
	ok(has(denied.message, "requires") or has(denied.message, "Mining"), "locked region refused: " .. tostring(denied.message))
	-- Learned warps survive a rejoin.
	ok(stored(traveller).regionQuests.warps.Quarry == true, "warp saved")
end
print("PASS: " .. (checks - partD) .. " server assertions (" .. completed .. " quests completed through server verbs).")
print("World Art & Regions QA passed " .. checks .. " checks.")
print("SUITE-END verify-regions.luau")

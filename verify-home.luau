-- Home islands (§27): big private islands, expansion rings, placement bounds,
-- legacy decoration migration, part/light budgets and the home grid.
-- Part A checks shared/GameData.lua (Data.Home, Data.Island) pure rules.
-- Part B runs world.server.lua with real Roblox instances (budgets, layout,
-- expansion in place, no overlap between homes or with static islands).
-- Part C runs server.server.lua (DataStore doubles) and plays the purchase,
-- its validation, persistence, staged placement bounds and save migration.
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
local H, I = Data.Home, Data.Island
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
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
eq(H.MAX_LEVEL, 5, "Homestead levels 1-5 (base island + four expansion rings)")
ok(H.radius(1) >= 80, "base build radius >= 80 studs")
ok(H.area(1) >= math.pi * 80 * 80 - 1, "base build area >= target (" .. math.floor(H.area(1)) .. " sq studs)")
ok(H.area(1) >= 18 * (math.pi * 18.5 ^ 2), "base island is over 18x the legacy build area")
for level = 2, H.MAX_LEVEL do
	local gain = H.area(level) / H.area(level - 1) - 1
	ok(gain >= 0.24 and gain <= 0.31, "ring " .. (level - 1) .. " adds ~25-30% area (" .. string.format("%.1f%%", gain * 100) .. ")")
	local ring = H.Stages[level]
	ok(ring.coins > 0 and ring.carpentry >= 1, "ring " .. (level - 1) .. " has a coin cost and Carpentry gate")
	for material, n in pairs(ring.costs) do ok(Data.Items[material] ~= nil and n > 0, "ring " .. (level - 1) .. " material " .. material) end
	if level > 2 then
		ok(ring.coins > H.Stages[level - 1].coins and ring.carpentry > H.Stages[level - 1].carpentry, "ring " .. (level - 1) .. " costs more than the last")
	end
end
eq(I.RANGE * I.CELL, H.radius(H.MAX_LEVEL), "grid RANGE covers the largest stage")
eq(I.RADIUS, H.radius(1), "Island.RADIUS is the stage-0 radius")
eq(I.cap(0), 120, "stage-0 cap keeps the legacy 120")
eq(I.cap(4), I.MAX_PLACEMENTS, "full expansion reaches the absolute cap")
for stage = 0, 4 do ok(I.radius(stage) == H.radius(stage + 1), "Island.radius(" .. stage .. ") follows Data.Home") end
eq(H.level("junk"), 1, "junk level is 1")
eq(H.level(99), H.MAX_LEVEL, "level clamped to the top")
eq(I.stage(-3), 0, "stage clamped at 0")
-- canExpand: every gate, in order.
local ring1 = H.Stages[2]
local function rich() local t = {} for m, n in pairs(ring1.costs) do t[m] = n end return t end
ok(select(1, H.canExpand(1, ring1.carpentry, ring1.coins, rich())) == true, "funded ring 1 allowed")
ok(has(select(2, H.canExpand(1, ring1.carpentry - 1, ring1.coins, rich())), "Carpentry"), "Carpentry gate")
ok(has(select(2, H.canExpand(1, ring1.carpentry, ring1.coins - 1, rich())), "coins"), "coin gate")
ok(has(select(2, H.canExpand(1, ring1.carpentry, ring1.coins, {})), "needs"), "material gate")
ok(has(select(2, H.canExpand(H.MAX_LEVEL, 99, 1e9, {})), "fully expanded"), "no ring past the top")
ok(has(H.costText(1), "coins") and H.costText(H.MAX_LEVEL) == "Fully expanded", "cost text")
-- Placement bounds per stage: a cell just inside each stage's rim is valid at
-- that stage and off the island one stage earlier.
for stage = 1, 4 do
	local r = I.radius(stage)
	local x = math.floor((r - I.CELL / 2) / I.CELL)
	while (math.abs(x * I.CELL) + I.CELL / 2) ^ 2 + (I.CELL / 2) ^ 2 > r * r do x -= 1 end
	eq(I.cellBlocked(x, 0, stage), nil, "rim cell " .. x .. " valid at stage " .. stage)
	eq(I.cellBlocked(x, 0, stage - 1), "edge", "rim cell " .. x .. " off the island at stage " .. (stage - 1))
end
-- Every legacy-valid cell (r18.5 grid, legacy zones) stays valid at stage 0,
-- so old saves keep every decoration at offset (0, 0).
local NEW_ZONES = {["terrace path"] = true, ["lookout path"] = true}
local function legacyBlocked(x, z)
	if math.abs(x) > I.LEGACY_RANGE or math.abs(z) > I.LEGACY_RANGE then return true end
	local cx, cz = x * I.CELL, z * I.CELL
	local fx, fz = math.abs(cx) + I.CELL / 2, math.abs(cz) + I.CELL / 2
	if fx * fx + fz * fz > I.LEGACY_RADIUS ^ 2 then return true end
	local e = I.CELL / 2 - I.BRUSH
	for _, r in ipairs(I.Protected) do
		if not NEW_ZONES[r.name] and cx + e > r.x1 and cx - e < r.x2 and cz + e > r.z1 and cz - e < r.z2 then return true end
	end
	return false
end
local legacyCells, stillFree = {}, 0
for z = -I.LEGACY_RANGE, I.LEGACY_RANGE do
	for x = -I.LEGACY_RANGE, I.LEGACY_RANGE do
		if not legacyBlocked(x, z) then
			table.insert(legacyCells, {x, z})
			if I.cellBlocked(x, z, 0) == nil then stillFree += 1 end
		end
	end
end
ok(#legacyCells >= 120, "legacy grid had " .. #legacyCells .. " cells")
eq(stillFree, #legacyCells, "every legacy-valid cell is still buildable at stage 0")
-- Stage-0 grid area.
local free = 0
for z = -I.RANGE, I.RANGE do for x = -I.RANGE, I.RANGE do if I.cellBlocked(x, z, 0) == nil then free += 1 end end end
ok(free * I.CELL * I.CELL >= 0.8 * H.area(1), "stage-0 free cells cover >= 80% of the build disc (" .. free .. " cells)")
ok(free * I.CELL * I.CELL >= 160 * 160 * 0.8, "stage-0 usable area is roughly 160 x 160 studs (" .. free * 4 .. " sq studs)")
print("Stage-0 usable build area: " .. free * 4 .. " sq studs (" .. free .. " cells); legacy: " .. #legacyCells * 4 .. " sq studs.")
-- Migration of a full legacy save: nothing moves, nothing is lost.
local legacy = {}
for i = 1, 120 do
	local c = legacyCells[i]
	legacy[i] = I.record({id = i, prop = if i % 2 == 0 then "StonePath" else "Boardwalk", x = c[1], z = c[2], rot = i % 4})
end
local migrated, refunds, report = I.migrate({placed = legacy, paid = {}}, 0)
eq(#migrated.placed, 120, "legacy full island migrates every decoration")
eq(report.kept, 120, "legacy decorations keep their cell (offset 0,0)")
eq(report.moved + report.refunded, 0, "nothing moved or refunded")
eq(next(refunds), nil, "no refunds")
eq(migrated.v, I.VERSION, "migrated save is versioned")
for i = 1, 120 do eq(migrated.placed[i], legacy[i], "legacy record " .. i .. " unchanged") end
-- Clashing records move, never vanish; extras over the caps are refunded.
local clash = {"1:StonePath:0:10:0", "2:StonePath:0:10:0", "2:Boardwalk:3:-6:0", "3:StonePath:0:1:0", "4:GardenGazebo:44:0:0",
	"5:CarpenterStump:9:9:0", "6:CarpenterStump:-9:9:0", "junk", "7:Nope:1:1:0"}
local m2, r2, rep2 = I.migrate({placed = clash, v = I.VERSION}, 0)
eq(#m2.placed, 6, "clashing records relocate")
eq(rep2.moved, 4, "overlap, duplicate id, protected landing and off-rim gazebo move")
eq(rep2.refunded, 1, "second stump (over max) refunded")
eq(r2.Timber, I.Props.CarpenterStump.costs.Timber, "refund is the full material cost")
local occ, ids = {}, {}
for _, rec in ipairs(m2.placed) do
	local e = I.parseRecord(rec)
	ok(e and not ids[e.id], "unique id after migration")
	ids[e.id] = true
	ok(I.check(occ, e.prop, e.x, e.z, e.rot, 0), rec .. " is valid where it landed")
	for _, c in ipairs(I.cells(e.prop, e.x, e.z, e.rot)) do occ[I.key(c[1], c[2])] = e.id end
end
-- A gazebo hanging off the rim at stage 0 is pulled inward.
local m3 = I.migrate({placed = {"1:GardenGazebo:45:0:0"}, v = I.VERSION}, 0)
eq(#m3.placed, 1, "off-rim decoration relocated inward, not deleted")
local over = {}
for i = 1, 150 do over[i] = I.record({id = i, prop = "StonePath", x = (i % 30) - 15, z = 20 + i // 30, rot = 0}) end
local m4, r4 = I.migrate({placed = over, v = I.VERSION}, 0)
ok(#m4.placed == I.Props.StonePath.max and r4.Ore == (150 - I.Props.StonePath.max) * I.Props.StonePath.costs.Ore, "per-prop max refunds the extras in full")
-- §27 part budget: every prop declares its parts; migration refunds records past the budget in save order.
ok(I.PART_BUDGET == 600, "placement part budget is 600 parts per home")
for id, def in pairs(I.Props) do ok(type(def.parts) == "number" and def.parts >= 1 and def.parts <= 12, id .. " declares its part count") end
do
	local freeCells = {}
	for z = -20, 20 do for x = -20, 20 do if I.cellBlocked(x, z, 0) == nil then table.insert(freeCells, {x, z}) end end end
	local heavy = {}
	for i = 1, 60 do heavy[i] = I.record({id = i, prop = "Boardwalk", x = freeCells[i][1], z = freeCells[i][2], rot = 0}) end
	for i = 61, 120 do heavy[i] = I.record({id = i, prop = "PicketFence", x = freeCells[i][1], z = freeCells[i][2], rot = 0}) end
	local mb, rb, repb = I.migrate({placed = heavy, v = I.VERSION}, 0)
	local kept = {}
	for _, rec in ipairs(mb.placed) do table.insert(kept, I.parseRecord(rec)) end
	eq(I.parts(kept), I.PART_BUDGET, "migration keeps records up to the part budget")
	eq(#mb.placed, 100, "60 boardwalks + 40 picket fences fit 600 parts")
	eq(repb.refunded, 20, "records past the budget are refunded, never deleted")
	eq(rb.Timber, 60 * 0 + 20 * I.Props.PicketFence.costs.Timber, "refund is the full cost of the extras")
	eq(mb.placed[100], heavy[100], "earlier records keep their cell")
end
-- L8: the homestead sign zone covers the "Make it yours" post (x -11.2 .. -10.7).
ok(I.cellBlocked(-6, 7, 0) == "homestead sign" and I.cellBlocked(-5, 7, 0) ~= nil, "homestead sign zone reaches x -12")
-- Home grid: allocator spacing.
local foot = H.footprint()
ok(foot >= H.meadow(H.MAX_LEVEL), "footprint covers the largest meadow")
ok(H.PITCH >= 2 * foot + 20, "PITCH clears two largest islands with a 20-stud gap")
local centers = {}
for slot = 1, 40 do
	local x, z = H.slotCenter(slot)
	centers[slot] = Vector3.new(x, 0, z)
	for j = 1, slot - 1 do assert((centers[j] - centers[slot]).Magnitude >= 2 * foot, "homes " .. j .. " and " .. slot .. " overlap") end
end
checks += 1
print("PASS: " .. (checks - partA) .. " home island data assertions.")

------------------------------------------------------------------------------
-- Part B: world geometry.
------------------------------------------------------------------------------
local partB = checks
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local worldPlayers = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
local dataModule = {Name = "AetherData"}
local services = {
	Players = worldPlayers,
	Lighting = roblox.Instance.new("Lighting"),
	CollectionService = {AddTag = function() end},
	ReplicatedStorage = {WaitForChild = function(_, name) return if name == "AetherData" then dataModule else nil end},
	ServerStorage = {FindFirstChild = function() return nil end},
}
local world = roblox.Instance.new("Workspace")
local worldLoops, worldWaits = {}, {}
local environment = {
	game = {GetService = function(_, name) return services[name] end},
	workspace = world, Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame,
	Color3 = roblox.Color3, UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum,
	task = {spawn = function(fn, ...) local co = coroutine.create(fn); coroutine.resume(co, ...); table.insert(worldLoops, co); return co end,
		wait = function(t) worldWaits[coroutine.running()] = t; return coroutine.yield() end},
	NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local source = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
luau.load(source, {environment = environment, injectGlobals = true})()
local archipelago = world:FindFirstChild("AetherIsles")
local function homeOwner(id, attributes)
	local changed = {}
	local p = {UserId = id, CharacterAdded = signal(), attributes = attributes or {}}
	function p:GetAttribute(key) return self.attributes[key] end
	function p:GetAttributeChangedSignal(key) changed[key] = changed[key] or signal() return changed[key] end
	function p:SetAttribute(key, value) self.attributes[key] = value; self:GetAttributeChangedSignal(key):Fire() end
	worldPlayers.PlayerAdded:Fire(p)
	return p
end
local function count(root)
	local parts, lights = 0, 0
	for _, obj in root:GetDescendants() do
		if obj:IsA("BasePart") then parts += 1 elseif obj:IsA("Light") then lights += 1 end
	end
	return parts, lights
end
local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
local fresh = homeOwner(61)
local home = archipelago:FindFirstChild("WayfarersRest_61")
ok(home ~= nil, "home island built")
local center = home:GetAttribute("IslandCenter")
local cx, cz = H.slotCenter(home:GetAttribute("HomeSlot"))
ok(center.X == cx and center.Z == cz, "home sits on its grid slot")
eq(home:GetAttribute("HomesteadLevel"), 1, "fresh home at level 1")
local meadow = home:FindFirstChild("Meadow")
ok(math.abs(meadow.Size.Y / 2 - H.meadow(1) - .1) < 1e-3, "meadow radius = build radius + margin")
eq(home:GetAttribute("IslandRadius"), H.meadow(1), "IslandRadius attribute")
local freshParts, freshLights = count(home)
ok(freshParts <= H.PART_BUDGET, "fresh home part budget (" .. freshParts .. " <= " .. H.PART_BUDGET .. ")")
ok(freshLights <= H.LIGHT_BUDGET, "fresh home lights (" .. freshLights .. ")")
-- Edge band: every feature beyond the build radius and on the meadow.
local edge = home:FindFirstChild("Island edge")
ok(edge ~= nil, "edge band exists")
local kinds = {}
for _, f in ipairs(H.Edge) do kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
ok(kinds.beach == 1 and kinds.cliff >= 3 and kinds.pond == 1 and kinds.windpine >= 3 and kinds.ore >= 3, "beach, cliffs, pond, trees and ore rocks")
local timberPrompts, orePrompts = 0, 0
for _, obj in edge:GetDescendants() do
	ok(not (obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "gather"), "§42: no gather prompt on the edge")
	if obj:GetAttribute("GatherNode") then -- §42: struck node hosts
		eq(obj:GetAttribute("OwnerUserId"), 61, "edge node is owner-only")
		if obj:GetAttribute("GatherNode") == "Timber" then timberPrompts += 1 elseif obj:GetAttribute("GatherNode") == "Ore" then orePrompts += 1 end
	end
end
ok(timberPrompts == kinds.windpine and orePrompts == kinds.ore, "gatherable windpines and ore rocks")
local function bandCheck(level)
	local R = H.radius(level)
	for _, model in ipairs(home:FindFirstChild("Island edge"):GetChildren()) do
		if model.Name ~= "Sand beach" and not string.match(model.Name, "^Anchor_") then
			local pos = if model:IsA("BasePart") then model.CFrame.Position else nil
			if not pos then
				local sum, n = Vector3.zero, 0
				for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then sum += d.CFrame.Position; n += 1 end end
				pos = sum / n
			end
			local d = flat(pos, center)
			assert(d >= R and d <= H.meadow(level), model.Name .. " sits in the edge band at level " .. level .. " (" .. d .. ")")
		end
	end
	checks += 1
end
bandCheck(1)
-- Fixed objects of the core and add-ons stay inside the build disc and inside
-- protected zones (so no placement can sit on them).
for _, name in ipairs({"Worker Yard", "Builders Terrace", "Verdant Garden"}) do
	local m = home:FindFirstChild(name)
	ok(m ~= nil, name .. " on the home island")
end
for _, obj in home:GetDescendants() do
	if obj:IsA("BasePart") and obj.CanCollide and obj.Name ~= "Meadow" and obj.Name ~= "Floating foundation" and not obj:IsDescendantOf(edge)
		and obj.Name ~= "Home Landing" then
		local o = obj.CFrame.Position - center
		if flat(obj.CFrame.Position, center) > 21 then
			local x, z = math.floor(o.X / I.CELL + .5), math.floor(o.Z / I.CELL + .5)
			assert(I.cellBlocked(x, z, 0) ~= nil, obj:GetFullName() .. " stands on a buildable cell")
		end
	end
end
checks += 1
local stake = home:FindFirstChild("Survey stake")
local survey = stake and stake:FindFirstChildOfClass("ProximityPrompt")
ok(survey and survey:GetAttribute("IsleAction") == "homeExpand" and survey:GetAttribute("OwnerUserId") == 61, "survey stake sells the next ring")
ok(has(survey.ObjectText, "Homestead level 1") and has(survey.ObjectText, "coins"), "survey stake shows the cost")
-- Fully built home: every addition, every worker station active.
local full = {HomeGarden = true, HomeDeck = true, HomeLanterns = true, WorkerSlots = 12, HomesteadLevel = 5}
for i = 1, 12 do full["Worker" .. i .. "Tier"] = 7; full["Worker" .. i .. "Resource"] = "Ore" end
homeOwner(62, full)
local big = archipelago:FindFirstChild("WayfarersRest_62")
local fullParts, fullLights = count(big)
ok(fullParts <= H.PART_BUDGET, "fully built home part budget (" .. fullParts .. " <= " .. H.PART_BUDGET .. ")")
ok(fullLights <= H.LIGHT_BUDGET, "fully built home lights (" .. fullLights .. " <= " .. H.LIGHT_BUDGET .. ")")
ok(math.abs(big:FindFirstChild("Meadow").Size.Y / 2 - H.meadow(5) - .1) < 1e-3, "saved level restores the full island")
ok(big:FindFirstChild("Deck"):FindFirstChild("Continuous bridge deck") == nil, "the deck needs no bridge on the big island")
-- Expansion in place: same part count, bigger meadow, the band moves out.
for level = 2, H.MAX_LEVEL do
	fresh:SetAttribute("HomesteadLevel", level)
	eq(home:GetAttribute("HomesteadLevel"), level, "home follows HomesteadLevel " .. level)
	eq(meadow.Parent, home, "meadow resized in place")
	ok(math.abs(meadow.Size.Y / 2 - H.meadow(level) - .1) < 1e-3, "meadow grows to level " .. level)
	eq((count(home)), freshParts, "part count unchanged at level " .. level)
	local shores = 0
	for _, child in ipairs(home:GetChildren()) do if child.Name == "Anchor_Waypoint_HomeShore" then shores += 1 end end
	eq(shores, 1, "one shore anchor at level " .. level)
	bandCheck(level)
end
ok(not survey.Enabled and has(survey.ObjectText, "Fully expanded"), "survey stake closes at the top level")
-- Placements beyond the old rim render once the level allows them.
local outer = homeOwner(63, {IslandPlacements = "1:StonePath:56:0:0"})
local outerHome = archipelago:FindFirstChild("WayfarersRest_63")
ok(outerHome:FindFirstChild("Placements"):FindFirstChild("Placement_1") == nil, "an outer-ring record waits for its level")
outer:SetAttribute("HomesteadLevel", 3)
ok(outerHome:FindFirstChild("Placements"):FindFirstChild("Placement_1") ~= nil, "it renders when the ring is bought")
-- No overlap between homes or with static islands.
local homes, statics = {}, {}
for _, m in ipairs(archipelago:GetChildren()) do
	if string.match(m.Name, "^WayfarersRest_") then table.insert(homes, m) end
end
for _, root in ipairs({world:FindFirstChild("Islands"), archipelago}) do
	for _, m in ipairs(root:GetChildren()) do
		if not string.match(m.Name, "^WayfarersRest_") and m:GetAttribute("IslandCenter") and m:GetAttribute("IslandRadius") then table.insert(statics, m) end
	end
end
ok(#homes == 3 and #statics >= 10, "homes and static islands found")
for i, a in ipairs(homes) do
	for j = i + 1, #homes do
		ok(flat(a:GetAttribute("IslandCenter"), homes[j]:GetAttribute("IslandCenter")) >= 2 * foot, "homes " .. a.Name .. " and " .. homes[j].Name .. " never overlap")
	end
end
-- Every slot of a 40-player server clears every static island and the
-- dungeon (z 1690-1800) and minigame (x -2400) arenas.
for slot = 1, 40 do
	local x, z = H.slotCenter(slot)
	local c = Vector3.new(x, 0, z)
	for _, s in ipairs(statics) do
		assert(flat(c, s:GetAttribute("IslandCenter")) >= foot + s:GetAttribute("IslandRadius") + 20, "slot " .. slot .. " clears " .. s.Name)
	end
	assert(flat(c, Vector3.new(0, 0, 1800)) >= foot + 250 and flat(c, Vector3.new(-2400, 0, 0)) >= foot + 300, "slot " .. slot .. " clears the arenas")
end
checks += 1
-- §27 lazy homes: placements and terrace furniture exist only while someone is near.
do
	local loop
	for _, co in ipairs(worldLoops) do if worldWaits[co] == H.LIVE_TICK and coroutine.status(co) == "suspended" then loop = co end end
	ok(loop ~= nil, "lazy-home presence loop running")
	local function tick(dt) local okRun, err = coroutine.resume(loop, dt); assert(okRun, err) end
	local root = {Position = Vector3.zero}
	local character = {FindFirstChild = function(_, name) return if name == "HumanoidRootPart" then root else nil end}
	local lazy = homeOwner(80, {IslandPlacements = "1:StonePath:0:-30:0;2:LanternPost:2:-30:0", FurnitureBench = "SturdyWorkbench"})
	local lazyHome = archipelago:FindFirstChild("WayfarersRest_80")
	local folder, terrace = lazyHome:FindFirstChild("Placements"), lazyHome:FindFirstChild("Builders Terrace")
	local c = lazyHome:GetAttribute("IslandCenter")
	ok(lazyHome:GetAttribute("HomeLive") == true and #folder:GetChildren() == 2, "a joining owner (no character yet) gets a live home")
	ok(terrace:FindFirstChild("Furniture_Bench") ~= nil, "terrace furniture built while live")
	local liveParts = (count(lazyHome))
	lazy.Character = character
	root.Position = c + Vector3.new(0, 3, 240)
	tick(40)
	ok(lazyHome:GetAttribute("HomeLive") == true, "owner within " .. H.LIVE_RANGE .. " studs keeps it live")
	root.Position = c + Vector3.new(0, 3, 260)
	tick(H.LIVE_LINGER - 1)
	ok(lazyHome:GetAttribute("HomeLive") == true and #folder:GetChildren() == 2, "the home lingers after the owner leaves")
	tick(2)
	ok(lazyHome:GetAttribute("HomeLive") == false and #folder:GetChildren() == 0, "placements torn down " .. H.LIVE_LINGER .. " s after the last player left")
	ok(terrace:FindFirstChild("Furniture_Bench") == nil and terrace:FindFirstChild("Workshop Bench hotspot") ~= nil, "furniture torn down, hotspot plinth stays")
	ok(lazyHome:FindFirstChild("Island shell") ~= nil and lazyHome:FindFirstChild("Island edge") ~= nil and lazyHome:FindFirstChild("Meadow") ~= nil, "shell and edge stay")
	local dormantParts = (count(lazyHome))
	ok(dormantParts < liveParts, "dormant home sheds parts (" .. liveParts .. " -> " .. dormantParts .. ")")
	lazy:SetAttribute("IslandPlacements", "1:StonePath:0:-30:0")
	ok(#folder:GetChildren() == 0, "record changes while dormant build nothing")
	-- A visitor brings it back.
	local visitorRoot = {Position = c + Vector3.new(30, 3, 0)}
	local visitor = {UserId = 81, Character = {FindFirstChild = function(_, name) return if name == "HumanoidRootPart" then visitorRoot else nil end}}
	worldPlayers.GetPlayers = function() return {lazy, visitor} end
	tick(1)
	ok(lazyHome:GetAttribute("HomeLive") == true and #folder:GetChildren() == 1 and folder:FindFirstChild("Placement_1") ~= nil, "a visitor within range rebuilds the current records")
	ok(terrace:FindFirstChild("Furniture_Bench") ~= nil, "furniture rebuilt for the visitor")
	worldPlayers.GetPlayers = function() return {} end
	root.Position = c + Vector3.new(0, 3, 5)
	print(string.format("Lazy home: live %d parts, dormant %d parts.", liveParts, dormantParts))
	worldPlayers.PlayerRemoving:Fire(lazy)
end
-- Leaving frees the slot and the model.
worldPlayers.PlayerRemoving:Fire(outer)
ok(archipelago:FindFirstChild("WayfarersRest_63") == nil, "leaving removes the home")
-- Worst case for a full server (documented in §27): fixed geometry plus the
-- player-authored caps (terrace furniture, placements at the absolute cap).
local propParts = {}
do
	local maxParts = 0
	for _, id in ipairs(I.PropOrder) do
		local tester = homeOwner(70 + #propParts, {IslandPlacements = "1:" .. id .. ":0:-30:0"})
		local n = (count(archipelago:FindFirstChild("WayfarersRest_" .. tester.UserId):FindFirstChild("Placements")))
		propParts[#propParts + 1] = {id = id, n = n}
		eq(n, I.Props[id].parts, id .. " builds exactly its declared parts")
		if n > maxParts then maxParts = n end
		worldPlayers.PlayerRemoving:Fire(tester)
	end
	table.sort(propParts, function(a, b) return a.n > b.n end)
	local worst, left = 0, I.MAX_PLACEMENTS
	for _, e in ipairs(propParts) do
		local take = math.min(left, I.Props[e.id].max)
		worst += take * e.n
		left -= take
	end
	local furniture = #Data.Hotspots * 16
	local before = H.PART_BUDGET + furniture + worst
	local perHome = H.PART_BUDGET + furniture + math.min(worst, I.PART_BUDGET)
	ok(maxParts <= 12 and worst <= 2000, "placement worst case without a budget (" .. worst .. " parts)")
	ok(perHome <= 1000, "budgeted live home stays under 1,000 parts (" .. perHome .. ")")
	print(string.format("Home worst case: fixed %d + furniture %d + placements %d (was %d) = %d parts/live home (was %d); 40 homes: %d parts if all are live (was %d), %d when dormant (shells only).",
		H.PART_BUDGET, furniture, math.min(worst, I.PART_BUDGET), worst, perHome, before, perHome * 40, before * 40, H.PART_BUDGET * 40))
	print(string.format("Measured: fresh home %d parts / %d lights, fully built %d parts / %d lights.", freshParts, freshLights, fullParts, fullLights))
end
print("PASS: " .. (checks - partB) .. " home island world assertions.")

------------------------------------------------------------------------------
-- Part C: server behaviour.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, val in value do out[k] = copy(val) end
	return out
end
local clock, utc = 10, 1500000000
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
local serverServices = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "home-test" end},
	RunService = {IsStudio = function() return false end},
}
local coroutines, yieldOf = {}, {}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return serverServices[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end}, Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state end}
		table.insert(serverObjects, o)
		return o
	end},
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return 0.999 end, NextInteger = function(_, a) return a end} end},
	task = {
		spawn = function(f, ...)
			local co = coroutine.create(f)
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			if coroutine.status(co) == "suspended" then table.insert(coroutines, co) end
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) yieldOf[coroutine.running()] = t return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local autosave
for _, co in ipairs(coroutines) do if yieldOf[co] == 55 then autosave = co end end
ok(autosave ~= nil, "autosave loop found")
local function renew() local okR, errR = coroutine.resume(autosave, 55) assert(okR, tostring(errR)) end
local function player(id)
	local root = {Position = Vector3.zero, Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	serverServices.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) p.Parent = nil; serverServices.Players.PlayerRemoving:Fire(p) end
local function saved(p) return data["p" .. p.UserId].profile end
local function rejoin(p, mutate)
	leave(p)
	if mutate then mutate(saved(p)) end
	return player(p.UserId)
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction RemoteFunction found")
local function cmd(p, verb, item)
	clock += 1; utc += 1
	renew()
	return remote.OnServerInvoke(p, verb, item)
end
local function homestead(s) return s.journal.construction.island.homestead end
local function setCarpentry(prof, lvl) prof.xp.Carpentry = P.xpForLevel(lvl); prof.levelRewards = prof.levelRewards or {}; prof.levelRewards.Carpentry = lvl end

-- C1: fresh profile, level 1, attribute published, gates.
local a = player(9101)
local s = cmd(a, "state")
eq(homestead(s).level, 1, "fresh Homestead level 1")
eq(a.attrs.HomesteadLevel, 1, "HomesteadLevel attribute published")
eq(homestead(s).radius, H.radius(1), "snapshot radius")
eq(homestead(s).next.coins, H.Stages[2].coins, "snapshot names the next ring cost")
eq(s.journal.construction.island.cap, I.cap(0), "snapshot cap at stage 0")
ok(has(cmd(a, "homeExpand").message, "Carpentry"), "Carpentry gate refuses")
a = rejoin(a, function(prof) setCarpentry(prof, 60) end)
local before = cmd(a, "state")
ok(has(cmd(a, "homeExpand").message, "coins"), "coin gate refuses")
a = rejoin(a, function(prof) prof.coins = 1e6 end)
local m = cmd(a, "homeExpand")
ok(has(m.message, "needs"), "material gate refuses")
eq(homestead(m).level, 1, "refusals change nothing")
eq(m.coins, 1e6, "refusals spend nothing")
-- A ring outside the current radius is refused before the purchase.
a = rejoin(a, function(prof)
	prof.items = prof.items or {}
	for level = 2, H.MAX_LEVEL do for mat, n in pairs(H.Stages[level].costs) do prof.items[mat] = (prof.items[mat] or 0) + n end end
	prof.items.Ore = (prof.items.Ore or 0) + 30
end)
ok(has(cmd(a, "place", "StonePath:46:0:0").message, "fully on your island"), "cell 46 (r~93) is off the stage-0 island")
-- C2: purchase.
m = cmd(a, "homeExpand")
ok(has(m.message, "Homestead level 2") and has(m.message, "%"), "ring 1 bought: " .. tostring(m.message))
eq(homestead(m).level, 2, "level 2")
eq(m.coins, 1e6 - H.Stages[2].coins, "ring coins spent")
eq(a.attrs.HomesteadLevel, 2, "attribute follows the purchase")
eq(m.journal.construction.island.cap, I.cap(1), "cap grows with the ring")
local placed = cmd(a, "place", "StonePath:46:0:0")
eq(placed.journal.construction.island.count, 1, "the new ring is buildable")
-- C3: persistence and the rest of the rings.
a = rejoin(a)
s = cmd(a, "state")
eq(homestead(s).level, 2, "level persists across rejoin")
eq(saved(a).homestead.level, 2, "profile stores p.homestead.level")
eq(s.journal.construction.island.count, 1, "outer-ring placement persists")
for level = 3, H.MAX_LEVEL do eq(homestead(cmd(a, "homeExpand")).level, level, "ring to level " .. level) end
ok(has(cmd(a, "homeExpand").message, "fully expanded"), "no purchase past the top")
eq(homestead(cmd(a, "state")).next, nil, "no next ring at the top")
-- C4: legacy save migration through the server (no version, old core cells).
local legacyRecords = {}
for i = 1, 30 do local c = legacyCells[i] legacyRecords[i] = I.record({id = i, prop = "Boardwalk", x = c[1], z = c[2], rot = 0}) end
local b = player(9102)
b = rejoin(b, function(prof) prof.island = {placed = legacyRecords, paid = {Boardwalk = 30}}; prof.homestead = nil end)
s = cmd(b, "state")
eq(s.journal.construction.island.count, 30, "legacy decorations all load")
eq(b.attrs.IslandPlacements, table.concat(legacyRecords, ";"), "legacy records unchanged (offset 0,0)")
leave(b)
eq(saved(b).island.v, I.VERSION, "migrated save written with its version")
-- C5: tampered Homestead level is clamped.
local c = player(9103)
c = rejoin(c, function(prof) prof.homestead = {level = 99} end)
eq(homestead(cmd(c, "state")).level, H.MAX_LEVEL, "tampered level clamped")
c = rejoin(c, function(prof) prof.homestead = "x" end)
eq(homestead(cmd(c, "state")).level, 1, "junk homestead reset")
-- C6: the place verb enforces the per-home part budget; migration on load refunds extras.
do
	local free = {}
	for z = -20, 20 do for x = -20, 20 do if I.cellBlocked(x, z, 0) == nil then table.insert(free, {x, z}) end end end
	local recs = {}
	for i = 1, 60 do recs[i] = I.record({id = i, prop = "Boardwalk", x = free[i][1], z = free[i][2], rot = 0}) end
	for i = 61, 99 do recs[i] = I.record({id = i, prop = "PicketFence", x = free[i][1], z = free[i][2], rot = 0}) end -- 594 parts
	local d = player(9104)
	d = rejoin(d, function(prof)
		setCarpentry(prof, 60)
		prof.items = {Timber = 500, Ore = 500}
		prof.island = {placed = recs, paid = {}, v = I.VERSION}
	end)
	local st = cmd(d, "state").journal.construction.island
	eq(st.parts, 594, "snapshot reports placement parts")
	eq(st.partBudget, I.PART_BUDGET, "snapshot reports the part budget")
	local occ = I.occupancy(I.decode(table.concat(recs, ";")))
	local wx, wz
	for z = 30, 40 do for x = -10, 10 do if not wx and I.check(occ, "StoneWell", x, z, 0, 0) then wx, wz = x, z end end end
	local refused = cmd(d, "place", "StoneWell:" .. wx .. ":" .. wz .. ":0") -- 594 + 9 > 600
	ok(has(refused.message, "detail budget"), "a prop past the part budget is refused: " .. tostring(refused.message))
	eq(refused.journal.construction.island.count, 99, "refusal places nothing")
	local fits = cmd(d, "place", "StonePath:" .. free[151][1] .. ":" .. free[151][2] .. ":0")
	eq(fits.journal.construction.island.parts, 597, "a light prop still fits under the budget")
	-- Over-budget save (e.g. from before the budget): extras refunded on load, never deleted.
	d = rejoin(d, function(prof)
		for i = 100, 110 do table.insert(prof.island.placed, I.record({id = i, prop = "PicketFence", x = free[i + 60][1], z = free[i + 60][2], rot = 0})) end
		prof.items = {}
	end)
	st = cmd(d, "state").journal.construction.island
	ok(st.parts <= I.PART_BUDGET and st.count == 100, "over-budget save trimmed to the budget on load (" .. st.parts .. " parts)")
	eq(saved(d).items.Timber, 11 * I.Props.PicketFence.costs.Timber, "extras refunded in full")
end
print("PASS: " .. (checks - partC) .. " home island server assertions.")
print("Home islands QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-home.luau")

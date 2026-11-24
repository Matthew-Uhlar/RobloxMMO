-- World Art pass 2 (docs/DEPTH-CONTRACT.md §40): the building kit and the
-- settlements. Builds the production world headlessly (tools/world-harness.luau)
-- and checks every building: kit / mesh / collider agreement, walkable doors
-- and interiors, nothing blocked (prompts, anchors, paths, bridges), no
-- overlaps, the part budget, forge template budgets and window glow sites.
-- Run from the project root: lune run verify-buildings.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local W = require("./tools/world-harness")

local checks = 0
local function ok(condition, label)
	checks += 1
	if not condition then error("FAILED: " .. label, 2) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function nearV(a, b, eps) return near(a.X, b.X, eps) and near(a.Y, b.Y, eps) and near(a.Z, b.Z, eps) end

local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local source = fs.readFile("world.server.lua")
-- The generated kit table in world.server.lua is the same data as the catalog meta.
local kitSource = string.match(source, "%-%- BEGIN GENERATED BUILDINGS[^\n]*\n(.-)\n%-%- END GENERATED BUILDINGS")
ok(kitSource ~= nil, "world.server.lua carries the generated building kit")
local KIT = luau.load(kitSource .. "\nreturn BUILDING_KIT")()

------------------------------------------------------------------------------
-- Kit and catalog
------------------------------------------------------------------------------
local kinds = {facade = 0, walkin = 0, interior = 0}
local kitTriangles = 0
for name, def in KIT do
	local data = World.shapes[name]
	ok(data ~= nil, name .. " is a catalog shape")
	ok(data.kind == "building", name .. " has kind building")
	kinds[def.kind] += 1
	kitTriangles += #data.faces
	ok(#data.faces <= 2400, name .. " stays within the 2400-triangle building budget (" .. #data.faces .. ")")
	-- Fit box = the mesh bounds (ShapeBox = fit size maps the mesh 1:1).
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, v in data.vertices do local p = Vector3.new(v[1], v[2], v[3]); lo, hi = lo:Min(p), hi:Max(p) end
	ok(nearV(lo, Vector3.new(table.unpack(def.fit[1])), .002) and nearV(hi, Vector3.new(table.unpack(def.fit[2])), .002), name .. " fit box = mesh bounds")
	ok(def.fit[1][2] >= -.05, name .. " stands on the ground (no geometry below y 0)")
	if def.kind ~= "interior" then
		ok(#def.windows >= 4, name .. " has glazed windows (" .. #def.windows .. ")")
		ok(def.door ~= nil and def.door.w >= 2 and def.door.h >= 3.8, name .. " has a door")
		-- Every door is on the street (-Z) face; every window on an outer face.
		ok(near(def.door.ry, 0) and def.door.z <= -def.d / 2 + .01, name .. " door faces the street")
		ok(def.fit[1][1] <= -def.w / 2 and def.fit[2][1] >= def.w / 2 and def.fit[1][3] <= -def.d / 2 and def.fit[2][3] >= def.d / 2, name .. " mesh covers its walls")
	end
	for i, w in def.windows do
		ok(#w == 6 and w[4] > .3 and w[5] > .3, name .. " window " .. i .. " is a pane rect")
		local out = Vector3.new(-math.sin(w[6]), 0, -math.cos(w[6]))
		local p = Vector3.new(w[1], w[2], w[3])
		-- The pane sits on (just outside) an outer wall plane, facing out.
		local reach = math.abs(p.X * out.X + p.Z * out.Z)
		local half = math.abs(out.X) * def.w / 2 + math.abs(out.Z) * def.d / 2
		ok(reach >= half - (def.t or 0) - .05 or w[2] > def.h, name .. " window " .. i .. " is on an outer face (or a dormer / gable above the eaves)")
		ok(w[2] > 1 and w[2] < def.fit[2][2], name .. " window " .. i .. " height")
	end
	if def.kind == "walkin" then
		ok(def.t > .4 and def.floor > .1 and def.floor < .6, name .. " wall thickness and floor step")
		ok(def.opening.w >= 3.6 and def.opening.h >= 6.5, name .. " door opening fits a player (" .. def.opening.w .. " x " .. def.opening.h .. ")")
		ok(near(def.door.w, def.opening.w) and near(def.door.h, def.opening.h), name .. " mesh doorway = collider opening")
	end
	if def.counter then
		local c, s = def.counter.c, def.counter.s
		ok(c[2] - s[2] / 2 >= .3, name .. " counter stands on the hall floor")
	end
end
ok(kinds.facade >= 6 and kinds.walkin >= 2 and kinds.interior >= 4, string.format("kit: %d facades, %d walk-in halls, %d interiors", kinds.facade, kinds.walkin, kinds.interior))
-- Interiors fit inside the hall they furnish.
for _, pair in {{"BankInterior", "ShopHall"}, {"ShopInterior", "ShopHall"}, {"TavernInterior", "TavernHall"}} do
	local i, h = KIT[pair[1]], KIT[pair[2]]
	ok(i.fit[1][1] >= -h.w / 2 + h.t - .01 and i.fit[2][1] <= h.w / 2 - h.t + .01 and i.fit[1][3] >= -h.d / 2 + h.t - .01 and i.fit[2][3] <= h.d / 2 - h.t + .01,
		pair[1] .. " fits inside " .. pair[2] .. "'s walls")
	ok(i.fit[2][2] < h.h + 4, pair[1] .. " hangs below " .. pair[2] .. "'s roof")
	-- The counter leaves the doorway and three studs inside it free.
	local c, s = i.counter.c, i.counter.s
	local clearX, inner = h.opening.w / 2 + 1, -h.d / 2 + h.t
	local overlapsDoor = math.abs(c[1]) - s[1] / 2 < clearX and c[3] - s[3] / 2 < inner + 3
	ok(not overlapsDoor, pair[1] .. " counter leaves room inside the door")
end

------------------------------------------------------------------------------
-- The built world
------------------------------------------------------------------------------
local b = W.build()
local world, islands = b.world, b.islands
local staticParts = 0
for _, obj in world:GetDescendants() do if obj:IsA("BasePart") then staticParts += 1 end end
ok(staticParts <= 4000, "static world within the 4000-part budget (" .. staticParts .. ")")

local hosts, perIsle, buildingParts = {}, {}, 0
for _, obj in islands:GetDescendants() do
	if obj:IsA("BasePart") and obj:GetAttribute("BuildingType") then table.insert(hosts, obj) end
end
local function isleOf(obj)
	local node = obj
	while node.Parent and node.Parent ~= islands do node = node.Parent end
	return node
end
local function boxOf(p)
	local cf, s = p.CFrame, p.Size / 2
	local function ext(axis) return math.abs(cf.RightVector[axis]) * s.X + math.abs(cf.UpVector[axis]) * s.Y + math.abs(cf.LookVector[axis]) * s.Z end
	local c = cf.Position
	return c - Vector3.new(ext("X"), ext("Y"), ext("Z")), c + Vector3.new(ext("X"), ext("Y"), ext("Z"))
end
-- Oriented box (cf, half sizes) against an axis-aligned box: separating axes
-- X, Y, Z and the box's own three axes (edge-cross axes are not needed for
-- the upright boxes the world uses).
local function obbHitsAabb(cf, h, lo, hi, pad)
	pad = pad or 0
	local c, eh = (lo + hi) / 2 - cf.Position, (hi - lo) / 2
	local axes = {Vector3.xAxis, Vector3.yAxis, Vector3.zAxis, cf.RightVector, cf.UpVector, cf.LookVector}
	for _, a in axes do
		local rb = math.abs(cf.RightVector:Dot(a)) * h.X + math.abs(cf.UpVector:Dot(a)) * h.Y + math.abs(cf.LookVector:Dot(a)) * h.Z
		local ra = math.abs(a.X) * eh.X + math.abs(a.Y) * eh.Y + math.abs(a.Z) * eh.Z
		if math.abs(c:Dot(a)) >= rb + ra + pad - 1e-6 then return false end
	end
	return true
end
-- Two oriented boxes: separating axes = both boxes' face axes (exact for
-- boxes upright about Y, which every building, path and anchor is).
local function obbObb(cfA, hA, cfB, hB, pad)
	pad = pad or 0
	local d = cfB.Position - cfA.Position
	local function radius(cf, h, a) return math.abs(cf.RightVector:Dot(a)) * h.X + math.abs(cf.UpVector:Dot(a)) * h.Y + math.abs(cf.LookVector:Dot(a)) * h.Z end
	for _, a in {cfA.RightVector, cfA.UpVector, cfA.LookVector, cfB.RightVector, cfB.UpVector, cfB.LookVector} do
		if math.abs(d:Dot(a)) >= radius(cfA, hA, a) + radius(cfB, hB, a) + pad - 1e-6 then return false end
	end
	return true
end
local function inside(cf, h, p, pad)
	local q = cf:PointToObjectSpace(p)
	pad = pad or 0
	return math.abs(q.X) < h.X + pad and math.abs(q.Y) < h.Y + pad and math.abs(q.Z) < h.Z + pad
end

local typeCount, glowSites, panes, walkins, interiorLights = {}, 0, 0, {}, 0
for _, host in hosts do
	local name = host:GetAttribute("BuildingType")
	local def = KIT[name]
	local model = host.Parent
	ok(def ~= nil and def.kind ~= "interior", host:GetFullName() .. " is a kit building")
	typeCount[name] = (typeCount[name] or 0) + 1
	local isle = isleOf(host)
	perIsle[isle.Name] = (perIsle[isle.Name] or 0) + 1
	ok(host:GetAttribute("Shape") == name, name .. " host is its own mesh slot")
	local lo, hi = Vector3.new(table.unpack(def.fit[1])), Vector3.new(table.unpack(def.fit[2]))
	ok(nearV(host:GetAttribute("ShapeBox"), hi - lo, .01), name .. " ShapeBox = the mesh fit box")
	-- The building's ground frame from the host (facade: centre at h/2; hall floor at floor - .25).
	local hostAt = if def.kind == "facade" then Vector3.new(0, def.h / 2, 0) else Vector3.new(0, def.floor - .25, 0)
	ok(nearV(host:GetAttribute("ShapeBoxOffset"), (lo + hi) / 2 - hostAt, .01), name .. " ShapeBoxOffset centres the mesh on the building")
	local ground = host.CFrame * CFrame.new(-hostAt)
	ok(math.abs(ground.UpVector.Y - 1) < 1e-4, name .. " stands upright")
	local IC = isle:GetAttribute("IslandCenter")
	ok(math.abs(ground.Position.Y - IC.Y) < .05, name .. " stands on its island's meadow (" .. isle.Name .. ")")
	ok(Vector3.new(ground.Position.X - IC.X, 0, ground.Position.Z - IC.Z).Magnitude < isle:GetAttribute("IslandRadius") - 4, name .. " stands inside the island rim")
	-- Night glow: a pooled §35 glow site and the lit window panes.
	ok(host:GetAttribute("GlowSite") == "window", name .. " is a window glow site")
	local list = host:GetAttribute("WindowGlow")
	local n = 0
	for entry in string.gmatch(list, "[^;]+") do
		n += 1
		local v = {}
		for x in string.gmatch(entry, "[^,]+") do table.insert(v, tonumber(x)) end
		local w = def.windows[n]
		ok(#v == 6 and near(v[1] + hostAt.X, w[1], .002) and near(v[2] + hostAt.Y, w[2], .002) and near(v[3] + hostAt.Z, w[3], .002), name .. " pane " .. n .. " matches the kit")
	end
	ok(n == #def.windows, name .. " carries every window pane")
	glowSites += 1
	panes += n
	if def.kind == "facade" then
		ok(host.Name == "Roofed house" and host.CanCollide and host.Transparency == 0, name .. " collider block is the visible fallback")
		ok(nearV(host.Size, Vector3.new(def.w, def.h, def.d), .001), name .. " collider = the kit footprint")
		for _, p in model:GetChildren() do if p:IsA("BasePart") then buildingParts += 1 end end
		-- §40 QC L6: the porch deck / door step outside the block collides.
		local ground = host.CFrame * CFrame.new(0, -def.h / 2, 0)
		local probe
		if name == "LogLodge" then probe = ground * CFrame.new(3, .35, -def.d / 2 - 1.2)
		elseif name ~= "StoneCottage" then probe = ground * CFrame.new(def.door.x, .25, def.door.z - .45) end
		if probe then
			local hit = false
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") and p:GetAttribute("FurnitureCollider") and p.CanCollide and p.Transparency == 1 and inside(p.CFrame, p.Size / 2, probe.Position) then hit = true end
			end
			ok(hit, model.Name .. " (" .. name .. ") porch / step has an invisible collider")
		end
	else
		table.insert(walkins, {host = host, def = def, ground = ground, name = name})
		ok(host.Name == "Roofed hall floor" and host:GetAttribute("ShapeOwnsModel") == true, name .. " floor hosts the hall mesh")
		local walls, counter = 0, nil
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				buildingParts += 1
				if p.Name == "Hall wall" or p.Name == "Hall lintel" then walls += 1 end
				if p:GetAttribute("Interior") then counter = p end
			end
		end
		ok(walls == 6, name .. " has six wall colliders")
		ok(counter ~= nil and counter.CanCollide and KIT[counter:GetAttribute("Interior")] ~= nil, name .. " is furnished (" .. model.Name .. ")")
		local idef = KIT[counter:GetAttribute("Interior")]
		ok(counter:GetAttribute("Shape") == counter:GetAttribute("Interior"), model.Name .. " interior mesh rides the counter")
		local ilo, ihi = Vector3.new(table.unpack(idef.fit[1])), Vector3.new(table.unpack(idef.fit[2]))
		ok(nearV(counter:GetAttribute("ShapeBox"), ihi - ilo, .01), model.Name .. " interior ShapeBox = its fit box")
		local c = Vector3.new(table.unpack(idef.counter.c))
		ok(nearV(counter.CFrame.Position, (ground * CFrame.new(c)).Position, .01), model.Name .. " counter sits where the interior mesh draws it")
		for _, d in model:GetDescendants() do if d:IsA("Light") then
			interiorLights += 1
			ok(d:GetAttribute("NightLight") == true and d:GetAttribute("LightWanted") == true and d.Shadows == false, model.Name .. " interior light is a bounded night light")
		end end
	end
end
ok(#hosts >= 50, "settlements are dense (" .. #hosts .. " buildings)")
ok((perIsle["Compass Quay"] or 0) >= 16, "Compass Quay has a dense town core (" .. (perIsle["Compass Quay"] or 0) .. ")")
for _, style in {"Mosswake Grove", "Brassfall Quarry", "Skyreach", "Tidewater Shoals", "Guild Terrace", "Warden Reach", "Tempest Spire", "Gloomhollow Caverns"} do
	ok((perIsle[style] or 0) >= 2, style .. " has a settlement (" .. (perIsle[style] or 0) .. ")")
end
ok(#walkins >= 6, "walk-in halls (" .. #walkins .. ")")
print("Halls: " .. (function() local t = {} for _, w in walkins do table.insert(t, w.host.Parent.Name) end table.sort(t) return table.concat(t, ", ") end)())

-- Walk-ins: the doorway is clear, the floor is continuous to the counter, the
-- interior is enclosed, and the hall keeps room for an NPC behind the counter.
local solids = {}
for _, obj in islands:GetDescendants() do
	if obj:IsA("BasePart") and obj.CanCollide and obj.Name ~= "Meadow" and obj.Name ~= "Floating foundation" and obj.Name ~= "Island underside" then table.insert(solids, obj) end
end
local function solidAt(cf, h, except)
	for _, p in solids do
		if not except[p] and obbObb(cf, h, p.CFrame, p.Size / 2) then return p end
	end
	return nil
end
for _, w in walkins do
	local def, ground, model = w.def, w.ground, w.host.Parent
	local floorTop = ground.Position.Y + def.floor
	-- A player-sized column swept through the door from 3 studs outside to the counter front.
	local idef = KIT[(function() for _, p in model:GetChildren() do if p:GetAttribute("Interior") then return p:GetAttribute("Interior") end end end)()]
	-- Straight in along the door axis to the counter front, or to mid-hall
	-- when the counter stands to one side (a tavern bar).
	local cc, cs = idef.counter.c, idef.counter.s
	local ahead = math.abs(cc[1]) - cs[1] / 2 < 1.1
	-- (§40 QC L6: the tavern's tables collide now, so the way to a side bar
	-- goes in past the door, then across the front of the room to the bar.)
	local z1 = if ahead then cc[3] - cs[3] / 2 - .6 else -2.2
	local z0 = -def.d / 2 - 3
	local sweep = ground * CFrame.new(0, def.floor + .2 + 2.75, (z0 + z1) / 2)
	local hit = solidAt(sweep, Vector3.new(1.1, 2.6, (z1 - z0) / 2), {[w.host] = true})
	ok(hit == nil, model.Name .. ": the way in from the street to the counter is clear" .. (if hit then " (blocked by " .. hit:GetFullName() .. ")" else ""))
	if not ahead then
		local x1 = math.sign(cc[1]) * (math.abs(cc[1]) - cs[1] / 2 - .6)
		local across = ground * CFrame.new(x1 / 2, def.floor + .2 + 2.75, z1)
		hit = solidAt(across, Vector3.new(math.abs(x1) / 2, 2.6, 1.1), {[w.host] = true})
		ok(hit == nil, model.Name .. ": the way across to the bar is clear" .. (if hit then " (blocked by " .. hit:GetFullName() .. ")" else ""))
	end
	-- Enclosed: each wall's span is covered by a collider (no gap but the door).
	for _, probe in {{0, def.d / 2 - def.t / 2}, {def.w / 2 - def.t / 2, 0}, {-def.w / 2 + def.t / 2, 0}, {def.w / 2 - 2, -def.d / 2 + def.t / 2}, {-def.w / 2 + 2, -def.d / 2 + def.t / 2}} do
		local p = (ground * CFrame.new(probe[1], 3, probe[2])).Position
		local found = false
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and (child.Name == "Hall wall") and inside(child.CFrame, child.Size / 2, p, .01) then found = true end
		end
		ok(found, model.Name .. " wall collider at " .. probe[1] .. "," .. probe[2])
	end
	-- The floor: a solid top at the kit's floor height under the whole interior.
	ok(near(w.host.CFrame.Position.Y + w.host.Size.Y / 2, floorTop, .01), model.Name .. " floor top at the kit floor height")
end

-- Nothing blocked: no prompt host, anchor, sign, bridge or path inside any building.
local anchors, prompts, paths = {}, {}, {}
for _, obj in islands:GetDescendants() do
	if obj:IsA("BasePart") and string.find(obj.Name, "^Anchor_") then table.insert(anchors, obj) end
	if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then table.insert(prompts, obj) end
	if obj:IsA("BasePart") and (obj.Name == "Path" or obj.Name == "Ramp" or obj.Name == "Continuous bridge deck" or obj.Name == "Bridge guard") then table.insert(paths, obj) end
end
local function ownBuilding(obj)
	local node = obj
	while node and node ~= islands do
		if node:IsA("Model") and node:GetAttribute("Building") then return node end
		node = node.Parent
	end
	return nil
end
local insideHalls = {}
for _, host in hosts do
	local def = KIT[host:GetAttribute("BuildingType")]
	local hostAt = if def.kind == "facade" then Vector3.new(0, def.h / 2, 0) else Vector3.new(0, def.floor - .25, 0)
	local ground = host.CFrame * CFrame.new(-hostAt)
	local model = host.Parent
	-- The building's whole visual box (fit) and its collider box.
	local lo, hi = Vector3.new(table.unpack(def.fit[1])), Vector3.new(table.unpack(def.fit[2]))
	local fitCF, fitH = ground * CFrame.new((lo + hi) / 2), (hi - lo) / 2
	local wallCF, wallH = ground * CFrame.new(0, def.h / 2, 0), Vector3.new(def.w, def.h, def.d) / 2
	for _, a in anchors do
		if ownBuilding(a) ~= model then
			local p = a.CFrame.Position
			if def.kind == "walkin" and inside(wallCF, wallH - Vector3.new(def.t, 0, def.t), p + Vector3.new(0, 1, 0)) then
				insideHalls[a.Name] = model.Name
			else
				-- Standing room: outside the walls by at least 1.5 studs (eaves, awnings
				-- and porches may overhang a waypoint, as a shop sign would).
				ok(not inside(wallCF, wallH, p + Vector3.new(0, 1, 0), 1.5), a.Name .. " stays outside " .. model.Name)
			end
		end
	end
	for _, q in prompts do
		local hostPart = q.Parent
		if ownBuilding(hostPart) ~= model then
			local p = hostPart.CFrame.Position
			ok(not inside(wallCF, wallH, p) or def.kind == "walkin" and inside(wallCF, wallH - Vector3.new(def.t, 0, def.t), p), "prompt " .. hostPart:GetFullName() .. " is not walled in by " .. model.Name)
			local plo, phi = boxOf(hostPart)
			ok(not obbHitsAabb(wallCF, wallH, plo, phi) or def.kind == "walkin" and not obbHitsAabb(ground * CFrame.new(0, def.h / 2, def.d / 2 - def.t / 2), Vector3.new(def.w / 2, def.h / 2, def.t / 2), plo, phi),
				"prompt host " .. hostPart:GetFullName() .. " clear of " .. model.Name)
		end
	end
	for _, p in paths do
		-- Paths and bridges keep their full width clear of the visual (fit) box.
		ok(not obbObb(fitCF, fitH, p.CFrame, p.Size / 2), p:GetFullName() .. " is not built over by " .. model.Name)
	end
end
-- Anchors inside halls are exactly the service ones (banker, merchant and their waypoints).
for name, hall in insideHalls do
	ok(name == "Anchor_NPC_Banker" or name == "Anchor_NPC_Merchant" or name == "Anchor_Waypoint_Bank" or name == "Anchor_Waypoint_Market", name .. " is inside " .. hall .. " by design")
end
ok(insideHalls.Anchor_NPC_Banker == "Quay Bank" and insideHalls.Anchor_Waypoint_Bank == "Quay Bank", "banker and bank waypoint stand inside the Quay Bank")
ok(insideHalls.Anchor_NPC_Merchant == "Trade Counter" and insideHalls.Anchor_Waypoint_Market == "Trade Counter", "merchant and market waypoint stand inside the Trade Counter")

-- No overlaps: building visual (fit) boxes never intersect each other, and
-- neighbouring houses keep an alley between their collider blocks.
local function fitFrame(h)
	local d = KIT[h:GetAttribute("BuildingType")]
	local at = if d.kind == "facade" then Vector3.new(0, d.h / 2, 0) else Vector3.new(0, d.floor - .25, 0)
	local lo, hi = Vector3.new(table.unpack(d.fit[1])), Vector3.new(table.unpack(d.fit[2]))
	return h.CFrame * CFrame.new(-at) * CFrame.new((lo + hi) / 2), (hi - lo) / 2
end
local minGap = math.huge
for i = 1, #hosts do
	for j = i + 1, #hosts do
		local a, c = hosts[i], hosts[j]
		if isleOf(a) == isleOf(c) and (a.CFrame.Position - c.CFrame.Position).Magnitude < 60 then
			local fa, ha = fitFrame(a)
			local fc, hc = fitFrame(c)
			ok(not obbObb(fa, ha, fc, hc), a.Parent.Name .. " and " .. c.Parent.Name .. " do not overlap")
			if a.Name == "Roofed house" and c.Name == "Roofed house" then
				local gap = 0
				for _, axis in {a.CFrame.RightVector, a.CFrame.LookVector, c.CFrame.RightVector, c.CFrame.LookVector} do
					local d = math.abs((c.CFrame.Position - a.CFrame.Position):Dot(axis))
					local ra = math.abs(a.CFrame.RightVector:Dot(axis)) * a.Size.X / 2 + math.abs(a.CFrame.LookVector:Dot(axis)) * a.Size.Z / 2
					local rc = math.abs(c.CFrame.RightVector:Dot(axis)) * c.Size.X / 2 + math.abs(c.CFrame.LookVector:Dot(axis)) * c.Size.Z / 2
					gap = math.max(gap, d - ra - rc)
				end
				minGap = math.min(minGap, gap)
			end
		end
	end
end
ok(minGap >= 2.4, string.format("an alley of at least 2.4 studs between house walls (min %.2f)", minGap))

-- §40 QC L2: the placement searches that run after the settlements (World
-- Art & Regions props, the Skyward Vents, exploration, lairs, raids, the
-- Council Hall, beacons) block with a building's whole declared mesh box, so
-- no part of theirs stands inside a house's roof / porch / awning volume.
do
	local CONTENT = {"ExploreContent", "LairContent", "RaidContent", "VentId", "CouncilContent", "BeaconContent", "RegionArt"}
	local function contentOf(obj)
		local node = obj.Parent
		while node and node ~= islands do
			for _, a in CONTENT do if node:GetAttribute(a) ~= nil then return a end end
			node = node.Parent
		end
		return nil
	end
	local probed = 0
	for _, h in hosts do
		local fcf, fh = fitFrame(h)
		local isle = isleOf(h)
		for _, obj in isle:GetDescendants() do
			if obj:IsA("BasePart") and ownBuilding(obj) == nil and (obj.CanCollide or obj.Transparency < 1) then
				local what = contentOf(obj)
				if what then
					probed += 1
					ok(not obbObb(fcf, fh, obj.CFrame, obj.Size / 2, -.05), obj:GetFullName() .. " (" .. what .. ") is not placed inside " .. h.Parent.Name)
				end
			end
		end
	end
	ok(probed > 0, "post-settlement content probed against building boxes (" .. probed .. ")")
	-- Every clearance helper from the first settlement on reads Buildings.box
	-- (ShapeBox / ShapeBoxOffset), never the bare part size.
	local after = string.sub(source, (string.find(source, "function Buildings.settle", 1, true)))
	local _, bare = string.gsub(after, "local cf,sz=obj%.CFrame,obj%.Size\n", "")
	local _, boxed = string.gsub(after, "local cf,sz=Buildings%.box%(obj%)", "")
	ok(bare == 0 and boxed >= 7, "post-settlement placement helpers honour ShapeBox (" .. boxed .. " boxed, " .. bare .. " bare)")
end

-- §40 QC L5: the regional walk-in shops carry a name sign (Signs.build) beside
-- their front corner, outside the walls.
for _, title in {"Quay Outfitters", "Mosswake Herbalist", "Brassfall Assay House", "Skyreach Outfitters"} do
	local hall
	for _, w in walkins do if w.host.Parent.Name == title then hall = w end end
	ok(hall ~= nil, title .. " is built")
	local holder = hall and hall.host.Parent:FindFirstChild("Sign " .. title)
	ok(holder ~= nil and holder:GetAttribute("SignTitle") == title and holder:GetAttribute("SignArchetype") ~= nil, title .. " has a name sign")
	for _, p in (holder and holder:GetDescendants() or {}) do
		if p:IsA("BasePart") then
			local q = hall.ground:PointToObjectSpace(p.CFrame.Position)
			ok(math.abs(q.X) > hall.def.w / 2 + .5 and q.Z < 0, title .. " sign stands outside the hall, by its front")
		end
	end
end

-- The Guild Hall pavilion is furnished (rug, trestle tables, benches,
-- chandelier) clear of its ledgers, the Huntmaster's pedestal and anchors.
do
	local furnish = islands:FindFirstChild("Guild Terrace"):FindFirstChild("Hall furnishings", true)
	ok(furnish ~= nil and furnish:GetAttribute("Shape") == "HallFurnishings" and furnish.Transparency == 1 and not furnish.CanCollide, "Guild Hall furnishings placed")
	local fit = KIT.HallFurnishings.fit
	ok(nearV(furnish.Size, Vector3.new(fit[2][1] - fit[1][1], fit[2][2] - fit[1][2], fit[2][3] - fit[1][3]), .01), "furnishing host = its fit box")
	-- §40: the furnishings follow the floor's yaw; QC L6: trestles and benches collide.
	local floor = furnish.Parent:FindFirstChild("Hall floor")
	local rel = floor.CFrame:ToObjectSpace(furnish.CFrame)
	ok(math.abs(rel.LookVector.Z + 1) < 1e-4 and math.abs(rel.UpVector.Y - 1) < 1e-4, "Guild Hall furnishings share the floor's yaw")
	local colliders = 0
	for _, obj in furnish.Parent:GetChildren() do
		if obj:IsA("BasePart") and obj:GetAttribute("FurnitureCollider") then
			colliders += 1
			ok(inside(furnish.CFrame, furnish.Size / 2, obj.CFrame.Position) and obj.CanCollide and obj.Transparency == 1, "furniture collider inside the furnishing box")
			local r = furnish.CFrame:ToObjectSpace(obj.CFrame)
			ok(math.abs(r.LookVector.Z + 1) < 1e-4, "furniture collider follows the floor's yaw")
		end
	end
	ok(colliders == 3, "Guild Hall trestles, benches and wall bench collide (" .. colliders .. ")")
	local inn = islands:FindFirstChild("Compass Quay"):FindFirstChild("The Gilded Compass Inn")
	local innColliders = 0
	for _, obj in inn:GetChildren() do if obj:IsA("BasePart") and obj:GetAttribute("FurnitureCollider") then innColliders += 1 end end
	ok(innColliders == 4, "the inn's tables and hearth collide (" .. innColliders .. ")")
	for _, obj in furnish.Parent:GetDescendants() do
		if obj:IsA("BasePart") and obj ~= furnish and obj.Name ~= "Hall floor" and not obj:GetAttribute("FurnitureCollider") and (obj.CanCollide or obj:FindFirstChildOfClass("ProximityPrompt")) then
			ok(not obbObb(furnish.CFrame, furnish.Size / 2, obj.CFrame, obj.Size / 2), "furnishings clear of " .. obj.Name)
		end
	end
end

-- Spread (owner: "spread everything out on the starter islands"): on Compass
-- Quay, Sunwheel Downs (Meadow Reach) and the home island, the stations,
-- prompts, gathering nodes, NPC anchors and buildings stand on average >= 45% of the island
-- radius from the centre, and every quadrant holds some of them.
local spreadReport = {}
do
	local starters = {islands:FindFirstChild("Compass Quay"), islands:FindFirstChild("Meadow Reach")}
	for _, m in b.archipelago:GetChildren() do if string.find(m.Name, "^WayfarersRest_") then table.insert(starters, m) end end
	ok(#starters == 3, "hub, Sunwheel Downs and a home island measured")
	for _, isle in starters do
		local IC, R = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
		local n, sum, quad = 0, 0, {0, 0, 0, 0}
		for _, obj in isle:GetDescendants() do
			local pos
			if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then pos = obj.Parent.CFrame.Position
			elseif obj:IsA("BasePart") and (string.find(obj.Name, "^Anchor_NPC_") or obj:GetAttribute("BuildingType") or obj:GetAttribute("GatherNode")) then pos = obj.CFrame.Position end -- §42: struck node hosts replace gather prompts
			if pos then
				local d = Vector3.new(pos.X - IC.X, 0, pos.Z - IC.Z)
				n += 1
				sum += d.Magnitude
				local q = (if d.X >= 0 then 1 else 0) + (if d.Z >= 0 then 2 else 0) + 1
				quad[q] += 1
			end
		end
		local share = sum / math.max(1, n) / R
		ok(n >= 15 and share >= .45, string.format("%s: content spread out (mean %.0f%% of r%d over %d items)", isle.Name, share * 100, R, n))
		for q = 1, 4 do ok(quad[q] >= 2, isle.Name .. " quadrant " .. q .. " is not empty (" .. quad[q] .. ")") end
		table.insert(spreadReport, string.format("%s %.0f%% (%d/%d/%d/%d)", isle.Name, share * 100, quad[1], quad[2], quad[3], quad[4]))
	end
end

-- The add-ons moved onto ground a player may already have decorated: every
-- saved decoration there is relocated (Island.migrate), never refunded or lost.
do
	local Data = b.Data
	local I = Data.Island
	local recs = {}
	local id = 0
	for _, c in I.ProtectedCircles do
		id += 1
		table.insert(recs, string.format("%d:TimberFence:%d:%d:0", id, math.floor(c.x / I.CELL + .5), math.floor(c.z / I.CELL + .5)))
	end
	-- §40 QC M1: the oriented garden walk and worker-yard path are protected
	-- (segment capsules) and saved decorations on their midpoints move too.
	ok(#I.ProtectedSegments >= 2, "the garden walk and the worker-yard path are protected walks")
	local walkRecs = 0
	for _, g in I.ProtectedSegments do
		local mx, mz = math.floor((g.ax + g.bx) / 2 / I.CELL + .5), math.floor((g.az + g.bz) / 2 / I.CELL + .5)
		ok(I.cellBlocked(mx, mz, 0) == g.name, g.name .. " midpoint cell is protected (" .. tostring(I.cellBlocked(mx, mz, 0)) .. ")")
		-- A cell well off the walk's side stays buildable (the capsule is narrow).
		local len = math.sqrt((g.bx - g.ax) ^ 2 + (g.bz - g.az) ^ 2)
		local nx, nz = -(g.bz - g.az) / len, (g.bx - g.ax) / len
		local sx, sz = math.floor(((g.ax + g.bx) / 2 + nx * 8) / I.CELL + .5), math.floor(((g.az + g.bz) / 2 + nz * 8) / I.CELL + .5)
		ok(I.cellBlocked(sx, sz, 0) == nil, g.name .. " leaves the meadow beside it buildable")
		id += 1
		walkRecs += 1
		table.insert(recs, string.format("%d:TimberFence:%d:%d:0", id, mx, mz))
	end
	local migrated, refunds, report = I.migrate({placed = recs, v = I.VERSION}, 0)
	ok(report.refunded == 0 and next(refunds) == nil, "decorations on the moved add-ons' ground are never refunded")
	ok(#migrated.placed == #recs and report.moved >= 1 + walkRecs, "they are relocated beside them (" .. report.moved .. " moved)")
	for _, rec in migrated.placed do
		local e = I.parseRecord(rec)
		ok(e ~= nil and I.cellBlocked(e.x, e.z, 0) == nil, "relocated record " .. tostring(rec) .. " lands on a buildable cell")
	end
	-- Every walk on a built home island (Path strips beyond the legacy core) is protected along its length.
	for _, m in b.archipelago:GetChildren() do
		if string.find(m.Name, "^WayfarersRest_") then
			local IC = m:GetAttribute("IslandCenter")
			local walks = 0
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and p.Name == "Path" then
					walks += 1
					for t = -.45, .45, .15 do
						local q = p.CFrame.Position + p.CFrame.LookVector * (p.Size.Z * t) - IC
						if math.sqrt(q.X * q.X + q.Z * q.Z) > 22 then
							local x, z = math.floor(q.X / I.CELL + .5), math.floor(q.Z / I.CELL + .5)
							ok(I.cellBlocked(x, z, 0) ~= nil, m.Name .. " walk at (" .. x .. ", " .. z .. ") is protected")
						end
					end
				end
			end
			-- §40 QC: the Builder's Terrace sign stands at the terrace, inside its protected zone.
			local signModel = m:FindFirstChild("Sign Builder's Terrace", true)
			ok(signModel ~= nil, "Builder's Terrace sign built")
			local zone
			for _, r in I.Protected do if r.name == "terrace sign" then zone = r end end
			for _, p in (signModel and signModel:GetDescendants() or {}) do
				if p:IsA("BasePart") and (p.CanCollide or p.Transparency < 1) then
					local q = p.CFrame.Position - IC
					ok(q.X > zone.x1 - .5 and q.X < zone.x2 + .5 and q.Z > zone.z1 - .5 and q.Z < zone.z2 + .5, p.Name .. " of the terrace sign inside its protected zone (" .. math.floor(q.X * 10) / 10 .. ", " .. math.floor(q.Z * 10) / 10 .. ")")
					ok(math.abs(q.X - Data.TERRACE_OFFSET.x) < 16, "the terrace sign stands near the terrace (" .. math.floor(q.X) .. ")")
				end
			end
			ok(walks >= 3, m.Name .. " home walks measured (yard, terrace, garden; the lookout boardwalk is a level add-on) (" .. walks .. ")")
		end
	end
end

-- Budgets: parts, templates, triangles, lights and glow panes.
local templates, templateTris = 0, 0
for name, count in typeCount do templates += 1; templateTris += #World.shapes[name].faces end
ok(buildingParts <= 260, "buildings cost at most 260 static parts (" .. buildingParts .. ")")
local L = luau.load(fs.readFile("shared/LightingProfiles.lua"), {environment = {Color3 = roblox.Color3}, injectGlobals = true})()
ok(L.GLOW_KINDS.window ~= nil, "window glow kind defined (§35)")
ok(type(L.WindowTiers) == "table", "window pane tiers defined (§40)")
for tier, cap in L.WindowTiers do
	ok(cap.panes <= 320 and cap.range <= 300 and cap.buildings <= 48, tier .. " window pane caps stay bounded")
end
print(string.format("Buildings: %d (%s), %d static parts, %d walk-in halls, %d interior lights, %d glow sites, %d window panes; kit %d shapes / %d triangles; world %d static parts.",
	#hosts, (function() local t = {} for k, v in perIsle do table.insert(t, k .. " " .. v) end table.sort(t) return table.concat(t, ", ") end)(),
	buildingParts, #walkins, interiorLights, glowSites, panes, templates, kitTriangles, staticParts))
print("Spread: " .. table.concat(spreadReport, "; ") .. ".")
print("Building QA passed " .. checks .. " checks.")
-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-buildings.luau")

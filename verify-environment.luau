-- Island environment art (docs/DEPTH-CONTRACT.md §54): shared/TerrainArt.lua,
-- terrain.client.lua, the forge's dress / ground pools and art/TerrainCatalog.lua.
-- (Shape smoothness, per-vertex colour and subdivision for every catalog are in
-- verify-mesh.luau.)
-- Part A: region art (3+ species per biome, near / far LODs, heroes, sway).
-- Part B: budgets per graphics tier and the forge's pool ceilings.
-- Part C: the real world (tools/world-harness.luau): coverage per island,
--   nothing on paths / build cells / node footprints / protected circles /
--   prompts / buildings, walkability by barycentric sampling of the real ground
--   mesh, the skirt, the forged cliff wall (smoothness, chord, colour, the lip
--   meeting the ground), cliff attachment, density per tier, part budget, and
--   one regression per QC finding (M1, M2, M4, M5, L1, L3-L7).
-- Part D: the forge's dress and ground pools (H1 tint quantising, H2 separate
--   ground failures, M6 dressing never watched, M7 phone cap and recovery).
-- Part E: terrain.client.lua headless (H1-H4, M3, M6, L2; caps per tier, LODs).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local checks = 0
local function ok(cond, case) checks += 1; if not cond then error("FAILED: " .. case, 2) end end
local function eq(a, b, case) ok(a == b, case .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")") end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local T = load("shared/TerrainArt.lua", {Vector3 = Vector3, CFrame = CFrame, Enum = Enum})
local Catalog = load("art/TerrainCatalog.lua")
local World = load("art/WorldCatalog.lua")
local A = load("shared/Ambience.lua")
local forgeSource = fs.readFile("forge.client.lua")
local clientSource = fs.readFile("terrain.client.lua")

------------------------------------------------------------------------------
-- Part A: region art.
------------------------------------------------------------------------------
local trisOf = {}
for name, data in pairs(Catalog.shapes) do trisOf[name] = data.tris end
local classOfKind = {clutter = "clutter", shrub = "clutter", rock = "rock", cliff = "cliff", satellite = "satellite"}
for name, data in pairs(Catalog.shapes) do
	local class = if data.kind == "foliage" then (if data.lod == "far" then "far" else "near") else classOfKind[data.kind]
	ok(class ~= nil and data.tris <= T.MAX_TRIS[class], name .. " fits its class's triangle size (" .. tostring(class) .. ")")
	if data.kind == "rock" then eq(T.SHAPE_CLASS[name], "rock", name .. " counts as a rock") end
	if data.kind == "foliage" and data.lod == "near" then ok(Catalog.shapes[name .. "Far"] ~= nil, name .. " has a far LOD") end
end
local regionCount, heroes = 0, {}
for id, art in pairs(T.Regions) do
	regionCount += 1
	local species = {}
	for _, s in ipairs(art.trees) do species[s.shape] = true; ok(#s.tints <= 2, id .. " " .. s.shape .. " keeps <= 2 tint variants (H1)") end
	local distinct = 0
	for _ in pairs(species) do distinct += 1 end
	ok(distinct >= 3, id .. " has 3+ tree species (" .. distinct .. ")")
	ok(Catalog.shapes[art.hero.shape] and Catalog.shapes[art.hero.shape].kind == "foliage" and art.hero.scale >= 1.8, id .. " hero silhouette tree")
	heroes[art.hero.shape .. art.hero.tint] = true
	for _, list in ipairs({art.trees, art.shrubs, art.clutter}) do
		for _, s in ipairs(list) do
			ok(Catalog.shapes[s.shape] ~= nil and Catalog.shapes[s.shape].lod ~= "far", id .. " names an authored near shape " .. s.shape)
			ok(#s.tints >= 1 and #s.tints <= 2 and s.weight > 0 and s.scale[1] > 0 and s.scale[2] >= s.scale[1], id .. " " .. s.shape .. " tints / weight / scale")
			ok(s.scale[2] * (if s.shape == art.hero.shape then 1 else 1) <= (Catalog.shapes[s.shape].maxScale or 1) + 1e-6, id .. " " .. s.shape .. " placed within its authored maxScale")
		end
	end
	ok(art.hero.scale * 1.08 <= Catalog.shapes[art.hero.shape].maxScale + 1e-6, id .. " hero within its maxScale")
	for i, shape in ipairs(art.cliff) do ok(Catalog.shapes[shape].kind == "cliff" and art.cliffTint[i] ~= nil, id .. " cliff dressing " .. shape) end
	ok(Catalog.shapes[art.satellite].kind == "satellite", id .. " satellite rock")
end
local unique = 0
for _ in pairs(heroes) do unique += 1 end
ok(unique >= 8, "hero silhouettes read distinct per region (" .. unique .. ")")
ok(T.Regions.Skyreach.trees[1].shape == "SnowPine" and T.Regions.Skyreach.hero.shape == "SnowPine", "Skyreach pines carry snow (A5)")
for name in pairs(T.SWAYS) do ok(A.SWAY[name] ~= nil and Catalog.shapes[name] ~= nil, name .. " is in the ambience sway table") end
print(string.format("PASS A: %d checks; %d terrain shapes; %d regions.", checks, (function() local n = 0 for _ in pairs(Catalog.shapes) do n += 1 end return n end)(), regionCount))

------------------------------------------------------------------------------
-- Part B: budgets.
------------------------------------------------------------------------------
local partB = checks
local function forgeNumber(name, phone)
	local a, b = string.match(forgeSource, "local " .. name .. " = if mobile then (%d+) else (%d+)")
	return tonumber(if phone then a else b)
end
local prev
for _, key in ipairs(T.TIER_ORDER) do
	local b = T.Budgets[key]
	ok(T.ceiling(b) <= b.triangles, string.format("%s worst case %d triangles <= budget %d", key, T.ceiling(b), b.triangles))
	ok(b.clutterRadius <= b.farRadius and b.nearRadius <= b.farRadius and b.farRadius <= b.satelliteRadius, key .. " far LOD ordering")
	ok(b.density > 0 and b.density <= 1 and b.hullLevels >= 12 and b.hullSeg >= 6, key .. " density / wall resolution")
	if prev then
		for _, field in ipairs({"clutter", "rock", "near", "far", "cliff", "satellite", "density", "grounds", "triangles", "hullLevels"}) do
			ok(b[field] <= prev[field], key .. " " .. field .. " never exceeds the tier above")
		end
		ok(b.cell >= prev.cell and b.hullSeg >= prev.hullSeg, key .. " never finer than the tier above")
	end
	prev = b
end
ok(T.Budgets.High.hullLevels >= 24 and T.Budgets.High.hullSeg >= 6 and T.Budgets.High.hullSeg <= 8, "High walls: >= 24 levels, one segment per 6-8 studs (A5)")
eq(T.CLASSES[1], "satellite", "far-seen classes first (H1)")
eq(T.CLASSES[#T.CLASSES], "clutter", "clutter last (H1)")
eq(T.budgetKey("High", true), "Lite", "phones use Lite")
eq(T.Budgets.Performance.grounds, 0, "Performance keeps the primitive meadow")
local high, lite = T.Budgets.High, T.Budgets.Lite
local function count(b) return b.clutter + b.rock + b.near + b.far + b.cliff + b.satellite end
ok(forgeNumber("DRESS_INSTANCE_CAP", false) >= count(high) and forgeNumber("DRESS_INSTANCE_CAP", true) >= count(lite), "dress instance ceilings hold High / Lite")
local function dressTris(b) return T.ceiling(b) - b.grounds * (T.groundTriangles(T.LARGEST_ISLAND, b.cell) + T.hullTriangles(T.LARGEST_ISLAND, b.hullSeg, b.hullLevels)) end
ok(forgeNumber("DRESS_PLACED_CAP", false) >= dressTris(high) and forgeNumber("DRESS_PLACED_CAP", true) >= dressTris(lite), "placed-triangle ceilings hold High / Lite")
ok(forgeNumber("GROUND_CAP", false) >= 2 * high.grounds and forgeNumber("GROUND_CAP", true) >= 2 * lite.grounds, "a ground and a wall per island")
ok(forgeNumber("GROUND_TRIANGLE_CAP", false) >= high.grounds * (T.groundTriangles(T.LARGEST_ISLAND, high.cell) + T.hullTriangles(T.LARGEST_ISLAND, high.hullSeg, high.hullLevels)), "desktop ground / wall triangles")
ok(forgeNumber("GROUND_TRIANGLE_CAP", true) >= lite.grounds * (T.groundTriangles(T.LARGEST_ISLAND, lite.cell) + T.hullTriangles(T.LARGEST_ISLAND, lite.hullSeg, lite.hullLevels)), "phone ground / wall triangles")
eq(forgeNumber("DRESS_TEMPLATE_CAP", true), 12, "[M7] phones keep a 12-template dress pool")
print(string.format("PASS B: %d budget checks (High ceiling %d, Lite %d triangles).", checks - partB, T.ceiling(high), T.ceiling(lite)))

------------------------------------------------------------------------------
-- Part C: the generated world.
------------------------------------------------------------------------------
local partC = checks
local W = require("./tools/world-harness")
local built = W.build()
local Data = built.Data
local islands = {}
for _, container in ipairs({built.islands, built.archipelago}) do
	for _, m in ipairs(container:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChild("Meadow") and m:GetAttribute("IslandCenter") then table.insert(islands, m) end
	end
end
ok(#islands >= 14, "islands found (" .. #islands .. ")")
local staticParts = 0
for _, d in ipairs(built.world:GetDescendants()) do
	if d:IsA("BasePart") then
		ok(d:GetAttribute("Dressing") == nil, "no server part is dressing")
		if not d:FindFirstAncestor("AetherIsles") then staticParts += 1 end
	end
end
ok(built.world:FindFirstChild("IsleDressing") == nil, "the dressing root is client-only")
ok(staticParts <= 4000, "static world parts " .. staticParts .. " <= 4000")
-- Lead decision: thick cliff walls (clamp(R*0.18, 10, 30)), colliders and keels intact.
for _, isle in ipairs(built.islands:GetChildren()) do
	local foundation, keel, meadow = isle:FindFirstChild("Floating foundation"), isle:FindFirstChild("Island underside"), isle:FindFirstChild("Meadow")
	if foundation and meadow then
		local r = isle:GetAttribute("IslandRadius")
		local wall = foundation:GetAttribute("WallHeight")
		ok(type(wall) == "number" and math.abs(foundation.Size.X - wall) < 1e-3 and wall >= 10 and wall <= 30, isle.Name .. " has a thick cliff wall (" .. tostring(wall) .. ")")
		ok(foundation.CanCollide and meadow.CanCollide, isle.Name .. " colliders unchanged")
		local fTop = foundation.CFrame.Position.Y + foundation.Size.X / 2
		ok(fTop < meadow.CFrame.Position.Y - meadow.Size.X / 2, isle.Name .. " wall top under the meadow slab")
		if keel then
			local kTop = keel.CFrame.Position.Y + keel.Size.X / 2
			ok(kTop > fTop - wall and kTop < fTop - wall + 1, isle.Name .. " keel hangs from the wall's foot")
		end
	end
end

-- Independent footprint distance (oriented, from the instances).
local function obbDistance(p, x, z)
	local o = T.footprint(p)
	return T.distanceTo(o, x, z)
end
local totals = {clutter = 0, rock = 0, tree = 0, cliff = 0, satellite = 0}
local largestGround, largestHull = 0, 0
local worstHullDev, worstHullDL = 0, 0
local function luma(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
-- Area-weighted 98th-percentile corner deviation of a flat-array mesh (its own smooth normals).
local function meshDeviation(m)
	local pos, idx, nor = m.positions, m.indices, m.normals
	local devs, total = {}, 0
	for f = 1, #idx, 3 do
		local a, b, c = idx[f], idx[f + 1], idx[f + 2]
		local pa = Vector3.new(pos[a * 3 - 2], pos[a * 3 - 1], pos[a * 3])
		local n = (Vector3.new(pos[b * 3 - 2], pos[b * 3 - 1], pos[b * 3]) - pa):Cross(Vector3.new(pos[c * 3 - 2], pos[c * 3 - 1], pos[c * 3]) - pa)
		local area = n.Magnitude
		if area > 0 then
			for _, k in ipairs({a, b, c}) do
				local vn = Vector3.new(nor[k * 3 - 2], nor[k * 3 - 1], nor[k * 3])
				table.insert(devs, {math.deg(math.acos(math.clamp(vn:Dot(n.Unit), -1, 1))), area})
				total += area
			end
		end
	end
	table.sort(devs, function(p, q) return p[1] < q[1] end)
	local acc = 0
	for _, e in ipairs(devs) do acc += e[2]; if acc >= total * 0.98 then return e[1] end end
	return 0
end
for _, model in ipairs(islands) do
	local desc = T.collect(model, Data.Island.ProtectedCircles)
	ok(desc ~= nil, model.Name .. " has an island descriptor")
	local items = T.plan(desc)
	local counts = {clutter = 0, rock = 0, tree = 0, cliff = 0, satellite = 0}
	for _, it in ipairs(items) do
		counts[it.class] += 1
		totals[it.class] += 1
		ok(Catalog.shapes[it.shape] ~= nil and pcall(Color3.fromHex, it.tint), model.Name .. " item shape / tint")
		if it.class == "tree" then ok(Catalog.shapes[it.far] ~= nil, model.Name .. " tree far LOD") end
	end
	local R = desc.radius
	local home = desc.build ~= nil
	local band = if home then math.pi * (R * R - (desc.build + 1) ^ 2) else math.pi * R * R
	ok(counts.clutter + counts.rock >= band / 160, string.format("%s clutter coverage %d over %.0f sq studs", model.Name, counts.clutter + counts.rock, band))
	ok(counts.cliff >= math.floor(2 * math.pi * R / 11 * 0.5), model.Name .. " cliff dressing around the rim (" .. counts.cliff .. ")")
	ok(counts.satellite >= 2, model.Name .. " has satellite rocks")
	if not home and model.Parent == built.islands then ok(counts.tree >= 2, model.Name .. " has trees (" .. counts.tree .. ")") end
	-- Rules: nothing on paths, nodes (L7: 3 studs), prompts, buildings, anchors, build cells, protected circles.
	local paths, nodes, solids = {}, {}, {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and not desc.self[p] and not T.IGNORE_NAMES[p.Name] then
			local _, y0, y1 = T.footprint(p)
			if y1 > desc.top - 0.6 and y0 < desc.top + 14 then
				if T.PATH_NAMES[p.Name] then table.insert(paths, p)
				elseif p:GetAttribute("GatherNode") ~= nil or (p.Parent and p.Parent:GetAttribute("GatherNode") ~= nil) then table.insert(nodes, p)
				elseif p:FindFirstChildOfClass("ProximityPrompt") or p:GetAttribute("BuildingType") or p.Name:sub(1, 7) == "Anchor_" then table.insert(solids, p) end
			end
		end
	end
	local cx, cz = desc.center[1], desc.center[3]
	for _, it in ipairs(items) do
		if it.class == "clutter" or it.class == "rock" or it.class == "tree" then
			local d = math.sqrt((it.x - cx) ^ 2 + (it.z - cz) ^ 2)
			ok(d <= R - 1, model.Name .. " item inside the rim")
			if home then
				ok(d >= desc.build + 1, model.Name .. " nothing on the home build cells")
				for _, c in ipairs(Data.Island.ProtectedCircles) do
					ok((it.x - (cx + c.x)) ^ 2 + (it.z - (cz + c.z)) ^ 2 > c.r * c.r, model.Name .. " clear of protected circle " .. c.name)
				end
			end
			for _, p in ipairs(paths) do ok(obbDistance(p, it.x, it.z) > 0.5, model.Name .. " " .. it.shape .. " off the path " .. p:GetFullName()) end
			for _, p in ipairs(nodes) do ok(obbDistance(p, it.x, it.z) >= 3, "[L7] " .. model.Name .. " " .. it.shape .. " >= 3 studs from node " .. p:GetFullName()) end
			for _, p in ipairs(solids) do ok(obbDistance(p, it.x, it.z) > 0.8, model.Name .. " " .. it.shape .. " clears " .. p:GetFullName()) end
		end
	end
	-- Ground: walkable band, flat on paths (M2 barycentric sampling of the real
	-- mesh), faces up, rim on the meadow wall, skirt folded under the curb (M4).
	local g = T.ground(desc, T.Budgets.High.cell)
	ok(T.ground(desc, T.Budgets.High.cell) == g, "[L6] the ground spec is cached per (island, cell)")
	eq(g.triangleCount, T.groundTriangles(R, T.Budgets.High.cell), model.Name .. " ground triangles match the grid")
	largestGround = math.max(largestGround, g.triangleCount)
	local pos, idx = g.positions, g.indices
	for v = 1, g.vertexCount do
		local y = pos[v * 3 - 1]
		ok(y <= T.HEIGHT.up + 1e-6 and y >= T.HEIGHT.skirt - 1e-6, model.Name .. " ground height band")
	end
	for f = 1, #idx, 3 do
		local a, b, c = idx[f], idx[f + 1], idx[f + 2]
		local ax, az = pos[a * 3 - 2], pos[a * 3]
		local ux, uz = pos[b * 3 - 2] - ax, pos[b * 3] - az
		local vx, vz = pos[c * 3 - 2] - ax, pos[c * 3] - az
		local uy, vy = pos[b * 3 - 1] - pos[a * 3 - 1], pos[c * 3 - 1] - pos[a * 3 - 1]
		local ny = uz * vx - ux * vz
		if f < g.skirtFrom then
			ok(ny > 0, model.Name .. " ground face wound up")
			-- M2: sample each triangle (barycentric); on any path footprint the
			-- surface stays at or under +0.04 (path tops sit at +0.08).
			for _, w in ipairs({{1 / 3, 1 / 3}, {0.6, 0.2}, {0.2, 0.6}, {0.2, 0.2}}) do
				local px, pz = ax + ux * w[1] + vx * w[2], az + uz * w[1] + vz * w[2]
				local py = pos[a * 3 - 1] + uy * w[1] + vy * w[2]
				if T.clearance(desc, cx + px, cz + pz, T.KINDS.paths) <= 0 then
					ok(py <= 0.04, string.format("[M2] %s ground under a path at %.1f, %.1f stays <= 0.04 (%.3f)", model.Name, px, pz, py))
				end
			end
		else
			local nx = uy * vz - uz * vy
			local nz = ux * vy - uy * vx
			ok(nx * ax + nz * az > 0, "[M4] " .. model.Name .. " skirt faces outward")
		end
	end
	local lastRing = (g.rings - 1) * g.segments + 2 -- first vertex of the rim ring
	ok(math.abs(math.sqrt(pos[lastRing * 3 - 2] ^ 2 + pos[lastRing * 3] ^ 2) - (R + 0.1)) < 0.05, model.Name .. " ground rim sits on the meadow wall")
	local skirtV = g.vertexCount
	ok(math.abs(math.sqrt(pos[skirtV * 3 - 2] ^ 2 + pos[skirtV * 3] ^ 2) - (R + 0.1 - T.HEIGHT.skirtIn)) < 0.05 and math.abs(pos[skirtV * 3 - 1] - T.HEIGHT.skirt) < 1e-6,
		"[M4] " .. model.Name .. " skirt folds under the curb")
	ok(meshDeviation(g) <= 15, model.Name .. " ground shading is smooth")
	-- Walkability sampling on a 6-stud grid.
	for gx = -R, R, 6 do
		for gz = -R, R, 6 do
			if gx * gx + gz * gz < (R - 2.5) ^ 2 then
				local h = T.heightAt(desc, cx + gx, cz + gz, g.margin)
				ok(h >= T.HEIGHT.down - 1e-6 and h <= T.HEIGHT.up + 1e-6, model.Name .. " walkable height")
			end
		end
	end
	for _, p in ipairs(solids) do
		local o = T.footprint(p)
		if (o.cx - cx) ^ 2 + (o.cz - cz) ^ 2 < (R - 3) ^ 2 then ok(math.abs(T.heightAt(desc, o.cx, o.cz, g.margin)) <= 0.01, model.Name .. " flat under " .. p.Name) end
	end
	-- The forged cliff wall (A2/A3/A5 at High): absolute-size lip + soil band +
	-- strata, >= 24 levels, smooth (<= 20 deg), chord <= 0.15 studs, continuous colour.
	local hb = T.Budgets.High
	local h = T.hull(desc, hb.hullSeg, hb.hullLevels)
	eq(h.triangleCount, T.hullTriangles(R, hb.hullSeg, hb.hullLevels), model.Name .. " wall triangles match the grid")
	largestHull = math.max(largestHull, h.triangleCount)
	ok(h.rows - #T.LIP >= 24, model.Name .. " wall has >= 24 strata levels")
	ok(2 * math.pi * (R + 0.5) / h.segments <= 8, model.Name .. " wall: a segment per <= 8 studs")
	local chord = (R + 1) * (1 - math.cos(math.pi / h.segments))
	ok(chord <= 0.15, string.format("%s wall chord %.3f <= 0.15 studs", model.Name, chord))
	local dev = meshDeviation(h)
	worstHullDev = math.max(worstHullDev, dev)
	ok(dev <= 20, string.format("%s wall shading deviation %.1f <= 20", model.Name, dev))
	ok(math.abs(h.depth - (desc.drop + desc.wall)) < 1e-6, model.Name .. " wall reaches the foundation's foot")
	-- The lip's first ring is the ground's rim ring (no seam).
	local hp = h.positions
	ok(math.abs(math.sqrt(hp[1] ^ 2 + hp[3] ^ 2) - (R + 0.1)) < 1e-6 and math.abs(hp[2] - (if desc.bare then T.HEIGHT.bareLip else T.HEIGHT.lip)) < 1e-6, model.Name .. " wall lip continues the ground rim")
	-- Hull colour check: continuous strata (in-row and in-column steps).
	local hc = h.colors
	for row = 1, h.rows do
		for j = 0, h.segments - 1 do
			local v = (row - 1) * h.segments + j + 1
			local l = luma(hc[v * 3 - 2], hc[v * 3 - 1], hc[v * 3])
			local right = (row - 1) * h.segments + (j + 1) % h.segments + 1
			local dl = math.abs(l - luma(hc[right * 3 - 2], hc[right * 3 - 1], hc[right * 3]))
			if row > #T.LIP + 1 and row < h.rows then
				local below = v + h.segments
				dl = math.max(dl, math.abs(l - luma(hc[below * 3 - 2], hc[below * 3 - 1], hc[below * 3])))
			end
			worstHullDL = math.max(worstHullDL, dl)
		end
	end
	-- M5: cliff dressing hangs from the forged wall's soil band, or the catalog rim.
	for _, it in ipairs(items) do
		if it.class == "cliff" then
			local x, _, z = T.cliffPosition(it, true)
			local r = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
			ok(math.abs(r - (R + T.ATTACH.near[1])) < 1e-6 and T.ATTACH.near[2] < -0.8 and T.ATTACH.near[1] < 0.6, "[M5] " .. model.Name .. " cliff piece hangs from the soil band under the lip")
			local fx, _, fz = T.cliffPosition(it, false)
			ok(math.abs(math.sqrt((fx - cx) ^ 2 + (fz - cz) ^ 2) - (desc.foundationRadius * T.ATTACH.farScale + 0.05)) < 0.05, "[M5] " .. model.Name .. " far: on the catalog cliff rim")
		end
	end
	-- Density per tier at the island's centre and rim: every class within its cap.
	for _, key in ipairs(T.TIER_ORDER) do
		local b = T.Budgets[key]
		for _, focus in ipairs({{cx, desc.top + 3, cz}, {cx + R, desc.top + 3, cz}}) do
			local vis = T.visible(items, key, focus, false)
			local per, tris = {}, 0
			for _, e in ipairs(vis) do
				per[e.class] = (per[e.class] or 0) + 1
				tris += trisOf[e.shape]
				if e.class == "far" then eq(e.shape, e.item.far, "far trees draw their far LOD") end
				if e.class == "near" then eq(e.shape, e.item.shape, "near trees draw their near LOD") end
			end
			for class, n in pairs(per) do ok(n <= b[class], string.format("%s %s %s %d <= %d", model.Name, key, class, n, b[class])) end
			ok(tris <= b.triangles, model.Name .. " " .. key .. " triangles within budget")
		end
	end
end
ok(worstHullDL <= 0.08, string.format("wall colour steps stay continuous (%.3f)", worstHullDL))
-- M1: oriented footprints (a rotated plank and a disc).
do
	local plank = roblox.Instance.new("Part")
	plank.Size = Vector3.new(10, 1, 1)
	plank.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
	local o = T.footprint(plank)
	ok(o.ux ~= nil and math.abs(o.hx - 5) < 1e-4 and math.abs(o.hz - 0.5) < 1e-4, "[M1] an upright box keeps its own axes")
	ok(T.distanceTo(o, 3, 3) > 2.5, "[M1] a point beside a diagonal plank is clear (an AABB would cover it)")
	ok(T.distanceTo(o, 2, -2) < 1e-6, "[M1] a point on the plank is inside")
	local disc = roblox.Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.5, 8, 8)
	disc.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local d = T.footprint(disc)
	eq(d.round, 4, "[M1] an upright cylinder is a disc")
	ok(T.distanceTo(d, 3.2, 3.2) > 0.5, "[M1] a disc's corner region is clear")
end
-- L1 / L3 / L4 / L5.
ok(T.HEIGHT.up <= 0.11 + 1e-9 and T.HEIGHT.down >= -0.06 - 1e-9, "[L1] the roll is halved (+0.11 / -0.06)")
do
	local home = built.archipelago:FindFirstChild("WayfarersRest_1")
	local desc = T.collect(home, nil)
	local plazas = 0
	for _, o in ipairs(desc.obstacles) do if o.part and o.part.Name == "Meadow" then plazas += 1 end end
	ok(plazas >= 1, "[L3] a plaza named Meadow still blocks the dressing; only the island's own meadow is ignored")
	ok(desc.self[home:FindFirstChild("Meadow")] == true, "[L3] the island's meadow is ignored by identity")
	local m = roblox.Instance.new("Model")
	local meadow = roblox.Instance.new("Part")
	meadow.Name, meadow.Size, meadow.Parent = "Meadow", Vector3.new(0.5, 40, 40), m
	ok(T.collect(m, nil) == nil, "[L5] no IslandCenter: skipped")
	m:SetAttribute("IslandCenter", Vector3.new(0 / 0, 0, 0))
	ok(T.collect(m, nil) == nil, "[L5] a NaN centre: skipped")
end
do
	local a = T.hash(-123456, 9876543, 42)
	ok(a == T.hash(-123456, 9876543, 42) and a >= 0 and a < 1, "[L4] the hash is stable for negative / large inputs")
	local seen = {}
	for i = 1, 200 do seen[T.hash(i * 7919, -i * 104729, 3)] = true end
	local n = 0
	for _ in pairs(seen) do n += 1 end
	ok(n >= 199, "[L4] the hash spreads (" .. n .. " distinct of 200)")
	ok(not has(fs.readFile("shared/TerrainArt.lua"), "* 1274126177, 0xFFFFFFFF"), "[L4] no 64-bit products in the hash")
end
print(string.format("PASS C: %d world checks; %d islands; clutter %d, rocks %d, trees %d, cliff %d, satellites %d; largest ground %d / wall %d triangles; wall deviation %.1f, colour step %.3f; %d static parts.",
	checks - partC, #islands, totals.clutter, totals.rock, totals.tree, totals.cliff, totals.satellite, largestGround, largestHull, worstHullDev, worstHullDL, staticParts))

------------------------------------------------------------------------------
-- Part D: the forge's dress and ground pools.
------------------------------------------------------------------------------
local partD = checks
local Props = load("art/PropCatalog.lua")
local function forgeHarness(mobile)
	local calls = {meshes = 0, fail = false}
	local asset = {}
	function asset.CreateEditableMesh()
		calls.meshes += 1
		local mesh = {n = 0}
		function mesh.AddVertex(self) self.n += 1; return self.n end
		function mesh.AddColor() return 1 end
		function mesh.AddTriangle() return 1 end
		function mesh.SetFaceColors() end
		function mesh.AddNormal() return 1 end
		function mesh.SetFaceNormals() end
		function mesh.Destroy() end
		return mesh
	end
	function asset.CreateMeshPartAsync()
		if calls.fail then error("simulated failure") end
		return roblox.Instance.new("MeshPart")
	end
	local tokens = {AetherWorldArt = "world", AetherArt = "props", AetherTerrainArt = "terrain"}
	local services = {AssetService = asset, ReplicatedStorage = {WaitForChild = function(_, name) return tokens[name] end},
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return {CFrame = CFrame.new()} end}}},
		UserInputService = {TouchEnabled = mobile, KeyboardEnabled = not mobile}}
	local test = {}
	local clock = 0
	load("forge.client.lua", {
		game = {GetService = function(_, name) return services[name] end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		require = function(token) return ({world = World, props = Props, terrain = Catalog})[token] or error("module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else f(...) end end, defer = function() end, wait = function() end},
		warn = function() end, print = function() end, os = {clock = function() return clock end},
	})
	return test.forge, calls, function(t) clock = t end
end
do
	local forge, calls = forgeHarness(false)
	local api = forge.dress
	local clone, token, extent, centre = api.visual("BroadleafTree", Color3.fromHex("5E9C4C"))
	ok(clone and clone:IsA("MeshPart") and token and extent.Magnitude > 5 and centre ~= nil, "a dressing clone, token, extent, centre")
	ok(clone.CanCollide == false and clone.CanQuery == false and clone.CanTouch == false, "dressing clones never collide or query")
	eq(clone:GetAttribute("ShapeOf"), "BroadleafTree", "clones name their shape (sway lookup)")
	eq(forge.stats.instances, 0, "dressing never counts as world instances")
	local _, t2 = api.visual("BroadleafTree", Color3.fromHex("6FAA55"))
	local _, t3 = api.visual("BroadleafTree", Color3.fromHex("C9752F"))
	eq(forge.stats.dressTemplates, 2, "[H1] desktop keeps <= 2 tint templates per dressing shape (a third tint reuses the nearest)")
	ok(api.release(token) and api.release(t2) and api.release(t3), "release")
	eq(api.visual("Boulder", nil), nil, "world props are not dressing")
	ok(has(forgeSource, 'skip(part, "dress shape", true)'), "Shape tags never forge dressing")
	-- Ground pool: flat arrays, a cap with a budget refusal, release.
	local desc = T.collect(built.islands:FindFirstChild("Mosswake Grove"), nil)
	local spec = T.ground(desc, T.Budgets.High.cell)
	local part, gtoken, gcentre = api.ground(spec)
	ok(part and part:IsA("MeshPart") and gtoken and gcentre and part.CanCollide == false, "a forged ground top from flat arrays")
	local held = {gtoken}
	for _ = 2, api.groundCap do local _, t = api.ground(T.hull(desc, 7, 28)); if t then table.insert(held, t) end end
	local none, reason = api.ground(spec)
	ok(none == nil and reason == "budget", "the ground cap refuses with budget")
	for _, t in ipairs(held) do api.groundRelease(t) end
	eq(forge.stats.grounds, 0, "grounds returned")
end
do
	-- H2: ground failures count on their own: a failing ground never stops the dressing.
	local forge, calls = forgeHarness(false)
	local tiny = {positions = {0, 0, 0, 1, 0, 0, 0, 0, 1}, colors = {1, 1, 1, 1, 1, 1, 1, 1, 1}, normals = {0, 1, 0, 0, 1, 0, 0, 1, 0}, indices = {1, 3, 2}}
	calls.fail = true
	for _ = 1, 3 do
		local p, r = forge.dress.ground(tiny)
		ok(p == nil and r == "failed", "[H2] a failing ground says failed")
	end
	eq(forge.dress.groundPool.stop, "unavailable", "[H2] grounds stop after their own failures")
	eq(forge.dress.pool.failures, 0, "[H2] ground failures never count against the dressing")
	calls.fail = false
	ok(forge.dress.visual("GrassTuft", nil) ~= nil, "[H2] the dressing keeps forging")
	local p, r = forge.dress.ground(tiny)
	ok(p == nil and r == "unavailable", "[H2] a stopped ground pool refuses")
end
do
	-- M7: phones: 12 dress templates; a blocked pool recovers after BLOCK_RETRY.
	local phone, _, setClock = forgeHarness(true)
	eq(phone.dress.cap, 12, "[M7] phone dress template cap")
	local _, a = phone.dress.visual("GrassTuft", Color3.fromHex("6FA956"))
	local _, b = phone.dress.visual("GrassTuft", Color3.fromHex("7DB35C"))
	ok(a and b and phone.stats.dressTemplates == 1, "phones share one tint variant per shape")
	phone.dress.pool.blocked, phone.dress.pool.blockedAt = true, 0
	setClock(10)
	local none, reason = phone.dress.visual("Pebbles", nil)
	ok(none == nil and reason == "unavailable", "[M7] a blocked pool refuses")
	setClock(phone.dress.blockRetry + 1)
	ok(phone.dress.visual("Pebbles", nil) ~= nil and phone.dress.pool.blocked == false, "[M7] a blocked pool recovers after its retry time")
end
ok(has(forgeSource, 'local DRESS_ROOT = "IsleDressing"') and has(forgeSource, "if parent and (parent.Name == DRESS_ROOT"), "[M6] the forge never watches the dressing root")
print(string.format("PASS D: %d forge pool checks.", checks - partD))

------------------------------------------------------------------------------
-- Part E: terrain.client.lua headless against the built world.
------------------------------------------------------------------------------
local partE = checks
local world = built.world
local tokens, placedLive, groundLive = 0, {}, {}
local refuseShape, groundReply = {}, nil
local invokes = {dress = {}, ground = 0}
local forgeApi = {Name = "MeshForgeLocal", Parent = true}
function forgeApi.Invoke(_, method, arg)
	if method == "dress" then
		invokes.dress[arg.shape] = (invokes.dress[arg.shape] or 0) + 1
		if refuseShape[arg.shape] then return nil, "budget" end
		assert(Catalog.shapes[arg.shape], "unknown " .. tostring(arg.shape))
		tokens += 1
		local clone = roblox.Instance.new("MeshPart")
		clone:SetAttribute("ShapeOf", arg.shape)
		placedLive[tokens] = clone
		return clone, tokens, Vector3.new(2, 4, 2), Vector3.new(0, 2, 0)
	elseif method == "dressRelease" then
		if placedLive[arg] then placedLive[arg]:Destroy(); placedLive[arg] = nil end
		return true
	elseif method == "ground" then
		invokes.ground += 1
		if groundReply then return nil, groundReply end
		ok(type(arg.positions) == "table" and type(arg.indices) == "table" and #arg.positions % 3 == 0, "[M6] grounds travel as flat arrays")
		tokens += 1
		local part = roblox.Instance.new("MeshPart")
		groundLive[tokens] = part
		return part, tokens, Vector3.new(0, 0, 0)
	elseif method == "groundRelease" then
		if groundLive[arg] then groundLive[arg]:Destroy(); groundLive[arg] = nil end
		return true
	end
end
local hrp = {CFrame = CFrame.new(-230, 3, 0)} -- Mosswake Grove
local player = {attributes = {IsleSettingGraphics = "High"}, Character = {FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then hrp else nil end}}
function player:GetAttribute(k) return self.attributes[k] end
local rs = {FindFirstChild = function(_, n) return if n == "MeshForgeLocal" then forgeApi else nil end, WaitForChild = function(_, n) return n end}
local services = {Players = {LocalPlayer = player}, ReplicatedStorage = rs, UserInputService = {TouchEnabled = false, KeyboardEnabled = true}, RunService = {}}
local test, hidden = {}, {}
local source = clientSource:gsub("pcall%(function%(%) part%.LocalTransparencyModifier = value end%)", "HIDE(part, value)")
ok(source ~= clientSource, "the hide hook is found")
local env = {
	game = {GetService = function(_, n) return services[n] end},
	workspace = world, script = {Destroying = {Once = function() end}},
	require = function(n) return if n == "AetherTerrain" then T elseif n == "AetherData" then Data else error(n) end,
	IsleTerrainTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum,
	warn = function(...) error(table.concat({...}, " ")) end, HIDE = function(part, v) hidden[part] = v end,
}
luau.load(source, {debugName = "terrain.client.lua", environment = env, injectGlobals = true})()
local Terrain = test.terrain
ok(Terrain ~= nil, "terrain.client.lua exposes its test hook")
local clock = 100
Terrain.setClock(function() return clock end)
local function steps(n, dt) for _ = 1, n do clock += dt or 1.1; Terrain.step() end end
local count = 0
for _ in pairs(Terrain.islands) do count += 1 end
eq(count, #islands, "every island is watched")
-- H3: the first plan waits for a quiet model.
local mosswake = built.islands:FindFirstChild("Mosswake Grove")
local mstate = Terrain.islands[mosswake]
mstate.changedAt = clock + 5
Terrain.step()
ok(mstate.desc == nil, "[H3] no plan while the island is still changing")
clock += 6
steps(24)
ok(mstate.desc ~= nil, "[H3] planned once quiet")
local root = world:FindFirstChild("IsleDressing")
ok(root ~= nil and root:FindFirstChild("Sway") ~= nil, "the local dressing root and its sway links")
local function census()
	local per = {}
	for item, rec in pairs(Terrain.placed) do
		local class = if item.class == "tree" then (if rec.shape == item.far then "far" else "near") else item.class
		per[class] = (per[class] or 0) + 1
		ok(rec.clone.CanCollide == false and rec.clone.CanQuery == false and rec.clone.CanTouch == false, "dressing never collides")
	end
	return per
end
local per = census()
for class, n in pairs(per) do ok(n <= T.Budgets.High[class], "High " .. class .. " " .. n .. " <= " .. T.Budgets.High[class]) end
ok((per.clutter or 0) >= 60 and (per.cliff or 0) >= 10 and (per.satellite or 0) >= 2 and ((per.near or 0) + (per.far or 0)) >= 3, "High dresses the island")
eq(hidden[mosswake.Meadow], 1, "the meadow is hidden locally under its forged ground")
eq(hidden[mosswake:FindFirstChild("Floating foundation")], 1, "the foundation is hidden locally behind the forged wall")
local g = Terrain.grounds[mstate]
ok(g and g.groundPart and g.hullPart, "a ground top and a cliff wall for the near island")
for _, link in ipairs(root.Sway:GetChildren()) do ok(A.SWAY[link.Value:GetAttribute("ShapeOf")] ~= nil, "sway links name registered shapes") end
-- H4: a hide undone elsewhere is re-asserted; a lost ground part releases its record.
hidden[mosswake.Meadow] = 0
steps(1)
eq(hidden[mosswake.Meadow], 1, "[H4] the meadow hide is re-asserted each cycle")
g.groundPart:Destroy()
steps(1)
ok(Terrain.grounds[mstate] == nil or Terrain.grounds[mstate].groundPart ~= g.groundPart, "[H4] a lost ground part releases its record")
eq(hidden[mosswake.Meadow], 0, "[H4] the meadow comes back with it")
-- M3: a clone re-seated when its ground goes publishes its rest frame.
local reseated = 0
for item, rec in pairs(Terrain.placed) do
	if item.island == mstate and rec.link and rec.clone:GetAttribute("SwayRest") ~= nil then reseated += 1 end
end
ok(reseated > 0, "[M3] re-seated swaying clones carry SwayRest (" .. reseated .. ")")
ok(has(fs.readFile("ambience.client.lua"), 'part:GetAttribute("SwayRest")'), "[M3] the sway layer re-arms on SwayRest")
-- H2: a refused ground backs off per island; a failed one is never retried; a tier change clears.
steps(70, 1)
local function groundInvokesOver(n) local before = invokes.ground; steps(n, 1); return invokes.ground - before end
Terrain.releaseGround(mstate)
groundReply = "budget"
local firstTry = groundInvokesOver(1)
local during = groundInvokesOver(1)
ok(firstTry >= 1 and during == 0, "[H2] a refused ground backs off (no retry next cycle)")
groundReply = "failed"
steps(70, 1)
local afterFail = groundInvokesOver(70)
ok(afterFail <= 1, "[H2] a failed ground is not retried for that cell (" .. afterFail .. ")")
groundReply = nil
player.attributes.IsleSettingGraphics = "Balanced"
steps(2)
ok(Terrain.grounds[mstate] ~= nil, "[H2] a tier change clears the ground backoffs")
-- H1: a refused shape backs off on its own; the rest keep placing, far-seen classes first.
Terrain.resetAll()
player.attributes.IsleSettingGraphics = "High"
steps(1)
refuseShape.GrassTuft = true
local before = invokes.dress.GrassTuft or 0
Terrain.resetAll()
Terrain.tierKey = "High"
Terrain.step()
local tried = (invokes.dress.GrassTuft or 0) - before
ok(tried == 1, "[H1] a refused shape is tried once, then backs off (" .. tried .. ")")
local others = 0
for item in pairs(Terrain.placed) do if item.class == "clutter" and item.shape ~= "GrassTuft" then others += 1 end end
ok(others > 0, "[H1] the rest keep placing past a refusal")
local firstVisible = T.visible(mstate.items, "High", {-230, 3, 0}, false)
eq(firstVisible[1].class, "satellite", "[H1] satellites first")
refuseShape.GrassTuft = nil
-- H3: a part added to the island blocks the dressing around it (after quiet); a removal re-plans.
steps(3)
local victim
for item in pairs(Terrain.placed) do if item.island == mstate and item.class == "clutter" then victim = item break end end
ok(victim ~= nil, "a placed clutter item to cover")
local crate = roblox.Instance.new("Part")
crate.Name, crate.Size, crate.CFrame = "Story crate", Vector3.new(6, 4, 6), CFrame.new(victim.x, mstate.desc.top + 2, victim.z)
crate.Parent = mosswake
table.insert(mstate.added, crate)
mstate.changedAt = clock
Terrain.step()
ok(Terrain.placed[victim] ~= nil, "[H3] nothing moves while the island is still changing")
steps(2)
ok(Terrain.placed[victim] == nil and table.find(mstate.items, victim) == nil, "[H3] a new part clears the dressing under it")
local plans = Terrain.stats.plans
crate:Destroy()
mstate.needPlan, mstate.changedAt = true, clock
steps(2)
ok(Terrain.stats.plans > plans, "[H3] a removal re-plans the island once quiet")
-- LODs: near within nearRadius, far beyond.
steps(4)
local near, far = 0, 0
for item, rec in pairs(Terrain.placed) do if item.class == "tree" then if rec.shape == item.far then far += 1 else near += 1 end end end
ok(near <= T.Budgets.High.near and far <= T.Budgets.High.far, "near / far tree LOD caps")
-- Far away: everything but far-LOD satellites is released.
hrp.CFrame = CFrame.new(5000, 0, 5000)
steps(3)
eq(Terrain.stats.placed, 0, "nothing stays placed far from every island")
local live = 0
for _ in pairs(placedLive) do live += 1 end
eq(live, 0, "every dress token returned")
-- L2: a removed island drops its signals and dressing.
do
	local fake = {Disconnect = function(self) self.gone = true end}
	mstate.conns = {fake}
	local saved = mosswake.Parent
	mosswake.Parent = nil
	Terrain.step()
	ok(fake.gone == true and Terrain.islands[mosswake] == nil, "[L2] a removed island disconnects its signals")
	mosswake.Parent = saved
	Terrain.scanIslands()
end
-- M6: work pauses inside a coroutine once its slice is spent.
do
	local co = coroutine.create(function() clock += 1; Terrain.pause(); return "done" end)
	Terrain.setWorker(co)
	local _, first = coroutine.resume(co)
	ok(coroutine.status(co) == "suspended" and first == nil, "[M6] a long cycle yields to the next frame")
	coroutine.resume(co)
	ok(coroutine.status(co) == "dead", "[M6] and resumes")
	Terrain.setWorker(nil)
	ok(has(clientSource, "RunService.Heartbeat:Connect") and has(clientSource, "local SLICE_SECONDS = 0.002"), "[M6] cycles run in 2 ms slices per frame")
	local yields = 0
	local d2 = T.collect(built.islands:FindFirstChild("Meadow Reach"), nil)
	T.ground(d2, 4.5, function() yields += 1 end)
	ok(yields > 0, "[M6] ground building offers yield points")
end
Terrain.resetAll()
local project = fs.readFile("default.project.json")
ok(has(project, '"AetherTerrainArt": { "$path": "art/TerrainCatalog.lua" }') and has(project, '"AetherTerrain": { "$path": "shared/TerrainArt.lua" }')
	and has(project, '"IsleTerrain": { "$path": "terrain.client.lua" }'), "project wiring")
ok(has(forgeSource, '"AetherTerrainArt"'), "the forge loads the terrain catalog")
ok(has(fs.readFile("ambience.client.lua"), '"IsleDressing"'), "the ambience layer scans the dressing root for sway")
for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-environment.luau"), script .. " runs this suite") end
print(string.format("PASS E: %d client checks.", checks - partE))
print(string.format("Environment QA passed %d checks.", checks))
print("SUITE-END verify-environment.luau")

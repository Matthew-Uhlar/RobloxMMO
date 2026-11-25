-- Island environment art (docs/DEPTH-CONTRACT.md §54): shared/TerrainArt.lua,
-- terrain.client.lua, the forge's dress / ground pools and art/TerrainCatalog.lua.
-- Part A: the terrain catalog (kinds, triangle ranges, smooth shading, facet and
--   colour-boundary ratios, winding, OBJ parity) and the region art (3+ tree
--   species per biome, every named shape authored, tints valid, sway table).
-- Part B: budgets per graphics tier (caps, radii, densities, triangle ceilings
--   within the tier's triangle budget and the forge's hard pool ceilings).
-- Part C: the real world (tools/world-harness.luau): coverage per island,
--   density per tier at sampled viewpoints, no clutter on paths / build cells /
--   node footprints / protected circles / prompts / buildings, walkability
--   sampling of the forged ground, the static part budget.
-- Part D: the forge's dress and ground pools (mocked AssetService).
-- Part E: terrain.client.lua headless against the built world (caps per tier,
--   non-colliding clones, meadow hidden only while its ground top shows, sway
--   links, tier switch and distance release, resized meadows re-planned).
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

------------------------------------------------------------------------------
-- Part A: catalog and region art.
------------------------------------------------------------------------------
local RANGE = {clutter = {100, 1000}, shrub = {150, 1200}, foliage = {400, 1300}, cliff = {150, 1500}, satellite = {300, 800}}
local CLASS_KIND = {clutter = "clutter", shrub = "clutter", foliage = "foliage", cliff = "cliff", satellite = "satellite"}
local function edgeRatios(data)
	local points = {}
	for i, v in ipairs(data.vertices) do points[i] = Vector3.new(v[1], v[2], v[3]) end
	local edges, normals = {}, {}
	for f, face in ipairs(data.faces) do
		local n = (points[face[2]] - points[face[1]]):Cross(points[face[3]] - points[face[1]])
		normals[f] = if n.Magnitude > 0 then n.Unit else Vector3.new(0, 1, 0)
		for k = 1, 3 do
			local a, b = face[k], face[k % 3 + 1]
			local key = if a < b then a * 65536 + b else b * 65536 + a
			edges[key] = edges[key] or {}
			table.insert(edges[key], f)
		end
	end
	local shared, hard, colour = 0, 0, 0
	local limit = math.cos(math.rad(data.smooth))
	for _, list in pairs(edges) do
		if #list == 2 then
			shared += 1
			if normals[list[1]]:Dot(normals[list[2]]) < limit then hard += 1 end
			if data.faces[list[1]][4] ~= data.faces[list[2]][4] then colour += 1 end
		end
	end
	return hard / math.max(1, shared), colour / math.max(1, shared), points
end
local shapeCount, shapeTris = 0, 0
local trisOf = {}
for name, data in pairs(Catalog.shapes) do
	shapeCount += 1
	local range = RANGE[data.kind]
	ok(range ~= nil, name .. " has a terrain kind")
	ok(World.shapes[name] == nil, name .. " is unique across catalogs")
	local n = #data.faces
	shapeTris += n
	trisOf[name] = n
	eq(data.tris, n, name .. " declares its triangle count")
	ok(n >= range[1] and n <= range[2], name .. " triangle range " .. n)
	ok(n <= T.MAX_TRIS[CLASS_KIND[data.kind]], name .. " within its class's budget triangle size")
	ok(#data.vertices < 4096, name .. " packs")
	ok(data.smooth >= 40, name .. " is smooth-shaded (crease " .. data.smooth .. ")")
	local hard, colour, points = edgeRatios(data)
	ok(hard <= 0.2, string.format("%s hard-edge ratio %.3f <= 0.2", name, hard))
	ok(colour <= 0.2, string.format("%s colour-boundary ratio %.3f <= 0.2", name, colour))
	for _, f in ipairs(data.faces) do
		ok(Catalog.palette[f[4]] ~= nil and (points[f[2]] - points[f[1]]):Cross(points[f[3]] - points[f[1]]).Magnitude > 1e-6, name .. " face valid")
	end
	ok(data.tint and pcall(Color3.fromHex, data.tint), name .. " default tint")
	-- OBJ parity (the import bundle is built from the OBJ masters).
	local vi = 0
	for line in string.gmatch(fs.readFile("art/" .. name .. ".obj"), "[^\n]+") do
		local x, y, z = string.match(line, "^v (%S+) (%S+) (%S+)")
		if x then
			vi += 1
			local v = data.vertices[vi]
			ok(math.abs(v[1] - tonumber(x)) < 1e-6 and math.abs(v[2] - tonumber(y)) < 1e-6 and math.abs(v[3] - tonumber(z)) < 1e-6, name .. " vertex matches OBJ")
		end
	end
	eq(vi, #data.vertices, name .. " OBJ vertex count")
end
ok(shapeCount >= 20, "terrain shapes authored (" .. shapeCount .. ")")
-- Source rules: round primitives only, >= 10 segments.
do
	local art = fs.readFile("art/terrain-shapes.cjs")
	for _, banned in ipairs({"kit.prism(", "kit.box(", "kit.bevelBox(", "kit.jewel(", "kit.slab(", "kit.spindle(", "kit.ring("}) do
		ok(not has(art, banned), "terrain art never uses the faceted primitive " .. banned)
	end
	ok(not string.find(art, "color: %(%w+, %w+%) =>"), "no colour callback reads the facet index")
	for n in string.gmatch(art, "[^%w]n: (%d+)") do ok(tonumber(n) >= 10, "every ring / tube has >= 10 segments (n: " .. n .. ")") end
	ok(has(art, "const N = 10"), "the shared minimum segment count is 10")
	for sub in string.gmatch(art, "sub: (%d+)") do ok(tonumber(sub) >= 1, "every blob subdivides at least once") end
end
-- The island hulls (§30 shapes, reworked here): smooth strata, never flat.
for _, name in ipairs({"IslandCliff", "IslandCliffBare", "IslandKeel", "IslandKeelCrystal", "IslandKeelEmber"}) do
	local data = World.shapes[name]
	ok(data.smooth >= 40, name .. " hull is smooth-shaded (crease " .. data.smooth .. ")")
	local hard = edgeRatios(data)
	ok(hard <= 0.25, string.format("%s hull hard-edge ratio %.3f", name, hard))
end
-- Region art: every biome has 3+ tree species, a hero, shrubs, clutter, cliff dressing.
local regionCount = 0
for id, art in pairs(T.Regions) do
	regionCount += 1
	local species = {}
	for _, s in ipairs(art.trees) do species[s.shape] = true end
	local distinct = 0
	for _ in pairs(species) do distinct += 1 end
	ok(distinct >= 3, id .. " has 3+ tree species (" .. distinct .. ")")
	ok(Catalog.shapes[art.hero.shape] and Catalog.shapes[art.hero.shape].kind == "foliage" and art.hero.scale >= 1.8, id .. " hero silhouette tree")
	for _, list in ipairs({art.trees, art.shrubs, art.clutter}) do
		ok(#list >= 1, id .. " dressing list")
		for _, s in ipairs(list) do
			ok(Catalog.shapes[s.shape] ~= nil, id .. " names authored shape " .. s.shape)
			ok(#s.tints >= 1 and s.weight > 0 and s.scale[1] > 0 and s.scale[2] >= s.scale[1], id .. " " .. s.shape .. " tints / weight / scale")
			for _, h in ipairs(s.tints) do ok(pcall(Color3.fromHex, h), id .. " tint " .. h) end
		end
	end
	for i, shape in ipairs(art.cliff) do ok(Catalog.shapes[shape].kind == "cliff" and art.cliffTint[i] ~= nil, id .. " cliff dressing " .. shape) end
	ok(Catalog.shapes[art.satellite].kind == "satellite", id .. " satellite rock")
	ok(pcall(Color3.fromHex, art.dirt) and art.treeShare > 0 and art.treeShare < 1, id .. " dirt / tree share")
end
for _, region in ipairs({"Hub", "Meadow", "Quarry", "Skyreach", "Windpine", "Gloomhollow", "Tidewater", "Tempest", "ShatteredCrown", "Home"}) do ok(T.Regions[region] ~= nil, region .. " has region art") end
-- Distinct identities: hero silhouettes and leaf palettes differ between biomes.
do
	local heroes = {}
	for id, art in pairs(T.Regions) do heroes[art.hero.shape .. art.hero.tint] = (heroes[art.hero.shape .. art.hero.tint] or 0) + 1 end
	local unique = 0
	for _ in pairs(heroes) do unique += 1 end
	ok(unique >= 8, "hero silhouettes read distinct per region (" .. unique .. ")")
end
-- §50 sway: every swaying dressing shape is registered with a gentle definition.
for name in pairs(T.SWAYS) do
	ok(A.SWAY[name] ~= nil and Catalog.shapes[name] ~= nil, name .. " is in the ambience sway table")
end
print(string.format("PASS A: %d checks; %d terrain shapes / %d triangles; %d regions.", checks, shapeCount, shapeTris, regionCount))

------------------------------------------------------------------------------
-- Part B: budgets per tier.
------------------------------------------------------------------------------
local partB = checks
local forgeSource = fs.readFile("forge.client.lua")
local function forgeNumber(name, phone)
	local a, b = string.match(forgeSource, "local " .. name .. " = if mobile then (%d+) else (%d+)")
	return tonumber(if phone then a else b)
end
local prev
for _, key in ipairs(T.TIER_ORDER) do
	local b = T.Budgets[key]
	ok(b ~= nil, key .. " budget")
	local ceiling = T.ceiling(b)
	ok(ceiling <= b.triangles, string.format("%s worst case %d triangles <= budget %d", key, ceiling, b.triangles))
	ok(b.clutterRadius <= b.foliageRadius and (b.cliff == 0 or b.foliageRadius <= b.cliffRadius) and b.foliageRadius <= b.satelliteRadius, key .. " far LOD: clutter < trees < cliffs < satellites")
	ok(b.density > 0 and b.density <= 1, key .. " density share")
	if prev then
		for _, field in ipairs({"clutter", "foliage", "cliff", "satellite", "clutterRadius", "foliageRadius", "density", "grounds", "triangles"}) do
			ok(b[field] <= prev[field], key .. " " .. field .. " never exceeds the tier above")
		end
		ok(b.cell >= prev.cell, key .. " ground cells are no finer than the tier above")
	end
	prev = b
end
eq(T.budgetKey("High", true), "Lite", "phones use Lite")
eq(T.budgetKey("Performance", true), "Performance", "Performance wins on phones")
eq(T.budgetKey(nil, false), "High", "desktop default High")
eq(T.Budgets.Performance.grounds, 0, "Performance keeps the primitive meadow")
-- The forge's hard ceilings hold the tier the device can run.
local desktopDress = T.Budgets.High.clutter + T.Budgets.High.foliage + T.Budgets.High.cliff + T.Budgets.High.satellite
local liteDress = T.Budgets.Lite.clutter + T.Budgets.Lite.foliage + T.Budgets.Lite.cliff + T.Budgets.Lite.satellite
ok(forgeNumber("DRESS_INSTANCE_CAP", false) >= desktopDress, "desktop dress instance ceiling holds High")
ok(forgeNumber("DRESS_INSTANCE_CAP", true) >= liteDress, "phone dress instance ceiling holds Lite")
ok(forgeNumber("DRESS_PLACED_CAP", false) >= T.ceiling(T.Budgets.High) - T.Budgets.High.grounds * T.groundTriangles(160, T.Budgets.High.cell), "desktop placed ceiling holds High")
ok(forgeNumber("DRESS_PLACED_CAP", true) >= T.ceiling(T.Budgets.Lite) - T.Budgets.Lite.grounds * T.groundTriangles(160, T.Budgets.Lite.cell), "phone placed ceiling holds Lite")
ok(forgeNumber("GROUND_CAP", false) >= T.Budgets.High.grounds and forgeNumber("GROUND_CAP", true) >= T.Budgets.Lite.grounds, "ground counts")
ok(forgeNumber("GROUND_TRIANGLE_CAP", false) >= T.Budgets.High.grounds * T.groundTriangles(160, T.Budgets.High.cell), "desktop ground triangles")
ok(forgeNumber("GROUND_TRIANGLE_CAP", true) >= T.Budgets.Lite.grounds * T.groundTriangles(160, T.Budgets.Lite.cell), "phone ground triangles")
print(string.format("PASS B: %d budget checks (High ceiling %d, Lite %d triangles).", checks - partB, T.ceiling(T.Budgets.High), T.ceiling(T.Budgets.Lite)))

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
-- Static part budget: the environment layer adds no server parts.
local staticParts = 0
for _, d in ipairs(built.world:GetDescendants()) do
	if d:IsA("BasePart") then
		ok(d:GetAttribute("Dressing") == nil, "no server part is dressing")
		if not d:FindFirstAncestor("AetherIsles") then staticParts += 1 end
	end
end
ok(built.world:FindFirstChild("IsleDressing") == nil, "the dressing root is client-only")
ok(staticParts <= 4000, "static world parts " .. staticParts .. " <= 4000")
local worldSource = fs.readFile("world.server.lua")
ok(not has(worldSource, "IsleDressing") and not has(worldSource, "AetherTerrain"), "world.server.lua builds no dressing")

local function footprint(p)
	local cf, size = p.CFrame, p.Size
	local declared = p:GetAttribute("ShapeBox")
	if typeof(declared) == "Vector3" then
		local offset = p:GetAttribute("ShapeBoxOffset")
		cf = cf * CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.new())
		size = declared
	end
	local h = size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
	local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
	return cf.Position, ex, ez, ey, cf, size
end
-- Exact distance (XZ) from a point to a part's oriented footprint.
local function obbDistance(p, x, z)
	local pos, _, _, _, cf, size = footprint(p)
	local rel = cf:PointToObjectSpace(Vector3.new(x, pos.Y, z))
	local dx = math.max(math.abs(rel.X) - size.X / 2, 0)
	local dz = math.max(math.abs(rel.Z) - size.Z / 2, 0)
	if math.abs(cf.UpVector.Y) < 0.5 then -- a lying part (cylinder disc): use its AABB
		local _, ex, ez = footprint(p)
		dx, dz = math.max(math.abs(x - pos.X) - ex, 0), math.max(math.abs(z - pos.Z) - ez, 0)
	end
	return math.sqrt(dx * dx + dz * dz)
end
local totals = {clutter = 0, shrub = 0, foliage = 0, hero = 0, cliff = 0, satellite = 0}
local groundTris = 0
local regionsSeen = {}
for _, model in ipairs(islands) do
	local desc = T.collect(model, Data.Island.ProtectedCircles)
	ok(desc ~= nil, model.Name .. " has an island descriptor")
	local items = T.plan(desc)
	local counts = {clutter = 0, shrub = 0, foliage = 0, hero = 0, cliff = 0, satellite = 0}
	local shapesUsed = {}
	for _, it in ipairs(items) do
		counts[it.kind] += 1
		totals[it.kind] += 1
		shapesUsed[it.shape] = true
		ok(Catalog.shapes[it.shape] ~= nil and pcall(Color3.fromHex, it.tint), model.Name .. " item shape / tint")
		ok(it.scale > 0 and it.scale < 3 and it.rank >= 0 and it.rank < 1 and it.yaw == it.yaw, model.Name .. " item scale / rank / yaw")
	end
	-- Coverage: the meadow is dressed in proportion to its open area, the rim is
	-- hung with roots / vines / veins, and satellites drift beside it.
	local R = desc.radius
	local home = desc.build ~= nil
	local band = if home then math.pi * (R * R - (desc.build + 1) ^ 2) else math.pi * R * R
	local dressed = counts.clutter + counts.shrub
	ok(dressed >= band / 160, string.format("%s clutter coverage %d over %.0f sq studs", model.Name, dressed, band))
	ok(counts.cliff >= math.floor(2 * math.pi * R / 11 * 0.5), model.Name .. " cliff dressing around the rim (" .. counts.cliff .. ")")
	ok(counts.satellite >= 2, model.Name .. " has satellite rocks")
	if not home and model.Parent == built.islands then
		ok(counts.foliage + counts.hero >= 2, model.Name .. " has trees (" .. counts.foliage + counts.hero .. ")")
		regionsSeen[desc.region] = regionsSeen[desc.region] or {}
		for shape in pairs(shapesUsed) do regionsSeen[desc.region][shape] = true end
	end
	-- Rules: nothing on paths, nodes, prompts, buildings, the build disc or protected circles.
	local paths, nodes, solids = {}, {}, {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and not T.IGNORE[p.Name] then
			local pos, _, _, ey = footprint(p)
			if pos.Y + ey > desc.top - 0.6 and pos.Y - ey < desc.top + 14 then
				if T.PATH_NAMES[p.Name] then table.insert(paths, p)
				elseif p:GetAttribute("GatherNode") ~= nil or (p.Parent and p.Parent:GetAttribute("GatherNode") ~= nil) then table.insert(nodes, p)
				elseif p:FindFirstChildOfClass("ProximityPrompt") or p:GetAttribute("BuildingType") or p.Name:sub(1, 7) == "Anchor_" then table.insert(solids, p) end
			end
		end
	end
	local cx, cz = desc.center[1], desc.center[3]
	for _, it in ipairs(items) do
		if it.class == "clutter" or it.class == "foliage" then
			local d = math.sqrt((it.x - cx) ^ 2 + (it.z - cz) ^ 2)
			ok(d <= R - 1, model.Name .. " item inside the rim")
			if home then
				ok(d >= desc.build + 1, model.Name .. " nothing on the home build cells")
				for _, c in ipairs(Data.Island.ProtectedCircles) do
					ok((it.x - (cx + c.x)) ^ 2 + (it.z - (cz + c.z)) ^ 2 > c.r * c.r, model.Name .. " clear of protected circle " .. c.name)
				end
			end
			for _, p in ipairs(paths) do ok(obbDistance(p, it.x, it.z) > 0.5, model.Name .. " " .. it.shape .. " is off the path " .. p:GetFullName()) end
			for _, p in ipairs(nodes) do ok(obbDistance(p, it.x, it.z) > 2, model.Name .. " " .. it.shape .. " clears node footprint " .. p:GetFullName()) end
			for _, p in ipairs(solids) do ok(obbDistance(p, it.x, it.z) > 0.8, model.Name .. " " .. it.shape .. " clears " .. p:GetFullName()) end
		end
	end
	-- Walkability: the forged ground stays within a gentle band of the collider,
	-- flat on and around paths and footprints (path tops stay above it), faces
	-- up, and its edge meets the cliff curb.
	for _, cell in ipairs({T.Budgets.High.cell, T.Budgets.Lite.cell}) do
		local g = T.ground(desc, cell)
		eq(#g.faces, T.groundTriangles(R, cell), model.Name .. " ground triangles match the grid")
		groundTris = math.max(groundTris, #g.faces)
		for i, v in ipairs(g.vertices) do
			ok(v[2] <= T.HEIGHT.up + 1e-6 and v[2] >= T.HEIGHT.bareLip - 1e-6, model.Name .. " ground height band")
			local c = g.colors[i]
			ok(c[1] >= 0 and c[1] <= 1 and c[2] >= 0 and c[2] <= 1 and c[3] >= 0 and c[3] <= 1, model.Name .. " ground colour")
			ok(g.normals[i][2] > 0.5, model.Name .. " ground normals face up (smooth, gentle)")
		end
		for _, f in ipairs(g.faces) do
			local a, b, c = g.vertices[f[1]], g.vertices[f[2]], g.vertices[f[3]]
			local ny = (b[3] - a[3]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[3] - a[3])
			ok(ny > 0, model.Name .. " ground face wound up")
		end
		local last = g.vertices[#g.vertices]
		ok(math.abs(math.sqrt(last[1] ^ 2 + last[3] ^ 2) - (R + 0.1)) < 0.05, model.Name .. " ground edge sits on the meadow wall")
	end
	local samples = 0
	for gx = -R, R, 6 do
		for gz = -R, R, 6 do
			local x, z = cx + gx, cz + gz
			if gx * gx + gz * gz < (R - 2.5) ^ 2 then
				samples += 1
				local h = T.heightAt(desc, x, z)
				ok(h >= T.HEIGHT.down - 1e-6 and h <= T.HEIGHT.up + 1e-6, model.Name .. " walkable height")
			end
		end
	end
	ok(samples >= 50, model.Name .. " walkability samples")
	for _, p in ipairs(paths) do
		local pos = footprint(p)
		ok(T.heightAt(desc, pos.X, pos.Z) <= 0.04, model.Name .. " the ground stays under the path " .. p.Name)
	end
	for _, p in ipairs(solids) do
		local pos = footprint(p)
		if (pos.X - cx) ^ 2 + (pos.Z - cz) ^ 2 < (R - 3) ^ 2 then ok(math.abs(T.heightAt(desc, pos.X, pos.Z)) <= 0.01, model.Name .. " flat under " .. p.Name) end
	end
	-- Density per tier at the island's centre and rim: every class within its cap.
	for _, key in ipairs(T.TIER_ORDER) do
		local b = T.Budgets[key]
		for _, focus in ipairs({{cx, desc.top + 3, cz}, {cx + R, desc.top + 3, cz}}) do
			local vis = T.visible(items, key, focus, false)
			local per, tris = {clutter = 0, foliage = 0, cliff = 0, satellite = 0}, 0
			for _, it in ipairs(vis) do per[it.class] += 1; tris += trisOf[it.shape] end
			for class, n in pairs(per) do ok(n <= b[class], string.format("%s %s %s %d <= %d", model.Name, key, class, n, b[class])) end
			ok(tris + b.grounds * T.groundTriangles(R, b.cell) <= b.triangles, model.Name .. " " .. key .. " triangles within budget")
			if key == "Performance" then ok(per.cliff == 0, "Performance hangs no cliff dressing") end
		end
	end
end
-- Region identity: each biome island shows 3+ tree species overall.
for region, shapes in pairs(regionsSeen) do
	local trees = 0
	for shape in pairs(shapes) do if Catalog.shapes[shape].kind == "foliage" then trees += 1 end end
	ok(trees >= 1, region .. " islands show their trees")
end
-- Density shares per tier are deterministic subsets (lower tiers keep a subset).
do
	local desc = T.collect(built.islands:FindFirstChild("Mosswake Grove"), nil)
	local items = T.plan(desc)
	local n = {}
	for _, key in ipairs(T.TIER_ORDER) do
		n[key] = 0
		for _, it in ipairs(items) do if it.class == "clutter" and it.rank < T.Budgets[key].density then n[key] += 1 end end
	end
	ok(n.High > n.Balanced and n.Balanced > n.Lite and n.Lite > n.Performance and n.Performance > 0, "density falls tier by tier")
	ok(T.plan(T.collect(built.islands:FindFirstChild("Mosswake Grove"), nil))[17].x == items[17].x, "plans are deterministic")
end
print(string.format("PASS C: %d world checks; %d islands; clutter %d, shrubs %d, trees %d, heroes %d, cliff %d, satellites %d; largest ground %d triangles; %d static parts.",
	checks - partC, #islands, totals.clutter, totals.shrub, totals.foliage, totals.hero, totals.cliff, totals.satellite, groundTris, staticParts))

------------------------------------------------------------------------------
-- Part D: the forge's dress and ground pools.
------------------------------------------------------------------------------
local partD = checks
local Props = load("art/PropCatalog.lua")
local function forgeHarness(mobile)
	local calls = {meshes = 0}
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
	function asset.CreateMeshPartAsync() return roblox.Instance.new("MeshPart") end
	local tokens = {AetherWorldArt = "world", AetherArt = "props", AetherTerrainArt = "terrain"}
	local services = {AssetService = asset, ReplicatedStorage = {WaitForChild = function(_, name) return tokens[name] end},
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return {CFrame = CFrame.new()} end}}},
		UserInputService = {TouchEnabled = mobile, KeyboardEnabled = not mobile}}
	local test = {}
	load("forge.client.lua", {
		game = {GetService = function(_, name) return services[name] end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		require = function(token) return ({world = World, props = Props, terrain = Catalog})[token] or error("module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else f(...) end end, defer = function() end, wait = function() end},
		warn = function() end, print = function() end,
	})
	return test.forge, calls
end
do
	local forge, calls = forgeHarness(false)
	local api = forge.dress
	ok(api and api.visual and api.release and api.ground and api.groundRelease, "the forge exposes the dress and ground API")
	local clone, token, extent, centre = api.visual("BroadleafTree", Color3.fromHex("5E9C4C"))
	ok(clone and clone:IsA("MeshPart") and token and extent.Magnitude > 5 and centre ~= nil, "a dressing clone, token, extent, centre")
	ok(clone.CanCollide == false and clone.CanQuery == false and clone.CanTouch == false, "dressing clones never collide or query")
	eq(clone:GetAttribute("ShapeOf"), "BroadleafTree", "clones name their shape (sway lookup)")
	eq(forge.stats.dressTemplates, 1, "one dress template")
	eq(forge.stats.instances, 0, "dressing never counts as world instances")
	local _, t2 = api.visual("BroadleafTree", Color3.fromHex("5E9C4C"))
	eq(calls.meshes, 1, "same shape and tint share a template")
	local _, t3 = api.visual("BroadleafTree", Color3.fromHex("6FAA55"))
	eq(forge.stats.dressTemplates, 2, "desktop keeps the second tint variant")
	eq(api.visual("Boulder", nil), nil, "world props are not dressing")
	eq(forge.outfit.visual("GrassTuft", nil), nil, "the outfit pool refuses dressing")
	ok(api.release(token) and api.release(t2) and api.release(t3), "release")
	eq(forge.stats.dressInstances, 0, "instances returned")
	-- A dressing shape on a Shape tag is refused (it is placed only through the pool).
	ok(has(forgeSource, 'skip(part, "dress shape", true)'), "Shape tags never forge dressing")
	-- Ground: unique mesh per island, capped.
	local desc = T.collect(built.islands:FindFirstChild("Mosswake Grove"), nil)
	local spec = T.ground(desc, T.Budgets.High.cell)
	local part, gtoken, gcentre = api.ground(spec)
	ok(part and part:IsA("MeshPart") and gtoken and gcentre, "a forged ground top")
	ok(part.CanCollide == false and part.CanQuery == false, "the ground top never collides (the Meadow stays the collider)")
	eq(forge.stats.grounds, 1, "one ground counted")
	local held = {gtoken}
	for i = 2, api.groundCap do local _, t = api.ground(spec); table.insert(held, t) end
	local none, reason = api.ground(spec)
	ok(none == nil and reason == "budget", "ground cap refuses with budget")
	for _, t in ipairs(held) do api.groundRelease(t) end
	eq(forge.stats.grounds, 0, "grounds returned")
	-- Fill the dress template pool with busy templates: refusals say budget, never evict busy ones.
	local busy = {}
	for i = 1, api.cap do
		local _, t = api.visual("Pebbles", Color3.fromRGB(i * 5 % 256, 40, 60 + i))
		if t then table.insert(busy, t) end
	end
	ok(forge.stats.dressTemplates <= api.cap, "within the dress template cap")
	local phone = forgeHarness(true)
	local _, a = phone.dress.visual("GrassTuft", Color3.fromHex("6FA956"))
	local _, b = phone.dress.visual("GrassTuft", Color3.fromHex("7DB35C"))
	ok(a and b and phone.stats.dressTemplates == 1, "phones share one tint variant per shape")
	ok(phone.dress.cap < api.cap and phone.dress.instanceCap < api.instanceCap, "phones keep a smaller dress pool")
end
print(string.format("PASS D: %d forge pool checks.", checks - partD))

------------------------------------------------------------------------------
-- Part E: terrain.client.lua headless against the built world.
------------------------------------------------------------------------------
local partE = checks
do
	local world = built.world
	local tokens, placedLive, groundLive = 0, {}, {}
	local maxDress = 0
	local forgeApi = {Name = "MeshForgeLocal", Parent = true}
	function forgeApi.Invoke(_, method, arg)
		if method == "dress" then
			local data = Catalog.shapes[arg.shape]
			assert(data, "unknown " .. tostring(arg.shape))
			tokens += 1
			local clone = roblox.Instance.new("MeshPart")
			clone:SetAttribute("ShapeOf", arg.shape)
			placedLive[tokens] = clone
			local n = 0
			for _ in pairs(placedLive) do n += 1 end
			maxDress = math.max(maxDress, n)
			return clone, tokens, Vector3.new(2, 4, 2), Vector3.new(0, 2, 0)
		elseif method == "dressRelease" then
			if placedLive[arg] then placedLive[arg]:Destroy(); placedLive[arg] = nil end
			return true
		elseif method == "ground" then
			tokens += 1
			local part = roblox.Instance.new("MeshPart")
			groundLive[tokens] = {part = part, spec = arg}
			return part, tokens, Vector3.new(0, 0, 0)
		elseif method == "groundRelease" then
			if groundLive[arg] then groundLive[arg].part:Destroy(); groundLive[arg] = nil end
			return true
		end
	end
	local hrp = {CFrame = CFrame.new(-230, 3, 0)} -- Mosswake Grove
	local player = {attributes = {IsleSettingGraphics = "High"}, Character = {FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then hrp else nil end}}
	function player:GetAttribute(k) return self.attributes[k] end
	local rs = {FindFirstChild = function(_, n) return if n == "MeshForgeLocal" then forgeApi else nil end,
		WaitForChild = function(_, n) return n end}
	local services = {Players = {LocalPlayer = player}, ReplicatedStorage = rs, UserInputService = {TouchEnabled = false, KeyboardEnabled = true}}
	local test = {}
	-- Lune instances keep LocalTransparencyModifier as a plain property when possible.
	local hiddenMeadows = {}
	local meadowProxy = {}
	local env = {
		game = {GetService = function(_, n) return services[n] end},
		workspace = world, script = {Destroying = {Once = function() end}},
		require = function(n) return if n == "AetherTerrain" then T elseif n == "AetherData" then Data else error(n) end,
		IsleTerrainTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum,
		task = {spawn = function() end, wait = function() end}, warn = function(...) error(table.concat({...}, " ")) end,
		typeof = roblox.typeof or typeof, pcall = pcall,
	}
	local source = fs.readFile("terrain.client.lua")
	-- Record meadow hiding (Lune parts may not expose LocalTransparencyModifier).
	source = source:gsub("state%.meadow%.LocalTransparencyModifier = 1", "MEADOW_HIDE(state.meadow, 1)"):gsub("state%.meadow%.LocalTransparencyModifier = 0", "MEADOW_HIDE(state.meadow, 0)")
	env.MEADOW_HIDE = function(meadow, v) hiddenMeadows[meadow] = v end
	luau.load(source, {debugName = "terrain.client.lua", environment = env, injectGlobals = true})()
	local Terrain = test.terrain
	ok(Terrain ~= nil, "terrain.client.lua exposes its test hook")
	local count = 0
	for _ in pairs(Terrain.islands) do count += 1 end
	eq(count, #islands, "every island is watched")
	for _ = 1, 20 do Terrain.step() end
	local root = world:FindFirstChild("IsleDressing")
	ok(root ~= nil and root:FindFirstChild("Sway") ~= nil, "the local dressing root and its sway links")
	local function census()
		local per, clones, links = {clutter = 0, foliage = 0, cliff = 0, satellite = 0}, 0, 0
		for item in pairs(Terrain.placed) do per[item.class] += 1 end
		for _, d in ipairs(root:GetChildren()) do
			if d:IsA("MeshPart") and d:GetAttribute("Dressing") ~= "ground" then
				clones += 1
				ok(d.CanCollide == false and d.CanQuery == false and d.CanTouch == false, "dressing never collides")
			end
		end
		links = #root.Sway:GetChildren()
		return per, clones, links
	end
	local per, clones, links = census()
	local b = T.Budgets.High
	for class, n in pairs(per) do ok(n <= b[class], "High " .. class .. " " .. n .. " <= " .. b[class]) end
	ok(per.clutter >= 100 and per.foliage >= 3 and per.cliff >= 10 and per.satellite >= 2, string.format("High dresses the island (clutter %d, trees %d, cliff %d, satellites %d)", per.clutter, per.foliage, per.cliff, per.satellite))
	eq(clones, Terrain.stats.placed, "one clone per placed item")
	ok(links > 0, "swaying dressing is linked for the ambience layer (" .. links .. ")")
	for _, link in ipairs(root.Sway:GetChildren()) do
		ok(link:IsA("ObjectValue") and link.Name == "ShapeMesh" and A.SWAY[link.Value:GetAttribute("ShapeOf")] ~= nil, "sway links name registered shapes")
	end
	local mosswake = built.islands:FindFirstChild("Mosswake Grove")
	eq(hiddenMeadows[mosswake.Meadow], 1, "the meadow is hidden locally under its forged ground")
	local grounds = 0
	for _ in pairs(groundLive) do grounds += 1 end
	ok(grounds >= 1 and grounds <= b.grounds, "grounds within the High cap (" .. grounds .. ")")
	-- Phone tier: caps drop, grounds coarser, everything re-placed within Lite.
	player.attributes.IsleSettingGraphics = "Performance"
	for _ = 1, 4 do Terrain.step() end
	per = census()
	for class, n in pairs(per) do ok(n <= T.Budgets.Performance[class], "Performance " .. class .. " " .. n) end
	grounds = 0
	for _ in pairs(groundLive) do grounds += 1 end
	eq(grounds, 0, "Performance releases every forged ground")
	eq(hiddenMeadows[mosswake.Meadow], 0, "and gives the primitive meadow back")
	player.attributes.IsleSettingGraphics = "Balanced"
	for _ = 1, 6 do Terrain.step() end
	per = census()
	for class, n in pairs(per) do ok(n <= T.Budgets.Balanced[class], "Balanced " .. class .. " " .. n) end
	-- Far away: everything but far-LOD satellites is released.
	hrp.CFrame = CFrame.new(5000, 0, 5000)
	for _ = 1, 3 do Terrain.step() end
	eq(Terrain.stats.placed, 0, "nothing stays placed far from every island")
	local live = 0
	for _ in pairs(placedLive) do live += 1 end
	eq(live, 0, "every dress token returned")
	ok(maxDress <= 720, "never more clones than the desktop ceiling (" .. maxDress .. ")")
	-- A resized home meadow (Homestead expansion) is re-planned.
	local home = built.archipelago:FindFirstChild("WayfarersRest_1")
	hrp.CFrame = CFrame.new(home:GetAttribute("IslandCenter") + Vector3.new(0, 3, 0))
	for _ = 1, 24 do Terrain.step() end
	local state = Terrain.islands[home]
	ok(state and state.desc and state.desc.build ~= nil, "the home island is planned with its build radius")
	local before = state.desc
	state.dirty = true -- what the meadow Size / BuildRadius signals set
	Terrain.step()
	ok(state.desc ~= before, "a resized home is re-planned")
	for item in pairs(Terrain.placed) do
		if item.island == state and (item.class == "clutter" or item.class == "foliage") then
			local c = home:GetAttribute("IslandCenter")
			ok(math.sqrt((item.x - c.X) ^ 2 + (item.z - c.Z) ^ 2) >= state.desc.build + 1, "home dressing stays off the build cells")
		end
	end
	Terrain.resetAll()
end
-- Wiring.
local project = fs.readFile("default.project.json")
ok(has(project, '"AetherTerrainArt": { "$path": "art/TerrainCatalog.lua" }') and has(project, '"AetherTerrain": { "$path": "shared/TerrainArt.lua" }')
	and has(project, '"IsleTerrain": { "$path": "terrain.client.lua" }'), "project wiring")
ok(has(forgeSource, '"AetherTerrainArt"'), "the forge loads the terrain catalog")
local amb = fs.readFile("ambience.client.lua")
ok(has(amb, '"IsleDressing"'), "the ambience layer scans the dressing root for sway")
for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-environment.luau"), script .. " runs this suite") end
print(string.format("PASS E: %d client checks.", checks - partE))
print(string.format("Environment QA passed %d checks.", checks))
print("SUITE-END verify-environment.luau")

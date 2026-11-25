--!strict
-- Island environment rules (docs/DEPTH-CONTRACT.md §54): ReplicatedStorage.AetherTerrain.
-- Pure and deterministic: no services, no instance creation, no randomness.
-- terrain.client.lua (StarterPlayerScripts.IsleTerrain) turns a plan into local
-- forged meshes; verify-environment.luau checks the same plans headlessly.
--
--   T.Regions[region]         per-biome dressing: tree species (3+ each), hero
--                             silhouette tree, shrubs, clutter mix, cliff dressing,
--                             satellite rock, palettes (leaf tints, flower tints,
--                             crystal, ground dirt)
--   T.Budgets[tier]           per graphics tier (High / Balanced / Lite = phones /
--                             Performance): instance caps and radii per class,
--                             density share, ground cell size, triangle ceiling
--   T.collect(model)          an island's descriptor: centre, meadow radius, top,
--                             region, build radius (homes), obstacle footprints,
--                             path strips, ponds
--   T.plan(desc)              every dressing item (clutter, shrub, foliage, hero,
--                             cliff, satellite) with world position, yaw, scale,
--                             tint and a density rank
--   T.ground(desc, cell)      the island's forged ground top: an undulating polar
--                             mesh (vertices, per-vertex colours and normals,
--                             faces) in island space (origin = meadow top centre)
--   T.heightAt(desc, x, z)    the ground height used by both (studs above the top)
--   T.visible(plan, tier, focus, mobile) the items a tier shows around a point,
--                             nearest first within each class cap
-- Everything placed is decorative: CanCollide / CanQuery / CanTouch false.
local T = {}
T.VERSION = 1

------------------------------------------------------------------------------
-- Budgets per graphics tier (the §35 tier, phones use Lite like §50).
--   clutter / foliage / cliff / satellite: instance caps (nearest first)
--   *Radius: studs from the focus (far LOD: beyond it the class is not drawn)
--   density: share of the island's candidates this tier keeps (by rank)
--   grounds: forged ground tops at once; groundRadius: from the island rim
--   cell: ground mesh cell size (studs); triangles: ceiling for everything
------------------------------------------------------------------------------
T.TIER_ORDER = {"High", "Balanced", "Lite", "Performance"}
T.Budgets = {
	High = {clutter = 420, clutterRadius = 150, foliage = 110, foliageRadius = 420, cliff = 80, cliffRadius = 480,
		satellite = 30, satelliteRadius = 1200, density = 1, grounds = 4, groundRadius = 600, cell = 4.5, triangles = 760000},
	Balanced = {clutter = 240, clutterRadius = 115, foliage = 64, foliageRadius = 300, cliff = 40, cliffRadius = 340,
		satellite = 16, satelliteRadius = 900, density = 0.55, grounds = 3, groundRadius = 420, cell = 5.5, triangles = 430000},
	Lite = {clutter = 110, clutterRadius = 80, foliage = 32, foliageRadius = 200, cliff = 18, cliffRadius = 220,
		satellite = 10, satelliteRadius = 700, density = 0.3, grounds = 2, groundRadius = 260, cell = 7, triangles = 200000},
	Performance = {clutter = 30, clutterRadius = 55, foliage = 14, foliageRadius = 140, cliff = 0, cliffRadius = 0,
		satellite = 6, satelliteRadius = 500, density = 0.1, grounds = 0, groundRadius = 0, cell = 9, triangles = 60000},
}
T.CLASSES = {"clutter", "foliage", "cliff", "satellite"}
-- Which class an item kind counts against.
T.CLASS_OF = {clutter = "clutter", shrub = "clutter", foliage = "foliage", hero = "foliage", cliff = "cliff", satellite = "satellite"}
-- Most triangles any shape of a class may have (generator ranges, art/generate-props.cjs).
T.MAX_TRIS = {clutter = 1000, foliage = 1300, cliff = 1500, satellite = 800}
function T.budgetKey(tier: string?, mobile: boolean?): string
	if tier == "Performance" then return "Performance" end
	if mobile then return "Lite" end
	return if tier and T.Budgets[tier] then tier else "High"
end
function T.budget(tier: string?, mobile: boolean?) return T.Budgets[T.budgetKey(tier, mobile)] end
-- Worst-case triangles a tier can place (every cap full of its largest shape) plus its grounds.
function T.ceiling(b): number
	local total = b.grounds * T.groundTriangles(160, b.cell)
	for _, class in ipairs(T.CLASSES) do total += b[class] * T.MAX_TRIS[class] end
	return total
end

------------------------------------------------------------------------------
-- Region art. Tints are hex; each species carries two tint variants so one
-- template pair gives the whole island its variety (plus yaw / scale jitter).
------------------------------------------------------------------------------
local function species(shape, weight, tints, lo, hi) return {shape = shape, weight = weight, tints = tints, scale = {lo, hi}} end
T.Regions = {
	Hub = {
		trees = {species("BroadleafTree", 3, {"5E9C4C", "6FAA55"}, .85, 1.15), species("BlossomTree", 2, {"F2A7C3", "F7C6D9"}, .85, 1.1), species("SpirePine", 1, {"3F7550", "4A8258"}, .8, 1.05)},
		hero = {shape = "BroadleafTree", tint = "5A9A4A", scale = 2.1},
		shrubs = {species("LeafyBush", 3, {"5E9A4E", "6CA858"}, .8, 1.2), species("Fern", 1, {"4F8F45"}, .8, 1.1)},
		clutter = {species("GrassTuft", 8, {"6FA956", "7DB35C"}, .8, 1.25), species("FlowerSprigs", 3, {"E58AB0", "F2D06B"}, .8, 1.15),
			species("Pebbles", 2, {"8C8F92"}, .8, 1.3), species("MossStone", 1, {"858A8F"}, .7, 1.1)},
		outcrop = {"7E8388"}, cliff = {"HangingRoots", "VineCurtain"}, cliffTint = {"6A4A32", "4E8A44"},
		satellite = "SatelliteRock", flowerTints = {"E58AB0", "F2D06B", "9FC7F0"}, dirt = "8A6E4F", treeShare = 0.22,
	},
	Meadow = {
		trees = {species("BlossomTree", 3, {"F2A7C3", "F7C6D9"}, .85, 1.15), species("BroadleafTree", 2, {"6FAA55", "84B65E"}, .85, 1.1), species("WillowTree", 2, {"7FAE5A", "8DB86A"}, .9, 1.1)},
		hero = {shape = "BlossomTree", tint = "F5B3CC", scale = 2.3},
		shrubs = {species("LeafyBush", 2, {"6CA858", "7DB35C"}, .8, 1.2), species("Fern", 1, {"4F8F45"}, .8, 1.1)},
		clutter = {species("MeadowGrass", 5, {"7DB35C", "8DBE63"}, .8, 1.2), species("GrassTuft", 4, {"6FA956", "7DB35C"}, .8, 1.2),
			species("FlowerSprigs", 5, {"E58AB0", "F2D06B"}, .8, 1.2), species("Pebbles", 1, {"8C8F92"}, .8, 1.2)},
		outcrop = {"8A8D86"}, cliff = {"VineCurtain", "HangingRoots"}, cliffTint = {"4E8A44", "6A4A32"},
		satellite = "SatelliteRock", flowerTints = {"E58AB0", "F2D06B", "C9A0F0"}, dirt = "8E7050", treeShare = 0.3,
	},
	Quarry = {
		trees = {species("BroadleafTree", 2, {"C9752F", "D9913E"}, .8, 1.05), species("SpirePine", 2, {"5C6E48", "6E7A50"}, .8, 1.05), species("CrystalTree", 1, {"FF9A4A", "FFC06A"}, .8, 1)},
		hero = {shape = "BroadleafTree", tint = "C9572F", scale = 2.0},
		shrubs = {species("LeafyBush", 1, {"8A8A4E"}, .7, 1)},
		clutter = {species("Pebbles", 5, {"9C9682", "8F8676"}, .9, 1.4), species("MossStone", 2, {"8F8676"}, .7, 1.1), species("GrassTuft", 3, {"9CA45E", "B0A86A"}, .7, 1.1),
			species("ShardCluster", 1, {"FF9A4A"}, .7, 1)},
		outcrop = {"8F8676"}, cliff = {"CrystalVein", "HangingRoots"}, cliffTint = {"FF8A3D", "6A4A32"},
		satellite = "SatelliteRockBare", flowerTints = {"F2D06B"}, dirt = "7A6650", treeShare = 0.28,
	},
	Skyreach = {
		trees = {species("SpirePine", 4, {"DDEBF0", "3F6F5A"}, .85, 1.15), species("BroadleafTree", 1, {"9EC3A8", "B6D3BC"}, .8, 1), species("CrystalTree", 1, {"BDEBFF", "DDF6FF"}, .8, 1.05)},
		hero = {shape = "SpirePine", tint = "E6F1F5", scale = 2.2},
		shrubs = {species("Fern", 1, {"6E9A80"}, .8, 1)},
		clutter = {species("GrassTuft", 5, {"9FBFA6", "B7CEB9"}, .8, 1.1), species("Pebbles", 3, {"B5BDC4"}, .8, 1.2), species("ShardCluster", 1, {"BDEBFF"}, .7, 1),
			species("FlowerSprigs", 1, {"DDF0FF"}, .7, 1)},
		outcrop = {"A9B3BB"}, cliff = {"CrystalVein", "VineCurtain"}, cliffTint = {"BDEBFF", "6E9A80"},
		satellite = "SatelliteRock", flowerTints = {"DDF0FF"}, dirt = "8E8E86", treeShare = 0.25,
	},
	Windpine = {
		trees = {species("SpirePine", 4, {"3F7550", "356846"}, .9, 1.25), species("WillowTree", 1, {"5E8E4A", "6F9E55"}, .85, 1.05), species("BroadleafTree", 2, {"4E8A44", "5A9450"}, .85, 1.1)},
		hero = {shape = "SpirePine", tint = "2F6444", scale = 2.5},
		shrubs = {species("Fern", 3, {"4F8F45", "5E9A4E"}, .9, 1.3), species("LeafyBush", 2, {"4E8A44"}, .8, 1.2)},
		clutter = {species("GrassTuft", 5, {"5F9A4E", "6FA956"}, .8, 1.2), species("MossStone", 2, {"7D847E"}, .7, 1.2), species("MeadowGrass", 2, {"6FA956"}, .8, 1.1),
			species("MushroomCluster", 1, {"C9A06A"}, .7, 1)},
		outcrop = {"7D847E"}, cliff = {"HangingRoots", "VineCurtain"}, cliffTint = {"6A4A32", "3F7A44"},
		satellite = "SatelliteRock", flowerTints = {"F2D06B", "FFFFFF"}, dirt = "6E5A40", treeShare = 0.55,
	},
	Gloomhollow = {
		trees = {species("MushroomTree", 3, {"9C5FD0", "6A7BE0"}, .85, 1.15), species("CrystalTree", 2, {"A58BFF", "8FE3FF"}, .85, 1.1), species("WillowTree", 1, {"5B4E8A", "4E5C8A"}, .85, 1.05)},
		hero = {shape = "MushroomTree", tint = "B07AD6", scale = 2.4},
		shrubs = {species("Fern", 2, {"4E5C8A", "5B4E8A"}, .8, 1.2)},
		clutter = {species("MushroomCluster", 4, {"B07AD6", "7FA0F0"}, .8, 1.2), species("ShardCluster", 3, {"A58BFF", "8FE3FF"}, .8, 1.2), species("Pebbles", 2, {"4A4F62"}, .9, 1.3),
			species("GrassTuft", 2, {"4E5C7A", "5B5A86"}, .8, 1.1)},
		outcrop = {"4A4F62"}, cliff = {"CrystalVein", "CrystalVein"}, cliffTint = {"A58BFF", "8FE3FF"},
		satellite = "SatelliteRockBare", flowerTints = {"A58BFF"}, dirt = "3A3448", treeShare = 0.3,
	},
	Tidewater = {
		trees = {species("WillowTree", 2, {"7FAE5A", "8DB86A"}, .85, 1.1), species("BlossomTree", 2, {"F08A6E", "F5B08E"}, .85, 1.1), species("BroadleafTree", 1, {"6FAF6A", "7DBB74"}, .8, 1)},
		hero = {shape = "BlossomTree", tint = "F08A6E", scale = 2.2},
		shrubs = {species("ReedClump", 3, {"7C9A4E", "8AA65A"}, .9, 1.3), species("LeafyBush", 1, {"6FA05A"}, .8, 1.1)},
		clutter = {species("Pebbles", 3, {"C9BFA5", "B8AE96"}, .8, 1.3), species("GrassTuft", 4, {"9CB86A", "A8C276"}, .8, 1.2), species("FlowerSprigs", 1, {"F08A6E"}, .8, 1.1)},
		outcrop = {"B8AE96"}, cliff = {"VineCurtain", "HangingRoots"}, cliffTint = {"5E9A6A", "6A4A32"},
		satellite = "SatelliteRock", flowerTints = {"F08A6E"}, dirt = "B39F78", treeShare = 0.2,
	},
	Tempest = {
		trees = {species("CrystalTree", 3, {"8FB8FF", "B5D3FF"}, .85, 1.15), species("SpirePine", 2, {"4A5E66", "56707A"}, .85, 1.1), species("MushroomTree", 1, {"5D6E9C"}, .8, 1)},
		hero = {shape = "CrystalTree", tint = "9FC4FF", scale = 2.4},
		shrubs = {species("Fern", 1, {"5A6E72"}, .8, 1.1)},
		clutter = {species("ShardCluster", 3, {"8FB8FF"}, .8, 1.2), species("Pebbles", 4, {"5F6878", "707A8A"}, .9, 1.4), species("GrassTuft", 2, {"6E7E78"}, .8, 1.1)},
		outcrop = {"5F6878"}, cliff = {"CrystalVein", "HangingRoots"}, cliffTint = {"8FB8FF", "4A3E36"},
		satellite = "SatelliteRockBare", flowerTints = {"8FB8FF"}, dirt = "4A4F5A", treeShare = 0.22,
	},
	ShatteredCrown = {
		trees = {species("CrystalTree", 3, {"F2D06B", "C9A0F0"}, .9, 1.15), species("BlossomTree", 2, {"C9A0F0", "E6C8FF"}, .85, 1.1), species("SpirePine", 1, {"5E5A7A"}, .8, 1)},
		hero = {shape = "CrystalTree", tint = "FFD56B", scale = 2.6},
		shrubs = {species("Fern", 1, {"6E6A8C"}, .8, 1.1)},
		clutter = {species("ShardCluster", 3, {"F2D06B", "C9A0F0"}, .8, 1.2), species("Pebbles", 3, {"8E8AA8"}, .9, 1.3), species("GrassTuft", 2, {"7A7898"}, .8, 1.1)},
		outcrop = {"8E8AA8"}, cliff = {"CrystalVein", "CrystalVein"}, cliffTint = {"F2D06B", "C9A0F0"},
		satellite = "SatelliteRockBare", flowerTints = {"F2D06B"}, dirt = "5E5A72", treeShare = 0.18,
	},
	Home = {
		trees = {species("BroadleafTree", 2, {"5E9C4C", "6FAA55"}, .85, 1.1), species("BlossomTree", 1, {"F2A7C3"}, .85, 1.05), species("SpirePine", 1, {"3F7550"}, .85, 1.05)},
		hero = {shape = "BroadleafTree", tint = "5A9A4A", scale = 1.8},
		shrubs = {species("LeafyBush", 2, {"5E9A4E"}, .8, 1.1), species("Fern", 1, {"4F8F45"}, .8, 1.1)},
		clutter = {species("GrassTuft", 5, {"6FA956", "7DB35C"}, .8, 1.2), species("FlowerSprigs", 3, {"E58AB0", "F2D06B"}, .8, 1.1), species("Pebbles", 1, {"8C8F92"}, .8, 1.2)},
		outcrop = {"858A8F"}, cliff = {"HangingRoots", "VineCurtain"}, cliffTint = {"6A4A32", "4E8A44"},
		satellite = "SatelliteRock", flowerTints = {"E58AB0"}, dirt = "8A6E4F", treeShare = 0.25,
	},
}
-- Islands whose region id does not name their biome.
T.ISLAND_REGION = {Shardhollow = "Gloomhollow", ["Cinder Shelf"] = "Quarry"}
-- Shapes that sway with the §50 wind (registered in Ambience.SWAY too).
T.SWAYS = {GrassTuft = true, MeadowGrass = true, FlowerSprigs = true, Fern = true, ReedClump = true, LeafyBush = true,
	BroadleafTree = true, BlossomTree = true, WillowTree = true, SpirePine = true, VineCurtain = true, HangingRoots = true}

------------------------------------------------------------------------------
-- Deterministic hashing and value noise.
------------------------------------------------------------------------------
local function hash(a: number, b: number, c: number): number
	local h = bit32.bxor(bit32.band(math.floor(a) * 374761393, 0xFFFFFFFF), bit32.band(math.floor(b) * 668265263, 0xFFFFFFFF), bit32.band(math.floor(c) * 2246822519, 0xFFFFFFFF))
	h = bit32.band(bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177, 0xFFFFFFFF)
	return bit32.bxor(h, bit32.rshift(h, 16)) / 0xFFFFFFFF
end
T.hash = hash
local function smooth(t: number): number return t * t * (3 - 2 * t) end
-- Value noise in [-1, 1] at frequency f (cycles per stud), seed s.
local function noise(x: number, z: number, f: number, s: number): number
	local u, v = x * f + 1000, z * f + 1000
	local i, j = math.floor(u), math.floor(v)
	local fu, fv = smooth(u - i), smooth(v - j)
	local a, b = hash(i, j, s), hash(i + 1, j, s)
	local c, d = hash(i, j + 1, s), hash(i + 1, j + 1, s)
	return ((a + (b - a) * fu) * (1 - fv) + (c + (d - c) * fu) * fv) * 2 - 1
end
T.noise = noise
local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
local function seedOf(name: string): number
	local h = 7
	for k = 1, #name do h = (h * 31 + string.byte(name, k)) % 1000003 end
	return h
end
local function hex(h: string): {number}
	return {tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255}
end
T.hex = hex
local function mix(a: {number}, b: {number}, t: number): {number}
	return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t}
end

------------------------------------------------------------------------------
-- Island descriptor (reads instances; never writes).
------------------------------------------------------------------------------
-- Parts that are the island itself (ground, hull, invisible rim guards, shore
-- dressing outside the rim) never block dressing.
T.IGNORE = {Meadow = true, ["Floating foundation"] = true, ["Island underside"] = true, ["Edge guard"] = true, ["Shore ledge"] = true}
T.PATH_NAMES = {Path = true, Ramp = true, ["Continuous bridge deck"] = true, ["Bridge guard"] = true, ["Bridge span"] = true, Boardwalk = true}
T.WATER_NAMES = {["Pond water"] = true, ["Fishing water"] = true}
-- Clearances (studs beyond a footprint): clutter, trees, hero trees.
T.CLEAR = {clutter = 1.2, path = 0.9, node = 3, tree = 3, treePath = 2.5, hero = 7, rim = 1.6, treeRim = 4.5}
local function footprint(p): (number, number, number, number, number, number)
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
	local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
	local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	local c = cf.Position
	return c.X - ex, c.X + ex, c.Z - ez, c.Z + ez, c.Y - ey, c.Y + ey
end
-- desc = {name, region, center {x,y,z}, radius (meadow), top, build (home build
-- radius or nil), bare (non-grass ground), ground {r,g,b}, obstacles = {{x0,x1,z0,z1,kind}},
-- ponds = {{x, z, r}}, protected = {{x, z, r}}}
function T.collect(model, protected)
	local center = model:GetAttribute("IslandCenter")
	local meadow = model:FindFirstChild("Meadow")
	if typeof(center) ~= "Vector3" or not meadow or not meadow:IsA("BasePart") then return nil end
	local radius = math.max(meadow.Size.Y, meadow.Size.Z) / 2
	local top = meadow.CFrame.Position.Y + meadow.Size.X / 2
	local region = T.ISLAND_REGION[model.Name] or model:GetAttribute("RegionId") or model:GetAttribute("Region") or "Home"
	if not T.Regions[region] then region = "Home" end
	local material = meadow.Material
	local desc = {
		name = model.Name, region = region, center = {center.X, top, center.Z}, radius = radius, top = top,
		build = model:GetAttribute("BuildRadius"), bare = material ~= Enum.Material.Grass and material ~= Enum.Material.LeafyGrass,
		ground = {meadow.Color.R, meadow.Color.G, meadow.Color.B}, obstacles = {}, ponds = {}, protected = {},
	}
	local mx, mz = meadow.CFrame.Position.X, meadow.CFrame.Position.Z
	desc.center[1], desc.center[3] = mx, mz
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and not (p.Parent == model and T.IGNORE[p.Name]) and not T.IGNORE[p.Name] then
			local x0, x1, z0, z1, y0, y1 = footprint(p)
			-- Only what stands on (or just above) the meadow blocks it.
			if y1 > top - 0.6 and y0 < top + 14 then
				local kind = if T.PATH_NAMES[p.Name] then "path" elseif p:GetAttribute("GatherNode") ~= nil or (p.Parent and p.Parent:GetAttribute("GatherNode") ~= nil) then "node" else "solid"
				if T.WATER_NAMES[p.Name] then
					table.insert(desc.ponds, {(x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2})
					kind = "water"
				end
				table.insert(desc.obstacles, {x0, x1, z0, z1, kind})
			end
		end
	end
	if desc.build and type(protected) == "table" then
		for _, c in ipairs(protected) do table.insert(desc.protected, {mx + c.x, mz + c.z, c.r}) end
	end
	return desc
end

-- Obstacle index: 8-stud buckets of footprints (built once per descriptor).
local CELL = 8
local function index(desc)
	if desc._index then return desc._index end
	local buckets = {}
	for i, o in ipairs(desc.obstacles) do
		for gx = math.floor((o[1] - 10) / CELL), math.floor((o[2] + 10) / CELL) do
			for gz = math.floor((o[3] - 10) / CELL), math.floor((o[4] + 10) / CELL) do
				local key = gx * 100003 + gz
				local list = buckets[key]
				if not list then list = {}; buckets[key] = list end
				table.insert(list, i)
			end
		end
	end
	desc._index = buckets
	return buckets
end
-- Distance (XZ) from a point to the nearest footprint of the given kinds
-- (nil = all), capped at 10 studs (the index reach).
function T.clearance(desc, x: number, z: number, kinds: {[string]: boolean}?): number
	local list = index(desc)[math.floor(x / CELL) * 100003 + math.floor(z / CELL)]
	local best = 10
	if list then
		for _, i in ipairs(list) do
			local o = desc.obstacles[i]
			if not kinds or kinds[o[5]] then
				local dx = math.max(o[1] - x, 0, x - o[2])
				local dz = math.max(o[3] - z, 0, z - o[4])
				local d = math.sqrt(dx * dx + dz * dz)
				if d < best then best = d end
			end
		end
	end
	return best
end
local PATHS = {path = true}
local NODES = {node = true}
local SOLIDS = {solid = true, water = true}
-- Is (x, z) free for an item of this footprint radius and class?
function T.free(desc, x: number, z: number, r: number, tree: boolean?): boolean
	local cx, cz = desc.center[1], desc.center[3]
	local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
	if d > desc.radius - (if tree then T.CLEAR.treeRim else T.CLEAR.rim) - r then return false end
	-- Homes: never on the build disc (every cell there is the owner's), so
	-- the protected circles inside it are clear by construction too.
	if desc.build and d < desc.build + 1 + r then return false end
	for _, c in ipairs(desc.protected) do
		if (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < (c[3] + r) ^ 2 then return false end
	end
	if T.clearance(desc, x, z, PATHS) < r + (if tree then T.CLEAR.treePath else T.CLEAR.path) then return false end
	if T.clearance(desc, x, z, NODES) < r + T.CLEAR.node then return false end
	if T.clearance(desc, x, z, SOLIDS) < r + (if tree then T.CLEAR.tree else T.CLEAR.clutter) then return false end
	return true
end

------------------------------------------------------------------------------
-- Ground height (studs above the meadow top). Flat (0) within 2.5 studs of any
-- footprint, rising to the full roll by 8 studs; never above +0.22 (feet sink
-- at most that far) or below -0.12 inside the rim; the last 2.4 studs roll
-- over the edge to meet the cliff's turf curb (-0.14 grassy, -0.4 bare).
------------------------------------------------------------------------------
T.HEIGHT = {up = 0.22, down = -0.12, flat = 2.5, full = 8, edge = 2.4, lip = -0.14, bareLip = -0.4}
function T.heightAt(desc, x: number, z: number): number
	local cx, cz = desc.center[1], desc.center[3]
	local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local open = smoothstep(T.HEIGHT.flat, T.HEIGHT.full, T.clearance(desc, x, z))
	if desc.build and d < desc.build + 1 then open = 0 end
	local h = open * (0.15 * noise(x, z, 1 / 23, s) + 0.07 * noise(x, z, 1 / 9, s + 1) + 0.04)
	h = math.clamp(h, T.HEIGHT.down, T.HEIGHT.up)
	local t = math.clamp((d - (desc.radius - T.HEIGHT.edge)) / T.HEIGHT.edge, 0, 1)
	if t > 0 then
		local lip = if desc.bare then T.HEIGHT.bareLip else T.HEIGHT.lip
		h = h * (1 - t) + lip * t * t
	end
	return h
end

------------------------------------------------------------------------------
-- Ground mesh: a polar grid (rings every ~cell studs, a fixed segment count),
-- heights from T.heightAt, per-vertex colours (grass patches, dry streaks,
-- worn dirt around paths and footprints, darker turf at the rim) and smooth
-- per-vertex normals. Island space: x / z from the centre, y above the top.
------------------------------------------------------------------------------
function T.groundGrid(radius: number, cell: number): (number, number)
	local rings = math.clamp(math.ceil(radius / cell), 8, 34)
	local segments = math.clamp(math.floor(2 * math.pi * radius / (cell * 1.4) / 8 + 0.5) * 8, 48, 128)
	return rings, segments
end
function T.groundTriangles(radius: number, cell: number): number
	local rings, segments = T.groundGrid(radius, cell)
	return segments * (2 * rings - 1)
end
function T.ground(desc, cell: number)
	local art = T.Regions[desc.region]
	local R = desc.radius
	local rings, segments = T.groundGrid(R, cell)
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local base = desc.ground
	local light, dark = mix(base, {1, 1, 1}, 0.16), mix(base, {0, 0, 0}, 0.2)
	local dry = mix(base, {0.86, 0.78, 0.45}, if desc.bare then 0.1 else 0.28)
	local dirt = hex(art.dirt)
	local cx, cz = desc.center[1], desc.center[3]
	local vertices, colors, faces = {}, {}, {}
	local function vertex(x: number, z: number)
		local wx, wz = cx + x, cz + z
		local h = T.heightAt(desc, wx, wz)
		table.insert(vertices, {x, h, z})
		local c = base
		local patch = noise(wx, wz, 1 / 17, s + 5)
		c = if patch > 0 then mix(c, light, patch * 0.9) else mix(c, dark, -patch * 0.8)
		local streak = noise(wx, wz, 1 / 31, s + 9)
		if streak > 0.25 then c = mix(c, dry, (streak - 0.25) * 1.1) end
		-- Height shading: rises catch light, hollows hold shade.
		c = if h > 0 then mix(c, light, math.min(1, h * 2.2)) else mix(c, dark, math.min(1, -h * 2.5))
		-- Worn dirt: paths fray into the turf, footprints trample it.
		local wear = 1 - smoothstep(0.4, 4.5, T.clearance(desc, wx, wz, PATHS))
		local trample = 1 - smoothstep(0, 2.2, T.clearance(desc, wx, wz, SOLIDS))
		local w = math.max(wear * 0.78, trample * 0.35) * (0.85 + 0.15 * noise(wx, wz, 1 / 3, s + 11))
		if w > 0 then c = mix(c, dirt, w) end
		local edge = math.clamp((math.sqrt(x * x + z * z) - (R - 3)) / 3, 0, 1)
		if edge > 0 then c = mix(c, dark, edge * 0.55) end
		table.insert(colors, c)
		return #vertices
	end
	local centre = vertex(0, 0)
	local ring = {}
	for i = 1, rings do
		-- The last ring sits on the meadow's side wall (radius + 0.1).
		local rho = if i == rings then R + 0.1 else R * (i / rings) ^ 0.92
		local row = {}
		for j = 0, segments - 1 do
			local a = (j + (if i % 2 == 0 then 0.5 else 0)) * 2 * math.pi / segments
			row[j] = vertex(math.cos(a) * rho, math.sin(a) * rho)
		end
		ring[i] = row
	end
	-- Faces wound counter-clockwise seen from above (normals up).
	for j = 0, segments - 1 do
		local k = (j + 1) % segments
		table.insert(faces, {centre, ring[1][k], ring[1][j]})
	end
	for i = 1, rings - 1 do
		local inner, outer = ring[i], ring[i + 1]
		local shift = (i + 1) % 2 == 0 -- outer row offset by half a segment
		for j = 0, segments - 1 do
			local k = (j + 1) % segments
			if shift then
				table.insert(faces, {inner[j], inner[k], outer[j]})
				table.insert(faces, {outer[j], inner[k], outer[k]})
			else
				local jm = (j - 1) % segments
				table.insert(faces, {inner[j], outer[j], outer[jm]})
				table.insert(faces, {inner[j], inner[k], outer[j]})
			end
		end
	end
	-- Orient every face up, then smooth per-vertex normals (area weighted).
	local normals = {}
	for i = 1, #vertices do normals[i] = {0, 0, 0} end
	for _, f in ipairs(faces) do
		local a, b, c = vertices[f[1]], vertices[f[2]], vertices[f[3]]
		local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
		local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
		if ny < 0 then
			f[2], f[3] = f[3], f[2]
			nx, ny, nz = -nx, -ny, -nz
		end
		for k = 1, 3 do
			local n = normals[f[k]]
			n[1] += nx; n[2] += ny; n[3] += nz
		end
	end
	for i, n in ipairs(normals) do
		local l = math.sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
		normals[i] = if l > 0 then {n[1] / l, n[2] / l, n[3] / l} else {0, 1, 0}
	end
	return {vertices = vertices, colors = colors, normals = normals, faces = faces, rings = rings, segments = segments}
end

------------------------------------------------------------------------------
-- Dressing plan.
------------------------------------------------------------------------------
T.SPACING = {clutter = 3.4, tree = 8}
T.FOOT = {clutter = 0.7, shrub = 1.2, foliage = 2, hero = 3.5}
local function pick(list, u: number)
	local total = 0
	for _, s in ipairs(list) do total += s.weight end
	local x = u * total
	for _, s in ipairs(list) do
		x -= s.weight
		if x < 0 then return s end
	end
	return list[#list]
end
local function nearWater(desc, x: number, z: number): boolean
	for _, p in ipairs(desc.ponds) do
		local d = math.sqrt((x - p[1]) ^ 2 + (z - p[2]) ^ 2) - p[3]
		if d > 0.6 and d < 4.5 then return true end
	end
	return false
end
function T.plan(desc)
	if desc._plan then return desc._plan end
	local art = T.Regions[desc.region]
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local cx, cz, R, top = desc.center[1], desc.center[3], desc.radius, desc.top
	local items = {}
	local function add(kind, sp, x: number, z: number, u: number, extra)
		local tints = sp.tints
		local item = {
			kind = kind, class = T.CLASS_OF[kind], shape = sp.shape, tint = tints[1 + math.floor(hash(x * 3, z * 3, s + 21) * #tints)],
			x = x, z = z, y = top + T.heightAt(desc, x, z) - 0.04, yaw = hash(x, z, s + 22) * 2 * math.pi,
			scale = sp.scale[1] + (sp.scale[2] - sp.scale[1]) * hash(x * 7, z * 7, s + 23), rank = u, sway = T.SWAYS[sp.shape] == true,
		}
		if extra then for k, v in pairs(extra) do item[k] = v end end
		table.insert(items, item)
		return item
	end
	-- Ground clutter and shrubs: a jittered grid over the meadow.
	local step = T.SPACING.clutter
	for gx = math.floor(-R / step), math.ceil(R / step) do
		for gz = math.floor(-R / step), math.ceil(R / step) do
			local x = cx + (gx + hash(gx, gz, s + 1)) * step
			local z = cz + (gz + hash(gx, gz, s + 2)) * step
			local u, v = hash(gx, gz, s + 3), hash(gx, gz, s + 4)
			-- Patchy: clumps gather where the noise is high, meadows stay open.
			if noise(x, z, 1 / 14, s + 6) > -0.35 then
				local water = nearWater(desc, x, z)
				local shrub = water or v < 0.12
				local list = if water then {species("ReedClump", 1, {"7C9A4E", "8AA65A"}, .9, 1.3)} elseif shrub then art.shrubs else art.clutter
				local kind = if shrub then "shrub" else "clutter"
				if T.free(desc, x, z, if shrub then T.FOOT.shrub else T.FOOT.clutter) then add(kind, pick(list, v / (if shrub then 0.12 else 1) % 1), x, z, u) end
			end
		end
	end
	-- Scattered stone outcrops (bigger, sparser).
	local outcrop = species("StoneOutcrop", 1, art.outcrop, .8, 1.3)
	for k = 1, math.floor(R / 12) do
		local a, d = hash(k, 1, s + 30) * 2 * math.pi, R * (0.35 + 0.55 * hash(k, 2, s + 30))
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		if T.free(desc, x, z, 2.4) then add("clutter", outcrop, x, z, hash(k, 3, s + 30)) end
	end
	-- Trees: a coarse grid; a region's tree share keeps meadows open.
	local tstep = T.SPACING.tree
	local heroes = 0
	for gx = math.floor(-R / tstep), math.ceil(R / tstep) do
		for gz = math.floor(-R / tstep), math.ceil(R / tstep) do
			local x = cx + (gx + 0.2 + 0.6 * hash(gx, gz, s + 41)) * tstep
			local z = cz + (gz + 0.2 + 0.6 * hash(gx, gz, s + 42)) * tstep
			local u = hash(gx, gz, s + 43)
			local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
			if hash(gx, gz, s + 44) < art.treeShare then
				-- A hero silhouette (the region's landmark tree) where the meadow is wide open.
				if heroes < 3 and d > R * 0.45 and T.free(desc, x, z, T.FOOT.hero, true) and T.clearance(desc, x, z) >= T.CLEAR.hero then
					heroes += 1
					add("hero", {shape = art.hero.shape, tints = {art.hero.tint}, scale = {art.hero.scale, art.hero.scale * 1.08}}, x, z, 0)
				elseif T.free(desc, x, z, T.FOOT.foliage, true) then
					add("foliage", pick(art.trees, hash(gx, gz, s + 45)), x, z, u)
				end
			end
		end
	end
	-- Cliff dressing: hung on the cliff face below the rim, every ~11 studs.
	local wall = (R + 0.15) / 0.99 * 1.02
	local count = math.floor(2 * math.pi * R / 11)
	for k = 0, count - 1 do
		local a = (k + hash(k, 1, s + 51) * 0.6) * 2 * math.pi / count
		local x, z = cx + math.cos(a) * wall, cz + math.sin(a) * wall
		-- Leave docks and bridge landings bare.
		if T.clearance(desc, cx + math.cos(a) * (R - 1), cz + math.sin(a) * (R - 1), PATHS) > 4 then
			local which = 1 + math.floor(hash(k, 2, s + 51) * #art.cliff)
			local shape = art.cliff[which]
			add("cliff", {shape = shape, tints = {art.cliffTint[which]}, scale = {.9, 1.4}}, x, z, hash(k, 3, s + 51),
				{y = top - (if desc.bare then 0.9 else 0.6) - 0.15, yaw = a, out = {math.cos(a), math.sin(a)}})
		end
	end
	-- Satellite rocks: small islets drifting beside the island, below its rim.
	local sats = math.clamp(math.floor(R / 22), 2, 6)
	for k = 1, sats do
		local a = (k + hash(k, 1, s + 61) * 0.7) * 2 * math.pi / sats
		local d = R * (1.25 + 0.35 * hash(k, 2, s + 61)) + 8
		local scale = math.clamp(R / 55, 0.7, 2.2) * (0.7 + 0.6 * hash(k, 3, s + 61))
		add("satellite", {shape = art.satellite, tints = art.outcrop, scale = {scale, scale}}, cx + math.cos(a) * d, cz + math.sin(a) * d, hash(k, 4, s + 61),
			{y = top - 6 - 12 * hash(k, 5, s + 61)})
	end
	desc._plan = items
	return items
end

-- Items a tier draws around `focus` ({x, y, z}): per class, those within the
-- tier's density share and radius, nearest first, up to the class cap.
function T.visible(items, tier: string?, focus: {number}, mobile: boolean?)
	local b = T.budget(tier, mobile)
	local byClass = {}
	for _, class in ipairs(T.CLASSES) do byClass[class] = {} end
	for _, item in ipairs(items) do
		local class = item.class
		local r = b[class .. "Radius"]
		if b[class] > 0 and (item.rank < b.density or item.kind == "hero" or class == "satellite") then
			local dx, dy, dz = item.x - focus[1], item.y - focus[2], item.z - focus[3]
			local d2 = dx * dx + dy * dy + dz * dz
			if item.kind == "hero" then r = math.max(r, b.foliageRadius * 1.8) end
			if d2 <= r * r then table.insert(byClass[class], {item, d2}) end
		end
	end
	local out = {}
	for _, class in ipairs(T.CLASSES) do
		local list = byClass[class]
		table.sort(list, function(a, c) return a[2] < c[2] end)
		for i = 1, math.min(#list, b[class]) do table.insert(out, list[i][1]) end
	end
	return out
end
T.species = species
return T

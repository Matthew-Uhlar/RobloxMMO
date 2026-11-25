--!strict
-- Island environment rules (docs/DEPTH-CONTRACT.md §54): ReplicatedStorage.AetherTerrain.
-- Pure and deterministic: no services, no instance creation, no randomness.
-- terrain.client.lua (StarterPlayerScripts.IsleTerrain) turns a plan into local
-- forged meshes; verify-environment.luau checks the same plans headlessly.
--
--   T.Regions[region]         per-biome dressing: tree species (3+ each, near +
--                             far LOD), hero silhouette tree, shrubs, clutter mix,
--                             rocks, cliff dressing, satellite rock, dirt colour
--   T.Budgets[tier]           per graphics tier (High / Balanced / Lite = phones /
--                             Performance): caps and radii per class, density
--                             share, ground / hull counts, cells and segments
--   T.collect(model, circles) an island's descriptor: centre, meadow radius, top,
--                             wall, region, build radius (homes), oriented obstacle
--                             footprints (boxes and discs), ponds
--   T.plan(desc)              every dressing item with world position, yaw,
--                             scale, tint and a density rank
--   T.ground(desc, cell)      the forged ground top (flat arrays, island space)
--   T.hull(desc, seg, levels) the forged cliff wall at absolute size (flat arrays)
--   T.heightAt(desc, x, z)    the ground height used by both (studs above the top)
--   T.visible(items, tier, focus) what a tier draws around a point: entries
--                             {item, shape} per class, nearest first, LOD chosen
-- Everything placed is decorative: CanCollide / CanQuery / CanTouch false.
local T = {}
T.VERSION = 2

------------------------------------------------------------------------------
-- Budgets per graphics tier (the §35 tier, phones use Lite like §50).
--   clutter / rock / near (trees at near LOD) / far (trees at far LOD) / cliff /
--   satellite: instance caps (nearest first); *Radius: studs from the focus (far
--   LOD: beyond it the class is not drawn; trees switch to the far LOD beyond
--   nearRadius); density: share of the island's candidates kept (by rank);
--   grounds: islands with a forged ground top and cliff wall (groundRadius from
--   the rim); cell: ground cell size; hullSeg / hullLevels: wall segment length
--   (studs) and profile levels; triangles: ceiling for the whole layer.
------------------------------------------------------------------------------
T.TIER_ORDER = {"High", "Balanced", "Lite", "Performance"}
T.Budgets = {
	High = {clutter = 200, clutterRadius = 150, rock = 20, rockRadius = 220, near = 16, nearRadius = 110, far = 70, farRadius = 420,
		cliff = 36, cliffRadius = 480, satellite = 24, satelliteRadius = 1200, density = 1, grounds = 4, groundRadius = 600, cell = 4.5,
		hullSeg = 7, hullLevels = 28, triangles = 1100000},
	Balanced = {clutter = 110, clutterRadius = 115, rock = 10, rockRadius = 170, near = 6, nearRadius = 80, far = 40, farRadius = 300,
		cliff = 20, cliffRadius = 340, satellite = 14, satelliteRadius = 900, density = 0.55, grounds = 3, groundRadius = 420, cell = 5.5,
		hullSeg = 8, hullLevels = 24, triangles = 600000},
	Lite = {clutter = 50, clutterRadius = 80, rock = 4, rockRadius = 120, near = 0, nearRadius = 0, far = 18, farRadius = 200,
		cliff = 8, cliffRadius = 220, satellite = 8, satelliteRadius = 700, density = 0.3, grounds = 2, groundRadius = 260, cell = 7,
		hullSeg = 10, hullLevels = 16, triangles = 250000},
	Performance = {clutter = 20, clutterRadius = 55, rock = 0, rockRadius = 0, near = 0, nearRadius = 0, far = 10, farRadius = 140,
		cliff = 0, cliffRadius = 0, satellite = 4, satelliteRadius = 500, density = 0.1, grounds = 0, groundRadius = 0, cell = 9,
		hullSeg = 12, hullLevels = 12, triangles = 100000},
}
-- Draw order (H1: far-seen classes first, so clutter never starves them).
T.CLASSES = {"satellite", "cliff", "far", "near", "rock", "clutter"}
-- Most triangles any shape of a class may have (generator ranges, art/generate-props.cjs).
T.MAX_TRIS = {clutter = 2000, rock = 2400, near = 7000, far = 3600, cliff = 2900, satellite = 3000}
-- Shapes that count as rocks (bigger than clutter).
T.SHAPE_CLASS = {MossStone = "rock", StoneOutcrop = "rock"}
T.LARGEST_ISLAND = 160 -- meadow radius used for worst-case ground / hull triangles
function T.budgetKey(tier: string?, mobile: boolean?): string
	if tier == "Performance" then return "Performance" end
	if mobile then return "Lite" end
	return if tier and T.Budgets[tier] then tier else "High"
end
function T.budget(tier: string?, mobile: boolean?) return T.Budgets[T.budgetKey(tier, mobile)] end
-- Worst-case triangles a tier can place (every cap full of its largest shape) plus its grounds and walls.
function T.ceiling(b): number
	local total = b.grounds * (T.groundTriangles(T.LARGEST_ISLAND, b.cell) + T.hullTriangles(T.LARGEST_ISLAND, b.hullSeg, b.hullLevels))
	for _, class in ipairs(T.CLASSES) do total += b[class] * T.MAX_TRIS[class] end
	return total
end

------------------------------------------------------------------------------
-- Region art. Tints are hex; each species carries at most two tint variants
-- (the forge keeps <= 2 templates per shape on desktop, H1) plus yaw / scale jitter.
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
		trees = {species("SnowPine", 4, {"3F6F5A", "4A7A64"}, .85, 1.15), species("BroadleafTree", 1, {"9EC3A8", "B6D3BC"}, .8, 1), species("CrystalTree", 1, {"BDEBFF", "DDF6FF"}, .8, 1.05)},
		hero = {shape = "SnowPine", tint = "3F6F5A", scale = 2.2},
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
		hero = {shape = "CrystalTree", tint = "FFD56B", scale = 2.55},
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
	BroadleafTree = true, BlossomTree = true, WillowTree = true, SpirePine = true, SnowPine = true, VineCurtain = true, HangingRoots = true,
	BroadleafTreeFar = true, BlossomTreeFar = true, WillowTreeFar = true, SpirePineFar = true, SnowPineFar = true}


------------------------------------------------------------------------------
-- Deterministic hashing and value noise. L4: every product stays below 2^53
-- (32-bit multiply split into 16-bit halves), so the engine and Lune agree bit
-- for bit whatever the inputs (negative or large coordinates included).
------------------------------------------------------------------------------
local TWO32 = 4294967296
local function mul32(a: number, b: number): number
	local ah, al = a // 65536, a % 65536
	return ((ah * b) % TWO32 * 65536 + al * b) % TWO32
end
local function u32(x: number): number return math.floor(x) % TWO32 end
local function hash(a: number, b: number, c: number): number
	local h = bit32.bxor(mul32(u32(a), 374761393), mul32(u32(b), 668265263), mul32(u32(c), 2246822519))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 13)), 1274126177)
	return bit32.bxor(h, bit32.rshift(h, 16)) / (TWO32 - 1)
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
local function finite(x: any): boolean return type(x) == "number" and x == x and x > -math.huge and x < math.huge end

------------------------------------------------------------------------------
-- Island descriptor (reads instances; never writes).
------------------------------------------------------------------------------
-- L3: the island's own meadow, foundation and underside are ignored by identity
-- (a plaza or terrace elsewhere on the island named "Meadow" still blocks);
-- invisible rim guards and shore ledges outside the rim are ignored by name.
T.IGNORE_NAMES = {["Edge guard"] = true, ["Shore ledge"] = true}
T.SELF_NAMES = {Meadow = true, ["Floating foundation"] = true, ["Island underside"] = true}
T.PATH_NAMES = {Path = true, Ramp = true, ["Continuous bridge deck"] = true, ["Bridge guard"] = true, ["Bridge span"] = true, Boardwalk = true}
T.WATER_NAMES = {["Pond water"] = true, ["Fishing water"] = true}
-- Clearances (studs beyond a footprint).
T.CLEAR = {clutter = 1.2, path = 0.9, node = 3, tree = 3, treePath = 2.5, hero = 7, rim = 1.6, treeRim = 4.5}
-- M1: an oriented footprint: a disc for upright cylinders / balls, an oriented
-- rectangle (the part's own XZ axes) for upright boxes, the projected AABB for
-- anything tilted past 45 degrees. Also returns the vertical extent.
local function footprint(p)
	local cf, size = p.CFrame, p.Size
	local declared = p:GetAttribute("ShapeBox")
	local isDeclared = typeof(declared) == "Vector3"
	if isDeclared then
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
	local o = {cx = c.X, cz = c.Z, x0 = c.X - ex, x1 = c.X + ex, z0 = c.Z - ez, z1 = c.Z + ez}
	local shape = if not isDeclared and p:IsA("Part") then p.Shape else nil
	if shape == Enum.PartType.Cylinder and math.abs(r.Y) > 0.9 then
		o.round = math.max(size.Y, size.Z) / 2
	elseif shape == Enum.PartType.Ball then
		o.round = size.X / 2
	elseif math.abs(u.Y) > 0.7 then
		local rl = math.sqrt(r.X * r.X + r.Z * r.Z)
		o.ux, o.uz = r.X / rl, r.Z / rl
		local ll = math.sqrt(l.X * l.X + l.Z * l.Z)
		o.hx = h.X * rl + h.Y * math.abs(u.X * o.ux + u.Z * o.uz)
		o.hz = h.Z * ll + h.Y * math.abs(-u.X * o.uz + u.Z * o.ux)
	else
		o.ux, o.uz, o.hx, o.hz = 1, 0, ex, ez
	end
	return o, c.Y - ey, c.Y + ey
end
T.footprint = footprint
-- Distance (XZ) from a point to a footprint.
local function distanceTo(o, x: number, z: number): number
	local dx, dz = x - o.cx, z - o.cz
	if o.round then return math.max(0, math.sqrt(dx * dx + dz * dz) - o.round) end
	local a = math.abs(dx * o.ux + dz * o.uz) - o.hx
	local b = math.abs(-dx * o.uz + dz * o.ux) - o.hz
	a, b = math.max(a, 0), math.max(b, 0)
	return math.sqrt(a * a + b * b)
end
T.distanceTo = distanceTo
local function classify(p): string
	if T.PATH_NAMES[p.Name] then return "path" end
	if T.WATER_NAMES[p.Name] then return "water" end
	if p:GetAttribute("GatherNode") ~= nil or (p.Parent and p.Parent:GetAttribute("GatherNode") ~= nil) then return "node" end
	return "solid"
end
-- desc = {name, region, center {x, top, z}, radius (meadow), top, wall, drop,
-- foundationRadius, build (home build radius or nil), bare, ground {r,g,b},
-- stone {r,g,b}, obstacles, ponds, protected, self = {meadow, foundation, underside}}
function T.collect(model, protected)
	local center = model:GetAttribute("IslandCenter")
	local meadow = model:FindFirstChild("Meadow")
	-- L5: a model without a usable centre or meadow is skipped (never errors).
	if typeof(center) ~= "Vector3" or not finite(center.X) or not finite(center.Z) then return nil end
	if not meadow or not meadow:IsA("BasePart") or meadow.Parent ~= model then return nil end
	local radius = math.max(meadow.Size.Y, meadow.Size.Z) / 2
	if not finite(radius) or radius < 4 then return nil end
	local top = meadow.CFrame.Position.Y + meadow.Size.X / 2
	local region = T.ISLAND_REGION[model.Name] or model:GetAttribute("RegionId") or model:GetAttribute("Region") or "Home"
	if not T.Regions[region] then region = "Home" end
	local material = meadow.Material
	local foundation = model:FindFirstChild("Floating foundation")
	if not foundation then
		local shell = model:FindFirstChild("Island shell")
		foundation = shell and shell:FindFirstChild("Floating foundation")
	end
	local wall = foundation and foundation:GetAttribute("WallHeight")
	local bare = material ~= Enum.Material.Grass and material ~= Enum.Material.LeafyGrass
	local desc = {
		name = model.Name, region = region, center = {meadow.CFrame.Position.X, top, meadow.CFrame.Position.Z}, radius = radius, top = top,
		build = model:GetAttribute("BuildRadius"), bare = bare, drop = if bare then 0.9 else 0.6,
		wall = if type(wall) == "number" then wall else math.clamp(radius * 0.18, 10, 30),
		foundationRadius = if foundation and foundation:IsA("BasePart") then math.max(foundation.Size.Y, foundation.Size.Z) / 2 else radius + 0.15,
		ground = {meadow.Color.R, meadow.Color.G, meadow.Color.B},
		stone = if foundation and foundation:IsA("BasePart") then {foundation.Color.R, foundation.Color.G, foundation.Color.B} else {0.42, 0.45, 0.5},
		obstacles = {}, ponds = {}, protected = {}, self = {[meadow] = true},
	}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and T.SELF_NAMES[child.Name] then desc.self[child] = true end
	end
	if foundation then desc.self[foundation] = true end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then T.addObstacle(desc, p) end
	end
	if desc.build and type(protected) == "table" then
		for _, c in ipairs(protected) do table.insert(desc.protected, {desc.center[1] + c.x, desc.center[3] + c.z, c.r}) end
	end
	return desc
end
-- Adds one part's footprint (H3: also used for parts that appear later).
-- Returns the footprint, or nil when the part does not block the meadow.
function T.addObstacle(desc, p)
	if desc.self[p] or T.IGNORE_NAMES[p.Name] then return nil end
	local o, y0, y1 = footprint(p)
	-- Only what stands on (or just above) the meadow blocks it.
	if not (y1 > desc.top - 0.6 and y0 < desc.top + 14) then return nil end
	o.kind, o.part = classify(p), p
	if o.kind == "water" then
		table.insert(desc.ponds, {o.cx, o.cz, o.round or math.max(o.hx or 0, o.hz or 0)})
	end
	table.insert(desc.obstacles, o)
	if desc._index then T.indexAdd(desc, #desc.obstacles) end
	return o
end

-- Obstacle index: 8-stud buckets of footprint AABBs (built once per descriptor).
local CELL = 8
function T.indexAdd(desc, i: number)
	local o = desc.obstacles[i]
	local buckets = desc._index
	for gx = math.floor((o.x0 - 10) / CELL), math.floor((o.x1 + 10) / CELL) do
		for gz = math.floor((o.z0 - 10) / CELL), math.floor((o.z1 + 10) / CELL) do
			local key = gx * 100003 + gz
			local list = buckets[key]
			if not list then list = {}; buckets[key] = list end
			table.insert(list, i)
		end
	end
end
local function index(desc)
	if desc._index then return desc._index end
	desc._index = {}
	for i in ipairs(desc.obstacles) do T.indexAdd(desc, i) end
	return desc._index
end
-- Distance (XZ) from a point to the nearest footprint of the given kinds
-- (nil = all), capped at 10 studs (the index reach).
function T.clearance(desc, x: number, z: number, kinds: {[string]: boolean}?): number
	local list = index(desc)[math.floor(x / CELL) * 100003 + math.floor(z / CELL)]
	local best = 10
	if list then
		for _, i in ipairs(list) do
			local o = desc.obstacles[i]
			if not kinds or kinds[o.kind] then
				local d = distanceTo(o, x, z)
				if d < best then best = d end
			end
		end
	end
	return best
end
local PATHS = {path = true}
local NODES = {node = true}
local SOLIDS = {solid = true, water = true}
T.KINDS = {paths = PATHS, nodes = NODES, solids = SOLIDS}
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
-- Ground height (studs above the meadow top). L1: a gentle roll of +0.11 /
-- -0.06 at most (feet sink at most 0.11). Flat (0) within 2.5 studs of any
-- footprint plus `margin` (M2: the ground passes its triangle size, so no
-- triangle that touches a footprint can rise above it), rolling to the full
-- undulation by 8 studs; the last 2.4 studs roll over the edge to the cliff's
-- turf curb (-0.14 grassy, -0.4 bare); home build discs stay flat.
------------------------------------------------------------------------------
T.HEIGHT = {up = 0.11, down = -0.06, flat = 2.5, full = 8, edge = 2.4, lip = -0.14, bareLip = -0.4, skirt = -0.6, skirtIn = 0.35}
function T.heightAt(desc, x: number, z: number, margin: number?): number
	local cx, cz = desc.center[1], desc.center[3]
	local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local open = smoothstep(T.HEIGHT.flat, T.HEIGHT.full, T.clearance(desc, x, z) - (margin or 0))
	if desc.build and d < desc.build + 1 + (margin or 0) then open = 0 end
	local h = open * (0.075 * noise(x, z, 1 / 23, s) + 0.035 * noise(x, z, 1 / 9, s + 1) + 0.02)
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
-- heights from T.heightAt (with the grid's edge length as margin), per-vertex
-- colours (grass patches, dry streaks, worn dirt around paths and footprints,
-- darker turf at the rim) and smooth per-vertex normals. M4: past the rim ring a
-- skirt folds inward under the cliff's curb, so no seam shows from the side.
-- Flat arrays (M6): positions / colors / normals {x, y, z, ...} and indices
-- {a, b, c, ...} (1-based) in island space (x / z from the centre, y above
-- the top). L6: cached per (descriptor, cell).
------------------------------------------------------------------------------
function T.groundGrid(radius: number, cell: number): (number, number)
	local rings = math.clamp(math.ceil(radius / cell), 8, 34)
	local segments = math.clamp(math.floor(2 * math.pi * radius / (cell * 1.4) / 8 + 0.5) * 8, 48, 128)
	return rings, segments
end
function T.groundTriangles(radius: number, cell: number): number
	local rings, segments = T.groundGrid(radius, cell)
	return segments * (2 * rings - 1) + 2 * segments
end
local function smoothNormals(pos, idx, outward)
	local n = #pos // 3
	local acc = table.create(n * 3, 0)
	for f = 1, #idx, 3 do
		local a, b, c = idx[f], idx[f + 1], idx[f + 2]
		local ax, ay, az = pos[a * 3 - 2], pos[a * 3 - 1], pos[a * 3]
		local ux, uy, uz = pos[b * 3 - 2] - ax, pos[b * 3 - 1] - ay, pos[b * 3] - az
		local vx, vy, vz = pos[c * 3 - 2] - ax, pos[c * 3 - 1] - ay, pos[c * 3] - az
		local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
		for _, k in ipairs({a, b, c}) do
			acc[k * 3 - 2] += nx; acc[k * 3 - 1] += ny; acc[k * 3] += nz
		end
	end
	for k = 1, n do
		local x, y, z = acc[k * 3 - 2], acc[k * 3 - 1], acc[k * 3]
		local l = math.sqrt(x * x + y * y + z * z)
		if l > 0 then acc[k * 3 - 2], acc[k * 3 - 1], acc[k * 3] = x / l, y / l, z / l else acc[k * 3 - 1] = 1 end
	end
	return acc
end
T.smoothNormals = smoothNormals
function T.ground(desc, cell: number, yield: (() -> ())?)
	desc._ground = desc._ground or {}
	local cached = desc._ground[cell]
	if cached then return cached end
	local art = T.Regions[desc.region]
	local R = desc.radius
	local rings, segments = T.groundGrid(R, cell)
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	-- M2: the largest edge of the grid (the outer ring's arc) is the flat margin.
	local margin = math.max(R / rings, 2 * math.pi * R / segments)
	local base = desc.ground
	local light, dark = mix(base, {1, 1, 1}, 0.16), mix(base, {0, 0, 0}, 0.2)
	local dry = mix(base, {0.86, 0.78, 0.45}, if desc.bare then 0.1 else 0.28)
	local dirt = hex(art.dirt)
	local cx, cz = desc.center[1], desc.center[3]
	local pos, col, idx = {}, {}, {}
	local count = 0
	local function vertex(x: number, z: number, y: number?)
		local wx, wz = cx + x, cz + z
		local h = y or T.heightAt(desc, wx, wz, margin)
		pos[#pos + 1] = x; pos[#pos + 1] = h; pos[#pos + 1] = z
		local c = base
		local patch = noise(wx, wz, 1 / 17, s + 5)
		c = if patch > 0 then mix(c, light, patch * 0.9) else mix(c, dark, -patch * 0.8)
		local streak = noise(wx, wz, 1 / 31, s + 9)
		if streak > 0.25 then c = mix(c, dry, (streak - 0.25) * 1.1) end
		c = if h > 0 then mix(c, light, math.min(1, h * 4)) else mix(c, dark, math.min(1, -h * 2.5))
		local wear = 1 - smoothstep(0.4, 4.5, T.clearance(desc, wx, wz, PATHS))
		local trample = 1 - smoothstep(0, 2.2, T.clearance(desc, wx, wz, SOLIDS))
		local w = math.max(wear * 0.78, trample * 0.35) * (0.85 + 0.15 * noise(wx, wz, 1 / 3, s + 11))
		if w > 0 then c = mix(c, dirt, w) end
		local edge = math.clamp((math.sqrt(x * x + z * z) - (R - 3)) / 3, 0, 1)
		if edge > 0 then c = mix(c, dark, edge * 0.55) end
		col[#col + 1] = c[1]; col[#col + 1] = c[2]; col[#col + 1] = c[3]
		count += 1
		if yield and count % 400 == 0 then yield() end
		return count
	end
	local centre = vertex(0, 0)
	local ring = {}
	for i = 1, rings + 1 do
		local row = {}
		for j = 0, segments - 1 do
			local a = (j + (if i % 2 == 0 then 0.5 else 0)) * 2 * math.pi / segments
			if i <= rings then
				-- The last ring sits on the meadow's side wall (radius + 0.1).
				local rho = if i == rings then R + 0.1 else R * (i / rings) ^ 0.92
				row[j] = vertex(math.cos(a) * rho, math.sin(a) * rho)
			else
				-- Skirt: folds in under the curb (M4).
				local rho = R + 0.1 - T.HEIGHT.skirtIn
				row[j] = vertex(math.cos(a) * rho, math.sin(a) * rho, T.HEIGHT.skirt)
			end
		end
		ring[i] = row
	end
	local function tri(a, b, c) idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c end
	for j = 0, segments - 1 do tri(centre, ring[1][(j + 1) % segments], ring[1][j]) end
	for i = 1, rings do
		local inner, outer = ring[i], ring[i + 1]
		local shift = (i + 1) % 2 == 0
		for j = 0, segments - 1 do
			local k = (j + 1) % segments
			if shift then
				tri(inner[j], inner[k], outer[j]); tri(outer[j], inner[k], outer[k])
			else
				local jm = (j - 1) % segments
				tri(inner[j], outer[j], outer[jm]); tri(inner[j], inner[k], outer[j])
			end
		end
	end
	-- Orient: the top faces up, the skirt band (the last 2 x segments) outward.
	local skirtFrom = #idx - 6 * segments + 1
	for f = 1, #idx, 3 do
		local a, b, c = idx[f], idx[f + 1], idx[f + 2]
		local ax, ay, az = pos[a * 3 - 2], pos[a * 3 - 1], pos[a * 3]
		local ux, uy, uz = pos[b * 3 - 2] - ax, pos[b * 3 - 1] - ay, pos[b * 3] - az
		local vx, vy, vz = pos[c * 3 - 2] - ax, pos[c * 3 - 1] - ay, pos[c * 3] - az
		local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
		local flip = if f >= skirtFrom then (nx * ax + nz * az) < 0 else ny < 0
		if flip then idx[f + 1], idx[f + 2] = c, b end
	end
	local out = {positions = pos, colors = col, normals = smoothNormals(pos, idx), indices = idx, rings = rings, segments = segments,
		vertexCount = count, triangleCount = #idx // 3, margin = margin, skirtFrom = skirtFrom}
	desc._ground[cell] = out
	return out
end

------------------------------------------------------------------------------
-- Cliff wall at absolute size (A5): the grass overhang lip continuing the ground
-- rim, a soil band tucked under the curb, then strata ledges in absolute studs
-- (a 2.6-stud course, irregular along the rim) down the foundation's wall
-- (clamp(R*0.18, 10, 30) studs), tucking in toward the keel. One segment per
-- `seg` studs of rim (6-8 near, coarser on lower tiers); `levels` strata levels
-- (>= 24 on High). Per-vertex colours, smooth normals, faces wound outward.
------------------------------------------------------------------------------
-- The lip: a smooth turf bulge leaving the ground's rim horizontally (rounded
-- overhang, ~0.65 studs proud at its belly), receding into a soil band tucked
-- under it. {studs beyond the meadow radius, studs below the top}; sampled densely
-- near the rim so no level turns sharply.
T.LIP, T.GRASS_LEVELS = {}, 0
for k = 0, 15 do
	local t = (k / 15) ^ 1.5
	local y = -0.14 - 1.56 * t
	table.insert(T.LIP, {0.1 + 0.2 * t + 0.6 * math.sin(math.pi * t ^ 0.55) * math.sqrt(1 - t), y})
	if t < 0.45 then T.GRASS_LEVELS += 1 end
end
T.LIP[1][1] = 0.1
function T.wallRadiusAt(desc, angle: number, y: number): number
	-- y: studs below the top (negative); the strata wall below the soil band.
	local s = desc.seed or seedOf(desc.name)
	local R = desc.radius
	local depth = desc.drop + desc.wall
	local t = math.clamp((-y - 1.7) / math.max(1, depth - 1.7), 0, 1)
	local arc = angle * R
	-- Strata courses in absolute studs, never finer than six wall levels (smooth
	-- shading); along the rim the noise stays >= 4 segments long (no zigzag). The
	-- relief fades in under the soil band so the wall leaves the lip smoothly.
	local course = math.max(4.5, desc._course or 4.5)
	local fade = smoothstep(0, 1.8, -y - 1.7)
	local ledge = 0.22 * math.sin(2 * math.pi * (-y - 1.7) / course + 1.3 * noise(arc, 0, 1 / 40, s + 21))
	local rough = 0.12 * noise(arc, -y, 1 / 32, s + 22)
	local tuck = -0.06 * R * smoothstep(0.75, 1, t)
	return R + T.LIP[#T.LIP][1] + fade * (ledge * (1 - t * 0.4) + rough) + tuck
end
function T.hullGrid(radius: number, seg: number, levels: number): (number, number)
	local segments = math.max(48, math.ceil(2 * math.pi * (radius + 0.5) / seg))
	return segments, #T.LIP + levels
end
function T.hullTriangles(radius: number, seg: number, levels: number): number
	local segments, rows = T.hullGrid(radius, seg, levels)
	return segments * (rows - 1) * 2
end
function T.hull(desc, seg: number, levels: number, yield: (() -> ())?)
	desc._hull = desc._hull or {}
	local key = seg * 1000 + levels
	if desc._hull[key] then return desc._hull[key] end
	local art = T.Regions[desc.region]
	local R = desc.radius
	local segments, rows = T.hullGrid(R, seg, levels)
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local depth = desc.drop + desc.wall
	desc._course = 6 * (depth - 1.7) / levels
	local stone = desc.stone
	local light, darkStone = mix(stone, {1, 1, 1}, 0.18), mix(stone, {0, 0, 0}, 0.3)
	local grass = mix(desc.ground, {0, 0, 0}, 0.12)
	local soil = mix(hex(art.dirt), {0, 0, 0}, 0.25)
	local pos, col, idx = {}, {}, {}
	local count = 0
	for row = 1, rows do
		local lip = T.LIP[row]
		local y = if lip then lip[2] + (if desc.bare then T.HEIGHT.bareLip - T.HEIGHT.lip else 0) else -1.7 - (depth - 1.7) * ((row - #T.LIP) / levels)
		for j = 0, segments - 1 do
			local a = j * 2 * math.pi / segments
			local r = if lip then R + lip[1] + (if desc.bare or row == 1 then 0 else 0.06 * noise(a * R, 0, 1 / 30, s + 23)) else T.wallRadiusAt(desc, a, y)
			if row == 1 then r = R + 0.1 end -- meets the ground's rim ring exactly
			pos[#pos + 1] = math.cos(a) * r; pos[#pos + 1] = y; pos[#pos + 1] = math.sin(a) * r
			local c
			if lip and row <= T.GRASS_LEVELS and not desc.bare then
				c = mix(grass, desc.ground, 0.5 + 0.5 * noise(a * R, 0, 1 / 30, s + 24))
			elseif lip then
				c = if desc.bare then light else soil
			else
				local band = math.sin(-y * 2 * math.pi / math.max(4.5, desc._course) * 0.8 + 0.6 * noise(a * R, y, 1 / 60, s + 25))
				c = if band > 0 then mix(stone, light, band * 0.7) else mix(stone, darkStone, -band * 0.6)
				c = mix(c, darkStone, smoothstep(0.7, 1, -y / depth) * 0.5)
			end
			col[#col + 1] = c[1]; col[#col + 1] = c[2]; col[#col + 1] = c[3]
			count += 1
			if yield and count % 400 == 0 then yield() end
		end
	end
	local function at(row, j) return (row - 1) * segments + (j % segments) + 1 end
	for row = 1, rows - 1 do
		for j = 0, segments - 1 do
			-- Wound outward: (row, j) -> (row, j+1) -> (row+1, j) seen from outside.
			idx[#idx + 1] = at(row, j); idx[#idx + 1] = at(row + 1, j); idx[#idx + 1] = at(row, j + 1)
			idx[#idx + 1] = at(row, j + 1); idx[#idx + 1] = at(row + 1, j); idx[#idx + 1] = at(row + 1, j + 1)
		end
	end
	-- Orient every face away from the axis (the lip curls, so test per face).
	for f = 1, #idx, 3 do
		local a, b, c = idx[f], idx[f + 1], idx[f + 2]
		local ax, ay, az = pos[a * 3 - 2], pos[a * 3 - 1], pos[a * 3]
		local ux, uy, uz = pos[b * 3 - 2] - ax, pos[b * 3 - 1] - ay, pos[b * 3] - az
		local vx, vy, vz = pos[c * 3 - 2] - ax, pos[c * 3 - 1] - ay, pos[c * 3] - az
		local nx, nz = uy * vz - uz * vy, ux * vy - uy * vx
		local mx, mz = (ax + pos[b * 3 - 2] + pos[c * 3 - 2]) / 3, (az + pos[b * 3] + pos[c * 3]) / 3
		if nx * mx + nz * mz < 0 then idx[f + 1], idx[f + 2] = c, b end
	end
	local out = {positions = pos, colors = col, normals = smoothNormals(pos, idx), indices = idx, segments = segments, rows = rows,
		vertexCount = count, triangleCount = #idx // 3, depth = depth}
	desc._hull[key] = out
	return out
end

------------------------------------------------------------------------------
-- Dressing plan.
------------------------------------------------------------------------------
T.SPACING = {clutter = 3.4, tree = 8}
T.FOOT = {clutter = 0.7, shrub = 1.2, rock = 2.4, foliage = 2, hero = 3.5}
-- Cliff dressing hangs from under the grass lip (M5): the soil band of the
-- forged wall, or the catalog cliff's rim when only the far hull shows.
T.ATTACH = {near = {0, 0}, farScale = 1.012}
do
	local best = T.LIP[1]
	for _, p in ipairs(T.LIP) do if math.abs(p[2] + 1.0) < math.abs(best[2] + 1.0) then best = p end end
	T.ATTACH.near = {best[1] + 0.02, best[2]}
end
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
T.CLASS_OF = {clutter = "clutter", shrub = "clutter", cliff = "cliff", satellite = "satellite"}
local REEDS = species("ReedClump", 1, {"7C9A4E", "8AA65A"}, .9, 1.3)
function T.plan(desc)
	if desc._plan then return desc._plan end
	local art = T.Regions[desc.region]
	local s = desc.seed or seedOf(desc.name)
	desc.seed = s
	local cx, cz, R, top = desc.center[1], desc.center[3], desc.radius, desc.top
	local items = {}
	local function add(kind, sp, x: number, z: number, u: number, extra)
		local tints = sp.tints
		local class = if kind == "foliage" or kind == "hero" then "tree" elseif T.SHAPE_CLASS[sp.shape] then T.SHAPE_CLASS[sp.shape] else T.CLASS_OF[kind]
		local item = {
			kind = kind, class = class, shape = sp.shape, tint = tints[1 + math.floor(hash(x * 3, z * 3, s + 21) * #tints)],
			x = x, z = z, y = top + T.heightAt(desc, x, z) - 0.04, flatY = top - 0.04, yaw = hash(x, z, s + 22) * 2 * math.pi,
			scale = sp.scale[1] + (sp.scale[2] - sp.scale[1]) * hash(x * 7, z * 7, s + 23), rank = u,
		}
		if class == "tree" then item.far = sp.shape .. "Far" end
		if extra then for k, v in pairs(extra) do item[k] = v end end
		item.sway = T.SWAYS[item.shape] == true
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
				local list = if water then {REEDS} elseif shrub then art.shrubs else art.clutter
				local sp = pick(list, v / (if shrub then 0.12 else 1) % 1)
				local foot = if T.SHAPE_CLASS[sp.shape] == "rock" then T.FOOT.rock elseif shrub then T.FOOT.shrub else T.FOOT.clutter
				if T.free(desc, x, z, foot) then add(if shrub then "shrub" else "clutter", sp, x, z, u) end
			end
		end
	end
	-- Scattered stone outcrops (bigger, sparser).
	local outcrop = species("StoneOutcrop", 1, art.outcrop, .8, 1.3)
	for k = 1, math.floor(R / 12) do
		local a, d = hash(k, 1, s + 30) * 2 * math.pi, R * (0.35 + 0.55 * hash(k, 2, s + 30))
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		if T.free(desc, x, z, T.FOOT.rock) then add("clutter", outcrop, x, z, hash(k, 3, s + 30)) end
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
				if heroes < 3 and d > R * 0.45 and T.free(desc, x, z, T.FOOT.hero, true) and T.clearance(desc, x, z) >= T.CLEAR.hero then
					heroes += 1
					add("hero", {shape = art.hero.shape, tints = {art.hero.tint}, scale = {art.hero.scale, art.hero.scale * 1.08}}, x, z, 0)
				elseif T.free(desc, x, z, T.FOOT.foliage, true) then
					add("foliage", pick(art.trees, hash(gx, gz, s + 45)), x, z, u)
				end
			end
		end
	end
	-- Cliff dressing: hung from under the grass lip every ~11 studs of rim.
	local count = math.floor(2 * math.pi * R / 11)
	for k = 0, count - 1 do
		local a = (k + hash(k, 1, s + 51) * 0.6) * 2 * math.pi / count
		-- Leave docks and bridge landings bare.
		if T.clearance(desc, cx + math.cos(a) * (R - 1), cz + math.sin(a) * (R - 1), PATHS) > 4 then
			local which = 1 + math.floor(hash(k, 2, s + 51) * #art.cliff)
			local nearR, farR = R + T.ATTACH.near[1], desc.foundationRadius * T.ATTACH.farScale + 0.05
			add("cliff", {shape = art.cliff[which], tints = {art.cliffTint[which]}, scale = {.9, 1.4}}, cx + math.cos(a) * nearR, cz + math.sin(a) * nearR, hash(k, 3, s + 51),
				{y = top + T.ATTACH.near[2], flatY = top - desc.drop - 0.05, yaw = a, out = {math.cos(a), math.sin(a)}, angle = a, nearR = nearR, farR = farR})
		end
	end
	-- Satellite rocks: small islets drifting beside the island, below its rim.
	local sats = math.clamp(math.floor(R / 22), 2, 6)
	for k = 1, sats do
		local a = (k + hash(k, 1, s + 61) * 0.7) * 2 * math.pi / sats
		local d = R * (1.25 + 0.35 * hash(k, 2, s + 61)) + 8
		local scale = math.clamp(R / 55, 0.7, 2.2) * (0.7 + 0.6 * hash(k, 3, s + 61))
		local y = top - 6 - 12 * hash(k, 5, s + 61)
		add("satellite", {shape = art.satellite, tints = art.outcrop, scale = {scale, scale}}, cx + math.cos(a) * d, cz + math.sin(a) * d, hash(k, 4, s + 61),
			{y = y, flatY = y})
	end
	desc._plan = items
	return items
end
-- Where a cliff item hangs: near the forged wall's soil band, else the catalog rim.
function T.cliffPosition(item, nearHull: boolean): (number, number, number)
	local r = if nearHull then item.nearR else item.farR
	local cx, cz = item.x - item.out[1] * item.nearR, item.z - item.out[2] * item.nearR
	return cx + item.out[1] * r, if nearHull then item.y else item.flatY, cz + item.out[2] * r
end

-- What a tier draws around `focus` ({x, y, z}). Per class: items within the
-- density share (heroes, cliff and satellites always) and the class radius,
-- nearest first, up to the cap. Trees: the near LOD within nearRadius (heroes
-- x1.5) while the near cap lasts, else the far LOD within farRadius (heroes x1.8).
-- Returns entries {item = item, shape = shape, class = class} in T.CLASSES order.
function T.visible(items, tier: string?, focus: {number}, mobile: boolean?)
	local b = T.budget(tier, mobile)
	local byClass = {}
	for _, class in ipairs(T.CLASSES) do byClass[class] = {} end
	local trees = {}
	local fx, fy, fz = focus[1], focus[2], focus[3]
	for _, item in ipairs(items) do
		local class = item.class
		local dx, dy, dz = item.x - fx, item.y - fy, item.z - fz
		local d2 = dx * dx + dy * dy + dz * dz
		local keep = item.rank < b.density or item.kind == "hero" or class == "satellite" or class == "cliff"
		if keep then
			if class == "tree" then
				local r = b.farRadius * (if item.kind == "hero" then 1.8 else 1)
				if d2 <= r * r then table.insert(trees, {item, d2}) end
			elseif b[class] > 0 then
				local r = b[class .. "Radius"]
				if d2 <= r * r then table.insert(byClass[class], {item, d2}) end
			end
		end
	end
	table.sort(trees, function(a, c) return a[2] < c[2] end)
	local nearLeft, farLeft = b.near, b.far
	for _, t in ipairs(trees) do
		local item, d2 = t[1], t[2]
		local nr = b.nearRadius * (if item.kind == "hero" then 1.5 else 1)
		if nearLeft > 0 and d2 <= nr * nr then
			nearLeft -= 1
			table.insert(byClass.near, {item, d2, item.shape})
		elseif farLeft > 0 then
			farLeft -= 1
			table.insert(byClass.far, {item, d2, item.far})
		end
	end
	local out = {}
	for _, class in ipairs(T.CLASSES) do
		local list = byClass[class]
		if class ~= "near" and class ~= "far" then table.sort(list, function(a, c) return a[2] < c[2] end) end
		local cap = b[class]
		for i = 1, math.min(#list, cap) do
			local e = list[i]
			table.insert(out, {item = e[1], shape = e[3] or e[1].shape, class = class})
		end
	end
	return out
end
T.species = species
return T

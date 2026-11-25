-- MeshForge (client): custom meshes for parts tagged with the Shape attribute
-- (docs/DEPTH-CONTRACT.md §10). EditableMesh data is local to the machine that
-- creates it, so every client forges its own meshes: one EditableMesh-backed
-- MeshPart template per (shape, tint), cloned for tagged parts within BUILD_RADIUS
-- of the player and released beyond UNLOAD_RADIUS. The original part is hidden
-- only locally (LocalTransparencyModifier) once its mesh exists, stays the
-- collider/SurfaceGui surface, and is restored when the mesh is released. If the
-- API is unavailable, fails, or a budget is reached, the primitive stays visible
-- (no per-triangle fallback). The server never hides anything.
--
-- Attributes read on a tagged part (the "host"):
--   Shape (string)          catalog shape name (art/WorldCatalog.lua or art/PropCatalog.lua)
--   Tint (Color3)           colour for the shape's tint slots (default: the shape's own tint)
--   ShapeScale (number)     multiplier on the host's own slot box (default 1). Hosts the world
--                           already sizes to the prop pass nil/1; it is never an absolute size.
--   ShapeFit (string)       "Uniform" keeps proportions: the largest fit inside the slot box,
--                           standing on its floor; default stretches the fit box over the slot box
--   ShapeOwnsModel (bool)   the mesh stands for the whole Model: the slot box grows to cover
--                           every visible sibling BasePart (no Shape, not Neon) of the host's
--                           Model, and those siblings are hidden locally while the mesh exists
--   ShapeBox (Vector3)      declared slot box size (sign frames, §28): the mesh fills this box
--                           instead of the host's own; the host (a post, pole or plinth) stays
--                           the visible fallback and is hidden locally once the mesh exists
--   ShapeBoxOffset (Vector3) centre of the declared box in the host's local frame (default 0)
-- Resource slots (CropBed, OreVein) whose host is a gather node (GatherNode, §42) use
-- the catalog's shape for that resource (Catalog.resourceShape), so each crop patch
-- and ore node shows its own crop or ore. Shapes with an `along` axis (ropes, lines)
-- turn that axis onto the slot box's longest axis, so one rope mesh serves both a
-- hanging rope and a span between two points.
-- Slot box: the host's own box, in an upright frame. Catalog meshes are Y-up; a
-- cylinder's axis is its local X (disk() stands one up by rolling it 90 degrees),
-- so a cylinder host carries the mesh's up axis along its cylinder axis.
-- Legacy AetherSculpture anchors (SculptureScale without ShapeScale) and creatures
-- stay with mesh.client.lua. Local-only markers: ShapeDone / ShapeSkipped attributes
-- and an ObjectValue "ShapeMesh" under the part (never replicated).
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Phones and tablets get a smaller forge: fewer templates, fewer placed
-- triangles and a shorter build radius. §55 QC M3: the device class is the
-- shared rule in shared/Device.lua (AetherDevice), the same one npc.client.lua
-- sizes its outfit budgets by; without the module (headless harnesses) the
-- forge applies that rule itself (touch-only = phone class).
local mobile = false
do
	local Device = nil
	pcall(function()
		local module = ReplicatedStorage:WaitForChild("AetherDevice", 5)
		if module then Device = require(module) end
	end)
	if type(Device) == "table" and type(Device.isPhone) == "function" then
		pcall(function() mobile = Device.isPhone(UserInputService) == true end)
	else
		pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
	end
end
-- creatureReserve (§55 QC H1): placed triangles world props may never take, so
-- creatures (creatureVisual, which shares placedTriangles) always find room.
local LIMITS = if mobile then {
	templates = 24, templateTriangles = 50000, instances = 400, placedTriangles = 150000, failures = 3, -- §55: smooth organic shapes (2-4k near, <= 1.2k far)
	creatureReserve = 25000,
} else {
	templates = 72, -- distinct (shape, tint) EditableMeshes kept alive (§30: island hulls, bridges, landmarks; §40: +8 for the town buildings); idle ones are LRU-evicted
	templateTriangles = 240000, -- triangles across all cached EditableMeshes (§40: whole-building meshes are ~2k each; §55: organic trees / rocks 2-9k)
	instances = 900, -- placed MeshPart clones near the player
	placedTriangles = 900000, -- triangles across all placed clones (§55: smooth organic world shapes)
	failures = 3, -- template build failures before the forge stops trying
	creatureReserve = 80000, -- §55 QC H1: placed triangles kept for creatures
}
-- §55 QC H2/H3: organic world shapes carry a far LOD (catalog `far`, <= 1.2k
-- triangles, the same fit box). It is placed beyond FAR_LOD_RADIUS (phones 40,
-- desktop 150 studs; back to the near shape inside it, to far again past
-- 1.25x), and always on phones for a near shape over PHONE_TEMPLATE_TRIS.
local FAR_LOD_RADIUS = if mobile then 40 else 150
local FAR_LOD_HYSTERESIS = 1.25
local PHONE_TEMPLATE_TRIS = 3000
local BUILD_RADIUS, UNLOAD_RADIUS = if mobile then 250 else 400, if mobile then 310 else 480
-- Shapes seen from afar (island hulls, bridges, landmarks; catalog meta `range`)
-- forge within their own range, capped on phones; release at 1.2x that range.
local RANGE_CAP = if mobile then 900 else 1600
local STEP_SECONDS = 1
local BACKOFF_FIRST, BACKOFF_MAX = 2, 64 -- seconds between retries of a budget-skipped part
local OWN_LIMIT = 40 -- a ShapeOwnsModel host's Model must be this small (a prop, not an island)

local function loadCatalog(name)
	local module = ReplicatedStorage:WaitForChild(name, 15)
	if not module then return nil end
	local ok, catalog = pcall(require, module)
	if ok and type(catalog) == "table" and type(catalog.shapes) == "table" then return catalog end
	return nil
end
local catalogs = {}
-- AetherCreatureArt (§48): creature, pet, limb and overlay meshes, forged only
-- through the creature API below (creatures.client.lua), never from a Shape tag.
-- AetherOutfitArt (§52): NPC outfit pieces and trade props, forged only through
-- the outfit API below (npc.client.lua), in their own pool.
-- AetherTerrainArt (§54): island dressing (clutter, shrubs, trees, cliff dressing,
-- satellite rocks), forged only through the dress API below (terrain.client.lua).
for _, name in ipairs({"AetherWorldArt", "AetherArt", "AetherCreatureArt", "AetherOutfitArt", "AetherTerrainArt"}) do
	local catalog = loadCatalog(name)
	if catalog then table.insert(catalogs, catalog) end
end
-- World tags use descriptive prop names; map them onto catalog shapes so every
-- tagged prop gets a mesh. Names with no good match stay primitive by design.
local ALIASES = {
	Rock = "Boulder", CliffRock = "CliffPiece", OreVein = "OreVein2", Lamp = "StreetLamp", PineTree = "WindpineTree",
	-- Sign system (§28 v2: signs are billboards; only the ledger board is meshed).
	NoticeBoard = "SignNoticeBoard",
}
local RESOURCE_SLOTS = {CropBed = true, OreVein = true}
local function lookup(shapeName)
	shapeName = ALIASES[shapeName] or shapeName
	for _, catalog in ipairs(catalogs) do
		local data = catalog.shapes[shapeName]
		-- §48 QC M3: creature shapes stay packed (lazy) until a template needs them.
		if type(data) == "table" and (data.lazy == true or (type(data.vertices) == "table" and type(data.faces) == "table")) then return data, catalog end
	end
	return nil
end

-- Buildings (§40, catalog kind "building"): whole houses forge nearer on
-- phones, and furnished interiors (meta `interior`) only near the player (they
-- are seen through a door or a window), so a town never starves the template
-- budget of the props, bridges and hulls around it.
local BUILDING_RADIUS = if mobile then {shell = 120, interior = 14} else {shell = BUILD_RADIUS, interior = 120}
-- Build radius for a tagged part (catalog `range` for far-seen shapes).
local rangeCache = setmetatable({}, {__mode = "k"})
local function buildRadius(part)
	local cached = rangeCache[part]
	if cached then return cached end
	local radius = BUILD_RADIUS
	local shapeName = part:GetAttribute("Shape")
	local data = type(shapeName) == "string" and lookup(shapeName)
	if data and type(data.range) == "number" and data.range > BUILD_RADIUS then radius = math.min(data.range, RANGE_CAP) end
	if data and data.kind == "building" then radius = math.min(radius, if data.interior then BUILDING_RADIUS.interior else BUILDING_RADIUS.shell) end
	rangeCache[part] = radius
	return radius
end
-- Release radius: beyond it a placed clone goes back to its primitive. Props
-- keep the UNLOAD_RADIUS hysteresis; buildings (§40 QC M2) release just past
-- their own (short) build radius, so a phone's house shells (120) and
-- interiors (14) hand their templates back instead of holding them to 310.
-- Interiors get +10 studs (at least) so stepping back out of a door does not flicker.
local function releaseRadius(part)
	local radius = buildRadius(part)
	local shapeName = part:GetAttribute("Shape")
	local data = type(shapeName) == "string" and lookup(shapeName)
	if data and data.kind == "building" then
		return if data.interior then math.max(radius * 1.2, radius + 10) else radius * 1.2
	end
	return math.max(UNLOAD_RADIUS, radius * 1.2)
end

-- Final catalog shape name for a tagged part (resource slot, then alias).
local function shapeOf(part)
	local shapeName = part:GetAttribute("Shape")
	if type(shapeName) ~= "string" then return nil end
	if RESOURCE_SLOTS[shapeName] then
		-- §42: a struck node host names its resource (GatherNode); older hosts a prompt's IsleItem.
		local item = part:GetAttribute("GatherNode")
		if type(item) ~= "string" then
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			item = prompt and prompt:GetAttribute("IsleItem")
		end
		if type(item) == "string" then
			for _, catalog in ipairs(catalogs) do
				local resolved = type(catalog.resourceShape) == "function" and catalog.resourceShape(item)
				if type(resolved) == "string" and lookup(resolved) then return resolved end
			end
		end
	end
	return ALIASES[shapeName] or shapeName
end

local stats = {templates = 0, templateTriangles = 0, creatureTemplates = 0, creatureTriangles = 0, outfitTemplates = 0, outfitTriangles = 0, outfitInstances = 0, outfitPlaced = 0, dressTemplates = 0, dressTriangles = 0, dressInstances = 0, dressPlaced = 0, grounds = 0, groundTriangles = 0, instances = 0, placedTriangles = 0, failures = 0, skipped = 0, evicted = 0, templateSkips = 0, reclaimed = 0,
	chartPins = 0, chartRevoked = 0, chartRefused = 0}
-- Indexing a missing member errors on an Instance, so probe the API under pcall.
local available = pcall(function()
	assert(typeof(AssetService.CreateEditableMesh) == "function" and typeof(AssetService.CreateMeshPartAsync) == "function")
	assert(Content ~= nil and Content.fromObject ~= nil)
end)
local stopReason = if available then nil else "unavailable"
local newTemplatesBlocked = false
-- key -> {part, mesh, extent, center, triangles, users, used, key, chartPins} | false (failed)
-- | {pending = true, waiters} while its first build is in flight (CreateMeshPartAsync
-- yields): the slot is already counted, and concurrent callers wait for it.
local templates = {}
-- Sign kit shapes (§28; see templateTint below).
local SIGN_KIT_SHAPES = {SignNoticeBoard = true} -- §28 v2: the one sign mesh left (ledger notice boards)
local useTick = 0 -- LRU clock: bumped whenever a template gains or loses a clone
-- Tint variants per shape: a shape keeps at most VARIANTS templates (desktop 2,
-- phones 1); a further tint reuses the shape's nearest existing variant. Legacy
-- sign shapes (kind "sign" outside the kit: pennants, cloth, ledgers) are exempt
-- so their colours stay exact (they are few), as are exactTint shapes on desktop.
local VARIANTS = if mobile then 1 else 2
-- §48 creatures: their shapes keep the exact creature colour on desktop (like
-- exactTint) under their own template sub-cap; phones share one variant.
local CREATURE_KINDS = {creature = true, pet = true, limb = true, overlay = true}
local CREATURE_TEMPLATE_CAP = if mobile then 8 else 22
local CREATURE_TRIANGLE_CAP = if mobile then 14000 else 44000 -- triangles across creature templates
-- QC H1: part of the creature pool only boss / world tiers may use, so a crowd
-- of pets and critters can never lock a boss out of its meshes.
local CREATURE_BOSS_RESERVE = if mobile then 3 else 6
local CREATURE_BOSS_TRIANGLES = if mobile then 6000 else 14000
-- QC M4: the creature pool keeps its own failure counter and blocked / stop
-- flags; a broken creature mesh never stops the world forge (and vice versa).
local creaturePool = {failures = 0, blocked = false, stop = stopReason} -- (no EditableMesh API: both pools stop)
-- §52 NPC outfits: their own pool beside the world's and the creatures' (a busy
-- town square never starves the creatures, and vice versa). Desktop keeps the
-- exact dye (npc.client.lua quantises to Data's NpcStyle dyes); phones share one
-- variant per shape. Only idle outfit templates are evicted for outfits (LRU).
local OUTFIT_KINDS = {outfit = true}
local OUTFIT_TEMPLATE_CAP = if mobile then 18 else 52
local OUTFIT_TRIANGLE_CAP = if mobile then 20000 else 160000 -- §55 QC M3: per-NPC outfit budgets (NpcStyle.NPC_TRIS, NpcStyle.POOL)
-- QC H1 / L: outfit clones are counted on their own (never against the world's
-- LIMITS.instances / placedTriangles), bounded by the dressed-NPC cap.
local OUTFIT_INSTANCE_CAP = if mobile then 40 else 120
local outfitPool = {failures = 0, blocked = false, stop = stopReason}
-- §54 island dressing: its own pool (templates, triangles, clones) beside the
-- world's, the creatures' and the outfits', so a meadow full of grass never
-- starves hulls, buildings or creatures. terrain.client.lua applies the
-- per-tier caps (shared/TerrainArt.lua) under these hard ceilings. Desktop keeps
-- each region tint; phones share one variant per shape.
local DRESS_KINDS = {clutter = true, shrub = true, foliage = true, cliff = true, satellite = true}
-- §54 QC M7: phones keep a 12-template dress pool; H1: desktop keeps at most
-- VARIANTS (2) tint templates per dressing shape like every other world shape.
local DRESS_TEMPLATE_CAP = if mobile then 12 else 44
local DRESS_TRIANGLE_CAP = if mobile then 40000 else 160000
local DRESS_INSTANCE_CAP = if mobile then 120 else 720
local DRESS_PLACED_CAP = if mobile then 240000 else 1000000
-- M7: a pool blocked by a memory / budget error retries after BLOCK_RETRY seconds.
local BLOCK_RETRY = 60
local dressPool = {failures = 0, blocked = false, blockedAt = 0, stop = stopReason}
-- Forged ground tops and cliff walls (one unique EditableMesh each, no template).
-- H2: their own failure counter and stop flag (a failing ground never stops the
-- dressing, and vice versa).
local GROUND_CAP = if mobile then 4 else 8 -- meshes (a ground and a wall per island)
local GROUND_TRIANGLE_CAP = if mobile then 24000 else 90000
local groundPool = {failures = 0, stop = stopReason}
local variants = {} -- shapeName -> {key -> tint | false}
local function tintDistance(a, b)
	if not a or not b then return if a == b then 0 else 1 end
	local dr, dg, db = a.R - b.R, a.G - b.G, a.B - b.B
	return 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
end
-- Nearest existing template of the shape (nil when it has none).
local function nearestVariant(shapeName, tint)
	local best, bestDistance = nil, math.huge
	for key, variantTint in pairs(variants[shapeName] or {}) do
		local entry = templates[key]
		local distance = tintDistance(tint, variantTint or nil)
		if entry and not entry.pending and distance < bestDistance then best, bestDistance = entry, distance end
	end
	return best
end
local function variantCount(shapeName)
	local n = 0
	for key in pairs(variants[shapeName] or {}) do if templates[key] then n += 1 end end
	return n
end

-- Colours ------------------------------------------------------------------
local function paletteColor(catalog, index, tint)
	local tintIndex = catalog.tintIndex or 11
	if tint then
		if index == tintIndex then return tint end
		if catalog.tintDarkIndex and index == catalog.tintDarkIndex then
			local k = catalog.tintDark or 0.62
			return Color3.new(tint.R * k, tint.G * k, tint.B * k)
		end
		if catalog.tintLightIndex and index == catalog.tintLightIndex then
			return tint:Lerp(Color3.new(1, 1, 1), catalog.tintLight or 0.4)
		end
	end
	local hex = catalog.palette[index]
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else Color3.new(0.6, 0.6, 0.6)
end
local function defaultTint(data)
	if type(data.tint) == "string" then
		local ok, color = pcall(Color3.fromHex, data.tint)
		if ok then return color end
	end
	return nil
end

-- Geometry -----------------------------------------------------------------
local function bounds(data)
	-- §55 QC H3: lazy world shapes carry their bounds (box), so placing one never decodes it.
	local box = rawget(data, "box")
	if type(box) == "table" and type(box[1]) == "table" and type(box[2]) == "table" then
		return Vector3.new(box[1][1], box[1][2], box[1][3]), Vector3.new(box[2][1], box[2][2], box[2][3])
	end
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, xyz in ipairs(data.vertices) do
		local v = Vector3.new(xyz[1], xyz[2], xyz[3])
		lo, hi = lo:Min(v), hi:Max(v)
	end
	return lo, hi
end
-- Per-corner normals: area-weighted face normals averaged within the crease angle.
local function cornerNormals(data)
	local crease = tonumber(data.smooth) or 0
	local points = {}
	for i, xyz in ipairs(data.vertices) do points[i] = Vector3.new(xyz[1], xyz[2], xyz[3]) end
	local faceNormal, faceWeight, around = {}, {}, {}
	for f, face in ipairs(data.faces) do
		local raw = (points[face[2]] - points[face[1]]):Cross(points[face[3]] - points[face[1]])
		faceWeight[f] = raw.Magnitude
		faceNormal[f] = if raw.Magnitude > 0 then raw.Unit else Vector3.yAxis
		for k = 1, 3 do
			local list = around[face[k]]
			if not list then list = {}; around[face[k]] = list end
			table.insert(list, f)
		end
	end
	local limit = math.cos(math.rad(crease))
	local result = {}
	for f, face in ipairs(data.faces) do
		local n = faceNormal[f]
		if crease <= 0 then
			result[f] = {n, n, n}
		else
			local corners = {}
			for k = 1, 3 do
				local sum = Vector3.zero
				for _, other in ipairs(around[face[k]]) do
					if faceNormal[other]:Dot(n) >= limit then sum += faceNormal[other] * faceWeight[other] end
				end
				corners[k] = if sum.Magnitude > 0 then sum.Unit else n
			end
			result[f] = corners
		end
	end
	return result
end

-- §54 QC A1: per-vertex colour for every catalog. Each face's palette colour
-- (tinted) takes two continuous fields at its centre (a height ramp / ambient
-- occlusion by depth, and low-frequency 3D value noise whose wavelength is six
-- mean edge lengths), is spread onto its vertices per material family (the
-- catalog's `families`; a shape's `blend` indices join its tint family), then
-- diffused over the mesh until no edge inside a family changes luminance by more
-- than VERTEX_DL (at most VERTEX_PASSES passes). Different families keep a hard
-- seam (bark against leaf). Returns the unique colours and, per face, the colour
-- index of each corner.
local VERTEX_DL, VERTEX_PASSES = 0.05, 32
local function luma(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
local function vhash(x, y, z)
	local h = bit32.bxor(bit32.band(x * 73856093, 0xFFFFFFFF), bit32.band(y * 19349663, 0xFFFFFFFF), bit32.band(z * 83492791, 0xFFFFFFFF))
	h = bit32.band(bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177 % 4294967296, 0xFFFFFFFF)
	return bit32.bxor(h, bit32.rshift(h, 16)) / 4294967295
end
local function vnoise(x, y, z)
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = x - ix, y - iy, z - iz
	fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
	local function c(a, b, d) return vhash(ix + a, iy + b, iz + d) end
	local x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * fx
	local x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * fx
	local x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * fx
	local x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * fx
	return ((x00 + (x10 - x00) * fy) + ((x01 + (x11 - x01) * fy) - (x00 + (x10 - x00) * fy)) * fz) * 2 - 1
end
local function vertexColors(data, catalog, tint)
	local families = catalog.families or {}
	local blend = {}
	if type(data.blend) == "table" then for _, i in ipairs(data.blend) do blend[i] = true end end
	local tintFamily = families[catalog.tintIndex or 11] or (catalog.tintIndex or 11)
	local function familyOf(shade) return if blend[shade] then tintFamily else (families[shade] or shade) end
	local verts, faces = data.vertices, data.faces
	local lo, hi, edgeSum, edgeCount = math.huge, -math.huge, 0, 0
	for _, v in ipairs(verts) do lo, hi = math.min(lo, v[2]), math.max(hi, v[2]) end
	for _, f in ipairs(faces) do
		local a, b = verts[f[1]], verts[f[2]]
		edgeSum += math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
		edgeCount += 1
	end
	local wave = math.max(0.05, 6 * edgeSum / math.max(1, edgeCount))
	local span = math.max(1e-3, hi - lo)
	local R, G, B, W, fam, keyOf = {}, {}, {}, {}, {}, {}
	local cache = {}
	for f, face in ipairs(faces) do
		local shade = face[4]
		local base = cache[shade]
		if not base then base = paletteColor(catalog, shade, tint); cache[shade] = base end
		local a, b, c = verts[face[1]], verts[face[2]], verts[face[3]]
		local cx, cy, cz = (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3, (a[3] + b[3] + c[3]) / 3
		-- Ambient occlusion by depth (feet and undersides darker) and soft mottling.
		local t = (cy - lo) / span
		local k = (0.86 + 0.14 * t * t * (3 - 2 * t)) * (1 + 0.05 * vnoise(cx / wave, cy / wave, cz / wave))
		local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
		local area = math.sqrt((uy * vz - uz * vy) ^ 2 + (uz * vx - ux * vz) ^ 2 + (ux * vy - uy * vx) ^ 2) + 1e-9
		local family = familyOf(shade)
		fam[f] = family
		local keys = {}
		for k2 = 1, 3 do
			local key = face[k2] * 512 + (family % 512)
			keys[k2] = key
			R[key] = (R[key] or 0) + base.R * k * area
			G[key] = (G[key] or 0) + base.G * k * area
			B[key] = (B[key] or 0) + base.B * k * area
			W[key] = (W[key] or 0) + area
		end
		keyOf[f] = keys
	end
	local list, index = {}, {}
	for key, w in pairs(W) do
		R[key], G[key], B[key] = R[key] / w, G[key] / w, B[key] / w
		table.insert(list, key)
	end
	table.sort(list)
	for i, key in ipairs(list) do index[key] = i end
	-- Same-family neighbours (edges of faces of that family).
	local nbr = {}
	for i in ipairs(list) do nbr[i] = {} end
	local seen = {}
	for f in ipairs(faces) do
		local keys = keyOf[f]
		for k2 = 1, 3 do
			local a, b = index[keys[k2]], index[keys[k2 % 3 + 1]]
			local pair = if a < b then a * 1048576 + b else b * 1048576 + a
			if a ~= b and not seen[pair] then
				seen[pair] = true
				table.insert(nbr[a], b)
				table.insert(nbr[b], a)
			end
		end
	end
	local r, g, b = {}, {}, {}
	for i, key in ipairs(list) do r[i], g[i], b[i] = R[key], G[key], B[key] end
	local passes = 0
	while passes < VERTEX_PASSES do
		local worst = 0
		for i = 1, #list do
			local li = luma(r[i], g[i], b[i])
			for _, j in ipairs(nbr[i]) do
				local d = math.abs(li - luma(r[j], g[j], b[j]))
				if d > worst then worst = d end
			end
		end
		if worst <= VERTEX_DL then break end
		passes += 1
		local nr, ng, nb = {}, {}, {}
		for i = 1, #list do
			local n = #nbr[i]
			if n == 0 then nr[i], ng[i], nb[i] = r[i], g[i], b[i]
			else
				local sr, sg, sb = 0, 0, 0
				for _, j in ipairs(nbr[i]) do sr += r[j]; sg += g[j]; sb += b[j] end
				nr[i], ng[i], nb[i] = 0.5 * r[i] + 0.5 * sr / n, 0.5 * g[i] + 0.5 * sg / n, 0.5 * b[i] + 0.5 * sb / n
			end
		end
		r, g, b = nr, ng, nb
	end
	local colors = {}
	for i = 1, #list do colors[i] = Color3.new(math.clamp(r[i], 0, 1), math.clamp(g[i], 0, 1), math.clamp(b[i], 0, 1)) end
	local corners = {}
	for f in ipairs(faces) do
		local keys = keyOf[f]
		corners[f] = {index[keys[1]], index[keys[2]], index[keys[3]]}
	end
	return colors, corners, passes, nbr, fam
end
-- Foliage normals (§54 A5): a shape's `sphere` entries {x, y, z, r, blend} bend
-- the shading normals of its tint-family faces within r of the centre toward
-- the radial direction, so a lobed canopy shades like one soft volume.
local function sphereNormals(data, catalog, normals)
	if type(data.sphere) ~= "table" then return normals end
	local families = catalog.families or {}
	local tintFamily = families[catalog.tintIndex or 11] or (catalog.tintIndex or 11)
	for f, face in ipairs(data.faces) do
		if (families[face[4]] or face[4]) == tintFamily then
			for k = 1, 3 do
				local v = data.vertices[face[k]]
				local p = Vector3.new(v[1], v[2], v[3])
				for _, s in ipairs(data.sphere) do
					local c = Vector3.new(s[1], s[2], s[3])
					local d = p - c
					if d.Magnitude <= s[4] and d.Magnitude > 1e-4 then
						local n = normals[f][k]:Lerp(d.Unit, s[5])
						normals[f][k] = if n.Magnitude > 1e-4 then n.Unit else normals[f][k]
						break
					end
				end
			end
		end
	end
	return normals
end

local function buildTemplate(shapeName, data, catalog, tint)
	local mesh
	local ok, result = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "CreateEditableMesh returned nil")
		local ids = {}
		for i, xyz in ipairs(data.vertices) do ids[i] = mesh:AddVertex(Vector3.new(xyz[1], xyz[2], xyz[3])) end
		local colorIds, normalIds = {}, {}
		local normals = sphereNormals(data, catalog, cornerNormals(data))
		local colors, corners = vertexColors(data, catalog, tint)
		for i, color in ipairs(colors) do colorIds[i] = mesh:AddColor(color, 1) end
		for f, face in ipairs(data.faces) do
			local triangle = mesh:AddTriangle(ids[face[1]], ids[face[2]], ids[face[3]])
			local cc = corners[f]
			mesh:SetFaceColors(triangle, {colorIds[cc[1]], colorIds[cc[2]], colorIds[cc[3]]})
			local corner = {}
			for k, n in ipairs(normals[f]) do
				local key = string.format("%.3f,%.3f,%.3f", n.X, n.Y, n.Z)
				local id = normalIds[key]
				if not id then id = mesh:AddNormal(n); normalIds[key] = id end
				corner[k] = id
			end
			mesh:SetFaceNormals(triangle, corner)
		end
		local content = Content.fromObject(mesh)
		local okOptions, part = pcall(AssetService.CreateMeshPartAsync, AssetService, content, {CollisionFidelity = Enum.CollisionFidelity.Box})
		if not okOptions or not part then part = AssetService:CreateMeshPartAsync(content) end
		assert(part and part:IsA("MeshPart"), "CreateMeshPartAsync returned no MeshPart")
		part.Name = shapeName
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.new(1, 1, 1)
		return part
	end)
	if ok then return result, mesh end
	if mesh then pcall(mesh.Destroy, mesh) end
	return nil, nil, tostring(result)
end

-- LRU eviction: when a new template would pass the template or triangle cap,
-- templates with no live clone are destroyed, least recently used first.
-- §48: creature templates live in their own budget (CREATURE_TEMPLATE_CAP /
-- CREATURE_TRIANGLE_CAP) beside the world's LIMITS, so a busy town never
-- starves the creatures and a crowd of creatures never starves the town; each
-- pool evicts only its own idle templates.
local function worldCounts() return stats.templates - stats.creatureTemplates - stats.outfitTemplates - stats.dressTemplates, stats.templateTriangles - stats.creatureTriangles - stats.outfitTriangles - stats.dressTriangles end
local function fits(creature, triangles, boss, outfit, dress)
	if dress then return stats.dressTemplates < DRESS_TEMPLATE_CAP and stats.dressTriangles + triangles <= DRESS_TRIANGLE_CAP end
	if outfit then return stats.outfitTemplates < OUTFIT_TEMPLATE_CAP and stats.outfitTriangles + triangles <= OUTFIT_TRIANGLE_CAP end
	if creature then
		local count, tris = CREATURE_TEMPLATE_CAP, CREATURE_TRIANGLE_CAP
		if not boss then count, tris = count - CREATURE_BOSS_RESERVE, tris - CREATURE_BOSS_TRIANGLES end
		return stats.creatureTemplates < count and stats.creatureTriangles + triangles <= tris
	end
	local count, tris = worldCounts()
	return count < LIMITS.templates and tris + triangles <= LIMITS.templateTriangles
end
local function dropTemplate(key, entry)
	templates[key] = nil
	if variants[entry.shape] then variants[entry.shape][key] = nil end
	stats.templates -= 1
	stats.templateTriangles -= entry.triangles
	if entry.creature then
		stats.creatureTemplates -= 1
		stats.creatureTriangles -= entry.triangles
	end
	if entry.outfit then
		stats.outfitTemplates -= 1
		stats.outfitTriangles -= entry.triangles
	end
	if entry.dress then
		stats.dressTemplates -= 1
		stats.dressTriangles -= entry.triangles
	end
	stats.evicted += 1
	pcall(entry.part.Destroy, entry.part)
	if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
end
local function evictFor(triangles, creature, boss, outfit, dress)
	creature, outfit, dress = creature == true, outfit == true, dress == true
	local idle = {}
	for key, entry in pairs(templates) do
		if entry and not entry.pending and entry.users == 0 and (entry.creature == true) == creature and (entry.outfit == true) == outfit and (entry.dress == true) == dress then table.insert(idle, {key, entry}) end
	end
	table.sort(idle, function(a, b) return a[2].used < b[2].used end)
	for _, item in ipairs(idle) do
		if fits(creature, triangles, boss, outfit, dress) then break end
		dropTemplate(item[1], item[2])
	end
	return fits(creature, triangles, boss, outfit, dress)
end
local function template(shapeName, data, catalog, tint, boss)
	local key = shapeName .. "#" .. (if tint then tint:ToHex() else "")
	local cached = templates[key]
	if cached and cached.pending then
		-- Another thread is building this template (CreateMeshPartAsync yields):
		-- wait for its result instead of building (and leaking) a second one.
		table.insert(cached.waiters, coroutine.running())
		return coroutine.yield()
	end
	if cached ~= nil then return cached or nil end
	-- exactTint shapes (travel beacons, §44: small, few per island, coloured by
	-- region) keep their exact Tint on desktop; phones share variants as usual.
	if variantCount(shapeName) >= VARIANTS and not (data.kind == "sign" and not SIGN_KIT_SHAPES[shapeName])
		and not (data.exactTint == true and not mobile) and not (CREATURE_KINDS[data.kind] and (not mobile or boss))
		and not (OUTFIT_KINDS[data.kind] and not mobile) then
		return nearestVariant(shapeName, tint)
	end
	local triangles = data.tris or #data.faces
	local creature = CREATURE_KINDS[data.kind] == true
	local outfit = OUTFIT_KINDS[data.kind] == true
	local dress = DRESS_KINDS[data.kind] == true
	if dress and dressPool.blocked and os.clock() - dressPool.blockedAt >= BLOCK_RETRY then dressPool.blocked = false end -- M7
	local stopped = if dress then (dressPool.stop or dressPool.blocked) elseif outfit then (outfitPool.stop or outfitPool.blocked) elseif creature then (creaturePool.stop or creaturePool.blocked) else (stopReason or newTemplatesBlocked)
	if stopped or (not fits(creature, triangles, boss, outfit, dress) and not evictFor(triangles, creature, boss, outfit, dress)) then
		stats.templateSkips += 1
		return nil, "budget"
	end
	-- Reserve the slot before the build yields, so concurrent callers see it.
	local marker = {pending = true, waiters = {}, users = 0, used = 0, triangles = triangles, shape = shapeName, creature = creature, outfit = outfit, dress = dress}
	templates[key] = marker
	stats.templates += 1
	stats.templateTriangles += triangles
	if creature then
		stats.creatureTemplates += 1
		stats.creatureTriangles += triangles
	end
	if outfit then
		stats.outfitTemplates += 1
		stats.outfitTriangles += triangles
	end
	if dress then
		stats.dressTemplates += 1
		stats.dressTriangles += triangles
	end
	local part, mesh, problem = buildTemplate(shapeName, data, catalog, tint)
	local entry, reason = nil, nil
	if not part then
		templates[key] = false
		stats.templates -= 1
		stats.templateTriangles -= triangles
		if creature then
			stats.creatureTemplates -= 1
			stats.creatureTriangles -= triangles
		end
		if outfit then
			stats.outfitTemplates -= 1
			stats.outfitTriangles -= triangles
		end
		if dress then
			stats.dressTemplates -= 1
			stats.dressTriangles -= triangles
		end
		local message = string.lower(problem or "")
		local blocked = message:find("budget", 1, true) or message:find("memory", 1, true) or message:find("limit", 1, true)
		if dress then
			dressPool.failures += 1
			if blocked then dressPool.blocked = true; dressPool.blockedAt = os.clock() end
			if dressPool.failures >= LIMITS.failures then dressPool.stop = "unavailable" end
		elseif outfit then
			outfitPool.failures += 1
			if blocked then outfitPool.blocked = true end
			if outfitPool.failures >= LIMITS.failures then outfitPool.stop = "unavailable" end
		elseif creature then
			creaturePool.failures += 1
			if blocked then creaturePool.blocked = true end
			if creaturePool.failures >= LIMITS.failures then creaturePool.stop = "unavailable" end
		else
			stats.failures += 1
			if blocked then newTemplatesBlocked = true end
			if stats.failures >= LIMITS.failures then stopReason = "unavailable" end
		end
		warn("[MeshForge] " .. shapeName .. " could not be meshed: " .. tostring(problem))
		reason = "failed"
	else
		local lo, hi = bounds(data)
		useTick += 1
		entry = {part = part, mesh = mesh, extent = (hi - lo):Max(Vector3.one * 0.01), center = (lo + hi) / 2, triangles = triangles,
			users = 0, used = useTick, shape = shapeName, key = key, chartPins = 0, creature = creature, outfit = outfit, dress = dress}
		variants[shapeName] = variants[shapeName] or {}
		variants[shapeName][key] = tint or false
		part.Size = entry.extent
		templates[key] = entry
		-- QC M3: the template holds the geometry now; forget the decoded arrays.
		if type(catalog.drop) == "function" then pcall(catalog.drop, shapeName) end
	end
	for _, waiter in ipairs(marker.waiters) do task.spawn(waiter, entry, reason) end
	return entry, reason
end

-- Signs: the original board keeps its SurfaceGui (the meshed frame wraps it);
-- text gets one consistent, higher-contrast style.
local SIGN_KINDS = {sign = true}
-- Sign kit (§28 v2): only the ledger notice board is still a sign mesh; its
-- Tint snaps to KIT_METALS on desktop and shares the default template on
-- phones. Every other kind "sign" shape (legacy Banner, Signboard,
-- SignboardPosted, SignPost: pennants, agility cloth, crew pennant) keeps its
-- Tint on every device.
local function hexColors(list)
	local out = {}
	for i, hex in ipairs(list) do out[i] = Color3.fromHex(hex) end
	return out
end
local KIT_METALS = hexColors({"C9A24E", "B0B8C4", "6FA898"}) -- brass, silver, verdigris
local function nearestColor(color, palette)
	local best, bestDistance = palette[1], math.huge
	for _, c in ipairs(palette) do
		local dr, dg, db = color.R - c.R, color.G - c.G, color.B - c.B
		local distance = 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
		if distance < bestDistance then best, bestDistance = c, distance end
	end
	return best
end
-- Template tint for a host: the Tint itself, or its quantised kit colour.
local function templateTint(shapeName, data, tint)
	if typeof(tint) ~= "Color3" then return defaultTint(data) end
	-- Phones: island hulls, bridges and far-seen landmarks (forged out to 900
	-- studs, always in use) share their default-tint template.
	if mobile and (data.kind == "rock" or data.kind == "bridge" or type(data.range) == "number") then return defaultTint(data) end
	if not SIGN_KIT_SHAPES[shapeName] then return tint end
	if mobile then return defaultTint(data) end
	return nearestColor(tint, KIT_METALS)
end
local fonts
local function signFonts()
	if fonts == nil then
		fonts = false
		pcall(function()
			fonts = {
				title = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
				body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
			}
		end)
	end
	return fonts or nil
end
local INK = Color3.fromRGB(12, 18, 26)
local function luminance(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function styleSign(part)
	for _, gui in ipairs(part:GetDescendants()) do
		if gui:IsA("SurfaceGui") and not gui:GetAttribute("SignStyled") then
			gui:SetAttribute("SignStyled", true)
			pcall(function() gui.LightInfluence = 0 end)
			for _, label in ipairs(gui:GetDescendants()) do
				if label:IsA("TextLabel") or label:IsA("TextButton") then
					local height = label.Size.Y.Offset
					local title = height >= 44 or (not label.TextScaled and label.TextSize >= 30)
					local chosen = signFonts()
					if chosen then pcall(function() label.FontFace = if title then chosen.title else chosen.body end) end
					if luminance(label.TextColor3) < 0.45 then label.TextColor3 = label.TextColor3:Lerp(Color3.new(1, 1, 1), 0.55) end
					if label.TextScaled and height > 0 and not label:FindFirstChildOfClass("UITextSizeConstraint") then
						local limit = Instance.new("UITextSizeConstraint")
						limit.MaxTextSize = math.max(12, math.floor(height * 0.8))
						limit.Parent = label
					end
					if not label:FindFirstChildOfClass("UIStroke") then
						local stroke = Instance.new("UIStroke")
						stroke.Color = INK
						stroke.Thickness = if title then 2 else 1.25
						stroke.Transparency = 0.35
						stroke.Parent = label
					end
				end
			end
		end
	end
end

-- Placement ----------------------------------------------------------------
-- Strong tables: step() drops a part (and releases its mesh) once it has no Parent, so
-- nothing leaks, and a part is never forgotten while it is still in the world.
local registry = {} -- tagged parts this client knows
local placed = {} -- part -> {visual, triangles, connections, decals, hidden, entry}
local final = setmetatable({}, {__mode = "k"}) -- permanently skipped parts
-- Budget skips back off exponentially (2 s, 4 s, ... 64 s) instead of retrying
-- every step; any release frees budget and lets every backed-off part retry.
local backoff = setmetatable({}, {__mode = "k"}) -- part -> {at, delay, epoch}
local budgetEpoch = 0
local function waiting(part)
	local entry = backoff[part]
	return entry ~= nil and entry.epoch == budgetEpoch and os.clock() < entry.at
end
local function skip(part, reason, permanent)
	if permanent then final[part] = true
	else
		local delay = math.min(BACKOFF_MAX, if backoff[part] then backoff[part].delay * 2 else BACKOFF_FIRST)
		backoff[part] = {at = os.clock() + delay, delay = delay, epoch = budgetEpoch}
	end
	if part:GetAttribute("ShapeSkipped") ~= reason then
		stats.skipped += 1
		pcall(part.SetAttribute, part, "ShapeSkipped", reason)
	end
end
-- Slot box: an upright frame and size for the host (see header).
local function hostFrame(part)
	if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		local size = part.Size
		return part.CFrame * CFrame.Angles(0, 0, -math.pi / 2), Vector3.new(size.Y, size.X, size.Z)
	end
	return part.CFrame, part.Size
end
-- Siblings a ShapeOwnsModel mesh stands for (nil when the host owns nothing).
-- Neon accents (flames, glowing cores) stay visible over the mesh.
local function ownedSiblings(part)
	if part:GetAttribute("ShapeOwnsModel") ~= true then return nil end
	local model = part.Parent
	if not model or not model:IsA("Model") then return nil end
	local children = model:GetChildren()
	if #children > OWN_LIMIT then return nil end
	local list = {}
	for _, child in ipairs(children) do
		if child ~= part and child:IsA("BasePart") and child:GetAttribute("Shape") == nil and child.Transparency < 1
			and child.Material ~= Enum.Material.Neon then
			table.insert(list, child)
		end
	end
	return list
end
local function slotBox(part, siblings)
	local frame, size = hostFrame(part)
	local declared = part:GetAttribute("ShapeBox")
	if typeof(declared) == "Vector3" and declared.X > 0 and declared.Y > 0 and declared.Z > 0 then
		local offset = part:GetAttribute("ShapeBoxOffset")
		return part.CFrame * CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.new()), declared
	end
	if not siblings or #siblings == 0 then return frame, size end
	local lo, hi = -size / 2, size / 2
	for _, other in ipairs(siblings) do
		local rel = frame:ToObjectSpace(other.CFrame)
		local h = other.Size / 2
		local r, u, l = rel.RightVector, rel.UpVector, rel.LookVector
		local reach = Vector3.new(
			math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
			math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
			math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
		lo, hi = lo:Min(rel.Position - reach), hi:Max(rel.Position + reach)
	end
	return frame * CFrame.new((lo + hi) / 2), hi - lo
end
local boundsCache = setmetatable({}, {__mode = "k"})
local function meshBounds(data)
	local cached = boundsCache[data]
	if not cached then
		local lo, hi = bounds(data)
		cached = {extent = (hi - lo):Max(Vector3.one * 0.01), center = (lo + hi) / 2}
		boundsCache[data] = cached
	end
	return cached.extent, cached.center
end
-- `along` axis -> {slot's longest axis -> {rotation, size in the rotated frame}}.
local ALONG = {
	Y = {
		Z = {CFrame.Angles(math.pi / 2, 0, 0), function(b) return Vector3.new(b.X, b.Z, b.Y) end},
		X = {CFrame.Angles(0, 0, -math.pi / 2), function(b) return Vector3.new(b.Y, b.X, b.Z) end},
	},
	Z = {
		Y = {CFrame.Angles(-math.pi / 2, 0, 0), function(b) return Vector3.new(b.X, b.Z, b.Y) end},
		X = {CFrame.Angles(0, math.pi / 2, 0), function(b) return Vector3.new(b.Z, b.Y, b.X) end},
	},
}
-- Final mesh box for a host: size and world CFrame of the MeshPart.
local function layout(part, data, siblings)
	local extent, center = meshBounds(data)
	local shapeScale = part:GetAttribute("ShapeScale")
	shapeScale = if type(shapeScale) == "number" and shapeScale > 0 and shapeScale <= 100 then shapeScale else 1
	local lo, hi
	if type(data.fit) == "table" and type(data.fit[1]) == "table" and type(data.fit[2]) == "table" then
		lo, hi = Vector3.new(table.unpack(data.fit[1])), Vector3.new(table.unpack(data.fit[2]))
	else
		lo, hi = center - extent / 2, center + extent / 2
	end
	local fitSize = (hi - lo):Max(Vector3.one * 0.01)
	local boxFrame, box = slotBox(part, siblings)
	local turn = ALONG[data.along]
	if turn then
		local longest = if box.Y >= box.X and box.Y >= box.Z then "Y" elseif box.Z >= box.X then "Z" else "X"
		local spin = turn[longest]
		if spin then boxFrame, box = boxFrame * spin[1], spin[2](box) end
	end
	local target = (box * shapeScale):Max(Vector3.one * 0.05)
	local k = target / fitSize
	local lift = 0
	if part:GetAttribute("ShapeFit") == "Uniform" then
		local m = math.min(k.X, k.Y, k.Z)
		k = Vector3.new(m, m, m)
		lift = (fitSize.Y * m - target.Y) / 2 -- stand on the slot floor
	end
	return extent * k, boxFrame * CFrame.new((center - (lo + hi) / 2) * k + Vector3.new(0, lift, 0)), boxFrame, box
end

-- Release a placed mesh and give the primitive back (removal, distance, shutdown).
local function release(part)
	local record = placed[part]
	if not record then return end
	placed[part] = nil
	stats.instances -= 1
	stats.placedTriangles -= record.triangles
	useTick += 1
	record.entry.users -= 1
	record.entry.used = useTick
	for _, connection in ipairs(record.connections) do connection:Disconnect() end
	pcall(function() part.LocalTransparencyModifier = 0 end)
	for _, decal in ipairs(record.decals) do pcall(function() decal.LocalTransparencyModifier = 0 end) end
	for _, sibling in ipairs(record.hidden) do pcall(function() sibling.LocalTransparencyModifier = 0 end) end
	budgetEpoch += 1
	local link = part:FindFirstChild("ShapeMesh")
	if link then link:Destroy() end
	pcall(part.SetAttribute, part, "ShapeDone", nil)
	pcall(record.visual.Destroy, record.visual)
end

local reclaim -- defined with step() below
local chartYield -- defined with the chart API below
local starvedTemplate = false -- set by forge() when no template slot was free
local lastOrigin = nil -- the focus of the latest step (far LOD choice)
-- LOD for a host: the near shape, or its far LOD (name, data, catalog, forced).
local function lodOf(part, shapeName, data, catalog)
	if type(data.far) ~= "string" then return shapeName, data, catalog, false end
	local farData, farCatalog = lookup(data.far)
	if not farData then return shapeName, data, catalog, false end
	if mobile and (data.tris or #data.faces) > PHONE_TEMPLATE_TRIS then return data.far, farData, farCatalog, true end
	if lastOrigin and (part.CFrame.Position - lastOrigin).Magnitude > FAR_LOD_RADIUS then return data.far, farData, farCatalog, false end
	return shapeName, data, catalog, false
end
local function forge(part)
	if placed[part] or final[part] or not part.Parent then return end
	local shapeName = shapeOf(part)
	if not shapeName then return end
	if part:GetAttribute("SculptureScale") ~= nil and part:GetAttribute("ShapeScale") == nil then skip(part, "legacy sculpture", true); return end
	local data, catalog = lookup(shapeName)
	if not data then skip(part, "unknown shape", true); return end
	local lodForced = false
	shapeName, data, catalog, lodForced = lodOf(part, shapeName, data, catalog)
	-- §48: creature meshes are posed by creatures.client.lua, never Shape-tagged.
	if CREATURE_KINDS[data.kind] then skip(part, "creature shape", true); return end
	if OUTFIT_KINDS[data.kind] then skip(part, "outfit shape", true); return end
	if DRESS_KINDS[data.kind] then skip(part, "dress shape", true); return end
	if stopReason then skip(part, stopReason, true); return end
	-- §55 QC H1: world props leave LIMITS.creatureReserve of the placed budget to creatures.
	if stats.instances >= LIMITS.instances or stats.placedTriangles + (data.tris or #data.faces) > LIMITS.placedTriangles - LIMITS.creatureReserve then skip(part, "budget"); return end
	local tint = templateTint(shapeName, data, part:GetAttribute("Tint"))
	local entry, problem = template(shapeName, data, catalog, tint)
	if not entry and problem == "budget" then
		-- Reuse the shape's nearest existing variant rather than leaving a primitive.
		entry = nearestVariant(shapeName, tint)
	end
	if not entry then
		if problem == "budget" then starvedTemplate = true end
		skip(part, problem or stopReason or "failed", problem ~= "budget")
		return
	end
	if not part.Parent then return end
	local siblings = ownedSiblings(part)
	local size, meshFrame = layout(part, data, siblings)
	local offset = part.CFrame:ToObjectSpace(meshFrame)
	local ok, visual = pcall(function()
		local clone = entry.part:Clone()
		clone.Name = part.Name .. " Mesh"
		clone.Size = size
		clone.CFrame = meshFrame
		clone:SetAttribute("ShapeOf", shapeName)
		clone:SetAttribute("ShapeTriangles", entry.triangles) -- Map Art (§32) triangle budget
		clone.Parent = part.Parent
		return clone
	end)
	if not ok or not visual then skip(part, "clone failed", true); return end
	local record = {visual = visual, triangles = entry.triangles, connections = {}, decals = {}, hidden = {}, entry = entry,
		lod = if data.lod == "far" then "far" elseif type(data.far) == "string" then "near" else nil, lodForced = lodForced}
	placed[part] = record
	useTick += 1
	entry.users += 1
	entry.used = useTick
	stats.instances += 1
	stats.placedTriangles += entry.triangles
	-- Hide the primitive for this client only, now that its mesh exists.
	pcall(function() part.LocalTransparencyModifier = 1 end)
	local function hideDecals(host)
		for _, child in ipairs(host:GetChildren()) do
			if child:IsA("Decal") then
				table.insert(record.decals, child)
				pcall(function() child.LocalTransparencyModifier = 1 end)
			end
		end
	end
	hideDecals(part)
	-- ShapeOwnsModel: the mesh stands for the Model, so its primitive parts go too.
	for _, sibling in ipairs(siblings or {}) do
		table.insert(record.hidden, sibling)
		pcall(function() sibling.LocalTransparencyModifier = 1 end)
		hideDecals(sibling)
	end
	local link = Instance.new("ObjectValue")
	link.Name = "ShapeMesh"
	link.Value = visual
	link.Parent = part
	backoff[part] = nil
	part:SetAttribute("ShapeSkipped", nil)
	part:SetAttribute("ShapeDone", true)
	pcall(function()
		table.insert(record.connections, part:GetPropertyChangedSignal("CFrame"):Connect(function() visual.CFrame = part.CFrame * offset end))
		table.insert(record.connections, part.AncestryChanged:Connect(function() if not part:IsDescendantOf(workspace) then release(part) end end))
	end)
end

-- Distance streaming --------------------------------------------------------
local function focus()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.CFrame.Position end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end
-- Template reclaim: every template slot is held by live clones, yet a nearer
-- part is waiting. The template whose nearest clone is farthest away (at least
-- RECLAIM_MARGIN studs farther than the waiting part: 100, phones 40) gives its clones back to
-- their primitives, goes idle and is LRU-evicted for the nearer shape. Far
-- hulls and landmarks therefore yield to what the player is walking past.
-- §40: phones 24 (was 40): a town near an island centre holds a few more
-- templates, so a far sign or bridge must give way sooner.
local RECLAIM_MARGIN = if mobile then 24 else 100
reclaim = function(starved, origin)
	local users = {}
	for part, record in pairs(placed) do
		local d = (part.CFrame.Position - origin).Magnitude
		local u = users[record.entry]
		if not u then u = {min = d, parts = {}}; users[record.entry] = u end
		if d < u.min then u.min = d end
		table.insert(u.parts, part)
	end
	local order = {}
	for _, u in pairs(users) do table.insert(order, u) end
	table.sort(order, function(a, b) return a.min > b.min end)
	local k = 1
	for _, item in ipairs(starved) do
		local victim = order[k]
		if victim and victim.min >= item[2] + RECLAIM_MARGIN then
			k += 1
			for _, part in ipairs(victim.parts) do release(part) end
		elseif not chartYield() then
			-- Nothing far enough to give back, and no chart-only pin to drop.
			break
		end
		stats.reclaimed += 1
		starvedTemplate = false
		pcall(forge, item[1])
	end
end
local stepping = false
local function step()
	if stepping then return end
	stepping = true
	local origin = focus()
	lastOrigin = origin
	if origin then
		-- Releases first, so budget they free is available to this step's builds.
		local swapped = {} -- LOD swaps: rebuilt below even between the build and release radii
		for part in pairs(registry) do
			local record = placed[part]
			if not part.Parent then
				registry[part] = nil
				release(part)
			elseif record then
				local distance = (part.CFrame.Position - origin).Magnitude
				if distance > releaseRadius(part) then
					release(part)
				-- §55 QC H2: swap LODs (rebuilt below, nearest first) across FAR_LOD_RADIUS.
				elseif (record.lod == "near" and distance > FAR_LOD_RADIUS * FAR_LOD_HYSTERESIS)
					or (record.lod == "far" and not record.lodForced and distance < FAR_LOD_RADIUS) then
					release(part)
					swapped[part] = true
				end
			end
		end
		local near = {}
		for part in pairs(registry) do
			if not placed[part] and not final[part] and not waiting(part) then
				local distance = (part.CFrame.Position - origin).Magnitude
				if distance <= buildRadius(part) or swapped[part] then table.insert(near, {part, distance}) end
			end
		end
		-- Nearest first, so budgets are spent on what the player sees.
		table.sort(near, function(a, b) return a[2] < b[2] end)
		local starved = {}
		for _, item in ipairs(near) do
			starvedTemplate = false
			local ok, problem = pcall(forge, item[1])
			if not ok then warn("[MeshForge] " .. tostring(problem)); skip(item[1], "error", true)
			elseif starvedTemplate then table.insert(starved, item) end
		end
		if #starved > 0 then
			local ok, problem = pcall(reclaim, starved, origin)
			if not ok then warn("[MeshForge] reclaim: " .. tostring(problem)) end
		end
	end
	stepping = false
end
local function consider(part)
	if registry[part] or typeof(part) ~= "Instance" or not part:IsA("BasePart") or type(part:GetAttribute("Shape")) ~= "string" then return end
	-- §51: moving ship parts (ShapeManual) are forged on request (MeshForgeLocal "visual") and welded by sailing.client.lua.
	if part:GetAttribute("ShapeManual") then return end
	registry[part] = true
	local data = lookup(shapeOf(part))
	if data and SIGN_KINDS[data.kind] then pcall(styleSign, part) end
	-- Re-forge when the slot's attributes change (signals, not periodic rescans).
	pcall(function()
		part.AttributeChanged:Connect(function(name)
			if name ~= "Shape" and name ~= "ShapeScale" and name ~= "ShapeFit" and name ~= "Tint" and name ~= "ShapeOwnsModel"
				and name ~= "ShapeBox" and name ~= "ShapeBoxOffset" then return end
			release(part)
			final[part], backoff[part], rangeCache[part] = nil, nil, nil
			if type(part:GetAttribute("Shape")) ~= "string" then registry[part] = nil end
			task.defer(step)
		end)
	end)
	task.defer(step)
end
local DRESS_ROOT = "IsleDressing" -- terrain.client.lua's local clones (M6: never watched)
local function watch(instance)
	if not instance:IsA("BasePart") or registry[instance] then return end
	local parent = instance.Parent
	if parent and (parent.Name == DRESS_ROOT or (parent.Parent and parent.Parent.Name == DRESS_ROOT)) then return end
	if instance:GetAttribute("Shape") ~= nil then consider(instance); return end
	pcall(function()
		local connection
		connection = instance:GetAttributeChangedSignal("Shape"):Connect(function()
			if type(instance:GetAttribute("Shape")) == "string" then connection:Disconnect(); consider(instance) end
		end)
	end)
end
-- Test hook / manual recovery only: discovery is signal-driven (DescendantAdded
-- plus the Shape attribute signal), never a periodic full GetDescendants walk.
local function rescan()
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and not registry[instance] and instance:GetAttribute("Shape") ~= nil then consider(instance) end
	end
end

-- Map Art (§32): the Sky Chart's miniature asks for a forged copy of a far
-- island hull or landmark: ReplicatedStorage.MeshForgeLocal:Invoke("visual",
-- host) -> an unparented MeshPart sized and placed like the world's, its
-- triangle count and a token. The chart never starves the world's forge:
--   * requests are served from an existing template of the shape (exact tint or
--     its nearest variant); a new template is built only while CHART_RESERVE
--     slots stay free for the world (stats.templates < LIMITS.templates - 8);
--   * a template is pinned (users + 1, so LRU eviction never empties a mesh the
--     cached chart shows) only when the chart accepts the mesh: Invoke("accept",
--     token). Invoke("release", token) unpins (a rejected mesh, a destroyed or
--     rebuilt chart). At most CHART_PIN_CAP templates are chart-pinned (6 on
--     phones, 16 on desktop);
--   * when the world is starved and nothing nearer can be reclaimed, a template
--     pinned only by the chart is unpinned (chartYield): its meshes get the
--     ShapeRevoked attribute and the chart swaps its primitive stand-ins back.
local CHART_RESERVE = 8
local CHART_PIN_CAP = if mobile then 6 else 16
local chartTokens, chartNext = {}, 0 -- token -> {entry, clone, accepted}
local function chartVisual(part)
	local shapeName = shapeOf(part)
	if not shapeName or stopReason then return nil end
	local data, catalog = lookup(shapeName)
	if not data then return nil end
	local tint = templateTint(shapeName, data, part:GetAttribute("Tint"))
	local key = shapeName .. "#" .. (if tint then tint:ToHex() else "")
	local entry = templates[key]
	if entry and entry.pending then
		entry = template(shapeName, data, catalog, tint) -- waits for the build in flight
	elseif not entry then
		entry = nearestVariant(shapeName, tint)
		if not entry and stats.templates - stats.creatureTemplates < LIMITS.templates - CHART_RESERVE then entry = template(shapeName, data, catalog, tint) end
	end
	if not entry or entry.pending then stats.chartRefused += 1; return nil end
	if entry.chartPins == 0 and stats.chartPins >= CHART_PIN_CAP then stats.chartRefused += 1; return nil end
	local size, meshFrame = layout(part, data, ownedSiblings(part))
	local clone = entry.part:Clone()
	clone.Name = part.Name .. " Mesh"
	clone.Size, clone.CFrame = size, meshFrame
	clone:SetAttribute("ShapeOf", shapeName)
	clone:SetAttribute("ShapeTriangles", entry.triangles)
	chartNext += 1
	chartTokens[chartNext] = {entry = entry, clone = clone, accepted = false}
	return clone, entry.triangles, chartNext
end
-- The chart keeps the mesh: pin its template (false when it was evicted since,
-- or the chart pin cap is reached; the chart then keeps its stand-in).
local function chartAccept(token)
	local t = chartTokens[token]
	if not t or t.accepted then return false end
	local entry = t.entry
	if templates[entry.key] ~= entry or (entry.chartPins == 0 and stats.chartPins >= CHART_PIN_CAP) then
		chartTokens[token] = nil
		return false
	end
	if entry.chartPins == 0 then stats.chartPins += 1; entry.users += 1 end
	entry.chartPins += 1
	t.accepted = true
	return true
end
local function chartUnpin(entry)
	if entry.chartPins <= 0 then return end
	entry.chartPins -= 1
	if entry.chartPins == 0 then
		stats.chartPins -= 1
		entry.users -= 1
		useTick += 1
		entry.used = useTick
	end
end
local function chartRelease(token)
	local t = chartTokens[token]
	if not t then return end
	chartTokens[token] = nil
	if t.accepted then chartUnpin(t.entry) end
end
-- A starved world takes back the least recently used template that only the
-- chart holds (no world clones). Returns true when one was freed.
chartYield = function()
	local best
	for _, entry in pairs(templates) do
		if entry and not entry.pending and entry.chartPins > 0 and entry.users == 1 and (not best or entry.used < best.used) then best = entry end
	end
	if not best then return false end
	for token, t in pairs(chartTokens) do
		if t.entry == best then
			chartTokens[token] = nil
			pcall(function() t.clone:SetAttribute("ShapeRevoked", true) end)
		end
	end
	best.chartPins = 1
	chartUnpin(best)
	stats.chartRevoked += 1
	return true
end

-- Creatures (§48): creatures.client.lua asks for one forged clone per rig
-- segment: creatureVisual(shape, tint) -> an unparented MeshPart at the mesh's
-- native size, a token, the mesh extent and its centre (the authored origin
-- sits at -centre in the clone's frame). The caller sizes, poses and parents it
-- and hands it back with creatureRelease(token). Clones count against the
-- instance and placed-triangle budgets; creature templates against
-- CREATURE_TEMPLATE_CAP (desktop 22, phones 8; the last 6 / 3 only for boss /
-- world tiers, QC H1) inside the forge's own caps, the
-- least recently used idle creature template giving way first (their own
-- pool, CREATURE_TRIANGLE_CAP too, beside the world's LIMITS). Desktop keeps
-- one template per exact colour (a shape's legs match its body); phones share
-- the nearest variant (VARIANTS = 1).
local creatureTokens, creatureNext = {}, 0 -- token -> {entry, clone}
local function creatureTemplateCount() return stats.creatureTemplates end
local function creatureVisual(shapeName, tint, boss)
	if type(shapeName) ~= "string" or creaturePool.stop then return nil, "unavailable" end
	local data, catalog = lookup(shapeName)
	if not data or not CREATURE_KINDS[data.kind] then return nil, "unknown" end
	local tris = data.tris or #data.faces
	if stats.instances >= LIMITS.instances or stats.placedTriangles + tris > LIMITS.placedTriangles then stats.skipped += 1; return nil, "budget" end
	local color = if typeof(tint) == "Color3" then tint else defaultTint(data)
	-- template() keeps exact colours on desktop (and for bosses on phones, QC
	-- L7), shares a variant on phones, evicts idle creature templates (LRU),
	-- keeps CREATURE_BOSS_RESERVE for bosses and waits for a build in flight.
	local entry = template(shapeName, data, catalog, color, boss == true)
	if not entry then entry = nearestVariant(shapeName, color) end
	if not entry or entry.pending then return nil, "budget" end
	local clone = entry.part:Clone()
	clone.Name = shapeName
	useTick += 1
	entry.users += 1
	entry.used = useTick
	stats.instances += 1
	stats.placedTriangles += entry.triangles
	creatureNext += 1
	creatureTokens[creatureNext] = {entry = entry, clone = clone}
	return clone, creatureNext, entry.extent, entry.center
end
-- §52 NPC outfits: outfitVisual(shape, tint) -> the same contract as
-- creatureVisual (an unparented clone, token, extent, centre) or nil and a
-- reason ("budget" while the pool is full of busy templates, "unavailable" /
-- "unknown" for good), from the outfit pool; handed back with
-- outfitRelease(token). Outfit clones never count against the world's limits.
local outfitTokens, outfitNext = {}, 0 -- token -> {entry, clone}
local function outfitVisual(shapeName, tint)
	if type(shapeName) ~= "string" then return nil, "unknown" end
	if outfitPool.stop or outfitPool.blocked then return nil, "unavailable" end
	local data, catalog = lookup(shapeName)
	if not data or not OUTFIT_KINDS[data.kind] then return nil, "unknown" end
	if stats.outfitInstances >= OUTFIT_INSTANCE_CAP then return nil, "budget" end
	local color = if typeof(tint) == "Color3" then tint else defaultTint(data)
	local entry, reason = template(shapeName, data, catalog, color, false)
	if not entry and reason == "failed" then return nil, if outfitPool.stop or outfitPool.blocked then "unavailable" else "failed" end
	if not entry then entry = nearestVariant(shapeName, color) end
	if not entry or entry.pending then return nil, if outfitPool.stop or outfitPool.blocked then "unavailable" else "budget" end
	local clone = entry.part:Clone()
	clone.Name = shapeName
	useTick += 1
	entry.users += 1
	entry.used = useTick
	stats.outfitInstances += 1
	stats.outfitPlaced += entry.triangles
	outfitNext += 1
	outfitTokens[outfitNext] = {entry = entry, clone = clone}
	return clone, outfitNext, entry.extent, entry.center
end
local function outfitRelease(token)
	local t = outfitTokens[token]
	if not t then return false end
	outfitTokens[token] = nil
	t.entry.users -= 1
	useTick += 1
	t.entry.used = useTick
	stats.outfitInstances -= 1
	stats.outfitPlaced -= t.entry.triangles
	pcall(t.clone.Destroy, t.clone)
	return true
end
local function creatureRelease(token)
	local t = creatureTokens[token]
	if not t then return false end
	creatureTokens[token] = nil
	local entry = t.entry
	entry.users -= 1
	useTick += 1
	entry.used = useTick
	stats.instances -= 1
	stats.placedTriangles -= entry.triangles
	-- (QC L6: no budgetEpoch bump; the world's backed-off parts keep their back-off.)
	pcall(t.clone.Destroy, t.clone)
	return true
end

-- §54 island dressing: dressVisual(shape, tint) -> an unparented clone at the
-- mesh's native size, a token, extent and centre (the outfit contract) from the
-- dress pool, or nil and a reason; dressRelease(token) hands it back.
local dressTokens, dressNext = {}, 0 -- token -> {entry, clone}
local function dressVisual(shapeName, tint)
	if type(shapeName) ~= "string" then return nil, "unknown" end
	if dressPool.blocked and os.clock() - dressPool.blockedAt >= BLOCK_RETRY then dressPool.blocked = false end -- M7
	if dressPool.stop or dressPool.blocked then return nil, "unavailable" end
	local data, catalog = lookup(shapeName)
	if not data or not DRESS_KINDS[data.kind] then return nil, "unknown" end
	local tris = data.tris or #data.faces
	if stats.dressInstances >= DRESS_INSTANCE_CAP or stats.dressPlaced + tris > DRESS_PLACED_CAP then return nil, "budget" end
	local color = if typeof(tint) == "Color3" then tint else defaultTint(data)
	local entry, reason = template(shapeName, data, catalog, color, false)
	if not entry and reason == "failed" then return nil, if dressPool.stop or dressPool.blocked then "unavailable" else "failed" end
	if not entry then entry = nearestVariant(shapeName, color) end
	if not entry or entry.pending then return nil, if dressPool.stop or dressPool.blocked then "unavailable" else "budget" end
	local clone = entry.part:Clone()
	clone.Name = shapeName
	clone:SetAttribute("ShapeOf", shapeName)
	clone.CanCollide, clone.CanTouch, clone.CanQuery = false, false, false
	useTick += 1
	entry.users += 1
	entry.used = useTick
	stats.dressInstances += 1
	stats.dressPlaced += entry.triangles
	dressNext += 1
	dressTokens[dressNext] = {entry = entry, clone = clone}
	return clone, dressNext, entry.extent, entry.center
end
local function dressRelease(token)
	local t = dressTokens[token]
	if not t then return false end
	dressTokens[token] = nil
	t.entry.users -= 1
	useTick += 1
	t.entry.used = useTick
	stats.dressInstances -= 1
	stats.dressPlaced -= t.entry.triangles
	pcall(t.clone.Destroy, t.clone)
	return true
end
-- Forged ground tops (§54): groundVisual(spec) with spec = shared/TerrainArt.lua
-- T.ground output ({vertices, colors, normals, faces}, island space) -> a
-- MeshPart (unparented, non-colliding; geometry recentred on its bounds), a
-- token and the bounds centre in island space; per-vertex colours and smooth
-- normals. groundRelease(token) destroys it. Capped at GROUND_CAP meshes and
-- GROUND_TRIANGLE_CAP triangles; failures count against the dress pool.
local groundTokens, groundNext = {}, 0 -- token -> {part, mesh, triangles}
local function groundVisual(spec)
	if type(spec) ~= "table" or type(spec.positions) ~= "table" or type(spec.indices) ~= "table" then return nil, "unknown" end
	if groundPool.stop then return nil, "unavailable" end
	local pos, col, nor, idx = spec.positions, spec.colors, spec.normals, spec.indices
	local triangles = #idx // 3
	if stats.grounds >= GROUND_CAP or stats.groundTriangles + triangles > GROUND_TRIANGLE_CAP then return nil, "budget" end
	stats.grounds += 1
	stats.groundTriangles += triangles
	local lx, ly, lz, hx, hy, hz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for i = 1, #pos, 3 do
		local x, y, z = pos[i], pos[i + 1], pos[i + 2]
		if x < lx then lx = x end; if y < ly then ly = y end; if z < lz then lz = z end
		if x > hx then hx = x end; if y > hy then hy = y end; if z > hz then hz = z end
	end
	local lo, hi = Vector3.new(lx, ly, lz), Vector3.new(hx, hy, hz)
	local centre = (lo + hi) / 2
	local mesh
	local ok, part = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "CreateEditableMesh returned nil")
		local ids, colorIds, normalIds = {}, {}, {}
		for v = 1, #pos // 3 do
			local i = v * 3 - 2
			ids[v] = mesh:AddVertex(Vector3.new(pos[i], pos[i + 1], pos[i + 2]))
			colorIds[v] = mesh:AddColor(Color3.new(col[i], col[i + 1], col[i + 2]), 1)
			normalIds[v] = mesh:AddNormal(Vector3.new(nor[i], nor[i + 1], nor[i + 2]))
		end
		for f = 1, #idx, 3 do
			local a, b, c = idx[f], idx[f + 1], idx[f + 2]
			local triangle = mesh:AddTriangle(ids[a], ids[b], ids[c])
			mesh:SetFaceColors(triangle, {colorIds[a], colorIds[b], colorIds[c]})
			mesh:SetFaceNormals(triangle, {normalIds[a], normalIds[b], normalIds[c]})
		end
		local content = Content.fromObject(mesh)
		local okOptions, result = pcall(AssetService.CreateMeshPartAsync, AssetService, content, {CollisionFidelity = Enum.CollisionFidelity.Box})
		if not okOptions or not result then result = AssetService:CreateMeshPartAsync(content) end
		assert(result and result:IsA("MeshPart"), "CreateMeshPartAsync returned no MeshPart")
		result.Name = "Forged ground"
		result.Anchored, result.CanCollide, result.CanTouch, result.CanQuery = true, false, false, false
		result.Material = Enum.Material.SmoothPlastic
		result.Color = Color3.new(1, 1, 1)
		result.Size = (hi - lo):Max(Vector3.one * 0.05)
		return result
	end)
	if not ok or not part then
		stats.grounds -= 1
		stats.groundTriangles -= triangles
		if mesh then pcall(mesh.Destroy, mesh) end
		groundPool.failures += 1
		if groundPool.failures >= LIMITS.failures then groundPool.stop = "unavailable" end
		warn("[MeshForge] ground could not be meshed: " .. tostring(part))
		return nil, "failed"
	end
	groundNext += 1
	groundTokens[groundNext] = {part = part, mesh = mesh, triangles = triangles}
	return part, groundNext, centre
end
local function groundRelease(token)
	local t = groundTokens[token]
	if not t then return false end
	groundTokens[token] = nil
	stats.grounds -= 1
	stats.groundTriangles -= t.triangles
	pcall(t.part.Destroy, t.part)
	if t.mesh then pcall(t.mesh.Destroy, t.mesh) end
	return true
end

workspace.DescendantAdded:Connect(function(instance) task.defer(watch, instance) end)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
step()
if MeshForgeTest then
	MeshForgeTest.forge = {stats = stats, limits = LIMITS, templates = templates, rescan = rescan, consider = consider, step = step,
		templateTint = templateTint, kitShapes = SIGN_KIT_SHAPES, kitMetals = KIT_METALS, variants = VARIANTS,
		cornerNormals = cornerNormals, vertexColors = vertexColors, sphereNormals = sphereNormals, styleSign = styleSign, stopReason = function() return stopReason end,
		radii = {build = BUILD_RADIUS, unload = UNLOAD_RADIUS, building = BUILDING_RADIUS, farLod = FAR_LOD_RADIUS, phoneTemplateTris = PHONE_TEMPLATE_TRIS}, buildRadius = buildRadius, releaseRadius = releaseRadius, mobile = mobile, backoff = backoff, registry = registry, final = final, placed = placed,
		chart = {visual = chartVisual, accept = chartAccept, release = chartRelease, tokens = chartTokens, pinCap = CHART_PIN_CAP, reserve = CHART_RESERVE},
		creature = {visual = creatureVisual, release = creatureRelease, tokens = creatureTokens, cap = CREATURE_TEMPLATE_CAP, triangleCap = CREATURE_TRIANGLE_CAP, count = creatureTemplateCount, kinds = CREATURE_KINDS,
			bossReserve = CREATURE_BOSS_RESERVE, bossTriangles = CREATURE_BOSS_TRIANGLES, pool = creaturePool},
		outfit = {visual = outfitVisual, release = outfitRelease, tokens = outfitTokens, cap = OUTFIT_TEMPLATE_CAP, triangleCap = OUTFIT_TRIANGLE_CAP,
			instanceCap = OUTFIT_INSTANCE_CAP, kinds = OUTFIT_KINDS, pool = outfitPool},
		dress = {visual = dressVisual, release = dressRelease, tokens = dressTokens, cap = DRESS_TEMPLATE_CAP, triangleCap = DRESS_TRIANGLE_CAP,
			instanceCap = DRESS_INSTANCE_CAP, placedCap = DRESS_PLACED_CAP, kinds = DRESS_KINDS, pool = dressPool,
			ground = groundVisual, groundRelease = groundRelease, groundTokens = groundTokens, groundCap = GROUND_CAP, groundTriangleCap = GROUND_TRIANGLE_CAP, groundPool = groundPool, blockRetry = BLOCK_RETRY},
		-- Final mesh box for a tagged part, without forging: size, CFrame, kind.
		describe = function(part)
			local shapeName = shapeOf(part)
			if not shapeName then return nil end
			local data = lookup(shapeName)
			if not data then return nil end
			local siblings = ownedSiblings(part)
			local size, frame, boxFrame, box = layout(part, data, siblings)
			return {size = size, cframe = frame, kind = data.kind, shape = shapeName,
				box = box, boxFrame = boxFrame, siblings = siblings or {}}
		end}
	return
end
do
	local api = ReplicatedStorage:FindFirstChild("MeshForgeLocal") or Instance.new("BindableFunction")
	api.Name = "MeshForgeLocal"
	api.OnInvoke = function(method, arg)
		if method == "visual" and typeof(arg) == "Instance" and arg:IsA("BasePart") then return chartVisual(arg) end
		if method == "accept" and type(arg) == "number" then return chartAccept(arg) end
		if method == "release" and type(arg) == "number" then chartRelease(arg) return true end
		if method == "creature" and type(arg) == "table" then return creatureVisual(arg.shape, arg.tint, arg.boss == true) end
		if method == "creatureRelease" and type(arg) == "number" then return creatureRelease(arg) end
		if method == "outfit" and type(arg) == "table" then return outfitVisual(arg.shape, arg.tint) end
		if method == "outfitRelease" and type(arg) == "number" then return outfitRelease(arg) end
		if method == "dress" and type(arg) == "table" then return dressVisual(arg.shape, arg.tint) end
		if method == "dressRelease" and type(arg) == "number" then return dressRelease(arg) end
		if method == "ground" and type(arg) == "table" then return groundVisual(arg) end
		if method == "groundRelease" and type(arg) == "number" then return groundRelease(arg) end
		return nil
	end
	api.Parent = ReplicatedStorage
end
print(string.format("[MeshForge] %s: %d templates (%d tris cached), %d meshes placed (%d tris), %d skipped",
	if stopReason then stopReason else "ready", stats.templates, stats.templateTriangles, stats.instances, stats.placedTriangles, stats.skipped))
task.spawn(function()
	while true do
		task.wait(STEP_SECONDS)
		step()
	end
end)
script.Destroying:Once(function()
	for part in pairs(placed) do release(part) end
	for token in pairs(creatureTokens) do creatureRelease(token) end
	for token in pairs(outfitTokens) do outfitRelease(token) end
	for token in pairs(dressTokens) do dressRelease(token) end
	for token in pairs(groundTokens) do groundRelease(token) end
	for _, entry in pairs(templates) do
		if entry and not entry.pending then
			pcall(entry.part.Destroy, entry.part)
			if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
		end
	end
end)

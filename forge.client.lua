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
-- Resource slots (CropBed, OreVein) whose host carries a gather prompt (IsleItem) use
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
-- triangles and a shorter build radius (touch-only devices).
local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
local LIMITS = if mobile then {
	templates = 24, templateTriangles = 30000, instances = 400, placedTriangles = 150000, failures = 3,
} else {
	templates = 64, -- distinct (shape, tint) EditableMeshes kept alive (§30: island hulls, bridges, landmarks); idle ones are LRU-evicted
	templateTriangles = 72000, -- triangles across all cached EditableMeshes
	instances = 900, -- placed MeshPart clones near the player
	placedTriangles = 600000, -- triangles across all placed clones
	failures = 3, -- template build failures before the forge stops trying
}
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
for _, name in ipairs({"AetherWorldArt", "AetherArt"}) do
	local catalog = loadCatalog(name)
	if catalog then table.insert(catalogs, catalog) end
end
-- World tags use descriptive prop names; map them onto catalog shapes so every
-- tagged prop gets a mesh. Names with no good match stay primitive by design.
local ALIASES = {
	Rock = "Boulder", CliffRock = "CliffPiece", OreVein = "OreVein2", Lamp = "StreetLamp", PineTree = "WindpineTree",
	-- Sign system (§28): descriptive names for the sign kit pieces.
	OrnateBracket = "SignHangingFrame", Signpost = "SignpostFrame", Standard = "BannerStandardFrame", Finial = "BannerStandardFrame",
	Plinth = "SignPlinthFrame", Crest = "SignPlinthFrame", NoticeFrame = "SignLedgerFrame", CarvedBoard = "SignCarvedBoard",
	ScrollBoard = "SignScrollBoard", ArrowBoard = "SignArrowBoard", Plaque = "SignPlaqueBoard", NoticeBoard = "SignNoticeBoard",
	ChainLink = "SignHangingFrame",
}
local RESOURCE_SLOTS = {CropBed = true, OreVein = true}
local function lookup(shapeName)
	shapeName = ALIASES[shapeName] or shapeName
	for _, catalog in ipairs(catalogs) do
		local data = catalog.shapes[shapeName]
		if type(data) == "table" and type(data.vertices) == "table" and type(data.faces) == "table" then return data, catalog end
	end
	return nil
end

-- Build radius for a tagged part (catalog `range` for far-seen shapes).
local rangeCache = setmetatable({}, {__mode = "k"})
local function buildRadius(part)
	local cached = rangeCache[part]
	if cached then return cached end
	local radius = BUILD_RADIUS
	local shapeName = part:GetAttribute("Shape")
	local data = type(shapeName) == "string" and lookup(shapeName)
	if data and type(data.range) == "number" and data.range > BUILD_RADIUS then radius = math.min(data.range, RANGE_CAP) end
	rangeCache[part] = radius
	return radius
end

-- Final catalog shape name for a tagged part (resource slot, then alias).
local function shapeOf(part)
	local shapeName = part:GetAttribute("Shape")
	if type(shapeName) ~= "string" then return nil end
	if RESOURCE_SLOTS[shapeName] then
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		local item = prompt and prompt:GetAttribute("IsleItem")
		if type(item) == "string" then
			for _, catalog in ipairs(catalogs) do
				local resolved = type(catalog.resourceShape) == "function" and catalog.resourceShape(item)
				if type(resolved) == "string" and lookup(resolved) then return resolved end
			end
		end
	end
	return ALIASES[shapeName] or shapeName
end

local stats = {templates = 0, templateTriangles = 0, instances = 0, placedTriangles = 0, failures = 0, skipped = 0, evicted = 0, templateSkips = 0}
-- Indexing a missing member errors on an Instance, so probe the API under pcall.
local available = pcall(function()
	assert(typeof(AssetService.CreateEditableMesh) == "function" and typeof(AssetService.CreateMeshPartAsync) == "function")
	assert(Content ~= nil and Content.fromObject ~= nil)
end)
local stopReason = if available then nil else "unavailable"
local newTemplatesBlocked = false
local templates = {} -- key -> {part, mesh, extent, center, triangles, users, used} | false (failed)
local useTick = 0 -- LRU clock: bumped whenever a template gains or loses a clone

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

local function buildTemplate(shapeName, data, catalog, tint)
	local mesh
	local ok, result = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "CreateEditableMesh returned nil")
		local ids = {}
		for i, xyz in ipairs(data.vertices) do ids[i] = mesh:AddVertex(Vector3.new(xyz[1], xyz[2], xyz[3])) end
		local colorIds, normalIds = {}, {}
		local normals = cornerNormals(data)
		for f, face in ipairs(data.faces) do
			local shade = face[4]
			local colorId = colorIds[shade]
			if not colorId then
				colorId = mesh:AddColor(paletteColor(catalog, shade, tint), 1)
				colorIds[shade] = colorId
			end
			local triangle = mesh:AddTriangle(ids[face[1]], ids[face[2]], ids[face[3]])
			mesh:SetFaceColors(triangle, {colorId, colorId, colorId})
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
local function evictFor(triangles)
	local idle = {}
	for key, entry in pairs(templates) do
		if entry and entry.users == 0 then table.insert(idle, {key, entry}) end
	end
	table.sort(idle, function(a, b) return a[2].used < b[2].used end)
	for _, item in ipairs(idle) do
		if stats.templates < LIMITS.templates and stats.templateTriangles + triangles <= LIMITS.templateTriangles then break end
		local entry = item[2]
		templates[item[1]] = nil
		stats.templates -= 1
		stats.templateTriangles -= entry.triangles
		stats.evicted += 1
		pcall(entry.part.Destroy, entry.part)
		if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
	end
	return stats.templates < LIMITS.templates and stats.templateTriangles + triangles <= LIMITS.templateTriangles
end
local function template(shapeName, data, catalog, tint)
	local key = shapeName .. "#" .. (if tint then tint:ToHex() else "")
	local cached = templates[key]
	if cached ~= nil then return cached or nil end
	local triangles = #data.faces
	if stopReason or newTemplatesBlocked or ((stats.templates >= LIMITS.templates or stats.templateTriangles + triangles > LIMITS.templateTriangles)
		and not evictFor(triangles)) then
		stats.templateSkips += 1
		return nil, "budget"
	end
	local part, mesh, problem = buildTemplate(shapeName, data, catalog, tint)
	if not part then
		templates[key] = false
		stats.failures += 1
		local message = string.lower(problem or "")
		if message:find("budget", 1, true) or message:find("memory", 1, true) or message:find("limit", 1, true) then newTemplatesBlocked = true end
		if stats.failures >= LIMITS.failures then stopReason = "unavailable" end
		warn("[MeshForge] " .. shapeName .. " could not be meshed: " .. tostring(problem))
		return nil, "failed"
	end
	local lo, hi = bounds(data)
	useTick += 1
	local entry = {part = part, mesh = mesh, extent = (hi - lo):Max(Vector3.one * 0.01), center = (lo + hi) / 2, triangles = triangles,
		users = 0, used = useTick}
	part.Size = entry.extent
	templates[key] = entry
	stats.templates += 1
	stats.templateTriangles += triangles
	return entry
end

-- Signs: the original board keeps its SurfaceGui (the meshed frame wraps it);
-- text gets one consistent, higher-contrast style.
local SIGN_KINDS = {sign = true}
-- Sign kit (§28): the eleven kit shapes, by final shape name. Every other
-- kind "sign" shape (legacy Banner, Signboard, SignboardPosted, SignPost:
-- pennants, agility cloth, crew pennant, commission ledger) keeps its Tint on
-- every device. Kit tints are quantised so ten island themes cannot each spend
-- a template per shape: frames and boards snap to the nearest of KIT_METALS on
-- desktop and share the shape's default-tint template on phones; BannerCloth
-- (its Tint is the banner's accent) snaps to CLOTH_PALETTE on every device.
local SIGN_KIT_SHAPES = {
	SignHangingFrame = true, SignpostFrame = true, BannerStandardFrame = true, SignPlinthFrame = true, SignLedgerFrame = true,
	SignCarvedBoard = true, SignScrollBoard = true, SignArrowBoard = true, SignPlaqueBoard = true, SignNoticeBoard = true, BannerCloth = true,
}
local function hexColors(list)
	local out = {}
	for i, hex in ipairs(list) do out[i] = Color3.fromHex(hex) end
	return out
end
local KIT_METALS = hexColors({"C9A24E", "B0B8C4", "6FA898"}) -- brass, silver, verdigris
local CLOTH_PALETTE = hexColors({"C15557", "D9A441", "3C9291", "7B5CC4", "4E8A3E", "3F6FB5"})
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
	if not SIGN_KIT_SHAPES[shapeName] then return tint end
	if shapeName == "BannerCloth" then return nearestColor(tint, CLOTH_PALETTE) end
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
local registry = setmetatable({}, {__mode = "k"}) -- tagged parts this client knows
local placed = setmetatable({}, {__mode = "k"}) -- part -> {visual, triangles, connections, decals}
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

local function forge(part)
	if placed[part] or final[part] or not part.Parent then return end
	local shapeName = shapeOf(part)
	if not shapeName then return end
	if part:GetAttribute("SculptureScale") ~= nil and part:GetAttribute("ShapeScale") == nil then skip(part, "legacy sculpture", true); return end
	local data, catalog = lookup(shapeName)
	if not data then skip(part, "unknown shape", true); return end
	if stopReason then skip(part, stopReason, true); return end
	if stats.instances >= LIMITS.instances or stats.placedTriangles + #data.faces > LIMITS.placedTriangles then skip(part, "budget"); return end
	local tint = templateTint(shapeName, data, part:GetAttribute("Tint"))
	local entry, problem = template(shapeName, data, catalog, tint)
	if not entry and problem == "budget" then
		-- Reuse the shape's default-tint template rather than leaving a primitive.
		local fallback = defaultTint(data)
		local cached = templates[shapeName .. "#" .. (if fallback then fallback:ToHex() else "")]
		if cached then entry = cached end
	end
	if not entry then skip(part, problem or stopReason or "failed", problem ~= "budget"); return end
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
		clone.Parent = part.Parent
		return clone
	end)
	if not ok or not visual then skip(part, "clone failed", true); return end
	local record = {visual = visual, triangles = entry.triangles, connections = {}, decals = {}, hidden = {}, entry = entry}
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
local stepping = false
local function step()
	if stepping then return end
	stepping = true
	local origin = focus()
	if origin then
		-- Releases first, so budget they free is available to this step's builds.
		for part in pairs(registry) do
			if not part.Parent then
				registry[part] = nil
				release(part)
			elseif placed[part] and (part.CFrame.Position - origin).Magnitude > math.max(UNLOAD_RADIUS, buildRadius(part) * 1.2) then
				release(part)
			end
		end
		local near = {}
		for part in pairs(registry) do
			if not placed[part] and not final[part] and not waiting(part) then
				local distance = (part.CFrame.Position - origin).Magnitude
				if distance <= buildRadius(part) then table.insert(near, {part, distance}) end
			end
		end
		-- Nearest first, so budgets are spent on what the player sees.
		table.sort(near, function(a, b) return a[2] < b[2] end)
		for _, item in ipairs(near) do
			local ok, problem = pcall(forge, item[1])
			if not ok then warn("[MeshForge] " .. tostring(problem)); skip(item[1], "error", true) end
		end
	end
	stepping = false
end
local function consider(part)
	if registry[part] or typeof(part) ~= "Instance" or not part:IsA("BasePart") or type(part:GetAttribute("Shape")) ~= "string" then return end
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
local function watch(instance)
	if not instance:IsA("BasePart") or registry[instance] then return end
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

workspace.DescendantAdded:Connect(function(instance) task.defer(watch, instance) end)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
step()
if MeshForgeTest then
	MeshForgeTest.forge = {stats = stats, limits = LIMITS, templates = templates, rescan = rescan, consider = consider, step = step,
		templateTint = templateTint, kitShapes = SIGN_KIT_SHAPES, kitMetals = KIT_METALS, clothPalette = CLOTH_PALETTE,
		cornerNormals = cornerNormals, styleSign = styleSign, stopReason = function() return stopReason end,
		radii = {build = BUILD_RADIUS, unload = UNLOAD_RADIUS}, mobile = mobile, backoff = backoff,
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
	for _, entry in pairs(templates) do
		if entry then
			pcall(entry.part.Destroy, entry.part)
			if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
		end
	end
end)

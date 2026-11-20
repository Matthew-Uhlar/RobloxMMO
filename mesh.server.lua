-- MeshForge: server-side custom meshes for parts tagged with the Shape attribute
-- (docs/DEPTH-CONTRACT.md §10). For each (shape, tint) one EditableMesh-backed
-- MeshPart template is built and cached; every tagged part gets an anchored,
-- non-colliding clone sized to the part (× ShapeScale) and parented beside it.
-- The original part stays as the collider and is hidden only after its mesh is
-- in place. When the API is unavailable, fails, or a budget is reached, the
-- original primitive stays visible (no per-triangle fallback).
--
-- Attributes read on a tagged part:
--   Shape (string)       catalog shape name (art/WorldCatalog.lua or art/PropCatalog.lua)
--   Tint (Color3)        colour for the shape's tint slots (default: the shape's own tint)
--   ShapeScale (number)  multiplies the part's size (default 1)
--   ShapeFit (string)    "Uniform" keeps proportions (fits inside the part); default stretches
--   SculptureScale       legacy AetherSculpture anchors without ShapeScale: authored size × scale,
--                        authored origin at the anchor (matches mesh.client.lua)
-- Attributes written: ShapeDone=true (mesh placed) or ShapeSkipped=<reason>;
-- an ObjectValue "ShapeMesh" under the part points at its MeshPart.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LIMITS = {
	templates = 64, -- distinct (shape, tint) EditableMeshes kept alive
	templateTriangles = 60000, -- triangles across all cached EditableMeshes
	instances = 2500, -- placed MeshPart clones
	placedTriangles = 1500000, -- triangles across all placed clones
	failures = 3, -- template build failures before the forge stops trying
}
local RESCAN_SECONDS = 20

local function loadCatalog(container, name)
	local module = container:WaitForChild(name, 15)
	if not module then return nil end
	local ok, catalog = pcall(require, module)
	if ok and type(catalog) == "table" and type(catalog.shapes) == "table" then return catalog end
	return nil
end
local catalogs = {}
for _, source in ipairs({{ServerStorage, "AetherWorldArt"}, {ReplicatedStorage, "AetherArt"}}) do
	local catalog = loadCatalog(source[1], source[2])
	if catalog then table.insert(catalogs, catalog) end
end
local function lookup(shapeName)
	for _, catalog in ipairs(catalogs) do
		local data = catalog.shapes[shapeName]
		if type(data) == "table" and type(data.vertices) == "table" and type(data.faces) == "table" then return data, catalog end
	end
	return nil
end

local stats = {templates = 0, templateTriangles = 0, instances = 0, placedTriangles = 0, failures = 0, skipped = 0}
-- Indexing a missing member errors on an Instance, so probe the API under pcall.
local available = pcall(function()
	assert(typeof(AssetService.CreateEditableMesh) == "function" and typeof(AssetService.CreateMeshPartAsync) == "function")
	assert(Content ~= nil and Content.fromObject ~= nil)
end)
local stopReason = if available then nil else "unavailable"
local newTemplatesBlocked = false
local templates = {} -- key -> {part, mesh, extent, center, triangles} | false (failed)

local function setStatus()
	pcall(function()
		ReplicatedStorage:SetAttribute("MeshForgeStatus", if stopReason == "unavailable" and stats.instances == 0 then "unavailable" else "ready")
		ReplicatedStorage:SetAttribute("MeshForgeTemplates", stats.templates)
		ReplicatedStorage:SetAttribute("MeshForgeInstances", stats.instances)
		ReplicatedStorage:SetAttribute("MeshForgeTriangles", stats.placedTriangles)
	end)
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

local function template(shapeName, data, catalog, tint)
	local key = shapeName .. "#" .. (if tint then tint:ToHex() else "")
	local cached = templates[key]
	if cached ~= nil then return cached or nil end
	local triangles = #data.faces
	if stopReason or newTemplatesBlocked or stats.templates >= LIMITS.templates or stats.templateTriangles + triangles > LIMITS.templateTriangles then
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
	local entry = {part = part, mesh = mesh, extent = (hi - lo):Max(Vector3.one * 0.01), center = (lo + hi) / 2, triangles = triangles}
	part.Size = entry.extent
	templates[key] = entry
	stats.templates += 1
	stats.templateTriangles += triangles
	return entry
end

-- Signs: the original board keeps its SurfaceGui (the meshed frame wraps it);
-- text gets one consistent, higher-contrast style.
local SIGN_KINDS = {sign = true}
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
local handled = setmetatable({}, {__mode = "k"})
local function skip(part, reason)
	handled[part] = true
	stats.skipped += 1
	pcall(part.SetAttribute, part, "ShapeSkipped", reason)
end
local function placement(part, data, entry)
	local legacyScale = part:GetAttribute("SculptureScale")
	local shapeScale = part:GetAttribute("ShapeScale")
	if type(shapeScale) ~= "number" and type(legacyScale) == "number" then
		if legacyScale <= 0 or legacyScale > 100 or legacyScale ~= legacyScale then return nil end
		return entry.extent * legacyScale, CFrame.new(entry.center * legacyScale)
	end
	shapeScale = if type(shapeScale) == "number" and shapeScale > 0 and shapeScale <= 100 then shapeScale else 1
	local lo, hi
	if type(data.fit) == "table" and type(data.fit[1]) == "table" and type(data.fit[2]) == "table" then
		lo, hi = Vector3.new(table.unpack(data.fit[1])), Vector3.new(table.unpack(data.fit[2]))
	else
		lo, hi = entry.center - entry.extent / 2, entry.center + entry.extent / 2
	end
	local fitSize = (hi - lo):Max(Vector3.one * 0.01)
	local target = (part.Size * shapeScale):Max(Vector3.one * 0.05)
	local k = target / fitSize
	if part:GetAttribute("ShapeFit") == "Uniform" then
		local m = math.min(k.X, k.Y, k.Z)
		k = Vector3.new(m, m, m)
	end
	return entry.extent * k, CFrame.new((entry.center - (lo + hi) / 2) * k)
end

local function forge(part)
	if handled[part] or not part.Parent then return end
	local shapeName = part:GetAttribute("Shape")
	if type(shapeName) ~= "string" then return end
	if part:GetAttribute("ShapeDone") then handled[part] = true; return end
	local data, catalog = lookup(shapeName)
	if not data then skip(part, "unknown shape"); return end
	if SIGN_KINDS[data.kind] then styleSign(part) end
	if stopReason then skip(part, stopReason); return end
	if stats.instances >= LIMITS.instances or stats.placedTriangles + #data.faces > LIMITS.placedTriangles then skip(part, "budget"); return end
	local tint = part:GetAttribute("Tint")
	if typeof(tint) ~= "Color3" then tint = defaultTint(data) end
	local entry, problem = template(shapeName, data, catalog, tint)
	if not entry and problem == "budget" then
		-- Reuse the shape's default-tint template rather than leaving a primitive.
		local fallback = defaultTint(data)
		local cached = templates[shapeName .. "#" .. (if fallback then fallback:ToHex() else "")]
		if cached then entry = cached end
	end
	if not entry then skip(part, problem or stopReason or "failed"); setStatus(); return end
	if not part.Parent then return end
	local size, offset = placement(part, data, entry)
	if not size then skip(part, "invalid scale"); return end
	local ok, visual = pcall(function()
		local clone = entry.part:Clone()
		clone.Name = part.Name .. " Mesh"
		clone.Size = size
		clone.CFrame = part.CFrame * offset
		clone:SetAttribute("ShapeOf", shapeName)
		clone.Parent = part.Parent
		return clone
	end)
	if not ok or not visual then skip(part, "clone failed"); return end
	handled[part] = true
	stats.instances += 1
	stats.placedTriangles += entry.triangles
	-- Hide the primitive only now that its mesh exists; it stays as the collider.
	part:SetAttribute("ShapeOriginalTransparency", part.Transparency)
	part.Transparency = 1
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") then child.Transparency = 1 end
	end
	local link = Instance.new("ObjectValue")
	link.Name = "ShapeMesh"
	link.Value = visual
	link.Parent = part
	part:SetAttribute("ShapeDone", true)
	pcall(function()
		part:GetPropertyChangedSignal("CFrame"):Connect(function() visual.CFrame = part.CFrame * offset end)
		part.Destroying:Once(function() visual:Destroy() end)
	end)
end

-- Queue: one template build at a time keeps allocation spikes bounded.
local queue, queued = {}, setmetatable({}, {__mode = "k"})
local pumping = false
local function pump()
	if pumping then return end
	pumping = true
	while #queue > 0 do
		local part = table.remove(queue, 1)
		queued[part] = nil
		local ok, problem = pcall(forge, part)
		if not ok then warn("[MeshForge] " .. tostring(problem)); skip(part, "error") end
	end
	pumping = false
	setStatus()
end
local function consider(part)
	if handled[part] or queued[part] then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or type(part:GetAttribute("Shape")) ~= "string" then return end
	queued[part] = true
	table.insert(queue, part)
	task.spawn(pump)
end
local function watch(instance)
	if not instance:IsA("BasePart") or handled[instance] then return end
	if instance:GetAttribute("Shape") ~= nil then consider(instance); return end
	pcall(function()
		instance:GetAttributeChangedSignal("Shape"):Once(function() consider(instance) end)
	end)
end
local function rescan()
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and not handled[instance] and instance:GetAttribute("Shape") ~= nil then consider(instance) end
	end
end

setStatus()
workspace.DescendantAdded:Connect(function(instance) task.defer(watch, instance) end)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
task.defer(function()
	print(string.format("[MeshForge] %s: %d templates (%d tris cached), %d meshes placed (%d tris), %d skipped",
		if stopReason then stopReason else "ready", stats.templates, stats.templateTriangles, stats.instances, stats.placedTriangles, stats.skipped))
end)
if MeshForgeTest then
	MeshForgeTest.forge = {stats = stats, limits = LIMITS, templates = templates, rescan = rescan, consider = consider,
		cornerNormals = cornerNormals, styleSign = styleSign, stopReason = function() return stopReason end}
	return
end
task.spawn(function()
	-- Safety net for attributes set in ways the per-part listeners missed.
	while true do
		task.wait(RESCAN_SECONDS)
		rescan()
	end
end)
script.Destroying:Once(function()
	for _, entry in pairs(templates) do
		if entry then
			pcall(entry.part.Destroy, entry.part)
			if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
		end
	end
end)

-- Exports one island with its §54 environment layer for tools/render-environment.py:
-- the forged ground top (T.ground), the dressing the High tier shows from a
-- viewpoint (T.visible: clutter, shrubs, trees, heroes, cliff dressing,
-- satellites), the hull meshes on their slots, building meshes and every other
-- visible part as a box / cylinder / ball (the Meadow is hidden, as in game).
--   lune run tools/dump-environment.luau "Windpine Grove" out.json [fx,fy,fz] [tier]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local W = require("./world-harness")
local b = W.build()
local T = luau.load(fs.readFile("shared/TerrainArt.lua"), {debugName = "TerrainArt", environment = {Vector3 = Vector3, CFrame = CFrame, Enum = roblox.Enum}, injectGlobals = true})()
local name = process.args[1] or "Windpine Grove"
local isle = b.islands:FindFirstChild(name) or b.archipelago:FindFirstChild(name)
assert(isle, "no island " .. name)
local tier = process.args[4] or "High"
local function cfList(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return {x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22}
end
local function hex(c) return string.format("%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local desc = T.collect(isle, b.Data.Island.ProtectedCircles)
local scene = {meshes = {}, boxes = {}, items = {}, surfaces = {}}
local bud = T.Budgets[tier]
-- Forged ground top and cliff wall (flat arrays, island space -> world).
local function surface(m)
	local verts, cols, nors, faces = {}, {}, {}, {}
	for v = 1, #m.positions // 3 do
		verts[v] = {m.positions[v * 3 - 2] + desc.center[1], m.positions[v * 3 - 1] + desc.center[2], m.positions[v * 3] + desc.center[3]}
		cols[v] = {m.colors[v * 3 - 2], m.colors[v * 3 - 1], m.colors[v * 3]}
		nors[v] = {m.normals[v * 3 - 2], m.normals[v * 3 - 1], m.normals[v * 3]}
	end
	for f = 1, #m.indices, 3 do table.insert(faces, {m.indices[f], m.indices[f + 1], m.indices[f + 2]}) end
	table.insert(scene.surfaces, {vertices = verts, colors = cols, normals = nors, faces = faces})
end
local forged = bud.grounds > 0
if forged then
	surface(T.ground(desc, bud.cell))
	surface(T.hull(desc, bud.hullSeg, bud.hullLevels))
end
local focus = {desc.center[1], desc.center[2], desc.center[3]}
if process.args[3] then
	local i = 1
	for v in string.gmatch(process.args[3], "[^,]+") do focus[i] = tonumber(v); i += 1 end
end
for _, e in ipairs(T.visible(T.plan(desc), tier, focus, false)) do
	local it = e.item
	local cf
	if it.class == "cliff" then
		local x, y, z = T.cliffPosition(it, forged)
		local p = Vector3.new(x, y, z)
		cf = CFrame.lookAt(p, p + Vector3.new(it.out[1], 0, it.out[2]))
	else
		local y = if forged and it.class ~= "satellite" then it.y else it.flatY
		cf = CFrame.new(it.x, y, it.z) * CFrame.Angles(0, it.yaw, 0)
	end
	table.insert(scene.items, {shape = e.shape, tint = it.tint, scale = it.scale, cf = cfList(cf)})
end
-- The forge's own layout (MeshForgeTest describe) for every other Shape host.
local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local Props = luau.load(fs.readFile("art/PropCatalog.lua"), {injectGlobals = true})()
local test = {}
local services = {AssetService = {}, ReplicatedStorage = {WaitForChild = function(_, n) return n end},
	Players = {LocalPlayer = nil}, UserInputService = {TouchEnabled = false, KeyboardEnabled = true}}
luau.load(fs.readFile("forge.client.lua"), {debugName = "forge", environment = {
	game = {GetService = function(_, n) return services[n] end},
	workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
	require = function(n) return if n == "AetherWorldArt" then World elseif n == "AetherArt" then Props else error(n) end,
	Content = {fromObject = function(o) return o end}, MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3,
	Instance = roblox.Instance, Enum = roblox.Enum, Font = roblox.Font,
	task = {spawn = function() end, defer = function() end, wait = function() end}, warn = function() end, print = function() end,
}, injectGlobals = true})()
local owned = {}
for _, p in isle:GetDescendants() do
	if p:IsA("BasePart") and p:GetAttribute("Shape") and not p:GetAttribute("BuildingType") and not p:GetAttribute("Interior")
		and p.Name ~= "Floating foundation" and p.Name ~= "Island underside" then
		local ok, d = pcall(test.forge.describe, p)
		if ok and d and fs.isFile("art/" .. d.shape .. ".obj") then
			local tint = p:GetAttribute("Tint")
			table.insert(scene.meshes, {shape = d.shape, tint = if typeof(tint) == "Color3" then hex(tint) else nil, cf = cfList(d.cframe), box = {d.size.X, d.size.Y, d.size.Z}})
			owned[p] = true
			for _, s in ipairs(d.siblings) do owned[s] = true end
		end
	end
end
for _, p in isle:GetDescendants() do
	if p:IsA("BasePart") and forged and p.Name == "Floating foundation" and p.Parent == isle then
		owned[p] = true -- the forged wall stands for it
	elseif p:IsA("BasePart") and forged and p.Name == "Fractured cliff" then
		owned[p] = true
	elseif p:IsA("BasePart") and (p.Name == "Floating foundation" or p.Name == "Island underside") and p.Parent == isle then
		-- Cylinder slot: the mesh up axis runs along the cylinder (local X).
		local cf = p.CFrame * CFrame.Angles(0, 0, -math.pi / 2)
		table.insert(scene.meshes, {shape = p:GetAttribute("Shape"), tint = hex(p:GetAttribute("Tint") or p.Color), cf = cfList(cf), box = {p.Size.Y, p.Size.X, p.Size.Z},
			fit = if p.Name == "Floating foundation" then {{-10, -6, -10}, {10, 0, 10}} else nil})
		owned[p] = true
	elseif p:IsA("BasePart") and p:GetAttribute("ShapeBox") and (p:GetAttribute("BuildingType") or p:GetAttribute("Interior")) then
		local box, offset = p:GetAttribute("ShapeBox"), p:GetAttribute("ShapeBoxOffset")
		local tint = p:GetAttribute("Tint")
		table.insert(scene.meshes, {shape = p:GetAttribute("Shape"), tint = tint and hex(tint) or nil, cf = cfList(p.CFrame * CFrame.new(offset)), box = {box.X, box.Y, box.Z}})
		if p:GetAttribute("ShapeOwnsModel") then for _, s in p.Parent:GetChildren() do owned[s] = true end end
		owned[p] = true
	end
end
for _, p in isle:GetDescendants() do
	local skip = owned[p] or (p.Name == "Meadow" and p.Parent == isle and forged)
	if p:IsA("BasePart") and not skip and p.Transparency < 0.9 and not p:GetAttribute("BuildingType") then
		local kind = if p.Shape == roblox.Enum.PartType.Cylinder then "cylinder" elseif p.Shape == roblox.Enum.PartType.Ball then "ball" else "box"
		table.insert(scene.boxes, {kind = kind, cf = cfList(p.CFrame), size = {p.Size.X, p.Size.Y, p.Size.Z}, color = hex(p.Color)})
	end
end
fs.writeFile(process.args[2] or "environment.json", serde.encode("json", scene))
print(string.format("%s: %d dressing items, %d meshes, %d parts, %d forged surfaces", name, #scene.items, #scene.meshes, #scene.boxes, #scene.surfaces))

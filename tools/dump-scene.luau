-- Exports one island's static world for tools/render-town.py (World Art pass 2,
-- §40 renders): building meshes (shape, tint, mesh CFrame, scale), every other
-- visible part as a box / cylinder / ball, and the lit window panes.
--   lune run tools/dump-scene.luau "Compass Quay" out.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local W = require("./world-harness")
local b = W.build()
local isle = b.islands:FindFirstChild(process.args[1] or "Compass Quay")
assert(isle, "no island")
local function cfList(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return {x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22}
end
local function hex(c) return string.format("%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local scene = {meshes = {}, boxes = {}, panes = {}}
local owned = {}
for _, p in isle:GetDescendants() do
	if p:IsA("BasePart") and p:GetAttribute("ShapeBox") and (p:GetAttribute("BuildingType") or p:GetAttribute("Interior")) then
		local shape = p:GetAttribute("Shape")
		local box, offset = p:GetAttribute("ShapeBox"), p:GetAttribute("ShapeBoxOffset")
		local tint = p:GetAttribute("Tint")
		table.insert(scene.meshes, {shape = shape, tint = tint and hex(tint) or nil, cf = cfList(p.CFrame * CFrame.new(offset)), box = {box.X, box.Y, box.Z}})
		if p:GetAttribute("ShapeOwnsModel") then for _, s in p.Parent:GetChildren() do owned[s] = true end end
		owned[p] = true
		for v in string.gmatch(p:GetAttribute("WindowGlow") or "", "[^;]+") do
			local n = {}
			for x in string.gmatch(v, "[^,]+") do table.insert(n, tonumber(x)) end
			local cf = p.CFrame * CFrame.new(n[1], n[2], n[3]) * CFrame.Angles(0, n[6], 0) * CFrame.new(0, 0, -0.03)
			table.insert(scene.panes, {cf = cfList(cf), size = {n[4] * .94, n[5] * .94, .04}})
		end
	end
end
for _, p in isle:GetDescendants() do
	if p:IsA("BasePart") and not owned[p] and p.Transparency < 0.9 and not p:GetAttribute("BuildingType") then
		local kind = if p.Shape == roblox.Enum.PartType.Cylinder then "cylinder" elseif p.Shape == roblox.Enum.PartType.Ball then "ball" else "box"
		table.insert(scene.boxes, {kind = kind, cf = cfList(p.CFrame), size = {p.Size.X, p.Size.Y, p.Size.Z}, color = hex(p.Color)})
	end
end
fs.writeFile(process.args[2] or "scene.json", serde.encode("json", scene))
print(string.format("%d meshes, %d parts, %d panes", #scene.meshes, #scene.boxes, #scene.panes))

-- Lists every visible part overlapping a building's walls box (World Art pass 2
-- planning aid): lune run tools/dump-inside.luau "Quay Bank"
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local W = require("./world-harness")
local b = W.build()
local model = b.islands:FindFirstChild(process.args[1] or "Quay Bank", true)
assert(model, "no building")
local host
for _, p in model:GetChildren() do if p:IsA("BasePart") and p:GetAttribute("BuildingType") then host = p end end
local box = host:GetAttribute("ShapeBox")
local cf = host.CFrame * roblox.CFrame.new(host:GetAttribute("ShapeBoxOffset"))
for _, p in b.islands:GetDescendants() do
	if p:IsA("BasePart") and p.Transparency < 1 and not p:IsDescendantOf(model) then
		local q = cf:PointToObjectSpace(p.CFrame.Position)
		local s = p.Size.Magnitude / 2
		if math.abs(q.X) < box.X / 2 + s and math.abs(q.Y) < box.Y / 2 + s and math.abs(q.Z) < box.Z / 2 + s then
			print(p:GetFullName(), q, p.Size)
		end
	end
end

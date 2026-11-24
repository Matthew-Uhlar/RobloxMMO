-- Path strips per island (World Art pass 2 planning aid): lune run tools/dump-paths.luau
local W = require("./world-harness")
local b = W.build()
for _, isle in b.islands:GetChildren() do
	local IC = isle:GetAttribute("IslandCenter")
	local n, lens, off = 0, {}, {}
	for _, p in isle:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Path" then
			n += 1
			table.insert(lens, string.format("%.0f@%.2f", p.Size.Z, p.CFrame.Position.Y - IC.Y))
		end
	end
	print(isle.Name, IC, isle:GetAttribute("IslandRadius"), n, table.concat(lens, " "))
end

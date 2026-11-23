-- Spread of interactive content on the starter islands (planning aid):
--   lune run tools/spread.luau
local W = require("./world-harness")
local Vector3 = require("@lune/roblox").Vector3
local b = W.build()
local function measure(isle, label)
	local IC, R = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
	local n, sum, quad = 0, 0, {0, 0, 0, 0}
	local kinds = {}
	for _, obj in isle:GetDescendants() do
		local pos, kind
		if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then pos, kind = obj.Parent.CFrame.Position, "prompt"
		elseif obj:IsA("BasePart") and string.find(obj.Name, "^Anchor_NPC_") then pos, kind = obj.CFrame.Position, "npc"
		elseif obj:IsA("BasePart") and obj:GetAttribute("BuildingType") then pos, kind = obj.CFrame.Position, "building" end
		if pos then
			local d = Vector3.new(pos.X - IC.X, 0, pos.Z - IC.Z)
			n += 1
			sum += d.Magnitude
			kinds[kind] = (kinds[kind] or 0) + 1
			local q = (if d.X >= 0 then 1 else 0) + (if d.Z >= 0 then 2 else 0) + 1
			quad[q] += 1
		end
	end
	print(string.format("%s r%d: %d items (%s), mean %.1f (%.0f%% of r), quadrants %d/%d/%d/%d", label, R, n,
		(function() local t = {} for k, v in kinds do table.insert(t, k .. " " .. v) end return table.concat(t, " ") end)(),
		sum / math.max(n, 1), 100 * sum / math.max(n, 1) / R, quad[1], quad[2], quad[3], quad[4]))
end
for _, name in {"Compass Quay", "Meadow Reach"} do measure(b.islands:FindFirstChild(name), name) end
for _, m in b.archipelago:GetChildren() do
	if string.find(m.Name, "^WayfarersRest_") then measure(m, m.Name) end
end

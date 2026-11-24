-- ASCII occupancy map of one island (World Art pass 2 planning aid):
--   lune run tools/dump-town.luau "Compass Quay" [cell]
-- '#' visible or solid part, '=' path, 'N' NPC anchor, 'A' other anchor,
-- 'P' prompt host, 'B' building (§40), '.' free meadow, ' ' off the island.
local process = require("@lune/process")
local W = require("./world-harness")
local b = W.build()
local name = process.args[1] or "Compass Quay"
local cell = tonumber(process.args[2]) or 4
local isle = b.islands:FindFirstChild(name)
assert(isle, "no island " .. name)
local IC, R = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
local FLOOR = {Meadow = true, ["Floating foundation"] = true, ["Island underside"] = true, ["Edge guard"] = true, ["Shore ledge"] = true, Wildflowers = true}
local n = math.ceil(R / cell)
local grid = {}
for iz = -n, n do
	grid[iz] = {}
	for ix = -n, n do
		local d = math.sqrt((ix * cell) ^ 2 + (iz * cell) ^ 2)
		grid[iz][ix] = if d < R - 2 then "." else " "
	end
end
local rank = {[" "] = 0, ["."] = 1, ["#"] = 2, ["="] = 3, ["B"] = 4, ["A"] = 5, ["P"] = 6, ["N"] = 7}
local function mark(obj, ch)
	local cf, sz = obj.CFrame, obj.Size
	local function ext(axis) return math.abs(cf.RightVector[axis]) * sz.X / 2 + math.abs(cf.UpVector[axis]) * sz.Y / 2 + math.abs(cf.LookVector[axis]) * sz.Z / 2 end
	local c = cf.Position - IC
	if c.Y > 30 then return end
	local hx, hz = ext("X"), ext("Z")
	if ch == "N" or ch == "A" or ch == "P" then hx, hz = 0.5, 0.5 end
	for iz = math.floor((c.Z - hz) / cell + .5), math.floor((c.Z + hz) / cell + .5) do
		for ix = math.floor((c.X - hx) / cell + .5), math.floor((c.X + hx) / cell + .5) do
			local row = grid[iz]
			if row and row[ix] and row[ix] ~= " " and rank[ch] > rank[row[ix]] then row[ix] = ch end
		end
	end
end
for _, obj in isle:GetDescendants() do
	if obj:IsA("BasePart") then
		local nm = obj.Name
		if string.find(nm, "^Anchor_NPC_") then mark(obj, "N")
		elseif string.find(nm, "^Anchor_") then mark(obj, "A")
		elseif obj:FindFirstChildOfClass("ProximityPrompt") then mark(obj, "P")
		elseif obj:GetAttribute("BuildingType") then mark(obj, "B")
		elseif nm == "Path" then mark(obj, "=")
		elseif not FLOOR[nm] and (obj.Transparency < 1 or obj.CanCollide or obj:GetAttribute("SculptureScale")) then mark(obj, "#") end
	end
end
print(name .. "  centre " .. tostring(IC) .. "  r" .. R .. "  cell " .. cell .. "  (x right, z down)")
local header = "      "
for ix = -n, n do header ..= if ix % 5 == 0 then "|" else " " end
print(header)
for iz = -n, n do
	local line = string.format("%5d ", iz * cell)
	for ix = -n, n do line ..= grid[iz][ix] end
	print(line)
end

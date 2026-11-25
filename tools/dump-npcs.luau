-- §52 preview dump: runs the production npc.server.lua against a small instance
-- double, poses each rig at a moment of its trade idle loop (shared/NpcStyle.lua,
-- forward kinematics through the Motor6Ds), and writes every primitive part plus
-- the forged outfit pieces (shape, bone frame, dye) as JSON for
-- tools/render-npcs.py. Usage (project root):
--   lune run tools/dump-npcs.luau OUT.json [phase] [role ...]
-- phase: seconds into each idle loop (default 0 = the loop's first key).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local function load(path, env)
	return luau.load(fs.readFile(path), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local Style = load("shared/NpcStyle.lua")

-- Instance double --------------------------------------------------------------
local Methods = {}
local Meta = {}
local function new(class)
	local o = setmetatable({__props = {ClassName = class, Name = class}, __children = {}, __attrs = {}}, Meta)
	return o
end
Meta.__index = function(self, key)
	if Methods[key] then return Methods[key] end
	local props = rawget(self, "__props")
	if props[key] ~= nil then return props[key] end
	for _, child in ipairs(rawget(self, "__children")) do if child.Name == key then return child end end
	return nil
end
Meta.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			for i, c in ipairs(list) do if c == self then table.remove(list, i); break end end
		end
		props.Parent = value
		if value then table.insert(rawget(value, "__children"), self) end
		return
	end
	props[key] = value
end
function Methods:GetChildren() return table.clone(rawget(self, "__children")) end
function Methods:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(rawget(o, "__children")) do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Methods:FindFirstChild(name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do if c.Name == name then return c end end
	if recursive then for _, c in ipairs(rawget(self, "__children")) do local f = c:FindFirstChild(name, true); if f then return f end end end
	return nil
end
function Methods:WaitForChild(name) return self:FindFirstChild(name) end
function Methods:IsA(class)
	if class == "BasePart" then return self.ClassName == "Part" or self.ClassName == "MeshPart" end
	return self.ClassName == class
end
function Methods:SetAttribute(k, v) rawget(self, "__attrs")[k] = v end
function Methods:GetAttribute(k) return rawget(self, "__attrs")[k] end
function Methods:GetPivot() return CFrame.new() end
function Methods:PivotTo() end
local function signal() return {Connect = function() return {Disconnect = function() end} end} end
for _, name in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AttributeChanged", "PlayerAdded", "PlayerRemoving", "CharacterAdded"}) do
	Methods[name] = signal()
end
function Methods:GetPropertyChangedSignal() return signal() end

local workspaceDouble = new("Workspace")
local serverStorage = new("ServerStorage")
local styleMarker, dataMarker, themeMarker = {}, {}, {}
local Theme = luau.load(fs.readFile("shared/UiTheme.lua"), {debugName = "UiTheme", injectGlobals = true, environment = {Instance = {new = function(class) return new(class) end}, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint}})()
local env = {
	game = {GetService = function(_, name)
		return ({Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
			ReplicatedStorage = {WaitForChild = function(_, child) return if child == "AetherNpcStyle" then styleMarker elseif child == "AetherUiTheme" then themeMarker else dataMarker end},
			ServerStorage = serverStorage})[name]
	end},
	workspace = workspaceDouble,
	require = function(target) return if target == styleMarker then Style elseif target == themeMarker then Theme else Data end,
	Instance = {new = function(class) return new(class) end},
	RaycastParams = {new = function() return {} end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2,
	ColorSequence = roblox.ColorSequence,
	task = {delay = function() end, spawn = function() end, wait = function() end, defer = function() end},
}
load("npc.server.lua", env)
local stash = serverStorage:FindFirstChild("TownsfolkUnplaced")

-- Forward kinematics -------------------------------------------------------------
local MOTOR_ORDER = {"Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle"}
local JOINT_OF = {}
for joint, motor in pairs(Style.MOTORS) do JOINT_OF[motor] = joint end
local function pose(model, idle, phase)
	local sample = Style.sample(idle, phase, {})
	local rest = {}
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then rest[d] = d.CFrame end end
	-- Weld constraints keep their rest offsets to Part0.
	local welds = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "WeldConstraint" then table.insert(welds, {d.Part0, d.Part1, rest[d.Part0]:Inverse() * rest[d.Part1]}) end
	end
	for _, name in ipairs(MOTOR_ORDER) do
		local m = model:FindFirstChild(name, true)
		if m then
			local c0 = m.C0
			local joint = JOINT_OF[name]
			local v = joint and sample[joint]
			if v then c0 = c0 * CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3])) end
			m.Part1.CFrame = m.Part0.CFrame * c0 * m.C1:Inverse()
		end
	end
	for _ = 1, 2 do for _, w in ipairs(welds) do w[2].CFrame = w[1].CFrame * w[3] end end
end
local function cf(c) return {c:GetComponents()} end

local out = {}
local args = process.args
local phase = tonumber(args[2] or "0") or 0
local only = {}
for i = 3, #args do only[args[i]] = true end
local roster = table.clone(Data.Townsfolk.Order)
for _, role in ipairs(Data.Townsfolk.RegionFolkOrder) do table.insert(roster, role) end
for _, role in ipairs(roster) do
	if next(only) and not only[role] then continue end
	local model
	for _, m in ipairs(stash:GetChildren()) do if m:GetAttribute("TownsfolkRole") == role then model = m end end
	local outfit = Style.outfit(role, Data.Townsfolk.NPCs[role])
	local loop = Style.IDLES[outfit.idle]
	pose(model, outfit.idle, if phase < 0 then loop.beat else phase)
	local hidden = {}
	for _, piece in ipairs(outfit.pieces) do hidden[piece.slot] = true; if piece.slot == "hat" then hidden.hair = true end end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Transparency or 0) < 0.95 and not hidden[d:GetAttribute("OutfitSlot") or ""] then
			table.insert(parts, {name = d.Name, size = {d.Size.X, d.Size.Y, d.Size.Z}, cf = cf(d.CFrame), color = d.Color:ToHex(),
				shape = d.Shape and d.Shape.Name or "Block", alpha = d.Transparency or 0, neon = d.Material == roblox.Enum.Material.Neon})
		end
	end
	local meshes = {}
	for _, piece in ipairs(outfit.pieces) do
		local bone = model:FindFirstChild(piece.bone)
		local frame = bone.CFrame * CFrame.new(piece.at[1], piece.at[2], piece.at[3]) * CFrame.Angles(piece.rot[1], piece.rot[2], piece.rot[3])
		table.insert(meshes, {shape = piece.shape, cf = cf(frame), k = piece.k, dye = piece.dye})
	end
	local def = Data.Townsfolk.NPCs[role]
	local plate = Style.plate(role, def)
	table.insert(out, {role = role, name = def.name, title = def.title, trade = outfit.trade, idle = outfit.idle, parts = parts, meshes = meshes,
		accent = plate.accent, titleColor = plate.titleColor, glyph = plate.glyph})
end
fs.writeFile(args[1] or "npcs.json", serde.encode("json", out))
print("dumped " .. #out .. " townsfolk")

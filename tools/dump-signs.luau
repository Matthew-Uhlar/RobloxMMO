-- Dumps sign models from the generated world to JSON for tools/render-signs.py
-- (approximate offline previews of the §28 sign system; confirm in Studio).
--   lune run tools/dump-signs.luau <out.json> "Sign Title" ["Sign Title" ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local function signal()
	return {Connect = function() return {Disconnect = function() end} end, Fire = function() end}
end
roblox.implementProperty("ProximityPrompt", "Triggered", function() return signal() end)
roblox.implementProperty("ProximityPrompt", "Destroying", function() return signal() end)
local Data = luau.load(fs.readFile("shared/GameData.lua"), {injectGlobals = true})()
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local env = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame,
	Color3 = roblox.Color3, UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum,
	NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function() return Data end,
}
luau.load(fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position"), {environment = env, injectGlobals = true})()
local function v3(v) return {v.X, v.Y, v.Z} end
local function hex(c) return c:ToHex() end
local out = {}
for i = 2, #process.args do
	local model = world:FindFirstChild("Sign " .. process.args[i], true)
	assert(model, "no sign " .. process.args[i])
	local sign = {title = process.args[i], kind = model:GetAttribute("SignArchetype"), parts = {}}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local cf = p.CFrame
			local entry = {name = p.Name, pos = v3(cf.Position), right = v3(cf.RightVector), up = v3(cf.UpVector), back = v3(-cf.LookVector),
				size = v3(p.Size), color = hex(p.Color), shape = p:GetAttribute("Shape"), fit = p:GetAttribute("ShapeFit"),
				tint = p:GetAttribute("Tint") and hex(p:GetAttribute("Tint")) or nil,
				box = p:GetAttribute("ShapeBox") and v3(p:GetAttribute("ShapeBox")) or nil,
				offset = p:GetAttribute("ShapeBoxOffset") and v3(p:GetAttribute("ShapeBoxOffset")) or nil}
			entry.guis = {}
			for _, gui in p:GetChildren() do
			if gui:IsA("SurfaceGui") then
				local items = {}
				for _, g in gui:GetDescendants() do
					if g:IsA("Frame") or g:IsA("TextLabel") then
						local stroke = g:FindFirstChildOfClass("UIStroke")
						table.insert(items, {class = g.ClassName, name = g.Name, x = g.Position.X.Offset, y = g.Position.Y.Offset,
							w = if g.Size.X.Scale == 1 then -1 else g.Size.X.Offset, h = if g.Size.Y.Scale == 1 then -1 else g.Size.Y.Offset,
							z = g.ZIndex, rot = g.Rotation, bg = hex(g.BackgroundColor3), bgT = g.BackgroundTransparency,
							stroke = stroke and {hex(stroke.Color), stroke.Thickness, stroke.Transparency} or nil,
							text = if g:IsA("TextLabel") then g.Text else nil, size = if g:IsA("TextLabel") then g.TextSize else nil,
							color = if g:IsA("TextLabel") then hex(g.TextColor3) else nil, tT = if g:IsA("TextLabel") then g.TextTransparency else nil,
							align = if g:IsA("TextLabel") then g.TextXAlignment.Name else nil,
							font = if g:IsA("TextLabel") then g.FontFace.Family else nil})
					end
				end
				table.insert(entry.guis, {face = gui.Face.Name, pps = gui.PixelsPerStud, items = items})
			end
			end
			table.insert(sign.parts, entry)
		end
	end
	table.insert(out, sign)
end
fs.writeFile(process.args[1], serde.encode("json", out))
print("Dumped " .. #out .. " signs to " .. process.args[1])

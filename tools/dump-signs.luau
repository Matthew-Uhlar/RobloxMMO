-- Dumps sign billboards (§28 v2) from the generated world to JSON for
-- tools/render-signs.py (approximate offline previews; confirm in Studio).
--   lune run tools/dump-signs.luau <out.json> "Sign Title" ["Sign Title" ...]
-- Post arrows are turned as the client would for a camera 14 studs south of
-- the sign looking north (shared/SignView.lua arrowRotation).
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
local View = luau.load(fs.readFile("shared/SignView.lua"), {environment = {Vector3 = roblox.Vector3}, injectGlobals = true})()
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
local function hex(c) return c:ToHex() end
local function walk(node, ox, oy, pivot, out)
	for _, g in node:GetChildren() do
		if g:IsA("GuiObject") then
			local x, y = ox + g.Position.X.Offset, oy + g.Position.Y.Offset
			local w, h = g.Size.X.Offset, g.Size.Y.Offset
			local corner = g:FindFirstChildOfClass("UICorner")
			local stroke = g:FindFirstChildOfClass("UIStroke")
			local grad = g:FindFirstChildOfClass("UIGradient")
			local item = {class = g.ClassName, name = g.Name, x = x, y = y, w = w, h = h, z = g.ZIndex, rot = g.Rotation, pivot = pivot,
				bg = hex(g.BackgroundColor3), bgT = g.BackgroundTransparency,
				corner = corner and {corner.CornerRadius.Scale, corner.CornerRadius.Offset} or nil,
				stroke = stroke and {hex(stroke.Color), stroke.Thickness, stroke.Transparency} or nil,
				grad = grad and {hex(grad.Color.Keypoints[1].Value), hex(grad.Color.Keypoints[#grad.Color.Keypoints].Value), grad.Rotation} or nil,
				night = g:GetAttribute("NightTransparency")}
			if g:IsA("TextLabel") then
				item.text, item.rich, item.size, item.color = g.Text, g.RichText, g.TextSize, hex(g.TextColor3)
				item.tT, item.align, item.font = g.TextTransparency, g.TextXAlignment.Name, g.FontFace.Family
			end
			table.insert(out, item)
			-- A rotated holder (post arrow) turns its children about its centre.
			local childPivot = pivot
			if g.Rotation ~= 0 and #g:GetChildren() > 0 then childPivot = {x + w / 2, y + h / 2, g.Rotation} end
			walk(g, x, y, childPivot, out)
		end
	end
end
local out = {}
for i = 2, #process.args do
	local model = world:FindFirstChild("Sign " .. process.args[i], true)
	assert(model, "no sign " .. process.args[i])
	local anchor = model:FindFirstChildWhichIsA("BasePart")
	local gui = anchor:FindFirstChild("SignBillboard")
	assert(gui, "no billboard on " .. process.args[i])
	local pos = anchor.CFrame.Position
	local cam = roblox.CFrame.lookAt(pos + roblox.Vector3.new(0, 2, 14), pos)
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") and typeof(d:GetAttribute("SignArrowTo")) == "Vector3" then
			d.Rotation = View.arrowRotation(d:GetAttribute("SignArrowTo") - pos, cam)
		end
	end
	local root = gui:FindFirstChild("Sign")
	local items = {}
	walk(root, 0, 0, nil, items)
	table.insert(out, {title = process.args[i], kind = model:GetAttribute("SignArchetype"), theme = model:GetAttribute("SignTheme"),
		w = root.Size.X.Offset, h = root.Size.Y.Offset, light = gui.LightInfluence, items = items})
end
fs.writeFile(process.args[1], serde.encode("json", out))
print("Dumped " .. #out .. " signs to " .. process.args[1])

-- Sign billboards (client; StarterPlayerScripts.SignView; docs/DEPTH-CONTRACT.md §28).
-- The server builds every sign as a floating BillboardGui ("SignBillboard") on
-- an invisible anchor (world.server.lua Signs). This script only presents them:
--   * caps: the nearest View.CAP signs (desktop 18, phones 8) are Enabled, the
--     rest are switched off (their GUI instances are kept and reused);
--   * scale and fade: UIScale "Scale" follows distance (clamped), and the root
--     CanvasGroup fades out over the last 20% of MaxDistance;
--   * bob: a slow float of StudsOffsetWorldSpace for enabled signs (none with
--     Settings › Reduced motion);
--   * post arrows: every "Arrow" holder (attribute SignArrowTo) turns toward
--     its destination relative to the camera, at 10 Hz;
--   * night: the aether crystal's glow brightens after dusk (isle clock).
-- Rules live in shared/SignView.lua (tested by verify-signs.luau). Never
-- touches Lighting (the §35 director is its only writer).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local View = require(ReplicatedStorage:WaitForChild("AetherSignView"))
local L = require(ReplicatedStorage:WaitForChild("AetherLighting"))
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local player = Players.LocalPlayer

local phone = false
pcall(function() phone = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
local CAP = if phone then View.CAP.phone else View.CAP.desktop

local signs = {} -- gui -> record
local list = {} -- records (stable order)
local function add(model)
	for _, gui in ipairs(model:GetDescendants()) do
		if gui:IsA("BillboardGui") and gui.Name == "SignBillboard" and not signs[gui] then
			local root = gui:FindFirstChild("Sign")
			local rec = {gui = gui, root = root, scale = root and root:FindFirstChild("Scale"), anchor = gui.Parent,
				lift = gui:GetAttribute("SignLift") or gui.StudsOffsetWorldSpace.Y, phase = #list * 1.7, arrows = {}, glows = {}, d = math.huge,
				max = gui.MaxDistance, shown = nil}
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("GuiObject") and typeof(d:GetAttribute("SignArrowTo")) == "Vector3" then table.insert(rec.arrows, d) end
				if d:IsA("GuiObject") and d:GetAttribute("NightTransparency") ~= nil then table.insert(rec.glows, d) end
			end
			gui.Enabled = false
			signs[gui] = rec
			table.insert(list, rec)
		end
	end
end
local function drop(model)
	for i = #list, 1, -1 do
		if list[i].gui:IsDescendantOf(model) or not list[i].gui.Parent then
			signs[list[i].gui] = nil
			table.remove(list, i)
		end
	end
end
for _, model in ipairs(CollectionService:GetTagged("AetherSign")) do add(model) end
CollectionService:GetInstanceAddedSignal("AetherSign"):Connect(function(model) task.defer(add, model) end)
CollectionService:GetInstanceRemovedSignal("AetherSign"):Connect(drop)

local visible, scratch = {}, {}
local function now()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	return if ok and type(t) == "number" then t else os.time()
end
local function refreshGlow()
	local day = L.dayFactor(L.clockAt(now(), Data.Calendar))
	for _, rec in ipairs(list) do
		for _, g in ipairs(rec.glows) do
			g.BackgroundTransparency = View.glowTransparency(day, g:GetAttribute("DayTransparency") or .7, g:GetAttribute("NightTransparency") or .35)
		end
	end
end
local function tick()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local eye = camera.CFrame.Position
	for _, rec in ipairs(list) do
		local a = rec.anchor
		rec.d = if a and a.Parent then (a.Position - eye).Magnitude else math.huge
	end
	View.select(list, CAP, scratch)
	table.clear(visible)
	for _, rec in ipairs(scratch) do visible[rec] = true end
	for _, rec in ipairs(list) do
		local on = visible[rec] == true
		if rec.shown ~= on then rec.gui.Enabled = on; rec.shown = on end
		if on then
			if rec.scale then rec.scale.Scale = View.scaleFor(rec.d, phone) end
			if rec.root and rec.root:IsA("CanvasGroup") then rec.root.GroupTransparency = View.fadeFor(rec.d, rec.max) end
			for _, arrow in ipairs(rec.arrows) do
				local to = arrow:GetAttribute("SignArrowTo")
				arrow.Rotation = View.arrowRotation(to - rec.anchor.Position, camera.CFrame)
			end
		end
	end
end

local acc, glowAcc = 0, View.GLOW_TICK
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	glowAcc += dt
	if acc >= View.TICK then acc = 0; tick() end
	if glowAcc >= View.GLOW_TICK then glowAcc = 0; refreshGlow() end
	local reduced = Theme.reducedMotion(player)
	local t = os.clock()
	for rec in pairs(visible) do
		rec.gui.StudsOffsetWorldSpace = Vector3.new(0, rec.lift + View.bob(t, rec.phase, reduced), 0)
	end
end)

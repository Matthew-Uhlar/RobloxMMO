--!strict
-- Sign billboards (client; StarterPlayerScripts.SignView; docs/DEPTH-CONTRACT.md §28).
-- The server builds every sign as a floating BillboardGui ("SignBillboard") on
-- an invisible anchor (world.server.lua Signs). This script only presents them:
--   * caps: the nearest View.CAP signs (desktop 18, phones 8) are candidates,
--     the rest are switched off (GUI instances are kept and reused);
--   * scale: UIScale "Scale" = REF / distance clamped to the archetype's band
--     (phones: viewport under 500 px tall, re-checked when it changes),
--     quantised to 0.05 and written only on change;
--   * compact form under View.DETAIL: the "Detail" layer (kicker ribbon,
--     divider) hides; banners swap to their short "Compact" pennant;
--   * declutter: a candidate whose on-screen box overlaps a nearer drawn sign
--     is switched off for that tick;
--   * fade: the CanvasGroup fades out over the last 20% of MaxDistance
--     (quantised, written on change);
--   * bob: a slow float of StudsOffsetWorldSpace for drawn signs, skipped
--     entirely with Settings › Reduced motion (cached each tick);
--   * post arrows: every "Arrow" holder (attribute SignArrowTo) turns toward
--     its destination relative to the camera, at 10 Hz;
--   * night: the aether crystal's glow brightens after dusk (isle clock).
-- Tagged models (AetherSign) may stream in after their tag (billboards
-- appear later) or lose parts: DescendantAdded / DescendantRemoving keep the
-- records in step. One bad record is dropped instead of stopping the loop.
-- Rules live in shared/SignView.lua (tested by verify-signs.luau). Never
-- touches Lighting (the §35 director is its only writer).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local View = require(ReplicatedStorage:WaitForChild("AetherSignView")) :: any
local L = require(ReplicatedStorage:WaitForChild("AetherLighting")) :: any
local Data = require(ReplicatedStorage:WaitForChild("AetherData")) :: any
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme")) :: any
local player = Players.LocalPlayer

type Rec = {
	gui: BillboardGui, root: CanvasGroup?, scale: UIScale?, compactRoot: CanvasGroup?, compactScale: UIScale?,
	detail: GuiObject?, anchor: BasePart?, kind: string, lift: number, phase: number, arrows: {GuiObject},
	glows: {GuiObject}, d: number, max: number, full: Vector2, compactBox: Vector2, compactY: number,
	shown: boolean?, compact: boolean?, scaleValue: number?, fade: number?, rect: any, clear: boolean?, model: Instance,
}

local phone = false
local CAP: number = View.CAP.desktop
local function readViewport()
	local camera = workspace.CurrentCamera
	phone = View.isPhone(if camera then camera.ViewportSize else nil)
	CAP = if phone then View.CAP.phone else View.CAP.desktop
end

local signs: {[BillboardGui]: Rec} = {}
local list: {Rec} = {}
local watched: {[Instance]: {RBXScriptConnection}} = {}
local function vec2(v: any, fallback: Vector2): Vector2
	return if typeof(v) == "Vector2" then v else fallback
end
local function addGui(model: Instance, gui: BillboardGui)
	if signs[gui] or gui.Name ~= "SignBillboard" then return end
	local root = gui:FindFirstChild("Sign")
	local compactRoot = gui:FindFirstChild("Compact")
	local anchor = gui.Parent
	local size = Vector2.new(gui.Size.X.Offset, gui.Size.Y.Offset)
	local rec: Rec = {
		gui = gui, model = model,
		root = if root and root:IsA("CanvasGroup") then root else nil,
		compactRoot = if compactRoot and compactRoot:IsA("CanvasGroup") then compactRoot else nil,
		anchor = if anchor and anchor:IsA("BasePart") then anchor else nil,
		kind = tostring(gui:GetAttribute("SignKind") or "hanging"),
		lift = tonumber(gui:GetAttribute("SignLift")) or gui.StudsOffsetWorldSpace.Y,
		phase = #list * 1.7, arrows = {}, glows = {}, d = math.huge, max = gui.MaxDistance,
		full = vec2(gui:GetAttribute("SignFull"), size), compactBox = vec2(gui:GetAttribute("SignCompact"), size),
		compactY = tonumber(gui:GetAttribute("SignCompactY")) or 0,
	}
	if rec.root then
		local s = rec.root:FindFirstChild("Scale")
		rec.scale = if s and s:IsA("UIScale") then s else nil
		local detail = rec.root:FindFirstChild("Detail")
		rec.detail = if detail and detail:IsA("GuiObject") then detail else nil
	end
	if rec.compactRoot then
		local s = rec.compactRoot:FindFirstChild("Scale")
		rec.compactScale = if s and s:IsA("UIScale") then s else nil
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") and typeof(d:GetAttribute("SignArrowTo")) == "Vector3" then table.insert(rec.arrows, d) end
		if d:IsA("GuiObject") and d:GetAttribute("NightTransparency") ~= nil then table.insert(rec.glows, d) end
	end
	gui.Enabled = false
	signs[gui] = rec
	table.insert(list, rec)
end
local function dropWhere(test: (Rec) -> boolean)
	for i = #list, 1, -1 do
		local rec = list[i]
		if test(rec) then
			pcall(function() rec.gui.Enabled = false end)
			signs[rec.gui] = nil
			table.remove(list, i)
		end
	end
end
local function scan(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") then addGui(model, d) end
	end
end
local function add(model: Instance)
	if watched[model] then return end
	watched[model] = {
		-- Streaming: the anchor / billboard can arrive after the tagged model.
		model.DescendantAdded:Connect(function(d)
			if d:IsA("BillboardGui") then task.defer(function() if d.Parent then addGui(model, d) end end)
			elseif d:IsA("BasePart") then task.defer(scan, model) end
		end),
		model.DescendantRemoving:Connect(function(d)
			dropWhere(function(rec) return rec.gui == d or rec.anchor == d or rec.gui:IsDescendantOf(d) end)
		end),
	}
	scan(model)
end
local function drop(model: Instance)
	local conns = watched[model]
	if conns then for _, c in ipairs(conns) do c:Disconnect() end end
	watched[model] = nil
	dropWhere(function(rec) return rec.model == model or not rec.gui.Parent end)
end
for _, model in ipairs(CollectionService:GetTagged("AetherSign")) do add(model) end
CollectionService:GetInstanceAddedSignal("AetherSign"):Connect(function(model) task.defer(add, model) end)
CollectionService:GetInstanceRemovedSignal("AetherSign"):Connect(drop)

local drawn: {[Rec]: boolean} = {}
local scratch: {any} = {}
local reduced = false
local function now(): number
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
local function setEnabled(rec: Rec, on: boolean)
	if rec.shown ~= on then rec.gui.Enabled = on; rec.shown = on end
end
-- Scale, compact form and fade of one candidate; returns its screen box.
local function present(rec: Rec, camera: Camera)
	local anchor = rec.anchor :: BasePart
	local scale = View.scaleFor(rec.d, phone, rec.kind)
	local compact = View.compact(scale)
	if rec.compact ~= compact then
		rec.compact = compact
		if rec.detail then rec.detail.Visible = not compact end
		if rec.compactRoot and rec.root then
			rec.root.Visible = not compact
			rec.compactRoot.Visible = compact
		end
	end
	if rec.scaleValue ~= scale then
		rec.scaleValue = scale
		if rec.scale then rec.scale.Scale = scale end
		if rec.compactScale then rec.compactScale.Scale = scale end
	end
	local fade = View.fadeFor(rec.d, rec.max)
	if rec.fade ~= fade then
		rec.fade = fade
		if rec.root then rec.root.GroupTransparency = fade end
		if rec.compactRoot then rec.compactRoot.GroupTransparency = fade end
	end
	local centre = anchor.Position + Vector3.new(0, rec.lift, 0)
	local point = camera:WorldToViewportPoint(centre)
	if point.Z <= 0 then return nil end -- behind the camera
	local box = if compact then rec.compactBox else rec.full
	return View.rect(point.X, point.Y, box.X, box.Y, if compact then rec.compactY else 0, scale)
end
local function tick()
	local camera = workspace.CurrentCamera
	if not camera then return end
	reduced = Theme.reducedMotion(player) == true
	local eye = camera.CFrame.Position
	for _, rec in ipairs(list) do
		local a = rec.anchor
		rec.d = if a and a.Parent then (a.Position - eye).Magnitude else math.huge
	end
	View.select(list, CAP, scratch)
	table.clear(drawn)
	for _, rec in ipairs(scratch) do
		-- QC L4: one bad record (removed anchor, odd attribute) never stops the loop.
		local ok, rect = pcall(present, rec, camera)
		rec.rect = if ok then rect else nil
		if not ok then dropWhere(function(r) return r == rec end) end
	end
	View.declutter(scratch)
	for _, rec in ipairs(scratch) do
		if rec.clear then drawn[rec] = true end
	end
	for _, rec in ipairs(list) do
		local on = drawn[rec] == true
		setEnabled(rec, on)
		if on then
			for _, arrow in ipairs(rec.arrows) do
				local to = arrow:GetAttribute("SignArrowTo")
				if typeof(to) == "Vector3" and rec.anchor then
					pcall(function() arrow.Rotation = View.arrowRotation(to - (rec.anchor :: BasePart).Position, camera.CFrame) end)
				end
			end
		end
	end
	if reduced then
		-- Reduced motion: settle every drawn sign at its rest height once.
		for rec in pairs(drawn) do
			if rec.gui.StudsOffsetWorldSpace.Y ~= rec.lift then rec.gui.StudsOffsetWorldSpace = Vector3.new(0, rec.lift, 0) end
		end
	end
end

-- L2: phone layout follows the viewport (rotation, window resize, new camera).
local viewportConn: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConn then viewportConn:Disconnect() end
	local camera = workspace.CurrentCamera
	viewportConn = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(readViewport) else nil
	readViewport()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

local acc, glowAcc = 0, View.GLOW_TICK
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	glowAcc += dt
	if acc >= View.TICK then acc = 0; tick() end
	if glowAcc >= View.GLOW_TICK then glowAcc = 0; refreshGlow() end
	if reduced then return end
	local t = os.clock()
	for rec in pairs(drawn) do
		rec.gui.StudsOffsetWorldSpace = Vector3.new(0, rec.lift + View.bob(t, rec.phase, false), 0)
	end
end)

-- Gathering Hearts client (StarterPlayerScripts.IsleHearts; docs/DEPTH-CONTRACT.md §46).
--   * Ability key: G (gamepad: ButtonL3) or the HUD chip beside the hotbar
--     relays `heartAbility "<Tree>"` through the atlas (IsleActionLocal); the
--     tree is the one you last swung at (IsleGatherSkill), else the first
--     unlocked ability that is ready. The server checks everything.
--   * The chip shows the chosen tree's ability glyph, a cooldown sweep and an
--     ACTIVE glow, and a small "+N Deepdust" pop when a break pays currency
--     (from the snapshot's `hearts`, relayed on IsleSnapshotLocal).
--   * Animation + VFX play only after the server accepted: it sets the player
--     attribute HeartAbility = "Tree:seq:duration:hits". For the local player
--     the gesture is one call into the existing helper
--     (IsleGestureLocal:Fire(<mine|chop|harvest>)); every nearby player gets
--     the VFX (Deepcall Surge: an azure ring and spark aura for the duration;
--     Rootquake: a green ground shockwave to its reach and a leaf burst;
--     Bountiful Reaping: a golden ring and drifting motes). Reduced motion
--     keeps the colour, drops the expanding tweens and most particles.
-- Nothing here grants anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local make = T.make
local HT = Data.Hearts

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots, toasts, gatherSkill = channel("IsleActionLocal"), channel("IsleSnapshotLocal"), channel("IsleToastLocal"), channel("IsleGatherSkill")
local function tbl(v) return if type(v) == "table" then v else {} end
local function num(v) return if type(v) == "number" and v == v then v else 0 end

local S = {hearts = nil, skill = nil, readyAt = {}, activeUntil = {}, dust = {}, seen = {}, live = 0, sent = 0, watched = {}}
S.FX_CAP = 4 -- concurrent ability effects (nearest players first come first served)
S.FX_RANGE = 120 -- studs from the camera
S.KEY = Enum.KeyCode.G
S.PAD = Enum.KeyCode.ButtonL3

------------------------------------------------------------------------------
-- Which tree the key fires
------------------------------------------------------------------------------
function S.unlocked(id)
	local tv = tbl(tbl(tbl(S.hearts).trees)[id])
	return tbl(tv.ability).unlocked == true
end
function S.ready(id) return os.clock() >= (S.readyAt[id] or 0) end
-- Returns the tree id to fire, or nil and a reason.
function S.pick()
	local preferred = S.skill and HT.TreeOfSkill[S.skill]
	if preferred and S.unlocked(preferred) then return preferred end
	local any = nil
	for _, id in ipairs(HT.Order) do
		if S.unlocked(id) then
			any = any or id
			if S.ready(id) then return id end
		end
	end
	if any then return any end
	return nil, "Unlock a heart ability first: Menu › Hearts (tier 3)."
end
function S.trigger()
	local id, why = S.pick()
	if not id then
		toasts:Fire(why)
		return false
	end
	-- Light client debounce only; the server's cooldown is the authority.
	local now = os.clock()
	if now - S.sent < 0.3 then return false end
	S.sent = now
	actions:Fire("heartAbility", id)
	return true
end

------------------------------------------------------------------------------
-- HUD chip
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleHearts", ResetOnSpawn = false, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local chip = make("TextButton", gui, {Name = "HeartChip", Text = "", AutoButtonColor = false, BorderSizePixel = 0, Visible = false,
	Size = UDim2.fromOffset(44, 44), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.08})
make("UICorner", chip, {CornerRadius = UDim.new(0.5, 0)})
local chipRim = make("UIStroke", chip, {Color = T.color.gold, Thickness = 2})
local sweep = make("Frame", chip, {Name = "Cooldown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2})
make("UICorner", sweep, {CornerRadius = UDim.new(0.5, 0)})
local glyph = T.label(chip, {Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "★", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3})
local keyTag = T.label(chip, {Name = "Key", Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(14, 14), Text = "G", TextSize = 10,
	Font = T.font.display, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4})
local timer = T.label(chip, {Name = "Timer", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4})
local pop = T.label(gui, {Name = "DustPop", Size = UDim2.fromOffset(140, 18), Text = "", TextSize = 13, Visible = false})
S.chip, S.sweep, S.timer, S.pop, S.glyph, S.keyTag = chip, sweep, timer, pop, glyph, keyTag
chip.Activated:Connect(function() S.trigger() end)

local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
-- The chip's slot is reserved in Theme.hudLayout (L.heartChip, QC L6):
-- desktop right of the hotbar (clear of the chat lane and the spell bar
-- corner), touch above the band's left edge and over the spell / prayer bars
-- (IsleHudLift, re-read whenever combat.client.lua changes it).
function S.layout()
	local L = T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled, lift = player:GetAttribute("IsleHudLift")})
	local slot = L.heartChip
	chip.Size = UDim2.fromOffset(slot.w, slot.h)
	chip.Position = UDim2.fromOffset(slot.x, slot.y)
	pop.Position = UDim2.fromOffset(math.max(4, slot.x + math.floor(slot.w / 2) - 70), slot.y - 20)
	return L
end
-- Redraws the chip for the tree the key would fire.
function S.refresh()
	local id = S.pick()
	chip.Visible = id ~= nil
	if not id then return end
	local tree = HT.Trees[id]
	local now = os.clock()
	local left = math.max(0, (S.readyAt[id] or 0) - now)
	local recharge = math.max(1, num(tbl(tbl(tbl(tbl(S.hearts).trees)[id]).ability).recharge))
	local active = now < (S.activeUntil[id] or 0)
	glyph.Text = if id == "Woodcutting" then "≋" elseif id == "Farming" then "☘" else "❖"
	glyph.TextColor3 = Color3.fromHex(tree.color)
	chipRim.Color = if active then Color3.fromHex(tree.accent) elseif left > 0 then T.color.dim else T.color.gold
	chipRim.Thickness = if active then 3 else 2
	sweep.Size = UDim2.fromScale(1, math.clamp(left / recharge, 0, 1))
	timer.Text = if left > 0 then tostring(math.ceil(left)) else ""
	S.tree = id
end
S.layout()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(S.layout)
player:GetAttributeChangedSignal("IsleHudLift"):Connect(S.layout)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0
	S.refresh()
end)

------------------------------------------------------------------------------
-- Snapshot (relayed by the atlas)
------------------------------------------------------------------------------
function S.accept(snap)
	if type(snap) ~= "table" or type(snap.hearts) ~= "table" then return end
	S.hearts = snap.hearts
	local now = os.clock()
	local gained, gainedTree = 0, nil
	for _, id in ipairs(HT.Order) do
		local tv = tbl(tbl(snap.hearts.trees)[id])
		local ab = tbl(tv.ability)
		S.readyAt[id] = now + num(ab.cooldown)
		S.activeUntil[id] = now + num(ab.active)
		local earned = num(tv.earned)
		-- A replayed snapshot (snap.replay) never pops again.
		if S.dust[id] ~= nil and earned > S.dust[id] and not snap.replay then gained, gainedTree = earned - S.dust[id], id end
		S.dust[id] = earned
	end
	if gained > 0 and gainedTree then
		pop.Text = "+" .. gained .. " " .. HT.Trees[gainedTree].currency
		pop.TextColor3 = Color3.fromHex(HT.Trees[gainedTree].accent)
		pop.Visible = true
		S.popSeq = (S.popSeq or 0) + 1
		local seq = S.popSeq
		task.delay(1.2, function() if S.popSeq == seq then pop.Visible = false end end)
	end
	S.refresh()
end
snapshots.Event:Connect(S.accept)
gatherSkill.Event:Connect(function(skill)
	if type(skill) == "string" and HT.TreeOfSkill[skill] then S.skill = skill; S.refresh() end
end)

------------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------------
Input.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == S.KEY or input.KeyCode == S.PAD then
		local ok, focused = pcall(function() return Input:GetFocusedTextBox() end)
		if ok and focused then return end
		S.trigger()
	end
end)

------------------------------------------------------------------------------
-- Animation + VFX (server-confirmed activations)
------------------------------------------------------------------------------
-- "Tree:seq:duration:hits[:radius]" -> tree, seq, duration, hits, radius
-- (nil when malformed). QC L5: the server sends the Rootquake reach, so every
-- viewer draws the caster's ring at the caster's radius.
function S.parse(value)
	if type(value) ~= "string" then return nil end
	local id, seq, duration, hits, radius = string.match(value, "^(%a+):(%d+):(%d+):(%d+):?(%d*)$")
	if not id or not HT.Trees[id] then return nil end
	return id, tonumber(seq), tonumber(duration), tonumber(hits), tonumber(radius)
end
local function fxFolder()
	local folder = workspace:FindFirstChild("IsleHeartsFx")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "IsleHeartsFx"
		folder.Parent = workspace
	end
	return folder
end
local function ring(folder, at, color, from, to, seconds, reduced)
	local part = make("Part", folder, {Name = "HeartRing", Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, Material = Enum.Material.Neon, Color = color, Transparency = 0.15,
		Size = Vector3.new(0.2, if reduced then to else from, if reduced then to else from),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))})
	if reduced then
		task.delay(0.35, function() part:Destroy() end)
	else
		local tween = TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = Vector3.new(0.2, to, to), Transparency = 1})
		tween:Play()
		task.delay(seconds + 0.05, function() part:Destroy() end)
	end
	return part
end
local function emitter(root, color, rate, seconds, reduced, burst)
	local attach = make("Attachment", root, {Name = "HeartFx"})
	local pe = make("ParticleEmitter", attach, {Name = "HeartMotes", Color = ColorSequence.new(color), LightEmission = 1, LightInfluence = 0,
		Rate = if reduced then math.floor(rate / 4) else rate, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.25, 0), Transparency = NumberSequence.new(0, 1)})
	if burst and burst > 0 and pe.Emit then pe:Emit(if reduced then math.floor(burst / 4) else burst) end
	local light = make("PointLight", attach, {Name = "HeartGlow", Color = color, Brightness = 1.5, Range = 10})
	task.delay(seconds, function()
		pe.Enabled = false
		light.Enabled = false
		task.delay(1.3, function() attach:Destroy() end)
	end)
	return attach
end
-- Plays the effect for `who` (any player); returns true when it played.
function S.fx(who, id, duration, hits, radius)
	local tree = HT.Trees[id]
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not tree or not root then return false end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - root.Position).Magnitude > S.FX_RANGE then return false end
	if S.live >= S.FX_CAP then return false end
	S.live += 1
	local reduced = T.reducedMotion(player)
	local color = Color3.fromHex(tree.color)
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	local folder = fxFolder()
	local seconds = math.max(0.8, duration)
	if tree.ability.kind == "quake" then
		local reach = if num(radius) > 0 then num(radius) else HT.abilityStats(tree, {perks = {}}).radius
		S.lastReach = reach
		ring(folder, feet, color, 2, reach * 2, 0.55, reduced)
		emitter(root, Color3.fromHex(tree.accent), 0, 0.6, reduced, 36)
		seconds = 0.8
	elseif tree.ability.kind == "speed" then
		ring(folder, feet, color, 3, 18, 0.6, reduced)
		emitter(root, color, 28, duration, reduced, 24)
	else
		ring(folder, feet, Color3.fromHex(tree.accent), 3, 14, 0.7, reduced)
		emitter(root, color, 18, duration, reduced, 16)
	end
	task.delay(seconds, function() S.live = math.max(0, S.live - 1) end)
	return true
end
function S.onAbility(who)
	local id, seq, duration, hits, radius = S.parse(who:GetAttribute("HeartAbility"))
	if not id or (S.seen[who] and seq <= S.seen[who]) then return end
	S.seen[who] = seq
	if who == player then
		-- The animation hook: one call into the existing gesture helper (animate.client.lua).
		local gesture = ReplicatedStorage:FindFirstChild("IsleGestureLocal")
		if gesture then gesture:Fire(HT.Trees[id].ability.gesture) end
		S.activeUntil[id] = os.clock() + duration
		S.refresh()
	end
	S.fx(who, id, duration, hits, radius)
end
function S.watch(who)
	if S.watched[who] then return end
	S.watched[who] = true
	-- A value already set when we start watching is history, never replayed.
	local _, seq = S.parse(who:GetAttribute("HeartAbility"))
	S.seen[who] = seq or 0
	who:GetAttributeChangedSignal("HeartAbility"):Connect(function() S.onAbility(who) end)
end
for _, who in ipairs(Players:GetPlayers()) do S.watch(who) end
Players.PlayerAdded:Connect(S.watch)
Players.PlayerRemoving:Connect(function(who) S.watched[who], S.seen[who] = nil, nil end)

-- Headless suites read the state through this (verify-hearts.luau).
local api = Instance.new("BindableFunction")
api.Name = "IsleHeartsApi"
api.OnInvoke = function(kind) if kind == "state" then return S end return nil end
api.Parent = player

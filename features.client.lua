--!strict
-- MMO Features client (StarterPlayerScripts.IsleFeatures; docs/DEPTH-CONTRACT.md §31).
--   * Announcement toasts: COLLECTION UNLOCKED, collection / skill / Isle Renown
--     level-ups and Wayfarer's Path steps from snapshot.announce = {seq, list}
--     (a recent ring, deduped by seq), queued one at a time above the hotbar
--     band, plus a styled system line in chat when TextChatService is present.
--   * Shop quantity picker: ReplicatedStorage.IsleQuantityLocal:Fire(spec) opens
--     a menu (1, 8, 16, 32, 64, custom) with the total; spec = {verb, base, name,
--     unit (coins per lot), amount (items per lot), max (lots)}. Buying fires
--     IsleActionLocal(verb, base .. ":" .. qty) through the atlas; the server
--     validates the quantity, coins and stock.
--     Sell mode (spec.sell = true, verb "sell"): max = the sellable count (held −
--     the kept upgraded copy), the totals read "+coins" and the button "Sell";
--     the satchel's "Sell…" and the atlas Items page open it (sell "<id>:<n>").
--   * Renown nameplates: "✦ <level> <title>" above every player's head from the
--     server-set attributes RenownLevel / RenownTitle / RenownColor.
--   * Skyward Vents: when the server sets VentFlight on this player, the arc to
--     the vent's VentLanding plays locally; the server lands the rider anyway.
--     Polish: wind streaks on the rider, a camera FOV kick and banking tilt
--     (Data.Vents.Fx); reduced motion keeps only a lighter wind.
-- Nothing here grants anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local C, make = T.color, T.make
local F = Data.Features

local function channel(name: string): any
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots, quantity = channel("IsleActionLocal"), channel("IsleSnapshotLocal"), channel("IsleQuantityLocal")
local function tbl(v: any): any return if type(v) == "table" then v else {} end
local function num(v: any): number return if type(v) == "number" and v == v then v else 0 end

local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleFeatures", ResetOnSpawn = false, DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local S: any = {lastSeq = nil, queue = {}, showing = false, shown = {}, chat = {}, picker = nil, plates = {}, watches = {}, flights = 0}
local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
local function layout() return T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled}) end

------------------------------------------------------------------------------
-- Announcement toasts
------------------------------------------------------------------------------
local toast = T.frame(gui, {name = "AnnounceToast", size = UDim2.fromOffset(340, 54), ornate = false, rimThickness = 1.5, visible = false, transparency = 0.08})
local toastHead = T.label(toast, {Name = "Head", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 16), Font = T.font.display, TextSize = 12,
	TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.void})
local toastBody = T.label(toast, {Name = "Message", Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -24, 0, 20), Font = T.font.label, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.35, TextStrokeColor3 = C.void})
-- Glow accent: an outer stroke in the announcement's colour.
local glowFrame = make("Frame", toast, {Name = "GlowRing", BackgroundTransparency = 1, Position = UDim2.fromOffset(-3, -3), Size = UDim2.new(1, 6, 1, 6), Active = false})
T.corner(glowFrame, 8)
local toastGlow = make("UIStroke", glowFrame, {Name = "Glow", Thickness = 2.5, Transparency = 0.35, Color = C.gold})
local function placeToast()
	local L = layout()
	local w = math.max(200, math.min(360, L.lane.right - L.lane.left, L.w - 20))
	local h = if L.short then 46 else 54
	toast.Size = UDim2.fromOffset(w, h)
	toastBody.TextSize = if L.short then 12 else 14
	-- Above the hotbar band, leaving the atlas notice strip (toastBottom) clear below.
	local bottom = L.band.y - (if L.short then 50 else 64)
	toast.Position = UDim2.fromOffset(math.floor((L.w - w) / 2), math.max(8, bottom - h))
end
-- Announcements are Game messages: the chat router (overlay.client.lua, §34)
-- applies the Game tab's On / Filtered / Off state (announcements count as
-- important), collapses repeats and prints the coloured system line.
local chatRouter = channel("IsleChatLocal")
local function chatLine(text: string, color: string)
	table.insert(S.chat, text)
	if #S.chat > 20 then table.remove(S.chat, 1) end
	pcall(function() chatRouter:Fire("announce", text, color, true) end)
end
local showNext: () -> ()
showNext = function()
	local entry = table.remove(S.queue, 1)
	if not entry then S.showing = false; toast.Visible = false; return end
	S.showing = true
	local text = F.announceText(entry)
	placeToast()
	toastHead.Text = text.head
	toastHead.TextColor3 = T.rgb(text.color)
	toastGlow.Color = T.rgb(text.color)
	toastBody.Text = text.body
	toast.Visible = true
	table.insert(S.shown, text.head .. " " .. text.body)
	if #S.shown > 30 then table.remove(S.shown, 1) end
	task.delay(if #S.queue > 2 then 1.6 else 2.6, showNext)
end
-- Every snapshot carries the recent ring; show entries newer than the last seen.
local function observe(snap: any)
	local ring = type(snap) == "table" and snap.announce
	if type(ring) ~= "table" or type(ring.list) ~= "table" then return end
	local seq = num(ring.seq)
	-- A fresh session (server ring restarted) resets the cursor.
	if S.lastSeq and seq < S.lastSeq then S.lastSeq = 0 end
	local from = S.lastSeq or 0
	for _, entry in ipairs(ring.list) do
		if type(entry) == "table" and num(entry.seq) > from then
			table.insert(S.queue, entry)
			local text = F.announceText(entry)
			chatLine(text.head .. "  " .. text.body, text.color)
		end
	end
	S.lastSeq = math.max(from, seq)
	F.trimAnnouncements(S.queue, 8) -- oldest ordinary toasts go first; renown / path toasts stay
	if not S.showing and #S.queue > 0 then showNext() end
end
if snapshots.Event then snapshots.Event:Connect(observe) end
task.spawn(function()
	local update = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if update then update.OnClientEvent:Connect(observe) end
end)

------------------------------------------------------------------------------
-- Shop quantity picker
------------------------------------------------------------------------------
local shade = make("TextButton", gui, {Name = "QuantityShade", Text = "", AutoButtonColor = false, BackgroundColor3 = C.void, BackgroundTransparency = 0.45,
	BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20})
local picker, pickerBody = T.frame(gui, {name = "QuantityPicker", title = "HOW MANY?", size = UDim2.fromOffset(330, 252), visible = false, transparency = 0.04})
picker.ZIndex = 21
local pickName = T.label(pickerBody, {Name = "ItemName", Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 18), Font = T.font.label, TextSize = 14, TextColor3 = C.gold})
local pickTotal = T.label(pickerBody, {Name = "Total", Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 16), TextSize = 12, TextColor3 = C.dim, RichText = true})
local grid = make("Frame", pickerBody, {Name = "Presets", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 98)})
make("UIGridLayout", grid, {CellSize = UDim2.new(1 / 3, -6, 0, 44), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder})
local presetButtons = {}
local customBox = make("TextBox", pickerBody, {Name = "Custom", Position = UDim2.fromOffset(12, 152), Size = UDim2.new(0.5, -15, 0, 44), BackgroundColor3 = C.inset,
	BorderSizePixel = 0, Text = "", PlaceholderText = "Custom (1-" .. F.Shop.MAX_LOTS .. ")", ClearTextOnFocus = false, Font = T.font.label, TextSize = 13,
	TextColor3 = C.text, PlaceholderColor3 = C.dim})
T.corner(customBox, 5)
local buyCustom = T.button(pickerBody, "Buy", {name = "BuyCustom", position = UDim2.new(0.5, 3, 0, 152), size = UDim2.new(0.5, -15, 0, 44), tone = "primary"})
local cancel = T.button(pickerBody, "Cancel", {name = "Cancel", position = UDim2.new(0, 12, 1, -6), anchor = Vector2.new(0, 1), size = UDim2.new(1, -24, 0, 0), tone = "ghost"})
cancel.Visible = false -- the shade and Esc close the menu; Cancel shows when there is room
local function closePicker()
	S.picker = nil
	S.sellArmed = nil
	picker.Visible, shade.Visible = false, false
end
local function lots(spec: any, qty: any): number return math.clamp(math.floor(num(qty)), 1, math.max(1, math.floor(num(spec.max)))) end
local function costText(spec: any, qty: number): string
	local amount = math.max(1, math.floor(num(spec.amount)))
	local items = qty * amount
	-- Polish: in sell mode the total is what the merchant pays.
	return "×" .. T.commas(items) .. "  ·  " .. (if spec.sell then "+" else "") .. T.commas(qty * num(spec.unit)) .. " coins"
end
local function buy(qty: any)
	local spec = S.picker
	if not spec then return end
	qty = math.floor(num(qty))
	if qty < 1 or qty > math.max(1, math.floor(num(spec.max))) then return end
	-- Polish QC M1: selling is never one tap. The first tap arms a confirmation
	-- ("Sell 32 for +128 coins?"); only a second tap on the same quantity sends.
	if spec.sell and S.sellArmed ~= qty then
		S.sellArmed = qty
		pickTotal.Text = "Sell " .. T.commas(qty) .. " for +" .. T.commas(qty * num(spec.unit)) .. " coins?  Tap again to confirm."
		buyCustom.Text = "Confirm"
		picker:SetAttribute("SellArmed", qty)
		return
	end
	closePicker()
	-- A sell always names its count (a bare sell "<id>" sells the whole stack).
	actions:Fire(spec.verb, if qty == 1 and not spec.sell then spec.base else spec.base .. ":" .. qty)
end
for i, n in ipairs(F.Shop.Presets) do
	local b = T.button(grid, "×" .. n, {name = "Qty" .. n, order = i, textSize = 13})
	b.Activated:Connect(function() buy(n) end)
	presetButtons[n] = b
end
buyCustom.Activated:Connect(function() buy(tonumber(customBox.Text)) end)
shade.Activated:Connect(closePicker)
customBox:GetPropertyChangedSignal("Text"):Connect(function()
	local spec = S.picker
	local n = tonumber(customBox.Text)
	-- Editing the custom count disarms a pending sell confirmation.
	if spec and spec.sell and S.sellArmed then S.sellArmed = nil; buyCustom.Text = "Sell"; picker:SetAttribute("SellArmed", nil) end
	if spec and n then pickTotal.Text = costText(spec, lots(spec, n)) end
end)
local function openPicker(spec: any)
	if type(spec) ~= "table" or type(spec.verb) ~= "string" or type(spec.base) ~= "string" then return end
	-- Warp scrolls and one-of-a-kind wares are bought one at a time (the server refuses qty > 1).
	-- Polish: sell mode (spec.sell; verb sell "<id>:<n>") is up to the sellable count, any item.
	if not spec.sell and spec.item ~= nil and F.Shop.singleLot(spec.item) then return end
	if spec.sell and spec.verb ~= "sell" then return end
	S.picker = spec
	S.sellArmed = nil
	picker:SetAttribute("SellArmed", nil)
	local maxLots = math.clamp(math.floor(num(spec.max)), 1, if spec.sell then F.SELL_MAX else F.Shop.MAX_LOTS)
	spec.max = maxLots
	buyCustom.Text = if spec.sell then "Sell" else "Buy"
	customBox.PlaceholderText = "Custom (1-" .. T.commas(maxLots) .. ")"
	picker:SetAttribute("Mode", if spec.sell then "sell" else "buy")
	local L = layout()
	local w, h = math.min(330, L.w - 20), math.min(252, L.h - 16)
	picker.Size = UDim2.fromOffset(w, h)
	picker.Position = UDim2.fromOffset(math.floor((L.w - w) / 2), math.floor((L.h - h) / 2))
	pickName.Text = tostring(spec.name or "Item")
	pickTotal.Text = costText(spec, 1) .. "  each"
	for n, b in pairs(presetButtons) do
		local ok = n <= maxLots
		b.Text = "×" .. n .. "\n" .. (if spec.sell then "+" else "") .. T.shortCount(n * num(spec.unit)) .. "c"
		T.tone(b, if ok then "secondary" else "ghost")
		b.Active = ok
		b.AutoButtonColor = false
		b:SetAttribute("Disabled", not ok)
	end
	customBox.Text = ""
	picker.Visible, shade.Visible = true, true
end
quantity.Event:Connect(openPicker)
Input.InputBegan:Connect(function(input, used)
	if not used and input.KeyCode == Enum.KeyCode.Escape and S.picker then closePicker() end
end)

------------------------------------------------------------------------------
-- Renown nameplates (every player's head)
------------------------------------------------------------------------------
local function plate(target: Player)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	local level = target:GetAttribute("RenownLevel")
	local held = S.plates[target]
	if not head or type(level) ~= "number" then
		if held then held.gui:Destroy(); S.plates[target] = nil end
		return
	end
	if not held or held.head ~= head or not held.gui.Parent then
		if held then held.gui:Destroy() end
		local board = Instance.new("BillboardGui")
		board.Name = "RenownPlate"
		board.Size = UDim2.new(6, 0, 0.5, 0)
		board.StudsOffset = Vector3.new(0, 3.9, 0)
		board.MaxDistance = 80
		board.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Name = "Renown"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextStrokeTransparency = 0.35
		text.Parent = board
		board.Adornee = head
		board.Parent = head
		held = {gui = board, label = text, head = head}
		S.plates[target] = held
	end
	local title = target:GetAttribute("RenownTitle")
	local color = target:GetAttribute("RenownColor")
	held.label.Text = "✦ " .. level .. (if type(title) == "string" and title ~= "" then "  " .. title else "")
	held.label.TextColor3 = if type(color) == "string" and #color == 6 then T.rgb(color) else C.text
end
-- Connections per watched player (S.watches), disconnected when they leave.
local function watch(target: Player)
	if S.watches[target] then return end
	local conns = {}
	S.watches[target] = conns
	for _, key in ipairs({"RenownLevel", "RenownTitle", "RenownColor"}) do
		table.insert(conns, target:GetAttributeChangedSignal(key):Connect(function() plate(target) end))
	end
	table.insert(conns, target.CharacterAdded:Connect(function(character)
		task.spawn(function()
			if character:WaitForChild("Head", 10) and S.watches[target] then plate(target) end
		end)
	end))
	plate(target)
end
for _, other in ipairs(Players:GetPlayers()) do watch(other) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(other)
	for _, c in ipairs(S.watches[other] or {}) do c:Disconnect() end
	S.watches[other] = nil
	local held = S.plates[other]
	if held then held.gui:Destroy() end
	S.plates[other] = nil
end)

------------------------------------------------------------------------------
-- Skyward Vents: the local arc
------------------------------------------------------------------------------
local function ventPad(id: string): Instance?
	local ok, list = pcall(function() return game:GetService("CollectionService"):GetTagged("SkywardVent") end)
	if not ok then return nil end
	for _, pad in ipairs(list) do if pad:GetAttribute("VentId") == id then return pad end end
	return nil
end
local function fly()
	local raw = player:GetAttribute("VentFlight")
	local id = type(raw) == "string" and string.match(raw, "^(%w+):%d+$")
	local pad = id and ventPad(id)
	local landing = pad and pad:GetAttribute("VentLanding")
	local root = (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if typeof(landing) ~= "Vector3" or not root then return end
	S.flights += 1
	local token = S.flights
	local from = root.Position
	local started = os.clock()
	local V = Data.Vents
	local fx = V.Fx
	-- Polish: wind streaks on the rider and (unless reduced motion) a camera FOV
	-- kick and a banking tilt over the arc; everything is undone at the landing.
	local reduced = T.reducedMotion(player)
	S.ventReduced = reduced
	local wind = Instance.new("Attachment")
	wind.Name = "VentWind"
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "VentWindStreaks"
	streaks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	streaks.Rate = if reduced then fx.WIND_RATE_REDUCED else fx.WIND_RATE
	streaks.Lifetime = NumberRange.new(0.25, 0.45)
	streaks.Speed = NumberRange.new(28, 40)
	streaks.SpreadAngle = Vector2.new(25, 25)
	streaks.EmissionDirection = Enum.NormalId.Bottom
	streaks.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
	streaks.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)})
	streaks.LightEmission = 0.4
	streaks.Color = ColorSequence.new(Color3.fromRGB(230, 246, 255))
	streaks.Parent = wind
	wind.Parent = root
	S.ventWind = wind
	local camera = workspace.CurrentCamera
	-- Polish QC L2: the base FOV is module-level and captured only while no arc owns
	-- the camera, so a vent ridden mid-arc never mistakes a kicked FOV for the base.
	if camera and S.ventFovOwner == nil then S.ventBaseFov = camera.FieldOfView end
	local baseFov = S.ventBaseFov or 70
	local side = if (landing - from):Cross(Vector3.yAxis).X >= 0 then 1 else -1
	local tiltName = "IsleVentTilt" .. token
	local tilting = false
	if camera and not reduced then
		tilting = true
		S.ventFovOwner = token
		pcall(function()
			RunService:BindToRenderStep(tiltName, Enum.RenderPriority.Camera.Value + 1, function()
				local t = math.clamp((os.clock() - started) / V.FLIGHT, 0, 1)
				camera.FieldOfView = baseFov + fx.fovKick(t)
				camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, side * fx.tilt(t))
			end)
		end)
	end
	local function finishFx()
		if tilting then
			tilting = false
			pcall(function() RunService:UnbindFromRenderStep(tiltName) end)
			-- Only the arc that owns the kick restores it (a newer kicked arc keeps going).
			if S.ventFovOwner == token then
				S.ventFovOwner = nil
				if camera then camera.FieldOfView = baseFov end
			end
		end
		streaks.Enabled = false
		task.delay(0.5, function() wind:Destroy() end)
	end
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / V.FLIGHT
		if token ~= S.flights or t >= 0.98 or not root.Parent then if connection then connection:Disconnect() end; finishFx(); return end
		local flat = from:Lerp(landing, t)
		local pos = Vector3.new(flat.X, V.arcY(from.Y, landing.Y, t), flat.Z)
		local ahead = from:Lerp(landing, math.min(1, t + 0.05))
		root.CFrame = CFrame.lookAt(pos, Vector3.new(ahead.X, pos.Y, ahead.Z))
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end
player:GetAttributeChangedSignal("VentFlight"):Connect(fly)

------------------------------------------------------------------------------
-- Test / tooling hook (like IsleHudApi).
------------------------------------------------------------------------------
local api = Instance.new("BindableFunction")
api.Name = "IsleFeaturesApi"
api.OnInvoke = function(method)
	if method == "state" then return S end
	return nil
end
api.Parent = player
S.gui, S.toast, S.picker_frame, S.shade, S.custom = gui, toast, picker, shade, customBox

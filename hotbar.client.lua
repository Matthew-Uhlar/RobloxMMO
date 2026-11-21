-- Hotbar: SkyBlock-style 9-slot bar + OSRS-style "wield". See docs/DEPTH-CONTRACT.md §26.
--   slot 1      the equipped weapon (snapshot depth.equipment.weapon)
--   slot 2      the context tool: the best owned tool for the last gather
--               prompt shown (pickaxe at ore, hatchet at trees, rod at water, hoe at crops)
--   slots 3-9   any owned item (saved server-side: `hotbarSet "<slot>:<itemId>"`,
--               published as the Hotbar attribute "id3,...,id9")
-- Keys 1-9, the mouse wheel over the bar, tap / click a slot. Right-click or
-- long-press slots 3-9 to pick an item. Selecting a slot sends `hold "<itemId>"`
-- ("none" for an empty or non-holdable slot); the server validates it, stores
-- p.held and sets the HeldItem attribute that held.server.lua turns into the
-- welded model. animate.client.lua fires ReplicatedStorage.IsleHeldAuto(itemId)
-- when a gather or attack needs another item: that becomes `hold "~<itemId>"`,
-- a temporary switch the server undoes after Data.Held.AUTO_RETURN idle seconds.
--
-- API for other client scripts (inventory "Move to hotbar"):
--   ReplicatedStorage.HotbarApi (BindableFunction):Invoke(method, ...)
--     "assign", slot (3-9), itemId|nil  -> ok, message   (nil clears the slot)
--     "getSlots"                        -> {slots = {[1..9] = id|false}, selected, held}
--     "select", slot (1-9)              -> ok
--   ReplicatedStorage.HotbarChanged (BindableEvent) fires (slots, selected, held).
-- Layout: bottom-centre; the band of STYLE.reserve px above it is left free for
-- the shared action bar. Publishes local attributes IsleHotbarHeight (bar +
-- reserve, so the combat spell bar and toasts clear both) and IsleHotbarWidth.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local Held = Data.Held
local action = ReplicatedStorage:WaitForChild("IsleAction")

-- All styling in one table so the shared UiTheme can replace it wholesale.
local function rgb(hex)
	hex = tostring(hex or "FFFFFF")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16) or 255, tonumber(hex:sub(5, 6), 16) or 255)
end
local STYLE = {
	slot = 52, slotCompact = 46, gap = 4, bottom = 6, reserve = 70, radius = 8, pad = 4,
	deep = rgb("0C1820"), raised = rgb("2A4D5E"), ivory = rgb("F7EFDC"), gold = rgb("F3C66E"), brass = rgb("C9974A"),
	mint = rgb("7FE3CC"), track = rgb("060E14"), selected = rgb("F3C66E"), auto = rgb("7FE3CC"),
	font = Enum.Font.BuilderSansExtraBold, glyphSize = 22, countSize = 13, keySize = 10, nameSize = 15,
	glyph = {sword = "⚔", greatblade = "⚔", dagger = "†", maul = "♜", glaive = "↟", shortbow = "➶", longbow = "➶",
		staff = "✦", wand = "✧", shield = "⛨", pickaxe = "⛏", hatchet = "⚒", rod = "⚓", hoe = "⚘", hammer = "⚒"},
	kindGlyph = {consumable = "✚", resource = "◆", material = "◈", accessory = "❖", armor = "⛊", pet = "❦"},
}
local COUNT, SLOTS = Held.HOTBAR_SLOTS, Held.FREE_SLOTS

local function make(class, parent, props)
	local object = Instance.new(class)
	for k, v in pairs(props or {}) do object[k] = v end
	object.Parent = parent
	return object
end

local S = {items = {}, weapon = nil, tools = {}, contextSkill = "Mining", selected = 1, loaded = false, buttons = {}}

------------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------------
local function owned(id) return type(id) == "string" and (tonumber(S.items[id]) or 0) > 0 end
local function contextTool()
	local id = S.tools[S.contextSkill]
	if owned(id) then return id end
	for _, skill in ipairs({"Mining", "Woodcutting", "Fishing", "Farming"}) do
		if owned(S.tools[skill]) then return S.tools[skill] end
	end
	return nil
end
local function slotItem(i)
	if i == 1 then return if owned(S.weapon) then S.weapon else nil end
	if i == 2 then return contextTool() end
	local list = string.split(tostring(player:GetAttribute("Hotbar") or ""), ",")
	local id = list[i - 2]
	return if id and id ~= "" and owned(id) then id else nil
end
local function currentHeld()
	local id = player:GetAttribute("HeldItem")
	return if type(id) == "string" and id ~= "" then id else nil
end

------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleHotbar", ResetOnSpawn = false, DisplayOrder = 6,
	IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local bar = make("Frame", gui, {Name = "Hotbar", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Visible = false})
local nameTag = make("TextLabel", gui, {Name = "HeldName", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Font = STYLE.font,
	TextSize = STYLE.nameSize, TextColor3 = STYLE.ivory, TextStrokeTransparency = 0.35, TextStrokeColor3 = STYLE.deep, Text = "",
	Size = UDim2.fromOffset(320, 20), Visible = false})
for i = 1, COUNT do
	local b = make("TextButton", bar, {Name = "Slot" .. i, Text = "", AutoButtonColor = true, BackgroundColor3 = STYLE.deep,
		BackgroundTransparency = 0.12, BorderSizePixel = 0, Selectable = true})
	make("UICorner", b, {CornerRadius = UDim.new(0, STYLE.radius)})
	make("UIStroke", b, {Name = "Rim", Color = STYLE.brass, Thickness = 1.5, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	local swatch = make("Frame", b, {Name = "Swatch", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * STYLE.pad, 1, -2 * STYLE.pad), BackgroundColor3 = STYLE.raised, BackgroundTransparency = 0.35, BorderSizePixel = 0})
	make("UICorner", swatch, {CornerRadius = UDim.new(0, STYLE.radius - 2)})
	make("UIGradient", swatch, {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.55, 0.55, 0.55))})
	make("TextLabel", b, {Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = STYLE.font, TextSize = STYLE.glyphSize,
		TextColor3 = STYLE.ivory, Text = "", TextStrokeTransparency = 0.3, TextStrokeColor3 = STYLE.deep, ZIndex = 2})
	make("TextLabel", b, {Name = "Count", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -1), Size = UDim2.fromOffset(30, 14),
		BackgroundTransparency = 1, Font = STYLE.font, TextSize = STYLE.countSize, TextColor3 = STYLE.ivory, TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.2, TextStrokeColor3 = STYLE.deep, Text = "", ZIndex = 3})
	make("TextLabel", b, {Name = "Key", Position = UDim2.fromOffset(3, 1), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1,
		Font = STYLE.font, TextSize = STYLE.keySize, TextColor3 = STYLE.gold, Text = tostring(i), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.4, TextStrokeColor3 = STYLE.deep, ZIndex = 3, Visible = not UserInputService.TouchEnabled})
	S.buttons[i] = b
end

-- Picker (slots 3-9): owned items, holdable first.
local picker = make("Frame", gui, {Name = "HotbarPicker", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = STYLE.deep,
	BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false, Size = UDim2.fromOffset(300, 260)})
make("UICorner", picker, {CornerRadius = UDim.new(0, 12)})
make("UIStroke", picker, {Color = STYLE.brass, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
local pickerTitle = make("TextLabel", picker, {Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -64, 0, 26),
	Font = STYLE.font, TextSize = 15, TextColor3 = STYLE.gold, TextXAlignment = Enum.TextXAlignment.Left, Text = "Slot"})
local pickerClose = make("TextButton", picker, {Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(44, 44),
	BackgroundTransparency = 1, Font = STYLE.font, TextSize = 18, TextColor3 = STYLE.ivory, Text = "✕"})
local list = make("ScrollingFrame", picker, {Name = "List", Position = UDim2.fromOffset(8, 46), Size = UDim2.new(1, -16, 1, -54), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", list, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})

------------------------------------------------------------------------------
-- Server calls
------------------------------------------------------------------------------
local toastChannel
local function toast(text)
	if type(text) ~= "string" or text == "" then return end
	toastChannel = toastChannel or ReplicatedStorage:FindFirstChild("IsleToastLocal")
	if toastChannel then toastChannel:Fire(text) end
end
local function invoke(verb, item)
	local ok, result = pcall(function() return action:InvokeServer(verb, item) end)
	if not ok or type(result) ~= "table" then return nil end
	return result
end
local sendToken = 0
-- Debounced: a fast scroll sends only where it settles.
local function requestHold(want)
	sendToken += 1
	local token = sendToken
	task.delay(0.12, function()
		if token ~= sendToken then return end
		if (currentHeld() or "none") == want then return end
		local result = invoke("hold", want)
		if result and (result.heldItem or "") ~= (if want == "none" then "" else want) then toast(result.message) end
	end)
end

------------------------------------------------------------------------------
-- Paint
------------------------------------------------------------------------------
local changed = ReplicatedStorage:FindFirstChild("HotbarChanged") or make("BindableEvent", ReplicatedStorage, {Name = "HotbarChanged"})
local function slotList()
	local out = table.create(COUNT, false)
	for i = 1, COUNT do out[i] = slotItem(i) or false end
	return out
end
local function glyphFor(def)
	local class = Held.classOf(def)
	return (class and STYLE.glyph[class]) or STYLE.kindGlyph[def.kind] or "•"
end
local function paint()
	local held = currentHeld()
	for i, b in ipairs(S.buttons) do
		local id = slotItem(i)
		local def = id and Data.Items[id]
		local glyph, count, swatch = b:FindFirstChild("Glyph"), b:FindFirstChild("Count"), b:FindFirstChild("Swatch")
		glyph.Text = if def then glyphFor(def) else ""
		glyph.TextColor3 = if def then rgb(def.color) else STYLE.ivory
		local n = if def then tonumber(S.items[id]) or 0 else 0
		count.Text = if n > 1 and not Held.holdable(id) then tostring(n) else ""
		swatch.BackgroundColor3 = if def then rgb(def.color):Lerp(STYLE.deep, 0.55) else STYLE.raised
		swatch.BackgroundTransparency = if def then 0.15 else 0.55
		local rim = b:FindFirstChild("Rim")
		local isSelected, isAuto = i == S.selected, held ~= nil and id == held and i ~= S.selected
		rim.Color = if isSelected then STYLE.selected elseif isAuto then STYLE.auto else STYLE.brass
		rim.Thickness = if isSelected then 3 elseif isAuto then 2 else 1.5
		b.BackgroundTransparency = if isSelected then 0 else 0.12
	end
	changed:Fire(slotList(), S.selected, held)
end
local function compact()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	return viewport ~= nil and (viewport.Y < 520 or viewport.X < 700)
end
local function talking()
	local folk = player:FindFirstChild("PlayerGui")
	folk = folk and folk:FindFirstChild("TownsfolkDialogue")
	local box = folk and folk:FindFirstChild("Dialogue")
	return box ~= nil and box.Visible == true
end
local function layout()
	local size = if compact() then STYLE.slotCompact else STYLE.slot
	local width = COUNT * size + (COUNT - 1) * STYLE.gap
	bar.Size = UDim2.fromOffset(width, size)
	bar.Position = UDim2.new(0.5, 0, 1, -STYLE.bottom)
	for i, b in ipairs(S.buttons) do
		b.Size = UDim2.fromOffset(size, size)
		b.Position = UDim2.fromOffset((i - 1) * (size + STYLE.gap), 0)
	end
	nameTag.Position = UDim2.new(0.5, 0, 1, -(STYLE.bottom + size + 6))
	picker.Position = UDim2.new(0.5, 0, 1, -(STYLE.bottom + size + STYLE.reserve + 4))
	local shown = S.loaded and player:GetAttribute("IslandBuilding") ~= true and not talking()
	bar.Visible = shown
	if not shown then picker.Visible = false end
	local height = if shown then STYLE.bottom + size + STYLE.reserve else 0
	if player:GetAttribute("IsleHotbarHeight") ~= height then player:SetAttribute("IsleHotbarHeight", height) end
	if player:GetAttribute("IsleHotbarWidth") ~= width then player:SetAttribute("IsleHotbarWidth", width) end
end

local nameToken = 0
local function showName(id)
	local def = id and Data.Items[id]
	nameToken += 1
	local token = nameToken
	nameTag.Text = if def then def.name else "Empty hands"
	nameTag.TextColor3 = if def and Data.Rarity[def.rarity] then rgb(Data.Rarity[def.rarity].color) else STYLE.ivory
	nameTag.Visible = true
	nameTag.TextTransparency = 0
	task.delay(1.6, function()
		if token ~= nameToken then return end
		TweenService:Create(nameTag, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
	end)
end

------------------------------------------------------------------------------
-- Selection
------------------------------------------------------------------------------
local function select(i)
	if type(i) ~= "number" or i < 1 or i > COUNT or i % 1 ~= 0 then return false end
	S.selected = i
	local id = slotItem(i)
	local want = if id and Held.holdable(id) then id else "none"
	requestHold(want)
	showName(if want == "none" then nil else want)
	paint()
	return true
end
S.select = select

local function assign(slot, id)
	if not table.find(SLOTS, slot) then return false, "Choose hotbar slot 3-9." end
	if id ~= nil and (type(id) ~= "string" or not Data.Items[id]) then return false, "Choose an item for the hotbar." end
	local result = invoke("hotbarSet", slot .. ":" .. (id or ""))
	local message = result and result.message or "The hotbar is busy."
	local ok = result ~= nil and (string.find(message, "set to hotbar", 1, true) ~= nil or string.find(message, "cleared", 1, true) ~= nil)
	if ok and S.selected == slot then select(slot) else paint() end
	return ok, message
end

local pickerSlot = nil
local function openPicker(slot)
	if not table.find(SLOTS, slot) then return end
	pickerSlot = slot
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	pickerTitle.Text = "Hotbar slot " .. slot
	local ids = {}
	for id, n in pairs(S.items) do
		if (tonumber(n) or 0) > 0 and Data.Items[id] then table.insert(ids, id) end
	end
	table.sort(ids, function(a, b)
		local ha, hb = Held.holdable(a), Held.holdable(b)
		if ha ~= hb then return ha end
		return (Data.Items[a].name or a) < (Data.Items[b].name or b)
	end)
	local function row(order, text, colour, onPick)
		local r = make("TextButton", list, {Name = "Row", LayoutOrder = order, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = STYLE.raised,
			BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = STYLE.font, TextSize = 14, TextColor3 = colour, Text = text,
			TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = true})
		make("UICorner", r, {CornerRadius = UDim.new(0, 8)})
		make("UIPadding", r, {PaddingLeft = UDim.new(0, 10)})
		r.Activated:Connect(onPick)
		return r
	end
	row(0, "Clear slot", STYLE.ivory, function() picker.Visible = false; task.spawn(assign, slot, nil) end)
	for index, id in ipairs(ids) do
		if index > 80 then break end
		local def = Data.Items[id]
		local n = tonumber(S.items[id]) or 0
		row(index, glyphFor(def) .. "  " .. (def.name or id) .. (if n > 1 then "  ×" .. n else ""), rgb(def.color), function()
			picker.Visible = false
			task.spawn(assign, slot, id)
		end)
	end
	picker.Visible = true
end
pickerClose.Activated:Connect(function() picker.Visible = false end)

for i, b in ipairs(S.buttons) do
	b.Activated:Connect(function() select(i) end)
	local pressToken = 0
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			openPicker(i)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			pressToken += 1
			local token = pressToken
			task.delay(0.5, function() if token == pressToken then openPicker(i) end end) -- long-press
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then pressToken += 1 end
	end)
end

local KEYS = {[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9}
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not bar.Visible then return end
	local i = KEYS[input.KeyCode]
	if i then select(i) end
end)
-- The wheel cycles only over the bar: elsewhere it keeps zooming the camera.
local hovering = false
bar.MouseEnter:Connect(function() hovering = true end)
bar.MouseLeave:Connect(function() hovering = false end)
UserInputService.InputChanged:Connect(function(input)
	if not hovering or not bar.Visible or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	local step = if input.Position.Z > 0 then -1 else 1
	select((S.selected - 1 + step) % COUNT + 1)
end)

------------------------------------------------------------------------------
-- Inputs from other scripts and the world
------------------------------------------------------------------------------
-- Gather prompts in view set the context tool (slot 2).
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt:GetAttribute("IsleAction") ~= "gather" then return end
	local item = prompt:GetAttribute("IsleItem")
	local skill = type(item) == "string" and Data.ResourceSkill[item]
	if skill and Held.SKILL_CLASS[skill] and skill ~= S.contextSkill then
		S.contextSkill = skill
		paint()
	end
end)

-- Auto switch requests (animate.client.lua): temporary, the server returns it.
local autoHold = ReplicatedStorage:FindFirstChild("IsleHeldAuto") or make("BindableEvent", ReplicatedStorage, {Name = "IsleHeldAuto"})
local autoBusy = false
autoHold.Event:Connect(function(id)
	if not Held.holdable(id) or currentHeld() == id or autoBusy then return end
	autoBusy = true
	task.spawn(function()
		invoke("hold", "~" .. id)
		autoBusy = false
	end)
end)

local api = ReplicatedStorage:FindFirstChild("HotbarApi") or make("BindableFunction", ReplicatedStorage, {Name = "HotbarApi"})
api.OnInvoke = function(method, a, b)
	if method == "assign" then return assign(a, b) end
	if method == "select" then return select(a) end
	if method == "getSlots" then return {slots = slotList(), selected = S.selected, held = currentHeld()} end
	return nil
end

local function onSnapshot(snapshot)
	if type(snapshot) ~= "table" or snapshot.loading then return end
	if type(snapshot.items) == "table" then S.items = snapshot.items end
	local depth = snapshot.depth
	if type(depth) == "table" then
		if type(depth.equipment) == "table" then S.weapon = depth.equipment.weapon end
		if type(depth.tools) == "table" then S.tools = depth.tools end
	end
	if not S.loaded then
		S.loaded = true
		-- Start on the slot showing what the character already holds.
		local held = currentHeld()
		for i = 1, COUNT do
			if held and slotItem(i) == held then S.selected = i; break end
		end
		layout()
	end
	paint()
end
ReplicatedStorage:WaitForChild("IsleUpdate").OnClientEvent:Connect(onSnapshot)
local snapshots = ReplicatedStorage:FindFirstChild("IsleSnapshotLocal")
if snapshots then snapshots.Event:Connect(onSnapshot) end
player:GetAttributeChangedSignal("HeldItem"):Connect(paint)
player:GetAttributeChangedSignal("Hotbar"):Connect(paint)
player:GetAttributeChangedSignal("IslandBuilding"):Connect(layout)
local camera = Workspace.CurrentCamera
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
-- Dialogue opening / closing: a slow poll is enough (no per-frame work).
task.spawn(function()
	while true do
		task.wait(0.5)
		if bar.Visible == talking() and S.loaded then layout() end
	end
end)
layout()
local actions = ReplicatedStorage:FindFirstChild("IsleActionLocal")
if actions then actions:Fire("snapshot") end

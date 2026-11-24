-- Dialogue: talk to the Townsfolk (Data.Townsfolk), the Wayfarer's Path checklist
-- in Pell's Path node, and the NPCs' client-side idle animation (one shared loop).
-- Options open atlas pages (IsleStation/IsleStationVisit, like world stations),
-- set waypoints through the Wayfinder, give tips from the server snapshot, or
-- call an existing IsleAction verb. Nothing here grants anything: the server
-- answers every verb.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local PromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = Data.Townsfolk
-- Colours, fonts and HUD lanes from the shared theme (§29).
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
Theme.useItems(Data.Items) -- §52: shop offers draw the cached vector item icons

local function rgb(h) return Color3.fromHex(h) end
local ink, deep, slate = Theme.color.panel, Theme.color.inset, Theme.color.raised
local ivory, muted, mint, gold = Theme.color.text, Theme.color.dim, Theme.color.mint, Theme.color.gold
local bold, regular, book = Enum.Font.BuilderSansBold, Enum.Font.BuilderSansMedium, Theme.font.display
local function make(class, parent, props)
	local o = Instance.new(class)
	if class == "UIStroke" then o.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r, edge)
	make("UICorner", o, {CornerRadius = UDim.new(0, r)})
	if edge then make("UIStroke", o, {Color = edge, Transparency = 0.35, Thickness = 1}) end
	return o
end

------------------------------------------------------------------------------
-- Snapshot: pushed IsleUpdate events plus a polite "state" read on demand.
------------------------------------------------------------------------------
local action = ReplicatedStorage:WaitForChild("IsleAction")
local snapshot = nil
local lastInput = 0
local listeners = {}
local function accept(data)
	if type(data) ~= "table" or type(data.items) ~= "table" then return false end
	snapshot = data
	for _, f in ipairs(listeners) do task.spawn(f) end
	return true
end
Input.InputBegan:Connect(function() lastInput = os.clock() end)
task.spawn(function()
	ReplicatedStorage:WaitForChild("IsleUpdate").OnClientEvent:Connect(accept)
end)
-- Shares the server's per-player read budget with the atlas, so reads wait for
-- a quiet moment (no input for 1.5 s) instead of colliding with a button press.
local reading = false
local function refresh(force)
	if reading then return snapshot end
	reading = true
	for _ = 1, 4 do
		if force or os.clock() - lastInput > 1.5 then
			local ok, result = pcall(action.InvokeServer, action, "state")
			if ok and accept(result) then break end
		end
		task.wait(0.7)
	end
	reading = false
	return snapshot
end
local function context()
	return {event = workspace:GetAttribute("AetherEvent"), nextEvent = workspace:GetAttribute("AetherNextEvent")}
end

------------------------------------------------------------------------------
-- Interface.
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "TownsfolkDialogue", ResetOnSpawn = false, DisplayOrder = 7,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = false})
local box = make("Frame", gui, {Name = "Dialogue", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -46),
	Size = UDim2.new(1, -20, 0, 260), BackgroundColor3 = ink, BorderSizePixel = 0, Visible = false})
make("UISizeConstraint", box, {MaxSize = Vector2.new(620, 420)})
round(box, 6, gold)
make("UIGradient", box, {Color = ColorSequence.new(ink, deep), Rotation = 90})
local portrait = make("Frame", box, {Name = "Portrait", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = slate, BorderSizePixel = 0})
round(portrait, 32, gold)
local portraitGradient = make("UIGradient", portrait, {Rotation = 120})
local face = make("TextLabel", portrait, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = bold, TextSize = 30, TextColor3 = ivory, Text = ""})
local nameLabel = make("TextLabel", box, {Position = UDim2.fromOffset(86, 12), Size = UDim2.new(1, -140, 0, 24), BackgroundTransparency = 1, Font = book,
	TextSize = 20, TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = ""})
local titleLabel = make("TextLabel", box, {Position = UDim2.fromOffset(86, 36), Size = UDim2.new(1, -140, 0, 18), BackgroundTransparency = 1, Font = bold,
	TextSize = 12, TextColor3 = mint, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = ""})
local closeButton = make("TextButton", box, {Position = UDim2.new(1, -48, 0, 10), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = deep, Text = "✕",
	Font = bold, TextSize = 18, TextColor3 = muted, AutoButtonColor = true})
round(closeButton, 19, slate)
local speech = make("TextButton", box, {Name = "Speech", Position = UDim2.fromOffset(86, 58), Size = UDim2.new(1, -98, 0, 64), BackgroundTransparency = 1,
	Font = regular, TextSize = 15, TextColor3 = ivory, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	AutoButtonColor = false, Text = ""})
local checklist = make("Frame", box, {Name = "Checklist", Position = UDim2.fromOffset(12, 126), Size = UDim2.new(1, -24, 0, 0), BackgroundColor3 = deep,
	BorderSizePixel = 0, Visible = false})
round(checklist, 8, slate)
make("UIListLayout", checklist, {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder})
make("UIPadding", checklist, {PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 8)})
local optionsFrame = make("ScrollingFrame", box, {Name = "Options", Position = UDim2.fromOffset(12, 130), Size = UDim2.new(1, -24, 1, -142),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = gold, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", optionsFrame, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})

-- Toast for dialogue-side notices (arrivals are the Wayfinder's).
local toast = make("TextLabel", gui, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.fromOffset(420, 36),
	BackgroundColor3 = deep, BackgroundTransparency = 0.1, TextColor3 = gold, Font = bold, TextSize = 14, TextWrapped = true, Visible = false, Text = ""})
make("UISizeConstraint", toast, {MaxSize = Vector2.new(420, 60)})
round(toast, 9, gold)
local toastSeq = 0
local function notify(text)
	toastSeq += 1
	local mine = toastSeq
	toast.Text, toast.Visible = text, true
	task.delay(3.5, function() if toastSeq == mine then toast.Visible = false end end)
end

------------------------------------------------------------------------------
-- Conversation state.
------------------------------------------------------------------------------
local talking = nil -- {role, def, model, node}
local busy = false
local typeToken = 0
local function typeText(text)
	typeToken += 1
	local token = typeToken
	speech.Text = text
	speech.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown, total = 0, utf8.len(text) or #text
		while token == typeToken and shown < total do
			shown = math.min(total, shown + 2)
			speech.MaxVisibleGraphemes = shown
			task.wait(1 / 45)
		end
		if token == typeToken then speech.MaxVisibleGraphemes = -1 end
	end)
end
speech.Activated:Connect(function() typeToken += 1; speech.MaxVisibleGraphemes = -1 end)

local function stationVisit(station)
	-- Same attributes the world stations set. A local negative visit number never
	-- collides with the server's positive counter, and IsleStation is restored so a
	-- later world visit (which may not re-replicate an unchanged value) opens its own page.
	local previous = player:GetAttribute("IsleStation")
	local tag = station .. ":npc" .. os.clock()
	player:SetAttribute("IsleStation", tag)
	player:SetAttribute("IsleStationVisit", -math.floor(os.clock() * 1000))
	task.delay(1.5, function()
		if player:GetAttribute("IsleStation") == tag then player:SetAttribute("IsleStation", previous) end
	end)
end
local function requestWaypoint(specs, label)
	local hub = player:FindFirstChild("WayfinderRequest") or player:WaitForChild("WayfinderRequest", 5)
	if not hub then notify("Your map is still unfolding. Try again in a moment."); return false end
	hub:Fire(specs, label)
	return true
end

local closeDialogue
local showNode
local function optionButton(text, order, onClick, accent)
	-- Long labels (regional quests, shop offers) wrap onto a second line; the
	-- button grows to fit (36 px minimum) and the options list scrolls.
	local b = make("TextButton", optionsFrame, {LayoutOrder = order, Size = UDim2.new(1, -6, 0, 36), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if accent then slate else deep, Text = text, Font = bold, TextSize = 14, TextColor3 = if accent then gold else ivory,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, AutoButtonColor = true})
	make("UIPadding", b, {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6)})
	round(b, 8, if accent then gold else slate)
	b.Activated:Connect(function() if not busy then onClick() end end)
	return b
end
-- §33 per-player daily stock on a regional shop offer: "8/64 left today"
-- (snapshot.systems.stock.left[Stock.key("rq", role, item)] = {left, limit}; the key is per item
-- across every shop, §33 QC M2); nil when unlimited.
local function stockOf(option)
	local role, index = string.match(option.item or "", "^(%w+):(%d+)$")
	local folk = role and Data.RegionArt and Data.RegionArt.FolkByRole[role]
	local offer = folk and folk.shop and folk.shop[tonumber(index)]
	local systems = snapshot and type(snapshot.systems) == "table" and snapshot.systems
	local stock = systems and type(systems.stock) == "table" and type(systems.stock.left) == "table" and systems.stock.left
	local entry = offer and stock and Data.Systems and stock[Data.Systems.Stock.key("rq", role, offer.item)]
	if type(entry) ~= "table" or type(entry[1]) ~= "number" or type(entry[2]) ~= "number" then return nil end
	return entry[1], entry[2], offer
end
local function stockLeft(option)
	local left, limit = stockOf(option)
	if not left then return nil end
	return if left > 0 then left .. "/" .. limit .. " left today" else "sold out today"
end
-- Lots still allowed today for an offer (MAX_LOTS when unlimited); caps the picker.
local function lotsLeft(option)
	local left, _, offer = stockOf(option)
	if not left then return Data.Features.Shop.MAX_LOTS end
	return math.max(1, math.floor(left / math.max(1, offer.amount)))
end
-- §31 shop quantities: right-click or long-press a shop offer for the quantity
-- picker (features.client.lua on IsleQuantityLocal; verb rqBuy "Role:i:qty").
local quantitySuppress = setmetatable({}, {__mode = "k"}) -- a long-press must not also buy one
local function quantityHook(b, option)
	local role, index = string.match(option.item or "", "^(%w+):(%d+)$")
	local folk = role and Data.RegionArt and Data.RegionArt.FolkByRole[role]
	local offer = folk and folk.shop and folk.shop[tonumber(index)]
	if not offer then return end
	-- Warp scrolls and one-of-a-kind wares are bought one at a time: no picker.
	if Data.Features and Data.Features.Shop.singleLot(offer.item) then return end
	local item = Data.Items[offer.item]
	local function open()
		local event = ReplicatedStorage:FindFirstChild("IsleQuantityLocal")
		if not event then return end
		local coins = snapshot and tonumber(snapshot.coins) or 0
		event:Fire({verb = "rqBuy", base = option.item, item = offer.item, name = item and item.name or offer.item, unit = offer.price, amount = offer.amount,
			max = math.max(1, math.min(Data.Features.Shop.MAX_LOTS, math.floor(coins / math.max(1, offer.price)), lotsLeft(option)))})
	end
	b.MouseButton2Click:Connect(open)
	local pressedAt
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local stamp = os.clock()
			pressedAt = stamp
			task.delay(0.55, function() if pressedAt == stamp then pressedAt = nil; quantitySuppress[option] = os.clock(); open() end end)
		end
	end)
	b.InputEnded:Connect(function() pressedAt = nil end)
end
local function clearOptions()
	for _, c in ipairs(optionsFrame:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
end
-- Placement (shared HUD map in combat.client.lua): the box sits above the atlas
-- action bar (bottom at H-46), never above y 100 (the atlas guild badge), left of
-- the minimap column when it reaches that high and, on touch screens, left of the
-- Attack button. Its height is clamped to that space and the options scroll, so
-- the portrait, name and close button are always on screen. Short screens (phone
-- landscape) use a compact header and leave the checklist to the tracker.
local DIALOGUE_TOP, DIALOGUE_FLOOR = 100, 46
-- HUD lanes (Theme.hudLayout): the dialogue stays above the action bar and
-- clear of the minimap (top-left) and the sidebar (top-right).
local function lanes()
	local view = gui.AbsoluteSize
	if not view or view.X <= 0 or view.Y <= 0 then
		local camera = workspace.CurrentCamera
		view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return Theme.hudLayout(view.X, view.Y, {touch = Input.TouchEnabled})
end
local function screenSize()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end
local function isCompact()
	local L = lanes()
	return L.action.y - 6 - (math.max(L.mapBlock.y + L.mapBlock.h, L.sidebar.y + L.sidebar.h) + 8) < 240
end
local function metrics(compact)
	local textX = if compact then 58 else 86
	local portraitSize = if compact then 40 else 64
	portrait.Position, portrait.Size = UDim2.fromOffset(if compact then 10 else 12, if compact then 8 else 12), UDim2.fromOffset(portraitSize, portraitSize)
	face.TextSize = if compact then 20 else 30
	nameLabel.Position, nameLabel.Size = UDim2.fromOffset(textX, if compact then 6 else 12), UDim2.new(1, -textX - 54, 0, 24)
	titleLabel.Position, titleLabel.Size = UDim2.fromOffset(textX, if compact then 28 else 36), UDim2.new(1, -textX - 54, 0, 18)
	closeButton.Position = UDim2.new(1, if compact then -44 else -48, 0, if compact then 6 else 10)
	closeButton.Size = UDim2.fromOffset(if compact then 34 else 38, if compact then 34 else 38)
	if compact then
		speech.Position, speech.Size, speech.TextSize = UDim2.fromOffset(12, 52), UDim2.new(1, -24, 0, 44), 13
	else
		speech.Position, speech.Size, speech.TextSize = UDim2.fromOffset(86, 58), UDim2.new(1, -98, 0, 64), 15
	end
	return if compact then 100 else 126
end
local function placeBox(desired)
	local L = lanes()
	local width = L.w
	local bottom = L.action.y - 6
	local clear = math.max(L.mapBlock.y + L.mapBlock.h, L.sidebar.y + L.sidebar.h) + 8
	local top, x, w
	if bottom - clear >= math.min(desired, 240) then
		-- Tall screens: centred under the top HUD row.
		top = math.max(clear, bottom - desired)
		w = math.min(620, width - 20)
		x = math.floor(width / 2 - w / 2)
	else
		-- Short screens: the top lane between the minimap and the sidebar.
		top = math.max(8, bottom - desired)
		w = math.min(620, L.lane.right - L.lane.left)
		x = L.lane.left + math.floor((L.lane.right - L.lane.left - w) / 2)
	end
	box.AnchorPoint, box.Position, box.Size = Vector2.new(0, 1), UDim2.fromOffset(x, bottom), UDim2.fromOffset(w, bottom - top)
	return bottom - top
end
local function layout(lines)
	local rows = math.min(lines, 5)
	local headTop = metrics(isCompact())
	local listHeight = checklist.Visible and checklist.Size.Y.Offset + 6 or 0
	checklist.Position = UDim2.fromOffset(12, headTop)
	local optionsTop = headTop + 4 + listHeight
	local height = placeBox(optionsTop + 12 + rows * 42)
	optionsFrame.Position = UDim2.fromOffset(12, optionsTop)
	optionsFrame.Size = UDim2.new(1, -24, 0, math.max(0, height - optionsTop - 8))
end
local function drawChecklist(show)
	for _, c in ipairs(checklist:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	-- Short screens: the tracker card carries the checklist; keep room for options.
	if show and isCompact() then show = false end
	checklist.Visible = show
	if not show then checklist.Size = UDim2.new(1, -24, 0, 0); return end
	-- Polish: the Wayfarer's Path checklist (the retired 6-step tutorial is gone).
	local G = Data.Features.Guide
	local g = type(snapshot) == "table" and type(snapshot.guide) == "table" and snapshot.guide or {}
	local marks = if type(g.marks) == "string" then g.marks else ""
	for i, step in ipairs(G.Steps) do
		local done = string.sub(marks, i, i) == "1" or g.complete == true
		local current = not g.complete and g.id == step.id
		local mark = if done then "✓" elseif current then "➤" else "•"
		make("TextLabel", checklist, {LayoutOrder = i, Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = if current then bold else regular,
			TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if done then mint elseif current then gold else muted,
			Text = mark .. "  " .. i .. ". " .. step.title})
	end
	checklist.Size = UDim2.new(1, -24, 0, #G.Steps * 15 + 8)
end
-- A reply (tip or verb result) with Back / Farewell.
local function reply(text)
	if not talking then return end
	drawChecklist(false)
	clearOptions()
	typeText(text)
	local node = talking.node
	optionButton("Back", 1, function() showNode(node) end)
	optionButton("Farewell", 2, function() closeDialogue() end)
	layout(2)
end
local function runOption(option)
	if option.to then showNode(option.to)
	elseif option.close then closeDialogue()
	elseif option.atlas then
		closeDialogue()
		stationVisit(option.atlas)
	elseif option.waypoint then
		local specs, label = option.waypoint, nil
		if specs == "path" then
			-- Polish: the Wayfarer's Path step's waypoint (Data.Features.Guide.Waypoints).
			local step = T.pathStep(snapshot)
			if not step then reply("You've walked the whole Wayfarer's Path! Ask me what to do next any time."); return end
			if not step.waypoint then reply(step.title .. ": " .. step.detail .. " No walking needed for this one."); return end
			specs, label = step.waypoint, step.title
		end
		if requestWaypoint(specs, label) then
			closeDialogue()
			notify("Follow the golden beam. Your map marks the way.")
		end
	elseif option.tip then
		busy = true
		typeText("Hmm, let me think…")
		refresh(true)
		busy = false
		local tip = T.Tips[option.tip]
		local ok, text = pcall(tip, snapshot, context())
		reply(if ok and type(text) == "string" then text else "I can't quite recall. Ask me again in a moment.")
	elseif option.verb then
		busy = true
		typeText("…")
		local ok, result = pcall(action.InvokeServer, action, option.verb, option.item)
		busy = false
		if ok and type(result) == "table" then
			accept(result)
			local message = if type(result.message) == "string" and result.message ~= "" then result.message else "Done."
			if option.verb == "recall" and string.sub(message, 1, 8) == "Recalled" then closeDialogue(); notify(message); return end
			reply(message)
		else
			reply("The ledger is busy. Try that again in a moment.")
		end
	end
end
-- Dialogue options that sell something (regional shops, warp scrolls, skill vendors, pets).
local SHOP_VERBS = {rqBuy = true, warpBuy = true, skillBuy = true, petShop = true, shop = true}
showNode = function(nodeId)
	if not talking then return end
	local node = talking.def.nodes[nodeId]
	if not node then closeDialogue(); return end
	talking.node = nodeId
	if node.path then refresh(true) end
	if not talking then return end
	local text = node.text
	if node.path then
		local step = T.pathStep(snapshot)
		text = if step then text .. "\n➤ " .. step.title .. ": " .. step.detail else "You've walked the whole Wayfarer's Path. The isles are yours to explore!"
	end
	drawChecklist(node.path == true)
	typeText(text)
	clearOptions()
	local options = T.visibleOptions(node, snapshot, context())
	local shop = false
	for i, option in ipairs(options) do
		if SHOP_VERBS[option.verb] then shop = true end
		local b = optionButton(option.label, i, function()
			local held = quantitySuppress[option]
			quantitySuppress[option] = nil
			if held and os.clock() - held < 1.5 then return end
			runOption(option)
		end, option.verb ~= nil or option.waypoint ~= nil)
		if option.verb == "rqBuy" then
			quantityHook(b, option)
			local stock = stockLeft(option)
			if stock then b.Text = option.label .. "   ·   " .. stock end -- §33 per-player daily stock
			-- §52: the offer's item icon (the cached vector icon) at the button's right.
			local role, index = string.match(option.item or "", "^(%w+):(%d+)$")
			local folk = role and Data.RegionArt and Data.RegionArt.FolkByRole[role]
			local offer = folk and folk.shop and folk.shop[tonumber(index)]
			local itemDef = offer and Data.Items[offer.item]
			if itemDef then
				local icon = Theme.icon(b, itemDef, 30)
				icon.AnchorPoint, icon.Position = Vector2.new(1, 0.5), UDim2.new(1, 2, 0.5, 0)
				local pad = b:FindFirstChildOfClass("UIPadding")
				if pad then pad.PaddingRight = UDim.new(0, 40) end
			end
		end
	end
	layout(#options)
	-- §43 QC M1: a priced offer on screen is the tutorial's first-shop encounter.
	if shop then
		local channel = ReplicatedStorage:FindFirstChild("IsleTutorialLocal")
		if channel then pcall(function() channel:Fire("shop") end) end
	end
end
local trackerSync -- (retired with the tutorial tracker; kept nil)
closeDialogue = function()
	talking = nil
	typeToken += 1
	box.Visible = false
	clearOptions()
	if trackerSync then trackerSync() end
end
closeButton.Activated:Connect(function() closeDialogue() end)
local function openDialogue(role, model)
	local def = T.NPCs[role]
	if not def then return end
	talking = {role = role, def = def, model = model}
	nameLabel.Text, titleLabel.Text, face.Text = def.name, def.title, def.portrait or string.sub(def.name, 1, 1)
	portraitGradient.Color = ColorSequence.new(rgb(def.look.shirt), rgb(def.look.accent))
	box.Visible = true
	if trackerSync then trackerSync() end
	if not snapshot then
		typeText("…")
		clearOptions()
		layout(0)
		refresh(true)
	end
	if talking and talking.role == role then showNode(def.start) end
end
PromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local role = prompt:GetAttribute("TownsfolkRole")
	if type(role) ~= "string" or not T.NPCs[role] then return end
	openDialogue(role, prompt:FindFirstAncestorOfClass("Model"))
end)
Input.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and talking then closeDialogue() end
end)

------------------------------------------------------------------------------
-- Polish: the old tutorial tracker is retired (the Wayfarer's Path shows in the
-- sidebar Objective and Menu › Renown). The open Path checklist follows snapshots.
------------------------------------------------------------------------------
local function placeToast()
	toast.Position = UDim2.new(0.5, 0, 1, -lanes().toastBottom)
end
placeToast()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeToast)
table.insert(listeners, function()
	if talking and box.Visible then
		local node = talking.def.nodes[talking.node or ""]
		if node and node.path then drawChecklist(true) end
	end
end)

------------------------------------------------------------------------------
-- NPC registry, quest markers, forged outfits (§52) and the single idle loop.
------------------------------------------------------------------------------
-- §52: every townsperson wears forged outfit pieces (shared/NpcStyle.lua →
-- art/OutfitCatalog.lua through the MeshForge outfit API) and plays their
-- trade's idle loop. Only the nearest NPCs are dressed (Style.DRESS_CAP within
-- Style.DRESS_RANGE; phones fewer); the server's primitive hat / prop / cape /
-- apron parts are the fallback and are hidden locally (LocalTransparencyModifier)
-- only while the matching mesh exists. Player characters are never touched
-- (animate.client.lua owns them); NPC motors are written through C0 here and the
-- talk nod (animate.client.lua) through the Neck's Transform, so they compose.
local Style = require(ReplicatedStorage:WaitForChild("AetherNpcStyle"))
local npcs = {} -- [model] = {role, root, head, motors={joint={motor, base}}, marker, phase, yaw, pitch, outfit, pose, ...}
local function isPhone()
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y < 500
end
local function register(model)
	local role = model:GetAttribute("TownsfolkRole")
	if type(role) ~= "string" or npcs[model] then return end
	local root = model:WaitForChild("HumanoidRootPart", 10)
	local head = model:WaitForChild("Head", 10)
	if not root or not head or not model.Parent then return end
	local def = T.NPCs[role]
	local outfit = Style.outfit(role, def)
	local entry = {role = role, root = root, head = head, motors = {}, phase = (#model.Name % 7) * 0.9, yaw = 0, pitch = 0, attention = 0,
		outfit = outfit, idle = model:GetAttribute("NpcIdle") or outfit.idle, pose = {}, lastBeat = -1,
		dressed = false, dressing = false, retryAt = 0, tokens = {}, hidden = {}, fx = nil, distance = math.huge}
	for joint, name in pairs(Style.MOTORS) do
		local m = model:FindFirstChild(name, true)
		if m and m:IsA("Motor6D") then entry.motors[joint] = {motor = m, base = m.C0} end
	end
	local marker = make("BillboardGui", head, {Name = "TownsfolkMarker", Size = UDim2.fromOffset(34, 34), StudsOffset = Vector3.new(0, 4.4, 0),
		AlwaysOnTop = false, MaxDistance = 120, LightInfluence = 0, Enabled = false})
	local bubble = make("TextLabel", marker, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = gold, Text = "!", Font = bold, TextSize = 22, TextColor3 = deep})
	round(bubble, 17, deep)
	entry.marker, entry.bubble = marker, bubble
	-- A "CLICK" cue under the server nameplate (SkyBlock-style vendor hologram,
	-- §29 theme), shown only up close; it follows the plate's lift over tall hats.
	local plate = head:FindFirstChild("Nameplate")
	local lift = if plate and plate:IsA("BillboardGui") then plate.StudsOffset.Y else 2.4
	local tag = make("BillboardGui", head, {Name = "TownsfolkClick", Size = UDim2.fromOffset(90, 16), StudsOffset = Vector3.new(0, lift - 1.3, 0),
		AlwaysOnTop = false, MaxDistance = 36, LightInfluence = 0})
	make("TextLabel", tag, {Name = "Click", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "CLICK", Font = Theme.font.display, TextSize = 10,
		TextColor3 = Theme.rgb("FFE066"), TextStrokeTransparency = 0.3, TextStrokeColor3 = Theme.color.void})
	entry.tag = tag
	npcs[model] = entry
end

-- Outfits ---------------------------------------------------------------------
local forgeApi = nil
local function forge()
	forgeApi = forgeApi or ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	return forgeApi
end
local function hideSlot(model, entry, slot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("OutfitSlot") == slot and not entry.hidden[d] then
			entry.hidden[d] = true
			d.LocalTransparencyModifier = 1
		end
	end
end
local function undress(entry)
	local api = forge()
	for _, token in ipairs(entry.tokens) do if api then pcall(api.Invoke, api, "outfitRelease", token) end end
	table.clear(entry.tokens)
	for part in pairs(entry.hidden) do if part.Parent then part.LocalTransparencyModifier = 0 end end
	table.clear(entry.hidden)
	entry.fx = nil
	entry.dressed = false
end
local function dress(model, entry)
	local api = forge()
	if not api or entry.dressing then return end
	entry.dressing = true
	local missing = false
	for _, piece in ipairs(entry.outfit.pieces) do
		local bone = model:FindFirstChild(piece.bone)
		if not bone or not entry.dressing then missing = true; continue end
		local ok, clone, token, extent, centre = pcall(api.Invoke, api, "outfit", {shape = piece.shape, tint = if piece.dye then Color3.fromHex(piece.dye) else nil})
		if not ok or not clone then missing = true; continue end
		if not entry.dressing or not model.Parent then pcall(api.Invoke, api, "outfitRelease", token); missing = true; continue end
		table.insert(entry.tokens, token)
		local k = piece.k or 1
		clone.Size = extent * k
		clone.Anchored, clone.Massless, clone.CanCollide, clone.CanQuery, clone.CanTouch, clone.CastShadow = false, true, false, false, false, true
		local offset = CFrame.new(piece.at[1], piece.at[2], piece.at[3]) * CFrame.Angles(piece.rot[1], piece.rot[2], piece.rot[3]) * CFrame.new(centre * k)
		clone.CFrame = bone.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0, weld.Part1, weld.C0 = bone, clone, offset
		weld.Parent = clone
		clone.Parent = model
		hideSlot(model, entry, piece.slot)
		if piece.slot == "hat" then hideSlot(model, entry, "hair") end
		if piece.slot == "held" then entry.fx = clone end
	end
	entry.dressing = false
	entry.dressed = true
	if missing then entry.retryAt = os.clock() + 8 end
end
-- Every 0.5 s: the nearest NPCs within range are dressed (cap per device).
local dressOrder, keep = {}, {}
task.spawn(function()
	while true do
		task.wait(0.5)
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local phone = isPhone()
		local range = if phone then Style.DRESS_RANGE.phone else Style.DRESS_RANGE.desktop
		local cap = if phone then Style.DRESS_CAP.phone else Style.DRESS_CAP.desktop
		table.clear(dressOrder)
		table.clear(keep)
		for model, entry in pairs(npcs) do
			if not model.Parent then continue end
			entry.distance = if rootPart then (rootPart.Position - entry.root.Position).Magnitude else math.huge
			-- Hysteresis: a dressed NPC keeps its outfit until 15% past the range.
			if entry.distance <= range * (if entry.dressed then 1.15 else 1) then table.insert(dressOrder, entry) end
		end
		table.sort(dressOrder, function(a, b) return a.distance < b.distance end)
		for i, entry in ipairs(dressOrder) do if i <= cap then keep[entry] = true end end
		for model, entry in pairs(npcs) do
			if keep[entry] then
				if not entry.dressed and not entry.dressing then task.spawn(dress, model, entry)
				elseif entry.dressed and entry.retryAt > 0 and os.clock() >= entry.retryAt then
					-- A piece was refused (pool full): try the whole outfit again.
					entry.retryAt = 0
					undress(entry)
					task.spawn(dress, model, entry)
				end
			elseif entry.dressed then
				entry.dressing = false
				undress(entry)
			end
		end
	end
end)

-- Prop beat FX (smith sparks, tinker sparks, beaconkeeper embers): one emitter per prop.
local BEAT_FX = {hammer = Color3.fromRGB(255, 196, 90), tinker = Color3.fromRGB(255, 220, 140), poke = Color3.fromRGB(255, 120, 50)}
local function beat(entry, reduced)
	local color = BEAT_FX[entry.idle]
	local prop = entry.fx
	if not color or reduced or not prop or not prop.Parent then return end
	local emitter = prop:FindFirstChild("BeatSparks")
	if not emitter then
		emitter = make("ParticleEmitter", prop, {Name = "BeatSparks", Enabled = false, Rate = 0, Lifetime = NumberRange.new(0.18, 0.4),
			Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(60, 60), LightEmission = 1, Size = NumberSequence.new(0.12, 0),
			Color = ColorSequence.new(color), Acceleration = Vector3.new(0, -24, 0)})
	end
	emitter:Emit(if isPhone() then 3 else 7)
end

local function updateMarkers()
	local s, ctx = snapshot, context()
	for _, entry in pairs(npcs) do
		local show = false
		-- World Art regional folk (§30): "!" quest on offer, gold "?" ready to hand
		-- in, grey "?" in progress, "…" someone sent you to talk to them.
		local RA = Data.RegionArt
		if s and RA and RA.FolkByRole[entry.role] then
			local state = RA.marker(s, entry.role)
			show = state ~= nil
			entry.bubble.Text = if state == "offer" then "!" elseif state == "talk" then "…" else "?"
			entry.bubble.BackgroundColor3 = if state == "active" then muted else gold
			entry.marker.Enabled = show
			continue
		end
		if s then
			if entry.role == "Guide" then show = T.Conditions.guideModeActive(s) or T.Conditions.guideTalkActive(s) or T.Conditions.guideRewardReady(s) or T.Conditions.contractReady(s)
			elseif entry.role == "Slayer" then show = T.Conditions.huntReady(s)
			elseif entry.role == "Herald" then show = T.Conditions.eventActive(s, ctx)
			end
		end
		entry.marker.Enabled = show
	end
end
table.insert(listeners, updateMarkers)
workspace:GetAttributeChangedSignal("AetherEvent"):Connect(updateMarkers)
task.spawn(function()
	local folder = workspace:WaitForChild("Townsfolk")
	folder.ChildAdded:Connect(function(m) task.spawn(register, m); task.delay(0.5, updateMarkers) end)
	folder.ChildRemoved:Connect(function(m)
		local entry = npcs[m]
		if entry then entry.dressing = false; undress(entry) end
		npcs[m] = nil
		if talking and talking.model == m then closeDialogue() end
	end)
	for _, m in ipairs(folder:GetChildren()) do task.spawn(register, m) end
	task.delay(1, updateMarkers)
end)

local LOOK_RANGE, ANIM_STEP = 20, 1 / 30
local accumulator, frame = 0, 0
local rad = math.rad
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < ANIM_STEP then return end
	local step = accumulator
	accumulator = 0
	frame += 1
	local character = player.Character
	local myHead = character and character:FindFirstChild("Head")
	local myPos = myHead and myHead.Position
	local now = os.clock()
	local phone = isPhone()
	local reduced = Theme.reducedMotion(player)
	for model, entry in pairs(npcs) do
		if not model.Parent then npcs[model] = nil; continue end
		local rootPos = entry.root.Position
		local distance = if myPos then (myPos - rootPos).Magnitude else math.huge
		local focused = talking ~= nil and talking.model == model
		local lod = if focused then 2 else Style.lod(distance, phone)
		if lod == 0 or distance > T.IDLE_RANGE then continue end
		-- Half rate at mid range: even frames only.
		if lod == 1 and frame % 2 == 1 then continue end
		local t = now + entry.phase
		-- Look-at: yaw/pitch toward the player's head, eased; neutral when far.
		local yaw, pitch, want = 0, 0, 0
		if myPos and (distance < LOOK_RANGE or focused) then
			local rel = entry.root.CFrame:PointToObjectSpace(myPos)
			yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.0, 1.0)
			pitch = math.clamp(math.atan2(rel.Y - 2.4, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.35, 0.35)
			want = 1
		end
		local ease = math.min(1, step * (if lod == 1 then 10 else 5))
		entry.yaw += (yaw - entry.yaw) * ease
		entry.pitch += (pitch - entry.pitch) * ease
		entry.attention += (want - entry.attention) * ease
		-- Trade idle loop (§52): calmer while the player is near or talking (the
		-- NPC pays attention) and under reduced motion.
		local pose = Style.sample(entry.idle, t, entry.pose, reduced)
		local loop = Style.IDLES[entry.idle]
		if loop and loop.beat then
			local phase = t % loop.period
			local crossed = entry.lastBeat >= 0 and entry.lastBeat < loop.beat and phase >= loop.beat
			entry.lastBeat = phase
			if crossed and entry.dressed and distance < 40 and not focused then beat(entry, reduced) end
		end
		local calm = 1 - 0.55 * entry.attention * (if focused then 1 else 0.6)
		local talk = if focused and not reduced then math.sin(t * 6) * 4 else 0
		for joint, slot in pairs(entry.motors) do
			local v = pose[joint]
			local rx, ry, rz = 0, 0, 0
			if v then rx, ry, rz = v[1] * calm, v[2] * calm, v[3] * calm end
			if joint == "neck" then
				slot.motor.C0 = slot.base * CFrame.Angles(rad(rx) + entry.pitch * entry.attention, rad(ry) + entry.yaw * 0.7, rad(rz))
			elseif joint == "waist" then
				slot.motor.C0 = slot.base * CFrame.Angles(rad(rx), rad(ry) + entry.yaw * 0.3 * entry.attention, rad(rz))
			elseif joint == "leftArm" then
				slot.motor.C0 = slot.base * CFrame.Angles(rad(rx + talk), rad(ry), rad(rz))
			else
				slot.motor.C0 = slot.base * CFrame.Angles(rad(rx), rad(ry), rad(rz))
			end
		end
		if focused and distance > 24 then closeDialogue() end
	end
end)

-- (Polish: the tutorial tracker's poll loop retired with the tracker; one refresh at start.)
task.spawn(function() refresh(false) end)

-- Dialogue: talk to the Townsfolk (Data.Townsfolk), the new-player tutorial
-- tracker, and the NPCs' client-side idle animation (one shared loop).
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
-- (snapshot.systems.stock.left["rq:<role>:<item>"] = {left, limit}); nil when unlimited.
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
	local state = T.tutorialState(snapshot)
	for i, step in ipairs(state.steps) do
		local current = state.current == i
		local mark = if step.done then "✓" elseif current then "➤" else "•"
		local detail = if step.need > 1 and not step.done then "  (" .. step.have .. "/" .. step.need .. ")" else ""
		make("TextLabel", checklist, {LayoutOrder = i, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = if current then bold else regular,
			TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if step.done then mint elseif current then gold else muted,
			Text = mark .. "  " .. i .. ". " .. step.title .. detail})
	end
	checklist.Size = UDim2.new(1, -24, 0, #state.steps * 20 + 8)
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
		if specs == "tutorial" then
			local state = T.tutorialState(snapshot)
			local step = state.current and T.Tutorial[state.current]
			if not step then reply("You've finished the basics! Ask me what to do next any time."); return end
			if not step.waypoint then
				reply(step.text .. (if step.atlas then "" else " No walking needed for this one."))
				return
			end
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
showNode = function(nodeId)
	if not talking then return end
	local node = talking.def.nodes[nodeId]
	if not node then closeDialogue(); return end
	talking.node = nodeId
	if node.tutorial then refresh(true) end
	if not talking then return end
	local text = node.text
	if node.tutorial then
		local state = T.tutorialState(snapshot)
		local step = state.current and T.Tutorial[state.current]
		text = if step then text .. "\n➤ " .. step.text else "You've mastered the basics, wayfarer. The isles are yours to explore!"
	end
	drawChecklist(node.tutorial == true)
	typeText(text)
	clearOptions()
	local options = T.visibleOptions(node, snapshot, context())
	for i, option in ipairs(options) do
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
		end
	end
	layout(#options)
end
local trackerSync -- the tutorial tracker hides while a dialogue is open
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
-- Tutorial tracker (left column under the atlas guild badge: x 10-260, y 100-166).
------------------------------------------------------------------------------
local tracker = make("Frame", gui, {Name = "TutorialTracker", Position = UDim2.fromOffset(10, 234), Size = UDim2.fromOffset(250, 66),
	BackgroundColor3 = deep, BackgroundTransparency = 0.08, BorderSizePixel = 0, Visible = false})
round(tracker, 6, gold)
local trackerTitle = make("TextLabel", tracker, {Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -40, 0, 16), BackgroundTransparency = 1, Font = bold,
	TextSize = 11, TextColor3 = mint, TextXAlignment = Enum.TextXAlignment.Left, Text = "FIRST STEPS"})
local trackerStep = make("TextLabel", tracker, {Position = UDim2.fromOffset(10, 21), Size = UDim2.new(1, -20, 0, 18), BackgroundTransparency = 1, Font = bold,
	TextSize = 14, TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = ""})
local trackerBar = make("Frame", tracker, {Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -100, 0, 8), BackgroundColor3 = rgb("0B1E29"), BorderSizePixel = 0})
round(trackerBar, 4)
local trackerFill = make("Frame", trackerBar, {Size = UDim2.fromScale(0, 1), BackgroundColor3 = mint, BorderSizePixel = 0})
round(trackerFill, 4)
local trackerGo = make("TextButton", tracker, {Position = UDim2.new(1, -84, 0, 36), Size = UDim2.fromOffset(74, 26), BackgroundColor3 = slate, Text = "Show me",
	Font = bold, TextSize = 13, TextColor3 = gold, AutoButtonColor = true})
round(trackerGo, 7, gold)
local trackerHide = make("TextButton", tracker, {Position = UDim2.new(1, -28, 0, 4), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Text = "–",
	Font = bold, TextSize = 16, TextColor3 = muted})
local trackerHidden, lastStep = false, nil
-- Left column under the minimap (Theme.hudLayout leftTop); the toast above the hotbar band.
local function placeTracker()
	local L = lanes()
	tracker.Position = UDim2.fromOffset(10, L.leftTop)
	tracker.Size = UDim2.fromOffset(if L.short then 184 else 250, 66)
	toast.Position = UDim2.new(0.5, 0, 1, -L.toastBottom)
end
placeTracker()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTracker)
local function updateTracker()
	local state = T.tutorialState(snapshot)
	local visible = not trackerHidden and not state.loading and not state.complete and not talking
	tracker.Visible = visible
	if state.loading then return end
	if lastStep and state.current ~= lastStep and lastStep <= #T.Tutorial then
		local finished = T.Tutorial[lastStep]
		notify(if state.complete then "Tutorial complete! Pell has more advice whenever you need it." else "✓ " .. finished.title .. " — next: " .. T.Tutorial[state.current].title)
	end
	lastStep = state.current or (#T.Tutorial + 1)
	if not visible then return end
	local step = T.Tutorial[state.current]
	trackerTitle.Text = "FIRST STEPS · " .. state.done .. "/" .. state.total
	trackerStep.Text = step.title .. (if state.steps[state.current].need > 1 then " (" .. state.steps[state.current].have .. "/" .. state.steps[state.current].need .. ")" else "")
	TweenService:Create(trackerFill, TweenInfo.new(0.3), {Size = UDim2.fromScale(state.done / state.total, 1)}):Play()
	trackerGo.Text = if step.waypoint then "Show me" elseif step.atlas then "Open" else "How?"
end
trackerGo.Activated:Connect(function()
	local state = T.tutorialState(snapshot)
	local step = state.current and T.Tutorial[state.current]
	if not step then return end
	if step.waypoint then
		if requestWaypoint(step.waypoint, step.title) then notify(step.text) end
	elseif step.atlas then stationVisit(step.atlas)
	else notify(step.text) end
end)
trackerHide.Activated:Connect(function() trackerHidden = true; tracker.Visible = false; notify("Tutorial hidden. Talk to Pell to see it again.") end)
table.insert(listeners, updateTracker)
trackerSync = updateTracker
table.insert(listeners, function()
	if talking and box.Visible then
		local node = talking.def.nodes[talking.node or ""]
		if node and node.tutorial then drawChecklist(true) end
	end
end)

------------------------------------------------------------------------------
-- NPC registry, quest markers and the single idle loop.
------------------------------------------------------------------------------
local npcs = {} -- [model] = {role, root, head, motors={name={motor, base}}, marker, phase, yaw, pitch}
local function register(model)
	local role = model:GetAttribute("TownsfolkRole")
	if type(role) ~= "string" or npcs[model] then return end
	local root = model:WaitForChild("HumanoidRootPart", 10)
	local head = model:WaitForChild("Head", 10)
	if not root or not head or not model.Parent then return end
	local entry = {role = role, root = root, head = head, motors = {}, phase = (#model.Name % 7) * 0.9, yaw = 0, pitch = 0}
	for _, name in ipairs({"Neck", "Waist", "LeftShoulder", "RightShoulder"}) do
		local m = model:FindFirstChild(name, true)
		if m and m:IsA("Motor6D") then entry.motors[name] = {motor = m, base = m.C0} end
	end
	local marker = make("BillboardGui", head, {Name = "TownsfolkMarker", Size = UDim2.fromOffset(34, 34), StudsOffset = Vector3.new(0, 4.4, 0),
		AlwaysOnTop = false, MaxDistance = 120, LightInfluence = 0, Enabled = false})
	local bubble = make("TextLabel", marker, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = gold, Text = "!", Font = bold, TextSize = 22, TextColor3 = deep})
	round(bubble, 17, deep)
	entry.marker, entry.bubble = marker, bubble
	-- A "CLICK" cue under the server nameplate (SkyBlock-style vendor hologram,
	-- §29 theme), shown only up close.
	local tag = make("BillboardGui", head, {Name = "TownsfolkClick", Size = UDim2.fromOffset(90, 16), StudsOffset = Vector3.new(0, 1.15, 0),
		AlwaysOnTop = false, MaxDistance = 36, LightInfluence = 0})
	make("TextLabel", tag, {Name = "Click", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "CLICK", Font = Theme.font.display, TextSize = 10,
		TextColor3 = Theme.rgb("FFE066"), TextStrokeTransparency = 0.3, TextStrokeColor3 = Theme.color.void})
	entry.tag = tag
	npcs[model] = entry
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
			if entry.role == "Guide" then show = T.Conditions.tutorialActive(s) or T.Conditions.contractReady(s)
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
	folder.ChildRemoved:Connect(function(m) npcs[m] = nil; if talking and talking.model == m then closeDialogue() end end)
	for _, m in ipairs(folder:GetChildren()) do task.spawn(register, m) end
	task.delay(1, updateMarkers)
end)

local LOOK_RANGE, ANIM_STEP = 20, 1 / 30
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < ANIM_STEP then return end
	local step = accumulator
	accumulator = 0
	local character = player.Character
	local myHead = character and character:FindFirstChild("Head")
	local myPos = myHead and myHead.Position
	local now = os.clock()
	for model, entry in pairs(npcs) do
		if not model.Parent then npcs[model] = nil; continue end
		local rootPos = entry.root.Position
		local distance = if myPos then (myPos - rootPos).Magnitude else math.huge
		if distance > T.IDLE_RANGE then continue end
		local t = now + entry.phase
		-- Look-at: yaw/pitch toward the player's head, eased; neutral when far.
		local yaw, pitch = 0, 0
		local focused = talking and talking.model == model
		if myPos and (distance < LOOK_RANGE or focused) then
			local rel = entry.root.CFrame:PointToObjectSpace(myPos)
			yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.0, 1.0)
			pitch = math.clamp(math.atan2(rel.Y - 2.4, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.35, 0.35)
		else
			yaw = math.sin(t * 0.35) * 0.25
		end
		local ease = math.min(1, step * 5)
		entry.yaw += (yaw - entry.yaw) * ease
		entry.pitch += (pitch - entry.pitch) * ease
		local m = entry.motors
		if m.Neck then m.Neck.motor.C0 = m.Neck.base * CFrame.Angles(entry.pitch, entry.yaw * 0.7, 0) end
		if m.Waist then m.Waist.motor.C0 = m.Waist.base * CFrame.Angles(math.sin(t * 1.6) * 0.025, entry.yaw * 0.3, math.sin(t * 0.8) * 0.03) end
		local talk = if focused then math.sin(t * 6) * 0.08 else 0
		if m.LeftShoulder then m.LeftShoulder.motor.C0 = m.LeftShoulder.base * CFrame.Angles(math.sin(t * 1.1) * 0.05, 0, -0.04 - talk) end
		if m.RightShoulder then m.RightShoulder.motor.C0 = m.RightShoulder.base * CFrame.Angles(-math.sin(t * 1.1) * 0.05 + talk, 0, 0.04) end
		if focused and distance > 24 then closeDialogue() end
	end
end)

-- Keep the tracker honest: poll gently while the tutorial is active.
task.spawn(function()
	refresh(false)
	while true do
		task.wait(10)
		local state = T.tutorialState(snapshot)
		if not state.complete and not trackerHidden then refresh(false) end
	end
end)

-- HUD depth overlay (StarterPlayerScripts.IsleOverlay; docs/DEPTH-CONTRACT.md §34).
--   * Action label: OSRS-style "verb target (level) / N more options" for what
--     the mouse is over (ProximityPrompt objects, townsfolk, creatures,
--     players), in the top lane (Theme.hudLayout actionLabel). Left click on a
--     prompt object drives that prompt (InputHoldBegin / InputHoldEnd, walking
--     up first when out of reach); creatures keep combat.client.lua's click.
--   * World context menu: right click (no drag) or a touch long-press lists
--     every action on the target: each prompt, Attack (IsleAttackLocal), Examine
--     (text from data, into chat), Walk here, Cancel.
--   * Status orbs beside the minimap (Theme.hudLayout orbs): Health, Prayer
--     (click: quick-prayers on / off through the atlas' "prayer" relay), Speed
--     (click: Journal › Agility), Special (a dungeon class's ultimate charges,
--     click drives the Eclipse Heart's Ultimate prompt; else the readiest
--     mastery capstone, click: Hero › Mastery).
--   * Chat: filter tabs (All / Game / Public / Private / Crew / Trade) with
--     On / Filtered / Off states (right-click a tab to cycle) over
--     TextChatService (OnIncomingMessage), and the Game message router
--     (ReplicatedStorage.IsleChatLocal): snapshot messages, announcements and
--     examine lines, colour-coded and with repeats collapsed ("… ×3").
--   * Pickup feed (Theme.hudLayout pickupFeed): "+3 Copperstone Ore" lines
--     (pictogram, rarity colour) from snapshot item deltas, merged per item.
-- Nothing here grants anything: every verb goes through existing validated paths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local HD = require(ReplicatedStorage:WaitForChild("AetherHudDepth"))
local C, make, rgb = T.color, T.make, T.rgb
local tok = T.HudDepth

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, toasts, snapshots = channel("IsleActionLocal"), channel("IsleToastLocal"), channel("IsleSnapshotLocal")
local hudEvents, chatEvents, attackEvents = channel("IsleHudLocal"), channel("IsleChatLocal"), channel("IsleAttackLocal")
local function tbl(v) return if type(v) == "table" then v else {} end
local function num(v, d) v = tonumber(v); return if v and v == v then v else (d or 0) end

local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleOverlay", ResetOnSpawn = false, DisplayOrder = 7,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
-- All state in one table (keeps the chunk far below Luau's local limit).
local S = {snap = nil, hover = nil, options = {}, menuOptions = {}, menuTarget = nil, mouseMode = not Input.TouchEnabled, mouse = nil,
	walkToken = 0, chatLog = {}, chatStates = HD.defaultStates(), chatTab = "All", friends = {}, feed = {}, feedRows = {}, items = nil, coins = nil,
	seen = setmetatable({}, {__mode = "k"}), orbs = {}, hoverAt = 0, sent = {}}
local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
local function layout()
	return T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled, satchelOpen = player:GetAttribute("IsleSatchelOpen") == true})
end
local function toast(text) if type(text) == "string" and text ~= "" then toasts:Fire(text) end end
local function send(verb, item)
	table.insert(S.sent, {verb, item})
	if #S.sent > 20 then table.remove(S.sent, 1) end
	actions:Fire(verb, item)
end
local function character()
	local char = player.Character
	return char, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

------------------------------------------------------------------------------
-- Chat router (Game messages) and filter tabs
------------------------------------------------------------------------------
S.collapser = HD.newCollapser(0.9, 4)
local function systemChannel()
	local ok, found = pcall(function()
		local service = game:GetService("TextChatService")
		local channels = service and service:FindFirstChild("TextChannels")
		return channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
	end)
	return if ok then found else nil
end
-- Prints one collapsed Game line (kept in S.chatLog for tests / tooling).
local function printGame(entry)
	local d = tbl(entry.data)
	local text = HD.collapsedText(entry.text, entry.count)
	table.insert(S.chatLog, {text = text, color = d.color, kind = d.kind, important = d.important})
	if #S.chatLog > 40 then table.remove(S.chatLog, 1) end
	local rich = "<font color=\"#" .. (d.color or tok.chatInfo) .. "\">" .. (if d.important then "<b>" .. HD.escape(text) .. "</b>" else HD.escape(text)) .. "</font>"
	local target = systemChannel()
	if target then pcall(function() target:DisplaySystemMessage(rich, "IsleGame:" .. tostring(d.kind or "info")) end) end
end
local function flushChat(force)
	local out = if force then S.collapser.flush() else S.collapser.due(os.clock())
	for _, entry in ipairs(out) do printGame(entry) end
end
-- kind: a HudDepth.gameKind kind, "announce" or "examine"; color: hex or nil
-- (classified); important: passes the Game tab's Filtered state.
function S.gameLine(kind, text, color, important)
	if type(text) ~= "string" or text == "" then return end
	local k, c, imp = HD.gameKind(text, T)
	if kind == "announce" or kind == "examine" then k, imp = kind, important ~= false end
	if not HD.chatShows("Game", S.chatStates, S.chatTab, {important = important == true or imp}) then return end
	local out = S.collapser.push(text, os.clock(), {kind = k, color = color or c, important = important == true or imp})
	for _, entry in ipairs(out) do printGame(entry) end
	task.delay(S.collapser.window + 0.05, flushChat)
end
chatEvents.Event:Connect(function(kind, text, color, important)
	if type(text) == "string" and #text <= 400 then S.gameLine(tostring(kind or "info"), text, type(color) == "string" and color or nil, important == true) end
end)
-- Player messages: classify (Public / Private / Crew / Trade) and hide what the
-- tab or its state filters out. Callbacks must not yield, so friendships are
-- cached up front.
local function crewOf(userId)
	local mine = player:GetAttribute("CoopId")
	if mine == nil or mine == "" then return false end
	local other = Players:GetPlayerByUserId(userId)
	return other ~= nil and other:GetAttribute("CoopId") == mine
end
function S.incoming(message)
	local source = message.TextSource
	local channelName = message.TextChannel and message.TextChannel.Name or ""
	local userId = source and source.UserId
	local msg = {system = source == nil, metadata = message.Metadata, channel = channelName, text = message.Text,
		fromCrew = userId ~= nil and userId ~= player.UserId and crewOf(userId), self = userId == player.UserId,
		friend = userId ~= nil and S.friends[userId] == true, important = true}
	msg.crew = msg.fromCrew
	-- Game lines the router printed were filtered already.
	if tostring(message.Metadata or ""):sub(1, 8) == "IsleGame" then return nil end
	local category = HD.chatCategory(msg)
	if HD.chatShows(category, S.chatStates, S.chatTab, msg) then return nil end
	local props = Instance.new("TextChatMessageProperties")
	props.Text, props.PrefixText = "", ""
	return props
end
pcall(function()
	local service = game:GetService("TextChatService")
	service.OnIncomingMessage = function(message)
		local ok, props = pcall(S.incoming, message)
		return if ok then props else nil
	end
end)
local function cacheFriend(other)
	if other == player then return end
	task.spawn(function()
		local ok, yes = pcall(function() return player:IsFriendsWith(other.UserId) end)
		if ok and yes then S.friends[other.UserId] = true end
	end)
end
pcall(function()
	for _, other in ipairs(Players:GetPlayers()) do cacheFriend(other) end
	Players.PlayerAdded:Connect(cacheFriend)
	Players.PlayerRemoving:Connect(function(other) S.friends[other.UserId] = nil end)
end)
-- Tabs (desktop; Theme.hudLayout chatTabs): click selects, right click cycles
-- the category's state. Published as local attributes IsleChatTab / IsleChatFilters.
S.tabRow = make("Frame", gui, {Name = "ChatTabs", BackgroundTransparency = 1, Visible = false})
S.tabs = {}
local function paintTabs()
	for name, b in pairs(S.tabs) do
		T.tone(b, if name == S.chatTab then "primary" else "secondary")
		local state = if name == "All" then nil else S.chatStates[name]
		local caption = b:FindFirstChild("State")
		caption.Text = state or ""
		b.TextYAlignment = if state then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
		caption.TextColor3 = if state then rgb(HD.STATE_COLORS[state]) elseif name == S.chatTab then C.onGold else C.dim
	end
	player:SetAttribute("IsleChatTab", S.chatTab)
	player:SetAttribute("IsleChatFilters", HD.encodeStates(S.chatStates))
end
function S.selectTab(name)
	if not table.find(HD.CHAT_TABS, name) then return end
	S.chatTab = name
	paintTabs()
end
function S.cycleTab(name)
	if not S.chatStates[name] then return end
	S.chatStates[name] = HD.cycleState(S.chatStates[name])
	paintTabs()
	toast(name .. " chat: " .. S.chatStates[name])
end
for i, name in ipairs(HD.CHAT_TABS) do
	local b = T.button(S.tabRow, "", {name = "Chat" .. name, order = i, size = UDim2.fromOffset(60, 26), textSize = 11})
	b.TextYAlignment = Enum.TextYAlignment.Top
	make("UIPadding", b, {PaddingTop = UDim.new(0, 2)})
	b.Text = name
	T.label(b, {Name = "State", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -4, 0, 9),
		Font = T.font.display, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 2})
	b.Activated:Connect(function() S.selectTab(name) end)
	b.MouseButton2Click:Connect(function() S.cycleTab(name) end)
	S.tabs[name] = b
end
paintTabs()

------------------------------------------------------------------------------
-- Action label and world context menu
------------------------------------------------------------------------------
S.label = make("Frame", gui, {Name = "ActionLabel", BackgroundColor3 = C.void, BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false})
T.corner(S.label, 5)
make("UIGradient", S.label, {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1)})})
S.labelMain = T.label(S.label, {Name = "Main", Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -12, 0, 18), Font = T.font.label, TextSize = 15,
	RichText = true, TextStrokeTransparency = 0.25, TextStrokeColor3 = C.void, Text = ""})
S.labelMore = T.label(S.label, {Name = "More", Position = UDim2.fromOffset(8, 19), Size = UDim2.new(1, -12, 0, 13), Font = T.font.body, TextSize = 12,
	RichText = true, TextStrokeTransparency = 0.35, TextStrokeColor3 = C.void, Text = ""})

-- The menu: a Skyforge panel titled "Choose option" with pooled option rows,
-- in its own ScreenGui above every HUD layer (the atlas is 8, the satchel 9).
S.menuGui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleWorldMenu", ResetOnSpawn = false, DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
S.menu = T.frame(S.menuGui, {name = "WorldMenu", size = UDim2.fromOffset(220, 60), ornate = false, rimThickness = 1.5, transparency = 0.04, visible = false,
	title = "CHOOSE OPTION", header = 22, titleSize = 10, zIndex = 40})
S.menuBody = S.menu:FindFirstChild("Body")
S.menuButtons = {}
local function menuButton(i)
	local b = S.menuButtons[i]
	if b then return b end
	b = make("TextButton", S.menuBody, {Name = "Option" .. i, AutoButtonColor = false, BackgroundColor3 = C.hover, BackgroundTransparency = 1,
		BorderSizePixel = 0, Font = T.font.label, TextSize = 14, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 41,
		Selectable = true})
	T.corner(b, 4)
	make("UIPadding", b, {PaddingLeft = UDim.new(0, 8)})
	b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.35 end)
	b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
	b.Activated:Connect(function() S.pickOption(i) end)
	S.menuButtons[i] = b
	return b
end

-- Target under a world part: the nearest creature, townsfolk, other player or
-- a part carrying ProximityPrompts (walking up at most 6 ancestors).
local function promptsOf(node, out)
	if not node:FindFirstChildOfClass("ProximityPrompt") then return out end
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("ProximityPrompt") and child.Enabled then
			table.insert(out, {action = child.ActionText, object = child.ObjectText, item = child:GetAttribute("IsleItem"), enabled = true,
				hold = child.HoldDuration, instance = child})
		end
	end
	return out
end
function S.resolve(part, position)
	local node = part
	local prompts = {}
	for _ = 1, 6 do
		if not node or node == workspace then break end
		if node:IsA("Model") then
			if CollectionService:HasTag(node, "IsleMonster") then
				local owner = node:GetAttribute("OwnerUserId")
				return {kind = "monster", model = node, name = tostring(node:GetAttribute("DisplayName") or node.Name), level = node:GetAttribute("Level"),
					monsterId = node:GetAttribute("MonsterId"), attackable = not node:GetAttribute("Dead") and (owner == nil or owner == player.UserId),
					prompts = {}, position = position}
			end
			local role = node:GetAttribute("TownsfolkRole")
			if role then
				local found = {}
				for _, d in ipairs(node:GetDescendants()) do
					if d:IsA("ProximityPrompt") then promptsOf(d.Parent, found); break end
				end
				local npc = tbl(tbl(Data.Townsfolk).NPCs)[role]
				return {kind = "npc", model = node, role = role, name = npc and npc.name or node.Name, prompts = found, position = position}
			end
			local other = Players:GetPlayerFromCharacter(node)
			if other and other ~= player then
				return {kind = "player", model = node, userId = other.UserId, name = other.DisplayName, renown = other:GetAttribute("RenownLevel"),
					title = other:GetAttribute("RenownTitle"), prompts = {}, position = position}
			end
		end
		if #prompts == 0 then promptsOf(node, prompts) end
		if #prompts > 0 then
			local first = prompts[1]
			return {kind = "prompt", part = node, name = HD.parseObject(first.object), prompts = prompts, position = position}
		end
		node = node.Parent
	end
	return nil
end
local function ctx()
	local snap = S.snap
	local skills = tbl(tbl(tbl(snap).depth).skills)
	return {Data = Data, levels = tbl(tbl(snap).levels), combatLevel = num(tbl(skills.Combat).level, num(tbl(tbl(snap).levels).Combat, 1))}
end
function S.optionsFor(target)
	return HD.targetOptions(target, ctx(), T)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
function S.hitAt(screenPos)
	local camera = workspace.CurrentCamera
	if not camera or not screenPos then return nil end
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	rayParams.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, rayParams)
	if not hit then return nil end
	return S.resolve(hit.Instance, hit.Position), hit.Position
end
function S.placeLabel()
	local L = layout()
	local box = L.actionLabel
	S.label.Position, S.label.Size = UDim2.fromOffset(box.x, box.y), UDim2.fromOffset(box.w, box.h)
	S.labelWidth = box.w
end
-- Sets the label from a target (nil hides it). Rewrites text only on change.
function S.setHover(target)
	S.hover = target
	S.options = if target then S.optionsFor(target) else {}
	local main, more = HD.labelText(S.options, T)
	if S.labelMain.Text ~= main then S.labelMain.Text = main end
	if S.labelMore.Text ~= more then S.labelMore.Text = more end
	S.label.Visible = main ~= "" and S.mouseMode and (S.labelWidth or 0) > 0 and not S.menu.Visible
end
-- Hover tick: one raycast at ≤ 10 Hz while the mouse is the input.
RunService.Heartbeat:Connect(function()
	if not S.mouseMode or not S.mouse then return end
	local now = os.clock()
	if now - S.hoverAt < 0.1 then return end
	S.hoverAt = now
	if S.orbHover then return end
	local target = S.hitAt(S.mouse)
	S.setHover(target)
end)

-- Drives a ProximityPrompt (its server handler decides): in reach, hold it for
-- its HoldDuration; otherwise walk up (Humanoid:MoveTo) and hold on arrival
-- (8 s at most; a newer order cancels it).
function S.drive(prompt)
	if not prompt or not prompt.Parent then return false end
	S.walkToken += 1
	local token = S.walkToken
	local function hold()
		pcall(function()
			prompt:InputHoldBegin()
			task.delay(num(prompt.HoldDuration) + 0.05, function() pcall(function() prompt:InputHoldEnd() end) end)
		end)
		S.lastDriven = prompt
		return true
	end
	local function within()
		local _, root = character()
		local part = prompt.Parent
		local at = if part and part:IsA("BasePart") then part.Position elseif part and part:IsA("Attachment") then part.WorldPosition else nil
		if not root or not at then return true, at end
		return (root.Position - at).Magnitude <= num(prompt.MaxActivationDistance, 10) - 0.5, at
	end
	local near, at = within()
	if near then return hold() end
	local _, _, humanoid = character()
	if not humanoid or not at then return false end
	humanoid:MoveTo(at)
	task.spawn(function()
		local untilAt = os.clock() + 8
		while S.walkToken == token and os.clock() < untilAt do
			task.wait(0.1)
			if S.walkToken ~= token or not prompt.Parent then return end
			if within() then hold() return end
		end
	end)
	return true
end
function S.walkTo(position)
	S.walkToken += 1
	local _, _, humanoid = character()
	if humanoid and typeof(position) == "Vector3" then humanoid:MoveTo(position) end
end
function S.run(option, target)
	if not option or not target then return end
	local kind = option["local"]
	if option.prompt then
		local p = target.prompts[option.prompt]
		if p and p.instance then S.drive(p.instance) end
	elseif kind == "attack" then
		attackEvents:Fire(target.model)
	elseif kind == "examine" then
		S.gameLine("examine", HD.examineText(target, Data), tok.chatAnnounce, true)
		flushChat(true)
	elseif kind == "walk" then
		S.walkTo(target.position or (target.model and target.model.PrimaryPart and target.model.PrimaryPart.Position))
	end
end
function S.closeMenu()
	S.menu.Visible = false
	S.menuTarget = nil
end
function S.openMenu(target, at)
	if not target then return false end
	local options = S.optionsFor(target)
	if #options == 0 then return false end
	S.menuTarget, S.menuOptions = target, options
	local L = layout()
	local rowH = if L.touch then 44 else 24
	local width = 200
	for i, option in ipairs(options) do
		local b = menuButton(i)
		b.Visible = true
		b.Text = HD.optionText(option, T)
		b.TextSize = if L.touch then 15 else 14
		b.Position, b.Size = UDim2.fromOffset(4, 4 + (i - 1) * rowH), UDim2.new(1, -8, 0, rowH)
		width = math.max(width, 24 + 8 * #(b.Text:gsub("<[^>]+>", "")))
	end
	for i = #options + 1, #S.menuButtons do S.menuButtons[i].Visible = false end
	width = math.min(width, 300, L.w - 16)
	local height = 22 + 8 + #options * rowH
	local x = math.clamp(math.floor(at.X - width / 2), 8, math.max(8, L.w - width - 8))
	local y = math.clamp(math.floor(at.Y - 10), 8, math.max(8, L.h - height - 8))
	S.menu.Position, S.menu.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(width, height)
	S.menu.Visible = true
	S.label.Visible = false
	return true
end
-- The menu is placed in screen pixels (Position / Size offsets).
function S.insideMenu(at)
	local p, s = S.menu.Position, S.menu.Size
	return at.X >= p.X.Offset and at.X <= p.X.Offset + s.X.Offset and at.Y >= p.Y.Offset and at.Y <= p.Y.Offset + s.Y.Offset
end
function S.pickOption(i)
	local option, target = S.menuOptions[i], S.menuTarget
	S.closeMenu()
	if option then S.run(option, target) end
end
-- Mouse: left click drives a hovered prompt object (creatures stay combat's);
-- right click without a drag (camera turns are drags) opens the menu.
Input.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		S.mouse = Vector2.new(input.Position.X, input.Position.Y)
		if not S.mouseMode then S.mouseMode = true end
	end
end)
Input.InputBegan:Connect(function(input, processed)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		S.mouseMode = false
		S.label.Visible = false
	end
	if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and S.menu.Visible then
		-- A press outside the menu closes it; inside, the option's Activated runs.
		if not S.insideMenu(input.Position) then S.closeMenu() end
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and S.menu.Visible then S.closeMenu() return end
	if processed then return end
	if kind == Enum.UserInputType.MouseButton1 then
		local target = S.hitAt(Vector2.new(input.Position.X, input.Position.Y))
		if target and (target.kind == "prompt" or target.kind == "npc") then
			local options = S.optionsFor(target)
			if options[1] and options[1].prompt then S.run(options[1], target) end
		end
	elseif kind == Enum.UserInputType.MouseButton2 then
		S.rightDown = {at = Vector2.new(input.Position.X, input.Position.Y), time = os.clock()}
	end
end)
Input.InputEnded:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 or not S.rightDown then return end
	local down = S.rightDown
	S.rightDown = nil
	local at = Vector2.new(input.Position.X, input.Position.Y)
	if processed or (at - down.at).Magnitude > 6 or os.clock() - down.time > 0.4 then return end
	local target = S.hitAt(at)
	if target and target.kind ~= nil then S.openMenu(target, at) end
end)
pcall(function()
	Input.TouchLongPress:Connect(function(positions, state, processed)
		if processed or state ~= Enum.UserInputState.Begin or type(positions) ~= "table" or not positions[1] then return end
		local at = Vector2.new(positions[1].X, positions[1].Y)
		local target = S.hitAt(at)
		if target then S.openMenu(target, at) end
	end)
end)

------------------------------------------------------------------------------
-- Status orbs
------------------------------------------------------------------------------
S.orbFrame = make("Frame", gui, {Name = "StatusOrbs", BackgroundTransparency = 1})
local GLYPHS = {Health = "❤", Prayer = "✧", Speed = "»", Special = "✸"}
for i, id in ipairs(HD.ORB_IDS) do
	local b = make("TextButton", S.orbFrame, {Name = "Orb" .. id, Text = "", AutoButtonColor = false, BackgroundColor3 = rgb(tok.orbGlass), BackgroundTransparency = 0.05,
		BorderSizePixel = 0, LayoutOrder = i, Selectable = true})
	make("UICorner", b, {CornerRadius = UDim.new(1, 0)})
	local liquid = make("Frame", b, {Name = "Liquid", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 2, Active = false})
	make("UICorner", liquid, {CornerRadius = UDim.new(1, 0)})
	local fill = make("UIGradient", liquid, {Name = "Fill", Rotation = 90})
	local shine = make("Frame", b, {Name = "Shine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.42, 0.1), Size = UDim2.fromScale(0.5, 0.26),
		BackgroundColor3 = C.white, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 4, Active = false})
	make("UICorner", shine, {CornerRadius = UDim.new(1, 0)})
	local rim = T.rim(b, 2)
	rim.Name = "Rim"
	-- The number sits on a dark pill across the orb's foot (OSRS orbs carry
	-- theirs beside the orb); the glyph stays in the glass.
	local value = T.label(b, {Name = "Value", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, 4, 0, 13),
		Font = T.font.number, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.void, ZIndex = 6,
		TextTruncate = Enum.TextTruncate.None, Text = "", BackgroundTransparency = 0.15, BackgroundColor3 = C.void})
	T.corner(value, 6)
	make("UIStroke", value, {Name = "Edge", Color = C.frameLo, Thickness = 1, Transparency = 0.2})
	local glyph = T.label(b, {Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(1, 0.5),
		Font = T.font.heading, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.1, TextStrokeColor3 = C.void, ZIndex = 5,
		Text = GLYPHS[id], TextColor3 = C.white})
	local active = make("UIStroke", make("Frame", b, {Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 6, 1, 6), BackgroundTransparency = 1, ZIndex = 1, Active = false}), {Name = "Glow", Thickness = 2, Transparency = 0.25, Color = C.mint})
	make("UICorner", active.Parent, {CornerRadius = UDim.new(1, 0)})
	S.orbs[id] = {button = b, liquid = liquid, fill = fill, value = value, glyph = glyph, rim = rim, halo = active.Parent, fraction = -1, text = nil, color = nil}
	b.MouseEnter:Connect(function() S.orbHover = id; S.showCaption(id) end)
	b.MouseLeave:Connect(function() if S.orbHover == id then S.orbHover = nil; S.setHover(nil) end end)
	b.Activated:Connect(function() S.clickOrb(id) end)
end
function S.placeOrbs()
	local L = layout()
	local o = L.orbs
	S.orbFrame.Position, S.orbFrame.Size = UDim2.fromOffset(o.x, o.y), UDim2.fromOffset(o.w, o.h)
	for i, id in ipairs(HD.ORB_IDS) do
		local col, row = (i - 1) % o.cols, (i - 1) // o.cols
		local orb = S.orbs[id]
		orb.button.Position = UDim2.fromOffset(col * (o.size + o.gap), row * (o.size + o.gap))
		orb.button.Size = UDim2.fromOffset(o.size, o.size)
		orb.value.TextSize = if o.size >= 44 then 10 else 9
		orb.value.Size = UDim2.new(1, 4, 0, if o.size >= 44 then 15 else 13)
		orb.glyph.TextSize = if o.size >= 44 then 19 else 15
	end
end
function S.orbInput()
	local _, _, humanoid = character()
	local snap = tbl(S.snap)
	local depth = tbl(snap.depth)
	return {
		health = if humanoid then humanoid.Health else num(tbl(snap.stats).maxHealth, 100),
		maxHealth = if humanoid then humanoid.MaxHealth else num(tbl(snap.stats).maxHealth, 100),
		prayer = player:GetAttribute("PrayerPoints"), prayerMax = player:GetAttribute("PrayerMax"),
		prayerActive = (player:GetAttribute("PrayerActive") or "") ~= "",
		speed = num(tbl(depth.stats).speed, 100), mastery = depth.mastery, masteryTrees = tbl(Data.Mastery).Trees,
		dungeon = {class = player:GetAttribute("DungeonClass"), ultimates = player:GetAttribute("DungeonUltimates"), abilityReady = player:GetAttribute("DungeonAbilityReady")},
	}
end
-- Repaints only what changed (fill keypoints, text, colours).
function S.paintOrbs()
	S.orbValues = HD.orbValues(S.orbInput(), T)
	for _, v in ipairs(S.orbValues) do
		local orb = S.orbs[v.id]
		if orb.fraction ~= v.fraction then
			orb.fraction = v.fraction
			local keys = {}
			for _, k in ipairs(HD.fillKeys(v.fraction)) do table.insert(keys, NumberSequenceKeypoint.new(k[1], k[2])) end
			orb.fill.Transparency = NumberSequence.new(keys)
		end
		if orb.color ~= v.color then
			orb.color = v.color
			local base = rgb(v.color)
			orb.fill.Color = ColorSequence.new(T.lighten(base, 0.3), T.darken(base, 0.35))
		end
		if orb.value.Text ~= v.text then orb.value.Text = v.text end
		orb.value.TextColor3 = if v.low then rgb(tok.orbLow) elseif v.dim then C.faint else C.text
		orb.halo.Visible = v.active == true
		orb.button.Active = v.clickable == true
		orb.button.AutoButtonColor = false
		orb.liquid.BackgroundTransparency = if v.dim then 0.6 else 0
	end
end
function S.showCaption(id)
	for _, v in ipairs(S.orbValues or {}) do
		if v.id == id then
			local text = HD.paint(HD.escape(v.caption or id), v.color)
			if v.clickable then text = HD.paint("Click", tok.verb) .. " " .. text end
			S.labelMain.Text, S.labelMore.Text = text, ""
			S.label.Visible = S.mouseMode and (S.labelWidth or 0) > 0
		end
	end
end
-- Eclipse Heart prompts (dungeon class abilities): driven like any prompt.
local function heartPrompt(action)
	local ok, found = pcall(function()
		local arena = workspace:FindFirstChild("The Hollow Observatory")
		local heart = arena and arena:FindFirstChild("Eclipse Heart")
		if not heart then return nil end
		for _, child in ipairs(heart:GetChildren()) do
			if child:IsA("ProximityPrompt") and child.ActionText == action then return child end
		end
		return nil
	end)
	return if ok then found else nil
end
function S.clickOrb(id)
	local v
	for _, o in ipairs(S.orbValues or {}) do if o.id == id then v = o end end
	if not v or not v.clickable then return end
	if id == "Prayer" then
		local ids = HD.quickPrayerPlan(player:GetAttribute("PrayerActive"), player:GetAttribute("PrayerQuick"))
		if #ids == 0 then toast("Choose quick-prayers on the Hero › Prayer page.") return end
		-- One toggle per prayer, spaced past the server's action cooldown.
		for i, prayer in ipairs(ids) do
			if i == 1 then send("prayer", prayer) else task.delay(0.3 * (i - 1), function() send("prayer", prayer) end) end
		end
	elseif id == "Speed" then
		hudEvents:Fire("open", "Journal", "Agility")
	elseif id == "Special" then
		if v.mode == "ultimate" then
			local prompt = heartPrompt("Ultimate")
			if prompt then S.drive(prompt) else toast("Stand by the Eclipse Heart to call your ultimate.") end
		else
			hudEvents:Fire("open", "Hero", "Mastery")
		end
	end
end
-- Health: the humanoid's own signals (rebound on respawn).
S.healthLinks = {}
local function bindHumanoid(char)
	for _, link in ipairs(S.healthLinks) do link:Disconnect() end
	table.clear(S.healthLinks)
	local humanoid = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10))
	if humanoid then
		table.insert(S.healthLinks, humanoid.HealthChanged:Connect(S.paintOrbs))
		table.insert(S.healthLinks, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(S.paintOrbs))
	end
	S.paintOrbs()
end
player.CharacterAdded:Connect(function(char) task.spawn(bindHumanoid, char) end)
for _, name in ipairs({"PrayerPoints", "PrayerMax", "PrayerActive", "DungeonClass", "DungeonUltimates", "DungeonAbilityReady"}) do
	player:GetAttributeChangedSignal(name):Connect(S.paintOrbs)
end
-- Mastery cooldowns count down between snapshots: 1 Hz, strings only.
task.spawn(function()
	while true do
		task.wait(1)
		local special = S.orbValues and S.orbValues[4]
		if special and special.mode == "mastery" and S.snap then
			local mastery = tbl(tbl(S.snap.depth).mastery)
			for _, t in pairs(tbl(mastery.trees)) do
				if type(t) == "table" then
					if num(t.cooldown) > 0 then t.cooldown = math.max(0, num(t.cooldown) - 1) end
					if num(t.active) > 0 then t.active = math.max(0, num(t.active) - 1) end
				end
			end
			S.paintOrbs()
		end
	end
end)

------------------------------------------------------------------------------
-- Pickup feed
------------------------------------------------------------------------------
S.feedFrame = make("Frame", gui, {Name = "PickupFeed", BackgroundTransparency = 1})
S.FEED_WINDOW, S.FEED_LIFE = 3, 4.5
local function feedRow(i)
	local row = S.feedRows[i]
	if row then return row end
	row = make("Frame", S.feedFrame, {Name = "Pickup" .. i, BackgroundColor3 = C.void, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false})
	T.corner(row, 4)
	make("UIGradient", row, {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0.3), NumberSequenceKeypoint.new(1, 1)})})
	local slot = T.slot(row, {name = "Icon", size = 18})
	slot.Position = UDim2.fromOffset(1, 1)
	slot.Active = false
	T.label(row, {Name = "Text", Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -26, 1, 0), Font = T.font.label, TextSize = 13,
		TextStrokeTransparency = 0.3, TextStrokeColor3 = C.void, Text = ""})
	S.feedRows[i] = row
	return row
end
function S.placeFeed()
	local L = layout()
	local f = L.pickupFeed
	S.feedFrame.Position, S.feedFrame.Size = UDim2.fromOffset(f.x, f.y), UDim2.fromOffset(f.w, f.h)
	S.feedLines, S.feedRowH = f.lines, f.row
end
-- Newest at the foot; rows beyond the lane's lines stay hidden.
function S.renderFeed()
	local lines = S.feedLines or 0
	local shown = math.min(#S.feed, lines)
	for i = 1, math.max(shown, #S.feedRows) do
		local row = feedRow(i)
		local entry = S.feed[#S.feed - shown + i]
		if i <= shown and entry then
			local def = if entry.id == "coins" then {id = "coins", name = "Coins", kind = "material", rarity = "Legendary", color = "F7C548"} else Data.Items[entry.id]
			local text, color = HD.feedText(entry, def, T)
			local label = row:FindFirstChild("Text")
			label.Text, label.TextColor3 = text, rgb(color)
			label.TextSize = if S.feedRowH < 20 then 12 else 13
			T.setSlot(row:FindFirstChild("Icon"), {id = entry.id, def = def, count = 0})
			row.Position, row.Size = UDim2.fromOffset(0, (i - 1) * S.feedRowH), UDim2.new(1, 0, 0, S.feedRowH - 2)
			row.Visible = true
		else
			row.Visible = false
		end
	end
end
local function expireFeed()
	if HD.feedExpire(S.feed, os.clock(), S.FEED_LIFE) > 0 then S.renderFeed() end
end
function S.observe(snap)
	if type(snap) ~= "table" or S.seen[snap] then return end
	S.seen[snap] = true
	if type(snap.items) == "table" then
		if S.items then
			local now = os.clock()
			for _, d in ipairs(HD.itemDeltas(S.items, snap.items, S.coins, snap.coins)) do
				if d.id == "coins" or Data.Items[d.id] then HD.feedPush(S.feed, d.id, d.n, now, S.FEED_WINDOW, 8) end
			end
			S.renderFeed()
			task.delay(S.FEED_LIFE + 0.1, expireFeed)
		end
		S.items, S.coins = table.clone(snap.items), snap.coins
	end
	S.snap = snap
	-- Game messages (drops, level-ups, notices) go to chat, segment by segment.
	for _, segment in ipairs(HD.segments(snap.message)) do S.gameLine("info", segment) end
	S.paintOrbs()
	if S.hover then S.setHover(S.hover) end
end
snapshots.Event:Connect(S.observe)

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------
function S.relayout()
	local L = layout()
	S.placeLabel()
	S.placeOrbs()
	S.placeFeed()
	S.renderFeed()
	local t = L.chatTabs
	S.tabRow.Visible = t.w > 0
	if t.w > 0 then
		S.tabRow.Position, S.tabRow.Size = UDim2.fromOffset(t.x, t.y), UDim2.fromOffset(t.w, t.h)
		local tw = math.floor((t.w - (#HD.CHAT_TABS - 1) * t.gap) / #HD.CHAT_TABS)
		for i, name in ipairs(HD.CHAT_TABS) do
			local b = S.tabs[name]
			b.Position, b.Size = UDim2.fromOffset((i - 1) * (tw + t.gap), 0), UDim2.fromOffset(tw, t.h)
		end
	end
	if S.menu.Visible then S.closeMenu() end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(S.relayout)
player:GetAttributeChangedSignal("IsleSatchelOpen"):Connect(S.relayout)
S.relayout()
task.spawn(bindHumanoid, player.Character)
actions:Fire("snapshot") -- a late start asks the atlas for the latest snapshot

-- Test / tooling handle (no gameplay effect).
S.gui = gui
local api = Instance.new("BindableFunction")
api.Name = "IsleOverlayApi"
api.OnInvoke = function(method)
	if method == "state" then return S end
	return nil
end
api.Parent = player

-- HUD depth overlay (StarterPlayerScripts.IsleOverlay; docs/DEPTH-CONTRACT.md §34).
--   * Action label: OSRS-style "verb target (level) / N more options" for what
--     the mouse is over (ProximityPrompt objects, townsfolk, creatures,
--     players), in the top lane (Theme.hudLayout actionLabel). Left click on a
--     prompt object drives that prompt (InputHoldBegin, released on Triggered /
--     PromptButtonHoldEnded; one hold per prompt at a time). Out of reach it
--     walks up first along a PathfindingService route (≤ S.WALK_MAX studs, every
--     waypoint ground-checked, aborted when unreachable, on manual movement or
--     on an attack); creatures keep combat.client.lua's click. Prompts owned by
--     someone else (OwnerUserId) or with ClickablePrompt = false are skipped; an
--     IsleDefault prompt attribute makes that prompt the left-click default.
--     Touch laptops: the label starts hidden when TouchEnabled and switches on
--     with the first mouse movement (a touch or gamepad input hides it again),
--     so hybrid devices get the label exactly while the mouse is the input.
--     No hover over an Active GUI object or while a gamepad drives.
--   * World context menu: right click (no drag) or a touch long-press lists
--     every action on the target: each prompt, Attack (IsleAttackLocal), Examine
--     (text from data, into chat), Walk here, Cancel.
--   * Status orbs beside the minimap (Theme.hudLayout orbs): Health, Prayer
--     (click: quick-prayers on / off: one atomic "prayerQuickToggle" verb
--     through the atlas' queued relay), Speed
--     (click: Journal › Agility), Special (a dungeon class's ultimate charges,
--     click drives the Eclipse Heart's Ultimate prompt; else the readiest
--     mastery capstone, click: Hero › Mastery).
--   * Chat: filter tabs (All / Game / Public / Private / Crew / Trade) with
--     On / Filtered / Off states (right-click a tab to cycle) over
--     TextChatService (OnIncomingMessage, OnBubbleAdded), and the Game message
--     router (ReplicatedStorage.IsleChatLocal): snapshot messages, announcements
--     and examine lines, colour-coded and with repeats collapsed ("… ×3").
--     The default chat window cannot hide a line per tab without deleting it,
--     so selecting a tab never filters anything (it marks the tab read); only
--     a category's state hides lines. Whispers always show and badge Private.
--     Snapshot messages print once per snapshot.seq (atlas replays are silent).
--     The tab row follows the real chat window (hidden while it is closed).
--   * Pickup feed (Theme.hudLayout pickupFeed): "+3 Copperstone Ore" lines
--     (pictogram, rarity colour) from the server's snapshot.pickups (gathering,
--     fishing, loot and kill drops only), merged per item.
-- Nothing here grants anything: every verb goes through existing validated paths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local function service(name)
	local ok, found = pcall(function() return game:GetService(name) end)
	return if ok then found else nil
end
local Pathfinding = service("PathfindingService")
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
	seen = setmetatable({}, {__mode = "k"}), orbs = {}, hoverAt = 0, sent = {}, printed = {}, printedOrder = {}, unread = {},
	holding = setmetatable({}, {__mode = "k"}), WALK_MAX = 60}
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
-- (classified); important: passes the Game tab's Filtered state; force: a
-- line the player asked for (Examine) echoes whatever the Game state is.
-- The selected tab never drops a line (tabs are not views; see the header).
function S.gameLine(kind, text, color, important, force)
	if type(text) ~= "string" or text == "" then return end
	local k, c, imp = HD.gameKind(text, T)
	if kind == "announce" or kind == "examine" then k, imp = kind, important ~= false end
	if not force and not HD.chatShows("Game", S.chatStates, "All", {important = important == true or imp}) then return end
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
-- Classifies a TextChatMessage: msg (HudDepth.chatCategory input) and its category.
function S.classify(message)
	local source = message.TextSource
	local channelName = message.TextChannel and message.TextChannel.Name or ""
	local userId = source and source.UserId
	local msg = {system = source == nil, metadata = message.Metadata, channel = channelName, text = message.Text,
		fromCrew = userId ~= nil and userId ~= player.UserId and crewOf(userId), self = userId == player.UserId,
		friend = userId ~= nil and S.friends[userId] == true, important = true}
	msg.crew = msg.fromCrew
	return msg, HD.chatCategory(msg)
end
-- Shown under the category states (never the selected tab: the chat window
-- cannot hide a line per tab without deleting it). Whispers always show.
function S.passes(message)
	-- Game lines the router printed were filtered already.
	if tostring(message.Metadata or ""):sub(1, 8) == "IsleGame" then return true end
	local msg, category = S.classify(message)
	return HD.chatShows(category, S.chatStates, "All", msg), category, msg
end
function S.incoming(message)
	local shown, category, msg = S.passes(message)
	if category == "Private" and msg and not msg.self and S.chatTab ~= "Private" then
		-- An unread whisper badges the Private tab until it is selected.
		S.unread.Private = (S.unread.Private or 0) + 1
		S.paintBadges()
	end
	if shown then return nil end
	local props = Instance.new("TextChatMessageProperties")
	props.Text, props.PrefixText = "", ""
	return props
end
-- Bubble chat: a line its state hides (Off, or Filtered for strangers) gets an
-- invisible bubble too.
function S.bubble(message)
	if S.passes(message) then return nil end
	local props = Instance.new("BubbleChatMessageProperties")
	for key, value in pairs({BackgroundTransparency = 1, TailVisible = false, TextSize = 1, TextColor3 = C.void}) do
		pcall(function() props[key] = value end)
	end
	return props
end
pcall(function()
	local textChat = game:GetService("TextChatService")
	textChat.OnIncomingMessage = function(message)
		local ok, props = pcall(S.incoming, message)
		return if ok then props else nil
	end
	pcall(function()
		textChat.OnBubbleAdded = function(message)
			local ok, props = pcall(S.bubble, message)
			return if ok then props else nil
		end
	end)
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
function S.paintBadges()
	for name, b in pairs(S.tabs or {}) do
		local badge = b:FindFirstChild("Unread")
		local n = S.unread[name] or 0
		if badge then
			badge.Visible = n > 0
			badge.Text = if n > 9 then "9+" else tostring(n)
		end
	end
end
-- Selecting a tab marks it read; it does not filter (see the header).
function S.selectTab(name)
	if not table.find(HD.CHAT_TABS, name) then return end
	S.chatTab = name
	S.unread[name] = nil
	paintTabs()
	S.paintBadges()
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
	T.label(b, {Name = "State", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -4, 0, 11),
		Font = T.font.display, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 2})
	local badge = T.label(b, {Name = "Unread", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -4), Size = UDim2.fromOffset(16, 14),
		Font = T.font.number, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 4, Visible = false,
		BackgroundTransparency = 0, BackgroundColor3 = rgb(HD.STATE_COLORS.Off), TextColor3 = C.white})
	T.corner(badge, 7)
	b.Activated:Connect(function() S.selectTab(name) end)
	b.MouseButton2Click:Connect(function() S.cycleTab(name) end)
	S.tabs[name] = b
end
paintTabs()
S.paintBadges()

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
-- Skips prompts that are off, not clickable (ClickablePrompt = false) or owned
-- by another player (OwnerUserId: the server refuses those anyway). A prompt
-- with the IsleDefault attribute goes first (the left-click default).
local function promptsOf(node, out)
	if not node:FindFirstChildOfClass("ProximityPrompt") then return out end
	local first = #out + 1
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("ProximityPrompt") and child.Enabled and child.ClickablePrompt ~= false then
			local owner = child:GetAttribute("OwnerUserId")
			if owner == nil or owner == player.UserId then
				local entry = {action = child.ActionText, object = child.ObjectText, item = child:GetAttribute("IsleItem"), enabled = true,
					hold = child.HoldDuration, instance = child}
				if child:GetAttribute("IsleDefault") == true then table.insert(out, first, entry) else table.insert(out, entry) end
			end
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
-- cached: reuse the last resolve while the ray stays on the same part (≤ 1 s;
-- the hover tick). Clicks always resolve afresh.
function S.hitAt(screenPos, cached)
	local camera = workspace.CurrentCamera
	if not camera or not screenPos then return nil end
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	rayParams.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, rayParams)
	if not hit then S.hoverCache = nil return nil end
	local c = S.hoverCache
	if cached and c and c.instance == hit.Instance and os.clock() - c.at < 1 then
		if c.target then c.target.position = hit.Position end
		return c.target, hit.Position
	end
	local target = S.resolve(hit.Instance, hit.Position)
	S.hoverCache = {instance = hit.Instance, target = target, at = os.clock()}
	return target, hit.Position
end
-- Is an Active, visible GUI object (a button, a panel) under the cursor?
function S.overGui(at)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui or not at then return false end
	local ok, list = pcall(function() return playerGui:GetGuiObjectsAtPosition(at.X, at.Y) end)
	if not ok or type(list) ~= "table" then return false end
	for _, o in ipairs(list) do
		if o.Active and o.Visible ~= false and not o:IsDescendantOf(S.label) then return true end
	end
	return false
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
-- Hover tick: one raycast at ≤ 10 Hz while the mouse is the input (none over
-- an Active GUI object; none while a gamepad drives: mouseMode is off).
RunService.Heartbeat:Connect(function()
	if not S.mouseMode or not S.mouse then return end
	local now = os.clock()
	if now - S.hoverAt < 0.1 then return end
	S.hoverAt = now
	if S.orbHover then return end
	if S.overGui(S.mouse) then
		if S.hover or S.label.Visible then S.setHover(nil) end
		return
	end
	local target = S.hitAt(S.mouse, true)
	S.setHover(target)
end)

-- Walking ----------------------------------------------------------------------
-- Ground under `position` (a short downward ray, the character excluded)?
function S.grounded(position)
	rayParams.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), rayParams)
	return hit ~= nil, hit
end
-- A PathfindingService route (waypoints past the start), or nil when there is
-- no complete path. Without the service: the straight line, sampled for ground.
function S.route(from, to)
	if not Pathfinding then
		local out, steps = {}, math.max(1, math.ceil((to - from).Magnitude / 4))
		for i = 1, steps do table.insert(out, {Position = from:Lerp(to, i / steps)}) end
		return out
	end
	local ok, waypoints = pcall(function()
		local path = Pathfinding:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4})
		path:ComputeAsync(from, to)
		if path.Status ~= Enum.PathStatus.Success then return nil end
		return path:GetWaypoints()
	end)
	if not ok or type(waypoints) ~= "table" or #waypoints == 0 then return nil end
	local out = {}
	for _, wp in ipairs(waypoints) do
		if (wp.Position - from).Magnitude > 1 then table.insert(out, wp) end
	end
	return out
end
-- Ends any walk-up (a newer order, manual movement or an attack).
function S.cancelWalk()
	S.walkToken += 1
	S.walking = nil
end
-- The player steering by hand: MoveDirection pointing away from the waypoint.
function S.steered(humanoid, root, toward)
	local md = humanoid.MoveDirection
	if typeof(md) ~= "Vector3" or md.Magnitude < 0.1 then return false end
	local flat = Vector3.new(toward.X - root.Position.X, 0, toward.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then return false end
	return md.Unit:Dot(flat.Unit) < 0.3
end
-- Walks to `goal` along a route. arrived() (optional) is polled each 0.1 s and
-- ends the walk early, calling onArrive(). Refused with a toast beyond
-- S.WALK_MAX studs, with no ground at the goal or under any waypoint (never off
-- an edge) and when no complete route exists. Returns whether it set off.
function S.walkPath(goal, arrived, onArrive)
	local _, root, humanoid = character()
	if not root or not humanoid or typeof(goal) ~= "Vector3" then return false end
	if (root.Position - goal).Magnitude > S.WALK_MAX then toast("Too far: walk closer first.") return false end
	local ground, hit = S.grounded(goal)
	if not ground then toast("You can't walk there.") return false end
	goal = Vector3.new(goal.X, math.max(goal.Y, hit.Position.Y), goal.Z)
	S.cancelWalk()
	local token = S.walkToken
	local waypoints = S.route(root.Position, goal)
	if not waypoints then toast("You can't reach that from here.") return false end
	for _, wp in ipairs(waypoints) do
		if not S.grounded(wp.Position) then toast("You can't reach that from here.") return false end
	end
	S.walking = token
	task.spawn(function()
		for _, wp in ipairs(waypoints) do
			if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
			humanoid:MoveTo(wp.Position)
			local untilAt = os.clock() + 4
			while true do
				if S.walkToken ~= token then return end
				if arrived and arrived() then S.walking = nil; onArrive() return end
				local here = root.Position
				if Vector3.new(here.X - wp.Position.X, 0, here.Z - wp.Position.Z).Magnitude < 2 then break end
				if os.clock() > untilAt then S.walking = nil return end
				task.wait(0.1)
				if S.walkToken ~= token then return end
				if S.steered(humanoid, root, wp.Position) then S.cancelWalk() return end
			end
		end
		if S.walkToken ~= token then return end
		S.walking = nil
		if not arrived or arrived() then
			if onArrive then onArrive() end
		end
	end)
	return true
end

-- Prompts ------------------------------------------------------------------------
-- Where the engine measures a prompt from: its part, attachment or model.
function S.promptPoint(prompt)
	local parent = prompt.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	if parent:IsA("Model") then
		if parent.PrimaryPart then return parent.PrimaryPart.Position end
		local ok, pivot = pcall(function() return parent:GetPivot() end)
		return if ok and pivot then pivot.Position else nil
	end
	return nil
end
-- In reach the way both sides measure: the engine (prompt point ≤ reach) and
-- the server (ancestor BasePart ≤ reach + 3). No character or no point: false.
function S.within(prompt)
	local _, root = character()
	local at = S.promptPoint(prompt)
	if not root or not at then return false, at end
	local reach = num(prompt.MaxActivationDistance, 10)
	if (root.Position - at).Magnitude > reach - 0.5 then return false, at end
	local base = prompt:FindFirstAncestorWhichIsA("BasePart")
	if not base or (root.Position - base.Position).Magnitude > reach + 3 - 0.5 then return false, at end
	return true, at
end
-- Holds a prompt: one hold per prompt at a time; released when the prompt
-- fires (Triggered: success, sets S.lastDriven) or the hold ends early
-- (PromptButtonHoldEnded). A safety delay only covers a prompt that vanishes.
function S.hold(prompt)
	if S.holding[prompt] then return false end
	local token = {}
	S.holding[prompt] = token
	local links = {}
	local function finish(success)
		if S.holding[prompt] ~= token then return end
		S.holding[prompt] = nil
		for _, link in ipairs(links) do pcall(function() link:Disconnect() end) end
		pcall(function() prompt:InputHoldEnd() end)
		if success then S.lastDriven = prompt end
	end
	pcall(function()
		table.insert(links, prompt.Triggered:Connect(function() finish(true) end))
		table.insert(links, prompt.PromptButtonHoldEnded:Connect(function() finish(false) end))
	end)
	if not pcall(function() prompt:InputHoldBegin() end) then finish(false) return false end
	task.delay(num(prompt.HoldDuration) + 2, function() finish(false) end)
	return true
end
-- Drives a ProximityPrompt (its server handler decides): in reach, hold it;
-- otherwise walk up (S.walkPath) and hold on arrival. Cancels combat's pending
-- walk-to-attack. Returns whether anything started.
function S.drive(prompt)
	if not prompt or not prompt.Parent or prompt.Enabled == false then return false end
	attackEvents:Fire("cancel")
	local near, at = S.within(prompt)
	if near then
		S.cancelWalk()
		return S.hold(prompt)
	end
	local _, root = character()
	if not root or not at or not prompt:FindFirstAncestorWhichIsA("BasePart") then return false end
	-- Aim for a ground spot inside reach on the player's side of the prompt.
	local flat = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
	local goal = at + dir * math.max(1.5, num(prompt.MaxActivationDistance, 10) - 2.5)
	if (root.Position - at).Magnitude > S.WALK_MAX then toast("Too far: walk closer first.") return false end
	return S.walkPath(goal, function() return prompt.Parent ~= nil and (S.within(prompt)) end, function() S.hold(prompt) end)
end
function S.walkTo(position)
	if typeof(position) ~= "Vector3" then return false end
	attackEvents:Fire("cancel")
	return S.walkPath(position)
end
function S.run(option, target)
	if not option or not target then return end
	local kind = option["local"]
	if option.prompt then
		local p = target.prompts[option.prompt]
		if p and p.instance then S.drive(p.instance) end
	elseif kind == "attack" then
		S.cancelWalk()
		attackEvents:Fire(target.model)
	elseif kind == "examine" then
		S.gameLine("examine", HD.examineText(target, Data), tok.chatAnnounce, true, true)
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
local function gamepad(kind) return kind ~= nil and string.sub(kind.Name, 1, 7) == "Gamepad" end
local MOVE_KEYS = {[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true, [Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true}
Input.InputChanged:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement then
		S.mouse = Vector2.new(input.Position.X, input.Position.Y)
		if not S.mouseMode then S.mouseMode = true end
		-- A held right button turns the camera with the cursor locked: Position
		-- stays put, so the drag is the summed Delta.
		local down = S.rightDown
		if down and typeof(input.Delta) == "Vector3" then down.moved += Vector2.new(input.Delta.X, input.Delta.Y).Magnitude end
	elseif gamepad(kind) then
		if S.mouseMode then S.mouseMode = false; S.setHover(nil) end
		if S.walking and input.KeyCode == Enum.KeyCode.Thumbstick1 and typeof(input.Position) == "Vector3" and input.Position.Magnitude > 0.5 then S.cancelWalk() end
	end
end)
Input.InputBegan:Connect(function(input, processed)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch or gamepad(kind) then
		S.mouseMode = false
		S.label.Visible = false
	end
	-- Manual movement cancels a walk-up.
	if S.walking and not processed and MOVE_KEYS[input.KeyCode] then S.cancelWalk() end
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
		elseif target and target.kind == "monster" then
			S.cancelWalk() -- combat's click attacks: no walk-up continues behind it
		end
	elseif kind == Enum.UserInputType.MouseButton2 then
		S.rightDown = {at = Vector2.new(input.Position.X, input.Position.Y), time = os.clock(), moved = 0}
	end
end)
Input.InputEnded:Connect(function(input, processed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 or not S.rightDown then return end
	local down = S.rightDown
	S.rightDown = nil
	local at = Vector2.new(input.Position.X, input.Position.Y)
	-- A click, not a camera turn: under 6 px of travel (Delta summed while held) and 0.4 s.
	if processed or down.moved >= 6 or (at - down.at).Magnitude >= 6 or os.clock() - down.time >= 0.4 then return end
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
		Font = T.font.number, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.void, ZIndex = 6,
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
		orb.value.TextSize = if o.size >= 44 then 12 else 11
		orb.value.Size = UDim2.new(1, 6, 0, if o.size >= 44 then 16 else 14)
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
		-- The whole plan in one server verb (validated like "prayer"), queued by
		-- the atlas' relay so it is never dropped behind a request in flight.
		send("prayerQuickToggle")
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
-- Has this snapshot been seen? By snapshot.seq (the server stamps each one;
-- atlas replays keep it) or, for an unstamped table, by identity.
function S.fresh(snap)
	local seq = snap.seq
	if type(seq) ~= "number" then
		if S.seen[snap] then return false end
		S.seen[snap] = true
		return true
	end
	if S.printed[seq] then return false end
	S.printed[seq] = true
	table.insert(S.printedOrder, seq)
	if #S.printedOrder > 128 then S.printed[table.remove(S.printedOrder, 1)] = nil end
	return true
end
function S.observe(snap)
	if type(snap) ~= "table" then return end
	local fresh = S.fresh(snap)
	S.snap = snap
	-- A replay (snap.replay: the atlas answering a late "snapshot" request) only
	-- sets the state: its message and pickups belong to the past.
	if fresh and not snap.replay then
		-- Pickups: the server's list (gathering, fishing, loot, kill drops only).
		local list = HD.pickupEntries(snap.pickups, Data)
		if #list > 0 then
			local now = os.clock()
			for _, d in ipairs(list) do HD.feedPush(S.feed, d.id, d.n, now, S.FEED_WINDOW, 8) end
			S.renderFeed()
			task.delay(S.FEED_LIFE + 0.1, expireFeed)
		end
		-- Game messages (drops, level-ups, notices) go to chat, segment by segment.
		-- Silent snapshots (price checks) carry their reply outside `message`.
		for _, segment in ipairs(HD.segments(snap.message)) do S.gameLine("info", segment) end
	end
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
	local window = S.chatWindow()
	S.windowX = window.x
	S.tabRow.Visible = t.w > 0 and window.open
	if t.w > 0 then
		-- Follow the real chat window's left edge (within the lane's screen room).
		local x = if window.x then math.clamp(math.floor(window.x), 0, math.max(0, L.w - t.w)) else t.x
		S.tabRow.Position, S.tabRow.Size = UDim2.fromOffset(x, t.y), UDim2.fromOffset(t.w, t.h)
		local tw = math.floor((t.w - (#HD.CHAT_TABS - 1) * t.gap) / #HD.CHAT_TABS)
		for i, name in ipairs(HD.CHAT_TABS) do
			local b = S.tabs[name]
			b.Position, b.Size = UDim2.fromOffset((i - 1) * (tw + t.gap), 0), UDim2.fromOffset(tw, t.h)
		end
	end
	if S.menu.Visible then S.closeMenu() end
end
-- The default chat window: open (enabled and not closed by the player) and its
-- left edge in pixels (nil when unknown). Polled at 1 Hz (ChatActive has no signal).
function S.chatWindow()
	local out = {open = true}
	pcall(function()
		local config = game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
		if config then
			if config.Enabled == false then out.open = false end
			local pos, size = config.AbsolutePosition, config.AbsoluteSize
			if typeof(pos) == "Vector2" and typeof(size) == "Vector2" and size.X > 0 then out.x = pos.X end
		end
	end)
	pcall(function()
		local starter = service("StarterGui")
		if starter and starter:GetCore("ChatActive") == false then out.open = false end
	end)
	return out
end
task.spawn(function()
	while true do
		task.wait(1)
		local window = S.chatWindow()
		local open = layout().chatTabs.w > 0 and window.open
		if S.tabRow.Visible ~= open or window.x ~= S.windowX then S.relayout() end
	end
end)
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

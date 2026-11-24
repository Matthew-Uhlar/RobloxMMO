--!strict
-- Tutorial coach cards (StarterPlayerScripts.IsleTutorial; docs/DEPTH-CONTRACT.md §43).
-- A guided layer over the systems that already exist; it is not a second
-- onboarding system:
--   * Coach card: snapshot.tutorial.card (derived on the SERVER from the
--     Wayfarer's Path step flags and quest progress, Data.Tutorial.current) is
--     shown as a Skyforge notification panel: chapter + progress dots, title,
--     a short instruction, the §33 quest helper's NEXT step on quest cards, and
--     buttons ("Next" on the welcome card, "Got it", "Show me" / "Pin it",
--     "Skip tutorial" behind a confirming second tap). "Got it" only collapses
--     the card (verb tutorial "dismiss:<card>"); a step card moves on only when
--     the server reports real progress, so the card sequence follows the Path.
--     Lane: Theme.hudLayout coach / coachChip (tall screens: docked left of
--     centre, under the level banner; phones: a centred card above the action
--     bar, collapsing to a 44 px chip at the top of the left column).
--   * Pointer: a pulsing ring and an arrow on the UI element the card is about
--     (sidebar Objective / Bag / Menu / Map buttons, hotbar slots, Menu tiles,
--     Journal sections, the status orbs), most specific visible target first.
--     World targets reuse the Wayfinder waypoint (LocalPlayer.WayfinderRequest):
--     set once when a new card first opens, and on "Show me".
--   * Tips: first encounters (first fight, level-up, full satchel page, night,
--     shop, quest accepted; Data.Tutorial.detectTips over snapshots and server
--     signals) shown once per account (verb tutorial "tip:<id>"; the snapshot's
--     tutorial.tips lists those already seen). Settings › Tutorial turns tips
--     off or replays the tutorial.
--   * Finale: a celebration card with the rewards summary and a claim button
--     for owed Wayfarer's Path coins (guideClaim through the atlas relay).
-- Nothing here grants anything; every verb goes through IsleActionLocal (the
-- atlas relay), and the server validates it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local C, make = T.color, T.make
local TU = Data.Tutorial

local function channel(name: string): any
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots, encounters = channel("IsleActionLocal"), channel("IsleSnapshotLocal"), channel("IsleTutorialLocal")
local function tbl(v: any): any return if type(v) == "table" then v else {} end
local function num(v: any): number return if type(v) == "number" and v == v then v else 0 end

-- The card sits under the atlas (8), satchel (9) and pickers (10); the pointer
-- ring draws above everything it points at.
local gui = make("ScreenGui", playerGui, {Name = "IsleTutorial", ResetOnSpawn = false, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local pointerGui = make("ScreenGui", playerGui, {Name = "IsleTutorialPointer", ResetOnSpawn = false, DisplayOrder = 12, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local S: any = {snap = nil, prev = nil, tut = nil, card = nil, expanded = false, tip = nil, tipQueue = {}, tipsShown = {}, skipArmed = false,
	waypointed = {}, signals = {}, target = nil, pointerKey = nil, mode = "hidden", clockAt = 0, serverTime = 0, sent = {}}
local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
local function layout() return T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled, satchelOpen = player:GetAttribute("IsleSatchelOpen") == true}) end
local function send(verb: string, item: string?)
	table.insert(S.sent, {verb, item})
	if #S.sent > 20 then table.remove(S.sent, 1) end
	actions:Fire(verb, item)
end

------------------------------------------------------------------------------
-- The card
------------------------------------------------------------------------------
local HEADER = 44
local card = T.frame(gui, {name = "CoachCard", size = UDim2.fromOffset(360, 176), transparency = 0.04, visible = false, studSize = 5})
local glow = make("UIStroke", make("Frame", card, {Name = "GlowRing", BackgroundTransparency = 1, Position = UDim2.fromOffset(-3, -3), Size = UDim2.new(1, 6, 1, 6), Active = false}),
	{Name = "Glow", Thickness = 2, Transparency = 0.45, Color = C.mint})
T.corner(glow.Parent :: any, 9)
local chapter = T.label(card, {Name = "Chapter", Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -70, 0, 14), Font = T.font.label, TextSize = 11,
	TextColor3 = C.mint, TextStrokeTransparency = 0.4, TextStrokeColor3 = C.void})
local dots = make("Frame", card, {Name = "Dots", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 7), Size = UDim2.fromOffset(10, 10)})
make("UIListLayout", dots, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center})
local title = T.label(card, {Name = "Title", Position = UDim2.fromOffset(14, 21), Size = UDim2.new(1, -70, 0, 20), Font = T.font.heading, TextSize = 16,
	TextColor3 = C.gold, TextStrokeTransparency = 0.5, TextStrokeColor3 = C.void})
local toggle = T.button(card, "–", {name = "Collapse", size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -46, 0, 0), tone = "ghost", textSize = 18})
local rule = T.rule(card, HEADER, C.frame, 10)
rule.Name = "HeaderRule"
local body = T.label(card, {Name = "Instruction", Position = UDim2.fromOffset(14, HEADER + 4), Size = UDim2.new(1, -28, 0, 60), TextWrapped = true,
	TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 13, RichText = true})
local nextLine = T.label(card, {Name = "NextStep", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 18), TextSize = 12, Font = T.font.label,
	TextColor3 = C.mint, RichText = true})
local buttons = make("Frame", card, {Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8),
	Size = UDim2.new(1, -20, 0, 44)})
local skipButton = T.button(buttons, "Skip tutorial", {name = "SkipTutorial", size = UDim2.fromOffset(104, 44), tone = "ghost", textSize = 12})
local secondary = T.button(buttons, "Show me", {name = "ShowMe", size = UDim2.fromOffset(92, 44), anchor = Vector2.new(1, 0), tone = "secondary"})
local primary = T.button(buttons, "Got it", {name = "GotIt", size = UDim2.fromOffset(92, 44), anchor = Vector2.new(1, 0), tone = "primary"})
primary.Position, secondary.Position = UDim2.new(1, 0, 0, 0), UDim2.new(1, -98, 0, 0)

-- Pointer ring + arrow (pointerGui, above every HUD layer).
local ring = make("Frame", pointerGui, {Name = "PointerRing", BackgroundTransparency = 1, Visible = false, Active = false})
T.corner(ring, 8)
local ringStroke = make("UIStroke", ring, {Name = "Pulse", Color = C.gold, Thickness = 3, Transparency = 0.1})
local arrow = T.label(pointerGui, {Name = "PointerArrow", Text = "▼", Font = T.font.heading, TextSize = 26, TextColor3 = C.gold, Visible = false,
	TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.1, TextStrokeColor3 = C.void, Size = UDim2.fromOffset(32, 30)})
local pulse: any = nil -- the looping ring tween (nil while still / hidden)
local function setPulse(on: boolean)
	local want = on and not T.reducedMotion(player)
	if want == (pulse ~= nil) then return end
	if pulse then
		pcall(function() pulse:Cancel() end)
		pulse = nil
		ringStroke.Transparency, ringStroke.Thickness = 0.1, 3
	end
	if want then
		pcall(function()
			pulse = TweenService:Create(ringStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.65, Thickness = 5})
			pulse:Play()
		end)
	end
end

------------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------------
local function cardDef(): any return S.card and TU.CardById[S.card] or nil end
-- Pooled dots (re-coloured only when the index / total change).
local dotPool: any = {}
local function paintDots(index: number, total: number)
	local key = index .. "/" .. total
	if S.dotsKey == key then return end
	S.dotsKey = key
	for i = 1, math.max(total, #dotPool) do
		local d = dotPool[i]
		if not d and i <= total then
			d = make("Frame", dots, {Name = "Dot" .. i, LayoutOrder = i, Size = UDim2.fromOffset(7, 7), BorderSizePixel = 0})
			T.corner(d, 4)
			dotPool[i] = d
		end
		if d then
			d.Visible = i <= total
			d.BackgroundColor3 = if i < index then C.mint elseif i == index then C.gold else C.line
		end
	end
	dots.Size = UDim2.fromOffset(math.max(0, total * 11 - 4), 10)
end
-- What the panel shows now: a tip (it borrows the card) or the coach card.
local function content(): any
	if S.tip then
		local tip = TU.TipById[S.tip]
		return {kind = "tip", chapter = "TIP", title = tip.title, body = tip.body, pointer = tip.pointer, primary = "Got it", secondary = "Tips off"}
	end
	local def = cardDef()
	if not def then return nil end
	local t = tbl(S.tut)
	local nx = tbl(t.next)
	local out: any = {kind = "card", id = def.id, chapter = tbl(t.dots).chapter or "", title = def.title, body = def.body, pointer = def.pointer,
		dots = t.dots, primary = if def.ack then (if def.id == "complete" then "Finish" else "Next") else "Got it", skip = def.id ~= "complete"}
	if def.quest then
		local text = tostring(nx.text or "")
		if nx.blocked then
			out.next = "<b>NEXT</b>  " .. T.escape(text) .. "  <font color=\"#FF8A7A\">(" .. T.escape(tostring(nx.blocked)) .. ")</font>"
		elseif text ~= "" then
			out.next = "<b>NEXT</b>  " .. T.escape(text)
		end
		out.secondary = if nx.pinned then (if nx.specs then "Show me" else nil) else "Pin it"
	elseif def.step then
		out.secondary = if TU.specsFor(def.id) then "Show me" else nil
	elseif def.id == "complete" then
		local lines = {"<font color=\"#A9B4C0\">Rewards earned on the way:</font>"}
		for _, line in ipairs(tbl(t.rewards)) do table.insert(lines, "<font color=\"#F7C548\">◆</font> " .. T.escape(tostring(line))) end
		out.body = table.concat(lines, "\n")
		out.secondary = if num(t.owed) > 0 then "Claim " .. T.commas(num(t.owed)) .. " coins" else nil
	end
	return out
end
local function specsNow(): any
	local def = cardDef()
	if not def then return nil end
	if def.quest then return tbl(tbl(S.tut).next).specs end
	return TU.specsFor(def.id)
end
local function waypoint()
	local specs = specsNow()
	local def = cardDef()
	if type(specs) ~= "table" or #specs == 0 or not def then return end
	local request = player:FindFirstChild("WayfinderRequest")
	if request then pcall(function() (request :: any):Fire(specs, def.title) end) end
end

------------------------------------------------------------------------------
-- Visibility: other windows that own the screen hide the card (the pointer
-- stays, so it can point into the atlas: Menu tiles, Journal sections).
------------------------------------------------------------------------------
local function shown(object: any): boolean
	if not object then return false end
	local o = object
	while o and o ~= playerGui do
		if o:IsA("ScreenGui") then return o.Enabled ~= false end
		if o:IsA("GuiObject") and o.Visible == false then return false end
		o = o.Parent
	end
	return o == playerGui
end
local function guiNamed(name: string): any return playerGui:FindFirstChild(name) end
local function covered(): boolean
	local atlas = guiNamed("AetherAtlas")
	if atlas and shown(atlas:FindFirstChild("Atlas")) then return true end
	local folk = guiNamed("TownsfolkDialogue")
	if folk and shown(folk:FindFirstChild("Dialogue")) then return true end
	local hud = guiNamed("IsleHud")
	if hud and (shown(hud:FindFirstChild("ChartShade")) or shown(hud:FindFirstChild("SatchelShade"))) then return true end
	if player:GetAttribute("IslandBuilding") then return true end
	return false
end
local function trackersShown(): boolean
	local atlas = guiNamed("AetherAtlas")
	if not atlas then return false end
	return shown(atlas:FindFirstChild("CourseTracker")) or shown(atlas:FindFirstChild("TrapTracker"))
end

------------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------------
local render: () -> ()
render = function()
	local c = content()
	local L = layout()
	if not c or covered() then
		card.Visible = false
		S.mode = if c then "covered" else "hidden"
		return
	end
	chapter.Text = c.chapter
	title.Text = c.title
	local d = tbl(c.dots)
	if c.kind == "card" and num(d.total) > 1 then
		paintDots(num(d.index), num(d.total))
		dots.Visible = true
		chapter.Text = c.chapter .. "  " .. num(d.index) .. "/" .. num(d.total)
	else
		dots.Visible = false
	end
	glow.Color = if c.kind == "tip" then C.gold elseif c.id == "complete" then C.gold else C.mint
	local expanded = S.expanded or c.kind == "tip"
	local rect
	if expanded then
		rect = L.coach
		S.mode = if L.coach.modal then "modal" else "docked"
	else
		rect = L.coachChip
		-- The chip yields the left column to the lap / trap trackers on phones, and
		-- hides when a docked satchel leaves it no room (the sidebar Objective stays).
		if rect.w < 160 or (L.short and trackersShown()) then
			card.Visible = false
			S.mode = "yield"
			return
		end
		S.mode = "chip"
	end
	card.Position, card.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, if expanded then rect.h else HEADER)
	-- Chapter line: the dots sit right-aligned before the collapse button; on a
	-- narrow card they give way to the chapter text (which keeps its "n/N").
	local dotsW = if dots.Visible then dots.Size.X.Offset + 10 else 0
	if rect.w - 52 - dotsW - 14 < 150 then dots.Visible, dotsW = false, 0 end
	dots.Visible = dots.Visible and expanded
	chapter.Size = UDim2.new(0, rect.w - 52 - (if dots.Visible then dotsW else 0) - 14, 0, 14)
	dots.Position = UDim2.fromOffset(rect.w - 52 - dotsW + 4, 7)
	-- The chip names the tutorial and the step count only (the title says the rest).
	if not expanded and c.kind == "card" then chapter.Text = "TUTORIAL" .. (if num(d.total) > 1 then "  " .. num(d.index) .. "/" .. num(d.total) else "") end
	toggle.Text = if expanded then "–" else "+"
	toggle.Visible = c.kind ~= "tip"
	title.Size = UDim2.new(1, if c.kind == "tip" then -28 else -70, 0, 20)
	rule.Visible, body.Visible, buttons.Visible = expanded, expanded, expanded
	nextLine.Visible = expanded and c.next ~= nil
	if expanded then
		body.Text = c.body
		body.TextSize = if L.short then 12 else 13
		local below = 8 + 44 + 6 + (if c.next then 20 else 0)
		body.Size = UDim2.new(1, -28, 0, math.max(16, rect.h - HEADER - 4 - below))
		nextLine.Text = c.next or ""
		nextLine.Position = UDim2.new(0, 14, 1, -(8 + 44 + 6 + 18))
		primary.Text = c.primary
		secondary.Visible = c.secondary ~= nil
		secondary.Text = c.secondary or ""
		local narrow = rect.w < 340
		local bw = if narrow then 80 else 92
		primary.Size, secondary.Size = UDim2.fromOffset(bw, 44), UDim2.fromOffset(if c.secondary and #c.secondary > 10 then bw + 36 else bw, 44)
		secondary.Position = UDim2.new(1, -(bw + 6), 0, 0)
		skipButton.Visible = c.skip == true
		skipButton.Text = if S.skipArmed then "Confirm skip" else "Skip tutorial"
		skipButton.Size = UDim2.fromOffset(if narrow then 88 else 104, 44)
		if c.kind == "tip" then
			-- Tips: "Tips off" sits where Skip would.
			skipButton.Visible = false
		end
	end
	card.Visible = true
end
S.render = render

------------------------------------------------------------------------------
-- Pointer placement (every ~0.1 s): the most specific visible target.
------------------------------------------------------------------------------
local SIDEBAR = {objective = "Goal", menu = "AtlasButton", satchel = "SatchelButton", chart = "ChartButton", clock = "Clock"}
local function resolve(key: string): any
	local atlas = guiNamed("AetherAtlas")
	local sidebarName = SIDEBAR[key]
	if sidebarName then
		local side = atlas and atlas:FindFirstChild("Sidebar")
		return side and side:FindFirstChild(sidebarName, true)
	end
	local slot = string.match(key, "^hotbar:(%d)$")
	if slot then
		local bar = guiNamed("IsleHotbar")
		return bar and bar:FindFirstChild("Slot" .. slot, true)
	end
	if key == "orbs" then
		local overlay = guiNamed("IsleOverlay")
		return overlay and (overlay:FindFirstChild("OrbHealth", true) or overlay:FindFirstChild("StatusOrbs", true))
	end
	return atlas and atlas:FindFirstChild(key, true)
end
-- The card's targets (a collapsed card keeps pointing; a covered one points
-- into the window that covers it). Resolved in full at most twice a second or
-- when asked (a new card, a window opened or closed); in between only the ring
-- follows the cached target.
local function pointerKeys(): any
	if S.tip then return tbl(TU.TipById[S.tip]).pointer or {} end
	local def = cardDef()
	return if def then def.pointer else {}
end
local function placePointer(cheap: boolean?)
	local target, key = S.target, S.pointerKey
	if not cheap or not target or os.clock() - (S.resolvedAt or 0) > 0.5 or not shown(target) then
		target, key = nil, nil
		local atlas = guiNamed("AetherAtlas")
		local atlasOpen = atlas ~= nil and shown(atlas:FindFirstChild("Atlas"))
		for _, k in ipairs(pointerKeys()) do
			-- Atlas tiles / sections exist only while the atlas shows: skip the search otherwise.
			local inAtlas = SIDEBAR[k] == nil and string.match(k, "^hotbar:") == nil and k ~= "orbs"
			if atlasOpen or not inAtlas then
				local o = resolve(k)
				if o and shown(o) then target, key = o, k; break end
			end
		end
		S.resolvedAt = os.clock()
	end
	S.target, S.pointerKey = target, key
	if not target then
		ring.Visible, arrow.Visible = false, false
		setPulse(false)
		return
	end
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	-- Pointer coordinates live in their own ScreenGui; both share the same inset.
	local pad = 5
	ring.Position = UDim2.fromOffset(pos.X - pad, pos.Y - pad)
	ring.Size = UDim2.fromOffset(size.X + 2 * pad, size.Y + 2 * pad)
	ring.Visible = true
	-- The arrow comes from the open side: from the left of right-hand targets
	-- (sidebar), the right of left-hand ones (minimap, orbs), else from above /
	-- below (hotbar, centred atlas tiles), so it never covers a neighbour.
	local view = screen()
	local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
	if cx > view.X * 0.62 then
		arrow.Text = "▶"
		arrow.Position = UDim2.fromOffset(pos.X - pad - 34, cy - 15)
	elseif cx < view.X * 0.3 then
		arrow.Text = "◀"
		arrow.Position = UDim2.fromOffset(pos.X + size.X + pad + 2, cy - 15)
	elseif cy < view.Y / 2 then
		arrow.Text = "▲"
		arrow.Position = UDim2.fromOffset(cx - 16, pos.Y + size.Y + pad + 2)
	else
		arrow.Text = "▼"
		arrow.Position = UDim2.fromOffset(cx - 16, pos.Y - pad - 32)
	end
	arrow.Visible = true
	setPulse(true)
end
S.placePointer = placePointer

------------------------------------------------------------------------------
-- Snapshots: the card follows server progress; tips fire on first encounters.
------------------------------------------------------------------------------
local function tipsAllowed(t: any): boolean
	return t.off ~= true and t.vet ~= true
end
local function showTip()
	-- Tips wait while the welcome card is up (a first join at night, a full satchel…).
	if S.tip or #S.tipQueue == 0 or S.card == "welcome" then return end
	local id = table.remove(S.tipQueue, 1)
	S.tip = id
	S.tipsShown[id] = true
	send("tutorial", "tip:" .. id) -- recorded once per account when it is shown
	local mine = id
	task.delay(14, function() if S.tip == mine then S.tip = nil; showTip(); render(); placePointer() end end)
end
local function queueTips(list: any)
	local t = tbl(S.tut)
	if not tipsAllowed(t) then return end
	local seen = {}
	for _, id in ipairs(tbl(t.tips)) do seen[id] = true end
	for _, id in ipairs(list) do
		if TU.TipById[id] and not seen[id] and not S.tipsShown[id] and not table.find(S.tipQueue, id) then table.insert(S.tipQueue, id) end
	end
end
local function nightNow(): boolean
	if S.serverTime <= 0 then return false end
	local clock = T.isleClock(S.serverTime + (os.clock() - S.clockAt), Data)
	return clock ~= nil and clock.night == true
end
local function observe(snap: any)
	if type(snap) ~= "table" or type(snap.tutorial) ~= "table" then return end
	local t = snap.tutorial
	local before = S.card
	S.prev, S.snap, S.tut = S.snap, snap, t
	local events = tbl(snap.events)
	if num(events.serverTime) > 0 then S.serverTime, S.clockAt = num(events.serverTime), os.clock() end
	S.card = if type(t.card) == "string" and TU.CardById[t.card] then t.card else nil
	if S.card ~= before then
		-- A new card opens (unless already read: rejoin resumes it collapsed) and
		-- lights its world target once this session.
		S.expanded = S.card ~= nil and t.read ~= true
		S.skipArmed = false
		if S.card and S.expanded and not S.waypointed[S.card] then
			S.waypointed[S.card] = true
			waypoint()
		end
	end
	-- Signals since the last snapshot (fight, shop) plus night from the isle clock.
	local signals = S.signals
	S.signals = {}
	signals.night = nightNow()
	-- Snapshot fallback for a fight: the bestiary / kill count rose.
	if S.prev and num(snap.kills) > num(S.prev.kills) then signals.fight = true end
	queueTips(TU.detectTips(S.prev, snap, signals))
	showTip()
	render()
	placePointer()
end
S.observe = observe
if snapshots.Event then snapshots.Event:Connect(observe) end
task.spawn(function()
	local update = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if update then (update :: any).OnClientEvent:Connect(observe) end
end)
-- First fight: a hit this player landed on a creature (combat.server.lua "hit").
task.spawn(function()
	local fx = ReplicatedStorage:WaitForChild("IsleCombatFx", 30)
	if not fx then return end
	(fx :: any).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind ~= "hit" or type(payload) ~= "table" or payload.attacker ~= player.UserId then return end
		local model = payload.model
		local ok, id = pcall(function() return model and model:GetAttribute("MonsterId") end)
		if ok and id ~= nil then
			S.signals.fight = true
			queueTips({"fight"})
			showTip()
			render()
		end
	end)
end)
-- Other scripts may report encounters (e.g. IsleTutorialLocal:Fire("shop")).
if encounters.Event then
	encounters.Event:Connect(function(kind: any)
		if kind == "shop" then queueTips({"shop"}); showTip(); render(); placePointer() end
	end)
end
-- First shop: a townsfolk dialogue listing priced offers.
local function shopOpen(): boolean
	local folk = guiNamed("TownsfolkDialogue")
	local box = folk and folk:FindFirstChild("Dialogue")
	if not shown(box) then return false end
	for _, o in ipairs(box:GetDescendants()) do
		if o:IsA("TextButton") and o.Visible ~= false and string.find(string.lower(o.Text), "coins", 1, true) then return true end
	end
	return false
end

------------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------------
primary.Activated:Connect(function()
	if S.tip then
		S.tip = nil
		showTip()
		render(); placePointer()
		return
	end
	local def = cardDef()
	if not def then return end
	if def.ack then
		send("tutorial", "next:" .. def.id)
	else
		send("tutorial", "dismiss:" .. def.id)
	end
	S.expanded = false
	render(); placePointer()
end)
secondary.Activated:Connect(function()
	if S.tip then
		send("tutorial", "tips:off")
		S.tip, S.tipQueue = nil, {}
		render(); placePointer()
		return
	end
	local def = cardDef()
	if not def then return end
	local nx = tbl(tbl(S.tut).next)
	if def.id == "complete" then
		if num(tbl(S.tut).owed) > 0 then send("guideClaim", nil) end
	elseif def.quest and not nx.pinned then
		send("helperPin", if def.quest == "contract" then "contract" else "quest:" .. def.quest)
	else
		waypoint()
	end
end)
skipButton.Activated:Connect(function()
	if not S.skipArmed then
		S.skipArmed = true
		render()
		task.delay(4, function() if S.skipArmed then S.skipArmed = false; render() end end)
		return
	end
	S.skipArmed = false
	send("tutorial", "skip")
	S.expanded = false
	render()
end)
toggle.Activated:Connect(function()
	S.expanded = not S.expanded
	render(); placePointer()
end)
-- The chip itself (collapsed header) opens the card on a click / tap.
card.InputBegan:Connect(function(input: any)
	if S.expanded or S.tip then return end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		S.expanded = true
		render(); placePointer()
	end
end)

------------------------------------------------------------------------------
-- Ticks: the pointer follows its target; covering windows and night / shop are
-- re-checked a few times a second (no per-frame allocation).
------------------------------------------------------------------------------
local acc, slow = 0, 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	slow += dt
	if acc < 0.1 then return end
	acc = 0
	if S.card or S.tip then
		-- Re-render only when a covering window or the phone trackers change.
		local cov, trk = covered(), trackersShown()
		if cov ~= S.wasCovered or trk ~= S.wasTrackers then
			S.wasCovered, S.wasTrackers = cov, trk
			render()
			placePointer()
		else
			placePointer(true)
		end
	elseif ring.Visible then
		placePointer() -- nothing left to point at: hides the ring
	end
	if slow >= 1 then
		slow = 0
		if S.tut and tipsAllowed(S.tut) then
			local list = {}
			if nightNow() then table.insert(list, "night") end
			if shopOpen() then table.insert(list, "shop") end
			if #list > 0 then queueTips(list); showTip(); render(); placePointer() end
		end
	end
end)
for _, attr in ipairs({"IsleSatchelOpen", "IslandBuilding", "IsleSettingReducedMotion"}) do
	player:GetAttributeChangedSignal(attr):Connect(function() render(); placePointer() end)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() render(); placePointer() end)

-- Test / tooling hook (verify-tutorial, tools/render-ui): the live state table.
local api = make("BindableFunction", player, {Name = "IsleTutorialApi"})
api.OnInvoke = function(cmd: any)
	if cmd == "state" then return S end
	return nil
end

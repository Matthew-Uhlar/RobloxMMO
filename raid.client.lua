-- Raid client (StarterPlayerScripts.IsleRaid; docs/DEPTH-CONTRACT.md §38).
--   * Party board: opens at the Undertide portal (server attribute
--     RaidPortalUntil) or while in a party (RaidLobby). Lists open parties
--     (workspace attribute RaidLobbies), hosts (normal / Challenge Mode),
--     joins, readies, toggles Challenge Mode (leader), begins (leader), leaves.
--   * Raid HUD: while RaidRun is set, the room card from RaidHud ("k=v;...":
--     room, timers, team / personal points, deaths), the encounter's health,
--     phase, stance and the next stance (pray to match), the puzzle's state
--     (glyph sequence, seal round, valves), the resource quota, and the team's
--     supplies with Eat / Drink buttons (verb raidUse).
--   * Raid Log: KC (normal / Challenge), personal bests per party size, points
--     records, uniques found, titles (Wear: verb raidTitle) and recent runs,
--     from snapshot.raids. Toasts from RaidNotice.
-- Every action is a server verb relayed through the atlas (IsleActionLocal);
-- the server validates everything. Nothing here grants anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local RD = Data.Raids
local C, make = T.color, T.make

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots = channel("IsleActionLocal"), channel("IsleSnapshotLocal")
local function send(verb, item) actions:Fire(verb, item) end
local function parse(text)
	local out = {}
	for pair in tostring(text or ""):gmatch("[^;]+") do
		local k, v = pair:match("^(%w+)=(.*)$")
		if k then out[k] = v end
	end
	return out
end
local function serverNow()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	return if ok then t else os.time()
end
local function fmt(s)
	s = math.max(0, math.floor(tonumber(s) or 0))
	return string.format("%d:%02d", s // 60, s % 60)
end
local function compact() local cam = workspace.CurrentCamera; return Input.TouchEnabled or (cam and cam.ViewportSize.X < 900) end

local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleRaid", ResetOnSpawn = false, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local S = {snap = nil, boardClosed = false, logOpen = false}

------------------------------------------------------------------------------
-- Toasts (RaidNotice)
------------------------------------------------------------------------------
local toast = T.frame(gui, {name = "RaidToast", size = UDim2.fromOffset(420, 40), anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 92),
	ornate = false, rimThickness = 1.5, visible = false, transparency = 0.1})
local toastText = T.label(toast, {Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center, Font = T.font.label, TextSize = T.text.label, TextColor3 = Color3.fromHex("BFFFF0")})
local toastSeq = 0
local function showToast(text)
	toastSeq += 1
	local mine = toastSeq
	toastText.Text = text
	toast.Size = UDim2.fromOffset(if compact() then 320 else 420, if #text > 70 then 52 else 40)
	toast.Visible = true
	task.delay(4.5, function() if toastSeq == mine then toast.Visible = false end end)
end
player:GetAttributeChangedSignal("RaidNoticeCount"):Connect(function()
	local text = player:GetAttribute("RaidNotice")
	if type(text) == "string" and text ~= "" then showToast(text) end
end)

------------------------------------------------------------------------------
-- Party board
------------------------------------------------------------------------------
local board, boardBody = T.frame(gui, {name = "RaidBoard", title = "THE UNDERTIDE VAULTS", size = UDim2.fromOffset(380, 360),
	anchor = Vector2.new(0, 0.5), position = UDim2.new(0, 16, 0.5, 0), visible = false})
local boardClose = T.button(board, "×", {name = "Close", size = UDim2.fromOffset(26, 22), position = UDim2.new(1, -32, 0, 3), tone = "ghost"})
boardClose.Activated:Connect(function() S.boardClosed = true; board.Visible = false end)
local boardInfo = T.label(boardBody, {Name = "Info", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 34), TextWrapped = true,
	TextSize = T.text.small, TextColor3 = C.dim, Text = "Combat " .. RD.COMBAT .. " · " .. RD.MIN_PARTY .. "–" .. RD.MAX_PARTY .. " raiders · rooms vary every run."})
local boardList = make("ScrollingFrame", boardBody, {Name = "List", Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -20, 1, -98),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", boardList, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
local boardActions = make("Frame", boardBody, {Name = "Actions", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -48), Size = UDim2.new(1, -20, 0, 40)})
make("UIListLayout", boardActions, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
end
local function action(caption, tone, fn, width)
	local b = T.button(boardActions, caption, {size = UDim2.fromOffset(width or 84, 38), tone = tone})
	b.Activated:Connect(fn)
	return b
end
local function row(parent, order, height)
	local f = make("Frame", parent, {Name = "Row" .. order, LayoutOrder = order, BackgroundColor3 = C.inset, BackgroundTransparency = 0.25,
		BorderSizePixel = 0, Size = UDim2.new(1, -6, 0, height or 40)})
	T.corner(f, 5)
	return f
end
local function drawBoard()
	local lobby = parse(player:GetAttribute("RaidLobby"))
	local run = player:GetAttribute("RaidRun")
	local portalUntil = player:GetAttribute("RaidPortalUntil")
	local atPortal = type(portalUntil) == "number" and portalUntil > serverNow()
	local inLobby = lobby.id ~= nil
	local show = (inLobby or atPortal) and not (type(run) == "string" and run ~= "") and not S.boardClosed
	board.Visible = show
	if not show then S.boardSig = nil return end
	local sig = tostring(player:GetAttribute("RaidLobby")) .. "|" .. tostring(workspace:GetAttribute("RaidLobbies")) .. "|" .. tostring(inLobby)
	if sig == S.boardSig then return end -- the 1 s portal check redraws only on a change
	S.boardSig = sig
	clear(boardList)
	clear(boardActions)
	if inLobby then
		boardInfo.Text = "Party " .. lobby.id .. " · led by " .. tostring(lobby.host) .. " · " .. tostring(lobby.n) .. "/" .. tostring(lobby.max)
			.. (if lobby.cm == "1" then " · CHALLENGE MODE" else "") .. "\nBegin needs " .. tostring(lobby.min) .. "+ raiders, all ready (*), at the portal."
		local i = 0
		for name in tostring(lobby.members or ""):gmatch("[^,]+") do
			i += 1
			local r = row(boardList, i, 30)
			local ready = name:sub(-1) == "*"
			T.label(r, {Text = (if ready then "✔  " else "…  ") .. name:gsub("%*$", ""), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0),
				TextColor3 = if ready then C.mint else C.dim, Font = T.font.label})
		end
		local host = lobby.hostMe == "1"
		action(if lobby.ready == "1" then "Unready" else "Ready", if lobby.ready == "1" then "ghost" else "selected", function() send("raidReady") end, 76).Visible = not host
		if host then
			action(if lobby.cm == "1" then "CM: on" else "CM: off", if lobby.cm == "1" then "selected" else "ghost", function() send("raidChallenge", if lobby.cm == "1" then "off" else "on") end, 76)
			action("Begin", "primary", function() send("raidStart") end, 84)
		end
		action("Leave", "danger", function() send("raidLeave") end, 70)
	else
		boardInfo.Text = "Combat " .. RD.COMBAT .. " · " .. RD.MIN_PARTY .. "–" .. RD.MAX_PARTY .. " raiders · two guardians, a puzzle, a supply room, then the Regent."
		local list = tostring(workspace:GetAttribute("RaidLobbies") or "")
		local i = 0
		for entry in list:gmatch("[^;]+") do
			local id, host, n, cm = entry:match("^([^|]+)|([^|]*)|(%d+)|(%d)$")
			if id then
				i += 1
				local r = row(boardList, i, 40)
				T.label(r, {Text = host .. "'s party  ·  " .. n .. "/" .. RD.MAX_PARTY .. (if cm == "1" then "  ·  CM" else ""), Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(1, -100, 1, 0), Font = T.font.label, TextColor3 = if cm == "1" then C.gold else C.text})
				local join = T.button(r, "Join", {size = UDim2.fromOffset(74, 32), position = UDim2.new(1, -80, 0.5, 0), anchor = Vector2.new(0, 0.5), tone = "selected"})
				join.Activated:Connect(function() send("raidJoin", id) end)
			end
		end
		if i == 0 then
			local r = row(boardList, 1, 40)
			T.label(r, {Text = "No parties yet. Host one and gather your crew.", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextColor3 = C.dim})
		end
		action("Host", "primary", function() send("raidHost", "normal") end, 84)
		action("Host CM", "selected", function() send("raidHost", "challenge") end, 92)
		action("Raid Log", "ghost", function() S.logOpen = true; S.drawLog() end, 92)
	end
end
for _, attr in ipairs({"RaidLobby", "RaidRun", "RaidPortalUntil"}) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		if attr == "RaidPortalUntil" or attr == "RaidLobby" then S.boardClosed = false end
		drawBoard()
	end)
end
workspace:GetAttributeChangedSignal("RaidLobbies"):Connect(drawBoard)

------------------------------------------------------------------------------
-- Raid HUD
------------------------------------------------------------------------------
local hud, hudBody = T.frame(gui, {name = "RaidHud", size = UDim2.fromOffset(300, 214), anchor = Vector2.new(1, 0),
	position = UDim2.new(1, -16, 0, 132), visible = false, ornate = false, transparency = 0.12})
local hudTitle = T.label(hudBody, {Name = "Room", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Font = T.font.heading,
	TextSize = T.text.heading, TextColor3 = C.gold, TextStrokeTransparency = 0.5})
local hudSub = T.label(hudBody, {Name = "Sub", Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 16), TextSize = T.text.small, TextColor3 = C.dim})
local hudBar = T.bar(hudBody, {name = "Health", position = UDim2.fromOffset(10, 46), size = UDim2.new(1, -20, 0, 16), color = C.health})
local hudLines = T.label(hudBody, {Name = "Lines", Position = UDim2.fromOffset(10, 66), Size = UDim2.new(1, -20, 0, 92), TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top, TextSize = T.text.body, RichText = true})
local hudPoints = T.label(hudBody, {Name = "Points", Position = UDim2.fromOffset(10, 158), Size = UDim2.new(1, -20, 0, 16), TextSize = T.text.small,
	TextColor3 = C.mint, Font = T.font.label})
local foodButton = T.button(hudBody, "Food", {name = "RaidFood", size = UDim2.new(0.5, -14, 0, 30), position = UDim2.new(0, 10, 1, -36), tone = "secondary"})
local potionButton = T.button(hudBody, "Draught", {name = "RaidPotion", size = UDim2.new(0.5, -14, 0, 30), position = UDim2.new(0.5, 4, 1, -36), tone = "selected"})
foodButton.Activated:Connect(function() send("raidUse", "food") end)
potionButton.Activated:Connect(function() send("raidUse", "potion") end)
local STYLE = {melee = "MELEE · Ward of Fangs", ranged = "RANGED · Ward of Quills", magic = "MAGIC · Ward of Glyphs"}
local function drawHud()
	local h = parse(player:GetAttribute("RaidHud"))
	local run = player:GetAttribute("RaidRun")
	hud.Visible = type(run) == "string" and run ~= "" and h.run ~= nil
	if not hud.Visible then return end
	hud.Size = UDim2.fromOffset(if compact() then 250 else 300, 214)
	hudTitle.Text = tostring(h.name) .. "  " .. tostring(h.room)
	local timer = if h["in"] then "starts in " .. h["in"] .. "s" elseif h.exit then "returning in " .. h.exit .. "s" elseif h.ends then fmt(h.ends) .. " left" else ""
	hudSub.Text = string.upper(tostring(h.kind)) .. (if h.cm == "1" then " · CHALLENGE" else "") .. " · " .. fmt(h.t) .. (if h.par then " / par " .. fmt(h.par) else "") .. (if timer ~= "" then " · " .. timer else "")
	local lines = {}
	local hp, maxHp = tostring(h.hp or ""):match("^(%d+)/(%d+)$")
	hudBar.Visible = hp ~= nil
	if hp then
		T.setBar(hudBar, tonumber(hp) / math.max(1, tonumber(maxHp)), T.commas(tonumber(hp)) .. " / " .. T.commas(tonumber(maxHp)))
		table.insert(lines, "<b>" .. tostring(h.pname) .. "</b> · weak to " .. tostring(h.weak))
		table.insert(lines, "Stance: " .. (STYLE[h.style] or tostring(h.style)) .. (if h.next and h.next ~= h.style then "  →  " .. string.upper(h.next) .. " in " .. tostring(h.sin) else ""))
		if h.seal and h.seal ~= "0" then table.insert(lines, '<font color="#FFD86B">Sealed: break seal ' .. h.seal .. ' next</font>') end
		if h.ward == "1" then table.insert(lines, '<font color="#FF9A8C">Warded: slay the adds</font>') end
		table.insert(lines, if h.enr == "1" then '<font color="#FF6B5A">ENRAGED</font>' else "Enrage in " .. fmt(h.enrage))
	elseif h.seq then
		local step = tonumber(h.step) or 0
		local parts = {}
		local i = 0
		for g in tostring(h.seq):gmatch("[^,]+") do
			i += 1
			table.insert(parts, if i <= step then '<font color="#6FE3C8">' .. g .. "</font>" elseif i == step + 1 then "<b>" .. g .. "</b>" else g)
		end
		table.insert(lines, "Chant: " .. table.concat(parts, " · "))
		table.insert(lines, "Press the glyph plates in this order.")
	elseif h.round then
		table.insert(lines, "Seal round " .. h.round .. " · held " .. tostring(h.held))
		table.insert(lines, "Stand on every lit seal at once for " .. RD.SEAL_HOLD .. "s.")
	elseif h.valves then
		local marks = {}
		for b in tostring(h.valves):gmatch(".") do table.insert(marks, if b == "1" then '<font color="#6FE3A0">●</font>' else '<font color="#E86A5A">○</font>') end
		table.insert(lines, "Valves: " .. table.concat(marks, " "))
		table.insert(lines, "Turning a valve also turns both neighbours.")
	elseif h.made then
		table.insert(lines, "Supplies made: " .. h.made)
		table.insert(lines, "Party stock: " .. tostring(h.stock or ""):gsub(",", " · "))
		table.insert(lines, "Gather 2, then brew or cook at the stations.")
	end
	hudLines.Text = table.concat(lines, "\n")
	hudPoints.Text = "Points " .. T.commas(tonumber(h.me) or 0) .. " · team " .. T.commas(tonumber(h.team) or 0) .. " · deaths " .. tostring(h.deaths or 0)
	foodButton.Text = tostring(h.foodName or "Food") .. " (" .. tostring(h.food or 0) .. ")"
	potionButton.Text = tostring(h.potionName or "Draught") .. " (" .. tostring(h.potion or 0) .. ")"
end
player:GetAttributeChangedSignal("RaidHud"):Connect(drawHud)
player:GetAttributeChangedSignal("RaidRun"):Connect(drawHud)

------------------------------------------------------------------------------
-- Raid Log
------------------------------------------------------------------------------
local log, logBody = T.frame(gui, {name = "RaidLog", title = "RAID LOG · UNDERTIDE VAULTS", size = UDim2.fromOffset(460, 420),
	anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), visible = false})
local logClose = T.button(log, "×", {name = "Close", size = UDim2.fromOffset(26, 22), position = UDim2.new(1, -32, 0, 3), tone = "ghost"})
logClose.Activated:Connect(function() S.logOpen = false; log.Visible = false end)
local logList = make("ScrollingFrame", logBody, {Name = "List", Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 1, -16),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", logList, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
local function heading(order, text)
	T.label(logList, {Name = "Heading" .. order, LayoutOrder = order, Text = text, Size = UDim2.new(1, -6, 0, 20), Font = T.font.heading,
		TextColor3 = C.gold, TextSize = T.text.heading})
end
local function line(order, text, color)
	local r = row(logList, order, 26)
	T.label(r, {Text = text, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextColor3 = color or C.text, RichText = true})
	return r
end
function S.drawLog()
	log.Visible = S.logOpen
	if not S.logOpen then return end
	log.Size = if compact() then UDim2.fromOffset(340, 320) else UDim2.fromOffset(460, 420)
	clear(logList)
	local r = type(S.snap) == "table" and type(S.snap.raids) == "table" and S.snap.raids or nil
	if not r then line(1, "Open your journal to load the Raid Log.", C.dim) return end
	local o = 0
	local function n() o += 1 return o end
	heading(n(), "Kill count")
	line(n(), "Clears " .. tostring(r.kc or 0) .. " · Challenge " .. tostring(r.cm or 0) .. " · failed " .. tostring(r.fails or 0) .. " · deaths " .. tostring(r.deaths or 0))
	local best = type(r.best) == "table" and r.best or {}
	line(n(), "Best personal points " .. T.commas(best.points or 0) .. " · best team " .. T.commas(best.team or 0))
	heading(n(), "Personal bests")
	for size = RD.MIN_PARTY, RD.MAX_PARTY do
		local pb = type(r.pb) == "table" and r.pb[tostring(size)]
		local cm = type(r.pbCm) == "table" and r.pbCm[tostring(size)]
		if pb or cm then
			line(n(), size .. " raiders · " .. (if pb then fmt(pb) else "—") .. " · CM " .. (if cm then fmt(cm) .. (if cm <= RD.par(size) then " (under par " .. fmt(RD.par(size)) .. ")" else "") else "—"))
		end
	end
	heading(n(), "Uniques")
	local got = type(r.got) == "table" and r.got or {}
	for _, id in ipairs(RD.UniqueOrder) do
		local d = Data.Items[id]
		local k = tonumber(got[id]) or 0
		line(n(), (if k > 0 then "✦ " else "· ") .. d.name .. (if k > 0 then "  ×" .. k else ""), if k > 0 then T.rarity(d.rarity).color else C.faint)
	end
	local kit = tonumber(got.GildedTideKit) or 0
	line(n(), (if kit > 0 then "✦ " else "· ") .. Data.Items.GildedTideKit.name .. (if kit > 0 then "  ×" .. kit else "  (Challenge Mode under par)"), if kit > 0 then C.gold else C.faint)
	heading(n(), "Titles")
	for _, t in ipairs(RD.Titles) do
		local owned = type(r.titles) == "table" and r.titles[t.id] == true
		local rr = line(n(), t.text .. "  ·  " .. t.hint, if owned then Color3.fromHex(t.color) else C.faint)
		if owned then
			local wearing = r.title == t.id
			local b = T.button(rr, if wearing then "Hide" else "Wear", {size = UDim2.fromOffset(60, 22), position = UDim2.new(1, -64, 0.5, 0), anchor = Vector2.new(0, 0.5),
				tone = if wearing then "ghost" else "selected", textSize = T.text.small})
			b.Activated:Connect(function() send("raidTitle", if wearing then "none" else t.id) end)
		end
	end
	heading(n(), "Recent runs")
	for _, e in ipairs(type(r.log) == "table" and r.log or {}) do
		local u = e.u and Data.Items[e.u]
		line(n(), fmt(e.s) .. " · " .. tostring(e.n) .. " raiders" .. (if e.cm then " · CM" else "") .. " · " .. T.commas(e.pts or 0) .. " pts (team " .. T.commas(e.team or 0) .. ")"
			.. (if u then ' · <font color="#FF7AD9">' .. u.name .. "</font>" else ""))
	end
end
local logButton = T.button(gui, "Raid Log", {name = "RaidLogButton", size = UDim2.fromOffset(86, 26), anchor = Vector2.new(1, 0), position = UDim2.new(1, -16, 0, 100),
	tone = "ghost", textSize = T.text.small})
logButton.Visible = false
logButton.Activated:Connect(function() S.logOpen = not S.logOpen; S.drawLog() end)

------------------------------------------------------------------------------
-- Snapshots
------------------------------------------------------------------------------
local function observe(state)
	if type(state) ~= "table" or type(state.raids) ~= "table" then return end
	S.snap = state
	-- The log button appears once the journal has met the raid (a visit or a clear).
	logButton.Visible = (tonumber(state.raids.kc) or 0) > 0 or (tonumber(state.raids.portalIn) or 0) > 0 or (tonumber(state.raids.fails) or 0) > 0
	if S.logOpen then S.drawLog() end
end
if snapshots.Event then snapshots.Event:Connect(observe) end
task.spawn(function()
	local update = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if update then update.OnClientEvent:Connect(observe) end
end)
task.spawn(function()
	while true do
		task.wait(1)
		drawBoard() -- the portal window expires on the server clock
	end
end)
drawBoard()
drawHud()

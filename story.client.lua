-- The Sundered Sky, client (StarterPlayerScripts.IsleStory; docs/DEPTH-CONTRACT.md §53).
-- Cosmetic and input only; the server (Story block) decides everything.
--   * Cutscenes: when the snapshot's story.cut.seq moves past the one seen at
--     join, play Data.Story.Cutscenes[id]: camera shots between anchors, a
--     dialogue card in the speaker's colour, an NPC gesture (local Motor6D
--     Transform). Runner ST.cutStart / ST.cutStep: a Skip button (and
--     Backspace / ButtonB) ends it; so do death, a teleport, damage, a missing
--     character and the hard deadline. Movement is never disabled; every end
--     path restores the camera (CameraType Custom, subject = humanoid).
--     Journal › Story replays any unlocked cutscene (IsleStoryLocal "replay").
--   * Puzzle panel (rune lock dials, astrolabe rings, signal mirrors) opened by
--     a set piece's Study prompt (attribute StoryPuzzle) or Journal › Story
--     (IsleStoryLocal "puzzle"); every move is a storyPuzzle verb through
--     IsleActionLocal; the panel only draws the server's state.
--   * The signal-mirror beam: local Neon segments over the Mirror field from
--     the server's traced path; mirror posts turn locally to their state.
--   * Encounter strip: the boss, the rise countdown, a Leave button and the
--     lantern hint.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local PromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local make = T.make
local ST = Data.Story

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots, local_ = channel("IsleActionLocal"), channel("IsleSnapshotLocal"), channel("IsleStoryLocal")
local function tbl(v) return if type(v) == "table" then v else {} end
local function send(verb, item) actions:Fire(verb, item) end
local function reduced() return T.reducedMotion and T.reducedMotion(player) or false end

local S = {story = nil, baseSeq = nil, run = nil, puzzleOpen = nil}

local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleStory", ResetOnSpawn = false, DisplayOrder = 11,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true})

------------------------------------------------------------------------------
-- Cutscenes.
------------------------------------------------------------------------------
local card = make("Frame", gui, {Name = "CutsceneCard", Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0.8, 0, 0, 118), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0})
make("UISizeConstraint", card, {MaxSize = Vector2.new(760, 160)})
T.corner(card, 12)
local cardStroke = make("UIStroke", card, {Color = T.color.gold, Thickness = 2})
local speaker = T.label(card, {Name = "Speaker", Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -140, 0, 22), Text = "",
	Font = T.font.heading, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left})
local line = T.label(card, {Name = "Line", Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -32, 1, -46), Text = "", TextWrapped = true,
	TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top})
local skip = T.button(card, "Skip ▸", {name = "SkipButton", position = UDim2.new(1, -112, 0, 8), size = UDim2.fromOffset(100, 34)})
local title = T.label(gui, {Name = "CutsceneTitle", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(600, 34), Text = "", Font = T.font.display, TextSize = 22, TextColor3 = T.color.gold, TextStrokeTransparency = 0.4})

local Cut = {skipRequested = false, gestures = {}}
local function anchorPart(name)
	if type(name) ~= "string" then return nil end
	local islands = workspace:FindFirstChild("Islands")
	local found = islands and islands:FindFirstChild("Anchor_" .. name, true)
	if found then return found end
	if string.sub(name, 1, 4) == "NPC_" then
		local folk = workspace:FindFirstChild("Townsfolk")
		if folk then
			for _, m in ipairs(folk:GetChildren()) do
				if m:GetAttribute("TownsfolkRole") == string.sub(name, 5) then return m:FindFirstChild("HumanoidRootPart") end
			end
		end
	end
	return nil
end
local function characterParts()
	local character = player.Character
	return character, character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end
-- Camera for one shot: from the look target plus the offset, looking at it.
local function shotFrame(s)
	local target = anchorPart(s.look) or anchorPart(s.at)
	local _, _, root = characterParts()
	local focus = (target and target.Position) or (root and root.Position) or Vector3.zero
	local off = s.off or {x = 8, y = 5, z = -8}
	local eye = focus + Vector3.new(off.x, off.y, off.z)
	return CFrame.lookAt(eye, focus + Vector3.new(0, 2, 0))
end
-- NPC gestures: a local right-arm pose on the NPC's motors (never replicated).
local GESTURE = {wave = CFrame.Angles(0, 0, math.rad(150)), point = CFrame.Angles(math.rad(90), 0, 0), raise = CFrame.Angles(0, 0, math.rad(170)), bow = CFrame.Angles(math.rad(-25), 0, 0)}
local function gesture(role, name)
	local pose = GESTURE[name or ""]
	if not pose or reduced() then return end
	local folk = workspace:FindFirstChild("Townsfolk")
	if not folk then return end
	for _, m in ipairs(folk:GetChildren()) do
		if m:GetAttribute("TownsfolkRole") == role then
			local motor = if name == "bow" then m:FindFirstChild("Waist", true) else m:FindFirstChild("RightShoulder", true)
			if motor and motor:IsA("Motor6D") then
				motor.Transform = pose
				table.insert(Cut.gestures, motor)
			end
		end
	end
end
local function clearGestures()
	for _, motor in ipairs(Cut.gestures) do pcall(function() motor.Transform = CFrame.identity end) end
	table.clear(Cut.gestures)
end
local function showShot(run)
	local c = ST.Cutscenes[run.id]
	local s = c and c.shots[run.shot]
	if not s then return end
	local v = ST.Voices[s.speaker] or ST.Voices.Narrator
	speaker.Text = if v.name ~= "" then v.name .. (if v.title ~= "" then "  ·  " .. v.title else "") else ""
	speaker.TextColor3 = Color3.fromHex(v.color)
	cardStroke.Color = Color3.fromHex(v.color)
	line.Text = s.line
	line.Font = if v.voice == "narrator" then Enum.Font.BuilderSansMedium elseif v.voice == "grand" then Enum.Font.BuilderSansExtraBold else T.font.body
	clearGestures()
	if s.gesture and s.speaker then gesture(s.speaker, s.gesture) end
	local camera = workspace.CurrentCamera
	if camera then camera.CFrame = shotFrame(s) end
end
-- The one restore path every ending takes (never leaves the camera captured).
local function restore()
	clearGestures()
	card.Visible, title.Visible = false, false
	local camera = workspace.CurrentCamera
	local _, humanoid = characterParts()
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then camera.CameraSubject = humanoid end
	end
	S.run = nil
	Cut.skipRequested = false
end
function Cut.play(id)
	if not ST.Cutscenes[id] then return end
	if S.run then restore() end
	local run = ST.cutStart(id, os.clock())
	S.run = run
	local _, humanoid, root = characterParts()
	Cut.lastHealth = humanoid and humanoid.Health or 0
	Cut.lastPos = root and root.Position
	local camera = workspace.CurrentCamera
	if camera then camera.CameraType = Enum.CameraType.Scriptable end
	title.Text = string.upper(ST.Cutscenes[id].title)
	title.Visible, card.Visible = true, true
	run.shown = 0
end
skip.Activated:Connect(function() Cut.skipRequested = true end)
Input.InputBegan:Connect(function(io, processed)
	if not S.run then return end
	if io.KeyCode == Enum.KeyCode.Backspace or io.KeyCode == Enum.KeyCode.ButtonB or (not processed and io.KeyCode == Enum.KeyCode.Space) then Cut.skipRequested = true end
end)
RunService.RenderStepped:Connect(function()
	local run = S.run
	if not run then return end
	local ok, err = pcall(function()
		local _, humanoid, root = characterParts()
		local pos = root and root.Position
		local ev = {skip = Cut.skipRequested, missing = humanoid == nil or root == nil, dead = humanoid ~= nil and humanoid.Health <= 0,
			hurt = humanoid ~= nil and humanoid.Health < (Cut.lastHealth or 0) - 0.5,
			teleported = pos ~= nil and Cut.lastPos ~= nil and (pos - Cut.lastPos).Magnitude > 40}
		Cut.lastHealth = humanoid and humanoid.Health or 0
		Cut.lastPos = pos
		local _, ended = ST.cutStep(run, os.clock(), ev)
		if ended then restore() return end
		if run.shown ~= run.shot then run.shown = run.shot; showShot(run) end
	end)
	if not ok then
		warn("[Story] cutscene ended: " .. tostring(err))
		restore()
	end
end)
player.CharacterAdded:Connect(function() if S.run then restore() end end)

------------------------------------------------------------------------------
-- Puzzle panel.
------------------------------------------------------------------------------
local panel = make("Frame", gui, {Name = "PuzzlePanel", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 400), BackgroundColor3 = T.color.panel, BorderSizePixel = 0})
T.corner(panel, 12)
make("UIStroke", panel, {Color = T.color.gold, Thickness = 2})
make("UISizeConstraint", panel, {MinSize = Vector2.new(300, 300)})
local pTitle = T.label(panel, {Name = "Title", Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -70, 0, 24), Text = "", Font = T.font.heading, TextSize = 17, TextColor3 = T.color.gold, TextXAlignment = Enum.TextXAlignment.Left})
local pHint = T.label(panel, {Name = "Hint", Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 36), Text = "", TextWrapped = true, TextSize = 13, TextColor3 = T.color.dim, TextXAlignment = Enum.TextXAlignment.Left})
local close = T.button(panel, "✕", {name = "Close", position = UDim2.new(1, -46, 0, 6), size = UDim2.fromOffset(38, 34)})
local body = make("Frame", panel, {Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 74), Size = UDim2.new(1, -28, 1, -88)})
close.Activated:Connect(function() S.puzzleOpen = nil; panel.Visible = false end)
local function clear() for _, c in ipairs(body:GetChildren()) do c:Destroy() end end
local function btn(parent, caption, pos, size, fn, tone)
	local b = T.button(parent, caption, {position = pos, size = size, tone = tone})
	b.Activated:Connect(fn)
	return b
end
local RUNE_COLOR = {GaleRune = "BFE3FF", SparkRune = "FFD166", TideRune = "4FA8FF", StoneRune = "A0522D", EmberRune = "FF6B5A"}
local DIR_GLYPH = {[0] = "╱", [1] = "╲"}
local function drawPuzzle()
	local story = tbl(S.story)
	local pz = tbl(story.puzzle)
	if not S.puzzleOpen then panel.Visible = false return end
	panel.Visible = true
	clear()
	local def = ST.Puzzles[S.puzzleOpen]
	pTitle.Text = def and string.upper(def.name) or "PUZZLE"
	if pz.id ~= S.puzzleOpen then
		pHint.Text = "This puzzle is not part of your story right now. Check Journal › Story."
		return
	end
	if pz.id == "runelock" then
		local clue = {}
		for i, r in ipairs(tbl(pz.clue)) do clue[i] = i .. ": " .. ((Data.Items[r] or {}).name or r) end
		pHint.Text = "Your rubbings: " .. table.concat(clue, "   ") .. ". Each dial takes one bound rune you carry." .. (if (pz.lockIn or 0) > 0 then "  (dials resetting " .. pz.lockIn .. "s)" else "")
		for d = 1, ST.DIALS do
			local current = tbl(pz.s)[d] or ""
			T.label(body, {Position = UDim2.new(0, 0, 0, (d - 1) * 52), Size = UDim2.fromOffset(70, 40), Text = "Dial " .. d, Font = T.font.label, TextColor3 = T.color.text})
			for i, rune in ipairs(ST.RUNES) do
				local b = btn(body, string.sub((Data.Items[rune] or {}).name or rune, 1, 5), UDim2.new(0, 70 + (i - 1) * 66, 0, (d - 1) * 52), UDim2.fromOffset(62, 40),
					function() send("storyPuzzle", "runelock:set:" .. d .. ":" .. rune) end, if current == rune then "primary" else nil)
				b.TextColor3 = if current == rune then T.color.onGold else Color3.fromHex(RUNE_COLOR[rune] or "FFFFFF")
			end
		end
		btn(body, "Turn the lock", UDim2.new(0, 0, 0, ST.DIALS * 52 + 6), UDim2.fromOffset(180, 42), function() send("storyPuzzle", "runelock:try") end, "primary")
		btn(body, "Clear dials", UDim2.new(0, 190, 0, ST.DIALS * 52 + 6), UDim2.fromOffset(140, 42), function() send("storyPuzzle", "runelock:reset") end)
	elseif pz.id == "stars" then
		pHint.Text = "Turn a ring and its neighbour turns with it. Bring every ring's star to the top mark (0)."
		for i = 1, ST.RINGS do
			local stop = tonumber(tbl(pz.s)[i]) or 0
			local ring = make("Frame", body, {Name = "Ring" .. i, Position = UDim2.new(0, (i - 1) * 84, 0, 0), Size = UDim2.fromOffset(76, 76), BackgroundColor3 = T.color.inset, BorderSizePixel = 0})
			make("UICorner", ring, {CornerRadius = UDim.new(1, 0)})
			make("UIStroke", ring, {Color = if stop == 0 then T.color.mint else T.color.frame, Thickness = 2})
			local a = stop / ST.STOPS * 2 * math.pi
			local star = T.label(ring, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5 + math.sin(a) * 0.36, 0, 0.5 - math.cos(a) * 0.36, 0), Size = UDim2.fromOffset(22, 22),
				Text = "✦", TextSize = 20, TextColor3 = if stop == 0 then T.color.mint else T.color.goldSoft})
			star.TextXAlignment = Enum.TextXAlignment.Center
			btn(body, "Turn " .. i, UDim2.new(0, (i - 1) * 84, 0, 84), UDim2.fromOffset(76, 40), function() send("storyPuzzle", "stars:turn:" .. i) end)
		end
		btn(body, "Reset", UDim2.new(0, 0, 0, 140), UDim2.fromOffset(120, 40), function() send("storyPuzzle", "stars:reset") end)
	elseif pz.id == "mirrors" then
		pHint.Text = "Turn the mirrors (here or at their posts) until the beam reaches the lens." .. (if pz.lit then "  The lens is lit!" else "")
		local L = ST.Mirror
		local cell = 40
		local lit = {}
		for _, c in ipairs(tbl(pz.path)) do lit[c.x .. ":" .. c.y] = true end
		local mirrorAt, wallAt = {}, {}
		for i, m in ipairs(L.mirrors) do mirrorAt[m.x .. ":" .. m.y] = i end
		for _, w in ipairs(L.walls) do wallAt[w.x .. ":" .. w.y] = true end
		for x = 1, L.size do
			for y = 1, L.size do
				local key = x .. ":" .. y
				local mi = mirrorAt[key]
				local text = if mi then DIR_GLYPH[tonumber(tbl(pz.s)[mi]) or 0] elseif wallAt[key] then "■" elseif x == L.receiver.x and y == L.receiver.y then "◎" else ""
				local b = make("TextButton", body, {Name = "Cell" .. key, Position = UDim2.fromOffset((x - 1) * cell, (L.size - y) * cell), Size = UDim2.fromOffset(cell - 3, cell - 3),
					Text = text, Font = T.font.heading, TextSize = 22, AutoButtonColor = mi ~= nil, BorderSizePixel = 0,
					BackgroundColor3 = if lit[key] then Color3.fromHex("FFD166") else T.color.inset, TextColor3 = if lit[key] then T.color.onGold else T.color.text})
				make("UICorner", b, {CornerRadius = UDim.new(0, 4)})
				if mi then b.Activated:Connect(function() send("storyPuzzle", "mirrors:turn:" .. mi) end) end
			end
		end
		btn(body, "Reset", UDim2.fromOffset(L.size * cell + 10, 0), UDim2.fromOffset(110, 40), function() send("storyPuzzle", "mirrors:reset") end)
	end
end
PromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local id = prompt:GetAttribute("StoryPuzzle")
	if type(id) == "string" and ST.Puzzles[id] then S.puzzleOpen = id; drawPuzzle() end
end)

------------------------------------------------------------------------------
-- The signal-mirror beam (local parts over the Mirror field).
------------------------------------------------------------------------------
local Beam = {parts = {}}
local function beamClear() for _, p in ipairs(Beam.parts) do p:Destroy() end table.clear(Beam.parts) end
local function drawBeam()
	beamClear()
	local pz = tbl(tbl(S.story).puzzle)
	if pz.id ~= "mirrors" then return end
	local islands = workspace:FindFirstChild("Islands")
	local model = islands and islands:FindFirstChild("Story set piece MirrorField", true)
	local field = model and model:FindFirstChild("Mirror field")
	if not field then return end
	local L, cell = ST.Mirror, model:GetAttribute("MirrorCell") or 3
	local function at(x, y) return (field.CFrame * CFrame.new((x - (L.size + 1) / 2) * cell, 1.5, -((y - (L.size + 1) / 2) * cell))).Position end
	local prev = at(L.source.x, L.source.y)
	for _, c in ipairs(tbl(pz.path)) do
		local nextPos = at(c.x, c.y)
		local seg = Instance.new("Part")
		seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
		seg.Material, seg.Color = Enum.Material.Neon, Color3.fromHex("FFD166")
		seg.Size = Vector3.new(0.35, 0.35, (nextPos - prev).Magnitude)
		seg.CFrame = CFrame.lookAt((prev + nextPos) / 2, nextPos)
		seg.Name = "StoryBeam"
		seg.Parent = workspace.CurrentCamera
		table.insert(Beam.parts, seg)
		prev = nextPos
	end
	for _, obj in ipairs(model:GetChildren()) do
		local i = obj:GetAttribute("MirrorIndex")
		if i then
			local state = tonumber(tbl(pz.s)[i]) or 0
			local base = obj:GetAttribute("BaseCFrame")
			if typeof(base) ~= "CFrame" then base = obj.CFrame; obj:SetAttribute("BaseCFrame", base) end
			obj.CFrame = base * CFrame.Angles(0, if state == 1 then -math.pi / 4 else math.pi / 4, 0)
		end
	end
end

------------------------------------------------------------------------------
-- Encounter strip.
------------------------------------------------------------------------------
local strip = make("Frame", gui, {Name = "EncounterStrip", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.fromOffset(420, 50), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.1, BorderSizePixel = 0})
T.corner(strip, 10)
make("UIStroke", strip, {Color = Color3.fromHex("B48CFF"), Thickness = 1.5})
local stripText = T.label(strip, {Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -120, 1, 0), Text = "", TextWrapped = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left})
local leave = T.button(strip, "Leave", {name = "LeaveButton", position = UDim2.new(1, -100, 0.5, -17), size = UDim2.fromOffset(90, 34), tone = "danger"})
leave.Activated:Connect(function() send("storyLeave", nil) end)
local function drawStrip()
	local f = tbl(S.story).fight
	if type(f) ~= "table" then strip.Visible = false return end
	local def = ST.Bosses[f.boss]
	strip.Visible = true
	local text = (def and def.name or "Encounter") .. (if f.state == "warmup" then "  ·  rises in " .. (f.riseIn or 0) .. "s" else "")
	if def and def.lanterns then text ..= "\nStrike only from inside the lit lantern's glow." end
	stripText.Text = text
end

------------------------------------------------------------------------------
-- Snapshots and the Journal relay.
------------------------------------------------------------------------------
local function onSnapshot(snap)
	if type(snap) ~= "table" or type(snap.story) ~= "table" then return end
	S.story = snap.story
	local cut = tbl(S.story.cut)
	local seq = tonumber(cut.seq) or 0
	if S.baseSeq == nil then
		S.baseSeq = seq -- a rejoin never replays the last cutscene
	elseif seq > S.baseSeq then
		S.baseSeq = seq
		if type(cut.id) == "string" then Cut.play(cut.id) end
	end
	drawStrip()
	if S.puzzleOpen then drawPuzzle() end
	pcall(drawBeam)
end
snapshots.Event:Connect(onSnapshot)
local_.Event:Connect(function(kind, arg)
	if kind == "replay" and type(arg) == "string" then
		for _, id in ipairs(ST.unlockedCutscenes({ch = tbl(tbl(S.story).cur).ch or (if tbl(S.story).done then #ST.Chapters + 1 else 1), step = tbl(tbl(S.story).cur).step or 99})) do
			if id == arg then Cut.play(id) return end
		end
	elseif kind == "puzzle" and type(arg) == "string" and ST.Puzzles[arg] then
		S.puzzleOpen = arg
		drawPuzzle()
	end
end)
-- A late start asks the atlas for the latest snapshot.
task.defer(function() actions:Fire("snapshot", nil) end)

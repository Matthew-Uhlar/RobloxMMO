-- Aether Motes (Exploration & Factions team): local rendering of the hidden
-- collectibles in Data.Exploration. The server holds no mote parts; it keeps
-- positions in data and validates every pickup by distance (Explore block in
-- server.server.lua, docs/DEPTH-CONTRACT.md §24). This script:
--   * reads the found bitmap from every accepted snapshot (IsleSnapshotLocal,
--     fed by the field guide) and the Wayglass bearing from player attributes
--     MoteHint / MoteHintUntil;
--   * draws only unfound motes within Data.Exploration.RENDER_RADIUS of the
--     character (plus the bearing's target), from a small reusable pool;
--   * gives each drawn mote a local ProximityPrompt (IsleAction "moteCollect",
--     so the Gestures script plays its interact gesture) whose trigger asks the
--     field guide to send "moteCollect" (the server picks the nearest mote).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local EX = Data.Exploration
if type(EX) ~= "table" then return end
local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local snapshots, actions = channel("IsleSnapshotLocal"), channel("IsleActionLocal")
local islands = workspace:WaitForChild("Islands", 60)
if not islands then return end
local folder = Instance.new("Folder")
folder.Name = "AetherMotesLocal"
folder.Parent = workspace
local color = Color3.fromHex(EX.MOTE.color)

-- World positions (island centre + offset), resolved lazily per island.
local positions = {}
local function positionOf(mote)
	local cached = positions[mote.id]
	if cached then return cached end
	local isle = islands:FindFirstChild(mote.isle)
	local center = isle and isle:GetAttribute("IslandCenter")
	if typeof(center) ~= "Vector3" then return nil end
	cached = center + Vector3.new(mote.at[1], mote.at[2], mote.at[3])
	positions[mote.id] = cached
	return cached
end

local found = nil -- bitmap string from snapshot.exploration.motes.found (nil until synced)
local pending = {} -- [id] = os.clock() of a local pickup request (hidden for a moment)
snapshots.Event:Connect(function(snapshot)
	local ex = type(snapshot) == "table" and snapshot.exploration
	local motes = type(ex) == "table" and ex.motes
	if type(motes) == "table" and type(motes.found) == "string" then found = motes.found end
end)
actions:Fire("snapshot") -- a late start asks the field guide for the latest snapshot

local function isFound(mote)
	return found == nil or string.sub(found, mote.index, mote.index) == "1"
end

-- Pool of drawn motes: [id] = {part, prompt, beacon}.
local drawn = {}
local spare = {}
local function build()
	local part = Instance.new("Part")
	part.Name = "AetherMote"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.1, 1.1, 1.1)
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.15
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Gather", EX.MOTE.name
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.4, 8, false
	prompt:SetAttribute("IsleAction", "moteCollect")
	prompt.Parent = part
	local beacon = Instance.new("BillboardGui")
	beacon.Name = "Bearing"
	beacon.AlwaysOnTop, beacon.LightInfluence, beacon.Enabled = true, 0, false
	beacon.Size = UDim2.fromOffset(150, 34)
	beacon.StudsOffset = Vector3.new(0, 2.6, 0)
	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.3
	text.Parent = beacon
	beacon.Parent = part
	local entry = {part = part, prompt = prompt, beacon = beacon, label = text}
	prompt.Triggered:Connect(function()
		if entry.id then pending[entry.id] = os.clock() end
		actions:Fire("moteCollect")
	end)
	return entry
end
local function show(mote, at)
	local entry = drawn[mote.id]
	if not entry then
		entry = table.remove(spare) or build()
		entry.id = mote.id
		entry.base = at
		entry.phase = mote.index * 0.7
		entry.part.CFrame = CFrame.new(at)
		entry.part.Parent = folder
		drawn[mote.id] = entry
	end
	return entry
end
local function hide(id)
	local entry = drawn[id]
	if not entry then return end
	drawn[id] = nil
	entry.id = nil
	entry.beacon.Enabled = false
	entry.part.Parent = nil
	if #spare < 12 then table.insert(spare, entry) else entry.part:Destroy() end
end

-- Visibility pass (4 Hz): nearby unfound motes plus the bearing's target.
local function refresh()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hintId = player:GetAttribute("MoteHint")
	local hintUntil = tonumber(player:GetAttribute("MoteHintUntil")) or 0
	local hinted = type(hintId) == "string" and hintUntil > os.time() and EX.MoteById[hintId] or nil
	local want = {}
	if root then
		local here = root.Position
		for _, mote in ipairs(EX.Motes) do
			local recent = pending[mote.id] and os.clock() - pending[mote.id] < 3
			if not recent and not isFound(mote) then
				local at = positionOf(mote)
				if at and ((at - here).Magnitude <= EX.RENDER_RADIUS or mote == hinted) then want[mote.id] = at end
			end
		end
	end
	for id in pairs(drawn) do if not want[id] then hide(id) end end
	for id, at in pairs(want) do
		local entry = show(EX.MoteById[id], at)
		local isHint = EX.MoteById[id] == hinted
		entry.beacon.Enabled = isHint
		if isHint and root then entry.label.Text = EX.MOTE.symbol .. " " .. math.floor((at - root.Position).Magnitude) .. " studs" end
	end
end
task.spawn(function()
	while folder.Parent do
		pcall(refresh)
		task.wait(0.25)
	end
end)
-- Gentle bob and spin for the few drawn motes.
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, entry in pairs(drawn) do
		local y = math.sin(t * 2 + entry.phase) * 0.35
		entry.part.CFrame = CFrame.new(entry.base + Vector3.new(0, y, 0)) * CFrame.Angles(0, t + entry.phase, 0)
	end
end)

-- The Sundered Sky (ServerScriptService.Story; docs/DEPTH-CONTRACT.md §53).
-- The Adventure script (server.server.lua, Story block) owns every rule: who
-- may enter, steps, rewards, the fight lifecycle. This script only builds:
--   * quest set pieces (Data.Story.Pieces) on the existing islands, each in a
--     "Story set piece" model inside its island model, with an invisible
--     Anchor_Story_<id> (waypoints, proximity checks, cutscene cameras) and its
--     prompt (storyInspect / storyBoss / storyWarp, or a client-only Study
--     prompt with attribute StoryPuzzle for the puzzle panels; the signal
--     mirrors carry storyPuzzle "mirrors:turn:<i>" prompts);
--   * instanced encounter arenas, through one synchronous BindableFunction
--     ServerStorage.IsleStoryHost:
--       "open"  {uid, boss} -> {ok, fight, center (floor top), spawn (CFrame), lanterns = {[i] = BasePart}} | {ok = false, reason}
--       "close" {fight}     -> true (destroys the arena; idempotent)
--       "count" {}          -> live arenas
--     Arenas sit in slots along X from Data.Story.ARENA_ORIGIN (ST.MAX_FIGHTS),
--     under Workspace.StoryInstances: floor, four invisible walls, four pillars,
--     an exit plinth (prompt storyLeave) and, for lantern encounters, the
--     lantern posts (combat lights the lit one).
-- Never touches island(): pieces are placed beside existing anchors / island
-- centres with a downward raycast for the ground.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local ST = Data.Story

local Host = {arenas = {}, slots = {}, seq = 0}
local V, CF = Vector3.new, CFrame.new
local function hex(h) return Color3.fromHex(h) end

local function part(parent, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cframe, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide = true, collide == true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function prompt(host, actionText, objectText, action, item, region)
	local q = Instance.new("ProximityPrompt")
	q.ActionText, q.ObjectText = actionText, objectText
	q.HoldDuration, q.MaxActivationDistance, q.RequiresLineOfSight = 0.3, 10, false
	if action then q:SetAttribute("IsleAction", action) end
	if item then q:SetAttribute("IsleItem", item) end
	local gated = region and Data.RegionById[region] and next(Data.RegionById[region].requires or {}) ~= nil
	if gated then q:SetAttribute("IsleRegion", region) end
	q.Parent = host
	return q
end
Host.part, Host.prompt = part, prompt

------------------------------------------------------------------------------
-- Set pieces.
------------------------------------------------------------------------------
-- The stand point of a piece: beside its `near` anchor (else the island
-- centre) plus its offset, dropped onto the ground under it.
function Host.placeOf(isle, piece, raycast)
	local center = isle:GetAttribute("IslandCenter")
	if typeof(center) ~= "Vector3" then return nil end
	local base = center
	if piece.near then
		local a = isle:FindFirstChild("Anchor_" .. piece.near, true)
		if a and a:IsA("BasePart") then base = a.Position end
	end
	local pos = V(base.X + piece.off.x, center.Y, base.Z + piece.off.z)
	local ground = raycast and raycast(pos + V(0, 60, 0), V(0, -140, 0))
	local y = if ground then ground.Y else center.Y
	return V(pos.X, y, pos.Z), center
end
local BRASS, SLATE, GOLD, VIOLET, GLASS = hex("C9A24E"), hex("4A4E5A"), hex("F2D27A"), hex("B48CFF"), hex("BFE3FF")
local function facing(pos, toward)
	local look = V(toward.X, pos.Y, toward.Z)
	if (look - pos).Magnitude < 0.1 then return CF(pos) end
	return CFrame.lookAt(pos, look)
end
-- Builds one piece at pos (ground) facing the island centre; returns the model.
function Host.buildPiece(isle, piece, pos, center)
	local m = Instance.new("Model")
	m.Name = "Story set piece " .. piece.id
	m:SetAttribute("StoryPiece", piece.id)
	local cf = facing(pos, center)
	local function at(x, y, z) return cf * CF(x, y, z) end
	local host
	local shape = piece.shape
	if shape == "tear" then
		host = part(m, "Tear plinth", V(3, 1, 3), at(0, 0.5, 0), SLATE, Enum.Material.Slate, true)
		local tear = part(m, "Sky tear", V(0.4, 10, 3.4), at(0, 9, 0) * CFrame.Angles(0, 0, 0.25), GOLD, Enum.Material.Neon, false)
		tear.Transparency = 0.25
		tear:SetAttribute("StoryGlow", true)
	elseif shape == "stone" then
		host = part(m, "Glyph stone", V(3, 4.5, 1.4), at(0, 2.25, 0) * CFrame.Angles(0.06, 0, 0.04), SLATE, Enum.Material.Slate, true)
		local glyph = part(m, "Glyph", V(1.6, 1.6, 0.1), at(0, 2.8, -0.72), VIOLET, Enum.Material.Neon, false)
		glyph:SetAttribute("StoryGlow", true)
	elseif shape == "vault" then
		host = part(m, "Vault door", V(9, 11, 1.6), at(0, 5.5, 0), BRASS, Enum.Material.Metal, true)
		for i = 1, ST.DIALS do
			local d = part(m, "Rune dial " .. i, V(0.5, 1.6, 1.6), at(-3.3 + (i - 1) * 2.2, 6.5, -0.95) * CFrame.Angles(0, math.pi / 2, 0), hex("7A5C2E"), Enum.Material.Metal, false)
			d.Shape = Enum.PartType.Cylinder
		end
		part(m, "Vault lintel", V(11, 1.2, 2.4), at(0, 11.6, 0), hex("8C6A30"), Enum.Material.Metal, true)
	elseif shape == "gate" then
		host = part(m, "Gate step", V(10, 0.8, 4), at(0, 0.4, 0), SLATE, Enum.Material.Slate, true)
		part(m, "Gate pillar L", V(1.6, 12, 1.6), at(-4.6, 6.4, 0), SLATE, Enum.Material.Slate, true)
		part(m, "Gate pillar R", V(1.6, 12, 1.6), at(4.6, 6.4, 0), SLATE, Enum.Material.Slate, true)
		part(m, "Gate arch", V(11, 1.4, 2), at(0, 12.8, 0), SLATE, Enum.Material.Slate, true)
		local veil = part(m, "Gate veil", V(7.4, 11, 0.2), at(0, 6.2, 0), VIOLET, Enum.Material.Neon, false)
		veil.Transparency = 0.45
		veil:SetAttribute("StoryGlow", true)
	elseif shape == "astrolabe" then
		host = part(m, "Astrolabe plinth", V(5, 3, 5), at(0, 1.5, 0), BRASS, Enum.Material.Metal, true)
		for i = 1, 3 do
			local ring = part(m, "Astrolabe ring " .. i, V(0.3, 7 - i, 7 - i), at(0, 7, 0) * CFrame.Angles(i * 0.6, i * 0.9, 0), BRASS, Enum.Material.Metal, false)
			ring.Shape = Enum.PartType.Cylinder
		end
	elseif shape == "lens" then
		host = part(m, "Lens cradle", V(3, 2, 3), at(0, 1, 0), BRASS, Enum.Material.Metal, true)
		local lens = part(m, "Signal lens", V(3, 3, 3), at(0, 3.5, 0), GLASS, Enum.Material.Glass, false)
		lens.Shape = Enum.PartType.Ball
		lens.Transparency = 0.3
	elseif shape == "mirrors" then
		local L = ST.Mirror
		local cell = 3
		host = part(m, "Mirror field", V(L.size * cell + 2, 0.4, L.size * cell + 2), at(0, 0.2, 0), SLATE, Enum.Material.Slate, true)
		local function cellCF(x, y) return at((x - (L.size + 1) / 2) * cell, 0, -((y - (L.size + 1) / 2) * cell)) end
		for i, mm in ipairs(L.mirrors) do
			local post = part(m, "Signal mirror " .. i, V(0.4, 2.6, 2.4), cellCF(mm.x, mm.y) * CF(0, 1.5, 0), GLASS, Enum.Material.Glass, true)
			post:SetAttribute("MirrorIndex", i)
			local q = prompt(post, "Turn", "Signal mirror " .. i, "storyPuzzle", "mirrors:turn:" .. i, piece.region)
			q.MaxActivationDistance = 7
		end
		for i, w in ipairs(L.walls) do part(m, "Mirror wall " .. i, V(2.6, 2.6, 2.6), cellCF(w.x, w.y) * CF(0, 1.3, 0), SLATE, Enum.Material.Slate, true) end
		part(m, "Beam source", V(1.6, 1.6, 1.6), cellCF(L.source.x, L.source.y) * CF(0, 1.3, 0), GOLD, Enum.Material.Neon, false):SetAttribute("MirrorSource", true)
		part(m, "Beam receiver", V(2, 2, 2), cellCF(L.receiver.x, L.receiver.y) * CF(0, 1.3, 0), GLASS, Enum.Material.Glass, false):SetAttribute("MirrorReceiver", true)
		m:SetAttribute("MirrorCell", cell)
	elseif shape == "thread" then
		host = part(m, "Thread post", V(1.4, 5, 1.4), at(-3, 2.5, 0), BRASS, Enum.Material.Metal, true)
		part(m, "Thread post B", V(1.4, 5, 1.4), at(3, 2.5, 0), BRASS, Enum.Material.Metal, true)
		local thread = part(m, "Sky-thread", V(6, 0.2, 0.2), at(0, 4.4, 0), GOLD, Enum.Material.Neon, false)
		thread:SetAttribute("StoryGlow", true)
	else -- loomheart / loomstone: a dais with a floating crystal
		host = part(m, "Loom dais", V(6, 1, 6), at(0, 0.5, 0), SLATE, Enum.Material.Slate, true)
		local crystal = part(m, "Loom crystal", V(1.6, 3.6, 1.6), at(0, 4.4, 0) * CFrame.Angles(0, math.pi / 4, 0), VIOLET, Enum.Material.Neon, false)
		crystal:SetAttribute("StoryGlow", true)
	end
	-- The prompt and the anchor (in front of the piece, toward the centre).
	local text = piece.prompt
	if piece.boss then prompt(host, text[1], text[2], "storyBoss", piece.boss, piece.region)
	elseif piece.warp then prompt(host, text[1], text[2], "storyWarp", piece.warp, nil)
	elseif piece.puzzle then
		local q = prompt(host, text[1], text[2], nil, nil, nil)
		q:SetAttribute("StoryPuzzle", piece.puzzle)
	else prompt(host, text[1], text[2], "storyInspect", piece.id, piece.region) end
	local a = part(m, "Anchor_Story_" .. piece.id, V(1, 1, 1), at(0, 0.5, -5), hex("7FE0E8"), Enum.Material.SmoothPlastic, false)
	a.Transparency, a.CanQuery, a.CastShadow = 1, false, false
	a:SetAttribute("AnchorPurpose", "Story_" .. piece.id)
	for _, obj in ipairs(m:GetDescendants()) do
		if obj:IsA("BasePart") then obj.CastShadow = obj.CastShadow and obj.Material ~= Enum.Material.Neon end
	end
	m.Parent = isle
	return m, host, a
end
function Host.raycast(origin, dir)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, name in ipairs({"Townsfolk", "IsleMonsters", "StoryInstances"}) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, dir, params)
	return hit and hit.Position or nil
end
function Host.placePieces(islands, raycast)
	local built = {}
	for _, piece in ipairs(ST.Pieces) do
		local isle = islands:FindFirstChild(piece.isle)
		if isle and not isle:FindFirstChild("Story set piece " .. piece.id) then
			local pos, center = Host.placeOf(isle, piece, raycast)
			if pos then built[piece.id] = Host.buildPiece(isle, piece, pos, center) end
		end
	end
	return built
end

------------------------------------------------------------------------------
-- Arenas.
------------------------------------------------------------------------------
local ARENA_HALF = 36
function Host.slotCenter(slot)
	local o = ST.ARENA_ORIGIN
	return V(o.x + (slot - 1) * ST.ARENA_SPACING, o.y, o.z)
end
function Host.open(payload, root)
	local def = type(payload) == "table" and ST.boss(payload.boss)
	if not def or type(payload.uid) ~= "number" then return {ok = false, reason = "invalid"} end
	local slot
	for i = 1, ST.MAX_FIGHTS do if not Host.slots[i] then slot = i break end end
	if not slot then return {ok = false, reason = "capacity"} end
	Host.seq += 1
	local fight = "story:" .. payload.uid .. ":" .. Host.seq
	local center = Host.slotCenter(slot)
	local m = Instance.new("Model")
	m.Name = fight
	m:SetAttribute("StoryArena", def.id)
	local floorColor = hex(def.arenaColor)
	part(m, "Arena floor", V(ARENA_HALF * 2, 2, ARENA_HALF * 2), CF(center - V(0, 1, 0)), floorColor, Enum.Material.Slate, true)
	for i, w in ipairs({{V(0, 0, ARENA_HALF), V(ARENA_HALF * 2, 30, 1)}, {V(0, 0, -ARENA_HALF), V(ARENA_HALF * 2, 30, 1)},
		{V(ARENA_HALF, 0, 0), V(1, 30, ARENA_HALF * 2)}, {V(-ARENA_HALF, 0, 0), V(1, 30, ARENA_HALF * 2)}}) do
		local wall = part(m, "Arena wall " .. i, w[2], CF(center + w[1] + V(0, 15, 0)), floorColor, Enum.Material.Glass, true)
		wall.Transparency = 0.85
	end
	for i = 1, 4 do
		local a = (i - 0.5) * math.pi / 2
		part(m, "Arena pillar " .. i, V(3, 16, 3), CF(center + V(math.cos(a) * (ARENA_HALF - 5), 8, math.sin(a) * (ARENA_HALF - 5))), hex(def.color):Lerp(Color3.new(0, 0, 0), 0.45), Enum.Material.Slate, true)
	end
	local exit = part(m, "Arena exit", V(4, 1.2, 4), CF(center + V(0, 0.6, -(ARENA_HALF - 6))), hex("F2D27A"), Enum.Material.Metal, true)
	prompt(exit, "Leave", def.short .. "'s domain", "storyLeave", def.id, nil)
	local lanterns
	if def.lanterns then
		lanterns = {}
		for i, spot in ipairs(ST.lanternSpots(def)) do
			part(m, "Lantern post " .. i, V(0.8, 6, 0.8), CF(center + V(spot.x, 3, spot.z)), hex("3A2A1E"), Enum.Material.Wood, true)
			local lamp = part(m, "Lantern " .. i, V(1.8, 1.8, 1.8), CF(center + V(spot.x, 6.6, spot.z)), hex("46405F"), Enum.Material.Glass, false)
			lamp:SetAttribute("LanternIndex", i)
			lamp:SetAttribute("LanternRadius", def.lanterns.radius)
			lanterns[i] = lamp
		end
	end
	m.Parent = root
	Host.slots[slot] = fight
	Host.arenas[fight] = {model = m, slot = slot, uid = payload.uid, boss = def.id}
	local spawn = CFrame.lookAt(center + V(0, 4, -(ARENA_HALF - 12)), center + V(0, 4, 0))
	return {ok = true, fight = fight, center = center, spawn = spawn, lanterns = lanterns}
end
function Host.close(payload)
	local fight = type(payload) == "table" and payload.fight
	local a = type(fight) == "string" and Host.arenas[fight]
	if not a then return true end
	Host.arenas[fight] = nil
	if Host.slots[a.slot] == fight then Host.slots[a.slot] = nil end
	pcall(function() a.model:Destroy() end)
	return true
end
function Host.count()
	local n = 0
	for _ in pairs(Host.arenas) do n += 1 end
	return n
end

if __StoryHostHarness then
	__StoryHostHarness(Host)
	return
end

------------------------------------------------------------------------------
-- Runtime.
------------------------------------------------------------------------------
local root = Instance.new("Folder")
root.Name = "StoryInstances"
root.Parent = workspace
do
	local existing = ServerStorage:FindFirstChild("IsleStoryHost")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleStoryHost"
	fn.OnInvoke = function(op, payload)
		if op == "open" then return Host.open(payload, root)
		elseif op == "close" then return Host.close(payload)
		elseif op == "count" then return Host.count() end
		return nil
	end
	fn.Parent = ServerStorage
end
task.spawn(function()
	local islands = workspace:WaitForChild("Islands", 120)
	if not islands then warn("[Story] no Workspace.Islands: set pieces skipped") return end
	-- Islands arrive while world.server.lua builds; place what exists, retry the rest.
	for _ = 1, 30 do
		Host.placePieces(islands, Host.raycast)
		local missing = 0
		for _, piece in ipairs(ST.Pieces) do
			local isle = islands:FindFirstChild(piece.isle)
			if not isle or not isle:FindFirstChild("Story set piece " .. piece.id) then missing += 1 end
		end
		if missing == 0 then break end
		task.wait(2)
	end
end)

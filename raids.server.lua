-- Raids (Raid team): The Undertide Vaults, an instanced party raid for 2-8
-- players. docs/DEPTH-CONTRACT.md §38; rules and data in Data.Raids
-- (shared/GameData.lua, "Raids" section).
--
-- Typing: default (non-strict) mode, like lairs.server.lua: the headless suite
-- (verify-raid.luau) loads this script with doubles for game and Players and
-- receives the Raid table through the global __RaidsHarness (nil in Roblox).
--
-- Entry (lead decision: parties are open to anyone at the portal): the
-- Undertide portal on Tidewater Shoals (world.server.lua, Raids section: prompt IsleAction "raidPortal", anchor Waypoint_RaidPortal). The
-- Adventure script (server.server.lua, Raids block) validates every verb
-- (Combat level, region, not busy) and asks ServerStorage.IsleRaids
-- (BindableFunction made here, synchronous, never yields):
--   "host" (player, challenge) / "join" (player, lobbyId) / "leave" (player)
--   / "ready" (player) / "challenge" (player, on) / "start" (player)
--       party lobbies at the portal (members within RD.PORTAL_RANGE). The
--       host starts a lobby of RD.MIN_PARTY..RD.MAX_PARTY ready members; a
--       raid complex is then built off-map in one of RD.MAX_RAIDS slots
--       (Workspace.RaidInstances) and the party is moved in (FastTravelAt is
--       set on every move: Aether Mote anti-teleport).
--   "act" (player, {target, part}) - a room prompt (verb raidAct, prompt only):
--       glyph plates, valves, resource nodes, stations.
--   "use" (player, "food"|"potion") - a supply from the team pool (verb raidUse).
--   "depart" (player) - the journal's close() calls this first (PlayerRemoving
--       here too; idempotent): a disconnect while dead or fleeing is a death,
--       otherwise the member is held RD.REJOIN_SECONDS with their points.
--   "drain" () - shutdown: every raid is torn down with result "shutdown"
--       (not a failure in the Raid Log; no fees, nothing to refund).
--   "status" (player) - {lobby, run, room}.
-- Rooms (RD.sequence(seed)): two combat rooms, a puzzle, a resource room in a
-- seeded order, then the Regent. Combat rooms ask ServerStorage.IsleRaidCombat
-- (combat.server.lua Raids section) to raise the encounter scaled to room.party
-- = the run's members not offline at the rise (the dead count, so a death
-- never lowers an encounter); puzzles and resource rooms run here, sized by
-- the same count (re-checked each seal round / step). Points per member:
-- damage share of each encounter's pool (RD.damagePoints with room.party),
-- room clears, puzzle steps, resource work, minus RD.Points.death on each
-- death. When the Regent falls, credited members (RD.credit: contribution
-- floor without room-clear points, a credited action in RD.RECENT_SECONDS,
-- still in the raid) are judged first; the purple (unique) chance comes from
-- the credited members' points and its recipient from the personal points
-- (RD.pickRecipient). Par and the PB bracket use the starting party. They are paid
-- through bridge "raid" {action = "complete", ...} (resent by UserId while the
-- journal syncs or the member is away, until RD.REWARD_WINDOW); everyone else
-- gets {action = "end"}. Members return to the portal RD.EXIT_SECONDS later
-- and the complex, its connections and its creatures are destroyed.
-- Deaths (lead decision: raid points only, never purse coins): a member who
-- dies loses RD.Points.death of their points, respawns at home (RaidRejoin
-- makes world.server.lua's home landing stand aside) and is returned to the
-- current room. Removal: outside the room RD.AWAY_SECONDS (alive; no
-- character root counts as away), idle RD.IDLE_SECONDS (no movement, no
-- credited action), offline past RD.REJOIN_SECONDS. A raid with nobody inside
-- for RD.EMPTY_SECONDS, or no members left, ends; an encounter that times out
-- fails the raid.
-- Player attributes: RaidLobby ("k=v;..." lobby card), RaidRun (run id or ""),
-- RaidHud ("k=v;..." raid HUD), RaidNotice / RaidNoticeCount (toasts),
-- RaidRejoin (this script owns the respawn), RaidWardUntil (os.time of a
-- brewed ward's end). Workspace attributes RaidLobbies ("id|host|n|cm;..."),
-- RaidInstances ("<used>/<max>").
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Data = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
local RD = Data.Raids
local V = Vector3.new
local ORIGIN = V(-3600, 300, -3600)   -- far off the archipelago (lairs +X, minigames x -2400, Observatory z 1800)
local SLOT_SPACING = 700               -- between raid complexes (along -Z)
local ROOM_SPACING = 140               -- between rooms of one complex (along -X)
local HALF = RD.GRID * RD.CELL / 2     -- room floor half-width (the tile lattice)
local WALL = 16
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "RaidInstances"
folder.Parent = workspace

local Raid = {lobbies = {}, runs = {}, slots = {}, lobbyOf = {}, runOf = {}, stash = {}, retries = {}, seq = 0, lobbySeq = 0, portal = nil}

local function bridge(op, who, payload)
	local fn = ServerStorage:FindFirstChild("IsleBridge")
	if not fn then return nil end
	local ok, reply = pcall(fn.Invoke, fn, op, who, payload)
	if not ok then warn("[Raids] bridge " .. tostring(op) .. " failed: " .. tostring(reply)) return nil end
	return reply
end
local function combat(op, payload)
	local fn = ServerStorage:FindFirstChild("IsleRaidCombat")
	if not fn then return nil end
	local ok, reply = pcall(fn.Invoke, fn, op, payload)
	if not ok then warn("[Raids] combat " .. tostring(op) .. " failed: " .. tostring(reply)) return nil end
	return reply
end
local function replyOk(reply) return type(reply) == "table" and reply.ok == true end
local function playerByUid(uid)
	for _, p in ipairs(Players:GetPlayers()) do if p.UserId == uid and p.Parent then return p end end
	return nil
end
local function rootOf(player)
	local character = player and player.Parent and player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end
local function humanoidOf(player)
	local character = player and player.Parent and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end
local function aliveOf(player)
	local humanoid = humanoidOf(player)
	return humanoid ~= nil and humanoid.Health > 0
end
local function nameOf(player) return tostring(player and (player.DisplayName or player.Name) or "A raider") end
local function notice(player, text)
	if not player or not player.Parent then return end
	player:SetAttribute("RaidNotice", text)
	player:SetAttribute("RaidNoticeCount", (player:GetAttribute("RaidNoticeCount") or 0) + 1)
end
local function moveTo(player, cf)
	local root, character = rootOf(player)
	if not root or not character or not player then return false end
	player:SetAttribute("FastTravelAt", os.clock()) -- known fast travel (Aether Mote pickup checks)
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end
local function count(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end
local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do table.insert(out, k) end
	table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
	return out
end
local function publish()
	local used = count(Raid.runs)
	workspace:SetAttribute("RaidInstances", used .. "/" .. RD.MAX_RAIDS)
	local list = {}
	for _, id in ipairs(sortedKeys(Raid.lobbies)) do
		local l = Raid.lobbies[id]
		local host = l.members[l.host]
		table.insert(list, table.concat({l.id, nameOf(host and host.player), tostring(count(l.members)), if l.challenge then "1" else "0"}, "|"))
	end
	workspace:SetAttribute("RaidLobbies", table.concat(list, ";"))
end

-- Portal (world.server.lua places Anchor_Waypoint_RaidPortal) -----------------------
function Raid.portalCFrame()
	local cached = Raid.portal
	if cached and cached.Parent then return cached.CFrame + V(0, 3, 0) end
	local islands = workspace:FindFirstChild("Islands")
	local anchor = islands and islands:FindFirstChild("Anchor_Waypoint_RaidPortal", true)
	if anchor then
		Raid.portal = anchor
		return anchor.CFrame + V(0, 3, 0)
	end
	local isle = islands and islands:FindFirstChild(RD.ISLE)
	local center = isle and isle:GetAttribute("IslandCenter")
	if typeof(center) == "Vector3" then return CFrame.new(center + V(0, 6, 0)) end
	return CFrame.new(V(0, 8, 0))
end
local function nearPortal(player)
	local root = rootOf(player)
	if not root then return false end
	local d = root.Position - Raid.portalCFrame().Position
	return V(d.X, 0, d.Z).Magnitude <= RD.PORTAL_RANGE and math.abs(d.Y) <= 30
end
local function busyElsewhere(player)
	local lair, game_ = player:GetAttribute("LairBoss"), player:GetAttribute("MinigameGame")
	return player:GetAttribute("DungeonInRun") == true or (type(lair) == "string" and lair ~= "") or (type(game_) == "string" and game_ ~= "")
end

-- Lobbies ------------------------------------------------------------------------------
local function lobbyCard(l, uid)
	if not l then return "" end
	local host = l.members[l.host]
	local names = {}
	for _, id in ipairs(l.order) do
		local m = l.members[id]
		if m then table.insert(names, nameOf(m.player) .. (if m.ready or id == l.host then "*" else "")) end
	end
	local me = l.members[uid]
	return table.concat({"id=" .. l.id, "host=" .. nameOf(host and host.player), "n=" .. count(l.members), "cm=" .. (if l.challenge then 1 else 0),
		"hostMe=" .. (if uid == l.host then 1 else 0), "ready=" .. (if me and (me.ready or uid == l.host) then 1 else 0),
		"members=" .. table.concat(names, ","), "min=" .. RD.MIN_PARTY, "max=" .. RD.MAX_PARTY}, ";")
end
local function refreshLobby(l)
	for uid, m in pairs(l.members) do
		if m.player and m.player.Parent then m.player:SetAttribute("RaidLobby", lobbyCard(l, uid)) end
	end
	publish()
end
local function closeLobby(l, text)
	for uid, m in pairs(l.members) do
		Raid.lobbyOf[uid] = nil
		if m.player and m.player.Parent then
			m.player:SetAttribute("RaidLobby", "")
			if text then notice(m.player, text) end
		end
	end
	Raid.lobbies[l.id] = nil
	publish()
end
local function leaveLobby(l, uid, text)
	local m = l.members[uid]
	if not m then return end
	l.members[uid] = nil
	Raid.lobbyOf[uid] = nil
	local i = table.find(l.order, uid)
	if i then table.remove(l.order, i) end
	if m.player and m.player.Parent then
		m.player:SetAttribute("RaidLobby", "")
		if text then notice(m.player, text) end
	end
	if count(l.members) == 0 then closeLobby(l) return end
	if l.host == uid then
		l.host = l.order[1]
		local nh = l.members[l.host]
		if nh then notice(nh.player, "You now lead this raid party.") end
	end
	for _, other in pairs(l.members) do notice(other.player, nameOf(m.player) .. " left the raid party.") end
	refreshLobby(l)
end
function Raid.host(player, challenge)
	local uid = player.UserId
	if Raid.lobbyOf[uid] or Raid.runOf[uid] or Raid.stash[uid] then return {ok = false, reason = "active"} end
	if not nearPortal(player) then return {ok = false, reason = "portal"} end
	if count(Raid.lobbies) >= RD.MAX_LOBBIES then return {ok = false, reason = "lobbies"} end
	Raid.lobbySeq += 1
	local l = {id = "P" .. Raid.lobbySeq, host = uid, members = {}, order = {uid}, challenge = challenge == true, createdAt = os.clock()}
	l.members[uid] = {player = player, ready = true, joinedAt = os.clock()}
	Raid.lobbies[l.id] = l
	Raid.lobbyOf[uid] = l
	refreshLobby(l)
	return {ok = true, lobby = l.id}
end
function Raid.join(player, id)
	local uid = player.UserId
	if Raid.lobbyOf[uid] or Raid.runOf[uid] or Raid.stash[uid] then return {ok = false, reason = "active"} end
	local l = type(id) == "string" and Raid.lobbies[id]
	if not l then return {ok = false, reason = "lobby"} end
	if count(l.members) >= RD.MAX_PARTY then return {ok = false, reason = "full"} end
	if not nearPortal(player) then return {ok = false, reason = "portal"} end
	l.members[uid] = {player = player, ready = false, joinedAt = os.clock()}
	table.insert(l.order, uid)
	Raid.lobbyOf[uid] = l
	for other, m in pairs(l.members) do if other ~= uid then notice(m.player, nameOf(player) .. " joins the raid party.") end end
	refreshLobby(l)
	return {ok = true, lobby = l.id, members = count(l.members)}
end
function Raid.ready(player)
	local l = Raid.lobbyOf[player.UserId]
	if not l then return {ok = false, reason = "lobby"} end
	local m = l.members[player.UserId]
	m.ready = not m.ready
	refreshLobby(l)
	return {ok = true, ready = m.ready}
end
function Raid.setChallenge(player, on)
	local l = Raid.lobbyOf[player.UserId]
	if not l then return {ok = false, reason = "lobby"} end
	if l.host ~= player.UserId then return {ok = false, reason = "host"} end
	l.challenge = on == true
	for uid, m in pairs(l.members) do if uid ~= l.host then m.ready = false end end -- a mode change asks everyone again
	refreshLobby(l)
	return {ok = true, challenge = l.challenge}
end

-- Complex -------------------------------------------------------------------------------
local function block(parent, name, pos, size, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.Size = size
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Material = material or Enum.Material.Slate
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
-- Mesh slot (contract §10): forge.client.lua renders `Shape` as a detailed
-- mesh and keeps this primitive as the collider / fallback.
local function slot(p, shape, tint)
	p:SetAttribute("Shape", shape)
	if tint then p:SetAttribute("Tint", tint) end
	return p
end
local function prompt(part, action, object, target, hold)
	local q = Instance.new("ProximityPrompt")
	q.ActionText, q.ObjectText = action, object
	q.HoldDuration, q.MaxActivationDistance, q.RequiresLineOfSight = hold or 0.36, 9, false
	q:SetAttribute("IsleAction", if target == "leave" then "raidLeave" else "raidAct")
	if target ~= "leave" then q:SetAttribute("IsleItem", target) end
	q.Parent = part
	return q
end
-- §42 (owner decision: no hold-to-gather): a resource-room node is a struck
-- node. The host carries GatherNode (the skill's entry resource, for the swing,
-- the HP bar and the cast / reel), StrikeKind "raid" and RaidTarget
-- "node:<k>:<j>"; server.server.lua's Strike path validates the strike and, on
-- the break, runs the same "act" as the retired prompt (Raids.strikeNode).
local function strikeNode(part, node, target)
	local ST = Data.Strike
	local id = ST.ENTRY[node.skill] or "Herb"
	part:SetAttribute("GatherNode", id)
	part:SetAttribute("StrikeKind", "raid")
	part:SetAttribute("RaidTarget", target)
	part:SetAttribute("NodeName", node.name)
	local r = ST.resource(id)
	if r then part:SetAttribute("NodeMaxHp", ST.maxHp(r)) end
	part.CanQuery = true
	pcall(function() game:GetService("CollectionService"):AddTag(part, "AetherNode") end)
	return part
end
local function ring(center, i, n, radius)
	local a = (i - 1) * 2 * math.pi / n
	return center + V(math.cos(a) * radius, 0, math.sin(a) * radius)
end
local function C3(hex) return Color3.fromHex(hex) end
-- One room: floor or tile lattice, 4 glass walls, 4 columns, 2 braziers (one
-- light), the exit plinth, plus the room's own furniture. Parts are counted by
-- verify-raid (Raid.roomParts).
function Raid.buildRoom(run, room)
	local c = room.center
	local def = room.def
	local model = Instance.new("Model")
	model.Name = "Raid room " .. room.index .. " " .. room.kind
	model:SetAttribute("RaidRun", run.id)
	model:SetAttribute("RaidRoom", room.index)
	local base = C3(def.arenaColor or "1E3448")
	local accent = C3(def.color or "6FE3D6")
	local floorMat = Enum.Material[def.floor or "Slate"] or Enum.Material.Slate
	if def.tiles then
		room.tiles = {}
		for index = 1, RD.GRID * RD.GRID do
			local ox, oz = Data.Lairs.cellOffset(index)
			local shade = if ((index - 1) % RD.GRID + (index - 1) // RD.GRID) % 2 == 0 then base else base:Lerp(Color3.new(1, 1, 1), 0.12)
			room.tiles[index] = block(model, "Tile_" .. index, c + V(ox, -0.5, oz), V(RD.CELL - 0.15, 1, RD.CELL - 0.15), shade, floorMat)
		end
	else
		block(model, "Raid floor", c + V(0, -0.5, 0), V(HALF * 2, 1, HALF * 2), base, floorMat)
	end
	for i = 0, 3 do
		local a = i * math.pi / 2
		local dir = V(math.cos(a), 0, math.sin(a))
		local wall = block(model, "Raid wall", c + dir * (HALF + 0.5) + V(0, WALL / 2, 0), if i % 2 == 0 then V(1, WALL, HALF * 2 + 2) else V(HALF * 2 + 2, WALL, 1), base, Enum.Material.Glass)
		wall.Transparency = 0.65
		local corner = V(math.cos(a + math.pi / 4), 0, math.sin(a + math.pi / 4)) * (HALF * math.sqrt(2) - 2.5)
		slot(block(model, "Raid column", c + corner + V(0, 6, 0), V(3, 12, 3), base:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Slate), "Column", accent)
	end
	for side = -1, 1, 2 do
		local fire = slot(block(model, "Raid brazier", c + V(side * (HALF - 4), 1.5, HALF - 4), V(1.4, 3, 1.4), accent, Enum.Material.Neon, false), "Torch", accent)
		if side == -1 then
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = accent, 48, 1.3
			light:SetAttribute("LightWanted", true)
			light.Parent = fire
		end
	end
	local plinth = block(model, "Raid exit", c + V(0, 1.5, -HALF + 3), V(3, 3, 1.4), accent:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Marble)
	prompt(plinth, "Leave raid", RD.NAME, "leave", 1.5)
	room.parts = {}
	if room.kind == "puzzle" and room.id == "Glyphs" then
		for i, glyph in ipairs(RD.GLYPHS) do
			local plate = slot(block(model, "Glyph plate " .. glyph, ring(c, i, #RD.GLYPHS, 15) + V(0, 0.6, 0), V(4, 1.2, 4), accent, Enum.Material.Marble), "Seal", accent)
			plate:SetAttribute("Glyph", glyph)
			prompt(plate, "Press " .. glyph, "Glyph plate", "glyph:" .. i)
			room.parts["glyph" .. i] = plate
		end
		slot(block(model, "Glyph lectern", c + V(0, 2, 0), V(2.4, 4, 2.4), accent:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Marble), "Obelisk", accent)
	elseif room.kind == "puzzle" and room.id == "Seals" then
		for i = 1, RD.SEAL_PLATES do
			local plate = block(model, "Weighted seal " .. i, ring(c, i, RD.SEAL_PLATES, 14) + V(0, 0.15, 0), V(0.3, RD.SEAL_RADIUS * 2, RD.SEAL_RADIUS * 2), base:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Marble, false)
			plate.Shape = Enum.PartType.Cylinder
			plate.CFrame = plate.CFrame * CFrame.Angles(0, 0, math.pi / 2)
			plate:SetAttribute("SealIndex", i)
			room.parts["seal" .. i] = plate
		end
	elseif room.kind == "puzzle" and room.id == "Valves" then
		for i = 1, RD.VALVES do
			local valve = slot(block(model, "Tide valve " .. i, ring(c, i, RD.VALVES, 14) + V(0, 2.5, 0), V(2.4, 5, 2.4), accent, Enum.Material.Metal), "StormPylon", accent)
			valve:SetAttribute("ValveIndex", i)
			prompt(valve, "Turn valve " .. i, "Tide valve", "valve:" .. i)
			room.parts["valve" .. i] = valve
		end
	elseif room.kind == "resource" then
		local res = RD.Resources[room.id]
		for k, node in ipairs(res.nodes) do
			for j = 1, RD.NODES_PER_KIND do
				local pos = ring(c, (k - 1) * RD.NODES_PER_KIND + j, #res.nodes * RD.NODES_PER_KIND, 17) + V(0, 1, 0)
				local part = slot(block(model, node.name .. " " .. j, pos, V(3, 2, 3), C3(node.color), Enum.Material.Grass), node.shape, C3(node.color))
				strikeNode(part, node, "node:" .. k .. ":" .. j)
				room.parts["node" .. k .. ":" .. j] = part
			end
		end
		for k, station in ipairs(res.stations) do
			local part = slot(block(model, station.name, c + V((k == 1 and -6 or 6), 1.5, 4), V(4, 3, 4), accent, Enum.Material.Metal), station.shape, accent)
			prompt(part, station.verb .. " (" .. RD.RAW_PER_SUPPLY .. ")", station.name, "station:" .. station.id, 1.5)
			room.parts["station" .. station.id] = part
		end
	elseif room.kind == "boss" then
		slot(block(model, "Regent's hoard", c + V(0, 1.5, HALF - 5), V(5, 3, 3.5), C3("FFD86B"), Enum.Material.Metal), "VaultChest", C3("FFD86B"))
	end
	model.Parent = run.model
	room.model = model
end
function Raid.roomSpawn(room, k)
	local x = (((k or 1) - 1) % 4 - 1.5) * 5
	local z = -HALF + 8 + (((k or 1) - 1) // 4) * 4
	return CFrame.lookAt(room.center + V(x, 3.5, z), room.center + V(x, 3.5, 0))
end
local function insideRoom(room, root)
	if not room or not root then return false end
	local d = root.Position - room.center
	return V(d.X, 0, d.Z).Magnitude <= RD.ARENA_RANGE + 2 and math.abs(d.Y) <= 40
end

-- Members ---------------------------------------------------------------------------------
local function present(run)
	local list = {}
	local room = run.rooms[run.index]
	for uid, m in pairs(run.members) do
		if m.player and m.player.Parent and not m.offlineAt and aliveOf(m.player) and insideRoom(room, (rootOf(m.player))) then table.insert(list, uid) end
	end
	table.sort(list)
	return list
end
local function broadcast(run, text)
	for _, m in pairs(run.members) do notice(m.player, text) end
end
-- clear = true for flat room-clear points: they count toward personal and
-- team points but not toward the credit floor's contribution (QC M3).
local function award(run, uid, points, clear)
	local m = run.members[uid]
	if not m or points == 0 then return end
	m.points = math.max(0, m.points + math.floor(points))
	if not clear then m.contrib = math.max(0, (m.contrib or 0) + math.floor(points)) end
end
-- QC H1 / M4: the members of the run who are not offline (the dead count, so
-- a deliberate death never lowers an encounter); sizes encounters, point
-- pools, puzzles and the resource quota.
local function liveCount(run)
	local n = 0
	for _, m in pairs(run.members) do
		if not m.offlineAt and m.player and m.player.Parent then n += 1 end
	end
	return math.max(1, n)
end
Raid.liveCount = liveCount
local function act(m, now)
	m.actionAt, m.activeAt = now, now
end
local function bringIn(run, uid)
	local m = run.members[uid]
	if not m or not m.player or Raid.runs[run.id] ~= run then return false end
	if moveTo(m.player, Raid.roomSpawn(run.rooms[run.index], m.index)) then
		m.player:SetAttribute("RaidRun", run.id)
		m.awaySince = nil
		return true
	end
	return false
end
local function retrying(uid)
	for _, job in ipairs(Raid.retries) do if job.uid == uid then return true end end
	return false
end
-- Delivers a reward / closing payload by UserId (the Player is resolved on
-- every try, so a rejoined member is paid). Resent every RD.REWARD_RETRY while
-- the journal answers "sync" or the member is away, until the deadline.
local function deliver(job)
	local player = playerByUid(job.uid)
	local reply = if player then bridge("raid", player, job.payload) else nil
	if replyOk(reply) then return true end
	local transient = player == nil or reply == nil or (type(reply) == "table" and reply.reason == "sync")
	if transient and os.clock() + RD.REWARD_RETRY <= job.deadline then
		job.at = os.clock() + RD.REWARD_RETRY
		table.insert(Raid.retries, job)
	end
	return false
end
-- Removes a member from a run. reason: "left" | "idle" | "away" | "won" | nil.
-- A member removed before the end gets bridge "raid" {action = "end"}.
function Raid.removeMember(run, uid, reason, sendHome)
	local m = run.members[uid]
	if not m then return end
	run.members[uid] = nil
	run.gone[uid] = {points = m.points, deaths = m.deaths, reason = reason}
	if Raid.runOf[uid] == run then Raid.runOf[uid] = nil end
	if Raid.stash[uid] == run then Raid.stash[uid] = nil end
	local current = playerByUid(uid)
	if current then current:SetAttribute("RaidRejoin", nil) end
	local player = m.player
	local online = player ~= nil and player.Parent ~= nil
	if online then
		player:SetAttribute("RaidRun", "")
		player:SetAttribute("RaidHud", "")
		player:SetAttribute("RaidWardUntil", nil)
		if sendHome then moveTo(player, Raid.portalCFrame()) end
	end
	if reason and reason ~= "won" and not m.settled then
		m.settled = true
		local payload = {action = "end", run = run.id, result = reason, deaths = m.deaths}
		if online then bridge("raid", player, payload) end
	end
end
function Raid.teardown(run, result)
	if Raid.runs[run.id] ~= run then return end
	local room = run.rooms[run.index]
	if room and room.fight and room.spawned then combat("despawn", {fight = room.fight}) end
	for _, uid in ipairs(sortedKeys(run.members)) do
		local m = run.members[uid]
		local player = m.player
		local inside = player ~= nil and player.Parent ~= nil and (insideRoom(room, (rootOf(player))) or m.dead)
		if result ~= "won" then notice(player, Raid.endText(result)) end
		Raid.removeMember(run, uid, result, inside)
	end
	for _, c in ipairs(run.connections) do c:Disconnect() end
	if run.model then run.model:Destroy() end
	Raid.runs[run.id] = nil
	Raid.slots[run.slot] = nil
	publish()
end
function Raid.endText(result)
	if result == "timeout" then return "The vault floods: the guardian outlasted your party. You are swept back to the portal." end
	if result == "abandoned" then return "The Undertide Vaults fall silent: your party is gone." end
	if result == "error" then return "The vault collapses before it can open. Try again shortly." end
	if result == "shutdown" then return "The Undertide Vaults close: this server is shutting down. This run does not count against you." end
	if result == "idle" then return "You stood idle too long; the vault casts you out." end
	if result == "away" or result == "left" then return "You leave " .. RD.NAME .. "." end
	return "You leave " .. RD.NAME .. "."
end

-- Start -------------------------------------------------------------------------------------
function Raid.start(player)
	local uid = player.UserId
	local l = Raid.lobbyOf[uid]
	if not l then return {ok = false, reason = "lobby"} end
	if l.host ~= uid then return {ok = false, reason = "host"} end
	-- Members who wandered off, fell, or got busy elsewhere drop out of the lobby.
	for _, id in ipairs(table.clone(l.order)) do
		local m = l.members[id]
		if m and (not m.player or not m.player.Parent or not aliveOf(m.player) or not nearPortal(m.player) or busyElsewhere(m.player)) then
			leaveLobby(l, id, "You must stand at the Undertide portal when the raid begins.")
		end
	end
	if Raid.lobbies[l.id] ~= l or not l.members[uid] then return {ok = false, reason = "portal"} end
	local n = count(l.members)
	if n < RD.MIN_PARTY then return {ok = false, reason = "party"} end
	for id, m in pairs(l.members) do if id ~= l.host and not m.ready then return {ok = false, reason = "ready"} end end
	local slotIndex
	for i = 1, RD.MAX_RAIDS do if not Raid.slots[i] then slotIndex = i break end end
	if not slotIndex then return {ok = false, reason = "capacity"} end
	Raid.seq += 1
	local seed = math.floor(rng:NextNumber() * 1e6)
	local job = tostring(game.JobId or ""):sub(1, 8)
	local run = {id = string.format("R%s:%d:%d", job, Raid.seq, seed), slot = slotIndex, seed = seed, challenge = l.challenge, index = 1,
		origin = ORIGIN + V(0, 0, -(slotIndex - 1) * SLOT_SPACING), rooms = {}, members = {}, gone = {}, joined = 0, connections = {},
		supplies = {food = 0, potion = 0}, startedAt = os.clock(), deaths = 0, mistakes = 0, party = n}
	local model = Instance.new("Folder")
	model.Name = "Undertide Vaults " .. slotIndex
	model:SetAttribute("RaidRun", run.id)
	run.model = model
	for i, r in ipairs(RD.sequence(seed)) do
		local def = if r.kind == "combat" or r.kind == "boss" then RD.encounter(r.id) elseif r.kind == "puzzle" then RD.Puzzles[r.id] else RD.Resources[r.id]
		run.rooms[i] = {index = i, kind = r.kind, id = r.id, def = def, center = run.origin + V(-(i - 1) * ROOM_SPACING, 0, 0), state = "waiting"}
	end
	local ok, err = pcall(function()
		for _, room in ipairs(run.rooms) do Raid.buildRoom(run, room) end
		model.Parent = folder
	end)
	if not ok then
		warn("[Raids] could not build a vault: " .. tostring(err))
		model:Destroy()
		return {ok = false, reason = "invalid"}
	end
	Raid.slots[slotIndex] = run
	Raid.runs[run.id] = run
	local now = os.clock()
	for _, id in ipairs(l.order) do
		local lm = l.members[id]
		run.joined += 1
		run.members[id] = {player = lm.player, index = run.joined, points = 0, contrib = 0, deaths = 0, actionAt = now, activeAt = now, xp = {}, resource = 0}
		Raid.runOf[id] = run
		if lm.player and lm.player.Parent then lm.player:SetAttribute("RaidRun", run.id) end -- QC L4: even if the move in fails
	end
	closeLobby(l)
	Raid.enterRoom(run, 1, now)
	for id in pairs(run.members) do bringIn(run, id) end
	broadcast(run, RD.NAME .. (if run.challenge then " (Challenge Mode, par " .. RD.formatTime(RD.par(n)) .. ")" else "") .. ": " .. RD.roomName(run.rooms[1]) .. " awaits.")
	publish()
	return {ok = true, run = run.id, members = n}
end
function Raid.enterRoom(run, index, now)
	run.index = index
	local room = run.rooms[index]
	room.state, room.startAt = "waiting", now + RD.ROOM_GAP
	run.advanceAt = nil
	for _, m in pairs(run.members) do
		-- Moving rooms is a credited beat for everyone still in the party.
		m.activeAt = math.max(m.activeAt, now)
	end
end
function Raid.leave(player)
	local uid = player.UserId
	local l = Raid.lobbyOf[uid]
	if l then leaveLobby(l, uid, "You leave the raid party.") return {ok = true, mode = "lobby"} end
	local run = Raid.runOf[uid]
	if not run then return {ok = false} end
	Raid.removeMember(run, uid, if run.state == "won" then "won" else "left", true)
	if count(run.members) == 0 and run.state ~= "won" then Raid.teardown(run, "abandoned") end
	return {ok = true, mode = "run"}
end

-- Room logic -----------------------------------------------------------------------------------
local function clearRoom(run, room, now, bonus)
	room.state, room.clearedAt = "cleared", now
	if bonus then
		local pts = math.floor(RD.Points.clear * RD.pointMult(run.challenge))
		for uid, m in pairs(run.members) do
			if not m.offlineAt then award(run, uid, pts, true) end
		end
	end
	if run.index < #run.rooms then
		run.advanceAt = now + RD.ADVANCE_SECONDS
		broadcast(run, RD.roomName(room) .. " cleared! On to " .. RD.roomName(run.rooms[run.index + 1]) .. " in " .. RD.ADVANCE_SECONDS .. "s.")
	end
end
function Raid.startRoom(run, room, now)
	room.state, room.startedAt = "active", now
	room.party = liveCount(run) -- QC H1 / M4: members not offline (the dead count), stored for the room's pools
	if room.kind == "combat" or room.kind == "boss" then
		local roster = sortedKeys(run.members)
		room.fight = run.id .. ":" .. room.index
		local reply = combat("spawn", {fight = room.fight, encounter = room.id, center = room.center, members = roster, party = room.party,
			seed = run.seed + room.index, challenge = run.challenge, tiles = room.tiles})
		if not replyOk(reply) then
			warn("[Raids] encounter could not rise: " .. tostring(type(reply) == "table" and reply.reason))
			room.spawned = true -- despawn whatever combat registered before failing
			Raid.teardown(run, "error")
			return
		end
		room.spawned, room.maxHp, room.seen = true, reply.hp or 1, {}
		broadcast(run, room.def.short .. " rises! " .. (room.def.mechanics[1] or ""))
	elseif room.kind == "puzzle" then
		local s = {mistakes = 0}
		room.puzzle = s
		if room.id == "Glyphs" then
			s.seq, s.step, s.best = RD.glyphSequence(run.seed + room.index, RD.glyphLength(room.party, run.challenge)), 0, 0
		elseif room.id == "Seals" then
			s.round, s.need = 1, Raid.sealNeedFor(room.party)
			s.plates = RD.sealPattern(run.seed + room.index, 1, s.need)
			Raid.paintSeals(room)
		elseif room.id == "Valves" then
			s.state = RD.valveStart(run.seed + room.index)
			s.best = RD.valvesOpen(s.state)
			Raid.paintValves(room)
		end
		broadcast(run, room.def.name .. ": " .. room.def.blurb)
	elseif room.kind == "resource" then
		local res = room.def
		local s = {stock = {}, made = 0, quota = RD.quota(room.party), uses = {}}
		for k, node in ipairs(res.nodes) do
			s.stock[node.id] = 0
			for j = 1, RD.NODES_PER_KIND do s.uses[k .. ":" .. j] = RD.nodeUses(room.party) end
		end
		room.resource = s
		broadcast(run, res.name .. ": gather, then brew and cook " .. s.quota .. " supplies for the Regent's throne.")
	end
end
function Raid.paintSeals(room)
	local s = room.puzzle
	for i = 1, RD.SEAL_PLATES do
		local plate = room.parts["seal" .. i]
		if plate and plate.Parent then
			local lit = s and s.plates and table.find(s.plates, i) ~= nil and room.state == "active"
			plate.Material = if lit then Enum.Material.Neon else Enum.Material.Marble
			plate.Color = if lit then C3(room.def.color) else C3(room.def.arenaColor):Lerp(Color3.new(1, 1, 1), 0.3)
			plate:SetAttribute("Lit", lit == true)
		end
	end
end
function Raid.paintValves(room)
	local s = room.puzzle
	for i = 1, RD.VALVES do
		local valve = room.parts["valve" .. i]
		if valve and valve.Parent then
			local open = s.state[i] == true
			valve.Color = if open then C3("6FE3A0") else C3("E86A5A")
			valve:SetAttribute("Open", open)
		end
	end
end
local function solved(run, room, now)
	broadcast(run, room.def.name .. " solved!")
	clearRoom(run, room, now, true)
end
-- Seals lit at once for n live members (never more than are there to hold them).
function Raid.sealNeedFor(n)
	n = math.max(1, math.floor(tonumber(n) or 1))
	return math.min(RD.sealNeed(n), n)
end
function Raid.sealStep(run, room, now)
	local s = room.puzzle
	-- QC M4: a party that shrank mid-round gets a pattern it can still hold.
	local need = Raid.sealNeedFor(liveCount(run))
	if need < s.need then
		s.need, s.holdSince = need, nil
		s.plates = RD.sealPattern(run.seed + room.index, s.round, need)
		Raid.paintSeals(room)
	end
	local standing = {}
	local held = 0
	for _, plateIndex in ipairs(s.plates) do
		local plate = room.parts["seal" .. plateIndex]
		local who
		for uid, m in pairs(run.members) do
			local root = not m.offlineAt and aliveOf(m.player) and rootOf(m.player)
			if root and plate then
				local d = root.Position - plate.CFrame.Position
				if V(d.X, 0, d.Z).Magnitude <= RD.SEAL_RADIUS + 0.5 and d.Y > -2 and d.Y < 8 and not standing[uid] then who = uid break end
			end
		end
		if who then standing[who] = true; held += 1 end
	end
	s.held = held
	if held < #s.plates then s.holdSince = nil return end
	s.holdSince = s.holdSince or now
	for uid in pairs(standing) do run.members[uid].activeAt = now end
	if now - s.holdSince < RD.SEAL_HOLD then return end
	local pts = math.floor(RD.Points.puzzleStep * RD.pointMult(run.challenge))
	for uid in pairs(standing) do award(run, uid, pts); act(run.members[uid], now) end
	s.holdSince = nil
	if s.round >= RD.SEAL_ROUNDS then
		s.plates = {}
		Raid.paintSeals(room)
		solved(run, room, now)
		return
	end
	s.round += 1
	s.need = Raid.sealNeedFor(liveCount(run)) -- QC M4: re-sized every round
	s.plates = RD.sealPattern(run.seed + room.index, s.round, s.need)
	Raid.paintSeals(room)
	broadcast(run, "Seal round " .. (s.round - 1) .. " holds. New seals light up.")
end
-- A room prompt (verb raidAct). target: "glyph:<i>" | "valve:<i>" | "node:<k>:<j>" | "station:<id>".
function Raid.act(player, payload)
	local uid = player.UserId
	local run = Raid.runOf[uid]
	local m = run and run.members[uid]
	if not run or not m or m.offlineAt then return {ok = false, reason = "raid"} end
	local room = run.rooms[run.index]
	local target = type(payload) == "table" and payload.target or payload
	if type(target) ~= "string" or room.state ~= "active" then return {ok = false, reason = "room"} end
	local part = type(payload) == "table" and payload.part or nil
	if part ~= nil and room.model and not part:IsDescendantOf(room.model) then return {ok = false, reason = "room"} end
	if not aliveOf(player) or not insideRoom(room, (rootOf(player))) then return {ok = false, reason = "room"} end
	local now = os.clock()
	if now < (m.actAt or 0) then return {ok = false, reason = "busy"} end
	m.actAt = now + 0.5
	local mult = RD.pointMult(run.challenge)
	local kind, a, b = string.match(target, "^(%a+):(%w+):?(%w*)$")
	if room.kind == "puzzle" and room.id == "Glyphs" and kind == "glyph" then
		local s = room.puzzle
		local g = tonumber(a)
		if not g or g < 1 or g > #RD.GLYPHS then return {ok = false, reason = "target"} end
		act(m, now)
		if s.seq[s.step + 1] == g then
			s.step += 1
			if s.step > s.best then
				s.best = s.step
				award(run, uid, math.floor(RD.Points.puzzleStep * mult))
			end
			if s.step >= #s.seq then solved(run, room, now) return {ok = true, solved = true} end
			return {ok = true, step = s.step}
		end
		s.step, s.mistakes = 0, s.mistakes + 1
		run.mistakes += 1
		award(run, uid, -RD.Points.puzzleMistake)
		-- QC L3: one party-wide notice per member per RD.MISTAKE_NOTICE seconds.
		if now >= (m.mistakeNoticeAt or 0) then
			m.mistakeNoticeAt = now + RD.MISTAKE_NOTICE
			broadcast(run, nameOf(player) .. " pressed the wrong glyph: the chant restarts.")
		else
			notice(player, "Wrong glyph: the chant restarts.")
		end
		return {ok = true, mistake = true}
	elseif room.kind == "puzzle" and room.id == "Valves" and kind == "valve" then
		local s = room.puzzle
		local i = tonumber(a)
		if not i or i < 1 or i > RD.VALVES then return {ok = false, reason = "target"} end
		act(m, now)
		RD.valveToggle(s.state, i)
		Raid.paintValves(room)
		local open = RD.valvesOpen(s.state)
		if open > s.best then
			s.best = open
			award(run, uid, math.floor(RD.Points.puzzleStep * mult))
		end
		if open >= RD.VALVES then solved(run, room, now) return {ok = true, solved = true} end
		return {ok = true, open = open}
	elseif room.kind == "resource" and kind == "node" then
		local s = room.resource
		local k, j = tonumber(a), tonumber(b)
		local node = k and room.def.nodes[k]
		local key = (k or 0) .. ":" .. (j or 0)
		if not node or not s.uses[key] then return {ok = false, reason = "target"} end
		if now < (m.gatherAt or 0) then return {ok = false, reason = "busy"} end
		if s.uses[key] <= 0 then return {ok = false, reason = "depleted"} end
		m.gatherAt = now + RD.GATHER_COOLDOWN
		s.uses[key] -= 1
		s.stock[node.id] += 1
		act(m, now)
		local pts = math.min(math.floor(RD.Points.gather * mult), math.max(0, math.floor(RD.Points.resourceCap * mult) - m.resource))
		m.resource += pts
		award(run, uid, pts)
		m.xp[node.skill] = (m.xp[node.skill] or 0) + node.xp
		return {ok = true, raw = node.id, stock = s.stock[node.id]}
	elseif room.kind == "resource" and kind == "station" then
		local s = room.resource
		local station
		for _, st in ipairs(room.def.stations) do if st.id == a then station = st end end
		if not station then return {ok = false, reason = "target"} end
		local raw
		for _, node in ipairs(room.def.nodes) do if node.makes == station.makes then raw = node.id end end
		if (s.stock[raw] or 0) < RD.RAW_PER_SUPPLY then return {ok = false, reason = "stock"} end
		s.stock[raw] -= RD.RAW_PER_SUPPLY
		s.made += 1
		run.supplies[station.makes] += 1
		act(m, now)
		local pts = math.min(math.floor(RD.Points.craft * mult), math.max(0, math.floor(RD.Points.resourceCap * mult) - m.resource))
		m.resource += pts
		award(run, uid, pts)
		m.xp[station.skill] = (m.xp[station.skill] or 0) + station.xp
		if s.made >= s.quota then
			broadcast(run, "The supplies are ready: " .. run.supplies.food .. " " .. room.def.supplies.food .. ", " .. run.supplies.potion .. " " .. room.def.supplies.potion .. ".")
			clearRoom(run, room, now, true)
		end
		return {ok = true, made = s.made, supply = station.makes}
	end
	return {ok = false, reason = "target"}
end
-- A supply from the team pool (verb raidUse): food heals, a draught heals a
-- little and raises a ward (damage x RD.WARD_MULT, applied by the journal's
-- bridge "damage").
function Raid.use(player, kind)
	local uid = player.UserId
	local run = Raid.runOf[uid]
	local m = run and run.members[uid]
	local supply = RD.Supplies[kind]
	if not run or not m or m.offlineAt then return {ok = false, reason = "raid"} end
	if not supply then return {ok = false, reason = "kind"} end
	if (run.supplies[kind] or 0) <= 0 then return {ok = false, reason = "empty"} end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 then return {ok = false, reason = "dead"} end
	-- QC L3: no wasted supplies from the shared pool.
	if not supply.ward and humanoid.Health >= humanoid.MaxHealth then return {ok = false, reason = "full"} end
	local wardUntil = player:GetAttribute("RaidWardUntil")
	if supply.ward and type(wardUntil) == "number" and wardUntil - os.time() > RD.WARD_REFRESH then return {ok = false, reason = "warded"} end
	local now = os.clock()
	if now < (m.supplyAt or 0) then return {ok = false, reason = "busy"} end
	m.supplyAt = now + RD.SUPPLY_COOLDOWN
	run.supplies[kind] -= 1
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * supply.heal)
	if supply.ward then player:SetAttribute("RaidWardUntil", os.time() + supply.ward) end
	m.activeAt = now
	return {ok = true, left = run.supplies[kind]}
end

-- Completion ---------------------------------------------------------------------------------------
local REASON_TEXT = {share = "your points fell below the party's floor", away = "you were not in the vault", idle = "you had not acted for a while",
	points = "you earned no points", removed = "you had left the raid"}
function Raid.complete(run, now)
	run.state, run.exitAt = "won", now + RD.EXIT_SECONDS
	local seconds = math.max(1, math.floor(now - run.startedAt + 0.5))
	local uids = sortedKeys(run.members)
	local contribution = 0
	for _, uid in ipairs(uids) do contribution += run.members[uid].contrib or 0 end
	-- QC M2: par, the PB bracket and the journal's clamps use the run's
	-- starting (largest) party, as the room pools never exceed it.
	local party = run.party
	local credited, entries = {}, {}
	local team = 0
	for _, uid in ipairs(uids) do
		local m = run.members[uid]
		local presentNow = (m.offlineAt ~= nil and now - m.offlineAt <= RD.REJOIN_SECONDS) or (m.player ~= nil and m.player.Parent ~= nil)
		local okCredit, reason = RD.credit({points = m.points, contribution = m.contrib or 0, teamContribution = contribution, party = #uids,
			present = presentNow, lastAction = m.actionAt, now = now})
		m.creditReason = reason
		if okCredit then
			table.insert(credited, uid)
			table.insert(entries, {uid = uid, points = m.points})
			team += m.points -- QC M3: the purple chance sums credited members only
		end
	end
	local chance = RD.uniqueChance(team)
	local recipient, unique
	if #entries > 0 and rng:NextNumber() < chance then
		recipient = RD.pickRecipient(entries, rng:NextNumber())
		unique = RD.pickUnique(rng:NextNumber())
	end
	local underPar = run.challenge and seconds <= RD.par(party)
	run.result = {seconds = seconds, team = team, chance = chance, recipient = recipient, unique = unique, underPar = underPar, credited = credited}
	local deadline = now + RD.REWARD_WINDOW
	for _, uid in ipairs(uids) do
		local m = run.members[uid]
		if table.find(credited, uid) then
			m.settled = true
			local xp = {}
			for skill, n in pairs(m.xp) do xp[skill] = math.min(n, 4000) end
			deliver({uid = uid, at = 0, deadline = deadline, payload = {action = "complete", run = run.id, seconds = seconds, party = party,
				points = m.points, team = team, challenge = run.challenge, underPar = underPar, unique = if recipient == uid then unique else nil,
				deaths = m.deaths, xp = xp}})
			local purple = if recipient == uid then "  PURPLE: " .. Data.Items[unique].name .. "!" elseif recipient then "  " .. nameOf(run.members[recipient].player) .. " found a unique." else ""
			notice(m.player, "Thalvorn falls in " .. RD.formatTime(seconds) .. "! " .. m.points .. " points (team " .. team .. ")." .. purple)
		else
			m.settled = true
			if m.player and m.player.Parent then
				bridge("raid", m.player, {action = "end", run = run.id, result = "nocredit", deaths = m.deaths})
				notice(m.player, "Thalvorn falls, but " .. (REASON_TEXT[m.creditReason or "points"] or "you earned no share") .. ".")
			end
		end
	end
end

-- Step ----------------------------------------------------------------------------------------------------
local function hudText(run, uid, now, status)
	local m = run.members[uid]
	local room = run.rooms[run.index]
	local res = nil
	for _, r in ipairs(run.rooms) do if r.kind == "resource" then res = r.def end end
	local team = 0
	for _, other in pairs(run.members) do team += other.points end
	local parts = {"run=" .. run.id, "room=" .. run.index .. "/" .. #run.rooms, "kind=" .. room.kind, "name=" .. RD.roomName(room), "state=" .. (if run.state == "won" then "won" else room.state),
		"cm=" .. (if run.challenge then 1 else 0), "t=" .. math.floor(now - run.startedAt), "team=" .. team, "me=" .. m.points, "deaths=" .. m.deaths,
		"food=" .. run.supplies.food, "potion=" .. run.supplies.potion,
		"foodName=" .. (if res then res.supplies.food else "Food"), "potionName=" .. (if res then res.supplies.potion else "Draught")}
	if run.challenge then table.insert(parts, "par=" .. RD.par(run.party)) end
	if run.state == "won" then
		table.insert(parts, "exit=" .. math.max(0, math.ceil((run.exitAt or now) - now)))
	elseif room.state == "waiting" then
		table.insert(parts, "in=" .. math.max(0, math.ceil(room.startAt - now)))
	elseif room.state == "cleared" and run.advanceAt then
		table.insert(parts, "in=" .. math.max(0, math.ceil(run.advanceAt - now)))
	elseif room.state == "active" then
		if (room.kind == "combat" or room.kind == "boss") and type(status) == "table" and status.alive then
			table.insert(parts, "hp=" .. status.hp .. "/" .. status.maxHp)
			table.insert(parts, "phase=" .. status.phase .. "/" .. status.phases)
			table.insert(parts, "pname=" .. tostring(status.phaseName or ""))
			table.insert(parts, "style=" .. tostring(status.style or ""))
			if status.switchIn then table.insert(parts, "next=" .. tostring(status.nextStyle) .. ";sin=" .. status.switchIn) end
			table.insert(parts, "weak=" .. tostring(status.weakness or ""))
			table.insert(parts, if status.enraged then "enr=1" else "enrage=" .. status.enrageIn)
			table.insert(parts, "ends=" .. status.endsIn)
			table.insert(parts, "ward=" .. (if status.warded then 1 else 0))
			table.insert(parts, "seal=" .. (if status.sealed then status.order else 0))
			table.insert(parts, "adds=" .. status.adds)
		elseif room.kind == "puzzle" then
			local s = room.puzzle
			table.insert(parts, "ends=" .. math.max(0, math.ceil(room.startedAt + RD.PUZZLE_SECONDS - now)))
			if room.id == "Glyphs" then
				local names = {}
				for _, g in ipairs(s.seq) do table.insert(names, RD.GLYPHS[g]) end
				table.insert(parts, "seq=" .. table.concat(names, ","))
				table.insert(parts, "step=" .. s.step)
			elseif room.id == "Seals" then
				table.insert(parts, "round=" .. s.round .. "/" .. RD.SEAL_ROUNDS)
				table.insert(parts, "plates=" .. table.concat(s.plates, ","))
				table.insert(parts, "held=" .. (s.held or 0) .. "/" .. #s.plates)
			elseif room.id == "Valves" then
				local bits = {}
				for i = 1, RD.VALVES do bits[i] = if s.state[i] then "1" else "0" end
				table.insert(parts, "valves=" .. table.concat(bits))
			end
		elseif room.kind == "resource" then
			local s = room.resource
			table.insert(parts, "ends=" .. math.max(0, math.ceil(room.startedAt + RD.RESOURCE_SECONDS - now)))
			table.insert(parts, "made=" .. s.made .. "/" .. s.quota)
			local stock = {}
			for _, node in ipairs(room.def.nodes) do table.insert(stock, node.name:match("^(%S+)") .. ":" .. s.stock[node.id]) end
			table.insert(parts, "stock=" .. table.concat(stock, ","))
		end
	end
	return table.concat(parts, ";")
end
local function settleRejoin(run, m, player, now)
	local humanoid = humanoidOf(player)
	if humanoid and m.health and humanoid.Health > m.health then humanoid.Health = math.max(1, m.health) end
	if now <= (m.rejoinUntil or 0) then
		if not insideRoom(run.rooms[run.index], (rootOf(player))) then moveTo(player, Raid.roomSpawn(run.rooms[run.index], m.index)) end
		m.awaySince = nil
		return
	end
	m.rejoinUntil, m.health = nil, nil
	player:SetAttribute("RaidRejoin", nil)
end
function Raid.memberStep(run, now)
	local room = run.rooms[run.index]
	for _, uid in ipairs(sortedKeys(run.members)) do
		local m = run.members[uid]
		local player = m.player
		if m.offlineAt then
			if now - m.offlineAt > RD.REJOIN_SECONDS then Raid.removeMember(run, uid, "left", false) end
		elseif not player or not player.Parent then
			m.player, m.offlineAt = nil, now
			Raid.stash[uid] = run
		elseif m.rejoinUntil then
			settleRejoin(run, m, player, now)
		elseif m.dead then
			-- Respawning: the CharacterAdded handler returns them to the room.
			if aliveOf(player) and now - (m.diedAt or now) > 1 then Raid.returnDead(run, uid, player) end
		else
			local root = rootOf(player)
			local humanoid = humanoidOf(player)
			if humanoid then
				if m.lastHp and humanoid.Health < m.lastHp then m.hurtAt = now end
				m.lastHp = humanoid.Health
			end
			if run.state ~= "won" and root and not aliveOf(player) then
				-- A death: points take the loss, the member respawns and comes back in.
				local loss = RD.deathLoss(m.points)
				m.points -= loss
				m.deaths += 1
				run.deaths += 1
				m.dead, m.diedAt = true, now
				player:SetAttribute("RaidRejoin", true)
				player:SetAttribute("RaidWardUntil", nil)
				notice(player, "You fell in the vault: -" .. loss .. " points. You will return to " .. RD.roomName(room) .. ".")
				for other, om in pairs(run.members) do if other ~= uid then notice(om.player, nameOf(player) .. " has fallen.") end end
			elseif root then
				if m.lastPos and (root.Position - m.lastPos).Magnitude >= RD.MOVE_STUDS then m.activeAt = now end
				m.lastPos = root.Position
				if insideRoom(room, root) then
					m.awaySince = nil
				else
					m.awaySince = m.awaySince or now
					if now - m.awaySince > RD.AWAY_SECONDS then
						notice(player, Raid.endText("away"))
						Raid.removeMember(run, uid, if run.state == "won" then "won" else "away", false)
						continue
					end
				end
				if run.state ~= "won" and now - math.max(m.activeAt, m.actionAt) > RD.IDLE_SECONDS then
					notice(player, Raid.endText("idle"))
					Raid.removeMember(run, uid, "idle", true)
				end
			else
				-- QC L4: no character root (removed, not loaded) counts as away.
				m.awaySince = m.awaySince or now
				if now - m.awaySince > RD.AWAY_SECONDS then
					notice(player, Raid.endText("away"))
					Raid.removeMember(run, uid, if run.state == "won" then "won" else "away", false)
				end
			end
		end
	end
end
function Raid.returnDead(run, uid, player)
	local m = run.members[uid]
	if not m then return end
	m.dead, m.diedAt, m.lastHp, m.hurtAt = nil, nil, nil, nil
	m.rejoinUntil = os.clock() + RD.REJOIN_VERIFY
	m.activeAt = math.max(m.activeAt, os.clock())
	moveTo(player, Raid.roomSpawn(run.rooms[run.index], m.index))
	notice(player, "Back into " .. RD.roomName(run.rooms[run.index]) .. ".")
end
function Raid.roomStep(run, now)
	local room = run.rooms[run.index]
	local status
	if room.state == "waiting" then
		if now >= room.startAt then Raid.startRoom(run, room, now) end
	elseif room.state == "active" then
		if room.kind == "combat" or room.kind == "boss" then
			status = combat("status", {fight = room.fight})
			if type(status) ~= "table" then
				run.lost = run.lost or now
				if now - run.lost > 10 then Raid.teardown(run, "error") end
				return nil
			end
			run.lost = nil
			for uid, d in pairs(type(status.dmg) == "table" and status.dmg or {}) do
				local m = run.members[uid]
				if m and d.lastHit and d.lastHit > m.actionAt then m.actionAt = d.lastHit; m.activeAt = math.max(m.activeAt, d.lastHit) end
			end
			if not status.alive then
				if status.result == "win" then
					local outcome = status.outcome or {}
					room.spawned = false
					-- QC M1: despawn the won encounter (its result record and tile map go with it).
					combat("despawn", {fight = room.fight})
					for uid, c in pairs(type(outcome.credit) == "table" and outcome.credit or {}) do
						if run.members[uid] then
							-- QC H1: the pool is sized by the same n the encounter scaled to.
							award(run, uid, RD.damagePoints(room.kind, (c.damage or 0) / math.max(1, room.maxHp), room.party or run.party, run.challenge))
							if c.lastHit and c.lastHit > run.members[uid].actionAt then run.members[uid].actionAt = c.lastHit end
						end
					end
					if room.kind == "boss" then
						clearRoom(run, room, now, true)
						Raid.complete(run, now)
					else
						broadcast(run, room.def.short .. " is defeated!")
						clearRoom(run, room, now, true)
					end
					return nil
				end
				room.spawned = false
				Raid.teardown(run, if status.result == "timeout" then "timeout" else "error")
				return nil
			end
			local seen = room.seen
			if seen.phase and status.phase > seen.phase then broadcast(run, room.def.short .. ": " .. tostring(status.phaseName) .. "! Weak to " .. tostring(status.weakness) .. ".") end
			if status.enraged and not seen.enraged then broadcast(run, room.def.short .. " is ENRAGED!") end
			if status.alert and status.alert.seq ~= seen.alert then
				if status.alert.kind == "tiles" then broadcast(run, status.alert.name .. "! Step off the glowing tiles!")
				elseif status.alert.kind == "safe" then broadcast(run, status.alert.name .. "! Get beside " .. room.def.short .. "!") end
				seen.alert = status.alert.seq
			end
			if status.sealed and not seen.sealed then broadcast(run, room.def.short .. " is sealed: break them in order, I first!") end
			if status.warded and not seen.warded then broadcast(run, room.def.short .. " is warded: slay the adds first!") end
			seen.phase, seen.enraged, seen.sealed, seen.warded = status.phase, status.enraged, status.sealed, status.warded
		elseif room.kind == "puzzle" then
			if room.id == "Seals" then Raid.sealStep(run, room, now) end
			if room.state == "active" and now - room.startedAt > RD.PUZZLE_SECONDS then
				broadcast(run, room.def.name .. " grinds open on its own (no completion points).")
				if room.id == "Seals" then room.puzzle.plates = {} end
				clearRoom(run, room, now, false)
				if room.id == "Seals" then Raid.paintSeals(room) end
			end
		elseif room.kind == "resource" then
			-- QC M4: a party that shrank needs only its own quota.
			local s = room.resource
			local quota = RD.quota(liveCount(run))
			if quota < s.quota then
				s.quota = quota
				if s.made >= s.quota then
					broadcast(run, "The supplies are ready: " .. run.supplies.food .. " " .. room.def.supplies.food .. ", " .. run.supplies.potion .. " " .. room.def.supplies.potion .. ".")
					clearRoom(run, room, now, true)
					return status
				end
			end
			if now - room.startedAt > RD.RESOURCE_SECONDS then
				broadcast(run, room.def.name .. " closes: the supplies you made come with you.")
				clearRoom(run, room, now, false)
			end
		end
	elseif room.state == "cleared" and run.state ~= "won" and run.advanceAt and now >= run.advanceAt then
		Raid.enterRoom(run, run.index + 1, now)
		for uid, m in pairs(run.members) do
			if m.player and m.player.Parent and not m.offlineAt and not m.dead then bringIn(run, uid) end
		end
		broadcast(run, RD.roomName(run.rooms[run.index]) .. (if run.rooms[run.index].kind == "boss" then ": the Regent stirs in " else " begins in ") .. RD.ROOM_GAP .. "s.")
	end
	return status
end
function Raid.step(now)
	-- Reward resends (by UserId).
	local due = {}
	local i = 1
	while i <= #Raid.retries do
		if now >= Raid.retries[i].at then table.insert(due, table.remove(Raid.retries, i)) else i += 1 end
	end
	for _, job in ipairs(due) do deliver(job) end
	-- Lobbies: expire, drop departed members.
	for _, id in ipairs(sortedKeys(Raid.lobbies)) do
		local l = Raid.lobbies[id]
		if l and now - l.createdAt > RD.LOBBY_SECONDS then
			closeLobby(l, "Your raid party disbanded: it never set out.")
		elseif l then
			for _, uid in ipairs(table.clone(l.order)) do
				local m = l.members[uid]
				if m and (not m.player or not m.player.Parent) then leaveLobby(l, uid) end
			end
		end
	end
	for _, id in ipairs(sortedKeys(Raid.runs)) do
		local run = Raid.runs[id]
		if not run then continue end
		Raid.memberStep(run, now)
		if Raid.runs[id] ~= run then continue end
		if count(run.members) == 0 then Raid.teardown(run, if run.state == "won" then "won" else "abandoned") continue end
		local status
		if run.state == "won" then
			if now >= (run.exitAt or now) then Raid.teardown(run, "won") continue end
		else
			status = Raid.roomStep(run, now)
			if Raid.runs[id] ~= run then continue end
			if #present(run) == 0 then
				run.emptySince = run.emptySince or now
				if now - run.emptySince > RD.EMPTY_SECONDS then Raid.teardown(run, "abandoned") continue end
			else
				run.emptySince = nil
			end
		end
		for uid, m in pairs(run.members) do
			if m.player and m.player.Parent and not m.offlineAt then
				local text = hudText(run, uid, now, status)
				if m.hud ~= text then
					m.hud = text
					m.player:SetAttribute("RaidHud", text)
				end
			end
		end
	end
end

-- Connection ends / rejoins ------------------------------------------------------------------------------
function Raid.depart(player)
	local uid = player and player.UserId
	local l = uid and Raid.lobbyOf[uid]
	if l then leaveLobby(l, uid) end
	local run = uid and Raid.runOf[uid]
	local m = run and run.members[uid]
	if not run or not m or m.player ~= player or m.offlineAt then return {ok = false} end
	local now = os.clock()
	local humanoid = humanoidOf(player)
	if humanoid and run.state ~= "won" then
		local hp = humanoid.Health
		if m.lastHp and hp < m.lastHp then m.hurtAt = now end
		local fleeing = hp > 0 and hp < humanoid.MaxHealth * RD.FLEE_HP and m.hurtAt ~= nil and now - m.hurtAt <= RD.FLEE_SECONDS
		if (hp <= 0 and not m.dead) or fleeing then
			-- Disconnecting to dodge a death is a death (points only; raids keep the purse).
			local loss = RD.deathLoss(m.points)
			m.points -= loss
			m.deaths += 1
			run.deaths += 1
		end
		m.health = if hp > 0 then hp else nil
	end
	m.dead, m.diedAt = nil, nil
	m.player, m.offlineAt = nil, now
	Raid.stash[uid] = run
	return {ok = true}
end
function Raid.held(uid)
	local run = Raid.stash[uid] or Raid.runOf[uid]
	return run ~= nil and Raid.runs[run.id] == run and run.members[uid] ~= nil
end
local function rejoin(player, character)
	local uid = player.UserId
	-- A death respawn inside a live run: back to the current room.
	local live = Raid.runOf[uid]
	local lm = live and live.members[uid]
	if live and lm and lm.dead and lm.player == player then
		local root = character and character:WaitForChild("HumanoidRootPart", 5)
		if root and Raid.runOf[uid] == live and live.members[uid] == lm and lm.dead then Raid.returnDead(live, uid, player) end
		return
	end
	local run = Raid.stash[uid]
	local m = run and run.members[uid]
	if not run or not m or Raid.runs[run.id] ~= run or not m.offlineAt or os.clock() - m.offlineAt > RD.REJOIN_SECONDS then
		if not live then player:SetAttribute("RaidRejoin", nil) end
		return
	end
	local root = character and character:WaitForChild("HumanoidRootPart", 5)
	if not root or Raid.stash[uid] ~= run or run.members[uid] ~= m then
		if not Raid.held(uid) then player:SetAttribute("RaidRejoin", nil) end
		return
	end
	Raid.stash[uid] = nil
	local now = os.clock()
	m.player, m.offlineAt, m.awaySince, m.hud = player, nil, nil, nil
	m.lastHp, m.hurtAt, m.lastPos = nil, nil, nil
	m.activeAt = math.max(m.activeAt, now - RD.IDLE_SECONDS + RD.REJOIN_GRACE)
	m.rejoinUntil = now + RD.REJOIN_VERIFY
	Raid.runOf[uid] = run
	player:SetAttribute("RaidRejoin", true)
	if moveTo(player, Raid.roomSpawn(run.rooms[run.index], m.index)) then player:SetAttribute("RaidRun", run.id) end
	settleRejoin(run, m, player, now)
	notice(player, "Back into " .. RD.NAME .. " • your points were kept.")
end
local function watch(player)
	-- Claim the respawn before any CharacterAdded handler runs (world.server.lua's
	-- home landing skips while RaidRejoin is set).
	if Raid.stash[player.UserId] and Raid.held(player.UserId) then player:SetAttribute("RaidRejoin", true) end
	if player.CharacterAdded then player.CharacterAdded:Connect(function(character) rejoin(player, character) end) end
	if player.Character then rejoin(player, player.Character) end
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player) Raid.depart(player) end)

function Raid.drain()
	for _, id in ipairs(sortedKeys(Raid.runs)) do
		local run = Raid.runs[id]
		if run and run.state ~= "won" then Raid.teardown(run, "shutdown") end -- QC L2: not a failure
	end
	return {}
end
do
	local fn = Instance.new("BindableFunction")
	fn.Name = "IsleRaids"
	fn.OnInvoke = function(op, player, arg)
		if op == "drain" then return Raid.drain() end
		if typeof(player) ~= "Instance" and type(player) ~= "table" then return {ok = false, reason = "invalid"} end
		if op == "host" then return Raid.host(player, arg == true or arg == "on")
		elseif op == "join" then return Raid.join(player, arg)
		elseif op == "leave" then return Raid.leave(player)
		elseif op == "ready" then return Raid.ready(player)
		elseif op == "challenge" then return Raid.setChallenge(player, arg == true or arg == "on")
		elseif op == "start" then return Raid.start(player)
		elseif op == "act" then return Raid.act(player, arg)
		elseif op == "use" then return Raid.use(player, arg)
		elseif op == "depart" then return Raid.depart(player)
		elseif op == "status" then
			local run = Raid.runOf[player.UserId]
			local l = Raid.lobbyOf[player.UserId]
			return {lobby = l and l.id, run = run and run.id, room = run and run.index, held = Raid.held(player.UserId)}
		end
		return nil
	end
	fn.Parent = ServerStorage
end
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then return end
	accumulator = 0
	Raid.step(os.clock())
end)
-- Shutdown: tear every complex down (no fees: nothing to refund).
game:BindToClose(function() Raid.drain() end)
publish()
if __RaidsHarness then __RaidsHarness(Raid) end -- headless tests only (nil in Roblox)

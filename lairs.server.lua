-- Lairs (Bossing team): instanced lair bosses for one to three players.
-- docs/DEPTH-CONTRACT.md §25; rules and data in Data.Lairs (shared/GameData.lua).
--
-- Four lair altars stand on existing islands (world.server.lua, Lairs section:
-- prompt IsleAction "lairEnter", IsleItem <boss>, IsleRegion <region>). The
-- Adventure script (server.server.lua, Lairs block) checks the journal (Combat
-- level, region, entry fee, not busy) and asks ServerStorage.IsleLairs
-- (BindableFunction made here, synchronous, never yields):
--   "enter" (player, boss) -> {ok, fight, mode = "open"|"join"} | {ok = false, reason}
--       opens an instance: an arena built off-map on demand in one of
--       LR.MAX_INSTANCES slots (Workspace.LairInstances), or joins a crewmate's
--       (same non-empty CoopId attribute) instance of that boss during its
--       LR.WARMUP; the fee is spent only after ok. Teleports run on the next
--       step (FastTravelAt is set on every move: Aether Mote anti-teleport).
--   "cancel" (player) -> undo an enter the journal could not pay for.
--   "leave" (player) -> forfeit (the arena exit prompt, verb lairLeave).
-- After the warmup the boss rises (ServerStorage.IsleLairCombat "spawn", in
-- combat.server.lua) with the members inside the arena; anyone outside then
-- has left. During the fight:
--   * a member who dies has fallen: out of the fight (respawn at home, items
--     kept; the game's usual purse-coin death loss applies), bridge "lair"
--     {action = "end", result = "died"};
--   * a member outside the arena for LR.AWAY_SECONDS (a teleport spell, a
--     fall) has left (result "left");
--   * a member who disconnects is held for LR.REJOIN_SECONDS: rejoining the
--     server in time puts them back in the arena with their damage share kept
--     (combat keys damage by UserId); the fight keeps running meanwhile and
--     pauses its specials while nobody is inside. A fight with no member
--     inside for LR.EMPTY_SECONDS, or with every member gone, ends cleanly.
-- The kill (IsleLairCombat "status" -> result "win" with per-UserId credit) is
-- paid through bridge "lair" {action = "kill", boss, fight, seconds, party,
-- share} for every credited member (resent while the journal syncs, until
-- LR.REWARD_WINDOW); members return to the altar LR.EXIT_SECONDS later and the
-- arena, its connections and its creatures are destroyed. A boss that cannot
-- be built refunds every member's fee (action "refund"); so does a shutdown.
-- Player attributes: LairBoss (boss id while inside, else ""), LairHud
-- ("k=v;..." for the in-fight HUD), LairNotice / LairNoticeCount (toasts).
-- Workspace attribute LairInstances = "<used>/<max>".
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Data = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
local LR = Data.Lairs
local V = Vector3.new
local ORIGIN = V(3600, 300, -3600)   -- far off the archipelago (islands span about +-650, Observatory z 1800, Skybreach x -2400)
local SPACING = 400                  -- between instance slots (beyond combat FX range)
local HALF = LR.GRID * LR.CELL / 2    -- arena floor half-width (the tile lattice)
local WALL = 14
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "LairInstances"
folder.Parent = workspace

local Lair = {fights = {}, slots = {}, byUser = {}, stash = {}, pending = {}, retries = {}, seq = 0, altars = {}}

local function bridge(op, player, payload)
	local fn = ServerStorage:FindFirstChild("IsleBridge")
	if not fn then return nil end
	local ok, reply = pcall(fn.Invoke, fn, op, player, payload)
	if not ok then warn("[Lairs] bridge " .. tostring(op) .. " failed: " .. tostring(reply)) return nil end
	return reply
end
local function combat(op, payload)
	local fn = ServerStorage:FindFirstChild("IsleLairCombat")
	if not fn then return nil end
	local ok, reply = pcall(fn.Invoke, fn, op, payload)
	if not ok then warn("[Lairs] combat " .. tostring(op) .. " failed: " .. tostring(reply)) return nil end
	return reply
end
local function rootOf(player)
	local character = player and player.Parent and player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end
local function aliveOf(player)
	local character = player and player.Parent and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end
local function notice(player, text)
	if not player or not player.Parent then return end
	player:SetAttribute("LairNotice", text)
	player:SetAttribute("LairNoticeCount", (player:GetAttribute("LairNoticeCount") or 0) + 1)
end
local function moveTo(player, cf)
	local root, character = rootOf(player)
	if not root then return false end
	player:SetAttribute("FastTravelAt", os.clock()) -- known fast travel (Aether Mote pickup checks)
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end
local function publish()
	local used = 0
	for _ in pairs(Lair.fights) do used += 1 end
	workspace:SetAttribute("LairInstances", used .. "/" .. LR.MAX_INSTANCES)
end

-- Altars: world.server.lua places Anchor_Waypoint_Lair_<boss> beside each altar.
function Lair.altar(boss)
	local cached = Lair.altars[boss]
	if cached and cached.Parent then return cached.CFrame + V(0, 3, 0) end
	local islands = workspace:FindFirstChild("Islands")
	local anchor = islands and islands:FindFirstChild("Anchor_Waypoint_Lair_" .. boss, true)
	if anchor then
		Lair.altars[boss] = anchor
		return anchor.CFrame + V(0, 3, 0)
	end
	local def = LR.boss(boss)
	local isle = islands and def and islands:FindFirstChild(def.isle)
	local center = isle and isle:GetAttribute("IslandCenter")
	if typeof(center) == "Vector3" then return CFrame.new(center + V(0, 6, 0)) end
	return CFrame.new(V(0, 8, 0))
end

-- Arena -------------------------------------------------------------------------
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
-- Parts: floor (1) or tile lattice (GRID^2), 4 walls, 4 pillars, 4 braziers,
-- the exit plinth (with its prompt) = 14 or 38. Asserted by verify-bosses.
function Lair.build(f)
	local def = f.def
	local model = Instance.new("Model")
	model.Name = "Lair " .. def.short .. " " .. f.slot
	model:SetAttribute("LairFight", f.id)
	model:SetAttribute("LairBoss", def.id)
	local c = f.center
	local base = Color3.fromHex(def.arenaColor)
	local accent = Color3.fromHex(def.color)
	local floorMat = Enum.Material[def.floor] or Enum.Material.Slate
	local tiles = nil
	if def.tiles then
		tiles = {}
		for index = 1, LR.GRID * LR.GRID do
			local ox, oz = LR.cellOffset(index)
			local shade = if ((index - 1) % LR.GRID + (index - 1) // LR.GRID) % 2 == 0 then base else base:Lerp(Color3.new(1, 1, 1), 0.12)
			tiles[index] = block(model, "Tile_" .. index, c + V(ox, -0.5, oz), V(LR.CELL - 0.15, 1, LR.CELL - 0.15), shade, floorMat)
		end
	else
		block(model, "Lair floor", c + V(0, -0.5, 0), V(HALF * 2, 1, HALF * 2), base, floorMat)
	end
	for i = 0, 3 do
		local a = i * math.pi / 2
		local dir = V(math.cos(a), 0, math.sin(a))
		local wall = block(model, "Lair wall", c + dir * (HALF + 0.5) + V(0, WALL / 2, 0), if i % 2 == 0 then V(1, WALL, HALF * 2 + 2) else V(HALF * 2 + 2, WALL, 1), base, Enum.Material.Glass)
		wall.Transparency = 0.7
		local corner = V(math.cos(a + math.pi / 4), 0, math.sin(a + math.pi / 4)) * (HALF * math.sqrt(2) - 2)
		block(model, "Lair pillar", c + corner + V(0, 5, 0), V(2.4, 10, 2.4), base:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Slate)
		local fire = block(model, "Lair brazier", c + corner + V(0, 10.6, 0), V(1.6, 1.2, 1.6), accent, Enum.Material.Neon, false)
		if i == 0 then
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = accent, 40, 1.2
			light.Parent = fire
		end
	end
	local plinth = block(model, "Lair exit", c + V(0, 1.5, -HALF + 3), V(3, 3, 1.4), accent:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Marble)
	local q = Instance.new("ProximityPrompt")
	q.ActionText, q.ObjectText = "Leave lair", def.lairName
	q.HoldDuration, q.MaxActivationDistance, q.RequiresLineOfSight = 1, 9, false
	q:SetAttribute("IsleAction", "lairLeave")
	q:SetAttribute("IsleItem", def.id)
	q.Parent = plinth
	model.Parent = folder
	f.model, f.tiles = model, tiles
end
local function spawnCFrame(f, k)
	local x = ((k or 1) - 2) * 5
	return CFrame.lookAt(f.center + V(x, 3.5, -HALF + 8), f.center + V(x, 3.5, 0))
end
local function inside(f, root)
	if not root then return false end
	local d = root.Position - f.center
	return V(d.X, 0, d.Z).Magnitude <= LR.ARENA_RANGE + 2 and math.abs(d.Y) <= 40
end

-- Members -------------------------------------------------------------------------
local function memberCount(f)
	local n = 0
	for _ in pairs(f.members) do n += 1 end
	return n
end
local function bringIn(f, uid)
	local m = f.members[uid]
	if not m or not m.player or Lair.fights[f.id] ~= f then return end
	if moveTo(m.player, spawnCFrame(f, m.index)) then
		m.player:SetAttribute("LairBoss", f.def.id)
		m.awaySince = nil
	end
end
-- Removes a member. result: "left" | "died" | "won" | nil (silent: cancelled entry).
function Lair.removeMember(f, uid, result, sendHome)
	local m = f.members[uid]
	if not m then return end
	f.members[uid] = nil
	if Lair.byUser[uid] == f then Lair.byUser[uid] = nil end
	if Lair.stash[uid] == f then Lair.stash[uid] = nil end
	local player = m.player
	if player and player.Parent then
		player:SetAttribute("LairBoss", "")
		player:SetAttribute("LairHud", "")
		if sendHome then moveTo(player, Lair.altar(f.def.id)) end
		if result and result ~= "won" and not m.paid then bridge("lair", player, {action = "end", boss = f.def.id, fight = f.id, result = result}) end
	end
end
function Lair.teardown(f, result, refund)
	if Lair.fights[f.id] ~= f then return end
	if f.spawned then combat("despawn", {fight = f.id}) end
	local uids = {}
	for uid in pairs(f.members) do table.insert(uids, uid) end
	table.sort(uids)
	for _, uid in ipairs(uids) do
		local m = f.members[uid]
		local player = m.player
		local present = player and player.Parent and inside(f, (rootOf(player)))
		if refund and player and player.Parent and not m.paid then
			bridge("lair", player, {action = "refund", boss = f.def.id, fight = f.id})
		end
		if result ~= "won" then notice(player, Lair.endText(f, result)) end
		Lair.removeMember(f, uid, if refund then nil else result, present)
	end
	for _, c in ipairs(f.connections) do c:Disconnect() end
	if f.model then f.model:Destroy() end
	Lair.fights[f.id] = nil
	Lair.slots[f.slot] = nil
	publish()
end
function Lair.endText(f, result)
	local name = f.def.short
	if result == "timeout" then return name .. " outlasts you: the lair seals and casts you out." end
	if result == "abandoned" then return "The lair falls silent: nobody stood against " .. name .. "." end
	if result == "failed" then return name .. " stands victorious. The lair casts you out." end
	if result == "error" then return "The lair collapses before " .. name .. " can rise; your offering is returned." end
	return "You leave " .. f.def.lairName .. "."
end

-- IsleLairs ops -------------------------------------------------------------------
function Lair.enter(player, boss)
	local def = LR.boss(boss)
	if typeof(player) ~= "Instance" and type(player) ~= "table" then return {ok = false, reason = "invalid"} end
	if not def then return {ok = false, reason = "boss"} end
	local uid = player.UserId
	if Lair.byUser[uid] then return {ok = false, reason = "active"} end
	-- Join a crewmate's instance of this boss during its warmup.
	local crew = player:GetAttribute("CoopId")
	crew = if crew ~= nil and crew ~= "" then tostring(crew) else nil
	if crew then
		for _, f in pairs(Lair.fights) do
			if f.def == def and f.state == "warmup" and f.crew == crew and memberCount(f) < LR.MAX_PARTY then
				f.joined += 1
				f.members[uid] = {player = player, index = f.joined, joinedAt = os.clock()}
				Lair.byUser[uid] = f
				table.insert(Lair.pending, {fight = f, uid = uid})
				for other, m in pairs(f.members) do if other ~= uid then notice(m.player, tostring(player.DisplayName or player.Name or "A crewmate") .. " joins the hunt.") end end
				return {ok = true, fight = f.id, mode = "join", members = memberCount(f)}
			end
		end
	end
	local slot
	for i = 1, LR.MAX_INSTANCES do if not Lair.slots[i] then slot = i break end end
	if not slot then return {ok = false, reason = "capacity"} end
	Lair.seq += 1
	local seed = math.floor(rng:NextNumber() * 1e6)
	local f = {id = string.format("L%d:%d:%d", Lair.seq, slot, seed), def = def, slot = slot, seed = seed, state = "warmup",
		center = ORIGIN + V((slot - 1) * SPACING, 0, 0), members = {}, joined = 1, crew = crew,
		openedAt = os.clock(), riseAt = os.clock() + LR.WARMUP, connections = {}, hud = {}, seen = {}}
	local ok, err = pcall(Lair.build, f)
	if not ok then
		warn("[Lairs] could not build an arena: " .. tostring(err))
		if f.model then f.model:Destroy() end
		return {ok = false, reason = "invalid"}
	end
	Lair.slots[slot] = f
	Lair.fights[f.id] = f
	f.members[uid] = {player = player, index = 1, joinedAt = os.clock()}
	Lair.byUser[uid] = f
	table.insert(Lair.pending, {fight = f, uid = uid})
	publish()
	return {ok = true, fight = f.id, mode = "open", members = 1}
end
function Lair.cancel(player)
	local f = player and Lair.byUser[player.UserId]
	if not f then return {ok = false} end
	Lair.removeMember(f, player.UserId, nil, false)
	if memberCount(f) == 0 then Lair.teardown(f, "abandoned") end
	return {ok = true}
end
function Lair.leave(player)
	local f = player and Lair.byUser[player.UserId]
	if not f then return {ok = false} end
	Lair.removeMember(f, player.UserId, if f.state == "won" then "won" else "left", true)
	if memberCount(f) == 0 and f.state ~= "won" then Lair.teardown(f, "abandoned") end
	return {ok = true}
end
do
	local fn = Instance.new("BindableFunction")
	fn.Name = "IsleLairs"
	fn.OnInvoke = function(op, player, arg)
		if op == "enter" then return Lair.enter(player, arg)
		elseif op == "cancel" then return Lair.cancel(player)
		elseif op == "leave" then return Lair.leave(player)
		elseif op == "status" then
			local f = player and Lair.byUser[player.UserId]
			return {active = f ~= nil, boss = f and f.def.id, state = f and f.state}
		end
		return nil
	end
	fn.Parent = ServerStorage
end

-- Fight loop ----------------------------------------------------------------------
local STYLE_NAME = {melee = "MELEE", ranged = "RANGED", magic = "MAGIC"}
local WARD_NAME = {melee = "Ward of Fangs", ranged = "Ward of Quills", magic = "Ward of Glyphs"}
local function present(f)
	local list = {}
	for uid, m in pairs(f.members) do
		if m.player and m.player.Parent and aliveOf(m.player) and inside(f, (rootOf(m.player))) then table.insert(list, uid) end
	end
	table.sort(list)
	return list
end
local function broadcastNotice(f, text)
	for _, m in pairs(f.members) do notice(m.player, text) end
end
local function hudText(f, status, now)
	local parts = {"boss=" .. f.def.id, "state=" .. f.state, "party=" .. memberCount(f)}
	if f.state == "warmup" then
		table.insert(parts, "rise=" .. math.max(0, math.ceil(f.riseAt - now)))
	elseif status and status.alive then
		table.insert(parts, "hp=" .. status.hp .. "/" .. status.maxHp)
		table.insert(parts, "phase=" .. status.phase .. "/" .. status.phases)
		table.insert(parts, "pname=" .. tostring(status.phaseName or ""))
		table.insert(parts, "style=" .. tostring(status.style or ""))
		if status.switchIn then table.insert(parts, "next=" .. tostring(status.nextStyle) .. ";in=" .. status.switchIn) end
		table.insert(parts, "weak=" .. tostring(status.weakness or ""))
		table.insert(parts, if status.enraged then "enr=1" else "enrage=" .. status.enrageIn)
		table.insert(parts, "ends=" .. status.endsIn)
		table.insert(parts, "t=" .. status.elapsed)
		table.insert(parts, "ward=" .. (if status.warded then 1 else 0))
		table.insert(parts, "seal=" .. (if status.sealed then status.order else 0))
		table.insert(parts, "adds=" .. status.adds)
	elseif f.state == "won" then
		table.insert(parts, "t=" .. math.floor(f.seconds or 0))
		table.insert(parts, "exit=" .. math.max(0, math.ceil((f.exitAt or now) - now)))
	end
	return table.concat(parts, ";")
end
local REASON_TEXT = {share = "you dealt too little of its health", dead = "you fell before it did", away = "you were outside the arena",
	idle = "you had not struck for a minute", ironman = "Ironman journals must carry 30% of a party kill", member = "you were not in this fight"}
local function payReward(f, uid, player, payload, deadline)
	local reply = bridge("lair", player, payload)
	if type(reply) == "table" and reply.ok then
		local m = f.members[uid]
		if m then m.paid = true end
		return true
	end
	if (reply == nil or (type(reply) == "table" and reply.reason == "sync")) and os.clock() + LR.REWARD_RETRY <= deadline then
		table.insert(Lair.retries, {fight = f, uid = uid, player = player, payload = payload, at = os.clock() + LR.REWARD_RETRY, deadline = deadline})
	end
	return false
end
function Lair.won(f, status, now)
	local outcome = status.outcome or {}
	f.state, f.exitAt, f.seconds = "won", now + LR.EXIT_SECONDS, outcome.seconds or 0
	local deadline = now + LR.REWARD_WINDOW
	for uid, m in pairs(f.members) do
		local c = type(outcome.credit) == "table" and outcome.credit[uid]
		if c and c.ok and m.player and m.player.Parent then
			m.credited = true
			payReward(f, uid, m.player, {action = "kill", boss = f.def.id, fight = f.id, seconds = math.max(1, math.floor(f.seconds + 0.5)),
				party = outcome.party or memberCount(f), share = c.share}, deadline)
			notice(m.player, f.def.short .. " is slain in " .. LR.formatTime(f.seconds) .. "! Returning to the altar in " .. LR.EXIT_SECONDS .. "s.")
		elseif m.player then
			notice(m.player, f.def.short .. " is slain, but " .. (REASON_TEXT[c and c.reason or "member"] or "you earned no share") .. ".")
		end
	end
end
function Lair.rise(f, now)
	local uids = present(f)
	-- Members not inside at the rise have left.
	for uid in pairs(f.members) do
		if not table.find(uids, uid) then Lair.removeMember(f, uid, "left", false) end
	end
	if #uids == 0 then Lair.teardown(f, "abandoned") return end
	local tiles = nil
	if f.tiles then tiles = f.tiles end
	local reply = combat("spawn", {fight = f.id, boss = f.def.id, center = f.center, members = uids, seed = f.seed, tiles = tiles})
	if type(reply) ~= "table" or not reply.ok then
		warn("[Lairs] boss could not rise: " .. tostring(type(reply) == "table" and reply.reason))
		Lair.teardown(f, "error", true)
		return
	end
	f.spawned, f.state, f.startedAt = true, "fight", now
	broadcastNotice(f, f.def.short .. " rises! " .. (f.def.mechanics[1] or ""))
end
function Lair.fightStep(f, now)
	local status = combat("status", {fight = f.id})
	if type(status) ~= "table" then
		f.lost = f.lost or now
		if now - f.lost > 10 then Lair.teardown(f, "error", true) end
		return nil
	end
	f.lost = nil
	if not status.alive then
		if status.result == "win" then Lair.won(f, status, now) return status end
		Lair.teardown(f, if status.result == "timeout" then "timeout" else "failed")
		return nil
	end
	-- Notices: stance, phase, enrage, telegraph names.
	local seen = f.seen
	if seen.style and status.style ~= seen.style then
		broadcastNotice(f, f.def.short .. " turns " .. (STYLE_NAME[status.style] or "?") .. " — " .. (WARD_NAME[status.style] or "") .. "!")
	end
	if seen.phase and status.phase > seen.phase then
		broadcastNotice(f, f.def.short .. ": " .. tostring(status.phaseName) .. "! Weak to " .. tostring(status.weakness) .. ".")
	end
	if status.enraged and not seen.enraged then broadcastNotice(f, f.def.short .. " is ENRAGED!") end
	if status.alert and status.alert.seq ~= seen.alert then
		if seen.alert ~= nil or status.alert.kind == "tiles" then
			if status.alert.kind == "tiles" then broadcastNotice(f, status.alert.name .. "! Step off the glowing tiles!") end
		end
		seen.alert = status.alert.seq
	end
	if status.sealed and not seen.sealed then broadcastNotice(f, f.def.short .. " is sealed: break the sigils in order, I first!") end
	if status.warded and not seen.warded then broadcastNotice(f, "The brood shields " .. f.def.short .. ": slay it first!") end
	seen.style, seen.phase, seen.enraged, seen.sealed, seen.warded = status.style, status.phase, status.enraged, status.sealed, status.warded
	return status
end
function Lair.memberStep(f, now)
	for uid, m in pairs(f.members) do
		local player = m.player
		if m.offlineAt then
			if now - m.offlineAt > LR.REJOIN_SECONDS then Lair.removeMember(f, uid, "left", false) end
		elseif not player or not player.Parent then
			m.offlineAt = now
			Lair.stash[uid] = f
		elseif f.state ~= "warmup" or now - m.joinedAt > 3 then
			local root = rootOf(player)
			if f.state == "fight" and root and not aliveOf(player) then
				notice(player, "You fell to " .. f.def.short .. ". Your items are safe at home.")
				Lair.removeMember(f, uid, "died", false)
			elseif inside(f, root) then
				m.awaySince = nil
			elseif root then
				m.awaySince = m.awaySince or now
				if now - m.awaySince > LR.AWAY_SECONDS then
					notice(player, "You left " .. f.def.lairName .. ".")
					Lair.removeMember(f, uid, if f.state == "won" then "won" else "left", false)
				end
			end
		end
	end
end
function Lair.step(now)
	-- Deferred moves (after the journal paid the fee).
	local pending = Lair.pending
	Lair.pending = {}
	for _, job in ipairs(pending) do bringIn(job.fight, job.uid) end
	-- Reward resends.
	local i = 1
	while i <= #Lair.retries do
		local job = Lair.retries[i]
		if now >= job.at then
			table.remove(Lair.retries, i)
			if job.player.Parent then payReward(job.fight, job.uid, job.player, job.payload, job.deadline) end
		else
			i += 1
		end
	end
	local ids = {}
	for id in pairs(Lair.fights) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local f = Lair.fights[id]
		if not f then continue end
		Lair.memberStep(f, now)
		if Lair.fights[id] ~= f then continue end
		local status
		if f.state == "warmup" then
			if now >= f.riseAt then Lair.rise(f, now) end
		elseif f.state == "fight" then
			status = Lair.fightStep(f, now)
		elseif f.state == "won" and now >= f.exitAt then
			Lair.teardown(f, "won")
			continue
		end
		if Lair.fights[id] ~= f then continue end
		if memberCount(f) == 0 then
			Lair.teardown(f, if f.state == "won" then "won" else "failed")
			continue
		end
		if f.state == "fight" then
			if #present(f) == 0 then
				f.emptySince = f.emptySince or now
				if now - f.emptySince > LR.EMPTY_SECONDS then Lair.teardown(f, "abandoned") continue end
			else
				f.emptySince = nil
			end
		end
		local text = hudText(f, status, now)
		for _, m in pairs(f.members) do
			if m.player and m.player.Parent and m.hud ~= text then
				m.hud = text
				m.player:SetAttribute("LairHud", text)
			end
		end
	end
end
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then return end
	accumulator = 0
	Lair.step(os.clock())
end)

-- Rejoin ------------------------------------------------------------------------------
local function rejoin(player, character)
	local f = Lair.stash[player.UserId]
	local m = f and f.members[player.UserId]
	if not m or Lair.fights[f.id] ~= f or not m.offlineAt or os.clock() - m.offlineAt > LR.REJOIN_SECONDS then return end
	local root = character and character:WaitForChild("HumanoidRootPart", 5)
	if not root or Lair.stash[player.UserId] ~= f or f.members[player.UserId] ~= m then return end
	Lair.stash[player.UserId] = nil
	m.player, m.offlineAt, m.awaySince, m.hud = player, nil, nil, nil
	Lair.byUser[player.UserId] = f
	if moveTo(player, spawnCFrame(f, m.index)) then player:SetAttribute("LairBoss", f.def.id) end
	notice(player, "Back into " .. f.def.lairName .. " • your share of the fight was kept.")
end
local function watch(player)
	if player.CharacterAdded then player.CharacterAdded:Connect(function(character) rejoin(player, character) end) end
	if player.Character then rejoin(player, player.Character) end
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	local f = Lair.byUser[player.UserId]
	local m = f and f.members[player.UserId]
	if not m then return end
	m.player, m.offlineAt = nil, os.clock()
	Lair.stash[player.UserId] = f
end)
-- Shutdown: unfinished fights refund their members' fees (the journals save after).
game:BindToClose(function()
	local ids = {}
	for id in pairs(Lair.fights) do table.insert(ids, id) end
	for _, id in ipairs(ids) do
		local f = Lair.fights[id]
		if f and f.state ~= "won" then Lair.teardown(f, "error", true) end
	end
end)
publish()
if __LairsHarness then __LairsHarness(Lair) end -- headless tests only (nil in Roblox)

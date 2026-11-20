-- Minigames (Minigames team): the Skybreach Bastion, a floating minigame
-- isle reached by the ferry beacon on the Guild Terrace (world.server.lua asks
-- ServerStorage.IsleMinigameAccess, a BindableFunction made here). Two group
-- minigames run one match each per server (rules in Data.Minigames):
--
--   Skybreach Siege (wave defence, 3-10 players). Three landing pads on the
--   bastion plaza (Novice / Veteran / Elite, gated by Combat level). Four rift
--   portals ring the Lumen Keeper; their shields drop one at a time in a random
--   order (the next drops early when a portal falls). Every living portal sends
--   a wave of rift creatures down its lane each WAVE_INTERVAL: lane creatures
--   stop at an intact barricade, flyers cross it and strike nearby defenders
--   (IsleBridge "damage"); creatures that reach the Keeper wear it down. Win by
--   destroying all four portals; lose when the Keeper falls or time runs out.
--   Points: strikes on creatures (+kill bonus) and open portals, barricade
--   repairs (1 Timber through the bridge, Carpentry XP).
--
--   Tempest Haul (skilling boss, 1-10 players; solo pays reduced rewards).
--   Catch stormfish at the spray, cook them at the brazier and load the deck
--   cannons (a cracked mast silences its cannon) to drain the Squall
--   Leviathan's energy; at zero it surfaces for VULNERABLE_SECONDS and the
--   harpoon drains its essence (otherwise it recharges). Squall surges crack
--   masts (repair: Carpentry), lightning lights deck fires (douse) that burn
--   the hull; the haul is lost when the hull breaks or time runs out. Fishing,
--   Cooking and Carpentry XP per action.
--
-- Lobbies (server-authoritative): a pad counts the living players standing on
-- it; with MIN_PLAYERS present (and the arena free) a PAD_SECONDS countdown
-- runs, cancelled when the count drops below the minimum. At launch the first
-- MAX_PLAYERS eligible players on the pad are taken in.
-- Credit: every credited action needs a member, alive, within prompt reach and
-- ACTION_COOLDOWN since the last; points only come from actions, so an idle
-- player has none (MIN_POINTS gates every reward). Members idle (no action,
-- no movement) for IDLE_SECONDS or outside the arena for AWAY_GRACE are
-- removed: they are paid the XP they earned but no reward. A member who
-- disconnects may rejoin within REJOIN_SECONDS and keeps their points.
-- Settlement goes through IsleBridge op "minigame" {action="settle", game,
-- tier, points, won, partySize, seconds, xp} (server.server.lua validates and
-- pays Commendations / Squall Cache rolls / XP and writes the minigame log).
-- Workspace attributes: MinigameLobbies ("<lobby>=<state>,<count>,<seconds>;..."
-- state idle|counting|running), MinigameMatches ("<game>=<players>,<elapsed>;...").
-- Player attributes: MinigameGame ("Siege"|"Haul"|""), MinigameHud ("k=v;..."
-- for the in-game HUD), MinigameNotice / MinigameNoticeCount (toasts).
local Players = game:GetService("Players")
local Storage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Data = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
local MG = Data.Minigames
local S, H = MG.Siege, MG.Haul
local V = Vector3.new
local ORIGIN = V(-2400, 90, 0)
local PLAZA = ORIGIN
local SIEGE_C = ORIGIN + V(0, 0, -170)
local HAUL_C = ORIGIN + V(0, 0, 170)
local LANDING = PLAZA + V(0, 4, 26)
local rng = Random.new()
local function roll() return rng:NextNumber() end
local function C(hex) return Color3.fromHex(hex) end
local dark, teal, gold, ember, sea = C("253447"), C("7FE3CC"), C("F3C66E"), C("EF7D67"), C("2F8FA8")

local bastion = Instance.new("Model")
bastion.Name = MG.ISLAND
bastion:SetAttribute("Minigames", true)
bastion:SetAttribute("IslandCenter", ORIGIN)
bastion.Parent = workspace
local function block(parent, name, pos, size, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.Slate
	p.Parent = parent
	return p
end
local function disk(parent, name, pos, radius, height, color, material)
	local p = block(parent, name, pos, V(height, radius * 2, radius * 2), color, material, true)
	p.Shape = Enum.PartType.Cylinder
	p.Orientation = V(0, 0, 90)
	return p
end
local function caption(part, text, offset)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Caption"
	gui.Size = UDim2.fromOffset(260, 46)
	gui.StudsOffset = V(0, offset or 5, 0)
	gui.MaxDistance = 90
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = dark
	l.BackgroundTransparency = 0.15
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = 15
	l.TextWrapped = true
	l.Text = text
	l.Parent = gui
	return l
end
local function notice(player, text)
	player:SetAttribute("MinigameNotice", text)
	player:SetAttribute("MinigameNoticeCount", (tonumber(player:GetAttribute("MinigameNoticeCount")) or 0) + 1)
end
local function rootOf(player)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then return root, hum end
	return nil
end
local function flat(a, b) local d = a - b; return V(d.X, 0, d.Z).Magnitude end
local function prompt(part, object, action, callback, distance)
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = object
	p.ActionText = action
	p.HoldDuration = 0.25
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(function(player)
		local root = rootOf(player)
		if root and (root.Position - part.Position).Magnitude <= p.MaxActivationDistance + 3 then callback(player, root) end
	end)
	return p
end
local function bridge(op, player, payload)
	local b = Storage:FindFirstChild("IsleBridge")
	if not b then return nil end
	local ok, result = pcall(b.Invoke, b, op, player, payload)
	return if ok then result else nil
end
local function info(player)
	local r = bridge("minigame", player, {action = "info"})
	if type(r) == "table" and type(r.levels) == "table" then return r end
	-- No journal service (tests without a bridge, Studio previews): level 1 everywhere.
	return {levels = {}, combat = 1, lumenward = false}
end

------------------------------------------------------------------------------
-- The bastion: plaza with four lobby pads, the siege ring and the haul deck.
------------------------------------------------------------------------------
disk(bastion, "Bastion plaza", PLAZA, 44, 3, C("3A4C5E"))
disk(bastion, "Siege ring", SIEGE_C, S.LANE + 16, 3, C("2B3B4C"))
local deck = block(bastion, "Haul deck", HAUL_C, V(70, 3, 110), C("6B4E2E"), Enum.Material.WoodPlanks)
block(bastion, "Storm sea", HAUL_C + V(0, -6, 0), V(180, 1, 200), sea, Enum.Material.Glass, false).Transparency = 0.35
local ringEdge = 170 - (S.LANE + 16)
block(bastion, "Causeway", PLAZA + V(0, 0, -(44 + ringEdge) / 2), V(10, 2, ringEdge - 44 + 8), C("2B3B4C"))
block(bastion, "Gangway", PLAZA + V(0, 0, (44 + 115) / 2), V(10, 2, 115 - 44 + 8), C("6B4E2E"), Enum.Material.WoodPlanks)
local anchor = block(bastion, "Anchor_Waypoint_SkybreachLanding", LANDING - V(0, 4, 0), V(1, 1, 1), teal, Enum.Material.SmoothPlastic, false)
anchor.Transparency = 1
anchor.CanQuery = false
anchor:SetAttribute("AnchorPurpose", "Waypoint_SkybreachLanding")
-- Return ferry: back to the Guild Terrace beacon (world anchor), or the quay.
local ferry = block(bastion, "Return ferry beacon", PLAZA + V(0, 4, 36), V(2, 6, 2), teal, Enum.Material.Glass, false)
ferry:SetAttribute("Shape", "WarpBeacon")
ferry:SetAttribute("Tint", teal)
prompt(ferry, "Skybreach ferry", "Return to the Guild Terrace", function(player)
	local home = workspace:FindFirstChild("Anchor_Waypoint_SkybreachFerry", true)
	local destination = if home and home:IsA("BasePart") then home.Position + V(0, 4, 0) else V(0, 8, 232)
	player.Character:PivotTo(CFrame.new(destination))
end)

-- Lobbies: three siege landings and the haul gangway.
local lobbies = {}
local lobbyOrder = {}
for i, t in ipairs(S.Tiers) do
	local pos = PLAZA + V(-20 + (i - 1) * 20, 1.6, -24)
	table.insert(lobbyOrder, {id = "Siege" .. t.id, game = "Siege", tier = t.id, pos = pos, color = C(t.color),
		title = t.name .. " • Combat " .. t.combat .. " • " .. S.MIN_PLAYERS .. "-" .. S.MAX_PLAYERS .. " players"})
end
table.insert(lobbyOrder, {id = "Haul", game = "Haul", pos = PLAZA + V(0, 1.6, 12), color = C(H.color),
	title = H.name .. " • Fishing " .. H.FISHING_LEVEL .. " • 1-" .. H.MAX_PLAYERS .. " players (solo: " .. math.floor(H.SOLO_REWARD * 100) .. "% rewards)"})
for _, l in ipairs(lobbyOrder) do
	local rules = if l.game == "Siege" then S else H
	local pad = disk(bastion, l.id .. " pad", l.pos, rules.PAD_RADIUS, 0.3, l.color, Enum.Material.Neon)
	pad.CanCollide = false
	pad.Transparency = 0.55
	pad:SetAttribute("MinigameLobby", l.id)
	l.pad = pad
	l.label = caption(pad, l.title, 6)
	l.state, l.deadline = "idle", 0
	lobbies[l.id] = l
end

-- Siege ring: Keeper, portals (lane ends), barricades (mid lane).
local keeperPart = block(bastion, "Lumen Keeper", SIEGE_C + V(0, 6, 0), V(5, 10, 5), gold, Enum.Material.Neon)
keeperPart:SetAttribute("Shape", "Obelisk")
keeperPart:SetAttribute("Tint", gold)
local keeperLabel = caption(keeperPart, S.keeper, 8)
local portalParts, barricadeParts, laneDir = {}, {}, {}
for _, def in ipairs(S.Portals) do
	local a = math.rad(def.angle)
	local dir = V(math.cos(a), 0, math.sin(a))
	laneDir[def.id] = dir
	local portal = block(bastion, def.name, SIEGE_C + dir * S.LANE + V(0, 7, 0), V(6, 12, 6), C(def.color), Enum.Material.Neon)
	portal:SetAttribute("PortalId", def.id)
	portal:SetAttribute("Shape", "WarpBeacon")
	portal:SetAttribute("Tint", C(def.color))
	portalParts[def.id] = {part = portal, label = caption(portal, def.name, 9)}
	local barricade = block(bastion, def.name .. " barricade", SIEGE_C + dir * (S.LANE * S.BARRICADE_AT) + V(0, 2.5, 0), V(4, 5, 14), C("8C6A43"), Enum.Material.WoodPlanks, false)
	barricade.CFrame = CFrame.lookAt(barricade.Position, SIEGE_C + V(0, 2.5, 0))
	barricade:SetAttribute("PortalId", def.id)
	barricadeParts[def.id] = barricade
end
-- Haul deck: masts (with their cannons), the spray, the brazier, the harpoon, fire spots and the Leviathan.
local mastParts, cannonParts, fireParts, spotParts = {}, {}, {}, {}
for i = 1, H.MASTS do
	local x = if i == 1 then -18 else 18
	mastParts[i] = block(bastion, "Mast " .. i, HAUL_C + V(x, 14, -10), V(2, 26, 2), C("8C6A43"), Enum.Material.Wood)
	cannonParts[i] = block(bastion, "Cannon " .. i, HAUL_C + V(x * 1.6, 3, -36), V(4, 3, 7), C("3D4752"), Enum.Material.Metal)
end
for i = 1, 3 do spotParts[i] = block(bastion, "Stormfish spray", HAUL_C + V(-30 + (i - 1) * 30, 1.6, 50), V(8, 0.4, 8), C("9BD1E8"), Enum.Material.Glass, false) end
local brazier = block(bastion, "Storm brazier", HAUL_C + V(0, 3, 18), V(4, 4, 4), ember, Enum.Material.Neon)
local harpoon = block(bastion, "Harpoon mount", HAUL_C + V(0, 3, -44), V(3, 4, 3), C("C9974A"), Enum.Material.Metal)
for i = 1, H.FIRE_CAP do
	local f = block(bastion, "Deck fire " .. i, HAUL_C + V(-24 + (i - 1) * 12, 2, 0), V(4, 1, 4), ember, Enum.Material.Neon, false)
	f.Transparency = 1
	fireParts[i] = f
end
local leviathan = block(bastion, H.boss, HAUL_C + V(0, -2, -80), V(30, 10, 18), C("1E3A4C"), Enum.Material.Slate, false)
local leviathanLabel = caption(leviathan, H.boss, 10)

------------------------------------------------------------------------------
-- Match state.
------------------------------------------------------------------------------
local matches = {} -- [game] = match
local memberOf = {} -- [player] = match
local departed = {} -- [UserId] = {match, record, expires}
local matchSeq = 0
local function count(t) local n = 0; for _ in pairs(t) do n += 1 end; return n end
local function centerOf(game) return if game == "Siege" then SIEGE_C else HAUL_C end
local function spawnFor(game) return if game == "Siege" then SIEGE_C + V(0, 5, -14) else HAUL_C + V(0, 5, 30) end

local function hudFor(match, record)
	local parts = {"game=" .. match.game, "points=" .. math.floor(record.points), "min=" .. (if match.game == "Siege" then S.MIN_POINTS else H.MIN_POINTS),
		"time=" .. math.max(0, math.ceil(match.limit - (os.clock() - match.started))), "players=" .. count(match.members)}
	if match.game == "Siege" then
		table.insert(parts, "tier=" .. match.tier)
		table.insert(parts, "keeper=" .. math.max(0, math.ceil(match.keeper)) .. "/" .. match.keeperMax)
		local list = {}
		for _, def in ipairs(S.Portals) do
			local pt = match.portals[def.id]
			table.insert(list, def.id .. ":" .. math.max(0, math.ceil(pt.hp)) .. ":" .. pt.max .. ":" .. (if pt.shielded then 1 else 0))
		end
		table.insert(parts, "portals=" .. table.concat(list, ","))
		local bars = {}
		for _, def in ipairs(S.Portals) do local b = match.barricades[def.id]; table.insert(bars, math.ceil(b.hp) .. "/" .. b.max) end
		table.insert(parts, "barricades=" .. table.concat(bars, ","))
		table.insert(parts, "wave=" .. match.wave)
		table.insert(parts, "creatures=" .. count(match.creatures))
	else
		table.insert(parts, "phase=" .. match.phase)
		table.insert(parts, "energy=" .. math.max(0, math.ceil(match.energy)))
		table.insert(parts, "essence=" .. math.max(0, math.ceil(match.essence)))
		table.insert(parts, "hull=" .. math.max(0, math.ceil(match.hull)))
		local fires, masts = 0, {}
		for i = 1, H.FIRE_CAP do if match.fires[i] then fires += 1 end end
		for i = 1, H.MASTS do table.insert(masts, if match.masts[i] then "1" else "0") end
		table.insert(parts, "fires=" .. fires)
		table.insert(parts, "masts=" .. table.concat(masts, ","))
		table.insert(parts, "raw=" .. record.raw)
		table.insert(parts, "cooked=" .. record.cooked)
	end
	return table.concat(parts, ";")
end
local function publish(match)
	for player, record in pairs(match.members) do
		player:SetAttribute("MinigameGame", match.game)
		player:SetAttribute("MinigameHud", hudFor(match, record))
	end
	if match.game == "Siege" then
		keeperLabel.Text = S.keeper .. " • " .. math.max(0, math.ceil(match.keeper)) .. " / " .. match.keeperMax
		for _, def in ipairs(S.Portals) do
			local pt = match.portals[def.id]
			local entry = portalParts[def.id]
			entry.label.Text = def.name .. " • " .. (if not pt.alive then "SEALED" elseif pt.shielded then "SHIELDED" else math.ceil(pt.hp) .. " / " .. pt.max)
			entry.part.Transparency = if pt.alive then (if pt.shielded then 0.45 else 0) else 0.85
		end
	else
		leviathanLabel.Text = H.boss .. " • " .. (if match.phase == "vulnerable" then "ESSENCE " .. math.ceil(match.essence) else "ENERGY " .. math.ceil(match.energy)) .. "%"
		for i = 1, H.FIRE_CAP do fireParts[i].Transparency = if match.fires[i] then 0.2 else 1 end
		for i = 1, H.MASTS do mastParts[i].Color = if match.masts[i] then C("8C6A43") else ember end
	end
end
local function clearHud(player)
	player:SetAttribute("MinigameGame", "")
	player:SetAttribute("MinigameHud", "")
end
local function addXp(record, xp)
	for skill, n in pairs(xp) do record.xp[skill] = (record.xp[skill] or 0) + n end
end
-- Pay one member: XP always, rewards only on a win with the minimum points.
local function settle(player, match, record, won, reason)
	local seconds = math.max(1, math.floor(os.clock() - math.max(match.started, record.joined)))
	local reply = bridge("minigame", player, {action = "settle", game = match.game, tier = match.tier, points = math.floor(record.points),
		won = won == true, partySize = match.size, seconds = seconds, xp = record.xp, forfeit = reason ~= nil})
	record.xp = {}
	local text = reason or (if won then (if match.game == "Siege" then "The rifts are sealed!" else "The Squall Leviathan is driven off!") else
		(if match.game == "Siege" then "The Lumen Keeper has fallen." else "The haul is lost."))
	if type(reply) == "table" and type(reply.message) == "string" and reply.message ~= "" then text ..= " " .. reply.message end
	notice(player, text)
	return reply
end
local function removeMember(player, match, reason)
	local record = match.members[player]
	if not record then return end
	match.members[player] = nil
	memberOf[player] = nil
	clearHud(player)
	settle(player, match, record, false, reason)
	local root = rootOf(player)
	if root and player.Character then player.Character:PivotTo(CFrame.new(LANDING)) end
end
local function finish(match, won)
	if matches[match.game] ~= match then return end
	matches[match.game] = nil
	for player, record in pairs(match.members) do
		memberOf[player] = nil
		clearHud(player)
		settle(player, match, record, won)
		if rootOf(player) then player.Character:PivotTo(CFrame.new(LANDING)) end
	end
	match.members = {}
	for id, d in pairs(departed) do if d.match == match then departed[id] = nil end end
	if match.game == "Siege" then
		for _, c in pairs(match.creatures) do c.part:Destroy() end
		match.creatures = {}
		keeperLabel.Text = S.keeper
		for _, def in ipairs(S.Portals) do portalParts[def.id].label.Text = def.name; portalParts[def.id].part.Transparency = 0 end
	else
		for i = 1, H.FIRE_CAP do fireParts[i].Transparency = 1 end
		for i = 1, H.MASTS do mastParts[i].Color = C("8C6A43") end
		leviathanLabel.Text = H.boss
	end
end
-- A credited action: member, cooldown, refreshes the idle timer.
local function actor(player, game)
	local match = memberOf[player]
	if not match or match.game ~= game or matches[game] ~= match then return nil end
	local record = match.members[player]
	local now = os.clock()
	if now < record.ready then return nil end
	record.ready = now + MG.ACTION_COOLDOWN
	record.active = now
	return match, record
end
local function credit(match, record, amount)
	-- Sanity cap: never more than MAX_POINTS_PER_SECOND per second of the match.
	local cap = MG.MAX_POINTS_PER_SECOND * math.max(1, os.clock() - record.joined + 1)
	record.points = math.min(record.points + amount, cap)
end

------------------------------------------------------------------------------
-- Skybreach Siege.
------------------------------------------------------------------------------
local function dropShield(match)
	while match.dropIndex <= #match.order do
		local id = match.order[match.dropIndex]
		match.dropIndex += 1
		local pt = match.portals[id]
		if pt.alive and pt.shielded then
			pt.shielded = false
			for player in pairs(match.members) do notice(player, S.PortalById[id].name .. "'s shield is down! Strike it!") end
			break
		end
	end
	match.nextDrop = os.clock() + S.DROP_INTERVAL
end
local function spawnCreature(match, portalId)
	if count(match.creatures) >= S.CREATURE_CAP then return end
	local id = S.pickCreature(roll())
	local def = S.CreatureById[id]
	match.seq += 1
	local seq = match.seq
	local dir = laneDir[portalId]
	local part = block(bastion, def.name, SIEGE_C + dir * (S.LANE - 6) + V(0, 2, 0), V(3, 3, 3), C(def.color), Enum.Material.SmoothPlastic, false)
	part:SetAttribute("Creature", id)
	local hp = S.creatureHp(id, match.tier)
	local c = {id = id, def = def, hp = hp, max = hp, portal = portalId, dist = S.LANE - 6, part = part, attack = 0, seq = seq}
	match.creatures[seq] = c
	prompt(part, def.name, "Strike", function(player)
		local m, record = actor(player, "Siege")
		if m ~= match or not match.creatures[seq] then return end
		local dmg = S.strikeDamage(record.combat, match.tier, record.lumenward)
		c.hp -= dmg
		credit(match, record, S.Points.strike)
		if c.hp <= 0 then
			match.creatures[seq] = nil
			part:Destroy()
			credit(match, record, S.Points.kill)
		end
		publish(match)
	end, 12)
end
local function siegeStep(match, dt)
	local now = os.clock()
	if now >= match.nextDrop then dropShield(match) end
	match.waveTimer += dt
	if match.waveTimer >= S.WAVE_INTERVAL then
		match.waveTimer = 0
		match.wave += 1
		for _, def in ipairs(S.Portals) do
			if match.portals[def.id].alive then
				for _ = 1, S.waveSize(match.tier, match.size) do spawnCreature(match, def.id) end
			end
		end
	end
	local barricadeDist = S.LANE * S.BARRICADE_AT
	for seq, c in pairs(match.creatures) do
		local dir = laneDir[c.portal]
		local bar = match.barricades[c.portal]
		local stop = if c.def.target == "lane" and bar.hp > 0 then barricadeDist + 2.5 else S.HIT_RANGE
		if c.dist > stop then
			c.dist = math.max(stop, c.dist - c.def.speed * dt)
			c.part.Position = SIEGE_C + dir * c.dist + V(0, 2, 0)
		else
			c.attack += dt
			if c.attack >= 1 then
				c.attack -= 1
				local dmg = S.creatureDamage(c.id, match.tier)
				if stop > S.HIT_RANGE then
					bar.hp = math.max(0, bar.hp - dmg * (c.def.breaker or 1))
				else
					match.keeper -= dmg * (c.def.keeperMult or 1)
				end
			end
		end
		-- Flyers strike the nearest defender within FLYER_RANGE every second.
		if c.def.target == "flyer" then
			c.zap = (c.zap or 0) + dt
			if c.zap >= 2 then
				c.zap = 0
				for player in pairs(match.members) do
					local root = rootOf(player)
					if root and flat(root.Position, c.part.Position) <= S.FLYER_RANGE then
						bridge("damage", player, {amount = S.creatureDamage(c.id, match.tier) * 3})
						break
					end
				end
			end
		end
	end
	if match.keeper <= 0 then finish(match, false) return end
	if now - match.started >= match.limit then finish(match, false) return end
end
local function startSiege(tierId, players)
	matchSeq += 1
	local scaled = S.scaled(tierId, #players)
	local match = {game = "Siege", id = matchSeq, tier = tierId, size = #players, started = os.clock(), limit = S.TIME_LIMIT, members = {},
		keeper = scaled.keeper, keeperMax = scaled.keeper, portals = {}, barricades = {}, creatures = {}, seq = 0, wave = 0, waveTimer = S.WAVE_INTERVAL - 4,
		order = S.shieldOrder(roll), dropIndex = 1, nextDrop = os.clock() + S.FIRST_DROP}
	for _, def in ipairs(S.Portals) do
		match.portals[def.id] = {hp = scaled.portal, max = scaled.portal, shielded = true, alive = true}
		match.barricades[def.id] = {hp = scaled.barricade, max = scaled.barricade, repair = scaled.repair}
	end
	return match
end
for _, def in ipairs(S.Portals) do
	local id = def.id
	prompt(portalParts[id].part, def.name, "Strike portal", function(player)
		local match = matches.Siege
		if not match or memberOf[player] ~= match then return end
		local pt = match.portals[id]
		if not pt.alive then return end
		if pt.shielded then notice(player, def.name .. " is shielded. Wait for its shield to drop.") return end
		local m, record = actor(player, "Siege")
		if not m then return end
		pt.hp -= S.strikeDamage(record.combat, match.tier, record.lumenward)
		credit(match, record, S.Points.portal)
		if pt.hp <= 0 then
			pt.alive = false
			pt.hp = 0
			for member in pairs(match.members) do notice(member, def.name .. " is sealed!") end
			local open = 0
			for _, p in pairs(match.portals) do if p.alive then open += 1 end end
			if open == 0 then publish(match); finish(match, true) return end
			-- The next shield drops now (if any still stands).
			local shielded = false
			for _, p in pairs(match.portals) do if p.alive and p.shielded then shielded = true end end
			if shielded then dropShield(match) end
		end
		publish(match)
	end, 14)
	prompt(barricadeParts[id], def.name .. " barricade", "Repair (1 Timber)", function(player)
		local match = matches.Siege
		if not match or memberOf[player] ~= match then return end
		local bar = match.barricades[id]
		if bar.hp >= bar.max then notice(player, "This barricade is already sound.") return end
		local record = match.members[player]
		if os.clock() < record.ready then return end
		local paid = bridge("minigame", player, {action = "spend", item = "Timber", amount = S.REPAIR_TIMBER})
		if type(paid) ~= "table" or paid.ok ~= true then notice(player, "Repairs need " .. S.REPAIR_TIMBER .. " Timber in your satchel.") return end
		local m, rec = actor(player, "Siege")
		if not m then return end
		bar.hp = math.min(bar.max, bar.hp + bar.repair)
		credit(match, rec, S.Points.repair)
		addXp(rec, {Carpentry = S.repairXp(rec.carpentry)})
		publish(match)
	end, 10)
end

------------------------------------------------------------------------------
-- Tempest Haul.
------------------------------------------------------------------------------
local function haulAction(player, action, fn)
	local match = matches.Haul
	if not match or memberOf[player] ~= match then return end
	local record = match.members[player]
	if os.clock() < record.ready then return end
	local okay, why = fn(match, record, true)
	if not okay then if why then notice(player, why) end return end
	local m, rec = actor(player, "Haul")
	if not m then return end
	fn(match, rec, false)
	credit(match, rec, if action == "load" then (if rec.loaded == "cooked" then H.Points.loadCooked else H.Points.loadRaw) else H.Points[action])
	addXp(rec, H.actionXp(action, rec.levels))
	publish(match)
	if match.essence <= 0 then finish(match, true) end
end
for i, spot in ipairs(spotParts) do
	prompt(spot, "Stormfish spray", "Catch stormfish", function(player)
		haulAction(player, "catch", function(match, rec, check)
			if rec.raw + rec.cooked >= H.CARRY then return false, "Your arms are full (" .. H.CARRY .. " stormfish). Cook or load them." end
			if not check then rec.raw += 1 end
			return true
		end)
	end, 10)
end
prompt(brazier, "Storm brazier", "Cook stormfish", function(player)
	haulAction(player, "cook", function(match, rec, check)
		if rec.raw < 1 then return false, "Catch a raw stormfish first." end
		if not check then rec.raw -= 1; rec.cooked += 1 end
		return true
	end)
end, 10)
for i = 1, H.CANNONS do
	prompt(cannonParts[i], "Deck cannon " .. i, "Load cannon", function(player)
		haulAction(player, "load", function(match, rec, check)
			if match.phase ~= "energy" then return false, "The Leviathan has surfaced: man the harpoon!" end
			if not match.masts[i] then return false, "Mast " .. i .. " is cracked: repair it before this cannon can fire." end
			if rec.raw + rec.cooked < 1 then return false, "Bring stormfish to load the cannon." end
			if not check then
				local cooked = rec.cooked > 0
				if cooked then rec.cooked -= 1 else rec.raw -= 1 end
				rec.loaded = if cooked then "cooked" else "raw"
				match.energy = math.max(0, match.energy - H.energyHit(cooked, match.size))
				if match.energy <= 0 then
					match.phase = "vulnerable"
					match.vulnerableUntil = os.clock() + H.VULNERABLE_SECONDS
					for member in pairs(match.members) do notice(member, "The " .. H.boss .. " surfaces! Harpoon it!") end
				end
			end
			return true
		end)
	end, 10)
	prompt(mastParts[i], "Mast " .. i, "Repair mast", function(player)
		haulAction(player, "repair", function(match, rec, check)
			if match.masts[i] then return false, "Mast " .. i .. " is sound." end
			if not check then match.masts[i] = true end
			return true
		end)
	end, 10)
end
for i = 1, H.FIRE_CAP do
	prompt(fireParts[i], "Deck fire", "Douse fire", function(player)
		haulAction(player, "douse", function(match, rec, check)
			if not match.fires[i] then return false, nil end
			if not check then match.fires[i] = false end
			return true
		end)
	end, 10)
end
prompt(harpoon, "Harpoon mount", "Harpoon the Leviathan", function(player)
	haulAction(player, "harpoon", function(match, rec, check)
		if match.phase ~= "vulnerable" then return false, "The " .. H.boss .. " is out of reach. Drain its energy with the cannons." end
		if not check then match.essence = math.max(0, match.essence - H.essenceHit(match.size)) end
		return true
	end)
end, 12)
local function haulStep(match, dt)
	local now = os.clock()
	if now >= match.nextSurge then
		match.nextSurge = now + H.SURGE_INTERVAL
		local intact = {}
		for i = 1, H.MASTS do if match.masts[i] then table.insert(intact, i) end end
		if #intact > 0 then
			local i = intact[math.clamp(math.floor(roll() * #intact) + 1, 1, #intact)]
			match.masts[i] = false
			for player in pairs(match.members) do notice(player, "A squall surge cracks mast " .. i .. "!") end
		end
	end
	if now >= match.nextFire then
		match.nextFire = now + H.FIRE_INTERVAL
		local free = {}
		for i = 1, H.FIRE_CAP do if not match.fires[i] then table.insert(free, i) end end
		if #free > 0 then match.fires[free[math.clamp(math.floor(roll() * #free) + 1, 1, #free)]] = true end
	end
	local burning = 0
	for i = 1, H.FIRE_CAP do if match.fires[i] then burning += 1 end end
	match.hull -= burning * H.FIRE_BURN * dt
	if match.phase == "vulnerable" and now >= match.vulnerableUntil then
		match.phase = "energy"
		match.energy = H.RECHARGE
		for player in pairs(match.members) do notice(player, "The " .. H.boss .. " dives and recharges. Load the cannons!") end
	end
	if match.hull <= 0 then finish(match, false) return end
	if now - match.started >= match.limit then finish(match, false) return end
end
local function startHaul(players)
	matchSeq += 1
	local match = {game = "Haul", id = matchSeq, size = #players, started = os.clock(), limit = H.TIME_LIMIT, members = {},
		energy = H.ENERGY, essence = H.ESSENCE, phase = "energy", vulnerableUntil = 0, hull = H.HULL, fires = {}, masts = {},
		nextSurge = os.clock() + H.SURGE_INTERVAL, nextFire = os.clock() + H.FIRE_INTERVAL}
	for i = 1, H.MASTS do match.masts[i] = true end
	return match
end

------------------------------------------------------------------------------
-- Lobbies, launch, idle/away rules, rejoin.
------------------------------------------------------------------------------
local function onPad(player, lobby)
	local root = rootOf(player)
	if not root then return false end
	local rules = if lobby.game == "Siege" then S else H
	return flat(root.Position, lobby.pad.Position) <= rules.PAD_RADIUS and math.abs(root.Position.Y - lobby.pad.Position.Y) <= 12
end
local function padPlayers(lobby)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not memberOf[player] and onPad(player, lobby) then table.insert(list, player) end
	end
	return list
end
local function newRecord(player, details)
	return {points = 0, xp = {}, ready = 0, active = os.clock(), joined = os.clock(), raw = 0, cooked = 0,
		combat = tonumber(details.combat) or 1, levels = details.levels or {}, carpentry = tonumber((details.levels or {}).Carpentry) or 1,
		lumenward = details.lumenward == true, userId = player.UserId}
end
local function launch(lobby)
	local rules = if lobby.game == "Siege" then S else H
	local eligible = {}
	for _, player in ipairs(padPlayers(lobby)) do
		if #eligible >= rules.MAX_PLAYERS then notice(player, "The " .. rules.name .. " is full; stay on the pad for the next match.") continue end
		local details = info(player)
		local ok, why = true, nil
		if lobby.game == "Siege" then ok, why = S.canEnter(lobby.tier, details.combat)
		elseif (tonumber(details.levels.Fishing) or 1) < H.FISHING_LEVEL then ok, why = false, H.name .. " needs Fishing " .. H.FISHING_LEVEL .. "." end
		if ok then table.insert(eligible, {player = player, details = details}) else notice(player, why) end
	end
	if #eligible < rules.MIN_PLAYERS then
		for _, e in ipairs(eligible) do notice(e.player, "Not enough eligible players (" .. rules.MIN_PLAYERS .. " needed). The countdown restarts.") end
		return false
	end
	local list = {}
	for _, e in ipairs(eligible) do table.insert(list, e.player) end
	local match = if lobby.game == "Siege" then startSiege(lobby.tier, list) else startHaul(list)
	matches[lobby.game] = match
	for _, e in ipairs(eligible) do
		match.members[e.player] = newRecord(e.player, e.details)
		memberOf[e.player] = match
		e.player.Character:PivotTo(CFrame.new(spawnFor(lobby.game)))
		notice(e.player, rules.name .. " begins • " .. #eligible .. " player" .. (if #eligible == 1 then "" else "s") .. ". " .. rules.rules)
	end
	publish(match)
	return true
end
local function publishLobbies()
	local parts = {}
	for _, l in ipairs(lobbyOrder) do
		local running = matches[l.game]
		local state = if running then "running" else l.state
		local seconds = if l.state == "counting" then math.max(0, math.ceil(l.deadline - os.clock())) else 0
		table.insert(parts, l.id .. "=" .. state .. "," .. (l.count or 0) .. "," .. seconds)
		l.label.Text = l.title .. "\n" .. (if running then "Match in progress" elseif l.state == "counting" then "Launching in " .. seconds .. "s" else
			(l.count or 0) .. " on the pad")
	end
	workspace:SetAttribute("MinigameLobbies", table.concat(parts, ";"))
	local m = {}
	for _, game in ipairs(MG.Order) do
		local match = matches[game]
		table.insert(m, game .. "=" .. (if match then count(match.members) .. "," .. math.floor(os.clock() - match.started) else "0,0"))
	end
	workspace:SetAttribute("MinigameMatches", table.concat(m, ";"))
end
local lastPublish = 0
local function step(dt)
	local now = os.clock()
	for _, l in ipairs(lobbyOrder) do
		local rules = if l.game == "Siege" then S else H
		local busy = matches[l.game] ~= nil
		local list = if busy then {} else padPlayers(l)
		l.count = #list
		if busy then l.state = "idle"
		elseif l.state == "counting" then
			if #list < rules.MIN_PLAYERS then
				l.state = "idle"
				for _, player in ipairs(list) do notice(player, "Countdown cancelled: " .. rules.MIN_PLAYERS .. " players needed.") end
			elseif now >= l.deadline then
				l.state = "idle"
				-- A refused launch (too few eligible) waits a full countdown before retrying.
				if not launch(l) then l.hold = now + rules.PAD_SECONDS end
			end
		elseif #list >= rules.MIN_PLAYERS and now >= (l.hold or 0) then
			l.state = "counting"
			l.deadline = now + rules.PAD_SECONDS
			for _, player in ipairs(list) do notice(player, rules.name .. " launches in " .. rules.PAD_SECONDS .. "s. Stay on the pad.") end
		end
	end
	for game, match in pairs(matches) do
		-- Idle / away rules.
		for player, record in pairs(match.members) do
			local root = rootOf(player)
			if root then
				if not record.pos or (root.Position - record.pos).Magnitude > 1 then record.pos = root.Position; record.moved = now end
				if flat(root.Position, centerOf(game)) > MG.AWAY_RADIUS then record.awaySince = record.awaySince or now else record.awaySince = nil end
			end
			local lastSign = math.max(record.active, record.moved or record.active)
			if record.awaySince and now - record.awaySince > MG.AWAY_GRACE then
				removeMember(player, match, "You left the " .. (if game == "Siege" then S.name else H.name) .. " and were removed (no reward).")
			elseif now - lastSign > MG.IDLE_SECONDS or now - record.active > MG.IDLE_SECONDS * 2 then
				removeMember(player, match, "Removed for inactivity after " .. MG.IDLE_SECONDS .. " s (no reward).")
			end
		end
		if matches[game] ~= match then continue end
		if game == "Siege" then siegeStep(match, dt) else haulStep(match, dt) end
		if matches[game] == match and next(match.members) == nil then
			local waiting = false
			for _, d in pairs(departed) do if d.match == match then waiting = true end end
			if not waiting then finish(match, false) end
		end
	end
	for id, d in pairs(departed) do if now > d.expires then departed[id] = nil end end
	if now - lastPublish >= 0.25 then
		lastPublish = now
		publishLobbies()
		for _, match in pairs(matches) do publish(match) end
	end
end
RunService.Heartbeat:Connect(step)

-- Rejoin: a dropped member's record waits REJOIN_SECONDS for their return.
local function rejoin(player)
	local d = departed[player.UserId]
	if not d or os.clock() > d.expires or matches[d.match.game] ~= d.match then return end
	departed[player.UserId] = nil
	local match = d.match
	d.record.active, d.record.moved, d.record.pos, d.record.awaySince = os.clock(), os.clock(), nil, nil
	match.members[player] = d.record
	memberOf[player] = match
	if player.Character then player.Character:PivotTo(CFrame.new(spawnFor(match.game))) end
	notice(player, "Welcome back to the " .. (if match.game == "Siege" then S.name else H.name) .. " • your " .. math.floor(d.record.points) .. " points were kept.")
	publish(match)
end
local function watch(player)
	if player.CharacterAdded then
		player.CharacterAdded:Connect(function(character)
			local match = memberOf[player]
			if match then
				-- Fallen members respawn into their match.
				local root = character:WaitForChild("HumanoidRootPart", 5)
				if root and memberOf[player] == match then character:PivotTo(CFrame.new(spawnFor(match.game))) end
			else
				rejoin(player)
			end
		end)
	end
	if player.Character then rejoin(player) end
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	local match = memberOf[player]
	if not match then return end
	local record = match.members[player]
	match.members[player] = nil
	memberOf[player] = nil
	departed[player.UserId] = {match = match, record = record, expires = os.clock() + MG.REJOIN_SECONDS}
end)

-- Ferry gate (world.server.lua's Guild Terrace beacon): Combat or Fishing high
-- enough for at least one game.
local access = Instance.new("BindableFunction")
access.Name = "IsleMinigameAccess"
access.OnInvoke = function(player)
	local details = info(player)
	local combat, fishing = tonumber(details.combat) or 1, tonumber(details.levels.Fishing) or 1
	if combat >= S.Tiers[1].combat or fishing >= H.FISHING_LEVEL then
		return {allowed = true, landing = LANDING}
	end
	return {allowed = false, message = MG.ISLAND .. ": reach Combat " .. S.Tiers[1].combat .. " (Skybreach Siege) or Fishing " .. H.FISHING_LEVEL .. " (Tempest Haul) to board the ferry."}
end
access.Parent = Storage
publishLobbies()

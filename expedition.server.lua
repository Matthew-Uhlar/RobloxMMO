-- The Hollow Observatory: one shared, server-authoritative dungeon run per server.
-- Floors I-V (Data.DungeonFloors) are chosen at the entry daises; a party of up
-- to five forms on the matchmaking pad (stand on it within 10 s). Each run is
-- prisms -> two sentinels -> floor boss, with per-floor mechanics:
--   II+  prisms must be tuned in the order shown on each prism (wrong = mistake, reset)
--   III+ the boss raises a shield at HP thresholds until the prisms are retuned
--   IV+  waves of umbral wisps ward the boss while alive
--   V    enrage timer: boss damage and tempo rise after Data floor.enrage.after s
-- Every boss telegraphs its attack (warning disc + heart VisualState "Warning").
-- Clear score = speed + survival + puzzle (Data.dungeonScore) -> grade S+..D.
-- Credit rules (documented in GameData Dungeons section):
--   * contributed: damage + 5%-of-floor-HP per tuning >= 10% of the party total;
--     tuning counts for at most half of that threshold, and in a party the delver
--     must also deal >= 5% of the party's damage (tuning alone never earns a chest)
--   * Ironman: credited only when solo or >= 30% of party damage
--   * cooldown: 90 s between reward credits per player (also enforced in profile)
-- Rewards are paid by ServerStorage.IsleExpeditionGrant (BindableFunction, returns
-- {ok, reason}) in server.server.lua; the IsleExpeditionReward BindableEvent is the
-- fallback. Payload {floor, grade, score, seconds, deaths, mistakes, partySize, damageShare}.
-- A run that is not cleared ends (no reward) after twice the floor's par time, and
-- delvers idle for 90 s (no damage, tuning or movement) or away from the arena are removed.
local Players = game:GetService("Players")
local Storage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local Data = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
local Rules = Data.Dungeons
local origin = Vector3.new(0, 42, 1800)
-- Run limits (M4/M5): see the header.
local IDLE_LIMIT, AWAY_RADIUS, AWAY_GRACE, RUN_CAP_PARS = 90, 120, 10, 2
local MIN_DAMAGE_SHARE, TUNE_CAP_OF_THRESHOLD = 0.05, 0.5
local arenaAnchors = {origin, origin + Vector3.new(0, 0, -110)}
local dark = Color3.fromRGB(37, 52, 71)
local gold = Color3.fromRGB(255, 193, 94)
local teal = Color3.fromRGB(66, 223, 205)
local violet = Color3.fromRGB(142, 124, 195)
local arena = Instance.new("Model")
arena.Name = "The Hollow Observatory"
arena.Parent = workspace

local function block(name, offset, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = origin + offset
	p.Color = color
	p.Material = material
	p.Parent = arena
	return p
end
local function artwork(anchor,shape,scale)
	anchor.Transparency=1
	anchor:SetAttribute("Shape",shape)
	anchor:SetAttribute("SculptureScale",scale)
	anchor:SetAttribute("VisualState","Active")
	CollectionService:AddTag(anchor,"AetherSculpture")
end

local function prompt(part, title, action, callback, distance)
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = title
	p.ActionText = action
	p.HoldDuration = 0.35
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(function(player)
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and (root.Position - part.Position).Magnitude <= p.MaxActivationDistance + 3 then
			callback(player, c)
		end
	end)
	return p
end
local function notice(player, text)
	player:SetAttribute("ExpeditionNotice", text)
end

block("Observatory floor", Vector3.zero, Vector3.new(76, 3, 76), dark, Enum.Material.Slate)
for i = 0, 7 do
	local angle = math.pi * i / 4
	local offset = Vector3.new(math.cos(angle) * 33, 5, math.sin(angle) * 33)
	block("Ruined pier", offset, Vector3.new(4, 11, 4), dark, Enum.Material.Basalt)
	block("Beacon", offset + Vector3.yAxis * 6, Vector3.new(3, 1, 3), teal, Enum.Material.Neon)
end
local heart = block("Eclipse Heart", Vector3.new(0, 6, 0), Vector3.new(7, 7, 7), gold, Enum.Material.Neon)
heart.Shape = Enum.PartType.Ball
artwork(heart,"EclipseAstrolabe",1.25)
local label = Instance.new("BillboardGui")
label.Size = UDim2.fromOffset(340, 64)
label.StudsOffset = Vector3.new(0, 7, 0)
label.MaxDistance = 105
label.Parent = heart
local caption = Instance.new("TextLabel")
caption.Size = UDim2.fromScale(1, 1)
caption.BackgroundColor3 = dark
caption.BackgroundTransparency = 0.12
caption.Font = Enum.Font.GothamBold
caption.TextColor3 = Color3.new(1, 1, 1)
caption.TextSize = 17
caption.Parent = label

-- Run state. members[player] = {last, damage, tunes, mistakes, ironman, down}
local members, pylons, charged, roles, selected = {}, {}, {}, {}, {}
local lastCredit = setmetatable({}, {__mode = "k"})
local known = {}
local guardians, adds = {}, {}
local lobby = nil
local run = {}
local function floorDef() return Data.DungeonFloors[run.floor or 1] end
local function totalHp(stats) return stats.guardianHp * 2 + stats.coreHp end
local function newRun(floorIndex)
	local stats = Data.dungeonFloorStats(floorIndex)
	run = {floor = floorIndex, stats = stats, active = false, stage = "prisms", remaining = 3, nextPrism = 1, seed = (run.seed or 0),
		health = stats.coreHp, guardianHealth = {stats.guardianHp, stats.guardianHp}, pulse = 0, telegraph = nil,
		attacks = 0, shieldIndex = 1, shielded = false, waveTimer = 0, enraged = false, startedAt = 0,
		deaths = 0, mistakes = 0, totalDamage = 0, totalTunes = 0, partySize = 0}
end
newRun(1)
local function guardsAlive()
	return run.guardianHealth[1] > 0 or run.guardianHealth[2] > 0
end
local function warded()
	for _, add in adds do if add.hp > 0 then return true end end
	return false
end
local function tunePoints(record)
	return record.tunes * Rules.tuneWeight * totalHp(run.stats)
end
-- Credited points: tuning counts for at most half the contribution threshold.
local function points(record, totalPoints)
	local cap = TUNE_CAP_OF_THRESHOLD * Rules.contributionShare * totalPoints
	return record.damage + math.min(tunePoints(record), cap)
end
local function touch(record) record.active = os.clock() end
local function orderOf(i)
	-- Ordered floors rotate which prism comes first each run.
	return ((i - 1 + run.seed) % 3) + 1
end

block("Sentinel hall floor", Vector3.new(0, 0, -110), Vector3.new(60, 3, 60), dark, Enum.Material.Slate)
for _, x in ipairs({-29,29}) do
	block("Sentinel hall wall", Vector3.new(x, 7, -110), Vector3.new(2, 14, 60), dark, Enum.Material.Basalt)
end
local passage = block("Sentinel passage", Vector3.new(0, 3, -26), Vector3.new(5, 5, 3), teal, Enum.Material.Glass)
local returnPassage = block("Core passage", Vector3.new(0, 3, -135), Vector3.new(5, 5, 3), gold, Enum.Material.Glass)
prompt(passage, "Sentinel hall", "Enter guardian chamber", function(player, character)
	if members[player] and run.stage ~= "prisms" then character:PivotTo(CFrame.new(origin + Vector3.new(0,5,-87))) end
end)
prompt(returnPassage, "Observatory core", "Return to core", function(player, character)
	if members[player] and run.stage == "core" then character:PivotTo(CFrame.new(origin + Vector3.new(0,5,-22))) end
end)
local warning = block("Pulse radius", Vector3.new(0, 1.6, 0), Vector3.new(0.12, 27, 27), gold, Enum.Material.Neon)
warning.Shape = Enum.PartType.Cylinder
warning.Orientation = Vector3.new(0, 0, 90)
warning.CanCollide = false
warning.Transparency = 1

local function display()
	local f = floorDef()
	local boss = f.boss
	heart:SetAttribute("Floor", f.index)
	heart:SetAttribute("BossName", boss.name)
	heart:SetAttribute("BossHealth", run.health)
	heart:SetAttribute("BossMaxHealth", run.stats.coreHp)
	heart:SetAttribute("Enraged", run.enraged)
	local locked = run.stage ~= "core" or run.shielded or warded()
	heart:SetAttribute("VisualState", if locked then "Shielded" elseif run.telegraph then "Warning" else "Active")
	local title = string.upper(boss.name) .. (if run.enraged then " ENRAGED" else "")
	local tuned = (3 - run.remaining) .. " / 3"
	local order = if f.mechanics.orderedPrisms then " in order" else ""
	if not run.active and lobby then
		local wait = math.max(0, math.ceil(lobby.deadline - os.clock()))
		caption.Text = "MATCHMAKING  •  " .. string.upper(Data.DungeonFloors[lobby.floor].name) .. "\nStand on the pad  •  launching in " .. wait .. "s"
	elseif run.stage == "prisms" then
		caption.Text = "HOLLOW OBSERVATORY  •  FLOOR " .. f.numeral .. "\nTune the prisms" .. order .. "  •  " .. tuned
	elseif run.stage == "guardians" then
		caption.Text = "SENTINEL HALL\nEnter the northern passage • defeat both guardians"
	elseif run.shielded then
		caption.Text = title .. " SHIELDED  •  " .. run.health .. " / " .. run.stats.coreHp .. "\nRetune the prisms" .. order .. "  •  " .. tuned
	elseif warded() then
		caption.Text = title .. " WARDED  •  " .. run.health .. " / " .. run.stats.coreHp .. "\nDestroy the umbral wisps"
	else
		local hint = if run.telegraph == "ring" then "Close in: the ring strikes the outer floor"
			elseif run.telegraph == "meteor" then "Starfall marked: scatter from the target"
			else "Step outside the amber pulse"
		caption.Text = title .. "  •  " .. run.health .. " / " .. run.stats.coreHp .. "\n" .. hint
	end
end
local function paintPrisms()
	local ordered = floorDef().mechanics.orderedPrisms
	for i, p in pylons do
		local tuned = charged[i] == true
		p.Color = if tuned then gold else teal
		p:SetAttribute("VisualState", if tuned then "Tuned" else "Active")
		p:SetAttribute("TuneOrder", if ordered then orderOf(i) else 0)
		local text = if ordered then "Resonance prism • tune " .. orderOf(i) .. " of 3" else "Resonance prism"
		for _, child in p:GetChildren() do
			if child:IsA("ProximityPrompt") then child.ObjectText = text end
		end
	end
end
local function clearAdds()
	for _, add in adds do if add.part.Parent then add.part:Destroy() end end
	table.clear(adds)
end
local function reset()
	table.clear(charged)
	clearAdds()
	newRun(run.floor or 1)
	for _, guardian in guardians do guardian.Color = gold;guardian:SetAttribute("VisualState","Active") end
	warning.Transparency = 1
	paintPrisms()
	display()
end
local function credit(record, amount)
	touch(record)
	record.damage += amount
	run.totalDamage += amount
end
for index, x in ipairs({-13,13}) do
	local guardian = block("Sentinel "..index, Vector3.new(x,5,-112), Vector3.new(5,8,5), gold, Enum.Material.Metal)
	artwork(guardian,"ObservatorySentinel",1.4)
	table.insert(guardians, guardian)
	prompt(guardian, "Sentinel • defeat to open the core passage", "Strike guardian", function(player, character)
		local member = members[player]
		if not member or run.stage ~= "guardians" or run.guardianHealth[index] <= 0 or os.clock()-member.last < 0.8 then return end
		member.last = os.clock()
		local hit = math.min(run.guardianHealth[index], if roles[player]=="Berserk" then 2 else 1)
		run.guardianHealth[index] -= hit
		credit(member, hit)
		if run.guardianHealth[index] == 0 then guardian.Color = dark;guardian:SetAttribute("VisualState","Defeated") else
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local counter = run.stats.guardianHit
			humanoid:TakeDamage(if roles[player]=="Tank" then math.floor(counter / 2) else counter)
		end
		if not guardsAlive() then
			run.stage = "core"
			run.waveTimer = if floorDef().mechanics.addWaves then floorDef().mechanics.addWaves.every else 0
		end
		display()
	end)
end
for i = 1, 3 do
	local a = i * math.pi * 2 / 3
	local p = block("Resonance prism", Vector3.new(math.cos(a)*22, 5, math.sin(a)*22), Vector3.new(3, 7, 3), teal, Enum.Material.Neon)
	p.Orientation = Vector3.new(0, i*45, 12)
	artwork(p,"AetherCrystal",1.3)
	table.insert(pylons, p)
	prompt(p, "Resonance prism", "Tune prism", function(player)
		local member = members[player]
		local tuning = run.stage == "prisms" or (run.stage == "core" and run.shielded)
		if not member or not tuning or charged[i] then return end
		if floorDef().mechanics.orderedPrisms and orderOf(i) ~= run.nextPrism then
			-- Wrong resonance: the whole sequence collapses and counts as a puzzle mistake.
			run.mistakes += 1
			member.mistakes += 1
			table.clear(charged)
			run.remaining, run.nextPrism = 3, 1
			notice(player, "Wrong resonance! Tune the prisms in the order shown.")
			paintPrisms()
			display()
			return
		end
		charged[i] = true
		touch(member)
		member.tunes += 1
		run.totalTunes += 1
		run.nextPrism += 1
		run.remaining -= 1
		if run.remaining == 0 then
			if run.stage == "prisms" then run.stage = "guardians" else run.shielded = false end
		end
		paintPrisms()
		display()
	end)
end
local gate, pad
local function leave(player, character)
	members[player] = nil
	if character and gate and gate.Parent then
		character:PivotTo(gate.CFrame + Vector3.new(0, 5, 0))
	end
	if not next(members) and run.active then reset() end
end
local function finish()
	local f = floorDef()
	local seconds = os.clock() - run.startedAt
	local score, parts = Data.dungeonScore(f.index, seconds, run.deaths, run.mistakes)
	local grade = Data.dungeonGrade(score)
	local totalPoints = run.totalDamage + run.totalTunes * Rules.tuneWeight * totalHp(run.stats)
	local reward = Storage:FindFirstChild("IsleExpeditionReward")
	local summary = f.name .. " • " .. grade .. " • score " .. score .. " (speed " .. math.floor(parts.speed) .. ", survival "
		.. parts.survival .. ", puzzle " .. parts.skill .. ")"
	for participant, record in table.clone(members) do
		local character = participant.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local share = if run.totalDamage > 0 then record.damage / run.totalDamage else 0
		local reason
		if not (root and humanoid and humanoid.Health > 0 and (root.Position - origin).Magnitude <= 60) then
			reason = "Stand in the Observatory, alive, when the boss falls to earn the chest."
		elseif not Data.dungeonContributed(points(record, totalPoints), totalPoints) then
			reason = "Contribute at least " .. math.floor(Rules.contributionShare * 100) .. "% of the party's damage and tuning to earn the chest (tuning counts for at most half)."
		elseif run.partySize > 1 and share < MIN_DAMAGE_SHARE then
			reason = "Deal at least " .. math.floor(MIN_DAMAGE_SHARE * 100) .. "% of the party's damage to earn the chest."
		elseif not Data.dungeonIronmanCredit(record.ironman, run.partySize, share) then
			reason = "Ironman credit needs a solo clear or " .. math.floor(Rules.ironmanDamageShare * 100) .. "% of the party's damage."
		elseif not Data.dungeonCooldownReady(lastCredit[participant], os.clock()) then
			reason = "Chest cooldown: wait " .. math.ceil(Rules.clearCooldown - (os.clock() - lastCredit[participant])) .. "s between credited clears."
		end
		participant:SetAttribute("DungeonResult", summary)
		if reason then
			notice(participant, reason)
		else
			local payload = {floor = f.index, grade = grade, score = score, seconds = math.floor(seconds), deaths = run.deaths,
				mistakes = run.mistakes, partySize = run.partySize, damageShare = share}
			-- The profile may still refuse (lease lapsed, floor gate, cooldown): only an
			-- accepted grant opens the chest and starts this script's cooldown.
			local grant = Storage:FindFirstChild("IsleExpeditionGrant")
			local granted, why
			if grant then
				local ok, result = pcall(grant.Invoke, grant, participant, payload)
				granted = ok and type(result) == "table" and result.ok == true
				why = if ok and type(result) == "table" and type(result.reason) == "string" then result.reason else nil
			elseif reward then
				reward:Fire(participant, payload)
				granted = true
			end
			if granted then
				lastCredit[participant] = os.clock()
				notice(participant, "Chest opened! " .. summary)
			else
				notice(participant, why or "The Observatory chest could not be credited to your journal. Try another clear.")
			end
		end
		leave(participant, participant.Character)
	end
	if run.active then reset() end
end
local function strike(player, ranged)
	local member = members[player]
	local role = roles[player]
	if ranged and role ~= "Mage" and role ~= "Archer" then return end
	local recovery = if role == "Mage" then 2.4 elseif role == "Archer" then 1.2 else 0.8
	if not member or run.stage ~= "core" or run.shielded or warded() or os.clock() - member.last < recovery then return end
	member.last = os.clock()
	local hit = math.min(run.health, if role == "Mage" then 3 elseif role == "Berserk" then 2 else 1)
	run.health -= hit
	credit(member, hit)
	if roles[player] == "Healer" then
		for ally in members do
			local character = ally.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 and (root.Position-heart.Position).Magnitude <= 20 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 3)
			end
		end
	end
	if run.health <= 0 then finish() return end
	local phases = floorDef().mechanics.shieldPhases
	local threshold = phases and phases[run.shieldIndex]
	if threshold and run.health <= run.stats.coreHp * threshold then
		run.shieldIndex += 1
		run.shielded = true
		table.clear(charged)
		run.remaining, run.nextPrism = 3, 1
		run.seed += 1
		paintPrisms()
	end
	display()
end
prompt(heart, "Eclipse Heart", "Strike core", function(player) strike(player, false) end)
local rangedPrompt = prompt(heart, "Mage / Archer", "Ranged attack", function(player) strike(player, true) end, 32)
rangedPrompt.KeyboardKeyCode = Enum.KeyCode.F
rangedPrompt.UIOffset = Vector2.new(0, 80)
local exit = block("Return arch", Vector3.new(0, 4, 29), Vector3.new(5, 5, 3), teal, Enum.Material.Glass)
prompt(exit, "Return arch", "Leave expedition", leave)

local function spawnWave()
	local wave = floorDef().mechanics.addWaves
	for n = 1, wave.count do
		local a = (n / wave.count + #adds * 0.17) * math.pi * 2
		local part = block("Umbral wisp", Vector3.new(math.cos(a) * 16, 4, math.sin(a) * 16), Vector3.new(3, 3, 3), violet, Enum.Material.Neon)
		part.Shape = Enum.PartType.Ball
		local add = {part = part, hp = run.stats.addHp}
		part:SetAttribute("AddHealth", add.hp)
		table.insert(adds, add)
		prompt(part, "Umbral wisp • wards the boss", "Strike wisp", function(player)
			local member = members[player]
			if not member or add.hp <= 0 or os.clock() - member.last < 0.8 then return end
			member.last = os.clock()
			local hit = math.min(add.hp, if roles[player] == "Berserk" or roles[player] == "Mage" then 2 else 1)
			add.hp -= hit
			credit(member, hit)
			part:SetAttribute("AddHealth", add.hp)
			if add.hp <= 0 then part:Destroy() end
			display()
		end)
	end
end
local function attackKind()
	local kind = floorDef().boss.kind
	if kind == "eclipse" then return if run.attacks % 2 == 0 then "pulse" else "ring" end
	return kind
end
local function beginTelegraph()
	local boss = floorDef().boss
	local kind = attackKind()
	run.telegraph = kind
	local center = heart.Position
	local size = boss.radius * 2
	if kind == "meteor" then
		-- Starfall marks the delver holding the most threat (highest damage).
		local best, bestDamage = nil, -1
		for player, record in members do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and record.damage > bestDamage then best, bestDamage = root, record.damage end
		end
		center = if best then best.Position else center
	elseif kind == "ring" then
		size = boss.radius * 2
	end
	run.target = center
	warning.Size = Vector3.new(0.12, size, size)
	warning.Position = Vector3.new(center.X, origin.Y + 1.6, center.Z)
	warning.Color = if kind == "ring" then teal elseif kind == "meteor" then violet else gold
	warning:SetAttribute("SafeRadius", if kind == "ring" then boss.inner else 0)
	warning.Transparency = 0.25
	heart:SetAttribute("Telegraph", boss.attack)
end
local function resolveAttack()
	local f = floorDef()
	local boss = f.boss
	local kind = run.telegraph or attackKind()
	local enrage = f.mechanics.enrage
	local base = boss.damage * (if run.enraged and enrage then enrage.damageMult else 1)
	local center = run.target or heart.Position
	for player in members do
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum and root then
			local distance = (root.Position - center).Magnitude
			local hit = if kind == "ring" then distance > boss.inner and distance <= boss.radius else distance <= boss.radius
			if hit then
				local damage = if roles[player] == "Tank" then math.floor(base / 2) else math.floor(base)
				local defense = math.clamp(player:GetAttribute("SkillDefense") or 0, 0, 5)
				hum:TakeDamage(math.max(1, damage - defense))
			end
		end
	end
	run.attacks += 1
	run.telegraph, run.target = nil, nil
	warning.Transparency = 1
	warning.Position = origin + Vector3.new(0, 1.6, 0)
	heart:SetAttribute("Telegraph", "")
end
local function onPad(player)
	if not pad then return false end
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return false end
	local offset = root.Position - gate.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Rules.padRadius and math.abs(offset.Y) <= 12
end
local function profileInfo(player)
	local bridge = Storage:FindFirstChild("IsleBridge")
	if bridge then
		local ok, result = pcall(bridge.Invoke, bridge, "dungeon", player)
		if ok and type(result) == "table" then
			return {level = tonumber(result.level) or 1, ironman = result.ironman == true}
		end
	end
	return {level = 1, ironman = false}
end
local function launch()
	local floorIndex = lobby.floor
	lobby = nil
	if pad then pad:SetAttribute("LobbyFloor", 0) end
	local joined = {}
	for _, player in ipairs(table.clone(known)) do
		if #joined >= Rules.maxParty then
			if onPad(player) then notice(player, "The party is full (" .. Rules.maxParty .. " delvers).") end
		elseif onPad(player) and not members[player] then
			local info = profileInfo(player)
			if Data.dungeonFloorUnlocked(floorIndex, info.level) then
				table.insert(joined, {player = player, info = info})
			else
				notice(player, "Requires Dungeoneering " .. Data.DungeonFloors[floorIndex].level .. " for " .. Data.DungeonFloors[floorIndex].name .. ".")
			end
		end
	end
	if #joined == 0 then display() return end
	local seed = (run.seed or 0) + 1
	table.clear(charged)
	clearAdds()
	newRun(floorIndex)
	run.seed = seed
	run.active = true
	run.startedAt = os.clock()
	run.partySize = #joined
	for _, guardian in guardians do guardian.Color = gold;guardian:SetAttribute("VisualState","Active") end
	for _, entry in joined do
		members[entry.player] = {last = 0, damage = 0, tunes = 0, mistakes = 0, ironman = entry.info.ironman, down = false, active = os.clock()}
		entry.player:SetAttribute("ExpeditionFloor", floorIndex)
		notice(entry.player, Data.DungeonFloors[floorIndex].name .. " begins • party of " .. #joined .. ".")
		entry.player.Character:PivotTo(CFrame.new(origin + Vector3.new(0, 5, 24)))
	end
	paintPrisms()
	display()
end
paintPrisms()
display()
RunService.Heartbeat:Connect(function(dt)
	if lobby then
		if os.clock() >= lobby.deadline then launch() else display() end
	end
	if not next(members) then return end
	local now = os.clock()
	-- M4: a run that is not cleared in twice the floor's par collapses with no reward.
	if run.active and now - run.startedAt >= RUN_CAP_PARS * floorDef().par then
		for participant in table.clone(members) do
			notice(participant, "The Observatory collapsed: " .. floorDef().name .. " was not cleared in time. No chest this run.")
			leave(participant, participant.Character)
		end
		if run.active then reset() end
		return
	end
	-- M4: idle delvers (no damage, tuning or movement for 90 s) or delvers away
	-- from the arena for more than a few seconds are removed from the party.
	for participant, record in table.clone(members) do
		local root = participant.Character and participant.Character:FindFirstChild("HumanoidRootPart")
		if root and not record.down then
			local pos = root.Position
			if not record.pos or (pos - record.pos).Magnitude > 1 then record.pos = pos; touch(record) end
			local nearest = math.huge
			for _, anchor in arenaAnchors do nearest = math.min(nearest, (pos - anchor).Magnitude) end
			if nearest > AWAY_RADIUS then
				record.awaySince = record.awaySince or now
			else
				record.awaySince = nil
			end
		else
			record.awaySince = nil
		end
		local why
		if record.awaySince and now - record.awaySince > AWAY_GRACE then
			why = "You left the Observatory and were removed from the expedition."
		elseif not record.down and now - (record.active or now) > IDLE_LIMIT then
			why = "Removed from the expedition after " .. IDLE_LIMIT .. " s without fighting, tuning or moving."
		end
		if why then
			notice(participant, why)
			leave(participant, participant.Character)
		end
	end
	if not next(members) then return end
	-- Deaths count once per fall; a fallen delver respawns into the run.
	for player, record in members do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 and not record.down then
			record.down = true
			run.deaths += 1
		elseif hum and hum.Health > 0 then
			record.down = false
		end
	end
	if run.stage ~= "core" then return end
	local f = floorDef()
	local enrage = f.mechanics.enrage
	if enrage and not run.enraged and os.clock() - run.startedAt >= enrage.after then
		run.enraged = true
		display()
	end
	local wave = f.mechanics.addWaves
	if wave and not run.shielded then
		run.waveTimer += dt
		if run.waveTimer >= wave.every then
			run.waveTimer = 0
			spawnWave()
			display()
		end
	end
	local boss = f.boss
	local tempo = if run.enraged and enrage then enrage.intervalMult else 1
	local interval = boss.interval * tempo
	local telegraph = math.min(boss.telegraph, interval * 0.6)
	run.pulse += dt
	if not run.telegraph and run.pulse >= interval - telegraph then
		beginTelegraph()
		display()
	end
	if run.pulse >= interval then
		run.pulse = 0
		resolveAttack()
		display()
	end
end)
local function watch(player)
	if not table.find(known, player) then table.insert(known, player) end
	player.CharacterRemoving:Connect(function(character)
		local record = members[player]
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if record and run.active and (record.down or (hum and hum.Health <= 0)) then
			-- Fallen delvers stay in the party and respawn at the Observatory entry.
			if not record.down then record.down = true; run.deaths += 1 end
			return
		end
		leave(player)
	end)
	if player.CharacterAdded then
		player.CharacterAdded:Connect(function(character)
			local record = members[player]
			if not record or not run.active then return end
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root and members[player] then character:PivotTo(CFrame.new(origin + Vector3.new(0, 5, 24))) end
		end)
	end
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	leave(player)
	roles[player], selected[player] = nil, nil
	local index = table.find(known, player)
	if index then table.remove(known, index) end
end)
local function openLobby(player)
	if run.active then notice(player, "A party is inside the Observatory. Wait for their run to end.") return end
	if lobby then notice(player, "Stand on the pad: " .. Data.DungeonFloors[lobby.floor].name .. " launches soon.") return end
	local floorIndex = selected[player] or 1
	local info = profileInfo(player)
	if not Data.dungeonFloorUnlocked(floorIndex, info.level) then
		notice(player, "Requires Dungeoneering " .. Data.DungeonFloors[floorIndex].level .. ".")
		return
	end
	lobby = {floor = floorIndex, deadline = os.clock() + Rules.padSeconds}
	if pad then pad:SetAttribute("LobbyFloor", floorIndex) end
	notice(player, Data.DungeonFloors[floorIndex].name .. " forming • stand on the pad for " .. Rules.padSeconds .. "s (max " .. Rules.maxParty .. ").")
	display()
end
local function attach(part)
	if gate or part.Name ~= "ExpeditionGate" or not part:IsA("BasePart") then return end
	gate = part
	pad = Instance.new("Part")
	pad.Name = "Matchmaking pad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.2, Rules.padRadius * 2, Rules.padRadius * 2)
	pad.Orientation = Vector3.new(0, 0, 90)
	pad.Position = part.Position - Vector3.new(0, part.Size.Y / 2 - 0.15, 0)
	pad.Color = teal
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.6
	pad:SetAttribute("LobbyFloor", 0)
	pad.Parent = arena
	for index, role in ipairs({"Berserk", "Healer", "Tank", "Mage", "Archer"}) do
		local pedestal = block(role .. " oath", Vector3.zero, Vector3.new(2, 3, 2), teal, Enum.Material.Slate)
		pedestal.Position = part.Position + Vector3.new((index-3)*4, 0, 7)
		local description = ({Berserk="Double core damage", Healer="Strikes heal nearby allies", Tank="Half pulse damage",
			Mage="Slow ranged burst", Archer="Quick ranged shots"})[role]
		prompt(pedestal, role .. " • " .. description, "Choose role", function(player)
			if members[player] then return end
			roles[player] = role
			player:SetAttribute("ExpeditionRole", role)
		end)
	end
	for index, def in ipairs(Data.DungeonFloors) do
		local dais = block(def.name, Vector3.zero, Vector3.new(2, 2 + index * 0.4, 2), if index == 1 then teal else violet, Enum.Material.Slate)
		dais.Position = part.Position + Vector3.new((index-3)*4, 0, -8)
		dais:SetAttribute("FloorIndex", index)
		dais:SetAttribute("RequiredLevel", def.level)
		prompt(dais, def.name .. " • " .. def.subtitle .. " • Dungeoneering " .. def.level, "Select floor", function(player)
			if members[player] then return end
			local info = profileInfo(player)
			if not Data.dungeonFloorUnlocked(index, info.level) then
				notice(player, "Requires Dungeoneering " .. def.level .. " (you are " .. info.level .. ").")
				return
			end
			selected[player] = index
			player:SetAttribute("ExpeditionFloor", index)
			notice(player, def.name .. " selected • boss: " .. def.boss.name .. ".")
		end)
	end
	prompt(part, "Hollow Observatory", "Enter expedition", function(player)
		if members[player] then return end
		openLobby(player)
	end)
end
workspace.DescendantAdded:Connect(attach)
for _, part in workspace:GetDescendants() do attach(part) end

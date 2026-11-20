-- The Hollow Observatory: one shared, server-authoritative dungeon run per server.
-- Floors I-VII (Data.DungeonFloors) are chosen at the entry daises; a party of up
-- to five forms on the matchmaking pad (stand on it within 10 s). Each run is
-- prisms -> two sentinels -> floor boss, with per-floor mechanics:
--   II+  prisms must be tuned in the order shown on each prism (wrong = mistake, reset)
--   III+ the boss raises a shield at HP thresholds until the prisms are retuned
--   IV+  waves of umbral wisps ward the boss while alive (wisp HP ~ sqrt of the floor HP
--        multiplier; the wave timer pauses while a full wave lives; at most DC.WISP_CAP alive)
--   V    enrage timer: boss damage and tempo rise after Data floor.enrage.after s
--   VI+  the boss regenerates while wisps live; Converging Lances mark every delver
--   VII  overload below 50% HP (faster strikes); Eventide Collapse cycles pulse/ring/lances
-- Every boss telegraphs its attack (warning disc + heart VisualState "Warning").
-- Dungeon classes (Data.DungeonClasses): one class per delver, chosen at the
-- class pedestals by the pad or on the Dungeon page (both write the profile
-- through the IsleBridge "dungeonClass" op; runs read only the profile, or the
-- DungeonClass attribute when no bridge exists); duplicates allowed, unique
-- compositions of the delvers credited at the end earn a team bonus. Passives shape strikes and damage taken; the
-- heart carries "Class ability" (Q) and "Ultimate" (R) prompts (also fired by the
-- party HUD's Q / R buttons in ui.client.lua for touch screens), validated here
-- with cooldowns/charges (DC.abilityCheck). Hidden secrets (caches and levers)
-- spawn each run. Master Mode (floors I-V, after an S+) doubles HP and damage; its par is x1.6.
-- Second Dawn (boss phase only) arms one forgiven fall for 20 s; it never stacks.
-- Clear score = DC.score: speed + survival + puzzle + secrets (x0.75) + bonus -> grade S+..D.
-- Credit rules (documented in GameData Dungeons section):
--   * contributed: damage + 5%-of-floor-HP per tuning >= 10% of the party total;
--     tuning counts for at most half of that threshold, and in a party the delver
--     must also deal >= 5% of the party's damage (tuning alone never earns a chest)
--   * Ironman: credited only when solo or >= 30% of party damage
--   * cooldown: 90 s between reward credits per player (also enforced in profile)
-- Rewards are paid by ServerStorage.IsleExpeditionGrant (BindableFunction, returns
-- {ok, reason}) in server.server.lua; the IsleExpeditionReward BindableEvent is the
-- fallback. Payload {floor, grade, score, seconds, deaths, mistakes, partySize, damageShare,
-- class, master, secrets, secretsTotal, bonus, teamMult, feat}.
-- A run that is not cleared ends (no reward) after twice the run's par time (DC.par), and
-- delvers idle for 90 s (no damage, tuning or movement) or away from the arena are removed.
-- Player attributes: DungeonClass, DungeonInRun, DungeonParty ("Name|Class|Level;..."),
-- DungeonAbilityReady (seconds), DungeonUltimates (charges left), DungeonMasterPick.
local Players = game:GetService("Players")
local Storage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local Data = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
local Rules = Data.Dungeons
local DC = Data.DungeonClasses
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

-- Run state. members[player] = {last, damage, tunes, mistakes, ironman, down, class, level,
-- carry, readyAt, ultimatesUsed, ultimateAt, healed, wispKills, feat}
local members, pylons, charged, selected, masterPick = {}, {}, {}, {}, {}
local lastCredit = setmetatable({}, {__mode = "k"})
local known = {}
local guardians, adds, secretParts, lanceMarks = {}, {}, {}, {}
local lobby = nil
local run = {}
local function floorDef() return Data.DungeonFloors[run.floor or 1] end
local function totalHp(stats) return stats.guardianHp * 2 + stats.coreHp end
local function newRun(floorIndex, master)
	local stats = DC.floorStats(floorIndex, master)
	run = {floor = floorIndex, master = master == true, stats = stats, active = false, stage = "prisms", remaining = 3, nextPrism = 1, seed = (run.seed or 0),
		health = stats.coreHp, guardianHealth = {stats.guardianHp, stats.guardianHp}, pulse = 0, telegraph = nil,
		attacks = 0, shieldIndex = 1, shielded = false, waveTimer = 0, regenTimer = 0, enraged = false, startedAt = 0,
		deaths = 0, mistakes = 0, totalDamage = 0, totalTunes = 0, partySize = 0,
		secretsFound = 0, secretsTotal = 0, bastion = 0, bastionBy = nil, bulwark = nil, forgive = nil, team = DC.teamBonus({})}
end
newRun(1)
local function guardsAlive()
	return run.guardianHealth[1] > 0 or run.guardianHealth[2] > 0
end
local function warded()
	for _, add in adds do if add.hp > 0 then return true end end
	return false
end
local function liveWisps()
	local n = 0
	for _, add in adds do if add.hp > 0 then n += 1 end end
	return n
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
-- Class hit for a strike kind (melee/guardian/wisp/ranged); unclassed delvers hit for 1.
local function classHit(record, kind)
	local def = record and DC.defs[record.class]
	if not def then return 1 end
	local base = if kind == "ranged" then (def.attack.ranged and def.attack.ranged.damage or 0) else (def.attack[kind] or 1)
	local hit, carry = DC.hit(base, record.class, record.level, record.carry)
	record.carry = carry
	return hit
end
local function takenMult(player)
	local record = members[player]
	return if record then DC.damageTakenMult(record.class, record.level) else 1
end
local function earnFeat(record, featId)
	local def = record and DC.defs[record.class]
	if def and def.feat.id == featId and not record.feat then record.feat = true end
end
-- A fall: Second Dawn forgives one within its window (armed once, never stacked).
local function countFall()
	local grace = run.forgive
	run.forgive = nil
	if grace and os.clock() <= grace.expires then return end
	run.deaths += 1
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
	heart:SetAttribute("MasterMode", run.master)
	heart:SetAttribute("SecretsFound", run.secretsFound)
	heart:SetAttribute("SecretsTotal", run.secretsTotal)
	local locked = run.stage ~= "core" or run.shielded or warded()
	heart:SetAttribute("VisualState", if locked then "Shielded" elseif run.telegraph then "Warning" else "Active")
	local title = string.upper(boss.name) .. (if run.enraged then " ENRAGED" else "")
	local tuned = (3 - run.remaining) .. " / 3"
	local order = if f.mechanics.orderedPrisms then " in order" else ""
	local mode = if run.master then "MASTER " else ""
	if not run.active and lobby then
		local wait = math.max(0, math.ceil(lobby.deadline - os.clock()))
		caption.Text = "MATCHMAKING  •  " .. (if lobby.master then "MASTER " else "") .. string.upper(Data.DungeonFloors[lobby.floor].name) .. "\nStand on the pad  •  launching in " .. wait .. "s"
	elseif run.stage == "prisms" then
		caption.Text = "HOLLOW OBSERVATORY  •  " .. mode .. "FLOOR " .. f.numeral .. "\nTune the prisms" .. order .. "  •  " .. tuned
	elseif run.stage == "guardians" then
		caption.Text = "SENTINEL HALL\nEnter the northern passage • defeat both guardians"
	elseif run.shielded then
		caption.Text = title .. " SHIELDED  •  " .. run.health .. " / " .. run.stats.coreHp .. "\nRetune the prisms" .. order .. "  •  " .. tuned
	elseif warded() then
		caption.Text = title .. " WARDED  •  " .. run.health .. " / " .. run.stats.coreHp .. "\nDestroy the umbral wisps"
			.. (if f.mechanics.regen then " before it regenerates" else "")
	else
		local hint = if run.telegraph == "ring" then "Close in: the ring strikes the outer floor"
			elseif run.telegraph == "meteor" then "Starfall marked: scatter from the target"
			elseif run.telegraph == "lances" then "Lances marked: step off your own mark"
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
local function clearSecrets()
	for _, part in secretParts do if part.Parent then part:Destroy() end end
	table.clear(secretParts)
end
local function clearLances()
	for _, part in lanceMarks do if part.Parent then part:Destroy() end end
	table.clear(lanceMarks)
end
local function partyRows()
	local rows = {}
	for _, player in ipairs(known) do
		local record = members[player]
		if record then table.insert(rows, {name = player.Name, class = record.class, level = record.level}) end
	end
	return rows
end
local function publishParty()
	local text = DC.partyString(partyRows())
	for player in members do player:SetAttribute("DungeonParty", text) end
end
local function reset()
	table.clear(charged)
	clearAdds()
	clearSecrets()
	clearLances()
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
		local hit = math.min(run.guardianHealth[index], classHit(member, "guardian"))
		run.guardianHealth[index] -= hit
		credit(member, hit)
		if run.guardianHealth[index] == 0 then
			guardian.Color = dark;guardian:SetAttribute("VisualState","Defeated")
			-- Riftblade feat on floors without wisps: a sentinel's final blow.
			if not floorDef().mechanics.addWaves then earnFeat(member, "Wisps") end
		else
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			humanoid:TakeDamage(math.floor(run.stats.guardianHit * takenMult(player)))
		end
		if not guardsAlive() then
			run.stage = "core"
			run.waveTimer = if floorDef().mechanics.addWaves then floorDef().mechanics.addWaves.every else 0
		end
		display()
	end)
end
-- Tune prism i for a member (by hand or by Attune / Eclipse Rift). Returns true when tuned.
local function tunePrism(i, member, player, spell)
	local tuning = run.stage == "prisms" or (run.stage == "core" and run.shielded)
	if not member or not tuning or charged[i] then return false end
	if floorDef().mechanics.orderedPrisms and orderOf(i) ~= run.nextPrism then
		-- Wrong resonance: the whole sequence collapses and counts as a puzzle mistake.
		run.mistakes += 1
		member.mistakes += 1
		table.clear(charged)
		run.remaining, run.nextPrism = 3, 1
		notice(player, "Wrong resonance! Tune the prisms in the order shown.")
		paintPrisms()
		display()
		return false
	end
	charged[i] = true
	touch(member)
	member.tunes += 1
	run.totalTunes += 1
	run.nextPrism += 1
	run.remaining -= 1
	if spell then earnFeat(member, "Attune") end
	if run.remaining == 0 then
		if run.stage == "prisms" then run.stage = "guardians" else run.shielded = false end
	end
	paintPrisms()
	display()
	return true
end
-- The prism that should be tuned next (correct order on ordered floors).
local function nextPrismIndex()
	local ordered = floorDef().mechanics.orderedPrisms
	for i in pylons do
		if not charged[i] and (not ordered or orderOf(i) == run.nextPrism) then return i end
	end
	return nil
end
for i = 1, 3 do
	local a = i * math.pi * 2 / 3
	local p = block("Resonance prism", Vector3.new(math.cos(a)*22, 5, math.sin(a)*22), Vector3.new(3, 7, 3), teal, Enum.Material.Neon)
	p.Orientation = Vector3.new(0, i*45, 12)
	artwork(p,"AetherCrystal",1.3)
	table.insert(pylons, p)
	prompt(p, "Resonance prism", "Tune prism", function(player)
		tunePrism(i, members[player], player, false)
	end)
end
local gate, pad
local function leave(player, character)
	local was = members[player] ~= nil
	members[player] = nil
	if was then
		player:SetAttribute("DungeonInRun", false)
		player:SetAttribute("DungeonParty", "")
		player:SetAttribute("DungeonAbilityReady", 0)
		player:SetAttribute("DungeonUltimates", 0)
		publishParty()
	end
	if character and gate and gate.Parent then
		character:PivotTo(gate.CFrame + Vector3.new(0, 5, 0))
	end
	if not next(members) and run.active then reset() end
end
local function finish()
	local f = floorDef()
	local seconds = os.clock() - run.startedAt
	local totalPoints = run.totalDamage + run.totalTunes * Rules.tuneWeight * totalHp(run.stats)
	-- Credit first: the team bonus and feats count only delvers still in the run and credited.
	local reasons, classes, feats = {}, {}, 0
	for participant, record in members do
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
		reasons[participant] = reason or false
		if not reason then
			table.insert(classes, record.class or false)
			if record.feat then feats += 1 end
		end
	end
	run.team = DC.teamBonus(classes)
	local bonus = DC.bonusScore(feats, run.team.balanced)
	local score, parts = DC.score(f.index, seconds, run.deaths, run.mistakes, run.secretsFound, run.secretsTotal, bonus, run.master)
	local grade = Data.dungeonGrade(score)
	local reward = Storage:FindFirstChild("IsleExpeditionReward")
	local summary = (if run.master then "Master " else "") .. f.name .. " • " .. grade .. " • score " .. score .. " (speed " .. math.floor(parts.speed) .. ", survival "
		.. parts.survival .. ", puzzle " .. parts.skill .. ", secrets " .. run.secretsFound .. "/" .. run.secretsTotal .. ", bonus " .. parts.bonus .. ")"
	for participant, record in table.clone(members) do
		local share = if run.totalDamage > 0 then record.damage / run.totalDamage else 0
		local reason = reasons[participant] or nil
		participant:SetAttribute("DungeonResult", summary)
		if reason then
			notice(participant, reason)
		else
			local payload = {floor = f.index, grade = grade, score = score, seconds = math.floor(seconds), deaths = run.deaths,
				mistakes = run.mistakes, partySize = run.partySize, damageShare = share,
				class = record.class, master = run.master, secrets = run.secretsFound, secretsTotal = run.secretsTotal,
				bonus = parts.bonus, teamMult = run.team.xpMult, feat = record.feat == true}
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
-- Damage the core (strikes, abilities). Returns false when the run just finished.
local function damageCore(member, amount)
	local hit = math.min(run.health, math.max(0, math.floor(amount)))
	if hit <= 0 then return true end
	run.health -= hit
	credit(member, hit)
	if run.health <= 0 then finish() return false end
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
	return true
end
local function healPlayer(player, amount, healer)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return 0 end
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	local restored = humanoid.Health - before
	if healer then
		-- Self-heals count too, so a solo Mender can earn its feat.
		healer.record.healed += restored
		if healer.record.healed >= (DC.defs.Mender.feat.need or 50) then earnFeat(healer.record, "Heal") end
	end
	return restored
end
local function strike(player, ranged)
	local member = members[player]
	local def = member and DC.defs[member.class]
	local style = def and def.attack.ranged
	if ranged and not style then return end
	local recovery = if ranged then style.recovery else 0.8
	if not member or run.stage ~= "core" or run.shielded or warded() or os.clock() - member.last < recovery then return end
	member.last = os.clock()
	local hit = classHit(member, if ranged then "ranged" else "melee")
	if def and def.attack.heal then
		local amount = DC.healAmount(def.attack.heal, member.level)
		for ally in members do
			local character = ally.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position-heart.Position).Magnitude <= 20 then
				healPlayer(ally, amount, {player = player, record = member})
			end
		end
	end
	if damageCore(member, hit) then display() end
end
prompt(heart, "Eclipse Heart", "Strike core", function(player) strike(player, false) end)
local rangedPrompt = prompt(heart, "Starshot / Arcanist", "Ranged attack", function(player) strike(player, true) end, 32)
rangedPrompt.KeyboardKeyCode = Enum.KeyCode.F
rangedPrompt.UIOffset = Vector2.new(0, 36)
local exit = block("Return arch", Vector3.new(0, 4, 29), Vector3.new(5, 5, 3), teal, Enum.Material.Glass)
prompt(exit, "Return arch", "Leave expedition", leave)

local function hitWisp(add, member, amount)
	if add.hp <= 0 then return end
	local hit = math.min(add.hp, amount)
	add.hp -= hit
	credit(member, hit)
	add.part:SetAttribute("AddHealth", add.hp)
	if add.hp <= 0 then
		add.part:Destroy()
		member.wispKills += 1
		if member.wispKills >= (DC.defs.Riftblade.feat.need or 3) then earnFeat(member, "Wisps") end
	end
end
local function spawnWave()
	local wave = floorDef().mechanics.addWaves
	-- Drop slain wisps from the list; never exceed DC.WISP_CAP live wisps.
	for i = #adds, 1, -1 do
		if adds[i].hp <= 0 then table.remove(adds, i) end
	end
	local room = math.max(0, DC.WISP_CAP - liveWisps())
	for n = 1, math.min(wave.count, room) do
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
			hitWisp(add, member, classHit(member, "wisp"))
			display()
		end)
	end
end
local function attackKind()
	return DC.attackKind(floorDef().boss.kind, run.attacks)
end
local function hideTelegraph()
	run.telegraph, run.target, run.targets = nil, nil, nil
	warning.Transparency = 1
	warning.Position = origin + Vector3.new(0, 1.6, 0)
	heart:SetAttribute("Telegraph", "")
	clearLances()
end
local function beginTelegraph()
	local boss = floorDef().boss
	local kind = attackKind()
	run.telegraph = kind
	local center = heart.Position
	local size = boss.radius * 2
	run.targets = nil
	if kind == "meteor" then
		-- Starfall marks the delver holding the most threat (highest damage).
		local best, bestDamage = nil, -1
		for player, record in members do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and record.damage > bestDamage then best, bestDamage = root, record.damage end
		end
		center = if best then best.Position else center
	elseif kind == "lances" then
		-- Converging Lances mark where every delver stands.
		run.targets = {}
		for player in members do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then table.insert(run.targets, root.Position) end
		end
		center = run.targets[1] or center
		size = (boss.lanceRadius or 8) * 2
		for index = 2, #run.targets do
			local mark = block("Lance mark", Vector3.zero, Vector3.new(0.12, size, size), violet, Enum.Material.Neon)
			mark.Shape = Enum.PartType.Cylinder
			mark.Orientation = Vector3.new(0, 0, 90)
			mark.CanCollide = false
			mark.Transparency = 0.25
			mark.Position = Vector3.new(run.targets[index].X, origin.Y + 1.6, run.targets[index].Z)
			table.insert(lanceMarks, mark)
		end
	end
	run.target = center
	warning.Size = Vector3.new(0.12, size, size)
	warning.Position = Vector3.new(center.X, origin.Y + 1.6, center.Z)
	warning.Color = if kind == "ring" then teal elseif kind == "meteor" or kind == "lances" then violet else gold
	warning:SetAttribute("SafeRadius", if kind == "ring" then boss.inner else 0)
	warning.Transparency = 0.25
	heart:SetAttribute("Telegraph", boss.attack)
end
local function resolveAttack()
	local f = floorDef()
	local boss = f.boss
	local kind = run.telegraph or attackKind()
	local enrage = f.mechanics.enrage
	local base = boss.damage * run.stats.bossDamageMult * (if run.enraged and enrage then enrage.damageMult else 1)
	local center = run.target or heart.Position
	local targets = run.targets
	local lanceRadius = boss.lanceRadius or 8
	run.attacks += 1
	local function struck(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		local distance = (root.Position - center).Magnitude
		if kind == "ring" then
			return distance > boss.inner and distance <= boss.radius
		elseif kind == "lances" then
			for _, at in targets or {} do
				local flat = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
				if flat.Magnitude <= lanceRadius then return true end
			end
			return false
		end
		return distance <= boss.radius
	end
	if run.bastion > 0 then
		-- Bastion of the Isles: the whole party ignores this strike. The Aegis earns
		-- its feat only when the strike would have landed on someone.
		run.bastion -= 1
		local caster = run.bastionBy
		if caster and members[caster.player] == caster.record then
			for player in members do
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and struck(player) then earnFeat(caster.record, "Absorb") break end
			end
		end
		hideTelegraph()
		return
	end
	local guard = run.bulwark
	local guardRecord = guard and members[guard.player]
	local guardHum = guard and guard.player.Character and guard.player.Character:FindFirstChildOfClass("Humanoid")
	if guard and guardRecord and guardHum and guardHum.Health > 0 then
		-- Starwall Bulwark: only the Aegis is struck, at its reduced damage.
		guard.strikes -= 1
		if guard.strikes <= 0 then run.bulwark = nil end
		local defense = math.clamp(guard.player:GetAttribute("SkillDefense") or 0, 0, 5)
		guardHum:TakeDamage(math.max(1, math.floor(base * takenMult(guard.player)) - defense))
		earnFeat(guardRecord, "Absorb")
		hideTelegraph()
		return
	end
	run.bulwark = nil
	for player in members do
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum and root then
			if struck(player) then
				local damage = math.floor(base * takenMult(player))
				local defense = math.clamp(player:GetAttribute("SkillDefense") or 0, 0, 5)
				hum:TakeDamage(math.max(1, damage - defense))
			end
		end
	end
	hideTelegraph()
end

-- Class abilities (Q) and ultimates (R): validated by DC.abilityCheck, effects here.
local function abilityState(player, record)
	return {inRun = run.active and record ~= nil, classId = record and record.class, level = record and record.level or 1,
		now = os.clock(), readyAt = record and record.readyAt or 0, ultimatesUsed = record and record.ultimatesUsed or 0,
		ultimateAt = record and record.ultimateAt, stage = run.stage, shielded = run.shielded, warded = warded(),
		telegraph = run.telegraph, wisps = liveWisps()}
end
local function useAbility(player, kind)
	local record = members[player]
	local ok, why = DC.abilityCheck(kind, abilityState(player, record))
	if not ok then notice(player, why) return false end
	local def = DC.defs[record.class]
	local id = if kind == "ability" then def.ability.id else def.ultimate.id
	local power = DC.abilityPower(record.class, record.level)
	touch(record)
	if kind == "ability" then
		record.readyAt = os.clock() + DC.cooldown(record.class, record.level)
	else
		record.ultimatesUsed += 1
		record.ultimateAt = os.clock()
	end
	local helper = {player = player, record = record}
	if id == "Bulwark" then
		run.bulwark = {player = player, strikes = power}
	elseif id == "Bastion" then
		run.bastion = def.ultimate.power
		run.bastionBy = helper
	elseif id == "MendingLight" then
		for ally in members do
			local hum = ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
			if hum then healPlayer(ally, DC.healAmount(hum.MaxHealth * power, record.level), helper) end
		end
	elseif id == "SecondDawn" then
		for ally in members do
			local hum = ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
			if hum then healPlayer(ally, hum.MaxHealth, helper) end
		end
		-- One forgiven fall within the window; recasting refreshes it, never stacks.
		run.forgive = {expires = os.clock() + (def.ultimate.window or 20)}
	elseif id == "Cleave" then
		for _, add in table.clone(adds) do hitWisp(add, record, power) end
		if not run.shielded and not warded() and not damageCore(record, power) then return true end
	elseif id == "RendingStorm" then
		for _, add in table.clone(adds) do hitWisp(add, record, 5) end
		if not damageCore(record, math.ceil(run.stats.coreHp * def.ultimate.power)) then return true end
	elseif id == "DisruptingShot" then
		hideTelegraph()
		run.pulse = 0
		run.attacks += 1
		earnFeat(record, "Disrupt")
		if not run.shielded and not warded() and not damageCore(record, power) then return true end
	elseif id == "CometVolley" then
		local any = false
		for _, add in table.clone(adds) do
			if add.hp > 0 then any = true; hitWisp(add, record, add.hp) end
		end
		if not any and not run.shielded and not damageCore(record, math.ceil(run.stats.coreHp * def.ultimate.power)) then return true end
	elseif id == "Attune" then
		for _ = 1, power do
			local i = nextPrismIndex()
			if not i or not tunePrism(i, record, player, true) then break end
		end
	elseif id == "EclipseRift" then
		for _ = 1, 3 do
			local i = nextPrismIndex()
			if not i or not tunePrism(i, record, player, true) then break end
		end
	end
	notice(player, (if kind == "ability" then def.ability.name else def.ultimate.name) .. "!")
	display()
	return true
end
local abilityPrompt = prompt(heart, "Class ability", "Class ability", function(player) useAbility(player, "ability") end, 40)
abilityPrompt.KeyboardKeyCode = Enum.KeyCode.Q
abilityPrompt.UIOffset = Vector2.new(0, 72)
local ultimatePrompt = prompt(heart, "Class ultimate", "Ultimate", function(player) useAbility(player, "ultimate") end, 40)
ultimatePrompt.KeyboardKeyCode = Enum.KeyCode.R
ultimatePrompt.UIOffset = Vector2.new(0, 108)

-- Secrets: hidden caches and levers placed per run (DC.secretsFor).
local function placeSecrets()
	clearSecrets()
	local list = DC.secretsFor(run.floor, run.seed)
	run.secretsTotal, run.secretsFound = #list, 0
	for _, spot in list do
		local lever = spot.kind == "lever"
		local part = block(if lever then "Secret lever" else "Secret cache", Vector3.new(spot.x, 2.5, spot.z),
			if lever then Vector3.new(0.6, 2, 0.6) else Vector3.new(1.6, 1, 1.2), if lever then violet else gold, Enum.Material.Slate)
		part.CanCollide = false
		part.Transparency = 0.55
		part:SetAttribute("SecretSpot", spot.spot)
		table.insert(secretParts, part)
		local found = false
		local p = prompt(part, if lever then "Rusted lever" else "Loose flagstone", if lever then "Pull lever" else "Search", function(player)
			local member = members[player]
			if found or not member or not run.active then return end
			found = true
			touch(member)
			run.secretsFound += 1
			part:Destroy()
			for ally in members do notice(ally, "Secret found by " .. player.Name .. " • " .. run.secretsFound .. " / " .. run.secretsTotal .. ".") end
			display()
		end, 6)
		p.HoldDuration = 0.8
	end
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
			return {level = tonumber(result.level) or 1, ironman = result.ironman == true, profile = true,
				class = if DC.valid(result.class) then result.class else nil,
				classXp = if type(result.classXp) == "table" then result.classXp else {},
				best = if type(result.best) == "table" then result.best else {}, master = result.master == true}
		end
	end
	return {level = 1, ironman = false, classXp = {}, best = {}, master = false}
end
-- The profile's class (pedestal and Dungeon page both write it); the attribute
-- published from the profile is the fallback when no bridge answers.
local function classFor(player, info)
	if info.profile then return info.class end
	local attr = player:GetAttribute("DungeonClass")
	return if DC.valid(attr) then attr else nil
end
local function masterOpen(info, floorIndex)
	return DC.masterUnlocked(floorIndex, tonumber(info.best[floorIndex]) or 0)
end
local function launch()
	local floorIndex, master = lobby.floor, lobby.master
	lobby = nil
	if pad then pad:SetAttribute("LobbyFloor", 0); pad:SetAttribute("LobbyMaster", false) end
	local joined = {}
	for _, player in ipairs(table.clone(known)) do
		if #joined >= Rules.maxParty then
			if onPad(player) then notice(player, "The party is full (" .. Rules.maxParty .. " delvers).") end
		elseif onPad(player) and not members[player] then
			local info = profileInfo(player)
			if not Data.dungeonFloorUnlocked(floorIndex, info.level) then
				notice(player, "Requires Dungeoneering " .. Data.DungeonFloors[floorIndex].level .. " for " .. Data.DungeonFloors[floorIndex].name .. ".")
			elseif master and not masterOpen(info, floorIndex) then
				notice(player, "Master Mode " .. Data.DungeonFloors[floorIndex].name .. " needs an S+ clear of the floor first.")
			else
				table.insert(joined, {player = player, info = info})
			end
		end
	end
	if #joined == 0 then display() return end
	local seed = (run.seed or 0) + 1
	table.clear(charged)
	clearAdds()
	newRun(floorIndex, master)
	run.seed = seed
	run.active = true
	run.startedAt = os.clock()
	run.partySize = #joined
	for _, guardian in guardians do guardian.Color = gold;guardian:SetAttribute("VisualState","Active") end
	local classes = {}
	for _, entry in joined do
		local class = classFor(entry.player, entry.info)
		local level = if class then DC.levelForXp(tonumber(entry.info.classXp[class]) or 0) else 1
		table.insert(classes, class or false)
		members[entry.player] = {last = 0, damage = 0, tunes = 0, mistakes = 0, ironman = entry.info.ironman, down = false, active = os.clock(),
			class = class, level = level, carry = 0, readyAt = 0, ultimatesUsed = 0, ultimateAt = nil, healed = 0, wispKills = 0, feat = false}
		entry.player:SetAttribute("ExpeditionFloor", floorIndex)
		entry.player:SetAttribute("DungeonInRun", true)
		entry.player:SetAttribute("DungeonUltimates", if class then DC.ultimateCharges(level) else 0)
		entry.player:SetAttribute("DungeonAbilityReady", 0)
		notice(entry.player, (if master then "Master " else "") .. Data.DungeonFloors[floorIndex].name .. " begins • party of " .. #joined .. ".")
		entry.player.Character:PivotTo(CFrame.new(origin + Vector3.new(0, 5, 24)))
	end
	run.team = DC.teamBonus(classes) -- launch preview; finish() recomputes from credited delvers
	heart:SetAttribute("TeamUnique", run.team.unique)
	heart:SetAttribute("TeamBalanced", run.team.balanced)
	placeSecrets()
	publishParty()
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
	if run.active and now - run.startedAt >= RUN_CAP_PARS * run.stats.par then
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
	-- Deaths count once per fall (Second Dawn forgives one); a fallen delver respawns into the run.
	for player, record in members do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 and not record.down then
			record.down = true
			countFall()
		elseif hum and hum.Health > 0 then
			record.down = false
		end
		-- Ability HUD: whole seconds until the class ability is ready, ultimates left.
		if record.class then
			local ready = math.max(0, math.ceil(record.readyAt - now))
			if ready ~= record.shownReady then record.shownReady = ready; player:SetAttribute("DungeonAbilityReady", ready) end
			local left = math.max(0, DC.ultimateCharges(record.level) - record.ultimatesUsed)
			if left ~= record.shownUlt then record.shownUlt = left; player:SetAttribute("DungeonUltimates", left) end
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
	-- The wave timer pauses while a full wave still lives (and spawnWave caps live wisps).
	if wave and not run.shielded and liveWisps() < wave.count then
		run.waveTimer += dt
		if run.waveTimer >= wave.every then
			run.waveTimer = 0
			spawnWave()
			display()
		end
	end
	-- VI+: the boss regenerates while any umbral wisp lives.
	local regen = f.mechanics.regen
	if regen and warded() then
		run.regenTimer += dt
		if run.regenTimer >= regen.every then
			run.regenTimer = 0
			run.health = math.min(run.stats.coreHp, run.health + math.ceil(run.stats.coreHp * regen.fraction))
			display()
		end
	elseif regen then
		run.regenTimer = 0
	end
	local boss = f.boss
	local tempo = if run.enraged and enrage then enrage.intervalMult else 1
	local overload = f.mechanics.overload
	if overload and run.health <= run.stats.coreHp * overload.below then tempo *= overload.intervalMult end
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
			if not record.down then
				record.down = true
				countFall()
			end
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
	selected[player], masterPick[player] = nil, nil
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
	local wantMaster = masterPick[player]
	if wantMaster == nil then wantMaster = player:GetAttribute("DungeonMasterOn") == true end
	local master = wantMaster and floorIndex <= DC.MASTER_FLOORS
	if master and not masterOpen(info, floorIndex) then
		notice(player, "Master Mode unlocks on " .. Data.DungeonFloors[floorIndex].name .. " after an S+ clear. Switch it off at the Master lever.")
		return
	end
	lobby = {floor = floorIndex, master = master, deadline = os.clock() + Rules.padSeconds}
	if pad then pad:SetAttribute("LobbyFloor", floorIndex); pad:SetAttribute("LobbyMaster", master) end
	notice(player, (if master then "Master " else "") .. Data.DungeonFloors[floorIndex].name .. " forming • stand on the pad for " .. Rules.padSeconds .. "s (max " .. Rules.maxParty .. ").")
	display()
end
-- Class choice: pedestal by the pad, persisted through the IsleBridge "dungeonClass" op.
-- The profile is the single source of truth: Classes.choose publishes DungeonClass.
local function chooseClass(player, class)
	if members[player] then notice(player, "Your class is locked until this run ends.") return end
	local bridge = Storage:FindFirstChild("IsleBridge")
	if bridge then
		local ok, result = pcall(bridge.Invoke, bridge, "dungeonClass", player, {class = class})
		if not (ok and type(result) == "table" and result.ok == true) then
			notice(player, "Your journal could not record the class. Try again in a moment.")
			return
		end
	else
		player:SetAttribute("DungeonClass", class)
	end
	local def = DC.defs[class]
	notice(player, def.name .. " (" .. def.role .. ") chosen • " .. def.ability.name .. " (Q), " .. def.ultimate.name .. " (R).")
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
	pad:SetAttribute("LobbyMaster", false)
	pad.Parent = arena
	for index, class in ipairs(DC.order) do
		local def = DC.defs[class]
		local pedestal = block(class .. " oath", Vector3.zero, Vector3.new(2, 3, 2), teal, Enum.Material.Slate)
		pedestal.Position = part.Position + Vector3.new((index-3)*4, 0, 7)
		pedestal:SetAttribute("DungeonClass", class)
		prompt(pedestal, def.name .. " • " .. def.role .. " • " .. def.passive, "Choose class", function(player)
			chooseClass(player, class)
		end)
	end
	local lever = block("Master lever", Vector3.zero, Vector3.new(1, 4, 1), violet, Enum.Material.Slate)
	lever.Position = part.Position + Vector3.new(14, 0, 0)
	prompt(lever, "Master Mode • floors I-V after an S+ • ×2 HP and damage, par ×1.6, ×2.2 XP and coins, extra chest roll", "Toggle Master Mode", function(player)
		if members[player] then return end
		local current = masterPick[player]
		if current == nil then current = player:GetAttribute("DungeonMasterOn") == true end
		masterPick[player] = not current
		player:SetAttribute("DungeonMasterPick", not current)
		notice(player, "Master Mode " .. (if not current then "on" else "off") .. " for the next run you open.")
	end)
	for index, def in ipairs(Data.DungeonFloors) do
		local dais = block(def.name, Vector3.zero, Vector3.new(2, 2 + index * 0.4, 2), if index == 1 then teal else violet, Enum.Material.Slate)
		dais.Position = part.Position + Vector3.new((index-4)*4, 0, -8)
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

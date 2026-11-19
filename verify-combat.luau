-- Headless checks for combat.server.lua: creature blueprints, spawn bookkeeping,
-- attack validation, cooldown math, kill credit, AI decisions and the slayer
-- boss lifecycle. The script exposes its pure core through __CombatTestHarness
-- and returns before touching any Roblox service, so the doubles stay tiny:
-- a clock, an rng, a recording bridge and a table of player positions.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)

local Combat
load("combat.server.lua", {
	Vector3 = Vector3, CFrame = CFrame, Color3 = Color3,
	__CombatTestHarness = function(exports) Combat = exports end,
})
assert(Combat, "harness hook must receive the combat exports")
local C = Combat.C

local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function near(actual, expected, case)
	assert(math.abs(actual - expected) < 1e-6, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end

------------------------------------------------------------------------------
-- Doubles
------------------------------------------------------------------------------
local function world()
	local w = {clock = 100, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, heals = {}, list = {},
		replies = {slayerBoss = {ok = true}}, playerCalls = 0}
	function w.rng()
		if #w.rolls > 0 then return table.remove(w.rolls, 1) end
		return 0.5
	end
	function w.player(name, pos, opts)
		opts = opts or {}
		local p = {Name = name, UserId = #w.list + 1}
		w.positions[p] = pos
		w.alive[p] = true
		w.stats[p] = {stats = opts.stats or {damage = 20, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0},
			combatLevel = opts.combatLevel or 5, ironman = opts.ironman == true}
		table.insert(w.list, p)
		return p
	end
	function w.count(op, player)
		local n = 0
		for _, c in ipairs(w.calls) do if c.op == op and (player == nil or c.player == player) then n += 1 end end
		return n
	end
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end,
		rng = w.rng,
		players = function() w.playerCalls += 1; return w.list end,
		alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.positions[p] end,
		heal = function(p, percent) table.insert(w.heals, {player = p, percent = percent}) end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if done then done(w.replies[op]) end
			return nil
		end,
	})
	return w
end
local function model(name) return {Name = name} end
local origin = Vector3.new(0, 0, 0)

------------------------------------------------------------------------------
-- Cooldown math and monster tuning
------------------------------------------------------------------------------
do
	local L = world().logic
	near(L.attackCooldown(0), 0.45, "base swing cooldown")
	near(L.attackCooldown(100), 0.225, "max attack speed halves the cooldown")
	near(L.attackCooldown(50), 0.3, "50 attack speed")
	near(L.attackCooldown(-20), 0.45, "negative attack speed clamps")
	near(L.attackCooldown(400), 0.225, "attack speed above cap clamps")
	near(L.attackCooldown(nil), 0.45, "missing attack speed")
	near(L.attackCooldown("fast"), 0.45, "garbage attack speed")
	near(L.monsterCooldown(12), 1.72, "boar-speed monster swing")
	near(L.monsterCooldown(100), 1.2, "monster swing floor")
	near(L.monsterCooldown(0), 2.0, "monster swing ceiling")
	ok(L.isPassive(Data.Monsters.BramblebackBoar), "level 2 boar is passive until hit")
	ok(not L.isPassive(Data.Monsters.Thornling), "thornlings are aggressive")
	ok(L.respawnDelay(Data.Monsters.StarbornSentinel) > L.respawnDelay(Data.Monsters.BramblebackBoar), "tougher monsters respawn slower")
end

------------------------------------------------------------------------------
-- Creature blueprints
------------------------------------------------------------------------------
do
	local shapes = {Block = true, Ball = true, Cylinder = true, Wedge = true}
	local signatures, kinds = {}, {}
	local monsterCount = 0
	for id, def in pairs(Data.Monsters) do
		monsterCount += 1
		local kind = Combat.BODY_KIND[id]
		ok(kind ~= nil, id .. " has a body kind")
		ok(not kinds[kind], id .. " has its own silhouette")
		kinds[kind] = true
		local plan = Combat.blueprint(kind, def.color, false)
		ok(#plan.parts + 1 <= 25, id .. " stays within 25 parts including the root")
		local names, eyes, tinted = {}, 0, false
		local base = Color3.fromRGB(tonumber(def.color:sub(1, 2), 16), tonumber(def.color:sub(3, 4), 16), tonumber(def.color:sub(5, 6), 16))
		for _, part in ipairs(plan.parts) do
			assert(shapes[part.shape], id .. " part shape " .. tostring(part.shape))
			assert(part.size.X > 0 and part.size.Y > 0 and part.size.Z > 0, id .. " positive part size")
			assert(Enum.Material[part.material] ~= nil, id .. " material " .. part.material)
			assert(not names[part.name], id .. " duplicate part name " .. part.name)
			assert(part.shape ~= "Ball" or (part.size.X == part.size.Y and part.size.Y == part.size.Z), id .. " balls are uniform")
			names[part.name] = true
			if part.material == "Neon" then eyes += 1 end
			if math.abs(part.color.R - base.R) < 1e-3 and math.abs(part.color.G - base.G) < 1e-3 and math.abs(part.color.B - base.B) < 1e-3 then tinted = true end
		end
		ok(eyes >= 2, id .. " has glowing eyes or accents")
		ok(tinted, id .. " uses its Data colour")
		ok(plan.hip > 0 and plan.radius > 0 and plan.radius <= C.MAX_RADIUS_BONUS, id .. " sane hip/radius")
		local signature = #plan.parts .. ":" .. tostring(plan.hitbox)
		ok(not signatures[signature], id .. " silhouette differs from the others")
		signatures[signature] = true
	end
	eq(monsterCount, 13, "every monster in Data has a model")
	ok(Combat.blueprint("sprite", "A8DADC", false).flying and Combat.blueprint("harrier", "7B8CDE", false).flying, "flyers hover")
	ok(not Combat.blueprint("golem", "D4A84B", false).flying, "golems walk")
	for line, def in pairs(Data.Slayers) do
		local body = Combat.BOSS_BODY[line]
		ok(body ~= nil, line .. " boss has a body")
		local boss = Combat.blueprint(body.kind, def.color, true)
		local normal = Combat.blueprint(body.kind, def.color, false)
		ok(#boss.parts + 1 <= 25, line .. " boss stays within 25 parts")
		ok(boss.scale > 2 and boss.hitbox.Y > normal.hitbox.Y * 2, line .. " boss is much larger")
		local crowns, redEyes = 0, true
		for _, part in ipairs(boss.parts) do
			if part.name:match("^Crown") then crowns += 1 end
			if part.name:match("^Eye") and part.color.G > 0.5 then redEyes = false end
		end
		ok(crowns == 3 and redEyes, line .. " boss has a crown and red eyes")
	end
end

------------------------------------------------------------------------------
-- Spawn bookkeeping
------------------------------------------------------------------------------
do
	local w = world()
	local L = w.logic
	local bad, reason = L.addMarker("bad", "NotAMonster", 2, origin)
	ok(bad == nil and reason == "unknown monster", "unknown monster ids are ignored")
	ok(L.addMarker("nil", nil, 2, origin) == nil, "missing MonsterId is ignored")
	eq(L.addMarker("a", "Thornling", nil, origin).count, C.DEFAULT_COUNT, "Count defaults to 2")
	eq(L.addMarker("b", "Thornling", 0, origin).count, 1, "Count clamps up to 1")
	eq(L.addMarker("c", "Thornling", 9, origin).count, 3, "Count clamps down to 3")
	eq(L.addMarker("d", "Thornling", 2.7, origin).count, 2, "Count floors")
	eq(L.addMarker("a", "CinderMite", 3, origin), L.marker("a"), "re-adding a marker keeps the original")
	local due = L.dueSpawns()
	eq(#due, 2 + 1 + 3 + 2, "every slot is due at start")
	eq(#L.dueSpawns(), 0, "slots are consumed")
	local marker = L.marker("b")
	local m1 = model("m1")
	local r = L.register(marker, m1, Vector3.new(0, 2, 0), {radius = 1.5})
	eq(L.liveCount(), 1, "register counts live monsters")
	eq(L.resolve(m1), r, "model resolves to its record")
	eq(r.hp, Data.Monsters.Thornling.hp, "monster spawns at full health")
	eq(r.radius, 1.5, "radius carried")
	L.unregister(r)
	eq(L.liveCount(), 0, "death releases the slot")
	eq(L.resolve(m1), nil, "dead model no longer resolves")
	eq(#L.dueSpawns(), 0, "respawn waits for its delay")
	w.clock += L.respawnDelay(Data.Monsters.Thornling) + 0.01
	local again = L.dueSpawns()
	eq(#again, 1, "respawn becomes due")
	eq(again[1], marker, "respawn belongs to its marker")
	local r2 = L.register(marker, model("m2"), origin)
	local removed = L.removeMarker("b")
	eq(#removed, 1, "removing a marker returns its monsters")
	eq(removed[1], r2, "the right monster is returned")
	eq(L.liveCount(), 0, "removed marker frees its monsters")
	ok(L.marker("b") == nil, "marker forgotten")
	w.clock += 100
	eq(#L.dueSpawns(), 0, "removed marker never respawns")
	local cmarker = L.marker("c")
	L.spawnFailed(cmarker)
	eq(#L.dueSpawns(), 0, "failed build retries later")
	w.clock += 5
	eq(#L.dueSpawns(), 1, "failed build retried")
	-- Global cap
	local capWorld = world()
	for i = 1, 40 do capWorld.logic.addMarker("k" .. i, "BramblebackBoar", 3, origin) end
	local capped = capWorld.logic.dueSpawns()
	eq(#capped, C.MAX_MONSTERS, "spawns stop at the monster cap")
	local first
	for i, m in ipairs(capped) do
		local r = capWorld.logic.register(m, model("cap" .. i), origin)
		first = first or r
	end
	eq(capWorld.logic.liveCount(), C.MAX_MONSTERS, "cap reached")
	eq(#capWorld.logic.dueSpawns(), 0, "cap holds while monsters live")
	capWorld.logic.unregister(first)
	eq(#capWorld.logic.dueSpawns(), 1, "a freed slot lets one queued spawn through")
end

------------------------------------------------------------------------------
-- Attack validation, damage, cooldown, lifesteal
------------------------------------------------------------------------------
do
	local w = world()
	local L = w.logic
	local marker = L.addMarker("m", "ShaleCrawler", 1, origin)
	L.dueSpawns()
	local target = model("crawler")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	local hero = w.player("hero", Vector3.new(10, 3, 0))
	eq(select(2, L.attack(hero, 5, target)), "verb", "non-string verb rejected")
	eq(select(2, L.attack(hero, "heal", target)), "verb", "unknown verb rejected")
	eq(select(2, L.attack(hero, "attack", nil)), "target", "nil target rejected")
	eq(select(2, L.attack(hero, "attack", model("fake"))), "target", "unspawned model rejected")
	w.alive[hero] = false
	eq(select(2, L.attack(hero, "attack", target)), "dead", "dead players cannot swing")
	w.alive[hero] = true
	w.positions[hero] = nil
	eq(select(2, L.attack(hero, "attack", target)), "position", "players without a character are rejected")
	w.positions[hero] = Vector3.new(16.5, 1, 0)
	eq(select(2, L.attack(hero, "attack", target)), "range", "out of range rejected (radius counted)")
	w.positions[hero] = Vector3.new(15.5, 1, 0)
	local result = L.attack(hero, "attack", target)
	ok(result ~= nil, "in range attack lands (14 + radius)")
	local expectedRaw = P.meleeDamage(w.stats[hero].stats, function() return 0.5 end)
	local expected = P.damageTaken(expectedRaw, Data.Monsters.ShaleCrawler.defense)
	eq(result.damage, expected, "damage = meleeDamage reduced by monster defense")
	eq(result.crit, false, "no crit at 0 crit chance")
	eq(r.hp, Data.Monsters.ShaleCrawler.hp - expected, "monster loses health")
	eq(r.contributors[hero], expected, "contribution recorded")
	eq(w.count("stats", hero), 1, "stats fetched through the bridge")
	eq(select(2, L.attack(hero, "attack", target)), "cooldown", "second swing inside cooldown rejected")
	w.clock += 0.45 - C.COOLDOWN_GRACE + 0.001
	ok(L.attack(hero, "attack", target) ~= nil, "swing inside the latency grace accepted")
	eq(w.count("stats", hero), 1, "stats cached within a second")
	w.clock += 1.01
	L.attack(hero, "attack", target)
	eq(w.count("stats", hero), 2, "stats refreshed after a second")
	eq(r.target, hero, "attacker becomes the target")
	-- crit and attack speed
	w.stats[hero].stats = {damage = 20, strength = 50, critChance = 100, critDamage = 100, attackSpeed = 100, lifesteal = 2}
	w.clock += 1.01
	local crit = L.attack(hero, "attack", target)
	ok(crit.crit, "100 crit chance always crits")
	eq(crit.damage, P.damageTaken(P.meleeDamage(w.stats[hero].stats, function() return 0.5 end), Data.Monsters.ShaleCrawler.defense), "crit damage uses Progression")
	ok(crit.damage > expected, "crits hit harder")
	eq(#w.heals, 1, "lifesteal heals")
	eq(w.heals[1].percent, 2, "lifesteal heals its percentage of max health")
	w.clock += 0.23
	ok(L.attack(hero, "attack", target) ~= nil, "100 attack speed swings every 0.225s")
	-- stats unavailable
	local ghost = w.player("ghost", Vector3.new(5, 1, 0))
	w.stats[ghost] = nil
	eq(select(2, L.attack(ghost, "attack", target)), "stats", "players without a profile cannot attack")
	-- passive monsters get provoked
	local boarMarker = L.addMarker("boar", "BramblebackBoar", 1, origin)
	L.dueSpawns()
	local boarModel = model("boar")
	local boar = L.register(boarMarker, boarModel, origin)
	eq(boar.target, nil, "boar starts without a target")
	w.clock += 1
	w.positions[hero] = Vector3.new(4, 1, 0)
	ok(L.attack(hero, "attack", boarModel) ~= nil, "boar hit lands")
	eq(boar.target, hero, "striking a passive boar provokes it")
end

------------------------------------------------------------------------------
-- Kill credit (incl. Ironman)
------------------------------------------------------------------------------
do
	local w = world()
	local L = w.logic
	local marker = L.addMarker("m", "BramblebackBoar", 3, origin)
	L.dueSpawns()
	local a = w.player("a", Vector3.new(5, 0, 0))
	local b = w.player("b", Vector3.new(-5, 0, 0))
	local far = w.player("far", Vector3.new(4, 0, 0))
	local iron = w.player("iron", Vector3.new(0, 0, 5), {ironman = true})
	local strong = {damage = 5000, strength = 0, critChance = 0, critDamage = 0, attackSpeed = 0}
	local m = model("boar1")
	local r = L.register(marker, m, origin)
	L.attack(a, "attack", m)
	L.attack(b, "attack", m)
	L.attack(far, "attack", m)
	L.attack(iron, "attack", m)
	w.positions[far] = Vector3.new(80, 0, 0)
	w.stats[a].stats = strong
	w.clock += 1.1
	local result = L.attack(a, "attack", m)
	ok(result.killed, "lethal blow kills")
	eq(r.hp, 0, "health floors at zero")
	local credited = {}
	for _, p in ipairs(result.credited) do credited[p] = true end
	ok(credited[a] and credited[b], "every nearby contributor is credited")
	ok(not credited[far], "contributors beyond 60 studs are not credited")
	ok(not credited[iron], "Ironman sharing a kill is not credited")
	eq(w.count("kill"), 2, "one kill call per credited player")
	for _, c in ipairs(w.calls) do if c.op == "kill" then eq(c.payload.monster, "BramblebackBoar", "kill payload names the monster") end end
	eq(L.resolve(m), nil, "killed monster unregistered")
	eq(select(2, L.attack(b, "attack", m)), "target", "corpse cannot be hit")
	eq(#L.dueSpawns(), 0, "kill queues a delayed respawn")

	local soloModel = model("boar2")
	local solo = L.register(marker, soloModel, origin)
	w.stats[iron].stats = strong
	w.clock += 2
	local soloResult = L.attack(iron, "attack", soloModel)
	ok(soloResult.killed and #soloResult.credited == 1 and soloResult.credited[1] == iron, "solo Ironman kill is credited")
	ok(solo.alive == false, "record marked dead")

	local deadModel = model("boar3")
	local r3 = L.register(marker, deadModel, origin)
	w.clock += 2
	L.attack(b, "attack", deadModel)
	w.alive[b] = false
	r3.contributors[a] = 0
	local list = L.creditEligible(r3)
	eq(#list, 0, "dead contributors and zero-damage entries earn nothing")
end

------------------------------------------------------------------------------
-- AI decisions
------------------------------------------------------------------------------
do
	local w = world()
	local L = w.logic
	local marker = L.addMarker("t", "Thornling", 1, origin)
	L.dueSpawns()
	local r = L.register(marker, model("thorn"), Vector3.new(0, 2, 0), {radius = 1.5})
	eq(L.think(r).kind, "sleep", "no players nearby: monster sleeps")
	local hero = w.player("hero", Vector3.new(40, 3, 0))
	local idle = L.think(r)
	ok(idle.kind == "wander" or idle.kind == "idle", "player outside aggro range: monster wanders")
	if r.wanderGoal then ok(L.flatDist(r.wanderGoal, r.home) <= C.WANDER_RADIUS + 1e-6, "wander stays near home") else ok(true, "idle") end
	w.positions[hero] = Vector3.new(20, 3, 0)
	local chase = L.think(r)
	eq(chase.kind, "chase", "player inside 25 studs is chased")
	eq(r.target, hero, "aggro target set")
	ok(L.step(r, chase.goal, chase.speed, 0.5, chase.stop), "monster steps toward target")
	near(r.position.X, Data.Monsters.Thornling.speed * 0.5, "step moves speed * dt")
	near(r.yaw, math.atan2(-1, 0), "monster faces its movement")
	w.positions[hero] = Vector3.new(r.position.X + 5, 3, 0)
	local strike = L.think(r)
	eq(strike.kind, "strike", "monster strikes in reach")
	eq(w.count("damage", hero), 1, "strike goes through the bridge")
	eq(w.calls[#w.calls].payload.amount, Data.Monsters.Thornling.damage, "strike uses monster damage")
	eq(L.think(r).kind, "hold", "monster waits for its swing cooldown")
	w.clock += r.attackCooldown
	eq(L.think(r).kind, "strike", "monster swings again after its cooldown")
	w.alive[hero] = false
	L.think(r)
	eq(r.target, nil, "dead players are dropped")
	w.alive[hero] = true
	-- Leash
	r.target = hero
	r.hp = 10
	r.contributors[hero] = 5
	r.position = Vector3.new(C.LEASH_RANGE + 5, 2, 0)
	w.positions[hero] = Vector3.new(C.LEASH_RANGE + 8, 3, 0)
	eq(L.think(r).kind, "leash", "beyond 60 studs from home the monster leashes")
	eq(r.target, nil, "leashing drops the target")
	local leash = L.think(r)
	eq(leash.kind, "leash", "still returning")
	for _ = 1, 100 do
		if not L.step(r, leash.goal, leash.speed, 0.5, leash.stop) then break end
	end
	local home = L.think(r)
	ok(home.healed, "monster heals on reaching home")
	eq(r.hp, r.maxHp, "full health after leash")
	eq(next(r.contributors), nil, "contributions reset after leash")
	-- Step stop distance
	local s = {position = Vector3.new(0, 0, 0), yaw = 0}
	ok(not L.step(s, Vector3.new(3, 0, 0), 10, 1, 4), "no step inside the stop distance")
	ok(L.step(s, Vector3.new(10, 0, 0), 10, 1, 4), "steps until the stop distance")
	near(s.position.X, 6, "stops short of the goal")
	-- Passive and tolerant
	local boarMarker = L.addMarker("boar", "BramblebackBoar", 1, Vector3.new(200, 0, 0))
	L.dueSpawns()
	local boar = L.register(boarMarker, model("boar"), Vector3.new(200, 1, 0))
	w.positions[hero] = Vector3.new(205, 3, 0)
	L.think(boar)
	eq(boar.target, nil, "passive boar ignores nearby players")
	local stalkerMarker = L.addMarker("st", "BarkStalker", 1, Vector3.new(-200, 0, 0))
	L.dueSpawns()
	local stalker = L.register(stalkerMarker, model("stalker"), Vector3.new(-200, 1, 0))
	local veteran = w.player("veteran", Vector3.new(-190, 3, 0), {combatLevel = 60})
	w.positions[hero] = Vector3.new(500, 0, 0)
	L.statsFor(veteran)
	L.think(stalker)
	eq(stalker.target, nil, "monsters tolerate players over twice their level")
	local rookie = w.player("rookie", Vector3.new(-195, 3, 0), {combatLevel = 10})
	L.think(stalker)
	eq(stalker.target, rookie, "lower-level players are attacked")
end

------------------------------------------------------------------------------
-- Slayer boss lifecycle
------------------------------------------------------------------------------
do
	local w = world()
	local L = w.logic
	local line, tier = L.parseBossReady("Bramble:1")
	ok(line == "Bramble" and tier == 1, "parses Line:tier")
	eq(select(2, L.parseBossReady("Gloom:4")), 4, "parses the top tier")
	eq(L.parseBossReady("Bramble:5"), nil, "unknown tier rejected")
	eq(L.parseBossReady("Nope:1"), nil, "unknown line rejected")
	eq(L.parseBossReady(""), nil, "empty rejected")
	eq(L.parseBossReady(12), nil, "non-string rejected")
	eq(L.parseBossReady("Bramble:1x"), nil, "trailing junk rejected")
	local spec = L.bossSpec("Tempest", 3)
	eq(spec.hp, Data.Slayers.Tempest.tiers[3].hp, "boss hp from Data")
	eq(spec.damage, Data.Slayers.Tempest.tiers[3].damage, "boss damage from Data")
	eq(spec.name, Data.Slayers.Tempest.name .. " III", "boss name carries the tier")
	eq(spec.defense, 2 * C.BOSS_DEFENSE_PER_TIER, "boss defense scales by tier")
	eq(spec.kind, "wraith", "spectral line uses the wraith body")

	local owner = w.player("owner", Vector3.new(0, 3, 0))
	local other = w.player("other", Vector3.new(4, 3, 0))
	w.positions[owner] = nil
	local action, pending = L.bossAttribute(owner, "Bramble:1")
	eq(action, "spawn", "ready attribute queues a boss")
	eq(#L.pendingBosses(), 0, "boss waits for the summoner's character")
	w.positions[owner] = Vector3.new(0, 3, 0)
	eq(#L.pendingBosses(), 1, "boss spawns once the summoner is present")
	ok(L.registerBoss(owner, L.bossSpec("Bramble", 1), model("x"), origin) == nil, "stale spec rejected")
	local bossModel = model("matriarch")
	local boss = L.registerBoss(owner, pending, bossModel, Vector3.new(0, 4, -10), {radius = 5})
	ok(boss and boss.boss, "boss registered")
	eq(L.bossOf(owner), boss, "boss bound to summoner")
	eq(#L.pendingBosses(), 0, "pending cleared")
	eq(L.liveCount(), 0, "bosses do not count toward the marker cap")
	eq(select(2, L.bossAttribute(owner, "Bramble:1")), "active", "no second boss while one lives")
	eq(select(2, L.attack(other, "attack", bossModel)), "owner", "only the summoner can damage the boss")
	eq(L.think(boss).kind, "strike", "boss hunts its summoner")
	eq(w.calls[#w.calls].payload.amount, Data.Slayers.Bramble.tiers[1].damage, "boss hits for tier damage")
	w.stats[owner].stats = {damage = 100000, strength = 0, critChance = 0, critDamage = 0, attackSpeed = 0}
	local win = L.attack(owner, "attack", bossModel)
	ok(win.killed, "boss can be slain")
	eq(w.count("slayerBoss", owner), 1, "boss kill reports to the bridge")
	eq(w.calls[#w.calls].payload.result, "win", "boss kill is a win")
	eq(w.count("kill"), 0, "boss kills are not regular kills")
	eq(L.bossOf(owner), nil, "boss cleared after the win")

	-- Timeout
	L.bossAttribute(owner, "Gloom:2")
	local timed = L.registerBoss(owner, L.pendingBosses()[1].spec, model("brood"), origin)
	w.clock += C.BOSS_DURATION - 1
	eq(#L.bossTick(), 0, "boss lives before 4 minutes")
	w.clock += 1
	local failed = L.bossTick()
	eq(#failed, 1, "boss expires at 4 minutes")
	eq(failed[1].reason, "timeout", "timeout reason")
	eq(failed[1].record, timed, "expired record returned for cleanup")
	eq(w.calls[#w.calls].payload.result, "fail", "timeout fails the quest")
	-- Death
	L.bossAttribute(owner, "Bramble:2")
	L.registerBoss(owner, L.pendingBosses()[1].spec, model("again"), origin)
	w.alive[owner] = false
	local died = L.bossTick()
	eq(died[1].reason, "died", "summoner death fails the boss")
	eq(w.count("slayerBoss", owner), 3, "each boss resolves exactly once")
	w.alive[owner] = true
	-- Abandon
	L.bossAttribute(owner, "Bramble:1")
	local abandoned = L.registerBoss(owner, L.pendingBosses()[1].spec, model("abandon"), origin)
	local cancel, record = L.bossAttribute(owner, "")
	ok(cancel == "cancel" and record == abandoned, "clearing the attribute despawns the boss")
	eq(w.count("slayerBoss", owner), 3, "abandoning does not call the bridge")
	-- Leaving
	L.bossAttribute(owner, "Bramble:1")
	local leaving = L.registerBoss(owner, L.pendingBosses()[1].spec, model("leave"), origin)
	local marker = L.addMarker("m", "Thornling", 1, origin)
	L.dueSpawns()
	local mob = L.register(marker, model("mob"), origin)
	mob.contributors[owner], mob.target = 50, owner
	w.clock += 2
	L.attack(owner, "attack", model("none"))
	local removed = L.playerRemoving(owner)
	eq(removed[1], leaving, "leaving despawns the boss")
	eq(w.count("slayerBoss", owner), 3, "leaving keeps the quest's boss ready")
	ok(not L.hasPlayerState(owner), "per-player state cleared on leave")
	eq(mob.contributors[owner], nil, "contributions cleared on leave")
	eq(mob.target, nil, "aggro cleared on leave")
	eq(#L.bossTick(), 0, "no stale boss ticks after leave")
end

------------------------------------------------------------------------------
-- Review regressions: M1 cooldown drift, M2 shared snapshot, L2 boss re-arm.
------------------------------------------------------------------------------
do
	-- M1: swinging at the edge of the grace window never beats the base rate.
	local w = world()
	local L = w.logic
	local marker = L.addMarker("dps", "StarbornSentinel", 1, origin)
	L.dueSpawns()
	local target = model("dummy")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	r.hp, r.maxHp = 1e12, 1e12
	local hero = w.player("hero", Vector3.new(5, 1, 0))
	local landed, duration = 0, 30
	local start = w.clock
	while w.clock < start + duration do
		if L.attack(hero, "attack", target) then landed += 1 end
		w.clock += C.BASE_COOLDOWN - C.COOLDOWN_GRACE + 0.001
	end
	ok(landed <= math.floor(duration / C.BASE_COOLDOWN) + 2, "sustained swings stay at the base cooldown (" .. landed .. ")")
	local onTime = 0
	w.clock += 1
	for i = 1, 20 do
		if L.attack(hero, "attack", target) then onTime += 1 end
		w.clock += C.BASE_COOLDOWN + (if i % 2 == 0 then 0.05 else -0.05) -- network jitter
	end
	eq(onTime, 20, "jittered on-time swings (early within the grace) all land")

	-- M2: one player snapshot per tick; sleep beyond ACTIVE_RANGE.
	local w2 = world()
	local L2 = w2.logic
	local m2 = L2.addMarker("pack", "Thornling", 3, origin)
	L2.dueSpawns()
	local pack = {}
	for i = 1, 3 do pack[i] = L2.register(m2, model("t" .. i), Vector3.new(i, 2, 0)) end
	local far = w2.player("far", Vector3.new(C.ACTIVE_RANGE + 10, 3, 0))
	w2.player("farther", Vector3.new(0, 3, C.ACTIVE_RANGE + 30))
	w2.playerCalls = 0
	L2.beginTick()
	for _, mob in ipairs(pack) do eq(L2.think(mob).kind, "sleep", "no player within " .. C.ACTIVE_RANGE .. " studs: sleep") end
	near(L2.nearestPlayerDistance(pack[1]), (Vector3.new(C.ACTIVE_RANGE + 10, 3, 0) - pack[1].position).Magnitude, "nearest player distance from the snapshot")
	L2.endTick()
	eq(w2.playerCalls, 1, "all monsters share one player list per tick")
	w2.positions[far] = Vector3.new(30, 3, 0)
	L2.beginTick()
	w2.positions[far] = Vector3.new(500, 3, 0)
	ok(L2.think(pack[1]).kind ~= "sleep", "think uses the tick snapshot")
	L2.endTick()
	eq(L2.think(pack[1]).kind, "sleep", "outside a tick live positions are used")

	-- L2: an unapplied slayerBoss report re-arms the boss instead of dropping it.
	local w3 = world()
	local L3 = w3.logic
	local owner = w3.player("owner", Vector3.new(0, 3, 0))
	w3.replies.slayerBoss = {ok = false, reason = "sync"}
	local _, spec = L3.bossAttribute(owner, "Bramble:1")
	local boss = L3.registerBoss(owner, spec, model("b"), Vector3.new(0, 3, -8))
	w3.stats[owner].stats = {damage = 1e9, strength = 0, critChance = 0, critDamage = 0, attackSpeed = 0}
	ok(L3.attack(owner, "attack", boss.model).killed, "boss slain")
	eq(#L3.dueRearms(), 0, "re-arm waits a moment")
	ok(L3.hasPlayerState(owner), "re-arm is tracked per player")
	w3.clock += C.BOSS_REARM_DELAY
	local due = L3.dueRearms()
	eq(due[1], owner, "unapplied win re-arms the boss")
	eq(#L3.dueRearms(), 0, "re-arm fires once")
	eq((L3.bossAttribute(owner, "Bramble:1")), "spawn", "re-read attribute queues the boss again")
	w3.replies.slayerBoss = {ok = true}
	local again = L3.registerBoss(owner, L3.pendingBosses()[1].spec, model("b2"), Vector3.new(0, 3, -8))
	L3.attack(owner, "attack", again.model)
	w3.clock += C.BOSS_REARM_DELAY
	eq(#L3.dueRearms(), 0, "applied win does not re-arm")
	w3.replies.slayerBoss = nil
	L3.bossAttribute(owner, "Bramble:1")
	L3.registerBoss(owner, L3.pendingBosses()[1].spec, model("b3"), Vector3.new(0, 3, -8))
	w3.clock += C.BOSS_DURATION
	L3.bossTick()
	L3.playerRemoving(owner)
	w3.clock += C.BOSS_REARM_DELAY
	eq(#L3.dueRearms(), 0, "leaving clears a pending re-arm")
	ok(not L3.hasPlayerState(owner), "no per-player state after leave")
end

------------------------------------------------------------------------------
-- Static checks on the runtime and client
------------------------------------------------------------------------------
do
	local server = fs.readFile("combat.server.lua")
	local client = fs.readFile("combat.client.lua")
	local _, loops = server:gsub("Heartbeat:Connect", "")
	eq(loops, 1, "a single Heartbeat loop drives all AI")
	ok(server:find("PlayerRemoving:Connect", 1, true) ~= nil, "server cleans up on PlayerRemoving")
	ok(server:find('remote("IsleCombat")', 1, true) and server:find('remote("IsleCombatFx")', 1, true), "both remotes created")
	ok(server:find('WaitForChild("MonsterSpawns", math.huge)', 1, true) ~= nil, "spawn folder awaited")
	ok(server:find("ChildAdded", 1, true) ~= nil, "late markers handled")
	ok(server:find('"IsleBridge"', 1, true) ~= nil, "bridge looked up in ServerStorage")
	local order = tonumber(client:match("DisplayOrder = (%d+)"))
	ok(order and order < 8, "combat HUD sits below the atlas")
	ok(client:find("ButtonR2", 1, true) and client:find("TouchTapInWorld", 1, true) and client:find("AttackButton", 1, true), "mouse, touch and gamepad inputs")
	ok(client:find("✧", 1, true) ~= nil, "crit numbers marked")
	ok(#luau.compile(server) > 0 and #luau.compile(client) > 0, "both scripts compile")
end

------------------------------------------------------------------------------
-- Runtime smoke test: the full script under small generic doubles.
------------------------------------------------------------------------------
do
	local function signal()
		local listeners = {}
		local s = {}
		function s:Connect(f)
			local entry = {f = f, live = true}
			table.insert(listeners, entry)
			return {Disconnect = function() entry.live = false end}
		end
		function s:Once(f)
			local c
			c = s:Connect(function(...) c.Disconnect(); f(...) end)
			return c
		end
		function s:Fire(...) for _, e in ipairs(table.clone(listeners)) do if e.live then e.f(...) end end end
		function s:Live() local n = 0 for _, e in ipairs(listeners) do if e.live then n += 1 end end return n end
		return s
	end
	local defaults = {CFrame = CFrame.new(), Position = Vector3.zero, Size = Vector3.one}
	local partClasses = {Part = true, WedgePart = true}
	local Object = {}
	Object.__index = function(self, key)
		local method = Object[key]
		if method ~= nil then return method end
		return defaults[key]
	end
	Object.__newindex = function(self, key, value)
		if key == "Parent" and type(value) == "table" and rawget(value, "_children") then value._children[self.Name] = self end
		rawset(self, key, value)
	end
	local function object(class, props)
		local o = setmetatable({ClassName = class, Name = class, _attrs = {}, _attrSignals = {}, _children = {}}, Object)
		for k, v in pairs(props or {}) do o[k] = v end
		return o
	end
	function Object:SetAttribute(k, v)
		self._attrs[k] = v
		if self._attrSignals[k] then self._attrSignals[k]:Fire() end
	end
	function Object:GetAttribute(k) return self._attrs[k] end
	function Object:GetAttributeChangedSignal(k)
		self._attrSignals[k] = self._attrSignals[k] or signal()
		return self._attrSignals[k]
	end
	function Object:IsA(class)
		return self.ClassName == class or (class == "BasePart" and partClasses[self.ClassName] == true)
	end
	function Object:Destroy() self.destroyed = true; self.Parent = nil end
	function Object:Clone() local c = object(self.ClassName); for k, v in pairs(self) do if k:sub(1, 1) ~= "_" then c[k] = v end end; return c end
	function Object:FindFirstChild(name) return self._children[name] end
	function Object:FindFirstChildOfClass(class) for _, c in pairs(self._children) do if c.ClassName == class then return c end end return nil end
	function Object:WaitForChild(name) return self._children[name] end
	function Object:GetChildren() local list = {} for _, c in pairs(self._children) do table.insert(list, c) end return list end
	local function child(parent, o) parent._children[o.Name] = o; o.Parent = parent; return o end

	local now, serverTime = 1000, 5000
	local created, tags, fired, bridgeCalls, warnings = {}, {}, {}, {}, {}
	local heartbeat = signal()
	local players = {PlayerAdded = signal(), PlayerRemoving = signal(), list = {}}
	function players:GetPlayers() return self.list end
	local replicated = object("ReplicatedStorage")
	child(replicated, object("ModuleScript", {Name = "AetherData"}))
	child(replicated, object("ModuleScript", {Name = "AetherProgression"}))
	local serverStorage = object("ServerStorage")
	local strong = false
	local bossReply = {ok = true}
	child(serverStorage, object("BindableFunction", {Name = "IsleBridge", Invoke = function(_, op, player, payload)
		table.insert(bridgeCalls, {op = op, player = player, payload = payload})
		if op == "stats" then
			return {stats = {damage = if strong then 1000000 else 10, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0}, combatLevel = 3, ironman = false}
		elseif op == "damage" then
			return 7
		elseif op == "slayerBoss" then
			return bossReply
		end
		return {}
	end}))
	local spawnsFolder = object("Folder", {Name = "MonsterSpawns", ChildAdded = signal(), ChildRemoved = signal()})
	local workspaceDouble = object("Workspace")
	child(workspaceDouble, spawnsFolder)
	function workspaceDouble:Raycast(origin) return {Position = Vector3.new(origin.X, 0, origin.Z)} end
	function workspaceDouble:GetServerTimeNow() return serverTime end
	local services = {
		Players = players, ReplicatedStorage = replicated, ServerStorage = serverStorage,
		RunService = {Heartbeat = heartbeat},
		CollectionService = {AddTag = function(_, o, tag) tags[o] = tag end},
		Workspace = workspaceDouble,
	}
	local env = {
		game = {GetService = function(_, name) return assert(services[name], name) end},
		require = function(module) return if module.Name == "AetherData" then Data else P end,
		typeof = function(v) if type(v) == "table" and v.ClassName then return "Instance" end return typeof(v) end,
		Instance = {new = function(class)
			local o = object(class)
			if class == "RemoteEvent" then
				o.OnServerEvent = signal()
				o.FireClient = function(_, player, kind, payload) table.insert(fired, {player = player, kind = kind, payload = payload}) end
			end
			table.insert(created, o)
			return o
		end},
		RaycastParams = {new = function() return {} end},
		Random = {new = function() return {NextNumber = function(_, a, b) a, b = a or 0, b or 1; return a + (b - a) * 0.5 end} end},
		Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		task = {
			spawn = function(f, ...) local co = coroutine.create(f); assert(coroutine.resume(co, ...)) end,
			defer = function(f, ...) f(...) end,
			delay = function(_, f, ...) f(...) end,
		},
		os = {clock = function() return now end, time = os.time},
		warn = function(...) table.insert(warnings, table.concat({...}, " ")) end,
	}
	local source = fs.readFile("combat.server.lua"):gsub("^\239\187\191", "")
	luau.load(source, {debugName = "combat.server.lua", environment = env, injectGlobals = true})()
	local remotes = {}
	for _, o in ipairs(created) do if o.ClassName == "RemoteEvent" then remotes[o.Name] = o end end
	ok(remotes.IsleCombat and remotes.IsleCombatFx and remotes.IsleCombat.Parent == replicated, "runtime creates both remotes")
	local monsters = workspaceDouble._children.IsleMonsters
	ok(monsters ~= nil, "runtime creates the monster folder")

	local function fireCount(kind) local n = 0 for _, f in ipairs(fired) do if f.kind == kind then n += 1 end end return n end
	local function bridgeCount(op) local n = 0 for _, c in ipairs(bridgeCalls) do if c.op == op then n += 1 end end return n end
	local function live()
		local list = {}
		for _, o in ipairs(created) do if o.ClassName == "Model" and o.Parent == monsters and not o.destroyed then table.insert(list, o) end end
		return list
	end
	local function tick(seconds)
		local steps = math.ceil(seconds / 0.1)
		for _ = 1, steps do now += 0.1; serverTime += 0.1; heartbeat:Fire(0.1) end
	end

	-- A player joins near a Thornling marker added after start.
	local humanoid = object("Humanoid", {Health = 100, MaxHealth = 100})
	local root = object("Part", {Name = "HumanoidRootPart", Position = Vector3.new(40, 3, 0), CFrame = CFrame.new(40, 3, 0)})
	local character = object("Model")
	child(character, humanoid); child(character, root)
	local hero = object("Player", {Name = "Hero", UserId = 7, Character = character, CharacterAdded = signal()})
	hero.Parent = players
	table.insert(players.list, hero)
	players.PlayerAdded:Fire(hero)
	local marker = object("Part", {Name = "ThornMarker", Position = Vector3.new(0, 1, 0)})
	marker:SetAttribute("MonsterId", "Thornling")
	marker:SetAttribute("Count", 2)
	child(spawnsFolder, marker)
	spawnsFolder.ChildAdded:Fire(marker)
	tick(0.6)
	local mobs = live()
	eq(#mobs, 2, "marker spawns its Count of monsters")
	local mob = mobs[1]
	eq(tags[mob], "IsleMonster", "monsters are tagged for the client")
	eq(mob:GetAttribute("MonsterId"), "Thornling", "model carries its monster id")
	eq(mob:GetAttribute("Health"), Data.Monsters.Thornling.hp, "model carries health")
	local partCount = 0
	for _, o in ipairs(created) do if (o.ClassName == "Part" or o.ClassName == "WedgePart") and o.Parent == mob then partCount += 1 end end
	ok(partCount > 5 and partCount <= 25, "built model stays within the part budget")
	ok(mob.PrimaryPart and mob.PrimaryPart.Anchored, "anchored root drives the welded body")
	local plateText
	for _, o in ipairs(created) do if o.ClassName == "TextLabel" and o.Text and o.Text:find("Thornling", 1, true) then plateText = o.Text end end
	eq(plateText, "[Lv 5] Thornling", "name plate format")
	-- Late-attribute marker
	local late = object("Part", {Name = "Late", Position = Vector3.new(300, 1, 0)})
	child(spawnsFolder, late)
	spawnsFolder.ChildAdded:Fire(late)
	tick(0.6)
	eq(#live(), 2, "markers without MonsterId wait")
	late:SetAttribute("MonsterId", "ShaleCrawler")
	tick(0.6)
	eq(#live(), 4, "markers spawn once MonsterId arrives (default Count 2)")

	-- M2: limb welds animate only near players; distant monsters write nothing.
	local thorn
	for _, m in ipairs(live()) do if m:GetAttribute("MonsterId") == "Thornling" then thorn = m end end
	local petalWeld
	for _, o in ipairs(created) do
		if o.ClassName == "Weld" and o.Part0 == thorn.PrimaryPart and o.Part1 and o.Part1.Name == "Petal1" then petalWeld = o end
	end
	ok(petalWeld ~= nil, "animated weld found")
	local c0 = petalWeld.C0
	tick(1)
	ok(petalWeld.C0 ~= c0, "limbs animate with a player within " .. C.ANIMATE_RANGE .. " studs")
	root.Position = Vector3.new(0, 3, 100)
	tick(0.2)
	c0 = petalWeld.C0
	tick(1)
	eq(petalWeld.C0, c0, "limbs freeze beyond the animation range")
	root.Position = Vector3.new(0, 3, 400)
	tick(0.2)
	local frozen = thorn.PrimaryPart.CFrame
	tick(2)
	eq(thorn.PrimaryPart.CFrame, frozen, "monsters with no player in range write no CFrame")
	root.Position = Vector3.new(40, 3, 0)
	tick(0.2)

	-- Aggro and monster strikes through the bridge.
	root.Position = Vector3.new(8, 3, 0)
	tick(4)
	ok(bridgeCount("damage") >= 1, "aggressive monsters strike through the bridge")
	ok(fireCount("hurt") >= 1, "the player sees the damage they took")

	-- Player attack.
	local target = mobs[1].PrimaryPart and mobs[1]
	local before = target:GetAttribute("Health")
	root.Position = target.PrimaryPart.CFrame.Position + Vector3.new(3, 0, 0)
	now += 1
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", target)
	ok(target:GetAttribute("Health") < before, "attack lowers model health")
	ok(fireCount("hit") == 1, "hit numbers broadcast")
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", "not an instance")
	remotes.IsleCombat.OnServerEvent:Fire(hero, {}, target)
	eq(fireCount("hit"), 1, "malformed attacks are ignored")
	strong = true
	now += 2
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", target)
	ok(target.destroyed, "killed model is destroyed")
	eq(bridgeCount("kill"), 1, "kill reported once")
	eq(fireCount("death"), 1, "death burst broadcast")

	-- Slayer boss summon, then timeout.
	hero:SetAttribute("SlayerBossReady", "Bramble:1")
	tick(0.6)
	local boss
	for _, m in ipairs(live()) do if m:GetAttribute("Boss") then boss = m end end
	ok(boss ~= nil, "SlayerBossReady spawns the boss")
	eq(boss:GetAttribute("OwnerUserId"), 7, "boss records its summoner")
	eq(boss:GetAttribute("MaxHealth"), Data.Slayers.Bramble.tiers[1].hp, "boss uses tier health")
	eq(fireCount("bossSpawn"), 1, "boss arrival announced")
	tick(C.BOSS_DURATION + 1)
	ok(boss.destroyed, "boss despawns after the time limit")
	eq(fireCount("bossFail"), 1, "summoner told the boss escaped")
	local fails = 0
	for _, c in ipairs(bridgeCalls) do if c.op == "slayerBoss" and c.payload.result == "fail" then fails += 1 end end
	eq(fails, 1, "timeout reported as a failure once")
	tick(C.BOSS_REARM_DELAY + 1)
	local respawned = 0
	for _, m in ipairs(live()) do if m:GetAttribute("Boss") then respawned += 1 end end
	eq(respawned, 0, "an applied report does not re-arm the boss")
	-- L2: the server could not apply the report (lease lapsed): the boss comes back.
	bossReply = {ok = false, reason = "sync"}
	hero:SetAttribute("SlayerBossReady", "Bramble:1")
	tick(0.6)
	local unreported
	for _, m in ipairs(live()) do if m:GetAttribute("Boss") then unreported = m end end
	ok(unreported ~= nil, "boss summoned again")
	tick(C.BOSS_DURATION + 1)
	ok(unreported.destroyed, "unreported boss despawned on timeout")
	tick(C.BOSS_REARM_DELAY + 1)
	local rearmed
	for _, m in ipairs(live()) do if m:GetAttribute("Boss") and not m.destroyed then rearmed = m end end
	ok(rearmed ~= nil and rearmed ~= unreported, "unapplied boss report re-arms the boss from SlayerBossReady")
	bossReply = {ok = true}

	-- Marker removal and leaving.
	spawnsFolder.ChildRemoved:Fire(late)
	local crawlers = 0
	for _, m in ipairs(live()) do if m:GetAttribute("MonsterId") == "ShaleCrawler" then crawlers += 1 end end
	eq(crawlers, 0, "removing a marker despawns its monsters")
	local attrSignal = hero:GetAttributeChangedSignal("SlayerBossReady")
	eq(attrSignal:Live(), 1, "one boss watcher per player")
	players.PlayerRemoving:Fire(hero)
	eq(attrSignal:Live(), 0, "watchers disconnected on leave")
	eq(hero.CharacterAdded:Live(), 0, "character watcher disconnected on leave")
	eq(heartbeat:Live(), 1, "still exactly one AI loop")
	eq(#warnings, 0, "no runtime warnings: " .. table.concat(warnings, "; "))
end

print("Combat QA: " .. checks .. " checks passed.")

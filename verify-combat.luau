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
	local w = {clock = 100, wall = 5000, blocked = {}, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, heals = {}, list = {},
		replies = {slayerBoss = {ok = true}}, playerCalls = 0, inv = {}, teleports = {}, walls = false, moving = {}}
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
		time = function() return w.wall end, -- wall clock of mastery capstone expiries
		rng = w.rng,
		players = function() w.playerCalls += 1; return w.list end,
		alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.positions[p] end,
		heal = function(p, percent) table.insert(w.heals, {player = p, percent = percent}) end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if op == "consume" then
				-- Synchronous, atomic payment from w.inv[player] (combat styles).
				local inv = w.inv[player] or {}
				for id, n in pairs(payload.items) do if (inv[id] or 0) < n then return {ok = false, reason = "missing"} end end
				local remaining, saved = {}, {}
				for id, n in pairs(payload.items) do
					-- w.glyphSave: Ink Thrift at 100% keeps every glyph (server Mastery.thrift).
					if w.glyphSave and Data.Items[id] and Data.Items[id].category == "glyph" then saved[id] = n else inv[id] -= n end
					remaining[id] = inv[id]
				end
				return {ok = true, remaining = remaining, saved = if next(saved) then saved else nil}
			end
			if op == "refund" then
				local inv = w.inv[player] or {}
				w.inv[player] = inv
				for id, n in pairs(payload.items) do inv[id] = (inv[id] or 0) + n end
				return {ok = true}
			end
			if done then done(w.replies[op]) end
			return nil
		end,
		lineOfSight = function(from, r) return not w.walls and not w.blocked[r] end,
		teleport = function(player) table.insert(w.teleports, player); return w.hub ~= false end,
		moving = function(player) return w.moving[player] == true end,
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
	eq(r.contributors[hero].damage, expected, "contribution recorded")
	eq(r.contributors[hero].xp.melee, expected, "melee damage XP accrued on the monster")
	eq(w.count("combatXp", hero), 0, "no damage XP is paid before the kill")
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
	r3.contributors[a] = {damage = 0, xp = {}}
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
	r.contributors[hero] = {damage = 5, xp = {melee = 5}}
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
	mob.contributors[owner], mob.target = {damage = 50, xp = {melee = 50}}, owner
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
	-- Combat styles client: every verb the server accepts, and every fx kind it sends.
	ok(client:find('"ranged"', 1, true) and client:find('FireServer("cast", model, id)', 1, true), "client sends ranged and cast verbs")
	for _, kind in ipairs({"projectile", "snare", "heal", "teleport", "denied"}) do
		ok(client:find('kind == "' .. kind .. '"', 1, true) ~= nil, "client renders fx " .. kind)
	end
	for reason in pairs({style = 1, ammo = 1, ammoTier = 1, sight = 1, range = 1, mana = 1, glyphs = 1, level = 1, spell = 1, immune = 1, combat = 1, teleport = 1}) do
		ok(client:find(reason .. " = ", 1, true) ~= nil or reason == "weapon", "denied reason " .. reason .. " has a toast")
	end
	ok(client:find("QuiverCount", 1, true) and client:find('"Mana"', 1, true), "quiver and mana attributes read")
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

	-- Sea creatures: attribute protocol end to end.
	local function seaModels()
		local list = {}
		for _, m in ipairs(live()) do if m:GetAttribute("SeaCreature") then table.insert(list, m) end end
		return list
	end
	local function seaReports(result)
		local n = 0
		for _, c in ipairs(bridgeCalls) do if c.op == "seaCreature" and c.payload.result == result then n += 1 end end
		return n
	end
	strong = false
	root.Position = Vector3.new(200, 3, 200)
	hero:SetAttribute("SeaCreatureAt", Vector3.new(204, 1, 200))
	hero:SetAttribute("SeaCreatureSpawn", "CoralbackBruiser:1")
	local sea = seaModels()
	eq(#sea, 1, "SeaCreatureSpawn spawns the creature")
	eq(sea[1]:GetAttribute("OwnerUserId"), 7, "sea creature records its angler")
	eq(sea[1]:GetAttribute("MonsterId"), "CoralbackBruiser", "sea creature carries its id")
	ok((sea[1].PrimaryPart.CFrame.Position - Vector3.new(204, 1, 200)).Magnitude <= C.SEA_OFFSET + 3, "it surfaces beside the fishing node")
	local seaParts = 0
	for _, o in ipairs(created) do if (o.ClassName == "Part" or o.ClassName == "WedgePart") and o.Parent == sea[1] then seaParts += 1 end end
	ok(seaParts > 10 and seaParts <= 25, "sea creature model stays within the part budget")
	hero:SetAttribute("SeaCreatureSpawn", "CoralbackBruiser:1")
	eq(#seaModels(), 1, "re-setting the same ticket spawns nothing")
	tick(C.SEA_DURATION + 0.5)
	ok(sea[1].destroyed, "sea creature submerges after its lifetime")
	eq(seaReports("despawn"), 1, "submerge reported once")
	hero:SetAttribute("SeaCreatureAt", Vector3.new(204, 1, 200))
	hero:SetAttribute("SeaCreatureSpawn", "ShellsnapCrab:2")
	local crab = seaModels()[1]
	strong = true
	now += 2
	root.Position = crab.PrimaryPart.CFrame.Position + Vector3.new(3, 0, 0)
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", crab)
	ok(crab.destroyed, "angler kills their sea creature")
	eq(seaReports("kill"), 1, "kill reported through the seaCreature op")
	local killReport
	for _, c in ipairs(bridgeCalls) do if c.op == "seaCreature" and c.payload.result == "kill" then killReport = c end end
	ok(killReport.player == hero and killReport.payload.seq == 2 and killReport.payload.monster == "ShellsnapCrab", "kill report names the owner's ticket")
	hero:SetAttribute("SeaCreatureSpawn", "ShellsnapCrab:3")
	eq(#seaModels(), 1, "a third ticket spawns")
	local seaSignal = hero:GetAttributeChangedSignal("SeaCreatureSpawn")
	eq(seaSignal:Live(), 1, "one sea watcher per player")

	-- Marker removal and leaving.
	spawnsFolder.ChildRemoved:Fire(late)
	local crawlers = 0
	for _, m in ipairs(live()) do if m:GetAttribute("MonsterId") == "ShaleCrawler" then crawlers += 1 end end
	eq(crawlers, 0, "removing a marker despawns its monsters")
	local attrSignal = hero:GetAttributeChangedSignal("SlayerBossReady")
	eq(attrSignal:Live(), 1, "one boss watcher per player")
	players.PlayerRemoving:Fire(hero)
	eq(attrSignal:Live(), 0, "watchers disconnected on leave")
	eq(seaSignal:Live(), 0, "sea watcher disconnected on leave")
	eq(#seaModels(), 0, "leaving despawns the angler's sea creatures")
	eq(hero.CharacterAdded:Live(), 0, "character watcher disconnected on leave")
	eq(heartbeat:Live(), 1, "still exactly one AI loop")
	eq(#warnings, 0, "no runtime warnings: " .. table.concat(warnings, "; "))
end

------------------------------------------------------------------------------
-- Sea creatures: aquatic body plans, spawn protocol, owner-only credit, despawn
------------------------------------------------------------------------------
do
	local seaChecks = checks
	-- Body plans
	local shapes = {Block = true, Ball = true, Cylinder = true, Wedge = true}
	local seen = {}
	for _, kind in pairs(Combat.BODY_KIND) do
		local plan = Combat.blueprint(kind, "AAAAAA", false)
		seen[#plan.parts .. ":" .. tostring(plan.hitbox)] = kind
	end
	local bodyCount = 0
	for _, kind in ipairs({"serpent", "crab", "ray", "jelly"}) do
		ok(Combat.SEA_BODIES[kind], kind .. " is an aquatic body plan")
		bodyCount += 1
		local plan = Combat.blueprint(kind, "D9774B", false)
		local base = Color3.fromRGB(0xD9, 0x77, 0x4B)
		ok(#plan.parts + 1 <= 25, kind .. " stays within 25 parts including the root")
		ok(#plan.parts >= 12, kind .. " has a detailed silhouette")
		local names, neon, tinted = {}, 0, false
		for _, part in ipairs(plan.parts) do
			assert(shapes[part.shape], kind .. " part shape " .. tostring(part.shape))
			assert(Enum.Material[part.material] ~= nil, kind .. " material " .. part.material)
			assert(not names[part.name], kind .. " duplicate part name " .. part.name)
			assert(part.shape ~= "Ball" or (part.size.X == part.size.Y and part.size.Y == part.size.Z), kind .. " balls are uniform")
			names[part.name] = true
			if part.material == "Neon" then neon += 1 end
			if math.abs(part.color.R - base.R) < 1e-3 and math.abs(part.color.G - base.G) < 1e-3 and math.abs(part.color.B - base.B) < 1e-3 then tinted = true end
		end
		ok(neon >= 2, kind .. " has glowing eyes")
		ok(tinted, kind .. " takes the creature colour")
		ok(plan.hip > 0 and plan.radius > 0 and plan.radius <= C.MAX_RADIUS_BONUS, kind .. " sane hip/radius")
		local signature = #plan.parts .. ":" .. tostring(plan.hitbox)
		ok(seen[signature] == nil, kind .. " silhouette differs from every other creature")
		seen[signature] = kind
	end
	eq(bodyCount, 4, "four aquatic body plans")
	ok(Combat.blueprint("ray", "8FB8D6", false).flying and Combat.blueprint("jelly", "B39DDB", false).flying, "rays and jellies hover")
	ok(not Combat.blueprint("crab", "D9774B", false).flying and not Combat.blueprint("serpent", "7FA35A", false).flying, "crabs and serpents crawl")
	for _, id in ipairs(Data.SeaCreatureOrder) do
		ok(Combat.SEA_BODIES[Data.SeaCreatures[id].body], id .. " uses an aquatic body plan")
	end

	-- Attribute parsing
	local w = world()
	local L = w.logic
	local owner = w.player("angler", Vector3.new(0, 3, 0))
	local helper = w.player("helper", Vector3.new(4, 3, 0))
	local node = Vector3.new(6, 0, 0)
	local id, seq, def = L.parseSeaSpawn("ShellsnapCrab:4")
	ok(id == "ShellsnapCrab" and seq == 4 and def == Data.SeaCreatures.ShellsnapCrab, "spawn attribute parses id and sequence")
	ok(L.parseSeaSpawn("Thornling:1") == nil, "marker monsters are not sea creatures")
	ok(L.parseSeaSpawn("ShellsnapCrab:0") == nil, "sequence starts at 1")
	ok(L.parseSeaSpawn("ShellsnapCrab") == nil and L.parseSeaSpawn("ShellsnapCrab:-1") == nil, "malformed sequence rejected")
	ok(L.parseSeaSpawn(42) == nil and L.parseSeaSpawn(nil) == nil, "non-string attribute rejected")
	ok(L.parseSeaSpawn(string.rep("A", 90) .. ":1") == nil, "overlong attribute rejected")
	ok(L.parseSeaSpawn("__index:1") == nil, "metatable keys are not creatures")
	ok(L.addMarker("sea", "ShellsnapCrab", 2, origin) == nil, "sea creatures never spawn from world markers")
	ok(Data.Monsters.ShellsnapCrab ~= nil, "sea creatures resolve through Data.Monsters")

	-- Spawn requests
	local action, spec = L.seaAttribute(owner, "ShellsnapCrab:1", node)
	eq(action, "spawn", "fresh ticket spawns")
	eq(spec.owner, owner, "spawn is owned by the angler")
	eq(spec.at, node, "spawn sits at the fishing node")
	eq(w.count("seaCreature"), 0, "accepted spawn reports nothing yet")
	eq(select(2, L.seaAttribute(owner, "ShellsnapCrab:1", node)), "stale", "a replayed sequence is ignored")
	eq(select(2, L.seaAttribute(owner, "", node)), "empty", "cleared attribute is ignored")
	eq(select(2, L.seaAttribute(owner, "Dragon:9", node)), "invalid", "unknown creature ignored")
	eq(w.count("seaCreature"), 0, "invalid requests never reach the bridge")
	local r1 = L.registerSea(owner, spec, model("sea1"), node + Vector3.new(6, 1, 0), {radius = 2})
	ok(r1 ~= nil and r1.sea and r1.owner == owner and r1.seq == 1, "sea creature registered for its owner")
	eq(r1.hp, Data.SeaCreatures.ShellsnapCrab.hp, "spawns at full health")
	eq(r1.target, owner, "it turns on the angler")
	eq(L.seaCount(owner), 1, "owner count tracked")
	eq(L.liveCount(), 0, "sea creatures do not use marker slots")
	eq(L.registerSea(owner, spec, model("dup"), node), nil, "a spec registers once per cap check")
	-- Two more tickets fill the per-owner cap.
	local _, s2 = L.seaAttribute(owner, "DriftbellJelly:2", node)
	local _, s3 = L.seaAttribute(owner, "ReedfinEel:3", node)
	ok(s2 ~= nil and s3 ~= nil, "second and third tickets accepted")
	L.registerSea(owner, s2, model("sea2"), node)
	L.registerSea(owner, s3, model("sea3"), node)
	eq(L.seaCount(owner), Data.SeaCreatureCap, "owner reaches the cap")
	local capped, capReason = L.seaAttribute(owner, "ShellsnapCrab:4", node)
	ok(capped == nil and capReason == "cap", "a fourth creature is refused")
	local last = w.calls[#w.calls]
	ok(last.op == "seaCreature" and last.payload.result == "despawn" and last.payload.seq == 4, "refused ticket is released on the server")
	eq(select(2, L.seaAttribute(helper, "ShellsnapCrab:1", Vector3.new(500, 0, 0))), "far", "nodes far from the angler are refused")
	w.alive[helper] = false
	eq(select(2, L.seaAttribute(helper, "ShellsnapCrab:2", node)), "dead", "dead anglers hook nothing")
	w.alive[helper] = true
	local fallbackAction, fallback = L.seaAttribute(helper, "ShellsnapCrab:3", nil)
	ok(fallbackAction == "spawn" and fallback.at == w.positions[helper], "missing node position falls back to the angler")

	-- AI: hunts its owner first even with a closer helper.
	r1.target = nil
	L.beginTick()
	local thought = L.think(r1)
	L.endTick()
	eq(r1.target, owner, "sea creature chases its owner")
	ok(thought.kind == "chase" or thought.kind == "strike" or thought.kind == "hold", "sea creature engages")

	-- Credit: helpers may fight, only the owner is credited.
	local before = w.count("kill")
	w.stats[helper].stats.damage = 1000000
	w.positions[helper] = r1.position + Vector3.new(3, 0, 0)
	local helped = L.attack(helper, "attack", r1.model)
	ok(helped ~= nil and helped.killed, "helpers can damage and kill sea creatures")
	eq(#helped.credited, 0, "a kill the owner never touched credits nobody")
	last = w.calls[#w.calls]
	ok(last.op == "seaCreature" and last.payload.result == "despawn" and last.payload.seq == 1, "uncredited kill frees the ticket")
	eq(w.count("kill"), before, "sea creatures never use the marker kill op")
	eq(L.seaCount(owner), 2, "dead creature frees its slot")

	local r2 = L.resolve(model("sea2")) or nil
	for _, r in ipairs(L.records()) do if r.seq == 2 and r.owner == owner then r2 = r end end
	w.positions[owner] = r2.position + Vector3.new(3, 0, 0)
	w.stats[owner].stats.damage = 1000000
	w.clock += 5
	local own = L.attack(owner, "attack", r2.model)
	ok(own.killed and #own.credited == 1 and own.credited[1] == owner, "owner kill credits the owner")
	last = w.calls[#w.calls]
	ok(last.op == "seaCreature" and last.player == owner and last.payload.result == "kill" and last.payload.seq == 2 and last.payload.monster == "DriftbellJelly", "owner kill reports the ticket")
	-- Unapplied kill (journal not live): resent every few seconds while the ticket lasts.
	eq(#L.dueSeaRetries(), 0, "kill resend waits a moment")
	w.clock += C.SEA_RETRY_DELAY
	local resend = L.dueSeaRetries()
	ok(#resend == 1 and resend[1].player == owner and resend[1].seq == 2 and resend[1].id == "DriftbellJelly", "unapplied kill report is resent")
	eq(#L.dueSeaRetries(), 0, "each resend fires once")
	w.replies.seaCreature = {ok = false, reason = "sync"}
	L.reportSea(owner, resend[1].id, resend[1].seq, "kill", resend[1].deadline)
	w.clock += C.SEA_RETRY_DELAY
	eq(#L.dueSeaRetries(), 1, "a sync reply keeps resending")
	w.replies.seaCreature = {ok = true}
	L.reportSea(owner, resend[1].id, resend[1].seq, "kill", resend[1].deadline)
	w.clock += C.SEA_RETRY_DELAY
	eq(#L.dueSeaRetries(), 0, "an applied report ends the resends")
	w.replies.seaCreature = {ok = false, reason = "ticket"}
	L.reportSea(owner, "DriftbellJelly", 2, "kill", w.clock + 60)
	w.clock += C.SEA_RETRY_DELAY
	eq(#L.dueSeaRetries(), 0, "a settled ticket is never resent")
	w.replies.seaCreature = nil
	L.reportSea(owner, "DriftbellJelly", 2, "kill", w.clock + 2)
	w.clock += C.SEA_RETRY_DELAY
	eq(#L.dueSeaRetries(), 0, "no resend past the ticket's expiry")
	L.reportSea(owner, "DriftbellJelly", 2, "despawn", w.clock + 60)
	w.clock += C.SEA_RETRY_DELAY
	eq(#L.dueSeaRetries(), 0, "despawns are never resent")

	-- Owner contributed but walked away: no credit.
	local r3
	for _, r in ipairs(L.records()) do if r.seq == 3 and r.owner == owner then r3 = r end end
	w.stats[owner].stats.damage = 20
	w.clock += 5
	L.attack(owner, "attack", r3.model)
	ok(L.contribution(r3, owner) > 0, "owner dealt damage")
	w.positions[owner] = r3.position + Vector3.new(C.CREDIT_RANGE + 5, 0, 0)
	L.kill(r3)
	last = w.calls[#w.calls]
	ok(last.payload.result == "despawn", "owner out of range forfeits the kill")
	eq(L.seaCount(owner), 0, "all slots free")

	-- Ironman owners need a solo kill.
	local iw = world()
	local iron = iw.player("iron", Vector3.new(0, 3, 0), {ironman = true, stats = {damage = 20, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0}})
	local friend = iw.player("friend", Vector3.new(2, 3, 0))
	local _, ispec = iw.logic.seaAttribute(iron, "ShellsnapCrab:1", origin)
	local ir = iw.logic.registerSea(iron, ispec, model("iron1"), Vector3.new(3, 1, 0))
	iw.logic.statsFor(iron)
	iw.logic.attack(iron, "attack", ir.model)
	iw.clock += 1
	iw.logic.attack(friend, "attack", ir.model)
	eq(#iw.logic.seaCredit(ir), 0, "Ironman owner with help is not credited")
	ir.contributors[friend] = nil
	eq(#iw.logic.seaCredit(ir), 1, "Ironman owner solo kill is credited")
	w.alive[owner] = true

	-- Despawn after the lifetime.
	local dw = world()
	local diver = dw.player("diver", Vector3.new(0, 3, 0))
	local _, dspec = dw.logic.seaAttribute(diver, "MistwingRay:7", origin)
	dw.logic.registerSea(diver, dspec, model("ray"), origin)
	eq(#dw.logic.seaTick(), 0, "fresh creature stays")
	dw.clock += C.SEA_DURATION - 1
	eq(#dw.logic.seaTick(), 0, "still there just before the limit")
	dw.clock += 1.01
	local gone = dw.logic.seaTick()
	eq(#gone, 1, "submerges after " .. C.SEA_DURATION .. " s")
	ok(not gone[1].alive and dw.logic.resolve(gone[1].model) == nil, "submerged creature is unregistered")
	local dlast = dw.calls[#dw.calls]
	ok(dlast.op == "seaCreature" and dlast.payload.result == "despawn" and dlast.payload.seq == 7, "despawn reported")
	eq(dw.logic.seaCount(diver), 0, "despawn frees the slot")
	eq(#dw.logic.seaTick(), 0, "despawn happens once")
	eq(Data.SeaCreatureLifetime, C.SEA_DURATION, "data and combat agree on the lifetime")

	-- Owner leaving despawns silently and forgets state.
	local _, lspec = dw.logic.seaAttribute(diver, "ShellsnapCrab:8", origin)
	dw.logic.registerSea(diver, lspec, model("crab"), origin)
	local calls = #dw.calls
	local removed = dw.logic.playerRemoving(diver)
	eq(#removed, 1, "leaving removes owned sea creatures")
	eq(#dw.calls, calls, "leaving reports nothing (server drops tickets)")
	eq(dw.logic.seaLive(), 0, "server-wide count released")
	ok(not dw.logic.hasPlayerState(diver), "no per-player sea state survives leaving")

	-- Server-wide cap.
	local gw = world()
	for i = 1, C.SEA_MAX + 2 do
		local pl = gw.player("p" .. i, Vector3.new(i, 3, 0))
		local act, sp = gw.logic.seaAttribute(pl, "ShellsnapCrab:1", Vector3.new(i, 0, 0))
		if act then gw.logic.registerSea(pl, sp, model("g" .. i), Vector3.new(i, 1, 0)) end
	end
	eq(gw.logic.seaLive(), C.SEA_MAX, "server-wide sea creature cap holds")
	eq(gw.count("seaCreature"), 2, "creatures over the global cap release their tickets")
	print("PASS: " .. (checks - seaChecks) .. " sea creature combat assertions.")
end

------------------------------------------------------------------------------
-- Damage XP is accrued on the monster and paid only on the kill (OSRS model).
------------------------------------------------------------------------------
do
	local before = checks
	local function paidXp(w, player, style)
		local total, n = 0, 0
		for _, c in ipairs(w.calls) do
			if c.op == "combatXp" and c.player == player and c.payload.damage and (style == nil or c.payload.style == style) then
				total += c.payload.damage; n += 1
			end
		end
		return total, n
	end
	local weak = {damage = 20, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0}
	local strong = {damage = 5000, strength = 0, critChance = 0, critDamage = 0, attackSpeed = 0}
	-- Credited contributors are paid exactly the damage they removed; others nothing.
	do
		local w = world()
		local L = w.logic
		local marker = L.addMarker("m", "ShaleCrawler", 2, origin)
		L.dueSpawns()
		local m = model("crawler")
		local r = L.register(marker, m, Vector3.new(0, 1, 0))
		local a = w.player("a", Vector3.new(5, 1, 0), {stats = weak})
		local b = w.player("b", Vector3.new(-5, 1, 0), {stats = weak})
		local far = w.player("far", Vector3.new(0, 1, 5), {stats = weak})
		L.attack(a, "attack", m); L.attack(b, "attack", m); L.attack(far, "attack", m)
		local dealtB, dealtFar = r.contributors[b].damage, r.contributors[far].damage
		eq(select(2, paidXp(w, a)), 0, "no XP while the monster lives")
		w.positions[far] = Vector3.new(90, 1, 0)
		w.stats[a].stats = strong
		w.clock += 1.1
		local hpBefore = r.hp
		local kill = L.attack(a, "attack", m)
		ok(kill.killed, "killing blow")
		local dealtA = r.contributors[a].damage
		eq(dealtA + dealtB + dealtFar, Data.Monsters.ShaleCrawler.hp, "contributions sum to the monster's hp (overkill capped)")
		ok(kill.damage > hpBefore and dealtA < Data.Monsters.ShaleCrawler.hp, "the overkill blow only counts the hp it removed")
		local paidA, callsA = paidXp(w, a, "melee")
		eq(paidA, dealtA, "killer paid the damage it removed")
		eq(callsA, 1, "one XP report per style per kill")
		eq((paidXp(w, b, "melee")), dealtB, "helper paid its own damage")
		eq((paidXp(w, far)), 0, "uncredited contributors get no XP")
		-- Total Combat XP of a solo melee kill is monster.xp (server converts damage).
		local combat = P.styleXp("melee", Data.Monsters.ShaleCrawler.hp, Data.Monsters.ShaleCrawler.xp, Data.Monsters.ShaleCrawler.hp)
		near(combat.Combat, Data.Monsters.ShaleCrawler.xp, "a whole melee kill is worth exactly monster.xp Combat XP")
	end
	-- Leashing: untargetable, and the heal discards the accrued XP.
	do
		local w = world()
		local L = w.logic
		local marker = L.addMarker("t", "Thornling", 1, origin)
		L.dueSpawns()
		local m = model("thorn")
		local r = L.register(marker, m, Vector3.new(0, 1, 0))
		local hero = w.player("hero", Vector3.new(5, 1, 0), {stats = weak})
		L.attack(hero, "attack", m)
		ok(L.contribution(r, hero) > 0, "damage accrued")
		r.position = Vector3.new(C.LEASH_RANGE + 2, 1, 0)
		w.positions[hero] = Vector3.new(C.LEASH_RANGE + 6, 1, 0)
		eq(L.think(r).kind, "leash", "monster leashes")
		w.clock += 1.1
		eq(select(2, L.attack(hero, "attack", m)), "leashing", "leashing monsters cannot be hit")
		w.stats[hero].loadout = {style = "magic", weapon = "MeadowWand", levels = {Magic = 30}, supplies = {GaleGlyph = 5, SparkGlyph = 5, BindGlyph = 2, StoneGlyph = 4}}
		w.inv[hero] = {GaleGlyph = 5, SparkGlyph = 5, BindGlyph = 2, StoneGlyph = 4}
		w.positions[hero] = Vector3.new(C.LEASH_RANGE + 20, 1, 0)
		eq(select(2, L.cast(hero, "cast", m, "GaleDart")), "leashing", "nor targeted by damage spells")
		eq(select(2, L.cast(hero, "cast", m, "Rootbind")), "leashing", "nor snared")
		eq(w.count("consume", hero), 0, "refused casts spend nothing")
		eq(w.count("combatXp", hero), 0, "and grant no cast XP")
		r.position = r.home
		ok(L.think(r).healed, "monster heals at home")
		eq(L.contribution(r, hero), 0, "accrued XP discarded with the heal")
		-- Fight again and kill: only the new damage pays.
		w.stats[hero].loadout = nil
		w.positions[hero] = Vector3.new(5, 1, 0)
		w.stats[hero].stats = strong
		w.clock += 1.1
		ok(L.attack(hero, "attack", m).killed, "kill after the leash")
		eq((paidXp(w, hero, "melee")), Data.Monsters.Thornling.hp, "only one monster's worth of XP is paid")
	end
	-- Snared beyond the leash: hits accrue, the leash after the snare discards them.
	do
		local w = world()
		local L = w.logic
		local marker = L.addMarker("t", "Thornling", 1, origin)
		L.dueSpawns()
		local m = model("thorn")
		local r = L.register(marker, m, Vector3.new(C.LEASH_RANGE + 10, 1, 0))
		local hero = w.player("hero", Vector3.new(C.LEASH_RANGE + 15, 1, 0), {stats = weak})
		r.snaredUntil = w.clock + 5
		ok(L.think(r).kind ~= "leash", "a snared monster stays put past its leash")
		for _ = 1, 3 do
			w.clock += 1.1
			L.attack(hero, "attack", m)
		end
		ok(L.contribution(r, hero) > 0 and r.hp > 0, "damage accrued on the snared monster")
		w.clock += 5
		eq(L.think(r).kind, "leash", "the snare ends and it leashes")
		r.position = r.home
		L.think(r)
		eq(r.hp, r.maxHp, "healed")
		eq(w.count("combatXp", hero), 0, "no XP from the snared hits")
	end
	-- Despawn without a kill pays nothing; bosses pay their owner on the win.
	do
		local w = world()
		local L = w.logic
		local marker = L.addMarker("t", "Thornling", 1, origin)
		L.dueSpawns()
		local m = model("thorn")
		local r = L.register(marker, m, Vector3.new(0, 1, 0))
		local hero = w.player("hero", Vector3.new(5, 1, 0), {stats = weak})
		L.attack(hero, "attack", m)
		L.removeMarker("t")
		eq(r.alive, false, "despawned")
		eq(w.count("combatXp", hero), 0, "despawns discard accrued XP")
		local owner = w.player("owner", Vector3.new(0, 1, 30), {stats = strong})
		local _, spec = L.bossAttribute(owner, "Bramble:1")
		local bm = model("boss")
		L.registerBoss(owner, spec, bm, Vector3.new(0, 1, 34))
		ok(L.attack(owner, "attack", bm).killed, "boss slain")
		local paid
		for _, c in ipairs(w.calls) do if c.op == "combatXp" and c.player == owner then paid = c.payload end end
		ok(paid ~= nil and paid.monster == "Boss:Bramble" and paid.tier == 1 and paid.damage == Data.Slayers.Bramble.tiers[1].hp, "boss win pays the owner its damage XP")
	end
	-- Mana tick cost is bounded: only a few stats reads per tick, none for idle full players.
	do
		local w = world()
		local L = w.logic
		local crowd = {}
		for i = 1, 12 do table.insert(crowd, w.player("p" .. i, Vector3.new(i * 3, 1, 0))) end
		local function reads() return w.count("stats") end
		L.manaTick()
		ok(reads() <= C.MANA_REFRESH_BUDGET, "first tick reads at most the budget")
		local seen = reads()
		for _ = 1, 3 do w.clock += 1; L.manaTick() end
		eq(reads(), 12, "every player is read once within a few ticks")
		w.clock += 1
		L.manaTick()
		eq(reads(), 12, "full-mana players are not re-read before MANA_REFRESH")
		ok(seen > 0, "budget spent on first sight")
		w.clock += C.MANA_REFRESH
		local start = reads()
		L.manaTick()
		ok(reads() - start <= C.MANA_REFRESH_BUDGET, "refreshes stay within the budget")
	end
	print("PASS: " .. (checks - before) .. " kill-paid XP and mana tick assertions.")
end

------------------------------------------------------------------------------
-- Combat styles: ranged shots, spells, mana, triangle, XP routing.
------------------------------------------------------------------------------
local stylesBefore = checks
local function styleStats(extra)
	local s = {damage = 20, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0, rangedStrength = 0, rangedAccuracy = 0, intelligence = 100, abilityDamage = 0}
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local function xpCalls(w, style)
	local list = {}
	for _, c in ipairs(w.calls) do if c.op == "combatXp" and (style == nil or c.payload.style == style) then table.insert(list, c.payload) end end
	return list
end
-- Ranged validation and damage.
do
	local w = world()
	local L = w.logic
	eq(L.maxRange, 40, "ranged reach capped at 40 studs")
	local marker = L.addMarker("boar", "BramblebackBoar", 1, origin)
	L.dueSpawns()
	local target = model("boar")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	eq(r.weakness, "magic", "records carry the monster weakness")
	eq(r.defenceStyle, "ranged", "records carry the resisted style")
	local archer = w.player("archer", Vector3.new(35, 1, 0), {stats = styleStats()})
	local lo = {style = "melee", weapon = "BrassSword", levels = {Combat = 1, Ranged = 1, Magic = 1}, supplies = {}, ammoCount = 0}
	w.stats[archer].loadout = lo
	eq(select(2, L.ranged(archer, "attack", target)), "verb", "ranged verb required")
	eq(select(2, L.ranged(archer, "ranged", model("fake"))), "target", "unspawned model rejected")
	eq(select(2, L.ranged(archer, "ranged", target)), "weapon", "a sword cannot shoot")
	lo.style, lo.weapon = "ranged", "MeadowShortbow"
	eq(select(2, L.ranged(archer, "ranged", target)), "range", "shortbows reach 30 studs (radius counted)")
	lo.weapon = "MeadowLongbow"
	eq(select(2, L.ranged(archer, "ranged", target)), "ammo", "an empty quiver cannot shoot")
	lo.ammo, lo.ammoCount = "CelestialArrow", 10
	eq(select(2, L.ranged(archer, "ranged", target)), "ammoTier", "meadow bows refuse celestial arrows")
	lo.ammo, lo.ammoCount = "CopperArrow", 3
	w.inv[archer] = {CopperArrow = 3}
	w.walls = true
	eq(select(2, L.ranged(archer, "ranged", target)), "sight", "no line of sight, no shot")
	eq(w.count("consume", archer), 0, "blocked shots spend no arrows")
	w.walls = false
	w.positions[archer] = Vector3.new(42.5, 1, 0)
	eq(select(2, L.ranged(archer, "ranged", target)), "range", "beyond 40 studs rejected")
	w.positions[archer] = Vector3.new(35, 1, 0)
	w.alive[archer] = false
	eq(select(2, L.ranged(archer, "ranged", target)), "dead", "dead archers cannot shoot")
	w.alive[archer] = true
	eq(select(2, L.attack(archer, "attack", target)), "range", "melee reach stays 14 studs")
	w.positions[archer] = Vector3.new(10, 1, 0)
	eq(select(2, L.attack(archer, "attack", target)), "style", "melee refused while a bow is wielded")
	w.positions[archer] = Vector3.new(35, 1, 0)
	-- A hit: roll 0 hits, 0.99 does not crit.
	w.rolls = {0, 0.99}
	local shot = L.ranged(archer, "ranged", target)
	ok(shot ~= nil, "longbow shot lands at 33 studs")
	local stats = w.stats[archer].stats
	local raw = P.rangedDamage(stats, Data.Items.MeadowLongbow, Data.Items.CopperArrow, 1, function() return 0.99 end)
	eq(shot.damage, P.damageTaken(math.floor(raw * 0.7), Data.Monsters.BramblebackBoar.defense), "ranged damage with the -30% resist")
	eq(shot.tag, "resist", "boars resist arrows")
	eq(shot.style, "ranged", "shot style")
	eq(w.inv[archer].CopperArrow, 2, "one arrow consumed per shot")
	eq(shot.ammoLeft, 2, "quiver count returned")
	eq(r.hp, Data.Monsters.BramblebackBoar.hp - shot.damage, "boar loses health")
	eq(r.target, archer, "the archer draws aggro")
	eq(#xpCalls(w, "ranged"), 0, "ranged damage XP waits for the kill")
	eq(r.contributors[archer].xp.ranged, shot.damage, "ranged damage accrued on the monster")
	ok(math.abs(shot.chance - P.hitChance(0, 1, Data.Monsters.BramblebackBoar.level, 0)) < 1e-9, "hit chance from Progression")
	eq(select(2, L.ranged(archer, "ranged", target)), "cooldown", "second shot inside the bow cooldown")
	w.clock += 1.05 - C.COOLDOWN_GRACE + 0.001
	w.rolls = {0.999}
	local miss = L.ranged(archer, "ranged", target)
	ok(miss and miss.miss and miss.damage == 0, "a failed accuracy roll misses")
	eq(w.inv[archer].CopperArrow, 1, "misses still spend the arrow")
	eq(r.contributors[archer].xp.ranged, shot.damage, "misses accrue no XP")
	w.clock += 1.2
	ok(L.ranged(archer, "ranged", target) ~= nil, "last arrow fired")
	eq(lo.ammoCount, 0, "cached quiver count follows the bridge")
	w.clock += 1.2
	eq(select(2, L.ranged(archer, "ranged", target)), "ammo", "empty quiver after the last arrow")
	lo.ammoCount = 5 -- stale cache: the bridge still refuses
	eq(select(2, L.ranged(archer, "ranged", target)), "ammo", "the bridge payment is authoritative")
	eq(lo.ammoCount, 0, "a refused payment empties the cached quiver")
	-- Attack speed shortens the bow cooldown; a killing shot reports the kill.
	w.inv[archer].CopperArrow, lo.ammoCount = 10, 10
	w.stats[archer].stats = styleStats({attackSpeed = 100, rangedStrength = 100000})
	w.clock += 2
	w.rolls = {0, 0.99}
	local kill = L.ranged(archer, "ranged", target)
	ok(kill.killed, "a killing shot kills")
	eq(w.count("kill", archer), 1, "ranged kills report through the bridge")
	local paid = xpCalls(w, "ranged")
	eq(#paid, 1, "the kill pays the accrued ranged XP once")
	eq(paid[1].damage, Data.Monsters.BramblebackBoar.hp, "paid damage = the hp actually removed (overkill capped)")
	eq(paid[1].monster, "BramblebackBoar", "xp report names the monster")
	local ranged = P.styleXp("ranged", paid[1].damage, Data.Monsters.BramblebackBoar.xp, Data.Monsters.BramblebackBoar.hp)
	near(ranged.Ranged, Data.Monsters.BramblebackBoar.xp, "a ranged kill is worth monster.xp Ranged XP")
	near(ranged.Combat, Data.Monsters.BramblebackBoar.xp / 3, "plus a third of it to Combat")
	-- Weakness bonus: thornlings (magic) are weak to arrows.
	local thornMarker = L.addMarker("thorn", "Thornling", 1, origin)
	L.dueSpawns()
	local thorn = model("thorn")
	local tr = L.register(thornMarker, thorn, Vector3.new(0, 1, 0), {radius = 2})
	w.stats[archer].stats = styleStats({attackSpeed = 100})
	w.clock += 0.53
	w.rolls = {0, 0.99}
	local weak = L.ranged(archer, "ranged", thorn)
	local rawWeak = P.rangedDamage(w.stats[archer].stats, Data.Items.MeadowLongbow, Data.Items.CopperArrow, 1, function() return 0.99 end)
	eq(weak.damage, P.damageTaken(math.floor(rawWeak * 1.3), Data.Monsters.Thornling.defense), "+30% against the weakness")
	eq(weak.tag, "weak", "weakness tagged")
	eq(tr.weakness, "ranged", "thornlings are weak to ranged")
	-- Melee keeps working and now reports Combat XP for its damage.
	local brute = w.player("brute", Vector3.new(4, 1, 0))
	ok(L.attack(brute, "attack", thorn) ~= nil, "melee without a loadout still swings")
	eq(#xpCalls(w, "melee"), 0, "melee damage XP waits for the kill")
	ok(tr.contributors[brute].xp.melee > 0, "melee damage accrued on the monster")
	print("PASS: " .. (checks - stylesBefore) .. " ranged combat assertions.")
end
-- Spells, mana, cooldowns, utility spells.
do
	local before = checks
	local w = world()
	local L = w.logic
	local marker = L.addMarker("boar", "BramblebackBoar", 1, origin)
	L.dueSpawns()
	local target = model("boar")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	r.maxHp, r.hp = 1e9, 1e9
	local mage = w.player("mage", Vector3.new(30, 1, 0), {stats = styleStats({intelligence = 100})})
	local lo = {style = "melee", weapon = nil, levels = {Combat = 1, Ranged = 1, Magic = 1}, supplies = {}, ammoCount = 0}
	w.stats[mage].loadout = lo
	eq(select(2, L.cast(mage, "zap", target, "GaleDart")), "verb", "cast verb required")
	eq(select(2, L.cast(mage, "cast", target, "Fireball")), "spell", "unknown spell rejected")
	eq(select(2, L.cast(mage, "cast", target, nil)), "spell", "no spell and no autocast")
	eq(select(2, L.cast(mage, "cast", target, 42)), "spell", "non-string spell rejected")
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "weapon", "combat spells need a staff or wand")
	lo.style, lo.weapon = "magic", "MeadowWand"
	eq(select(2, L.cast(mage, "cast", target, "GaleLance")), "level", "lance needs Magic 30")
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "glyphs", "no glyphs, no spell")
	eq(select(2, L.cast(mage, "cast", nil, "GaleDart")), "target", "damage spells need a target")
	lo.supplies = {GaleGlyph = 2, SparkGlyph = 3}
	w.inv[mage] = {GaleGlyph = 2, SparkGlyph = 3}
	w.walls = true
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "sight", "spells need line of sight")
	w.walls = false
	eq(w.count("consume", mage), 0, "blocked casts spend nothing")
	w.positions[mage] = Vector3.new(43, 1, 0)
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "range", "spells reach 40 studs")
	w.positions[mage] = Vector3.new(30, 1, 0)
	local cast = L.cast(mage, "cast", target, "GaleDart")
	ok(cast ~= nil, "gale dart cast")
	local raw = P.spellDamage(w.stats[mage].stats, Data.Spells.GaleDart, Data.Items.MeadowWand, 1)
	eq(cast.damage, P.damageTaken(math.floor(raw * 1.3), Data.Monsters.BramblebackBoar.defense), "spell damage with the +30% weakness")
	eq(cast.tag, "weak", "boars are weak to magic")
	eq(cast.mana, 100 - Data.Spells.GaleDart.mana, "mana spent")
	eq(cast.maxMana, 100, "max mana is intelligence")
	eq(w.inv[mage].GaleGlyph, 1, "element glyph spent"); eq(w.inv[mage].SparkGlyph, 2, "catalyst spent")
	eq(lo.supplies.GaleGlyph, 1, "cached supplies follow the bridge")
	local mx = xpCalls(w, "magic")
	eq(#mx, 1, "spell reports cast XP once, immediately")
	eq(mx[1].spell, "GaleDart", "xp report names the spell (cast XP)")
	eq(mx[1].damage, nil, "damage XP waits for the kill")
	eq(r.contributors[mage].xp.magic, cast.damage, "magic damage accrued on the monster")
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "cooldown", "wand cooldown")
	w.clock += 0.8 - C.COOLDOWN_GRACE + 0.001
	ok(L.cast(mage, "cast", target, "GaleDart") ~= nil, "wand recast after 0.8s")
	w.clock += 1
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "glyphs", "out of gale glyphs")
	-- Elemental staff: gale glyphs are free, the catalyst is not.
	lo.weapon = "MeadowStaff"
	ok(L.cast(mage, "cast", target, "GaleDart") ~= nil, "staff supplies the element")
	eq(w.inv[mage].GaleGlyph, 0, "no gale glyph needed with the gale staff")
	eq(w.inv[mage].SparkGlyph, 0, "catalyst paid")
	w.clock += 0.9
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "cooldown", "staves cast slower than wands")
	w.clock += 0.4
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "glyphs", "out of catalysts")
	-- Stale cache refused by the bridge.
	lo.supplies.SparkGlyph = 9
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "glyphs", "bridge payment is authoritative")
	eq(lo.supplies.SparkGlyph, 0, "refused payment clears the cached glyphs")
	-- Mana: low intelligence runs dry, then regenerates.
	w.inv[mage].SparkGlyph, lo.supplies.SparkGlyph = 50, 50
	w.stats[mage].stats = styleStats({intelligence = 10})
	w.clock += 5
	ok(L.cast(mage, "cast", target, "GaleDart") ~= nil, "cast with 10 mana")
	w.clock += 1.3
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "mana", "not enough mana")
	local m = L.manaOf(mage, w.stats[mage].stats)
	ok(m.current < Data.Spells.GaleDart.mana and m.max == 10, "mana capped by the new max")
	w.clock += 20
	eq(math.floor(L.manaOf(mage).current), 10, "mana regenerates to max")
	-- Autocast.
	lo.autocast = "GaleDart"
	local auto = L.cast(mage, "cast", target, nil)
	ok(auto ~= nil and auto.spell == "GaleDart", "nil spell uses the autocast")
	w.clock += 1.3
	ok(L.cast(mage, "cast", target, "") == nil, "empty spell id uses the autocast too (mana gated)")
	w.stats[mage].stats = styleStats({intelligence = 500})
	eq(L.manaOf(mage, w.stats[mage].stats).max, 500, "raising intelligence raises max mana")
	ok(L.manaOf(mage).current < 20, "but does not refill the pool")
	-- Rootbind snares regular monsters, not bosses.
	lo.levels.Magic = 30
	lo.supplies.BindGlyph, lo.supplies.StoneGlyph = 2, 4
	w.inv[mage].BindGlyph, w.inv[mage].StoneGlyph = 2, 4
	w.clock += 30
	r.target = mage
	w.positions[mage] = Vector3.new(30, 1, 0)
	eq(L.think(r).kind, "chase", "a provoked boar chases")
	local bind = L.cast(mage, "cast", target, "Rootbind")
	ok(bind ~= nil and bind.kind == "snare" and bind.duration == 5, "rootbind lands")
	eq(L.think(r).kind, "hold", "snared monsters cannot move")
	eq(select(2, L.cast(mage, "cast", target, "Rootbind")), "cooldown", "rootbind has its own cooldown")
	w.clock += 5.1
	eq(L.think(r).kind, "chase", "the snare wears off")
	w.positions[mage] = Vector3.new(0, 1, 3)
	r.snaredUntil = w.clock + 5
	eq(L.think(r).kind, "strike", "snared monsters still strike in reach")
	local bossHolder = w.player("summoner", Vector3.new(60, 1, 60), {stats = styleStats()})
	local action, spec = L.bossAttribute(bossHolder, "Gloom:1")
	eq(action, "spawn", "boss queued")
	local bossModel = model("boss")
	local boss = L.registerBoss(bossHolder, spec, bossModel, Vector3.new(60, 1, 70))
	eq(boss.weakness, Data.Slayers.Gloom.weakness, "bosses carry their line's weakness")
	eq(boss.weakness, "melee", "the broodmother is weak to melee")
	w.stats[bossHolder].loadout = {style = "magic", weapon = "MeadowStaff", levels = {Magic = 30}, supplies = {BindGlyph = 2, StoneGlyph = 4}}
	eq(select(2, L.cast(bossHolder, "cast", bossModel, "Rootbind")), "immune", "slayer bosses cannot be snared")
	eq(select(2, L.cast(mage, "cast", bossModel, "GaleDart")), "owner", "other players' bosses stay untouchable")
	-- Mend heals without a weapon.
	lo.style, lo.weapon = "melee", "BrassSword"
	lo.supplies.VitaGlyph, lo.supplies.TideGlyph = 1, 2
	w.inv[mage].VitaGlyph, w.inv[mage].TideGlyph = 1, 2
	local mend = L.cast(mage, "cast", nil, "Mend")
	ok(mend ~= nil and mend.kind == "heal", "mend cast without a staff")
	eq(w.heals[#w.heals].percent, Data.Spells.Mend.heal, "mend heals its percentage")
	eq(xpCalls(w, "magic")[#xpCalls(w, "magic")].spell, "Mend", "mend grants cast XP")
	eq(xpCalls(w, "magic")[#xpCalls(w, "magic")].damage, nil, "mend reports no damage")
	eq(select(2, L.cast(mage, "cast", nil, "Mend")), "cooldown", "mend cooldown")
	-- Hubward tablet: combat lock, teleport, consumption.
	lo.supplies.HubwardTablet = 1
	w.inv[mage].HubwardTablet = 1
	L.strike(r, mage)
	eq(select(2, L.cast(mage, "cast", nil, "Hubward")), "combat", "no tablets within 5s of being struck")
	eq(#w.teleports, 0, "nobody teleported")
	w.clock += 5.1
	w.moving[mage] = true
	eq(select(2, L.cast(mage, "cast", nil, "Hubward")), "teleport", "no tablets during an agility move")
	eq(#w.teleports, 0, "a moving player is not teleported")
	eq(w.inv[mage].HubwardTablet, 1, "and keeps the tablet")
	w.moving[mage] = nil
	-- Stale cached supplies: the bridge refuses, so no free teleport.
	w.inv[mage].HubwardTablet = 0
	eq(select(2, L.cast(mage, "cast", nil, "Hubward")), "glyphs", "stale tablet cache refused")
	eq(#w.teleports, 0, "an unpaid tablet never teleports")
	w.inv[mage].HubwardTablet, lo.supplies.HubwardTablet = 1, 1
	local magicBefore = #xpCalls(w, "magic")
	w.hub = false
	eq(select(2, L.cast(mage, "cast", nil, "Hubward")), "teleport", "uncharted hub refuses")
	eq(w.count("refund", mage), 1, "a failed teleport refunds the tablet through the bridge")
	eq(w.inv[mage].HubwardTablet, 1, "a failed teleport keeps the tablet")
	eq(lo.supplies.HubwardTablet, 1, "cached supplies follow the refund")
	eq(#xpCalls(w, "magic"), magicBefore, "a failed teleport grants no XP")
	w.hub = true
	local port = L.cast(mage, "cast", nil, "Hubward")
	ok(port ~= nil and port.kind == "teleport", "hubward teleports")
	eq(#w.teleports, 2, "teleport invoked (once failed, once landed)")
	eq(w.inv[mage].HubwardTablet, 0, "tablet consumed")
	w.clock += 3.1
	eq(select(2, L.cast(mage, "cast", nil, "Hubward")), "glyphs", "no tablet left")
	-- Mana replication.
	local fresh = w.player("fresh", Vector3.new(100, 1, 100), {stats = styleStats({intelligence = 240})})
	local updates = L.manaTick()
	local mine
	for _, u in ipairs(updates) do if u.player == fresh then mine = u end end
	ok(mine ~= nil and mine.mana == 240 and mine.max == 240, "new players start with full mana")
	local again = 0
	for _, u in ipairs(L.manaTick()) do if u.player == fresh then again += 1 end end
	eq(again, 0, "unchanged mana is not re-sent")
	w.stats[fresh].stats.intelligence = 300
	w.clock += 2
	local stale = 0
	for _, u in ipairs(L.manaTick()) do if u.player == fresh then stale += 1 end end
	eq(stale, 0, "full-mana players are not re-read every tick")
	w.clock += C.MANA_REFRESH
	local grown
	for _, u in ipairs(L.manaTick()) do if u.player == fresh then grown = u end end
	ok(grown ~= nil and grown.max == 300, "max mana follows intelligence")
	w.stats[fresh] = nil
	-- Cleanup.
	ok(L.hasPlayerState(mage), "mage has combat state")
	L.playerRemoving(mage)
	ok(not L.hasPlayerState(mage), "mana, spell cooldowns and combat lock cleared on leave")
	print("PASS: " .. (checks - before) .. " magic combat assertions.")
end

------------------------------------------------------------------------------
-- Combat styles runtime: remote verbs, projectiles, denials, mana attributes,
-- Hubward teleport, under the same generic doubles as the smoke test.
------------------------------------------------------------------------------
do
	local before = checks
	local function signal()
		local listeners = {}
		local s = {}
		function s:Connect(f)
			local entry = {f = f, live = true}
			table.insert(listeners, entry)
			return {Disconnect = function() entry.live = false end}
		end
		function s:Fire(...) for _, e in ipairs(table.clone(listeners)) do if e.live then e.f(...) end end end
		return s
	end
	local defaults = {CFrame = CFrame.new(), Position = Vector3.zero, Size = Vector3.one}
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
	function Object:SetAttribute(k, v) self._attrs[k] = v; if self._attrSignals[k] then self._attrSignals[k]:Fire() end end
	function Object:GetAttribute(k) return self._attrs[k] end
	function Object:GetAttributeChangedSignal(k) self._attrSignals[k] = self._attrSignals[k] or signal(); return self._attrSignals[k] end
	function Object:IsA(class) return self.ClassName == class or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "WedgePart")) end
	function Object:Destroy() self.destroyed = true; self.Parent = nil end
	function Object:Clone() local c = object(self.ClassName); for k, v in pairs(self) do if k:sub(1, 1) ~= "_" then c[k] = v end end; return c end
	function Object:FindFirstChild(name) return self._children[name] end
	function Object:FindFirstChildOfClass(class) for _, c in pairs(self._children) do if c.ClassName == class then return c end end return nil end
	function Object:WaitForChild(name) return self._children[name] end
	function Object:GetChildren() local list = {} for _, c in pairs(self._children) do table.insert(list, c) end return list end
	function Object:PivotTo(cf) self.pivotedTo = cf end
	local function child(parent, o) parent._children[o.Name] = o; o.Parent = parent; return o end

	local now = 1000
	local created, fired, calls, warnings = {}, {}, {}, {}
	local heartbeat = signal()
	local players = {PlayerAdded = signal(), PlayerRemoving = signal(), list = {}}
	function players:GetPlayers() return self.list end
	local replicated = object("ReplicatedStorage")
	child(replicated, object("ModuleScript", {Name = "AetherData"}))
	child(replicated, object("ModuleScript", {Name = "AetherProgression"}))
	local serverStorage = object("ServerStorage")
	local runtimeMastery = nil -- Skill Mastery snapshot the bridge reports (set by the multishot check)
	local inv = {CopperArrow = 3, GaleGlyph = 5, SparkGlyph = 5, HubwardTablet = 1}
	local loadout = {style = "ranged", weapon = "MeadowLongbow", ammo = "CopperArrow", ammoCount = 3,
		levels = {Combat = 1, Ranged = 1, Magic = 1}, supplies = {GaleGlyph = 5, SparkGlyph = 5, HubwardTablet = 1}}
	child(serverStorage, object("BindableFunction", {Name = "IsleBridge", Invoke = function(_, op, player, payload)
		table.insert(calls, {op = op, player = player, payload = payload})
		if op == "stats" then
			return {stats = styleStats({intelligence = 150}), combatLevel = 3, ironman = false, loadout = loadout, mastery = runtimeMastery}
		elseif op == "refund" then
			for id, n in pairs(payload.items) do inv[id] = (inv[id] or 0) + n end
			return {ok = true}
		elseif op == "consume" then
			for id, n in pairs(payload.items) do if (inv[id] or 0) < n then return {ok = false} end end
			local remaining = {}
			for id, n in pairs(payload.items) do inv[id] -= n; remaining[id] = inv[id] end
			return {ok = true, remaining = remaining}
		end
		return {}
	end}))
	local spawnsFolder = object("Folder", {Name = "MonsterSpawns", ChildAdded = signal(), ChildRemoved = signal()})
	local workspaceDouble = object("Workspace")
	child(workspaceDouble, spawnsFolder)
	local wall = false
	-- Ground probes are vertical; line-of-sight rays are mostly horizontal.
	function workspaceDouble:Raycast(origin, direction)
		if math.abs(direction.Y) > math.abs(direction.X) + math.abs(direction.Z) then return {Position = Vector3.new(origin.X, 0, origin.Z)} end
		return if wall then {Position = origin + direction / 2} else nil
	end
	function workspaceDouble:GetServerTimeNow() return now end
	local islands = child(workspaceDouble, object("Folder", {Name = "Islands"}))
	local services = {
		Players = players, ReplicatedStorage = replicated, ServerStorage = serverStorage,
		RunService = {Heartbeat = heartbeat},
		CollectionService = {AddTag = function() end},
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
		Random = {new = function() return {NextNumber = function(_, a, b) a, b = a or 0, b or 1; return a + (b - a) * 0.01 end} end},
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
	local monsters = workspaceDouble._children.IsleMonsters
	local function fires(kind) local list = {} for _, f in ipairs(fired) do if f.kind == kind then table.insert(list, f) end end return list end
	local function opCount(op) local n = 0 for _, c in ipairs(calls) do if c.op == op then n += 1 end end return n end
	local function tick(seconds) for _ = 1, math.ceil(seconds / 0.1) do now += 0.1; heartbeat:Fire(0.1) end end

	local humanoid = object("Humanoid", {Health = 100, MaxHealth = 100})
	local root = object("Part", {Name = "HumanoidRootPart", Position = Vector3.new(30, 3, 0), CFrame = CFrame.new(30, 3, 0)})
	local character = object("Model")
	child(character, humanoid); child(character, root)
	local hero = object("Player", {Name = "Ranger", UserId = 9, Character = character, CharacterAdded = signal()})
	hero.Parent = players
	table.insert(players.list, hero)
	players.PlayerAdded:Fire(hero)
	local marker = object("Part", {Name = "BoarMarker", Position = Vector3.new(0, 1, 0)})
	marker:SetAttribute("MonsterId", "BramblebackBoar")
	marker:SetAttribute("Count", 1)
	child(spawnsFolder, marker)
	spawnsFolder.ChildAdded:Fire(marker)
	tick(0.6)
	eq(hero:GetAttribute("MaxMana"), 150, "MaxMana attribute replicated")
	eq(hero:GetAttribute("Mana"), 150, "Mana attribute starts full")
	local boar
	for _, o in ipairs(created) do if o.ClassName == "Model" and o.Parent == monsters then boar = o end end
	ok(boar ~= nil, "boar spawned")
	local boarPos = boar.PrimaryPart.CFrame.Position
	root.Position = boarPos + Vector3.new(30, 0, 0)
	local hpBefore = boar:GetAttribute("Health")
	-- Melee spam with a bow is denied with a reason.
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", boar)
	local denied = fires("denied")
	eq(#denied, 1, "melee with a bow is refused out loud")
	eq(denied[1].payload.reason, "range", "out of melee reach first")
	now += 1
	root.Position = boarPos + Vector3.new(4, 0, 0)
	remotes.IsleCombat.OnServerEvent:Fire(hero, "attack", boar)
	eq(fires("denied")[2].payload.reason, "style", "then the style refusal")
	root.Position = boarPos + Vector3.new(30, 0, 0)
	-- A bow shot.
	remotes.IsleCombat.OnServerEvent:Fire(hero, "ranged", boar)
	ok(boar:GetAttribute("Health") < hpBefore, "arrow lowers model health")
	eq(inv.CopperArrow, 2, "arrow consumed through the bridge")
	eq(hero:GetAttribute("QuiverCount"), 2, "QuiverCount attribute replicated")
	local projectiles = fires("projectile")
	eq(#projectiles, 1, "projectile broadcast")
	eq(projectiles[1].payload.style, "ranged", "projectile style")
	eq(projectiles[1].payload.color, Data.Items.CopperArrow.color, "projectile coloured by the arrow")
	local hits = fires("hit")
	eq(#hits, 1, "hit broadcast")
	eq(hits[1].payload.style, "ranged", "hit carries the style")
	eq(hits[1].payload.tag, "resist", "hit carries the triangle tag")
	eq(opCount("combatXp"), 0, "damage XP waits for the kill")
	-- Line of sight blocked: denied, no arrow spent.
	now += 2
	wall = true
	remotes.IsleCombat.OnServerEvent:Fire(hero, "ranged", boar)
	eq(fires("denied")[#fires("denied")].payload.reason, "sight", "walls block arrows")
	eq(inv.CopperArrow, 2, "blocked shot keeps the arrow")
	wall = false
	-- Malformed casts are ignored silently.
	local deniedBefore = #fires("denied")
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", "nope", "GaleDart")
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", boar, {})
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", boar, string.rep("x", 60))
	remotes.IsleCombat.OnServerEvent:Fire(hero, "dance", boar)
	eq(#fires("denied"), deniedBefore, "malformed requests are dropped without a notice")
	-- Swap to a wand: a dart.
	loadout.style, loadout.weapon = "magic", "MeadowWand"
	now += 2
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", boar, "GaleDart")
	eq(#fires("projectile"), 2, "spell projectile broadcast")
	eq(fires("projectile")[2].payload.spell, "GaleDart", "projectile names the spell")
	eq(fires("hit")[#fires("hit")].payload.tag, "weak", "magic hits the boar's weakness")
	eq(hero:GetAttribute("Mana"), 150 - Data.Spells.GaleDart.mana, "Mana attribute updated on cast")
	eq(inv.GaleGlyph, 4, "glyph consumed"); eq(inv.SparkGlyph, 4, "catalyst consumed")
	-- Denials are throttled.
	now += 0.05
	local count = #fires("denied")
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", boar, "GaleLance")
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", boar, "GaleLance")
	eq(#fires("denied"), count + 1, "denied notices are rate limited")
	eq(fires("denied")[#fires("denied")].payload.reason, "level", "level refusal reported")
	-- Hubward: no hub island yet, then a charted hub.
	now += 6
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", nil, "Hubward")
	eq(fires("denied")[#fires("denied")].payload.reason, "teleport", "uncharted hub refuses the tablet")
	eq(inv.HubwardTablet, 1, "tablet kept")
	local hub = child(islands, object("Model", {Name = "HubIsland"}))
	hub:SetAttribute("Region", "Hub")
	child(hub, object("Part", {Name = "Anchor_Landing", Position = Vector3.new(500, 10, 500), Size = Vector3.new(4, 2, 4)}))
	now += 4
	remotes.IsleCombat.OnServerEvent:Fire(hero, "cast", nil, "Hubward")
	ok(character.pivotedTo ~= nil and (character.pivotedTo.Position - Vector3.new(500, 14.5, 500)).Magnitude < 1e-3, "hubward lands on the hub anchor")
	eq(inv.HubwardTablet, 0, "tablet consumed")
	eq(#fires("teleport"), 1, "teleport confirmed to the caster")
	-- Mana regenerates and replicates through the AI loop.
	tick(10)
	eq(hero:GetAttribute("Mana"), 150, "mana regenerates to full")
	-- Skill Mastery multishot: a Volley arrow shows one projectile and one hit per target.
	local thornMarker = object("Part", {Name = "ThornMarker", Position = boar.PrimaryPart.CFrame.Position})
	thornMarker:SetAttribute("MonsterId", "Thornling")
	thornMarker:SetAttribute("Count", 1)
	child(spawnsFolder, thornMarker)
	spawnsFolder.ChildAdded:Fire(thornMarker)
	tick(0.6)
	local thornModel
	for _, o in ipairs(created) do if o.ClassName == "Model" and o.Parent == monsters and o ~= boar then thornModel = o end end
	ok(thornModel ~= nil, "a second monster spawned beside the boar")
	local here = boar.PrimaryPart.CFrame.Position
	root.Position = here + Vector3.new(20, 0, 0)
	loadout.style, loadout.weapon, loadout.ammo, loadout.ammoCount = "ranged", "MeadowLongbow", "CopperArrow", inv.CopperArrow
	runtimeMastery = {melee = {firstStrike = 0, execute = 0, xpBoost = 0}, ranged = {firstStrike = 0, execute = 0, arrowSave = 0, multishot = 3, xpBoost = 0},
		magic = {manaThrift = 0, glyphSave = 0, xpBoost = 0}, active = {Ranged = os.time() + 60}}
	now += 2
	local projectilesBefore, hitsBefore, arrowsBefore = #fires("projectile"), #fires("hit"), inv.CopperArrow
	remotes.IsleCombat.OnServerEvent:Fire(hero, "ranged", boar)
	eq(#fires("projectile") - projectilesBefore, 2, "Volley: one projectile per struck target")
	eq(#fires("hit") - hitsBefore, 2, "Volley: one hit per struck target")
	eq(fires("hit")[#fires("hit")].payload.model, thornModel, "the extra hit names the second monster")
	eq(arrowsBefore - inv.CopperArrow, 1, "one arrow for the volley")
	runtimeMastery = nil
	players.PlayerRemoving:Fire(hero)
	eq(#warnings, 0,"no runtime warnings: " .. table.concat(warnings, "; "))
	print("PASS: " .. (checks - before) .. " combat style runtime assertions.")
end
print("PASS: " .. (checks - stylesBefore) .. " combat style assertions in total.")

------------------------------------------------------------------------------
-- Skill Mastery combat perks: firstStrike, execute, manaThrift, multishot
-- (bridge "stats" mastery = Progression.masteryCombat; capstones via .active).
------------------------------------------------------------------------------
local masteryBefore = checks
local function masteryOf(melee, ranged, magic, active)
	return {melee = melee or {firstStrike = 0, execute = 0, xpBoost = 0},
		ranged = ranged or {firstStrike = 0, execute = 0, arrowSave = 0, multishot = 1, xpBoost = 0},
		magic = magic or {manaThrift = 0, glyphSave = 0, xpBoost = 0}, active = active or {}}
end
-- Refund after a failed teleport returns only what was spent: glyphs kept by
-- Ink Thrift (glyphSave=100, consume reply "saved") are never refunded.
do
	local before = checks
	local w = world()
	local L = w.logic
	Data.Spells.TestGlyphPort = {id = "TestGlyphPort", name = "Test Glyph Port", kind = "teleport", level = 1, mana = 0, xp = 10, cooldown = 3,
		requiresWeapon = false, color = "F9CC77", costs = {GaleGlyph = 2, HubwardTablet = 1}}
	Data.Spells.TestInkPort = {id = "TestInkPort", name = "Test Ink Port", kind = "teleport", level = 1, mana = 0, xp = 10, cooldown = 3,
		requiresWeapon = false, color = "F9CC77", costs = {GaleGlyph = 3}}
	local mage = w.player("thrifty", Vector3.new(30, 1, 0), {stats = styleStats({intelligence = 100})})
	local lo = {style = "melee", weapon = "BrassSword", levels = {Combat = 1, Ranged = 1, Magic = 1}, supplies = {GaleGlyph = 4, HubwardTablet = 1}}
	w.stats[mage].loadout = lo
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 0, glyphSave = 100, xpBoost = 0})
	w.inv[mage] = {GaleGlyph = 4, HubwardTablet = 1}
	w.glyphSave = true
	w.hub = false
	eq(select(2, L.cast(mage, "cast", nil, "TestGlyphPort")), "teleport", "mock glyph teleport fails")
	eq(w.count("refund", mage), 1, "the spent tablet is refunded")
	local refund = w.calls[#w.calls]
	eq(refund.op, "refund", "last bridge call is the refund")
	eq(refund.payload.items.GaleGlyph, nil, "saved glyphs are not refunded")
	eq(refund.payload.items.HubwardTablet, 1, "the spent tablet is refunded")
	eq(w.inv[mage].GaleGlyph, 4, "glyphs not inflated by a refund (4 kept, not 6)")
	eq(w.inv[mage].HubwardTablet, 1, "tablet back")
	eq(lo.supplies.GaleGlyph, 4, "cached glyph supplies stay at 4")
	eq(lo.supplies.HubwardTablet, 1, "cached tablet supplies follow the refund")
	-- Everything saved: nothing was spent, so no refund call at all.
	w.clock += 5
	eq(select(2, L.cast(mage, "cast", nil, "TestInkPort")), "teleport", "mock ink teleport fails")
	eq(w.count("refund", mage), 1, "nothing spent: no refund call")
	eq(w.inv[mage].GaleGlyph, 4, "glyph count unchanged")
	eq(lo.supplies.GaleGlyph, 4, "cached glyphs unchanged")
	-- Without thrift the full cost is refunded, as before.
	w.glyphSave = false
	w.clock += 5
	eq(select(2, L.cast(mage, "cast", nil, "TestInkPort")), "teleport", "mock ink teleport fails without thrift")
	eq(w.count("refund", mage), 2, "spent glyphs refunded")
	eq(w.calls[#w.calls].payload.items.GaleGlyph, 3, "full spent cost refunded")
	eq(w.inv[mage].GaleGlyph, 4, "glyphs restored exactly")
	eq(lo.supplies.GaleGlyph, 4, "cache restored exactly")
	Data.Spells.TestGlyphPort, Data.Spells.TestInkPort = nil, nil
	print("PASS: " .. (checks - before) .. " thrift-aware refund assertions.")
end
-- Perk snapshot: defaults, sanitising, capstone active vs expired.
do
	local w = world()
	local L = w.logic
	local none = L.perks(nil, "melee")
	ok(none.firstStrike == 0 and none.execute == 0 and none.manaThrift == 0 and none.multishot == 1, "no stats: neutral perks")
	local plain = L.perks({stats = {}}, "ranged")
	ok(plain.firstStrike == 0 and plain.multishot == 1, "no mastery: neutral perks")
	eq(L.perks({mastery = {ranged = "junk"}}, "ranged").multishot, 1, "malformed style perks ignored")
	local wild = L.perks({mastery = masteryOf({firstStrike = 150, execute = -5}, {multishot = 10}, {manaThrift = 0 / 0})}, "melee")
	eq(wild.firstStrike, 100, "firstStrike capped at 100%")
	eq(wild.execute, 0, "negative execute clamps to 0")
	eq(L.perks({mastery = masteryOf(nil, {multishot = 10})}, "ranged").multishot, C.MULTISHOT_MAX, "multishot never above the Volley cap")
	eq(L.perks({mastery = masteryOf(nil, {multishot = 2.7})}, "ranged").multishot, 2, "multishot floors")
	eq(L.perks({mastery = masteryOf(nil, nil, {manaThrift = 0 / 0})}, "magic").manaThrift, 0, "NaN thrift ignored")
	eq(C.MULTISHOT_MAX, Data.Mastery.TreeById.Ranged.NodeById.Volley.ability.multishot, "cap matches the Volley capstone")
	-- Real numbers through Progression.masteryCombat: Volley and Glyphstorm.
	local p = {mastery = {trees = {Ranged = {PinningShot = 5, QuarryMark = 5, Volley = 1}, Magic = {ManaWeave = 5, LeanCasting = 5, Glyphstorm = 1},
		Melee = {OpeningBlow = 5, Finisher = 5}}, active = {Ranged = {started = 4990, expires = 5000}, Magic = {started = 4990, expires = 5005}}}}
	local live = {mastery = P.masteryCombat(p, 4995)}
	eq(live.mastery.active.Ranged, 5000, "bridge reports the Volley expiry")
	w.wall = 4995
	local ranged = L.perks(live, "ranged")
	eq(ranged.multishot, 3, "Volley running: shots strike 3 targets")
	eq(ranged.firstStrike, 50, "Pinning Shot x5 = 50% opening blow")
	eq(ranged.execute, 20, "Quarry Mark x5 = +20% execute")
	eq(L.perks(live, "magic").manaThrift, 75, "Glyphstorm running: 25% + 50% thrift")
	eq(L.perks(live, "melee").firstStrike, 50, "Opening Blow x5 = 50%")
	eq(L.perks(live, "melee").execute, 20, "Finisher x5 = +20%")
	w.wall = 5000
	eq(L.perks(live, "ranged").multishot, 1, "an expired Volley in a cached snapshot no longer splits shots")
	eq(L.perks(live, "ranged").firstStrike, 50, "node perks outlive the capstone")
	eq(L.perks(live, "magic").manaThrift, 75, "Glyphstorm still running until its own expiry")
	w.wall = 5005
	eq(L.perks(live, "magic").manaThrift, 25, "an expired Glyphstorm gives its 50% back")
	eq(P.masteryCombat(p, 5005).magic.manaThrift, L.perks(live, "magic").manaThrift, "matches a fresh bridge snapshot")
	eq(P.masteryCombat(p, 5005).ranged.multishot, L.perks(live, "ranged").multishot, "multishot matches a fresh snapshot")
	local noCap = {mastery = P.masteryCombat({mastery = {trees = {Ranged = {PinningShot = 1}}}}, 4995)}
	eq(L.perks(noCap, "ranged").multishot, 1, "no Volley: one target")
	print("PASS: " .. (checks - masteryBefore) .. " mastery perk snapshot assertions.")
end
-- manaThrift: rounding, floor at 0, mana gate, Glyphstorm.
do
	local before = checks
	local w = world()
	local L = w.logic
	eq(Data.Spells.GaleDart.mana, 6, "gale dart costs 6 mana")
	local dart = Data.Spells.GaleDart
	eq(L.spellManaCost(dart, 0), 6, "no thrift: full cost")
	eq(L.spellManaCost(dart, nil), 6, "missing thrift: full cost")
	eq(L.spellManaCost(dart, -20), 6, "negative thrift never raises the cost")
	eq(L.spellManaCost(dart, 25), 5, "4.5 rounds up to 5")
	eq(L.spellManaCost(dart, 26), 4, "4.44 rounds down to 4")
	eq(L.spellManaCost(dart, 50), 3, "half cost")
	eq(L.spellManaCost(dart, 75), 2, "1.5 rounds up to 2")
	eq(L.spellManaCost(dart, 92), 0, "0.48 rounds to 0")
	eq(L.spellManaCost(dart, 100), 0, "100% thrift is free")
	eq(L.spellManaCost(dart, 250), 0, "cost floors at 0")
	eq(L.spellManaCost(Data.Spells.Hubward, 50), 0, "free spells stay free")
	eq(L.spellManaCost(Data.Spells.Mend, 25), 30, "mend 40 x 0.75")
	local marker = L.addMarker("boar", "BramblebackBoar", 1, origin)
	L.dueSpawns()
	local target = model("boar")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	r.maxHp, r.hp = 1e9, 1e9
	local mage = w.player("mage", Vector3.new(20, 1, 0), {stats = styleStats({intelligence = 100})})
	local lo = {style = "magic", weapon = "MeadowWand", levels = {Combat = 1, Ranged = 1, Magic = 1}, supplies = {GaleGlyph = 50, SparkGlyph = 50}}
	w.stats[mage].loadout = lo
	w.inv[mage] = {GaleGlyph = 50, SparkGlyph = 50}
	local full = L.cast(mage, "cast", target, "GaleDart")
	eq(full.manaCost, 6, "without perks a dart costs 6")
	eq(full.mana, 94, "6 mana spent")
	w.clock += 2
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 25, glyphSave = 0, xpBoost = 0})
	L.manaOf(mage).current = 100
	local lean = L.cast(mage, "cast", target, "GaleDart")
	eq(lean.manaCost, 5, "25% thrift: 5 mana")
	eq(lean.mana, 95, "5 mana spent")
	-- Glyphstorm running (bridge folds +50 in), then expired in the cached snapshot.
	w.clock += 2
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 75, glyphSave = 100, xpBoost = 0}, {Magic = w.wall + 15})
	L.manaOf(mage).current = 100
	eq(L.cast(mage, "cast", target, "GaleDart").manaCost, 2, "Glyphstorm: 75% thrift")
	w.clock += 2
	w.wall += 15
	L.manaOf(mage).current = 100
	eq(L.cast(mage, "cast", target, "GaleDart").manaCost, 5, "Glyphstorm expired: back to 25%")
	-- The mana gate uses the reduced cost.
	w.clock += 2
	w.stats[mage].stats = styleStats({intelligence = 2})
	L.statsFor(mage)
	w.clock += 2
	L.manaOf(mage, w.stats[mage].stats).current = 2
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 0})
	eq(select(2, L.cast(mage, "cast", target, "GaleDart")), "mana", "2 mana cannot pay 6")
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 75})
	local cheap = L.cast(mage, "cast", target, "GaleDart")
	ok(cheap ~= nil and cheap.manaCost == 2 and cheap.mana == 0, "75% thrift casts on 2 mana and never goes negative")
	w.clock += 2
	w.stats[mage].mastery = masteryOf(nil, nil, {manaThrift = 100})
	local free = L.cast(mage, "cast", target, "GaleDart")
	ok(free ~= nil and free.manaCost == 0 and free.mana >= 0, "100% thrift casts at 0 mana cost")
	print("PASS: " .. (checks - before) .. " manaThrift assertions.")
end
-- execute: strictly below 30% health, melee and ranged.
do
	local before = checks
	local w = world()
	local L = w.logic
	local marker = L.addMarker("boar", "BramblebackBoar", 3, origin)
	L.dueSpawns()
	local target = model("boar")
	local r = L.register(marker, target, Vector3.new(0, 1, 0), {radius = 2})
	r.maxHp = 1000
	local brute = w.player("brute", Vector3.new(4, 1, 0), {stats = styleStats({damage = 95})})
	local base = P.damageTaken(100, r.defense) -- (5 + 95), no crit, neutral style
	local function swing(hp)
		r.hp = hp
		w.clock += 1
		w.rolls = {0.99}
		return L.attack(brute, "attack", target)
	end
	eq(swing(300).damage, base, "no perks: no execute bonus")
	w.stats[brute].mastery = masteryOf({firstStrike = 0, execute = 20, xpBoost = 0})
	local edge = swing(300)
	eq(edge.damage, base, "exactly 30% health: no execute")
	eq(edge.execute, nil, "boundary not flagged")
	local below = swing(299)
	eq(below.damage, P.damageTaken(120, r.defense), "below 30%: +20% damage")
	ok(below.execute == true, "execute flagged")
	eq(swing(1000).damage, base, "healthy targets take normal damage")
	w.stats[brute].mastery = masteryOf({firstStrike = 0, execute = 20, xpBoost = 0}, nil, nil, {Melee = w.wall + 5})
	eq(swing(200).damage, P.damageTaken(120, r.defense), "execute is a node perk: unaffected by capstone timing")
	-- XP accrual is capped by the hp actually removed.
	r.contributors = {}
	local finisher = swing(50)
	ok(finisher.killed and r.contributors[brute].xp.melee == 50, "an execute kill accrues the remaining hp only")
	-- Ranged execute uses the ranged tree only.
	local m2 = model("boar2")
	local r2 = L.register(marker, m2, Vector3.new(0, 1, 0), {radius = 2})
	r2.maxHp, r2.hp = 1000, 200
	local archer = w.player("archer", Vector3.new(20, 1, 0), {stats = styleStats({rangedAccuracy = 1000})})
	w.stats[archer].loadout = {style = "ranged", weapon = "MeadowLongbow", ammo = "CopperArrow", ammoCount = 20, levels = {Ranged = 1}, supplies = {}}
	w.inv[archer] = {CopperArrow = 20}
	w.stats[archer].mastery = masteryOf({firstStrike = 0, execute = 50, xpBoost = 0})
	local rawShot = P.rangedDamage(w.stats[archer].stats, Data.Items.MeadowLongbow, Data.Items.CopperArrow, 1, function() return 0.99 end)
	w.rolls = {0, 0.99}
	eq(L.ranged(archer, "ranged", m2).damage, P.damageTaken(math.floor(rawShot * 0.7), r2.defense), "melee execute does not boost arrows")
	w.stats[archer].mastery = masteryOf(nil, {firstStrike = 0, execute = 50, arrowSave = 0, multishot = 1, xpBoost = 0})
	w.clock += 2
	r2.hp = 200
	w.rolls = {0, 0.99}
	local shot = L.ranged(archer, "ranged", m2)
	eq(shot.damage, P.damageTaken(math.floor(rawShot * 1.5 * 0.7), r2.defense), "ranged execute +50% before the resist")
	ok(shot.execute == true, "ranged execute flagged")
	print("PASS: " .. (checks - before) .. " execute assertions.")
end
-- firstStrike: first landed hit on a full-health monster, once per monster per player.
do
	local before = checks
	local w = world()
	local L = w.logic
	local marker = L.addMarker("boar", "BramblebackBoar", 3, origin)
	L.dueSpawns()
	local function boar(name)
		local m = model(name)
		local r = L.register(marker, m, Vector3.new(0, 1, 0), {radius = 2})
		r.maxHp, r.hp = 1e6, 1e6
		return m, r
	end
	local stats = styleStats({damage = 95, critDamage = 50})
	local plainHit, critHit = 100, 150
	local brute = w.player("brute", Vector3.new(4, 1, 0), {stats = stats})
	local m1, r1 = boar("b1")
	w.rolls = {0.99}
	local hit = L.attack(brute, "attack", m1)
	ok(hit.crit == false and hit.damage == plainHit and hit.firstStrike == nil, "no perks: no opening crit")
	eq(#w.rolls, 0, "only the crit roll was used")
	-- With the perk, but the monster is no longer at full health.
	w.stats[brute].mastery = masteryOf({firstStrike = 100, execute = 0, xpBoost = 0})
	w.clock += 1
	w.rolls = {0.99, 0.99}
	ok(not L.attack(brute, "attack", m1).crit, "a wounded monster gives no opening blow")
	eq(#w.rolls, 1, "and spends no opening roll")
	-- Fresh monster: forced crit.
	local m2, r2 = boar("b2")
	w.clock += 1
	w.rolls = {0.99, 0.99}
	local opening = L.attack(brute, "attack", m2)
	ok(opening.crit and opening.firstStrike and opening.damage == critHit, "first hit on a full-health monster crits")
	-- Healed back to full (leash): still only once per monster per player.
	r2.hp = r2.maxHp
	w.clock += 1
	w.rolls = {0.99, 0.99}
	local again = L.attack(brute, "attack", m2)
	ok(not again.crit and again.firstStrike == nil, "the opening blow is once per monster per player")
	-- A failed roll still uses up the opening blow.
	w.stats[brute].mastery = masteryOf({firstStrike = 10, execute = 0, xpBoost = 0})
	local m3, r3 = boar("b3")
	w.clock += 1
	w.rolls = {0.5, 0.99}
	ok(not L.attack(brute, "attack", m3).crit, "50 >= 10%: no opening crit")
	r3.hp = r3.maxHp
	w.clock += 1
	w.rolls = {0.01, 0.99}
	ok(not L.attack(brute, "attack", m3).crit, "no second opening roll after a failed one")
	local m4 = boar("b4")
	w.clock += 1
	w.rolls = {0.05, 0.99}
	ok(L.attack(brute, "attack", m4).crit, "5 < 10%: opening crit")
	-- Another player gets their own opening blow, only while the monster is at full health.
	local m5, r5 = boar("b5")
	local second = w.player("second", Vector3.new(-4, 1, 0), {stats = stats})
	w.stats[second].mastery = masteryOf({firstStrike = 100, execute = 0, xpBoost = 0})
	w.rolls = {0.99, 0.99}
	ok(L.attack(second, "attack", m5).crit, "second player opens on a fresh monster")
	w.clock += 1
	w.rolls = {0.99, 0.99}
	ok(not L.attack(brute, "attack", m5).crit, "the first player cannot open a wounded monster")
	eq(r5.opened[brute], nil, "and spends nothing on it")
	-- Capstone timing never touches the opening blow (a node perk).
	w.stats[brute].mastery = masteryOf({firstStrike = 100, execute = 0, xpBoost = 0}, nil, nil, {Melee = w.wall - 1})
	local m6 = boar("b6")
	w.clock += 1
	w.rolls = {0.99, 0.99}
	ok(L.attack(brute, "attack", m6).crit, "an expired Warcry leaves Opening Blow intact")
	-- Ranged: a miss is not a hit; the next landed arrow opens.
	local archer = w.player("archer", Vector3.new(20, 1, 0), {stats = styleStats({rangedAccuracy = 0, critDamage = 50})})
	w.stats[archer].loadout = {style = "ranged", weapon = "MeadowLongbow", ammo = "CopperArrow", ammoCount = 20, levels = {Ranged = 1}, supplies = {}}
	w.inv[archer] = {CopperArrow = 20}
	w.stats[archer].mastery = masteryOf({firstStrike = 100, execute = 0, xpBoost = 0}, {firstStrike = 10, execute = 0, arrowSave = 0, multishot = 1, xpBoost = 0})
	local m7, r7 = boar("b7")
	w.rolls = {0.999}
	ok(L.ranged(archer, "ranged", m7).miss, "the opening arrow misses")
	eq(r7.opened, nil, "a miss does not use the opening blow")
	w.clock += 2
	w.rolls = {0, 0.05, 0.99}
	local arrowOpen = L.ranged(archer, "ranged", m7)
	ok(arrowOpen.crit and arrowOpen.firstStrike, "ranged tree's 10% opens with the first landed arrow")
	local forced = table.clone(w.stats[archer].stats); forced.critChance = 100
	local rawCrit = P.rangedDamage(forced, Data.Items.MeadowLongbow, Data.Items.CopperArrow, 1, function() return 0.99 end)
	eq(arrowOpen.damage, P.damageTaken(math.floor(rawCrit * 0.7), r7.defense), "opening arrow deals crit damage")
	w.clock += 2
	r7.hp = r7.maxHp
	w.rolls = {0, 0.01, 0.99}
	ok(not L.ranged(archer, "ranged", m7).crit, "one opening arrow per monster")
	print("PASS: " .. (checks - before) .. " firstStrike assertions.")
end
-- multishot: Volley splits a shot over up to 3 valid nearby targets, one arrow.
do
	local before = checks
	local w = world()
	local L = w.logic
	local marker = L.addMarker("pack", "Thornling", 3, origin)
	L.dueSpawns()
	local function thorn(name, pos, radius)
		local m = model(name)
		local r = L.register(marker, m, pos, {radius = radius or 0})
		r.maxHp, r.hp = 1e6, 1e6
		return m, r
	end
	local mp, rp = thorn("primary", Vector3.new(0, 1, 0), 2)
	local ma, ra = thorn("a", Vector3.new(0, 1, 5))
	local mb, rb = thorn("b", Vector3.new(0, 1, 8))
	local mc, rc = thorn("c", Vector3.new(0, 1, -10))
	local _, rd = thorn("far", Vector3.new(0, 1, 20))     -- 20 studs from the target
	local _, re = thorn("outOfReach", Vector3.new(-12, 1, 0)) -- 42 studs from the archer
	local archer = w.player("archer", Vector3.new(30, 1, 0), {stats = styleStats({rangedAccuracy = 1000})})
	local lo = {style = "ranged", weapon = "MeadowLongbow", ammo = "CopperArrow", ammoCount = 50, levels = {Ranged = 1}, supplies = {}}
	w.stats[archer].loadout = lo
	w.inv[archer] = {CopperArrow = 50}
	local function shoot(target)
		w.clock += 2
		w.rolls = {}
		return L.ranged(archer, "ranged", target or mp)
	end
	local function struck(shot)
		local set = {}
		for _, h in ipairs(shot.extra or {}) do set[h.record] = true end
		return set
	end
	-- No perks: one target.
	local single = shoot()
	ok(single ~= nil and single.extra == nil, "no multishot: one target")
	eq(rp.hp, 1e6 - single.damage, "primary struck")
	-- Volley running: the two nearest valid extras.
	w.stats[archer].mastery = masteryOf(nil, {firstStrike = 0, execute = 0, arrowSave = 0, multishot = 3, xpBoost = 0}, nil, {Ranged = w.wall + 10})
	local consumes = w.count("consume", archer)
	local volley = shoot()
	eq(#volley.extra, 2, "Volley: two extra targets")
	local set = struck(volley)
	ok(set[ra] and set[rb], "nearest extras chosen first")
	eq(w.count("consume", archer) - consumes, 1, "one arrow paid per shot")
	eq(w.inv[archer].CopperArrow, 48, "one arrow consumed for three targets")
	eq(volley.ammoLeft, 48, "quiver count follows one arrow")
	ok(volley.extra[1].damage > 0 and ra.hp < 1e6 and rb.hp < 1e6, "extras take damage")
	eq(ra.contributors[archer].xp.ranged, 1e6 - ra.hp, "extra hits accrue ranged XP like a normal hit")
	eq(ra.target, archer, "extras are provoked by the archer")
	eq(rc.hp, 1e6, "the third extra is beyond the cap")
	eq(rd.hp, 1e6, "monsters far from the target are never struck")
	eq(re.hp, 1e6, "monsters beyond the bow's reach are never struck")
	-- A bogus multishot never exceeds the cap.
	w.stats[archer].mastery.ranged.multishot = 99
	eq(#shoot().extra, 2, "multishot 99 still strikes at most 3 targets")
	-- Leashing and line-of-sight-blocked monsters are skipped.
	ra.leashing = true
	w.blocked[rb] = true
	local filtered = shoot()
	set = struck(filtered)
	ok(#filtered.extra == 1 and set[rc], "skips leashing and blocked targets, takes the next valid one")
	ok(not set[ra] and not set[rb] and not set[rd] and not set[re], "never a leashing, blocked, far or out-of-reach monster")
	ra.leashing = false
	w.blocked[rb] = nil
	-- Expired Volley in the cached snapshot: back to one target.
	w.wall += 10
	ok(shoot().extra == nil, "an expired Volley strikes one target")
	w.wall -= 10
	-- Dead extras and other players' slayer bosses are never struck.
	rb.alive = false
	local summoner = w.player("summoner", Vector3.new(60, 1, 60), {stats = styleStats()})
	local _, spec = L.bossAttribute(summoner, "Gloom:1")
	local bossModel = model("boss")
	local boss = L.registerBoss(summoner, spec, bossModel, Vector3.new(3, 1, 0))
	local bossHp = boss.hp
	set = struck(shoot())
	ok(set[ra] and set[rc] and not set[rb] and not set[boss], "dead monsters and others' bosses skipped")
	eq(boss.hp, bossHp, "the boss is untouched")
	rb.alive = true
	L.unregister(boss)
	-- Ironman rules: never splash onto another Ironman's fight; an Ironman never splashes onto anyone's.
	local iron = w.player("iron", Vector3.new(0, 1, 30), {stats = styleStats(), ironman = true})
	L.statsFor(iron)
	ra.contributors[iron] = {damage = 5, xp = {melee = 5}}
	set = struck(shoot())
	ok(not set[ra] and set[rb] and set[rc], "another Ironman's monster is skipped")
	ra.contributors[iron] = nil
	w.stats[archer].ironman = true
	L.statsFor(archer)
	local helper = w.player("helper", Vector3.new(0, 1, 30), {stats = styleStats()})
	rb.contributors[helper] = {damage = 5, xp = {melee = 5}}
	set = struck(shoot())
	ok(set[ra] and not set[rb] and set[rc], "an Ironman's arrows skip monsters others have fought")
	w.stats[archer].ironman = false
	rb.contributors[helper] = nil
	-- Extras roll their own accuracy: a miss accrues nothing.
	w.clock += 2
	local hpA, hpB = ra.hp, rb.hp
	w.rolls = {0, 0.99, 0.999, 0, 0.99}
	local mixed = L.ranged(archer, "ranged", mp)
	ok(mixed.extra[1].miss and mixed.extra[1].damage == 0, "an extra arrow can miss")
	eq(ra.hp + rb.hp, hpA + hpB - mixed.extra[2].damage, "only the landed extra hit removes health")
	-- An extra kill reports through the bridge and pays XP.
	local mk, rk = thorn("weak", Vector3.new(4, 1, 0))
	rk.hp = 1
	local kills = w.count("kill", archer)
	local killer = shoot()
	local killed
	for _, h in ipairs(killer.extra) do if h.record == rk then killed = h end end
	ok(killed and killed.killed, "an extra arrow can kill")
	eq(w.count("kill", archer) - kills, 1, "the extra kill is credited")
	eq(L.resolve(mk), nil, "the killed extra is gone")
	local paidRanged = 0
	for _, c in ipairs(w.calls) do if c.op == "combatXp" and c.payload.monster == "Thornling" and c.payload.damage == 1 then paidRanged += 1 end end
	eq(paidRanged, 1, "XP for the hp actually removed")
	eq(#L.multishotTargets(archer, rp, Vector3.new(30, 1, 0), 40, 5), C.MULTISHOT_MAX - 1, "target search capped at MULTISHOT_MAX - 1")
	print("PASS: " .. (checks - before) .. " multishot assertions.")
end
print("PASS: " .. (checks - masteryBefore) .. " mastery combat perk assertions in total.")

print("Combat QA: " .. checks .. " checks passed.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-combat.luau")

-- Creature visuals (docs/DEPTH-CONTRACT.md §48): forged creature rigs, tiers,
-- animation timings and budgets. Run from the project root:
--   lune run verify-creatures.luau
-- 1. Coverage: every monster, sea creature, slayer boss, superior, lair boss and
--    add, raid encounter and add, world boss, Siege creature, Observatory
--    guardian / wisp and pet form maps to an authored rig (never the slime
--    fallback, never primitives).
-- 2. Scale vs hitbox: rig hip / hitbox equal combat.server.lua's blueprint,
--    feet on the ground, the assembled rest pose fills the click box.
-- 3. Tiers: overlays and size escalate critter -> world; eyes and rings.
-- 4. Timings: windups fill [TelegraphAt - windup, TelegraphAt) for every
--    telegraph in the data, the slam starts at resolve, bites match the
--    server lunge; reduced motion.
-- 5. Budgets: per-rig triangles and templates, scene caps against the
--    MeshForge, catalog download, LOD.
-- 6. MeshForge creature API (mocked AssetService): templates, exact tints,
--    the creature sub-cap with LRU eviction, release accounting, phones.
-- 7. creatures.client.lua against stub instances: build / LOD / release,
--    primitives hidden locally and restored, one BulkMoveTo per frame with no
--    instance churn, telegraph / lunge / flinch / death, caps, phones.
-- 8. Source rules: server authority, no per-frame tables, attributes set.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local checks = 0
local function ok(cond, case) if not cond then error("FAILED: " .. case, 2) end checks += 1 end
local function eq(a, b, case) if a ~= b then error("FAILED: " .. case .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end checks += 1 end
local function near(a, b, eps, case) if math.abs(a - b) > eps then error("FAILED: " .. case .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end checks += 1 end
local function has(s, word) return type(s) == "string" and string.find(s, word, 1, true) ~= nil end
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end

local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local Combat
load("combat.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, __CombatTestHarness = function(exports) Combat = exports end})
assert(Combat, "combat harness")
local Cat = load("art/CreatureCatalog.lua")
local R = load("shared/CreatureRules.lua", {CFrame = CFrame, Vector3 = Vector3})
local World = load("art/WorldCatalog.lua")
local combatSource = fs.readFile("combat.server.lua")
local clientSource = fs.readFile("creatures.client.lua")
local forgeSource = fs.readFile("forge.client.lua")

------------------------------------------------------------------------------
-- 1. Coverage
------------------------------------------------------------------------------
local OVERLAYS = {"OverlayPauldron", "OverlayHorns", "OverlayCrown", "OverlayWorldCrown", "OverlayRuneRing"}
for kind, rig in pairs(Cat.rigs) do
	local core = Cat.shapes[rig.core]
	ok(core and (core.kind == "creature" or core.kind == "pet"), kind .. " core is an authored creature mesh")
	for _, seg in ipairs(rig.segs) do
		local data = Cat.shapes[seg.shape]
		ok(data and data.kind == "limb", kind .. " segment " .. tostring(seg.shape) .. " is an authored limb")
		ok(type(seg.at) == "table" and #seg.at == 3, kind .. " segment pivot")
		ok(seg.mirror == nil or R.MIRROR[seg.mirror] ~= nil, kind .. " mirror mode")
		ok(type(seg.role) == "string", kind .. " segment role")
	end
	for _, g in ipairs(rig.glow or {}) do
		ok(#g.at == 3 and g.r > 0 and #g.color == 6, kind .. " glow accent")
	end
	ok(R.GAIT[rig.gait] ~= nil, kind .. " gait " .. tostring(rig.gait))
end
for _, name in ipairs(OVERLAYS) do ok(Cat.shapes[name] and Cat.shapes[name].kind == "overlay", name .. " overlay authored") end
for overlay, shape in pairs(R.OVERLAY_SHAPES) do ok(Cat.shapes[shape] ~= nil, overlay .. " overlay shape exists") end
-- Every combat body resolves to its own rig (the slime is only for unknown ids).
local covered = {}
local function cover(label, kind, color, boss)
	ok(type(kind) == "string", label .. " names a body")
	local plan = Combat.blueprint(kind, color or "AAAAAA", boss)
	ok(plan.kind ~= "blob", label .. " (" .. kind .. ") has an authored rig, not the fallback")
	ok(Cat.rigs[plan.kind] ~= nil, label .. " rig " .. tostring(plan.kind) .. " in the catalog")
	covered[plan.kind] = true
	return plan
end
local monsters = 0
for id, def in pairs(Data.Monsters) do
	monsters += 1
	cover("monster " .. id, Combat.BODY_KIND[id] or def.body, def.color, false)
end
for id, def in pairs(Data.SeaCreatures) do cover("sea creature " .. id, def.body, def.color, false) end
for line, body in pairs(Combat.BOSS_BODY) do cover("slayer boss " .. line, body.kind, "AAAAAA", true) end
for id, def in pairs(Data.WorldBosses) do cover("world boss " .. id, def.body, def.color, "world") end
for id, def in pairs(Data.Lairs.Bosses) do cover("lair boss " .. id, def.body, def.color, true) end
for id, def in pairs(Data.Lairs.Adds) do cover("lair add " .. id, def.body, def.color, false) end
for id, def in pairs(Data.Raids.Encounters) do cover("raid encounter " .. id, def.body, def.color, true) end
for id, def in pairs(Data.Raids.Adds) do cover("raid add " .. id, def.body, def.color, false) end
for id, def in pairs(Data.SlayerTasks.Superiors or {}) do cover("superior " .. id, Combat.BODY_KIND[def.base], def.color, true) end
ok(monsters >= 20, "the bestiary is non-trivial (" .. monsters .. " monsters)")
eq(Combat.blueprint("no-such-body", "AAAAAA", false).kind, "blob", "unknown bodies fall back to the slime rig")
-- Every authored combat rig is reachable by some creature.
for kind in pairs(Cat.rigs) do
	if not string.find(kind, "^pet_") and kind ~= "blob" then ok(covered[kind], kind .. " rig is used by a creature") end
end
-- Skybreach Siege creatures (minigames.server.lua CREATURE_RIGS).
local siegeSource = fs.readFile("minigames.server.lua")
for _, c in ipairs(Data.Minigames.Siege.Creatures) do
	local rig, scale = string.match(siegeSource, c.id .. ' = {"(%a+)", ([%d%.]+)}')
	ok(rig and Cat.rigs[rig] ~= nil, "Siege " .. c.id .. " maps to a rig")
	local h = Cat.rigs[rig].hitbox
	local s = tonumber(scale)
	ok(s and math.max(h[1], h[2], h[3]) * s <= 3 * 1.2 and math.max(h[1], h[2], h[3]) * s >= 3 * 0.75, "Siege " .. c.id .. " fills its 3-stud host")
end
ok(has(siegeSource, 'AddTag(part, "IsleCreature")') and has(siegeSource, 'SetAttribute("CreatureRig", rig[1])'), "Siege hosts are tagged creature hosts")
-- Hollow Observatory: Sentinels and umbral wisps.
local expSource = fs.readFile("expedition.server.lua")
ok(has(expSource, 'creatureHost(guardian, "sentinel"') and has(expSource, 'creatureHost(part, "wisp"'), "Observatory guardians and wisps are forged rigs")
ok(not has(expSource, 'artwork(guardian,"ObservatorySentinel"'), "the legacy sentinel sculpture is retired")
ok(has(expSource, 'CollectionService:AddTag(part, "IsleCreature")'), "dungeon hosts are tagged")
-- Pets: every look form has a rig; the pet client tags its follower.
for species, look in pairs(Data.PetDepth.Looks) do
	ok(Cat.rigs["pet_" .. look.form] ~= nil, "pet " .. species .. " (" .. look.form .. ") has a forged rig")
	eq(R.PET_RIGS[look.form], "pet_" .. look.form, "pet form " .. look.form .. " in the rules")
end
local petSource = fs.readFile("pets.client.lua")
ok(has(petSource, 'SetAttribute("CreatureRig", "pet_" .. tostring(plan.form))') and has(petSource, 'AddTag(model, "IsleCreature")'), "pets.client tags its follower for the renderer")
print("PASS: coverage (" .. checks .. ")")

------------------------------------------------------------------------------
-- 2. Scale vs hitbox
------------------------------------------------------------------------------
local part2 = checks
local function kvec(k) if type(k) == "table" then return Vector3.new(k[1], k[2], k[3]) end local n = k or 1 return Vector3.new(n, n, n) end
local function meshBounds(name)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, v in ipairs(Cat.shapes[name].vertices) do local p = Vector3.new(v[1], v[2], v[3]); lo, hi = lo:Min(p), hi:Max(p) end
	return lo, hi
end
local function restBounds(rig, skipOrbit)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local function add(shape, cf, k)
		for _, v in ipairs(Cat.shapes[shape].vertices) do
			local p = cf * (Vector3.new(v[1], v[2], v[3]) * k)
			lo, hi = lo:Min(p), hi:Max(p)
		end
	end
	add(rig.core, CFrame.new(), Vector3.one)
	for _, seg in ipairs(rig.segs) do
		if not (skipOrbit and seg.role == "orbit") then add(seg.shape, R.rest(seg), kvec(seg.k)) end
	end
	return lo, hi
end
local GROUND = {quad = true, biped = true, hex = true, octo = true, roots = true, hop = true, slither = true}
for kind, rig in pairs(Cat.rigs) do
	local pet = string.find(kind, "^pet_") ~= nil
	if not pet then
		local plan = Combat.blueprint(kind, "AAAAAA", false)
		near(rig.hip, plan.hip, 1e-6, kind .. " hip equals the combat blueprint")
		ok(near ~= nil and math.abs(rig.hitbox[1] - plan.hitbox.X) < 1e-6 and math.abs(rig.hitbox[2] - plan.hitbox.Y) < 1e-6 and math.abs(rig.hitbox[3] - plan.hitbox.Z) < 1e-6,
			kind .. " hitbox equals the combat blueprint")
		eq(R.FLYING[rig.gait] == true, plan.flying == true, kind .. " flies exactly when the server hovers it")
	end
	local lo, hi = restBounds(rig, true)
	local size = hi - lo
	local h = rig.hitbox
	local limit = if R.FLYING[rig.gait] or pet then 2.2 else 1.6
	for axis, i in pairs({X = 1, Y = 2, Z = 3}) do
		local ratio = size[axis] / h[i]
		ok(ratio >= 0.5 and ratio <= limit, string.format("%s rest pose %s %.2f fits its %.1f hitbox side (ratio %.2f)", kind, axis, size[axis], h[i], ratio))
	end
	local mid = (lo + hi) / 2
	ok(math.abs(mid.X) <= 0.2 * h[1], kind .. " is centred across the root")
	if GROUND[rig.gait] then
		ok(math.abs(lo.Y + rig.hip) <= math.max(0.12, 0.25 * rig.hip), string.format("%s stands on the ground (feet %.2f, ground %.2f)", kind, lo.Y, -rig.hip))
	else
		ok(lo.Y > -rig.hip, kind .. " hovers above the ground")
	end
	-- Orbiting shards circle within reach of the body.
	for _, seg in ipairs(rig.segs) do
		if seg.role == "orbit" then
			local r = math.sqrt(seg.at[1] ^ 2 + seg.at[3] ^ 2)
			ok(r <= 0.75 * math.max(h[1], h[2], h[3]) and r >= 0.4, kind .. " orbit radius " .. r)
		end
	end
	-- Anchors sit on the body: crowns above the core's top half, rings at the feet radius.
	local a = rig.anchors or {}
	if a.crown then ok(a.crown[2] >= 0.2 * (hi.Y - lo.Y) + lo.Y and a.crown[2] <= hi.Y + 0.5, kind .. " crown anchor on the head") end
	if a.ring then ok(a.ring >= 0.25 * math.max(h[1], h[3]) and a.ring <= 0.8 * math.max(h[1], h[3]) + 0.5, kind .. " rune ring radius") end
end
-- Bosses scale uniformly (CreatureScale = blueprint scale), so a world boss towers.
for _, kind in ipairs({"golem", "drake", "sovereign"}) do
	near(Combat.blueprint(kind, "AAAAAA", false).scale, 1, 1e-9, kind .. " scale 1")
	near(Combat.blueprint(kind, "AAAAAA", true).scale, 2.2, 1e-9, kind .. " boss scale 2.2")
	near(Combat.blueprint(kind, "AAAAAA", "world").scale, 3.2, 1e-9, kind .. " world scale 3.2")
end
ok(has(combatSource, 'model:SetAttribute("CreatureRig", plan.kind)') and has(combatSource, 'model:SetAttribute("CreatureScale", plan.scale)'), "combat models publish their rig and scale")
-- Sentinel hosts: scaled to stand in their 8-stud box.
local sentinel = Cat.rigs.sentinel
ok(sentinel.hitbox[2] * 0.92 <= 8 * 1.05, "Observatory Sentinel fits its 8-stud host at 0.92")
-- Host parts: ground rigs stand on the host floor, fliers centre on it.
near(R.hostLift(Cat.rigs.mite, 1.5, 0.7), -1.5 + 1.3 * 0.7, 1e-9, "a ground rig's feet sit on the host bottom")
near(R.hostLift(Cat.rigs.sentinel, 4, 0.92, -3.5), -3.5 + 4.2 * 0.92, 1e-9, "CreatureFloor moves the feet to the floor")
eq(R.hostLift(Cat.rigs.wisp, 1.5, 0.88), 0, "a floating rig centres on its host")
print("PASS: scale vs hitbox (" .. (checks - part2) .. ")")

------------------------------------------------------------------------------
-- 3. Tiers
------------------------------------------------------------------------------
local part3 = checks
eq(R.tier({Level = 3}), "critter", "a level 3 boar is a critter")
eq(R.tier({Level = R.BRUTE_LEVEL}), "brute", "brute at level 25")
eq(R.tier({Level = R.ELITE_LEVEL}), "elite", "elite at level 60")
eq(R.tier({Level = 5, Superior = true}), "elite", "superiors are elite at least")
eq(R.tier({Level = 5, Boss = true}), "boss", "slayer bosses")
eq(R.tier({Level = 30, Lair = "fight-1"}), "boss", "lair / raid bosses (Lair attribute)")
eq(R.tier({Level = 30, Lair = ""}), "brute", "an empty Lair attribute is not a boss")
eq(R.tier({Level = 99, WorldBoss = true, Boss = true}), "world", "world bosses outrank everything")
eq(R.tier({Pet = true, Level = 99}), "pet", "pets")
eq(R.tier({CreatureTier = "elite", Level = 1}), "elite", "explicit tier (Observatory Sentinels)")
eq(R.tier(nil), "critter", "no attributes")
local previous = -1
for _, tier in ipairs({"critter", "brute", "elite", "boss", "world"}) do
	local n = #R.overlays(tier, false)
	ok(n >= previous, tier .. " carries at least as many overlays as the tier below")
	previous = n
	ok(#R.overlays(tier, true) <= n, tier .. " phones carry no more overlays than desktop")
	for _, o in ipairs(R.overlays(tier, true)) do ok(table.find(R.overlays(tier, false), o) ~= nil, tier .. " phone overlay " .. o .. " is a desktop overlay") end
end
eq(#R.overlays("critter", false), 0, "critters stay bare")
ok(table.find(R.overlays("boss", false), "crown") and table.find(R.overlays("boss", false), "ring"), "bosses: crown and rune ring")
ok(table.find(R.overlays("world", false), "worldcrown") and table.find(R.overlays("world", true), "worldcrown"), "world bosses keep their crown on phones")
ok(R.EYE_OVERRIDE.boss ~= R.EYE_OVERRIDE.world and R.EYE_OVERRIDE.critter == nil, "boss and world eyes differ; critters keep theirs")
ok(R.TIER_RANGE.world > R.TIER_RANGE.boss and R.TIER_RANGE.boss > R.TIER_RANGE.critter, "bigger tiers are drawn from further away")
for stance in pairs({melee = 1, ranged = 1, magic = 1}) do ok(#R.STANCE_COLOR[stance] == 6, stance .. " stance ring colour") end
-- Every critter vs world boss of the same body differs in size by >= 3x.
ok(Combat.blueprint("drake", "AAAAAA", "world").scale / Combat.blueprint("boar", "AAAAAA", false).scale >= 3, "world bosses read instantly by size")
print("PASS: tiers (" .. (checks - part3) .. ")")

------------------------------------------------------------------------------
-- 4. Timings
------------------------------------------------------------------------------
local part4 = checks
local lunge = tonumber(string.match(combatSource, "r%.lungeUntil = env%.now%(%) %+ ([%d%.]+)"))
eq(lunge, R.TIMING.LUNGE, "the client's bite window equals the server lunge")
eq(tonumber(string.match(combatSource, "r%.lungeUntil = now %+ ([%d%.]+)")), R.TIMING.LUNGE, "lair / raid lunges too")
ok(has(combatSource, 'v.model:SetAttribute("TelegraphAt", Workspace:GetServerTimeNow() + tg.windup)'), "the server stamps TelegraphAt = now + windup")
ok(has(combatSource, 'v.model:SetAttribute("AttackAt", Workspace:GetServerTimeNow())'), "the server stamps AttackAt when a hit lands")
local _, wbCount = string.gsub(combatSource, "\n%s+markTelegraph%(r, tg%)", "")
eq(wbCount, 2, "world boss and lair / raid telegraphs both stamp the model")
local windups = {}
local function collect(label, attacks)
	for id, a in pairs(attacks or {}) do
		if type(a) == "table" and type(a.windup) == "number" then table.insert(windups, {label .. "." .. id, a.windup}) end
	end
end
for id, def in pairs(Data.WorldBosses) do collect(id, def.attacks) end
for id, def in pairs(Data.Lairs.Bosses) do collect(id, def.attacks) end
for id, def in pairs(Data.Raids.Encounters) do collect(id, def.attacks) end
ok(#windups >= 20, "telegraphs found (" .. #windups .. ")")
local rig = Cat.rigs.golem
local function poseAt(state) return R.pose(rig, state, {seg = {}}) end
local function pitchOf(cf) local x = cf:ToEulerAnglesXYZ() return x end
for _, item in ipairs(windups) do
	local label, windup = item[1], item[2]
	ok(windup >= R.TIMING.MIN_WINDUP, label .. " windup " .. windup .. " is long enough to read")
	local at = 1000
	local start = at - windup
	eq(R.telegraphPhase(start - 1 / 60, at, windup), nil, label .. ": no windup before the telegraph")
	local phase, p = R.telegraphPhase(start, at, windup)
	eq(phase, "windup", label .. ": windup starts with the telegraph")
	near(p, 0, 1e-9, label .. ": windup from 0")
	phase, p = R.telegraphPhase(at - 1 / 60, at, windup)
	eq(phase, "windup", label .. ": still winding up a frame before resolve")
	ok(p >= 1 - (1 / 60) / windup - 1e-9, label .. ": fully wound up at resolve")
	phase, p = R.telegraphPhase(at, at, windup)
	eq(phase, "strike", label .. ": the slam starts exactly when the server resolves")
	near(p, 0, 1e-9, label .. ": slam from 0")
	eq(R.telegraphPhase(at + R.TIMING.STRIKE, at, windup), nil, label .. ": the slam ends after STRIKE")
end
-- Pose shape: rearing back during the windup, arms raised; slam forward at the pulse peak.
local rest = poseAt({t = 0})
local wound = poseAt({t = 0, windup = 1})
local slam = poseAt({t = 0, strike = R.pulse(1 / 3)})
ok(pitchOf(wound.core) < pitchOf(rest.core) - 0.25, "a wound-up boss rears back")
ok(pitchOf(slam.core) > pitchOf(rest.core) + 0.2, "the slam pitches forward")
local armIndex
for i, seg in ipairs(rig.segs) do if seg.role == "armA" then armIndex = i end end
ok(wound.seg[armIndex].UpVector.Y < rest.seg[armIndex].UpVector.Y - 0.5, "arms are raised overhead during the windup")
near(R.pulse(1 / 3), 1, 1e-9, "the strike pulse peaks a third of the way in")
eq(R.pulse(0), 0, "pulse starts at 0")
eq(R.pulse(1), 0, "pulse settles by the end")
for p = 0, 1, 0.05 do ok(R.pulse(p) >= 0 and R.pulse(p) <= 1, "pulse bounded") end
-- Lunge (ordinary monster hits) over exactly the server's window.
eq(R.lungePhase(999.99, 1000), nil, "no bite before AttackAt")
eq((R.lungePhase(1000, 1000)), "strike", "bite at AttackAt")
eq((R.lungePhase(1000 + R.TIMING.LUNGE - 0.001, 1000)), "strike", "bite through the lunge")
eq(R.lungePhase(1000 + R.TIMING.LUNGE, 1000), nil, "bite over when the lunge ends")
-- Walk cycle: legs swing in opposition and only while moving; arms counter-swing.
local boar = Cat.rigs.boar
local stand = R.pose(boar, {t = 2, gait = math.pi / 2, speed = 0}, {seg = {}})
local walk = R.pose(boar, {t = 2, gait = math.pi / 2, speed = 1}, {seg = {}})
local function legPitch(out, i) return pitchOf(out.seg[i]) end
near(legPitch(stand, 1), legPitch(stand, 2), 1e-6, "standing legs rest together")
ok(legPitch(walk, 1) * legPitch(walk, 2) < 0, "walking legs A / B swing in opposition")
ok(math.abs(legPitch(walk, 1)) > 0.4, "the swing is visible at full speed")
-- Legs stay planted when the boss rears (they follow the core's height only).
local rear = R.pose(boar, {t = 2, windup = 1}, {seg = {}})
ok(math.abs(rear.seg[1].Position.Z - boar.segs[1].at[3]) < 1e-6, "legs do not slide with the rear-back")
-- Arthropods sweep their legs (yaw) and lift on the return.
local crab = Cat.rigs.crab
local crabWalk = R.pose(crab, {t = 0, gait = 0.3, speed = 1}, {seg = {}})
local crabStand = R.pose(crab, {t = 0, gait = 0.3, speed = 0}, {seg = {}})
ok((crabWalk.seg[1].LookVector - crabStand.seg[1].LookVector).Magnitude > 0.1, "crab legs sweep while walking")
-- Wings flap in mirror image.
local drake = Cat.rigs.drake
local flap = R.pose(drake, {t = 0.3}, {seg = {}})
-- The span (mesh +X) of the right wing points +X, the mirrored left wing's -X,
-- and both tips rise and fall together.
ok(flap.seg[1].RightVector.X > 0 and flap.seg[2].RightVector.X < 0, "each wing spans its own side")
near(flap.seg[1].RightVector.Y, flap.seg[2].RightVector.Y, 0.15, "wings flap in mirror image")
local flap2 = R.pose(drake, {t = 0.3 + math.pi / (drake.flap or 4)}, {seg = {}})
ok(math.abs(flap2.seg[1].RightVector.Y - flap.seg[1].RightVector.Y) > 0.2, "wings beat over time")
-- Flinch kicks the core back; death slumps and sinks.
local flinch = R.pose(boar, {t = 0, flinch = 1}, {seg = {}})
ok(pitchOf(flinch.core) < pitchOf(R.pose(boar, {t = 0}, {seg = {}}).core) and flinch.core.Position.Z > 0, "flinch recoils")
local dead = R.pose(boar, {t = 0, death = 1}, {seg = {}})
ok(dead.core.Position.Y < -0.4 * boar.hip, "death sinks the body")
eq(R.dissolve(0, false), 0, "dissolve starts opaque")
eq(R.dissolve(1, false), 1, "dissolve ends invisible")
ok(R.TIMING.DISSOLVE_REDUCED < R.TIMING.DISSOLVE, "reduced motion dissolves faster")
-- Reduced motion: idle breathing and orbits stop, telegraphs still read.
local function coreY(t, reduced) return R.pose(Cat.rigs.wisp, {t = t, reduced = reduced}, {seg = {}}).core.Position.Y end
ok(coreY(0.3, false) ~= coreY(1.1, false), "idle breathing moves the core")
eq(coreY(0.3, true), coreY(1.1, true), "reduced motion: no idle breathing")
local o1 = R.pose(Cat.rigs.wisp, {t = 0.3, reduced = true}, {seg = {}}).seg[1].Position
local o2 = R.pose(Cat.rigs.wisp, {t = 2.3, reduced = true}, {seg = {}}).seg[1].Position
ok((o1 - o2).Magnitude < 1e-6, "reduced motion: orbiting shards hold still")
ok(pitchOf(R.pose(rig, {t = 0, windup = 1, reduced = true}, {seg = {}}).core) < -0.25, "reduced motion keeps the telegraph windup")
-- The pose is deterministic and reuses its output table.
local out = {seg = {}}
local first = R.pose(boar, {t = 1, gait = 1, speed = 0.5}, out)
ok(first == out and first.seg == out.seg, "pose writes into the caller's table")
print("PASS: timings (" .. (checks - part4) .. ")")

------------------------------------------------------------------------------
-- 5. Budgets and LOD
------------------------------------------------------------------------------
local part5 = checks
local function tris(name) return #Cat.shapes[name].faces end
local worst = {desktop = 0, phone = 0}
for kind, rigDef in pairs(Cat.rigs) do
	local base = tris(rigDef.core)
	local shapes = {[rigDef.core] = true}
	for _, seg in ipairs(rigDef.segs) do base += tris(seg.shape); shapes[seg.shape] = true end
	ok(base <= 5000, kind .. " rig " .. base .. " triangles <= 5000")
	ok(#rigDef.segs <= 10, kind .. " at most 10 limb segments")
	for _, tier in ipairs({"critter", "brute", "elite", "boss", "world"}) do
		for _, mobile in ipairs({false, true}) do
			local total, templates = base, 0
			local set = table.clone(shapes)
			for _, o in ipairs(R.overlays(tier, mobile)) do
				total += tris(R.OVERLAY_SHAPES[o]) * (if o == "pauldron" then 2 else 1)
				set[R.OVERLAY_SHAPES[o]] = true
			end
			for _ in pairs(set) do templates += 1 end
			ok(total <= 9000, kind .. " " .. tier .. " full rig " .. total .. " triangles <= 9000")
			ok(templates <= 8, kind .. " " .. tier .. " needs " .. templates .. " templates (<= 8)")
			ok(templates <= R.TEMPLATE_CAP.phone, kind .. " fits the phone creature template cap")
			local device = if mobile then "phone" else "desktop"
			if tier ~= "world" and total > worst[device] then worst[device] = total end
		end
	end
end
-- A full scene of capped rigs stays well inside the forge's placed-triangle budget.
local desktopLimit = tonumber(string.match(forgeSource, "placedTriangles = (%d+), %-%- triangles across all placed clones"))
local phoneLimit = tonumber(string.match(forgeSource, "templates = 24, templateTriangles = %d+, instances = %d+, placedTriangles = (%d+)"))
ok(desktopLimit and phoneLimit, "forge limits found")
ok(worst.desktop * R.cap(false) <= desktopLimit * 0.5, "desktop: " .. R.cap(false) .. " worst rigs use <= half the forge budget")
ok(worst.phone * R.cap(true) <= phoneLimit * 0.6, "phones: " .. R.cap(true) .. " worst rigs use <= 60% of the forge budget")
ok(R.cap(true) < R.cap(false), "phones draw fewer rigs")
ok(R.TEMPLATE_CAP.phone < R.TEMPLATE_CAP.desktop, "phones keep fewer creature templates")
eq(tonumber(string.match(forgeSource, "local CREATURE_TEMPLATE_CAP = if mobile then (%d+)")), R.TEMPLATE_CAP.phone, "forge phone creature cap matches the rules")
eq(tonumber(string.match(forgeSource, "local CREATURE_TEMPLATE_CAP = if mobile then %d+ else (%d+)")), R.TEMPLATE_CAP.desktop, "forge desktop creature cap matches the rules")
ok(R.TEMPLATE_CAP.desktop <= 72 / 3 and R.TEMPLATE_CAP.phone <= 24 / 3, "the creature template pool is at most a third of the world's")
-- LOD: monotonic in distance, longer for bosses, shorter on phones, hysteresis.
for _, tier in ipairs({"critter", "boss", "world"}) do
	for _, mobile in ipairs({false, true}) do
		local last = 3
		for d = 0, 800, 5 do
			local lod = R.lod(d, tier, mobile, false)
			ok(lod <= last, tier .. " LOD never rises with distance")
			last = lod
		end
		eq(R.lod(1, tier, mobile, false), 3, tier .. " full detail up close")
		eq(R.lod(5000, tier, mobile, false), 0, tier .. " nothing far away")
	end
end
ok(R.lod(R.LOD.desktop.core * 1.5, "world", false, false) > 0 and R.lod(R.LOD.desktop.core * 1.5, "critter", false, false) == 0, "world bosses are drawn further than critters")
ok(R.lod(R.LOD.phone.full + 5, "critter", true, false) < R.lod(R.LOD.phone.full + 5, "critter", false, false), "phones step down sooner")
local edge = R.LOD.desktop.core + 10
ok(R.lod(edge, "critter", false, true) > 0 and R.lod(edge, "critter", false, false) == 0, "an existing rig is kept a little past the build range")
ok(R.LIMB_HZ > R.CORE_HZ and R.CORE_HZ >= 4, "LOD animation rates")
-- Catalog download and authoring.
local bytes = #fs.readFile("art/CreatureCatalog.lua")
ok(bytes <= 640 * 1024, "creature catalog download " .. bytes .. " bytes <= 640 KB")
local shapes, total = 0, 0
for name, data in pairs(Cat.shapes) do
	shapes += 1
	total += #data.faces
	ok(World.shapes[name] == nil, name .. " is unique across catalogs")
	ok(type(data.smooth) == "number" and (data.smooth >= 18 or data.kind == "overlay"), name .. " is smooth-shaded (crease " .. data.smooth .. ")")
end
ok(shapes >= 60, "creature shapes authored (" .. shapes .. ")")
local rigCount = 0
for _ in pairs(Cat.rigs) do rigCount += 1 end
ok(rigCount >= 33, "rigs authored (" .. rigCount .. ")")
print("PASS: budgets and LOD (" .. (checks - part5) .. ")")

------------------------------------------------------------------------------
-- 6. MeshForge creature API (mocked AssetService)
------------------------------------------------------------------------------
local part6 = checks
local Props = load("art/PropCatalog.lua")
local function forgeHarness(mobile)
	local calls = {meshes = 0, parts = 0, destroyed = 0}
	local asset = {}
	function asset.CreateEditableMesh()
		calls.meshes += 1
		local mesh = {n = 0}
		function mesh.AddVertex(self) self.n += 1; return self.n end
		function mesh.AddColor() return 1 end
		function mesh.AddTriangle() return 1 end
		function mesh.SetFaceColors() end
		function mesh.AddNormal() return 1 end
		function mesh.SetFaceNormals() end
		function mesh.Destroy() calls.destroyed += 1 end
		return mesh
	end
	function asset.CreateMeshPartAsync() calls.parts += 1; return roblox.Instance.new("MeshPart") end
	local tokens = {AetherWorldArt = "world", AetherArt = "props", AetherCreatureArt = "creature"}
	local services = {
		AssetService = asset,
		ReplicatedStorage = {WaitForChild = function(_, name) return tokens[name] end},
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return {CFrame = CFrame.new()} end}}},
		UserInputService = {TouchEnabled = mobile, KeyboardEnabled = not mobile},
	}
	local test = {}
	load("forge.client.lua", {
		game = {GetService = function(_, name) return services[name] end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		require = function(token) return if token == "world" then World elseif token == "props" then Props elseif token == "creature" then Cat else error("module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else f(...) end end, defer = function() end, wait = function() end},
		warn = function() end, print = function() end,
	})
	return test.forge, calls
end
do
	local forge, calls = forgeHarness(false)
	local api = forge.creature
	ok(api and api.visual and api.release, "the forge exposes the creature API")
	local tint = Color3.fromHex("A0683D")
	local clone, token, extent, center = api.visual("CreatureBoar", tint)
	ok(clone and clone:IsA("MeshPart") and type(token) == "number", "a creature clone and token")
	local lo, hi = meshBounds("CreatureBoar")
	ok((extent - (hi - lo)).Magnitude < 1e-3 and (center - (lo + hi) / 2).Magnitude < 1e-3, "extent and centre describe the authored mesh")
	eq(forge.stats.templates, 1, "one template")
	eq(forge.stats.instances, 1, "one placed clone")
	eq(forge.stats.placedTriangles, tris("CreatureBoar"), "clone triangles counted")
	local clone2, token2 = api.visual("CreatureBoar", tint)
	ok(clone2 and token2 ~= token, "a second clone")
	eq(calls.meshes, 1, "the same shape and colour reuse the template")
	local _, token3 = api.visual("CreatureBoar", Color3.fromHex("33AA55"))
	eq(forge.stats.templates, 2, "desktop keeps a template per exact creature colour")
	eq(api.count(), 2, "both are creature templates")
	ok(api.release(token) and api.release(token2) and api.release(token3), "release")
	ok(not api.release(token), "a token releases once")
	eq(forge.stats.instances, 0, "instances returned")
	eq(forge.stats.placedTriangles, 0, "triangles returned")
	eq(api.visual("Boulder", tint), nil, "world props are not served as creatures")
	eq(api.visual("NoSuchShape", tint), nil, "unknown shapes refused")
	-- The creature sub-cap: idle creature templates give way (LRU), busy ones never.
	local held = {}
	for i = 1, api.cap do
		local _, t = api.visual("HoofLeg", Color3.fromRGB(i * 7 % 255, 40, 90))
		ok(t ~= nil, "template " .. i .. " within the cap")
		table.insert(held, t)
	end
	ok(api.count() <= api.cap, "creature templates within the cap")
	local before = forge.stats.evicted
	eq(api.visual("PawLeg", Color3.fromRGB(1, 2, 3)), nil, "busy creature templates are never evicted: a new shape waits")
	eq(forge.stats.evicted, before, "nothing evicted while every template is in use")
	api.release(table.remove(held, 1))
	local _, extra = api.visual("PawLeg", Color3.fromRGB(1, 2, 3))
	ok(extra ~= nil and forge.stats.evicted == before + 1, "the least recently used idle creature template gives way")
	for _, t in ipairs(held) do api.release(t) end
	api.release(extra)
	ok(api.count() <= api.cap, "still within the cap")
	-- Separate pools: a full world pool does not starve creatures, and creature
	-- templates never count against the world's LIMITS.
	local stats = forge.stats
	local worldBefore = stats.templates
	stats.templates += forge.limits.templates
	stats.templateTriangles += forge.limits.templateTriangles
	local _, t = api.visual("CreatureSpider", Color3.fromHex("4B3F72"))
	ok(t ~= nil, "creatures still forge while the world pool is full")
	ok(stats.creatureTemplates >= 1 and stats.creatureTriangles >= tris("CreatureSpider"), "creature pool counted on its own")
	stats.templates -= forge.limits.templates
	stats.templateTriangles -= forge.limits.templateTriangles
	ok(stats.templates - stats.creatureTemplates <= worldBefore, "the world pool holds no creature templates")
	ok(stats.creatureTriangles <= api.triangleCap, "creature template triangles within their cap")
	api.release(t)
	-- World Shape tags never forge creature meshes.
	local p = roblox.Instance.new("Part")
	p:SetAttribute("Shape", "CreatureBoar")
	ok(forge.describe(p) ~= nil, "describe still resolves the creature catalog")
end
do
	local forge, calls = forgeHarness(true)
	local api = forge.creature
	eq(api.cap, R.TEMPLATE_CAP.phone, "phones: the smaller creature cap")
	local _, a = api.visual("CreatureMite", Color3.fromHex("B5543A"))
	local _, b = api.visual("CreatureMite", Color3.fromHex("22CC88"))
	ok(a and b, "phones serve both colours")
	eq(calls.meshes, 1, "phones share one variant per creature shape")
end
print("PASS: forge creature API (" .. (checks - part6) .. ")")

------------------------------------------------------------------------------
-- 7. creatures.client.lua against stub instances
------------------------------------------------------------------------------
local part7 = checks
local rawTypeof = typeof
local function signal()
	local s = {fns = {}}
	function s:Connect(fn)
		table.insert(self.fns, fn)
		local conn = {}
		function conn.Disconnect() for i, f in ipairs(s.fns) do if f == fn then table.remove(s.fns, i) break end end end
		return conn
	end
	function s:Fire(...) for _, fn in ipairs(table.clone(self.fns)) do fn(...) end end
	return s
end
local created = 0
local function stub(class, props)
	created += 1
	local o = {__stub = true, ClassName = class, Transparency = 0, LocalTransparencyModifier = 0, attrs = {}, children = {}, inWorld = true,
		AttributeChanged = signal(), AncestryChanged = signal(), Parent = true}
	for k, v in pairs(props or {}) do o[k] = v end
	function o:IsA(c) return c == class or (c == "BasePart" and (class == "Part" or class == "MeshPart")) end
	function o:GetAttribute(k) return self.attrs[k] end
	function o:SetAttribute(k, v) self.attrs[k] = v; self.AttributeChanged:Fire(k) end
	function o:GetDescendants() return self.children end
	function o:FindFirstChild(n) for _, c in ipairs(self.children) do if c.Name == n then return c end end return nil end
	function o:IsDescendantOf() return self.inWorld end
	function o:Destroy() self.destroyed = true end
	return setmetatable(o, {__index = function(t, k) if k == "Position" then return rawget(t, "CFrame").Position end end})
end
local function runtime(opts)
	opts = opts or {}
	local env = {clock = 0, server = 1000, bulk = 0, bulkParts = 0, tokens = 0, live = {}, refuse = false, reduced = false}
	local api = {}
	function api:Invoke(method, arg)
		if method == "creature" then
			if env.refuse then return nil end
			env.tokens += 1
			env.live[env.tokens] = arg.shape
			local lo, hi = meshBounds(arg.shape)
			return stub("MeshPart", {Name = arg.shape, Size = hi - lo}), env.tokens, hi - lo, (lo + hi) / 2
		elseif method == "creatureRelease" then
			env.live[arg] = nil
			return true
		end
	end
	local modules = {rules = R, art = Cat, theme = {reducedMotion = function() return env.reduced end}}
	local tokensByName = {AetherCreatureRules = "rules", AetherCreatureArt = "art", AetherUiTheme = "theme"}
	local camera = {CFrame = CFrame.new(0, 5, 0)}
	env.camera = camera
	local test = {}
	load("creatures.client.lua", {
		game = {GetService = function(_, name)
			if name == "ReplicatedStorage" then
				return {WaitForChild = function(_, n) return tokensByName[n] end, FindFirstChild = function(_, n) return if n == "MeshForgeLocal" then api else nil end}
			elseif name == "UserInputService" then
				return {TouchEnabled = opts.mobile == true, KeyboardEnabled = opts.mobile ~= true}
			elseif name == "Players" then
				return {LocalPlayer = {}}
			end
			return {}
		end},
		require = function(token) return modules[token] end,
		workspace = {CurrentCamera = camera, GetServerTimeNow = function() return env.server end,
			BulkMoveTo = function(_, parts, frames) assert(#parts == #frames); env.bulk += 1; env.bulkParts = #parts end},
		Instance = {new = function(class) return stub(class) end},
		typeof = function(v) if type(v) == "table" and rawget(v, "__stub") then return "Instance" end return rawTypeof(v) end,
		os = {clock = function() return env.clock end},
		task = {spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end},
		CreatureTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum,
		warn = function(...) error(table.concat({...}, " ")) end,
	})
	env.C = test.creatures
	function env.liveCount() local n = 0 for _ in pairs(env.live) do n += 1 end return n end
	function env.frame(dt) env.clock += dt; env.server += dt; env.C.step(dt) end
	return env
end
local function monster(kind, attrs, position)
	local root = stub("Part", {Name = "Root", CFrame = CFrame.new(position or Vector3.new(0, 2, -20)), Size = Vector3.new(3, 3, 3), Transparency = 1})
	local body = stub("Part", {Name = "Body", CFrame = root.CFrame, Size = Vector3.new(2, 2, 2)})
	local model = stub("Model", {Name = kind, PrimaryPart = root})
	model.children = {root, body}
	model.attrs = {CreatureRig = kind, CreatureScale = 1, Color = "A0683D", Level = 3}
	for k, v in pairs(attrs or {}) do model.attrs[k] = v end
	return model, root, body
end
do
	local env = runtime()
	local C = env.C
	ok(C ~= nil, "the renderer exposes its test hook")
	local model, root, body = monster("golem", {Boss = true, CreatureScale = 2.2, Level = 40})
	C.track(model)
	local rec = C.records[model]
	ok(rec and rec.tier == "boss" and rec.kind == "golem", "a boss golem is tracked")
	C.assign()
	ok(rec.built and rec.full, "near: the full rig is built")
	local expected = R.rigMeshes(Cat.rigs.golem, "boss", false)
	eq(#rec.meshes, expected, "core + limbs + overlays (" .. expected .. ")")
	eq(env.liveCount(), expected, "every mesh came from the forge")
	eq(#rec.glows, #Cat.rigs.golem.glow, "glow accents placed")
	eq(body.LocalTransparencyModifier, 1, "the server primitive is hidden locally")
	eq(root.LocalTransparencyModifier, 0, "the invisible root (click target, name plate) is untouched")
	eq(body.Transparency, 0, "the replicated primitive's own Transparency is never written")
	-- One BulkMoveTo per frame, no instance churn while animating.
	local before = created
	env.frame(1 / 60)
	eq(env.bulk, 1, "one BulkMoveTo per frame")
	eq(env.bulkParts, expected + #Cat.rigs.golem.glow, "every mesh and glow posed in it")
	for _ = 1, 30 do env.frame(1 / 60) end
	eq(created, before, "no instances created while animating")
	eq(env.bulk, 31, "still one BulkMoveTo per frame")
	-- Boss glare: eyes override to the tier colour.
	local eyeGlow
	for _, g in ipairs(rec.glows) do if g.def.kind == "eye" then eyeGlow = g end end
	ok(eyeGlow and eyeGlow.part.Color == Color3.fromHex(R.EYE_OVERRIDE.boss), "boss eyes glare red")
	-- Telegraph window drives the windup then the slam.
	model:SetAttribute("TelegraphWindup", 2)
	model:SetAttribute("TelegraphAt", env.server + 2)
	env.frame(1)
	near(rec.state.windup, 0.5, 0.02, "half wound up halfway through the telegraph")
	eq(rec.state.strike, 0, "no slam during the windup")
	env.frame(1.05)
	ok(rec.state.strike > 0 and rec.state.windup == 0, "the slam follows the resolve")
	env.frame(1)
	eq(rec.state.strike, 0, "back to idle after the slam")
	-- A landed hit (AttackAt) plays the bite over the lunge window.
	model:SetAttribute("AttackAt", env.server)
	env.frame(0.08)
	ok(rec.state.strike > 0, "the bite plays when the server lands a hit")
	env.frame(0.3)
	eq(rec.state.strike, 0, "the bite ends with the lunge")
	-- Health drop flinches.
	model:SetAttribute("Health", 1000)
	model:SetAttribute("Health", 900)
	env.frame(0.01)
	ok(rec.state.flinch > 0.5, "a hit flinches the creature")
	env.frame(0.5)
	eq(rec.state.flinch, 0, "the flinch settles")
	-- Walking: the root moves, the gait advances, the speed rises.
	for i = 1, 20 do root.CFrame = CFrame.new(0, 2, -20 + i * 0.2); env.frame(1 / 20) end
	ok(rec.speed > 0.2 and rec.gait > 0, "moving roots drive the walk cycle")
	for _ = 1, 40 do env.frame(1 / 20) end
	ok(rec.speed < 0.05, "standing still settles the gait")
	-- Smoothing: the visual eases toward stepped server updates, snaps on teleports.
	root.CFrame = CFrame.new(0, 2, -14)
	env.frame(1 / 60)
	ok((rec.visual.Position - root.CFrame.Position).Magnitude > 0.01, "stepped root updates are smoothed")
	root.CFrame = CFrame.new(500, 2, 500)
	env.frame(1 / 60)
	ok((rec.visual.Position - root.CFrame.Position).Magnitude < 1e-6, "teleports snap")
	root.CFrame = CFrame.new(0, 2, -20)
	env.frame(1 / 60)
	-- Far away: released, primitives restored, tokens returned.
	env.camera.CFrame = CFrame.new(0, 5, 5000)
	C.assign()
	ok(not rec.built, "far: released")
	eq(env.liveCount(), 0, "every forge token returned")
	eq(body.LocalTransparencyModifier, 0, "the primitive is visible again")
	-- Mid range: core only, then the full rig again.
	local coreDistance = R.LOD.desktop.limbs * R.TIER_RANGE.boss + 10
	env.camera.CFrame = CFrame.new(0, 2, -20 + coreDistance)
	C.assign()
	ok(rec.built and not rec.full, "beyond the limb range only the core is drawn")
	eq(#rec.meshes, 1, "one mesh at core LOD")
	env.camera.CFrame = CFrame.new(0, 5, 0)
	C.assign()
	ok(rec.full and #rec.meshes == expected, "closer again: the full rig")
	-- Death: the rig dissolves after the server marks it Dead, then releases.
	model:SetAttribute("Dead", true)
	ok(rec.dying, "Dead starts the dissolve")
	eq(body.LocalTransparencyModifier, 1, "the dying primitive stays hidden (the server destroys it next)")
	model.inWorld = false
	model.AncestryChanged:Fire()
	env.frame(R.TIMING.DISSOLVE / 2)
	local mid = rec.meshes[1] and rec.meshes[1].part.Transparency or 1
	ok(mid > 0 and mid < 1, "half dissolved")
	env.frame(R.TIMING.DISSOLVE)
	ok(C.records[model] == nil, "dissolved rigs are forgotten")
	eq(env.liveCount(), 0, "and their meshes returned")
end
do
	-- The forge refuses (budget): the primitives stay, the renderer backs off.
	local env = runtime()
	env.refuse = true
	local model, _, body = monster("boar")
	env.C.track(model)
	env.C.assign()
	local rec = env.C.records[model]
	ok(not rec.built and body.LocalTransparencyModifier == 0, "no mesh: the primitive stays visible")
	env.refuse = false
	env.C.assign()
	ok(not rec.built, "retries back off")
	env.clock += 9
	env.C.assign()
	ok(rec.built, "and succeed later")
end
do
	-- Caps: at most R.cap() rigs, bosses first.
	local env = runtime()
	local models = {}
	for i = 1, 40 do
		local m = monster("mite", nil, Vector3.new(i, 2, -10))
		env.C.track(m)
		table.insert(models, m)
	end
	local boss = monster("drake", {WorldBoss = true, CreatureScale = 3.2}, Vector3.new(0, 2, -200))
	env.C.track(boss)
	env.C.assign()
	local built = 0
	for _, m in ipairs(models) do if env.C.records[m].built then built += 1 end end
	eq(built, R.cap(false) - 1, "the cap holds, the world boss takes a slot first")
	ok(env.C.records[boss].built, "the distant world boss is drawn")
	-- Tier overlays on a world boss.
	local rec = env.C.records[boss]
	local ring
	for _, m in ipairs(rec.meshes) do if m.ring then ring = m end end
	ok(ring ~= nil, "a world boss stands on a rune ring")
	ok(rec.meshes[1].part.Size.X > 3, "world boss meshes are scaled up (CreatureScale 3.2)")
end
do
	-- Phones: smaller cap and fewer overlays.
	local env = runtime({mobile = true})
	ok(env.C.mobile, "phone mode detected")
	local model = monster("golem", {Boss = true, CreatureScale = 2.2})
	env.C.track(model)
	env.C.assign()
	eq(#env.C.records[model].meshes, R.rigMeshes(Cat.rigs.golem, "boss", true), "phones carry the phone overlay set")
	ok(#env.C.records[model].meshes < R.rigMeshes(Cat.rigs.golem, "boss", false), "fewer meshes than desktop")
end
do
	-- Host parts (Observatory Sentinel): feet on CreatureFloor, defeat pose, hits flinch.
	local env = runtime()
	local host = stub("Part", {Name = "Sentinel 1", CFrame = CFrame.new(0, 47, -112), Size = Vector3.new(5, 8, 5)})
	host.attrs = {CreatureRig = "sentinel", CreatureScale = 0.92, Color = "D9B65C", CreatureTier = "elite", CreatureFloor = 43.5, VisualState = "Active"}
	env.C.track(host)
	env.C.assign()
	local rec = env.C.records[host]
	ok(rec.built and rec.tier == "elite", "the Sentinel is drawn as an elite")
	near(rec.lift, (43.5 - 47) + 4.2 * 0.92, 1e-6, "its feet stand on the hall floor")
	eq(host.LocalTransparencyModifier, 1, "the fallback block is hidden locally")
	env.frame(1 / 60)
	host:SetAttribute("Health", 500)
	host:SetAttribute("Health", 400)
	env.frame(0.01)
	ok(rec.state.flinch > 0.5, "guardian hits flinch")
	host:SetAttribute("VisualState", "Defeated")
	env.frame(0.5)
	ok(rec.state.defeated, "the defeated guardian slumps")
	-- Reduced motion is sampled by the LOD pass.
	env.reduced = true
	env.C.assign()
	env.frame(0.1) -- (119 studs away: an elite at limb LOD poses at 15 Hz)
	eq(rec.lod, 2, "the far guardian animates at the limb LOD rate")
	ok(rec.state.reduced, "reduced motion reaches the pose")
end
do
	-- Pets: local models tagged by pets.client.lua, drawn facing their owner's way.
	local env = runtime()
	local body = stub("Part", {Name = "Body", CFrame = CFrame.new(3, 1, 0), Size = Vector3.new(1, 1, 1)})
	local pet = stub("Model", {Name = "Alice's Emberfox", PrimaryPart = body})
	pet.children = {body}
	pet.attrs = {CreatureRig = "pet_quad", CreatureScale = 0.9, Color = "E07A3F", Pet = true}
	env.C.track(pet)
	env.C.assign()
	local rec = env.C.records[pet]
	ok(rec.built and rec.tier == "pet", "pets are drawn")
	eq(body.LocalTransparencyModifier, 1, "the pet's visible body primitive is hidden")
	env.frame(1 / 60)
	ok(rec.visual.LookVector:Dot(body.CFrame.LookVector) < -0.99, "pet rigs face the follower's +Z (rig yaw)")
end
print("PASS: renderer runtime (" .. (checks - part7) .. ")")

------------------------------------------------------------------------------
-- 8. Source rules
------------------------------------------------------------------------------
local part8 = checks
local function body(source, header)
	local start = string.find(source, header, 1, true)
	assert(start, "missing " .. header)
	local stop = string.find(source, "\nend\n", start, true)
	return string.sub(source, start, stop)
end
for _, header in ipairs({"local function pose(rec, dt, clock, serverNow)", "local function step(dt)"}) do
	local text = body(clientSource, header)
	ok(not string.find(text, "Instance.new", 1, true), header .. ": no instances per frame")
	ok(not string.find((text:gsub("%-%-[^\n]*", "")), "{", 1, true), header .. ": no table constructors per frame")
	ok(not string.find(text, "function(", 1, true), header .. ": no closures per frame")
end
local poseText = body(fs.readFile("shared/CreatureRules.lua"), "function R.pose(rig, state, out)")
ok(not string.find((poseText:gsub("%-%-[^\n]*", "")), "= {", 1, true) and not string.find(poseText, "function(", 1, true), "R.pose allocates no tables or closures")
ok(has(poseText, "out.seg = out.seg or {}"), "R.pose reuses the caller's segment list")
-- Server authority: the renderer never writes replicated state.
for _, banned in ipairs({":SetAttribute(", ":FireServer(", ":InvokeServer(", "rec.root.CFrame =", "host.CFrame =", ".Transparency = 1\n\t\t\tp", "host:Destroy()"}) do
	ok(not string.find(clientSource, banned, 1, true), "creatures.client.lua never uses " .. banned)
end
ok(has(clientSource, "LocalTransparencyModifier = 1") and has(clientSource, "LocalTransparencyModifier = 0"), "primitives are hidden and restored locally")
local _, bulkCalls = string.gsub(clientSource, "BulkMoveTo%(", "")
eq(bulkCalls, 1, "one BulkMoveTo call site")
ok(has(clientSource, "BindToRenderStep"), "poses on the render step")
ok(not has(clientSource, "Heartbeat"), "no Heartbeat loop")
-- The renderer stays out of the player animation script and the legacy sculpture path.
ok(not has(clientSource, "animate.client") and not has(clientSource, "Humanoid"), "player animations untouched")
ok(has(forgeSource, 'if CREATURE_KINDS[data.kind] then skip(part, "creature shape", true); return end'), "Shape-tagged world parts never forge creature meshes")
ok(has(forgeSource, '"AetherCreatureArt"'), "the forge loads the creature catalog")
-- Project wiring.
local project = fs.readFile("default.project.json")
ok(has(project, '"AetherCreatureArt": { "$path": "art/CreatureCatalog.lua" }') and has(project, '"AetherCreatureRules": { "$path": "shared/CreatureRules.lua" }')
	and has(project, '"IsleCreatures": { "$path": "creatures.client.lua" }'), "Rojo project wires the catalog, rules and renderer")
for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-creatures.luau"), script .. " runs this suite") end
print("PASS: source rules (" .. (checks - part8) .. ")")

print("Creature visuals QA passed " .. checks .. " checks.")
print("SUITE-END verify-creatures.luau")

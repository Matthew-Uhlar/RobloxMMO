-- Combat: real-time monsters, attacks, slayer bosses. See docs/DEPTH-CONTRACT.md §5.
--
-- Layout
--   1. Constants (C)
--   2. blueprint(kind, color, boss) – pure part specs for every original creature
--   3. createLogic(env) – pure, Roblox-free rules: spawn bookkeeping, AI decisions,
--      attack validation, cooldowns, kill credit, slayer boss lifecycle. Tested
--      headlessly by verify-combat.luau through the __CombatTestHarness hook.
--   4. Runtime – Instances, remotes, the single Heartbeat AI loop, FX broadcast.
--
-- Design decisions (documented for the other teams):
--   * Monsters at or below C.PASSIVE_MAX_LEVEL (the Brambleback Boar) are passive
--     until struck. Every other monster aggroes on a player within C.AGGRO_RANGE,
--     unless that player's combat level is more than double the monster's level
--     (OSRS "tolerance"), using only already-cached bridge stats.
--   * Kill credit: every contributor that dealt damage, is alive and is within
--     C.CREDIT_RANGE studs of the monster. Ironman contributors are credited only
--     when they were the sole contributor (loosely mirrors the Warden, where
--     Ironman journals fight their own solo instance).
--   * Slayer bosses are bound to their summoner: only they can damage it, it
--     never leashes, and it fails on summoner death or after C.BOSS_DURATION.
--     A summoner leaving the server despawns the boss WITHOUT a bridge call so
--     the quest's boss stays ready for their next session; clearing the
--     SlayerBossReady attribute (quest abandoned) also despawns silently.

local C = {
	ATTACK_RANGE = 14,          -- player HRP to monster surface
	AGGRO_RANGE = 25,
	LEASH_RANGE = 60,           -- from the spawn marker
	RETURN_RADIUS = 3,          -- leash completes inside this radius
	MONSTER_REACH = 6,          -- monster attack range (+ body radius)
	CREDIT_RANGE = 60,
	BASE_COOLDOWN = 0.45,       -- seconds between player swings at 0 Attack Speed
	COOLDOWN_GRACE = 0.08,      -- latency allowance on the swing cooldown
	STATS_TTL = 1,              -- bridge "stats" cache per player
	BOSS_DURATION = 240,        -- 4 minutes
	BOSS_DEFENSE_PER_TIER = 25, -- slayer tiers carry no defense; tier 1 = 0
	MAX_MONSTERS = 90,          -- marker monsters (bosses are capped at one per player)
	PASSIVE_MAX_LEVEL = 4,
	WANDER_RADIUS = 12,
	ACTIVE_RANGE = 160,         -- monsters with no player this close sleep
	FX_RANGE = 110,
	MAX_RADIUS_BONUS = 6,
	DEFAULT_COUNT = 2,
	MAX_COUNT = 3,
}

------------------------------------------------------------------------------
-- 2. Creature blueprints (pure). Forward is -Z, root sits `hip` above ground.
------------------------------------------------------------------------------
local BODY_KIND = {
	BramblebackBoar = "boar", Thornling = "thornling", ShaleCrawler = "crawler", CinderMite = "mite",
	BarkStalker = "stalker", GaleSprite = "sprite", BrassGolem = "golem", StormHarrier = "harrier",
	GloomfangSpider = "spider", VoidWisp = "wisp", ReefLurker = "lurker", TempestWraith = "wraith",
	StarbornSentinel = "sentinel",
}
local BOSS_BODY = {
	Bramble = {kind = "boar", speed = 13},
	Gloom = {kind = "spider", speed = 15},
	Tempest = {kind = "wraith", speed = 16},
}
local ROMAN = {"I", "II", "III", "IV", "V"}

local function hexColor(hex)
	hex = tostring(hex or "AAAAAA")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 170, tonumber(hex:sub(3, 4), 16) or 170, tonumber(hex:sub(5, 6), 16) or 170)
end
local function mix(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function blueprint(kind, colorHex, boss)
	local V, CF, A = Vector3.new, CFrame.new, CFrame.Angles
	local pi = math.pi
	local base = hexColor(colorHex)
	local dark = mix(base, Color3.new(0, 0, 0), 0.4)
	local light = mix(base, Color3.new(1, 1, 1), 0.35)
	local ivory = hexColor("FFF4D9")
	local eye = if boss then hexColor("FF3B3B") else hexColor("FFE680")
	local parts = {}
	local function add(name, shape, size, offset, color, material, anim, extra)
		local spec = {name = name, shape = shape, size = size, offset = offset, color = color,
			material = material or "SmoothPlastic", anim = anim, transparency = 0}
		if extra then for k, v in pairs(extra) do spec[k] = v end end
		table.insert(parts, spec)
		return spec
	end
	local alongZ, upright = A(0, pi / 2, 0), A(0, 0, pi / 2)
	local hip, hitbox, flying, light3 = 2, V(3, 3, 4), false, nil
	local function eyes(x, y, z, size, color)
		add("EyeL", "Ball", V(size, size, size), CF(-x, y, z), color or eye, "Neon")
		add("EyeR", "Ball", V(size, size, size), CF(x, y, z), color or eye, "Neon")
	end
	if kind == "boar" then
		hip, hitbox = 1.9, V(3, 3.4, 6.4)
		add("Body", "Cylinder", V(4.2, 2.6, 2.6), CF(0, 0, 0) * alongZ, base)
		add("Head", "Ball", V(2.1, 2.1, 2.1), CF(0, 0.25, -2.3), base)
		add("Snout", "Cylinder", V(1, 1.1, 1.1), CF(0, -0.1, -3.35) * alongZ, light)
		add("TuskL", "Cylinder", V(0.8, 0.22, 0.22), CF(-0.5, -0.15, -3.6) * A(0, 0, math.rad(65)), ivory)
		add("TuskR", "Cylinder", V(0.8, 0.22, 0.22), CF(0.5, -0.15, -3.6) * A(0, 0, math.rad(115)), ivory)
		eyes(0.55, 0.6, -3.05, 0.32)
		add("EarL", "Wedge", V(0.2, 0.7, 0.55), CF(-0.75, 1.25, -2.0), dark)
		add("EarR", "Wedge", V(0.2, 0.7, 0.55), CF(0.75, 1.25, -2.0), dark)
		for i, z in ipairs({-1.3, 1.3}) do
			add("LegL" .. i, "Block", V(0.7, 1.5, 0.7), CF(-0.9, -1.25, z), dark, nil, if i == 1 then "legA" else "legB")
			add("LegR" .. i, "Block", V(0.7, 1.5, 0.7), CF(0.9, -1.25, z), dark, nil, if i == 1 then "legB" else "legA")
		end
		for i, z in ipairs({-1.1, -0.2, 0.7, 1.6}) do
			add("Bramble" .. i, "Wedge", V(0.35, 1.0 - i * 0.1, 1.0), CF(0, 1.55 - i * 0.05, z), hexColor("5E8C4A"), "Grass")
		end
		add("Tail", "Cylinder", V(0.9, 0.18, 0.18), CF(0, 0.55, 2.45) * A(0, pi / 2, math.rad(-30)), dark, nil, "tail")
	elseif kind == "thornling" then
		hip, hitbox = 1.8, V(3, 5, 3)
		add("Stem", "Cylinder", V(2.4, 1.3, 1.3), CF(0, 0, 0) * upright, dark)
		add("Bulb", "Ball", V(2.3, 2.3, 2.3), CF(0, 1.9, 0), base)
		for i = 1, 5 do
			local a = (i - 1) * 2 * pi / 5
			add("Petal" .. i, "Wedge", V(0.3, 1.3, 1.1), A(0, a, 0) * CF(0, 2.7, 0.9) * A(math.rad(-25), 0, 0), hexColor("D96C9C"), nil, "sway")
		end
		eyes(0.45, 2.05, -1.05, 0.38, hexColor("F6FF8F"))
		add("Maw", "Block", V(1.0, 0.16, 0.2), CF(0, 1.5, -1.1), hexColor("2B1B17"))
		for i = 1, 4 do
			local a = (i - 1) * pi / 2 + pi / 4
			add("Root" .. i, "Cylinder", V(1.7, 0.4, 0.4), A(0, a, 0) * CF(0.9, -1.2, 0) * A(0, 0, math.rad(-35)), dark, nil, if i % 2 == 0 then "legA" else "legB")
		end
		add("VineL", "Cylinder", V(2.2, 0.3, 0.3), CF(-1.3, 0.4, -0.2) * A(0, 0, math.rad(55)), base, nil, "sway")
		add("VineR", "Cylinder", V(2.2, 0.3, 0.3), CF(1.3, 0.4, -0.2) * A(0, 0, math.rad(125)), base, nil, "sway")
		for i = 1, 3 do
			add("Thorn" .. i, "Wedge", V(0.2, 0.5, 0.45), A(0, i * 2.1, 0) * CF(0, -0.3 + i * 0.35, -0.75), light)
		end
	elseif kind == "crawler" then
		hip, hitbox = 1.1, V(3.4, 2.4, 6.4)
		for i, z in ipairs({-1.7, -0.3, 1.1, 2.3}) do
			local s = ({1.8, 2.1, 1.9, 1.5})[i]
			add("Segment" .. i, "Ball", V(s, s, s), CF(0, 0, z), if i % 2 == 0 then dark else base)
			if i <= 3 then add("Plate" .. i, "Block", V(s + 0.2, 0.4, 1.1), CF(0, s / 2 - 0.05, z), light, "Slate") end
		end
		for i, z in ipairs({-1.4, -0.2, 1.0}) do
			add("LegL" .. i, "Block", V(1.5, 0.25, 0.25), CF(-1.4, -0.45, z) * A(0, 0, math.rad(-25)), dark, nil, if i % 2 == 1 then "legA" else "legB", {pivot = V(0.75, 0, 0), axis = "Y"})
			add("LegR" .. i, "Block", V(1.5, 0.25, 0.25), CF(1.4, -0.45, z) * A(0, 0, math.rad(25)), dark, nil, if i % 2 == 1 then "legB" else "legA", {pivot = V(-0.75, 0, 0), axis = "Y"})
		end
		add("MandibleL", "Wedge", V(0.25, 0.4, 0.9), CF(-0.45, -0.25, -2.7), ivory)
		add("MandibleR", "Wedge", V(0.25, 0.4, 0.9), CF(0.45, -0.25, -2.7), ivory)
		eyes(0.4, 0.35, -2.5, 0.3, hexColor("FF9F43"))
	elseif kind == "mite" then
		hip, hitbox = 1.3, V(3.6, 2.6, 4.4)
		add("Body", "Ball", V(2.5, 2.5, 2.5), CF(0, 0.1, 0.4), base)
		add("Abdomen", "Ball", V(2.0, 2.0, 2.0), CF(0, 0.3, 1.7), dark)
		for i = 1, 3 do
			add("Ember" .. i, "Block", V(0.25, 0.25, 1.4), A(0, 0, (i - 2) * 0.6) * CF(0, 1.32, 0.6), hexColor("FF8A3D"), "Neon")
		end
		add("Head", "Ball", V(1.3, 1.3, 1.3), CF(0, -0.1, -1.1), dark)
		eyes(0.3, 0.1, -1.65, 0.28, hexColor("FFD23F"))
		for i, z in ipairs({-0.6, 0, 0.6, 1.2}) do
			local anim = if i % 2 == 1 then "legA" else "legB"
			add("LegL" .. i, "Block", V(1.4, 0.2, 0.2), CF(-1.5, -0.6, z) * A(0, 0, math.rad(-30)), dark, nil, anim, {pivot = V(0.7, 0, 0), axis = "Y"})
			add("LegR" .. i, "Block", V(1.4, 0.2, 0.2), CF(1.5, -0.6, z) * A(0, 0, math.rad(30)), dark, nil, if anim == "legA" then "legB" else "legA", {pivot = V(-0.7, 0, 0), axis = "Y"})
		end
		add("FangL", "Wedge", V(0.2, 0.45, 0.35), CF(-0.25, -0.65, -1.6) * A(pi, 0, 0), ivory)
		add("FangR", "Wedge", V(0.2, 0.45, 0.35), CF(0.25, -0.65, -1.6) * A(pi, 0, 0), ivory)
		light3 = hexColor("FF8A3D")
	elseif kind == "stalker" then
		hip, hitbox = 2.7, V(3, 4.6, 6.4)
		add("Torso", "Block", V(2.2, 2.0, 4.0), CF(0, 0.3, 0), base, "Wood")
		add("Neck", "Block", V(1.2, 1.4, 1.2), CF(0, 0.9, -2.1) * A(math.rad(30), 0, 0), base, "Wood")
		add("Head", "Block", V(1.6, 1.3, 2.0), CF(0, 1.4, -2.9), dark, "Wood")
		add("Jaw", "Wedge", V(1.4, 0.5, 1.6), CF(0, 0.6, -3.1) * A(pi, 0, 0), dark, "Wood")
		eyes(0.5, 1.6, -3.85, 0.3, hexColor("C7FF6B"))
		for i = 1, 3 do
			add("Mane" .. i, "Wedge", V(0.3, 1.0, 1.2), CF(0, 1.55, -1.4 + i * 0.9), hexColor("4F7F3A"), "Grass")
		end
		for i, z in ipairs({-1.4, 1.4}) do
			add("LegL" .. i, "Block", V(0.6, 2.6, 0.6), CF(-0.9, -1.4, z), dark, "Wood", if i == 1 then "legA" else "legB")
			add("LegR" .. i, "Block", V(0.6, 2.6, 0.6), CF(0.9, -1.4, z), dark, "Wood", if i == 1 then "legB" else "legA")
		end
		add("Tail", "Wedge", V(0.5, 0.8, 1.8), CF(0, 0.8, 2.7) * A(math.rad(-20), 0, 0), base, "Wood", "tail")
		add("HornL", "Cylinder", V(1.4, 0.25, 0.25), CF(-0.6, 2.4, -2.7) * A(0, 0, math.rad(60)), hexColor("8D6346"), "Wood")
		add("HornR", "Cylinder", V(1.4, 0.25, 0.25), CF(0.6, 2.4, -2.7) * A(0, 0, math.rad(120)), hexColor("8D6346"), "Wood")
	elseif kind == "sprite" then
		hip, hitbox, flying = 4, V(3.2, 3.2, 3.2), true
		add("Core", "Ball", V(1.5, 1.5, 1.5), CF(0, 0, 0), light, "Neon")
		add("Shell", "Ball", V(2.5, 2.5, 2.5), CF(0, 0, 0), base, "Glass", nil, {transparency = 0.45})
		eyes(0.38, 0.25, -1.15, 0.3, hexColor("1D3557"))
		for i = 1, 3 do
			add("Gust" .. i, "Cylinder", V(1.2, 0.8 - i * 0.18, 0.8 - i * 0.18), CF(0, -0.3 * i, 1.0 + i * 0.9) * alongZ, base, "SmoothPlastic", "tail", {transparency = 0.3 + i * 0.1})
		end
		for i = 1, 4 do
			local a = (i - 1) * pi / 2
			add("Mote" .. i, "Ball", V(0.4, 0.4, 0.4), A(0, a, 0) * CF(2.0, 0.3 * (i % 2), 0), hexColor("F1FAEE"), "Neon", "orbit")
		end
		add("WingL", "Wedge", V(0.12, 0.9, 1.8), CF(-1.6, 0.4, 0.2) * A(0, 0, math.rad(30)), light, "SmoothPlastic", "wingL", {transparency = 0.3, pivot = V(0, -0.45, 0), axis = "Z"})
		add("WingR", "Wedge", V(0.12, 0.9, 1.8), CF(1.6, 0.4, 0.2) * A(0, 0, math.rad(-30)), light, "SmoothPlastic", "wingR", {transparency = 0.3, pivot = V(0, -0.45, 0), axis = "Z"})
		light3 = light
	elseif kind == "golem" then
		hip, hitbox = 3.4, V(5.2, 7, 3)
		add("Torso", "Block", V(3.6, 3.0, 2.4), CF(0, 0.7, 0), base, "Metal")
		add("Core", "Ball", V(1.0, 1.0, 1.0), CF(0, 0.9, -1.15), hexColor("5CE1E6"), "Neon")
		add("Head", "Block", V(1.6, 1.3, 1.5), CF(0, 2.85, -0.2), dark, "Metal")
		add("Visor", "Block", V(1.25, 0.25, 0.12), CF(0, 2.95, -0.98), hexColor("5CE1E6"), "Neon")
		add("ShoulderL", "Ball", V(1.5, 1.5, 1.5), CF(-2.1, 1.9, 0), dark, "Metal")
		add("ShoulderR", "Ball", V(1.5, 1.5, 1.5), CF(2.1, 1.9, 0), dark, "Metal")
		add("ArmL", "Block", V(1.1, 2.8, 1.1), CF(-2.3, 0.2, 0), base, "Metal", "legB", {pivot = V(0, 1.4, 0)})
		add("ArmR", "Block", V(1.1, 2.8, 1.1), CF(2.3, 0.2, 0), base, "Metal", "legA", {pivot = V(0, 1.4, 0)})
		add("FistL", "Block", V(1.4, 1.2, 1.4), CF(-2.3, -1.7, 0), dark, "Metal", "legB", {pivot = V(0, 3.3, 0)})
		add("FistR", "Block", V(1.4, 1.2, 1.4), CF(2.3, -1.7, 0), dark, "Metal", "legA", {pivot = V(0, 3.3, 0)})
		add("Pelvis", "Block", V(2.6, 0.8, 1.8), CF(0, -1.1, 0), dark, "Metal")
		add("LegL", "Block", V(1.2, 2.0, 1.3), CF(-0.8, -2.4, 0), base, "Metal", "legA")
		add("LegR", "Block", V(1.2, 2.0, 1.3), CF(0.8, -2.4, 0), base, "Metal", "legB")
		add("FlueL", "Cylinder", V(1.4, 0.45, 0.45), CF(-0.8, 2.3, 1.1) * upright, dark, "Metal")
		add("FlueR", "Cylinder", V(1.4, 0.45, 0.45), CF(0.8, 2.3, 1.1) * upright, dark, "Metal")
	elseif kind == "harrier" then
		hip, hitbox, flying = 5, V(6, 2.4, 4.4), true
		add("Body", "Cylinder", V(2.6, 1.5, 1.5), CF(0, 0, 0) * alongZ, base)
		add("Head", "Ball", V(1.3, 1.3, 1.3), CF(0, 0.35, -1.6), base)
		add("Beak", "Wedge", V(0.4, 0.4, 0.8), CF(0, 0.2, -2.45) * A(0, pi, 0), hexColor("F9CC77"))
		eyes(0.4, 0.55, -1.95, 0.25, hexColor("E9F5FF"))
		add("WingL", "Block", V(2.4, 0.2, 1.6), CF(-1.9, 0.2, 0), base, nil, "wingL", {pivot = V(1.2, 0, 0), axis = "Z"})
		add("WingR", "Block", V(2.4, 0.2, 1.6), CF(1.9, 0.2, 0), base, nil, "wingR", {pivot = V(-1.2, 0, 0), axis = "Z"})
		add("TipL", "Block", V(1.6, 0.16, 1.1), CF(-3.8, 0.2, 0.25), light, nil, "wingL", {pivot = V(3.1, 0, 0), axis = "Z"})
		add("TipR", "Block", V(1.6, 0.16, 1.1), CF(3.8, 0.2, 0.25), light, nil, "wingR", {pivot = V(-3.1, 0, 0), axis = "Z"})
		for i = -1, 1 do
			add("Tail" .. (i + 2), "Wedge", V(0.5, 0.15, 1.4), CF(i * 0.45, 0.1, 1.9) * A(0, i * 0.35, 0), dark)
		end
		add("CrestA", "Wedge", V(0.15, 0.7, 0.9), CF(0, 1.05, -1.4), hexColor("CFE8FF"), "Neon")
		add("CrestB", "Wedge", V(0.15, 0.5, 0.7), CF(0, 0.85, -0.85), hexColor("CFE8FF"), "Neon")
		add("TalonL", "Block", V(0.25, 0.7, 0.25), CF(-0.35, -0.95, 0.2), dark)
		add("TalonR", "Block", V(0.25, 0.7, 0.25), CF(0.35, -0.95, 0.2), dark)
	elseif kind == "spider" then
		hip, hitbox = 1.6, V(6, 3, 5.6)
		add("Abdomen", "Ball", V(2.8, 2.8, 2.8), CF(0, 0.45, 1.3), base)
		add("Thorax", "Ball", V(1.8, 1.8, 1.8), CF(0, 0, -0.6), dark)
		add("Mark", "Block", V(0.5, 0.15, 1.1), CF(0, 1.85, 1.2), hexColor("B388EB"), "Neon")
		for i, z in ipairs({-1.1, -0.6, -0.1, 0.4}) do
			local tilt = math.rad(-20 + (i - 1) * 14)
			local anim = if i % 2 == 1 then "legA" else "legB"
			add("LegL" .. i, "Block", V(2.6, 0.28, 0.28), CF(-1.9, 0.1, z) * A(0, tilt, math.rad(-28)), dark, nil, anim, {pivot = V(1.3, 0, 0), axis = "Y"})
			add("LegR" .. i, "Block", V(2.6, 0.28, 0.28), CF(1.9, 0.1, z) * A(0, -tilt, math.rad(28)), dark, nil, if anim == "legA" then "legB" else "legA", {pivot = V(-1.3, 0, 0), axis = "Y"})
		end
		eyes(0.3, 0.35, -1.45, 0.26, if boss then eye else hexColor("D65DB1"))
		eyes(0.55, 0.15, -1.3, 0.2, if boss then eye else hexColor("D65DB1"))
		parts[#parts].name, parts[#parts - 1].name = "EyeR2", "EyeL2"
		add("FangL", "Wedge", V(0.22, 0.6, 0.35), CF(-0.25, -0.55, -1.35) * A(pi, 0, 0), ivory)
		add("FangR", "Wedge", V(0.22, 0.6, 0.35), CF(0.25, -0.55, -1.35) * A(pi, 0, 0), ivory)
	elseif kind == "wisp" then
		hip, hitbox, flying = 4, V(3.4, 3.4, 3.4), true
		add("Core", "Ball", V(1.4, 1.4, 1.4), CF(0, 0, 0), light, "Neon")
		add("Aura", "Ball", V(3.0, 3.0, 3.0), CF(0, 0, 0), base, "ForceField")
		for i = 1, 4 do
			add("Shard" .. i, "Wedge", V(0.4, 1.1, 0.5), A(0, (i - 1) * pi / 2, 0) * CF(2.1, 0.2 * ((i % 2) * 2 - 1), 0), dark, "Glass", "orbit")
		end
		for i = 1, 3 do
			add("Trail" .. i, "Ball", V(1 - i * 0.2, 1 - i * 0.2, 1 - i * 0.2), CF(0, -0.2 * i, 0.9 + i * 0.7), base, "Neon", "tail", {transparency = 0.2 + i * 0.18})
		end
		eyes(0.3, 0.15, -0.68, 0.22, hexColor("FFFFFF"))
		light3 = light
	elseif kind == "lurker" then
		hip, hitbox = 1.6, V(3, 3.6, 7.6)
		add("Body", "Cylinder", V(4.5, 2.2, 2.2), CF(0, 0, 0.3) * alongZ, base)
		add("Head", "Ball", V(2.3, 2.3, 2.3), CF(0, 0.15, -2.2), base)
		add("Jaw", "Wedge", V(1.8, 0.6, 1.6), CF(0, -0.75, -2.6) * A(pi, 0, 0), dark)
		add("ToothL", "Wedge", V(0.2, 0.4, 0.25), CF(-0.5, -0.35, -3.25) * A(pi, 0, 0), ivory)
		add("ToothR", "Wedge", V(0.2, 0.4, 0.25), CF(0.5, -0.35, -3.25) * A(pi, 0, 0), ivory)
		eyes(0.65, 0.65, -3.05, 0.34, hexColor("FFE66D"))
		for i = 1, 3 do
			add("Fin" .. i, "Wedge", V(0.2, 1.0 - i * 0.15, 1.2), CF(0, 1.4 - i * 0.05, -1.2 + i * 1.0), light)
		end
		add("FinL", "Wedge", V(0.15, 0.9, 1.2), CF(-1.2, -0.6, -0.6) * A(0, 0, math.rad(40)), light, nil, "wingL", {pivot = V(0, 0.45, 0), axis = "Z"})
		add("FinR", "Wedge", V(0.15, 0.9, 1.2), CF(1.2, -0.6, -0.6) * A(0, 0, math.rad(-40)), light, nil, "wingR", {pivot = V(0, 0.45, 0), axis = "Z"})
		add("Tail", "Cylinder", V(1.6, 1.2, 1.2), CF(0, 0, 3.2) * alongZ, dark, nil, "tail", {pivot = V(0.8, 0, 0)})
		add("Fluke", "Wedge", V(0.2, 1.6, 1.2), CF(0, 0, 4.2) * A(0, pi, 0), light, nil, "tail", {pivot = V(0, 0, -1.8), axis = "Y"})
		add("Stalk", "Cylinder", V(1.6, 0.15, 0.15), CF(0, 1.9, -2.6) * A(0, pi / 2, math.rad(-60)), dark, nil, "sway")
		add("Lure", "Ball", V(0.45, 0.45, 0.45), CF(0, 2.5, -3.3), hexColor("B8FFF4"), "Neon", "sway")
		light3 = hexColor("B8FFF4")
	elseif kind == "wraith" then
		hip, hitbox, flying = 3.6, V(4, 5.6, 3), true
		add("Hood", "Ball", V(2.1, 2.1, 2.1), CF(0, 1.7, 0), dark, "Fabric")
		add("Face", "Ball", V(1.5, 1.5, 1.5), CF(0, 1.6, -0.45), hexColor("0B0B14"))
		eyes(0.3, 1.7, -1.15, 0.24, if boss then eye else hexColor("7FDBFF"))
		add("Mantle", "Block", V(2.3, 1.8, 1.5), CF(0, 0.3, 0), base, "Fabric")
		for i = 1, 4 do
			local a = (i - 1) * pi / 2
			add("Tatter" .. i, "Wedge", V(1.0, 2.0, 0.5), A(0, a, 0) * CF(0, -1.4, -0.5) * A(pi, 0, 0), base, "Fabric", "sway", {transparency = 0.15})
		end
		add("SleeveL", "Cylinder", V(1.8, 0.55, 0.55), CF(-1.4, 0.3, -0.5) * A(0, math.rad(40), math.rad(-30)), base, "Fabric", "wingL", {pivot = V(0.9, 0, 0), axis = "Z"})
		add("SleeveR", "Cylinder", V(1.8, 0.55, 0.55), CF(1.4, 0.3, -0.5) * A(0, math.rad(-40), math.rad(-150)), base, "Fabric", "wingR", {pivot = V(-0.9, 0, 0), axis = "Z"})
		add("ClawL", "Wedge", V(0.3, 0.6, 0.5), CF(-2.0, -0.2, -1.2), hexColor("7FDBFF"), "Neon", "wingL", {pivot = V(1.5, 0.5, 0.7), axis = "Z"})
		add("ClawR", "Wedge", V(0.3, 0.6, 0.5), CF(2.0, -0.2, -1.2), hexColor("7FDBFF"), "Neon", "wingR", {pivot = V(-1.5, 0.5, 0.7), axis = "Z"})
		for i = 1, 3 do
			add("Bolt" .. i, "Block", V(0.15, 0.7, 0.15), A(0, (i - 1) * 2 * pi / 3, 0) * CF(1.7, 2.6, 0) * A(0, 0, 0.5), hexColor("CFE8FF"), "Neon", "orbit")
		end
		light3 = hexColor("7FDBFF")
	elseif kind == "sentinel" then
		hip, hitbox = 4.2, V(5.4, 8.4, 3)
		add("Torso", "Block", V(3.2, 3.6, 2.2), CF(0, 0.8, 0), base, "Marble")
		add("Star", "Ball", V(1.2, 1.2, 1.2), CF(0, 1.1, -1.05), hexColor("FFD166"), "Neon")
		add("HeadTop", "Wedge", V(1.4, 1.0, 1.4), CF(0, 3.6, 0), light, "Glass")
		add("HeadBottom", "Wedge", V(1.4, 1.0, 1.4), CF(0, 2.6, 0) * A(pi, 0, 0), light, "Glass")
		add("Halo", "Cylinder", V(0.15, 3.2, 3.2), CF(0, 3.2, 0.9) * alongZ, hexColor("FFD166"), "Neon", nil, {transparency = 0.25})
		for i = 1, 4 do
			add("Shard" .. i, "Wedge", V(0.5, 1.4, 0.6), A(0, (i - 1) * pi / 2 + pi / 4, 0) * CF(3.0, 1.2, 0), light, "Glass", "orbit")
		end
		add("ArmL", "Block", V(1.0, 3.2, 1.0), CF(-2.2, 0.6, 0), base, "Marble", "legB", {pivot = V(0, 1.6, 0)})
		add("ArmR", "Block", V(1.0, 3.2, 1.0), CF(2.2, 0.6, 0), base, "Marble", "legA", {pivot = V(0, 1.6, 0)})
		add("LegL", "Block", V(1.2, 2.6, 1.2), CF(-0.8, -2.5, 0), dark, "Marble", "legA")
		add("LegR", "Block", V(1.2, 2.6, 1.2), CF(0.8, -2.5, 0), dark, "Marble", "legB")
		light3 = hexColor("FFD166")
	else
		hip, hitbox = 1.5, V(3, 3, 3)
		add("Body", "Ball", V(3, 3, 3), CF(0, 0, 0), base)
		eyes(0.5, 0.4, -1.4, 0.35)
	end
	local scale = 1
	if boss then
		scale = 2.2
		for _, p in ipairs(parts) do
			p.size *= scale
			p.offset = CF(p.offset.Position * scale) * (p.offset - p.offset.Position)
			if p.pivot then p.pivot *= scale end
		end
		hip *= scale
		hitbox *= scale
		local top = hitbox.Y / 2
		for i = 1, 3 do
			add("Crown" .. i, "Wedge", V(0.5, 1.8, 1.0) , CF((i - 2) * 1.1, top - 0.2, -hitbox.Z * 0.2), hexColor("8B1E1E"), "Slate")
		end
		add("Aura", "Cylinder", V(0.3, hitbox.X * 1.3, hitbox.X * 1.3), CF(0, -hip + 0.2, 0) * upright, hexColor("FF3B3B"), "ForceField", "orbit", {transparency = 0.2})
		light3 = hexColor("FF3B3B")
	end
	return {parts = parts, hip = hip, hitbox = hitbox, flying = flying, scale = scale, light = light3,
		radius = math.min(C.MAX_RADIUS_BONUS, math.max(hitbox.X, hitbox.Z) / 2)}
end

------------------------------------------------------------------------------
-- 3. Pure rules
------------------------------------------------------------------------------
-- env = {Data, Progression, bridge(op, player, payload), now(), rng(),
--        position(player) -> Vector3?, alive(player) -> bool, players() -> {player},
--        heal(player, percentOfMaxHealth)}
local function createLogic(env)
	local Data, Progression = env.Data, env.Progression
	local L = {C = C}
	local records = {}       -- [record] = true
	local byModel = {}       -- [model] = record
	local markers = {}       -- [key] = marker
	local statsCache = {}    -- [player] = {value, at}
	local nextAttack = {}    -- [player] = time
	local bosses = {}        -- [player] = record
	local pendingBoss = {}   -- [player] = spec
	local liveCount = 0

	local function flat(v) return Vector3.new(v.X, 0, v.Z) end
	local function flatDist(a, b) return (flat(a) - flat(b)).Magnitude end
	L.flatDist = flatDist

	function L.attackCooldown(attackSpeed)
		local as = math.clamp(tonumber(attackSpeed) or 0, 0, 100)
		return C.BASE_COOLDOWN / (1 + as / 100)
	end
	function L.monsterCooldown(speed)
		return math.clamp(2.2 - (tonumber(speed) or 12) * 0.04, 1.2, 2.0)
	end
	function L.respawnDelay(def)
		return 8 + (def.level or 1) * 0.15
	end
	function L.isPassive(def)
		return (def.level or 1) <= C.PASSIVE_MAX_LEVEL
	end

	-- Stats ------------------------------------------------------------------
	function L.statsFor(player)
		local now = env.now()
		local cached = statsCache[player]
		if cached and now - cached.at < C.STATS_TTL then return cached.value end
		local value = env.bridge("stats", player)
		if type(value) ~= "table" or type(value.stats) ~= "table" then value = nil end
		statsCache[player] = {value = value, at = now}
		return value
	end
	function L.peekStats(player)
		local cached = statsCache[player]
		return cached and cached.value
	end

	-- Spawn bookkeeping ------------------------------------------------------
	function L.addMarker(key, monsterId, count, home, region)
		if markers[key] then return markers[key] end
		local def = type(monsterId) == "string" and Data.Monsters[monsterId]
		if not def then return nil, "unknown monster" end
		count = math.clamp(math.floor(tonumber(count) or C.DEFAULT_COUNT), 1, C.MAX_COUNT)
		local now = env.now()
		local marker = {key = key, id = monsterId, def = def, count = count, home = home, region = region, live = {}, queue = {}}
		for i = 1, count do marker.queue[i] = now end
		markers[key] = marker
		return marker
	end
	function L.marker(key) return markers[key] end
	function L.liveCount() return liveCount end
	function L.dueSpawns()
		local now, due = env.now(), {}
		for _, marker in pairs(markers) do
			local i = 1
			while i <= #marker.queue do
				if liveCount + #due >= C.MAX_MONSTERS then return due end
				if marker.queue[i] <= now then
					table.remove(marker.queue, i)
					table.insert(due, marker)
				else
					i += 1
				end
			end
		end
		return due
	end
	-- Runtime could not build the model: try again shortly.
	function L.spawnFailed(marker)
		if markers[marker.key] == marker then table.insert(marker.queue, env.now() + 5) end
	end
	local function newRecord(fields)
		local r = {alive = true, contributors = {}, nextHit = 0, nextWander = 0, yaw = 0, radius = 0, leashing = false}
		for k, v in pairs(fields) do r[k] = v end
		records[r] = true
		if r.model ~= nil then byModel[r.model] = r end
		return r
	end
	function L.register(marker, model, position, opts)
		local def = marker.def
		opts = opts or {}
		local r = newRecord({
			id = marker.id, def = def, name = def.name, level = def.level, maxHp = def.hp, hp = def.hp,
			damage = def.damage, defense = def.defense or 0, speed = def.speed or 12,
			attackCooldown = L.monsterCooldown(def.speed), passive = L.isPassive(def),
			marker = marker, home = marker.home, position = position, model = model,
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
		})
		marker.live[r] = true
		liveCount += 1
		return r
	end
	function L.unregister(r, noRespawn)
		if not records[r] then return end
		records[r] = nil
		r.alive = false
		if r.model ~= nil and byModel[r.model] == r then byModel[r.model] = nil end
		if r.boss then
			if bosses[r.owner] == r then bosses[r.owner] = nil end
			return
		end
		liveCount -= 1
		local marker = r.marker
		if marker then
			marker.live[r] = nil
			if not noRespawn and markers[marker.key] == marker then
				table.insert(marker.queue, env.now() + L.respawnDelay(marker.def))
			end
		end
	end
	function L.removeMarker(key)
		local marker = markers[key]
		if not marker then return {} end
		markers[key] = nil
		local removed = {}
		for r in pairs(marker.live) do table.insert(removed, r) end
		for _, r in ipairs(removed) do L.unregister(r, true) end
		return removed
	end
	function L.records()
		local list = {}
		for r in pairs(records) do table.insert(list, r) end
		return list
	end
	function L.resolve(model)
		if model == nil then return nil end
		return byModel[model]
	end

	-- Player attacks ---------------------------------------------------------
	function L.validateAttack(player, verb, target)
		if type(verb) ~= "string" or verb ~= "attack" then return false, "verb" end
		local r = L.resolve(target)
		if not r or not r.alive then return false, "target" end
		if r.boss and r.owner ~= player then return false, "owner" end
		if not env.alive(player) then return false, "dead" end
		local pos = env.position(player)
		if not pos then return false, "position" end
		if (pos - r.position).Magnitude - r.radius > C.ATTACK_RANGE then return false, "range" end
		if env.now() < (nextAttack[player] or 0) - C.COOLDOWN_GRACE then return false, "cooldown" end
		return true, r
	end
	function L.attack(player, verb, target)
		local ok, r = L.validateAttack(player, verb, target)
		if not ok then return nil, r end
		local info = L.statsFor(player)
		if not info then return nil, "stats" end
		local stats = info.stats
		nextAttack[player] = env.now() + L.attackCooldown(stats.attackSpeed)
		local raw, crit = Progression.meleeDamage(stats, env.rng)
		local dealt = Progression.damageTaken(raw, r.defense)
		local applied = math.min(dealt, r.hp)
		r.hp -= applied
		r.contributors[player] = (r.contributors[player] or 0) + applied
		if not r.boss and not r.target and not r.leashing then r.target = player end
		r.provoked = true
		local lifesteal = tonumber(stats.lifesteal) or 0
		if lifesteal > 0 then env.heal(player, lifesteal) end
		local result = {record = r, damage = dealt, crit = crit == true, healed = lifesteal > 0}
		if r.hp <= 0 then
			result.killed = true
			result.credited = L.kill(r)
		end
		return result
	end
	function L.creditEligible(r)
		local contributors = 0
		for _, dealt in pairs(r.contributors) do if dealt > 0 then contributors += 1 end end
		local out = {}
		for player, dealt in pairs(r.contributors) do
			if dealt > 0 and env.alive(player) then
				local pos = env.position(player)
				if pos and (pos - r.position).Magnitude <= C.CREDIT_RANGE then
					local info = L.peekStats(player)
					local ironman = info ~= nil and info.ironman == true
					if not ironman or contributors == 1 then table.insert(out, player) end
				end
			end
		end
		return out
	end
	function L.kill(r)
		r.hp = 0
		local credited
		if r.boss then
			credited = {r.owner}
			L.unregister(r)
			env.bridge("slayerBoss", r.owner, {result = "win"})
		else
			credited = L.creditEligible(r)
			L.unregister(r)
			for _, player in ipairs(credited) do env.bridge("kill", player, {monster = r.id}) end
		end
		return credited
	end

	-- AI ---------------------------------------------------------------------
	function L.nearestAggro(r)
		if r.passive and not r.provoked then return nil end
		local best, bestDist
		for _, player in ipairs(env.players()) do
			if env.alive(player) then
				local pos = env.position(player)
				if pos then
					local d = flatDist(pos, r.position)
					local info = L.peekStats(player)
					local tolerant = info and (tonumber(info.combatLevel) or 0) > r.level * 2
					if d <= C.AGGRO_RANGE and flatDist(pos, r.home) <= C.LEASH_RANGE and not tolerant and (not bestDist or d < bestDist) then
						best, bestDist = player, d
					end
				end
			end
		end
		return best
	end
	local function anyPlayerNear(r, range)
		for _, player in ipairs(env.players()) do
			local pos = env.position(player)
			if pos and (pos - r.position).Magnitude <= range then return true end
		end
		return false
	end
	function L.strike(r, player)
		r.nextHit = env.now() + r.attackCooldown
		r.lungeUntil = env.now() + 0.25
		env.bridge("damage", player, {amount = r.damage})
	end
	-- Returns an action: {kind = sleep|idle|wander|chase|hold|strike|leash, goal?, speed?, face?, stop?, healed?}
	function L.think(r)
		if not r.alive then return {kind = "dead"} end
		local now = env.now()
		if r.boss then
			local owner = r.owner
			local pos = env.alive(owner) and env.position(owner)
			if not pos then return {kind = "idle"} end
			r.target = owner
		else
			local fromHome = flatDist(r.position, r.home)
			if r.leashing then
				if fromHome <= C.RETURN_RADIUS then
					r.leashing, r.provoked = false, false
					r.hp, r.contributors = r.maxHp, {}
					return {kind = "idle", healed = true}
				end
				return {kind = "leash", goal = r.home, speed = r.speed * 1.25, stop = 0}
			end
			if fromHome > C.LEASH_RANGE then
				r.leashing, r.target = true, nil
				return {kind = "leash", goal = r.home, speed = r.speed * 1.25, stop = 0}
			end
			if r.target then
				local pos = env.alive(r.target) and env.position(r.target)
				if not pos or flatDist(pos, r.home) > C.LEASH_RANGE + 8 then r.target = nil end
			end
			if not r.target then r.target = L.nearestAggro(r) end
			if not r.target and not anyPlayerNear(r, C.ACTIVE_RANGE) then return {kind = "sleep"} end
		end
		if r.target then
			local pos = env.position(r.target)
			local reach = C.MONSTER_REACH + r.radius
			local d = flatDist(pos, r.position)
			if d <= reach then
				if now >= r.nextHit then
					L.strike(r, r.target)
					return {kind = "strike", face = pos, target = r.target}
				end
				return {kind = "hold", face = pos}
			end
			return {kind = "chase", goal = pos, speed = r.speed, face = pos, stop = reach * 0.7}
		end
		if now >= r.nextWander then
			local a, d = env.rng() * math.pi * 2, env.rng() * C.WANDER_RADIUS
			r.wanderGoal = r.home + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			r.nextWander = now + 4 + env.rng() * 5
		end
		if r.wanderGoal and flatDist(r.wanderGoal, r.position) > 1 then
			return {kind = "wander", goal = r.wanderGoal, speed = r.speed * 0.35, stop = 0}
		end
		return {kind = "idle"}
	end
	-- Moves r.position (flat) toward goal; returns true when it moved.
	function L.step(r, goal, speed, dt, stop)
		local delta = flat(goal) - flat(r.position)
		local dist = delta.Magnitude
		local travel = math.min(dist - (stop or 0), speed * dt)
		if dist < 1e-3 then return false end
		r.yaw = math.atan2(-delta.X, -delta.Z)
		if travel <= 0.01 then return false end
		r.position += delta.Unit * travel
		return true
	end

	-- Slayer bosses ----------------------------------------------------------
	function L.parseBossReady(value)
		if type(value) ~= "string" then return nil end
		local line, tier = value:match("^(%a+):(%d+)$")
		tier = tonumber(tier)
		if not line or not Data.Slayers[line] or not tier or not Data.Slayers[line].tiers[tier] then return nil end
		return line, tier
	end
	function L.bossSpec(line, tier)
		local def = Data.Slayers[line]
		local t = def.tiers[tier]
		local body = BOSS_BODY[line] or {kind = "boar", speed = 13}
		return {line = line, tier = tier, def = def, name = def.name .. " " .. (ROMAN[tier] or tostring(tier)),
			level = t.combatLevel or tier * 10, hp = t.hp, damage = t.damage,
			defense = (tier - 1) * C.BOSS_DEFENSE_PER_TIER, kind = body.kind, speed = body.speed, color = def.color}
	end
	-- Attribute changed. Returns ("spawn", spec) | ("cancel", record?) | (nil, reason)
	function L.bossAttribute(player, value)
		if value == nil or value == "" then
			pendingBoss[player] = nil
			local r = bosses[player]
			if r then L.unregister(r) end
			return "cancel", r
		end
		local line, tier = L.parseBossReady(value)
		if not line then return nil, "invalid" end
		if bosses[player] then return nil, "active" end
		local spec = L.bossSpec(line, tier)
		pendingBoss[player] = spec
		return "spawn", spec
	end
	function L.pendingBosses()
		local list = {}
		for player, spec in pairs(pendingBoss) do
			if env.alive(player) and env.position(player) then table.insert(list, {player = player, spec = spec}) end
		end
		return list
	end
	function L.registerBoss(player, spec, model, position, opts)
		if pendingBoss[player] ~= spec or bosses[player] then return nil end
		pendingBoss[player] = nil
		opts = opts or {}
		local r = newRecord({
			id = "Boss:" .. spec.line, boss = true, owner = player, line = spec.line, tier = spec.tier,
			name = spec.name, level = spec.level, maxHp = spec.hp, hp = spec.hp, damage = spec.damage,
			defense = spec.defense, speed = spec.speed, attackCooldown = 1.8, passive = false,
			home = position, position = position, model = model, expires = env.now() + C.BOSS_DURATION,
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS), target = player,
		})
		bosses[player] = r
		return r
	end
	function L.bossOf(player) return bosses[player] end
	function L.failBoss(player)
		local r = bosses[player]
		if not r then return nil end
		L.unregister(r)
		env.bridge("slayerBoss", player, {result = "fail"})
		return r
	end
	function L.bossTick()
		local now, failed = env.now(), {}
		for player, r in pairs(bosses) do
			local reason = if not env.alive(player) then "died" elseif now >= r.expires then "timeout" else nil
			if reason then
				L.failBoss(player)
				table.insert(failed, {record = r, reason = reason, player = player})
			end
		end
		return failed
	end

	-- Players ----------------------------------------------------------------
	function L.playerRemoving(player)
		statsCache[player], nextAttack[player], pendingBoss[player] = nil, nil, nil
		local removed = {}
		local boss = bosses[player]
		if boss then L.unregister(boss); table.insert(removed, boss) end
		for r in pairs(records) do
			r.contributors[player] = nil
			if r.target == player then r.target = nil end
		end
		return removed
	end
	function L.hasPlayerState(player)
		return statsCache[player] ~= nil or nextAttack[player] ~= nil or pendingBoss[player] ~= nil or bosses[player] ~= nil
	end
	return L
end

local exports = {C = C, blueprint = blueprint, createLogic = createLogic, BODY_KIND = BODY_KIND, BOSS_BODY = BOSS_BODY}
if __CombatTestHarness then
	__CombatTestHarness(exports)
	return
end

------------------------------------------------------------------------------
-- 4. Runtime
------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local Progression = require(ReplicatedStorage:WaitForChild("AetherProgression"))

local function remote(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end
local combatRemote = remote("IsleCombat")
local fxRemote = remote("IsleCombatFx")

local folder = Instance.new("Folder")
folder.Name = "IsleMonsters"
folder.Parent = Workspace

local random = Random.new()
local function characterOf(player)
	local character = player and player.Parent and player.Character
	if not character then return nil end
	return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

local bridgeInstance
local function invokeBridge(op, player, payload)
	bridgeInstance = bridgeInstance or ServerStorage:FindFirstChild("IsleBridge")
	if not bridgeInstance then return nil end
	local ok, result = pcall(bridgeInstance.Invoke, bridgeInstance, op, player, payload)
	if not ok then
		warn("[Combat] bridge " .. op .. " failed: " .. tostring(result))
		return nil
	end
	return result
end

local function broadcast(position, kind, payload)
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = characterOf(player)
		if root and (root.Position - position).Magnitude <= C.FX_RANGE then
			fxRemote:FireClient(player, kind, payload)
		end
	end
end

local Logic = createLogic({
	Data = Data, Progression = Progression,
	now = os.clock,
	rng = function() return random:NextNumber() end,
	players = function() return Players:GetPlayers() end,
	alive = function(player)
		local _, humanoid = characterOf(player)
		return humanoid ~= nil and humanoid.Health > 0
	end,
	position = function(player)
		local _, _, root = characterOf(player)
		return root and root.Position
	end,
	heal = function(player, percent)
		local _, humanoid = characterOf(player)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * percent / 100)
		end
	end,
	bridge = function(op, player, payload)
		if op == "stats" then return invokeBridge(op, player, payload) end
		-- Mutating ops may yield inside the Adventure script; never block the AI loop.
		task.spawn(function()
			local result = invokeBridge(op, player, payload)
			if op == "damage" and type(result) == "number" and player.Parent then
				fxRemote:FireClient(player, "hurt", {amount = result})
			end
		end)
		return nil
	end,
})

-- Ground probing -------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local spawnsFolder -- Workspace.MonsterSpawns once it exists (markers must not count as ground)
local function refreshRayFilter()
	local list = {folder, spawnsFolder}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(list, player.Character) end
	end
	rayParams.FilterDescendantsInstances = list
end
refreshRayFilter()
local function groundY(position, fallback)
	local hit = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

-- Models ---------------------------------------------------------------------
local view = {} -- [record] = {model, root, bar, fill, label, welds, blueprint, phase}
local function barColor(fraction)
	if fraction > 0.5 then return Color3.fromRGB(110, 220, 120) end
	if fraction > 0.25 then return Color3.fromRGB(240, 200, 80) end
	return Color3.fromRGB(230, 80, 70)
end
local function updateBar(r)
	local v = view[r]
	if not v then return end
	local fraction = math.clamp(r.hp / r.maxHp, 0, 1)
	v.fill.Size = UDim2.fromScale(fraction, 1)
	v.fill.BackgroundColor3 = if r.boss then Color3.fromRGB(220, 60, 60) else barColor(fraction)
	v.model:SetAttribute("Health", math.max(0, math.floor(r.hp)))
end

local function buildModel(name, plan, opts)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = plan.hitbox
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	local welds = {}
	for _, spec in ipairs(plan.parts) do
		local part
		if spec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if spec.shape == "Ball" then part.Shape = Enum.PartType.Ball
			elseif spec.shape == "Cylinder" then part.Shape = Enum.PartType.Cylinder end
		end
		part.Name = spec.name
		part.Size = spec.size
		part.Color = spec.color
		part.Material = Enum.Material[spec.material] or Enum.Material.SmoothPlastic
		part.Transparency = spec.transparency or 0
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = spec.size.Magnitude > 2
		part.CFrame = root.CFrame * spec.offset
		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = part
		weld.C0 = spec.offset
		weld.Parent = part
		part.Parent = model
		if spec.anim then table.insert(welds, {weld = weld, spec = spec}) end
	end
	if plan.light then
		local glow = Instance.new("PointLight")
		glow.Color = plan.light
		glow.Range = 10 * plan.scale
		glow.Brightness = 1.4
		glow.Parent = root
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromOffset(if opts.boss then 220 else 150, if opts.boss then 44 else 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, plan.hitbox.Y / 2 + 1.4, 0)
	gui.MaxDistance = if opts.boss then 160 else 90
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.58, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = if opts.boss then Color3.fromRGB(255, 120, 110) else Color3.fromRGB(255, 244, 217)
	label.TextStrokeTransparency = 0.35
	label.Text = "[Lv " .. opts.level .. "] " .. name
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.new(0.08, 0, 0.66, 0)
	back.Size = UDim2.new(0.84, 0, 0.26, 0)
	back.BackgroundColor3 = Color3.fromRGB(9, 25, 35)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(249, 204, 119)
	stroke.Thickness = 1
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = barColor(1)
	fill.Parent = back
	corner:Clone().Parent = fill
	model:SetAttribute("MonsterId", opts.id)
	model:SetAttribute("DisplayName", name)
	model:SetAttribute("Level", opts.level)
	model:SetAttribute("MaxHealth", opts.hp)
	model:SetAttribute("Health", opts.hp)
	model:SetAttribute("Color", opts.color)
	if opts.boss then
		model:SetAttribute("Boss", true)
		model:SetAttribute("OwnerUserId", opts.owner.UserId)
		model:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + C.BOSS_DURATION)
	end
	CollectionService:AddTag(model, "IsleMonster")
	return model, root, {label = label, fill = fill, welds = welds}
end

local function place(r)
	local v = view[r]
	if not v then return end
	local t = os.clock() + v.phase
	local plan = v.plan
	local bob = if plan.flying then math.sin(t * 2) * 0.5 * plan.scale else math.sin(t * 3) * 0.08 * plan.scale
	local lunge = 0
	if r.lungeUntil and os.clock() < r.lungeUntil then
		lunge = math.sin((r.lungeUntil - os.clock()) / 0.25 * math.pi) * 1.2 * plan.scale
	end
	v.root.CFrame = CFrame.new(r.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, r.yaw, 0) * CFrame.new(0, 0, -lunge)
end

local axes = {X = function(a) return CFrame.Angles(a, 0, 0) end, Y = function(a) return CFrame.Angles(0, a, 0) end, Z = function(a) return CFrame.Angles(0, 0, a) end}
local function animate(r, moving)
	local v = view[r]
	if not v or #v.welds == 0 then return end
	local t = os.clock() + v.phase
	local gait = if moving then math.sin(t * 9) * 0.55 else 0
	for _, entry in ipairs(v.welds) do
		local spec = entry.spec
		local angle, c0 = 0, nil
		if spec.anim == "legA" then angle = gait
		elseif spec.anim == "legB" then angle = -gait
		elseif spec.anim == "wingL" then angle = math.sin(t * 8) * 0.5
		elseif spec.anim == "wingR" then angle = -math.sin(t * 8) * 0.5
		elseif spec.anim == "tail" then angle = math.sin(t * 4) * 0.35
		elseif spec.anim == "sway" then angle = math.sin(t * 2) * 0.18
		elseif spec.anim == "orbit" then c0 = CFrame.Angles(0, t * 1.6, 0) * spec.offset end
		if not c0 then
			local pivot = spec.pivot or Vector3.new(0, spec.size.Y / 2, 0)
			local axis = axes[spec.axis or (if spec.anim == "tail" then "Y" else "X")]
			c0 = spec.offset * CFrame.new(pivot) * axis(angle) * CFrame.new(-pivot)
		end
		entry.weld.C0 = c0
	end
end

local function destroyView(r, burst)
	local v = view[r]
	if not v then return end
	view[r] = nil
	if burst then
		broadcast(r.position, "death", {position = r.position, color = v.model:GetAttribute("Color"), boss = r.boss == true, scale = v.plan.scale})
	end
	v.model:SetAttribute("Health", 0)
	v.model:SetAttribute("Dead", true)
	local model = v.model
	task.delay(if burst then 0.12 else 0, function() model:Destroy() end)
end

local function spawnMarkerMonster(marker)
	local def = marker.def
	local plan = blueprint(BODY_KIND[marker.id] or "blob", def.color, false)
	local angle, dist = random:NextNumber(0, math.pi * 2), random:NextNumber(0, 6)
	local spot = marker.home + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local position = Vector3.new(spot.X, groundY(spot, marker.home.Y) + plan.hip, spot.Z)
	local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = marker.id, level = def.level, hp = def.hp, color = def.color})
	if not ok then
		warn("[Combat] could not build " .. marker.id .. ": " .. tostring(model))
		Logic.spawnFailed(marker)
		return
	end
	local r = Logic.register(marker, model, position, {radius = plan.radius})
	r.yaw = random:NextNumber(-math.pi, math.pi)
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = random:NextNumber(0, 10)}
	place(r)
	model.Parent = folder
end

local function spawnBoss(player, spec)
	local _, _, hrp = characterOf(player)
	if not hrp then return end
	local plan = blueprint(spec.kind, spec.color, true)
	local spot = hrp.Position + hrp.CFrame.LookVector * 16
	local position = Vector3.new(spot.X, groundY(spot, hrp.Position.Y - 3) + plan.hip, spot.Z)
	local ok, model, root, parts = pcall(buildModel, spec.name, plan, {id = "Boss:" .. spec.line, level = spec.level, hp = spec.hp, color = spec.color, boss = true, owner = player})
	if not ok then
		warn("[Combat] could not build slayer boss: " .. tostring(model))
		return
	end
	local r = Logic.registerBoss(player, spec, model, position, {radius = plan.radius})
	if not r then model:Destroy() return end
	r.yaw = math.atan2(-(hrp.Position.X - position.X), -(hrp.Position.Z - position.Z))
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = 0}
	place(r)
	model.Parent = folder
	broadcast(position, "bossSpawn", {position = position, name = spec.name, owner = player.UserId, color = spec.color})
end

-- Spawn markers --------------------------------------------------------------
local markerConnections = {} -- [marker part] = connection
local function addMarker(part)
	if not part:IsA("BasePart") or Logic.marker(part) then return end
	local monsterId = part:GetAttribute("MonsterId")
	if type(monsterId) ~= "string" or not Data.Monsters[monsterId] then
		-- The World team may set attributes after parenting; retry on change.
		if not markerConnections[part] then
			markerConnections[part] = part:GetAttributeChangedSignal("MonsterId"):Connect(function()
				if markerConnections[part] then markerConnections[part]:Disconnect(); markerConnections[part] = nil end
				addMarker(part)
			end)
		end
		return
	end
	local home = Vector3.new(part.Position.X, groundY(part.Position, part.Position.Y), part.Position.Z)
	Logic.addMarker(part, monsterId, part:GetAttribute("Count"), home, part:GetAttribute("Region"))
end
local function removeMarker(part)
	if markerConnections[part] then markerConnections[part]:Disconnect(); markerConnections[part] = nil end
	for _, r in ipairs(Logic.removeMarker(part)) do destroyView(r, false) end
end
task.spawn(function()
	local spawns = Workspace:WaitForChild("MonsterSpawns", math.huge)
	spawnsFolder = spawns
	refreshRayFilter()
	spawns.ChildAdded:Connect(function(child) task.defer(addMarker, child) end)
	spawns.ChildRemoved:Connect(removeMarker)
	for _, child in ipairs(spawns:GetChildren()) do addMarker(child) end
end)

-- Player attacks -------------------------------------------------------------
combatRemote.OnServerEvent:Connect(function(player, verb, target)
	if typeof(target) ~= "Instance" then return end
	local result = Logic.attack(player, verb, target)
	if not result then return end
	local r = result.record
	updateBar(r)
	broadcast(r.position, "hit", {model = r.model, position = r.position + Vector3.new(0, (view[r] and view[r].plan.hitbox.Y or 3) / 2, 0),
		amount = result.damage, crit = result.crit, attacker = player.UserId})
	if result.killed then destroyView(r, true) end
end)

-- Slayer bosses --------------------------------------------------------------
local playerConnections = {} -- [player] = {connection...}
local function onBossAttribute(player)
	local action, payload = Logic.bossAttribute(player, player:GetAttribute("SlayerBossReady"))
	if action == "cancel" and payload then destroyView(payload, false) end
end
local function onPlayerAdded(player)
	playerConnections[player] = {
		player:GetAttributeChangedSignal("SlayerBossReady"):Connect(function() onBossAttribute(player) end),
		player.CharacterAdded:Connect(function() task.defer(refreshRayFilter) end),
	}
	onBossAttribute(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, player) end
Players.PlayerRemoving:Connect(function(player)
	for _, connection in ipairs(playerConnections[player] or {}) do connection:Disconnect() end
	playerConnections[player] = nil
	for _, r in ipairs(Logic.playerRemoving(player)) do destroyView(r, false) end
	task.defer(refreshRayFilter)
end)

-- One loop for all AI --------------------------------------------------------
local AI_STEP = 1 / 15
local accumulator, housekeeping = 0, 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < AI_STEP then return end
	local step = math.min(accumulator, 0.25)
	accumulator = 0
	housekeeping += step
	if housekeeping >= 0.5 then
		housekeeping = 0
		for _, marker in ipairs(Logic.dueSpawns()) do spawnMarkerMonster(marker) end
		for _, pending in ipairs(Logic.pendingBosses()) do spawnBoss(pending.player, pending.spec) end
	end
	for _, failed in ipairs(Logic.bossTick()) do
		if failed.player.Parent then fxRemote:FireClient(failed.player, "bossFail", {reason = failed.reason}) end
		destroyView(failed.record, false)
	end
	for _, r in ipairs(Logic.records()) do
		local v = view[r]
		if v then
			local action = Logic.think(r)
			if action.kind ~= "sleep" then
				local moved = false
				if action.goal then
					moved = Logic.step(r, action.goal, action.speed, step, action.stop)
					if moved then
						local y = groundY(r.position, r.position.Y - v.plan.hip)
						r.position = Vector3.new(r.position.X, y + v.plan.hip, r.position.Z)
					end
				elseif action.face then
					local d = action.face - r.position
					if d.Magnitude > 0.1 then r.yaw = math.atan2(-d.X, -d.Z) end
				end
				if action.healed then updateBar(r) end
				place(r)
				animate(r, moved)
			end
		end
	end
end)

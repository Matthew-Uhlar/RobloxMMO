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
--   * Sea creatures (Data.SeaCreatures) are hooked by the Adventure script on a
--     Fishing gather. It sets player attributes SeaCreatureAt (Vector3, the fishing
--     node) and then SeaCreatureSpawn = "<id>:<seq>" (seq strictly increasing per
--     player). Combat spawns the creature beside the node, owned by that player;
--     at most Data.SeaCreatureCap per owner and C.SEA_MAX server-wide. Anyone may
--     fight it, but only the owner is credited: alive, within C.CREDIT_RANGE, has
--     dealt damage, and (Ironman) the sole contributor. A kill reports bridge
--     "seaCreature" {seq, monster, result="kill"}; an uncredited kill, a refused
--     spawn or C.SEA_DURATION (90 s) without a kill reports result="despawn".
--     The owner leaving despawns silently (the server forgets their tickets).
--   * Combat styles (melee / ranged / magic, Data.CombatStyles). One weapon slot;
--     the style comes from the wielded weapon (Progression.weaponStyle), arrows
--     sit in the "ammo" equipment slot. IsleCombat verbs:
--       ("attack", model)              melee, unchanged; refused ("style") while a
--                                      bow, staff or wand is wielded
--       ("ranged", model)              bow shot: range = bow reach (<= 40 studs),
--                                      line of sight, ammo tier <= bow maxAmmoTier,
--                                      one arrow consumed via bridge "consume",
--                                      cooldown = bow speed / (1 + Attack Speed%)
--       ("cast", model|nil, spellId?)  spell (nil/"" = the profile's autocast):
--                                      Magic level, magic weapon (damage/snare),
--                                      range + line of sight, mana, glyphs (a staff
--                                      supplies its elements), cooldowns
--     Damage XP (OSRS model): every hit accrues the damage it actually removed on
--     the monster record (r.contributors[player] = {damage, xp = {[style] = dmg}});
--     when the monster dies each credited contributor gets bridge "combatXp"
--     {style, monster, tier, damage} per style (melee -> Combat, ranged -> Ranged,
--     magic -> Magic, plus a 1/3 Combat share). A leash heal or a despawn
--     discards the accrual, and leashing monsters cannot be targeted at all.
--     A spell's cast XP is still immediate ({style = "magic", spell}). Hubward
--     pays its tablet first, then teleports (refunded through bridge "refund"
--     if the teleport fails), and is refused during an agility move. Monsters take +30% from their weakness and -30% from their
--     defenceStyle (Progression.styleModifier). Mana lives here, per session:
--     max = Intelligence, regenerating Data.CombatStyles.manaRegenPercent of max
--     per second, replicated as player attributes Mana / MaxMana. Refusals with a
--     player-facing reason fire IsleCombatFx "denied" {action, reason}.
--   * Skill Mastery perks (bridge "stats" -> mastery = Progression.masteryCombat;
--     arrow/glyph save and XP boost are applied by the bridge itself):
--       firstStrike (melee, ranged)  % chance that a player's first landed hit on a
--                                    monster at full health crits. Rolled once per
--                                    monster per player (r.opened), even if it fails.
--       execute (melee, ranged)      +% raw damage while the target is strictly below
--                                    C.EXECUTE_THRESHOLD % of max health (before the hit).
--       manaThrift (magic)           mana cost = round(mana * (1 - thrift/100)), thrift
--                                    clamped to 0..100 so the cost never drops below 0.
--       multishot (ranged)           each shot also strikes up to multishot - 1 (capped at
--                                    C.MULTISHOT_MAX - 1) more monsters within
--                                    C.MULTISHOT_RADIUS of the target, nearest first. Each
--                                    extra target passes the normal checks (alive, not
--                                    leashing, boss owner, bow reach, line of sight from
--                                    the shooter) and is never another Ironman's fight (nor,
--                                    for an Ironman shooter, anyone else's). Each extra
--                                    hit rolls accuracy/crit/perks and accrues damage XP
--                                    like a normal hit; one arrow and one cooldown per shot;
--                                    lifesteal heals on the first target only.
--     Capstones (Volley, Glyphstorm) are folded into those numbers by the bridge;
--     mastery.active[tree] = os.time expiry lets a cached snapshot drop a capstone
--     the moment it ends (env.time, default os.time).

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
	ACTIVE_RANGE = 120,         -- monsters with no player this close sleep (no CFrame writes)
	ANIMATE_RANGE = 80,         -- limb welds animate only with a player this close
	ANIMATE_STEP = 1 / 5,       -- limb animation rate (movement stays at the AI rate)
	BOSS_REARM_DELAY = 5,       -- re-read SlayerBossReady after an unapplied boss report
	SEA_RETRY_DELAY = 5,        -- resend an unapplied sea creature kill report
	SEA_REPORT_GRACE = 15,      -- ...until this long after the creature's lifetime (server ticket grace)
	DENIED_NOTICE_GAP = 3,      -- Slayer tasks: at most one "slayerDenied" bridge call per player per gap
	FX_RANGE = 110,
	MAX_RADIUS_BONUS = 6,
	DEFAULT_COUNT = 2,
	MAX_COUNT = 3,
	SEA_DURATION = 90,          -- sea creatures submerge after this long
	SEA_CAP = 3,                -- per owner (Data.SeaCreatureCap wins when present)
	SEA_MAX = 36,               -- server-wide live sea creatures
	SEA_OFFSET = 6,             -- studs from the fishing node
	MAX_RANGE = 40,             -- ranged / magic reach (Data.CombatStyles.maxRange wins when present)
	DENY_INTERVAL = 0.3,        -- min seconds between "denied" notices per player
	EYE_HEIGHT = 1.5,           -- line-of-sight rays start this far above the root
	MANA_REFRESH = 10,          -- seconds before the mana tick re-reads a player's max mana
	MANA_REFRESH_BUDGET = 4,    -- stats fetches the mana tick may make per tick
	EXECUTE_THRESHOLD = 30,     -- Skill Mastery execute: target strictly below this % of max health
	MULTISHOT_MAX = 3,          -- Skill Mastery multishot: never more targets per shot (Volley)
	MULTISHOT_RADIUS = 12,      -- extra multishot targets lie within this many studs of the first
}
-- Refusal reasons worth telling the player about (cooldown/target spam stays silent).
local DENY_REASONS = {style = true, weapon = true, ammo = true, ammoTier = true, sight = true, range = true,
	mana = true, glyphs = true, level = true, spell = true, immune = true, combat = true, teleport = true}

------------------------------------------------------------------------------
-- 2. Creature blueprints (pure). Forward is -Z, root sits `hip` above ground.
------------------------------------------------------------------------------
local BODY_KIND = {
	BramblebackBoar = "boar", Thornling = "thornling", ShaleCrawler = "crawler", CinderMite = "mite",
	BarkStalker = "stalker", GaleSprite = "sprite", BrassGolem = "golem", StormHarrier = "harrier",
	GloomfangSpider = "spider", VoidWisp = "wisp", ReefLurker = "lurker", TempestWraith = "wraith",
	StarbornSentinel = "sentinel",
	-- Endgame (the Shattered Crown)
	RiftmawStalker = "riftmaw", ShardglassSeer = "seer", CrownforgedColossus = "colossus", VoidcrownDrake = "drake",
}
local BOSS_BODY = {
	Bramble = {kind = "boar", speed = 13},
	Gloom = {kind = "spider", speed = 15},
	Tempest = {kind = "wraith", speed = 16},
}
local ROMAN = {"I", "II", "III", "IV", "V"}
-- Aquatic body plans used by Data.SeaCreatures[id].body.
local SEA_BODIES = {serpent = true, crab = true, ray = true, jelly = true}

-- Slayer tasks section (Slayer team): bodies of the slayer-only monsters
-- (Data.SlayerTasks.SlayerOnlyOrder). blueprint() calls SLAYER_BODY[kind](kit)
-- with its part helpers; each returns hip, hitbox, flying, light.
BODY_KIND.HollowcapShrieker, BODY_KIND.MirrorscaleBasilisk = "shrieker", "basilisk"
BODY_KIND.ThundercragGargant, BODY_KIND.UmbralDreadmaw = "gargant", "dreadmaw"
local SLAYER_BODY = {}
function SLAYER_BODY.shrieker(k)
	local V, CF, A, add = Vector3.new, CFrame.new, CFrame.Angles, k.add
	local spore = k.hex("E9F5B0")
	add("Stalk", "Cylinder", V(3.0, 1.5, 1.5), CF(0, -0.4, 0) * k.upright, k.light, "SmoothPlastic", "sway")
	add("Cap", "Cylinder", V(0.9, 4.4, 4.4), CF(0, 1.5, 0) * k.upright, k.base)
	add("Dome", "Ball", V(3.0, 3.0, 3.0), CF(0, 1.9, 0), k.base)
	add("Gills", "Cylinder", V(0.3, 3.6, 3.6), CF(0, 0.95, 0) * k.upright, k.dark, "Fabric")
	k.eyes(0.45, 0.2, -0.78, 0.32)
	add("Mouth", "Block", V(0.9, 0.35, 0.2), CF(0, -0.45, -0.72), k.dark, "Neon")
	for i = 1, 5 do
		add("Spot" .. i, "Ball", V(0.6, 0.6, 0.6), A(0, (i - 1) * 2 * math.pi / 5, 0) * CF(1.6, 2.4, 0), spore, "Neon")
	end
	for i = 1, 3 do
		add("Root" .. i, "Wedge", V(0.5, 1.0, 1.4), A(0, (i - 1) * 2 * math.pi / 3, 0) * CF(0, -1.7, -0.9), k.dark, "Wood")
	end
	return 2.2, V(4.4, 5, 4.4), false, spore
end
function SLAYER_BODY.basilisk(k)
	local V, CF, add = Vector3.new, CFrame.new, k.add
	local mirror = k.hex("E9FBFF")
	add("Body", "Cylinder", V(5.0, 1.8, 1.8), CF(0, 0, 0.2) * k.alongZ, k.base)
	add("Head", "Block", V(1.4, 1.1, 1.8), CF(0, 0.3, -3.1), k.base)
	add("Jaw", "Wedge", V(1.2, 0.4, 1.4), CF(0, -0.25, -3.3) * CFrame.Angles(math.pi, 0, 0), k.dark)
	k.eyes(0.45, 0.55, -4.02, 0.3)
	for i, z in ipairs({-1.6, 1.6}) do
		add("LegL" .. i, "Block", V(0.5, 1.2, 0.5), CF(-1.0, -0.8, z), k.dark, nil, if i == 1 then "legA" else "legB")
		add("LegR" .. i, "Block", V(0.5, 1.2, 0.5), CF(1.0, -0.8, z), k.dark, nil, if i == 1 then "legB" else "legA")
	end
	add("Tail", "Cylinder", V(3.2, 0.6, 0.6), CF(0, 0, 3.9) * k.alongZ, k.base, nil, "tail", {pivot = V(-1.6, 0, 0)})
	for i = 1, 4 do
		add("Mirror" .. i, "Cylinder", V(0.12, 1.0, 1.0), CF(0, 1.0, -1.8 + i * 0.9) * CFrame.Angles(0, math.pi / 2, 0), mirror, "Glass", nil, {transparency = 0.15})
	end
	add("Crest", "Wedge", V(0.25, 0.8, 1.2), CF(0, 1.05, -2.9), k.light, "Glass")
	return 1.4, V(3, 2.8, 8.4), false, mirror
end
function SLAYER_BODY.gargant(k)
	local V, CF, add = Vector3.new, CFrame.new, k.add
	local bolt = k.hex("BFE4FF")
	add("Torso", "Block", V(4.6, 4.0, 3.0), CF(0, 1.0, 0), k.base, "Slate")
	add("Head", "Block", V(2.0, 1.6, 1.8), CF(0, 3.8, -0.3), k.dark, "Slate")
	k.eyes(0.45, 3.9, -1.22, 0.32, bolt)
	add("ArmL", "Block", V(1.5, 4.0, 1.5), CF(-3.0, 0.6, 0), k.base, "Slate", "legB", {pivot = V(0, 2.0, 0)})
	add("ArmR", "Block", V(1.5, 4.0, 1.5), CF(3.0, 0.6, 0), k.base, "Slate", "legA", {pivot = V(0, 2.0, 0)})
	add("FistL", "Ball", V(2.0, 2.0, 2.0), CF(-3.0, -1.9, 0), k.dark, "Slate", "legB", {pivot = V(0, 4.5, 0)})
	add("FistR", "Ball", V(2.0, 2.0, 2.0), CF(3.0, -1.9, 0), k.dark, "Slate", "legA", {pivot = V(0, 4.5, 0)})
	add("LegL", "Block", V(1.7, 2.6, 1.8), CF(-1.1, -2.3, 0), k.base, "Slate", "legA")
	add("LegR", "Block", V(1.7, 2.6, 1.8), CF(1.1, -2.3, 0), k.base, "Slate", "legB")
	for i = 1, 3 do
		add("Bolt" .. i, "Wedge", V(0.4, 1.4, 0.7), CF((i - 2) * 1.3, 3.4 + (i % 2) * 0.3, 1.0), bolt, "Neon")
	end
	add("Thunderhead", "Ball", V(2.6, 2.6, 2.6), CF(0, 5.4, 0.4), k.light, "Glass", "orbit", {transparency = 0.35})
	return 4.0, V(6.4, 9, 4), false, bolt
end
function SLAYER_BODY.dreadmaw(k)
	local V, CF, A, add = Vector3.new, CFrame.new, CFrame.Angles, k.add
	local glow = k.hex("C77DFF")
	add("Body", "Cylinder", V(4.4, 2.4, 2.4), CF(0, 0.2, 0.4) * k.alongZ, k.base)
	add("Chest", "Ball", V(2.8, 2.8, 2.8), CF(0, 0.5, -1.7), k.base)
	add("Head", "Block", V(1.8, 1.5, 2.2), CF(0, 1.0, -3.3), k.dark)
	add("Maw", "Wedge", V(1.6, 0.6, 1.8), CF(0, 0.1, -3.6) * A(math.pi, 0, 0), k.dark)
	k.eyes(0.5, 1.3, -4.42, 0.3, glow)
	for i, z in ipairs({-1.5, 1.6}) do
		add("LegL" .. i, "Block", V(0.7, 1.9, 0.8), CF(-1.0, -1.2, z), k.dark, nil, if i == 1 then "legA" else "legB")
		add("LegR" .. i, "Block", V(0.7, 1.9, 0.8), CF(1.0, -1.2, z), k.dark, nil, if i == 1 then "legB" else "legA")
	end
	add("Tail", "Cylinder", V(2.4, 0.5, 0.5), CF(0, 0.7, 3.2) * A(0, math.pi / 2, math.rad(-20)), k.dark, nil, "tail")
	for i = 1, 4 do
		add("Shade" .. i, "Wedge", V(0.3, 1.4 - i * 0.15, 1.0), CF(0, 1.6, -2.2 + i * 0.9), k.light, "Glass", "sway", {transparency = 0.3})
	end
	add("Void", "Ball", V(1.0, 1.0, 1.0), CF(0, 0.5, -3.1), glow, "Neon")
	return 2.2, V(3.6, 4.2, 7.8), false, glow
end
-- End Slayer tasks section (bodies).

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
	elseif kind == "serpent" then
		hip, hitbox = 2.2, V(3, 4.4, 9.4)
		add("Head", "Ball", V(2.1, 2.1, 2.1), CF(0, 1.1, -3.7), base)
		add("Jaw", "Wedge", V(1.6, 0.6, 1.4), CF(0, 0.2, -4.3) * A(pi, 0, 0), dark)
		eyes(0.6, 1.5, -4.45, 0.32, hexColor("F6FF8F"))
		add("HornL", "Wedge", V(0.25, 0.9, 0.9), CF(-0.6, 2.2, -3.4) * A(math.rad(-30), 0, 0), light)
		add("HornR", "Wedge", V(0.25, 0.9, 0.9), CF(0.6, 2.2, -3.4) * A(math.rad(-30), 0, 0), light)
		add("WhiskerL", "Cylinder", V(1.4, 0.12, 0.12), CF(-0.9, 0.7, -4.5) * A(0, math.rad(30), math.rad(-20)), light, nil, "sway")
		add("WhiskerR", "Cylinder", V(1.4, 0.12, 0.12), CF(0.9, 0.7, -4.5) * A(0, math.rad(-30), math.rad(-20)), light, nil, "sway")
		for i = 1, 5 do
			local s = 1.9 - i * 0.22
			local z = -2.3 + i * 1.25
			add("Coil" .. i, "Ball", V(s, s, s), CF(0, 0.6 * math.sin(i * 1.3), z), if i % 2 == 0 then light else base, nil, if i >= 3 then "tail" else nil, {pivot = V(0, 0, -z - 2.3), axis = "Y"})
			if i <= 3 then add("Fin" .. i, "Wedge", V(0.2, 0.8, 0.9), CF(0, 0.6 * math.sin(i * 1.3) + s / 2 + 0.2, z), hexColor("9EE7D2"), "Glass") end
		end
		add("Fluke", "Wedge", V(0.2, 1.4, 1.3), CF(0, 0.2, 4.6) * A(0, pi, 0), light, nil, "tail", {pivot = V(0, 0, -6.9), axis = "Y"})
	elseif kind == "crab" then
		hip, hitbox = 1.4, V(6.2, 2.8, 4.4)
		add("Shell", "Cylinder", V(1.0, 3.6, 3.6), CF(0, 0.1, 0) * upright, base, "Slate")
		add("Dome", "Ball", V(2.6, 2.6, 2.6), CF(0, 0.45, 0.1), light)
		add("StalkL", "Cylinder", V(0.8, 0.18, 0.18), CF(-0.45, 1.0, -1.55) * upright, dark)
		add("StalkR", "Cylinder", V(0.8, 0.18, 0.18), CF(0.45, 1.0, -1.55) * upright, dark)
		eyes(0.45, 1.5, -1.55, 0.34, hexColor("FFE680"))
		for side, sx in ipairs({-1, 1}) do
			local tag = if side == 1 then "L" else "R"
			local swing = if side == 1 then "wingL" else "wingR"
			add("Arm" .. tag, "Block", V(1.4, 0.45, 0.45), CF(sx * 2.2, 0, -1.4) * A(0, sx * math.rad(35), 0), dark)
			add("Pincer" .. tag, "Wedge", V(0.6, 0.6, 1.3), CF(sx * 2.7, 0.25, -2.1), base, nil, swing, {pivot = V(0, -0.3, 0.6), axis = "X"})
			add("Grip" .. tag, "Wedge", V(0.6, 0.4, 1.1), CF(sx * 2.7, -0.25, -2.05) * A(pi, 0, 0), light)
			for i, z in ipairs({-0.5, 0.4, 1.3}) do
				add("Leg" .. tag .. i, "Block", V(1.5, 0.22, 0.22), CF(sx * 2.0, -0.65, z) * A(0, 0, sx * math.rad(-30)), dark, nil, if (i + side) % 2 == 0 then "legA" else "legB", {pivot = V(-sx * 0.75, 0, 0), axis = "Y"})
			end
		end
	elseif kind == "ray" then
		hip, hitbox, flying = 2.8, V(7.4, 1.8, 5.4), true
		add("Body", "Block", V(2.4, 0.7, 3.6), CF(0, 0, 0), base)
		add("Belly", "Block", V(2.0, 0.3, 3.0), CF(0, -0.45, 0), hexColor("F1F7FB"))
		add("WingL", "Wedge", V(0.3, 2.6, 3.2), CF(-2.4, 0, 0.1) * A(0, 0, math.rad(90)), base, nil, "wingL", {pivot = V(0, -1.3, 0), axis = "Z"})
		add("WingR", "Wedge", V(0.3, 2.6, 3.2), CF(2.4, 0, 0.1) * A(0, 0, math.rad(-90)), base, nil, "wingR", {pivot = V(0, -1.3, 0), axis = "Z"})
		add("TipL", "Wedge", V(0.25, 0.9, 1.0), CF(-3.6, 0.1, 1.2) * A(0, 0, math.rad(90)), dark, nil, "wingL", {pivot = V(0, -2.5, 0), axis = "Z"})
		add("TipR", "Wedge", V(0.25, 0.9, 1.0), CF(3.6, 0.1, 1.2) * A(0, 0, math.rad(-90)), dark, nil, "wingR", {pivot = V(0, -2.5, 0), axis = "Z"})
		add("HornL", "Wedge", V(0.25, 0.5, 0.8), CF(-0.75, 0.05, -2.1), dark)
		add("HornR", "Wedge", V(0.25, 0.5, 0.8), CF(0.75, 0.05, -2.1), dark)
		eyes(0.85, 0.4, -1.5, 0.3, hexColor("BFF7E6"))
		add("SpotA", "Ball", V(0.4, 0.4, 0.4), CF(-0.5, 0.35, 0.6), hexColor("BFF7E6"), "Neon")
		add("SpotB", "Ball", V(0.4, 0.4, 0.4), CF(0.5, 0.35, 0.9), hexColor("BFF7E6"), "Neon")
		add("Tail", "Cylinder", V(3.2, 0.2, 0.2), CF(0, 0, 3.4) * alongZ, dark, nil, "tail", {pivot = V(-1.6, 0, 0)})
		add("Barb", "Wedge", V(0.2, 0.4, 0.7), CF(0, 0.15, 4.9), light, nil, "tail", {pivot = V(0, 0, -3.1), axis = "Y"})
		light3 = hexColor("BFF7E6")
	elseif kind == "jelly" then
		hip, hitbox, flying = 3.4, V(3.8, 5.6, 3.8), true
		add("Bell", "Ball", V(3.2, 3.2, 3.2), CF(0, 1.2, 0), base, "Glass", nil, {transparency = 0.25})
		add("Core", "Ball", V(1.4, 1.4, 1.4), CF(0, 1.1, 0), light, "Neon")
		add("Rim", "Cylinder", V(0.3, 3.4, 3.4), CF(0, 0.05, 0) * upright, dark, "Glass", nil, {transparency = 0.2})
		eyes(0.45, 1.4, -1.45, 0.26, hexColor("FFFFFF"))
		for i = 1, 6 do
			local a = (i - 1) * pi / 3
			add("Tentacle" .. i, "Cylinder", V(2.4 + (i % 2) * 0.6, 0.2, 0.2), A(0, a, 0) * CF(1.0, -1.3, 0) * upright, light, "Neon", "sway", {transparency = 0.3, pivot = V(1.2, 0, 0)})
		end
		for i = 1, 4 do
			add("Frill" .. i, "Wedge", V(0.2, 0.6, 0.8), A(0, (i - 1) * pi / 2 + pi / 4, 0) * CF(0, 0.1, -1.75), base, "Glass", "orbit", {transparency = 0.3})
		end
		light3 = light
	-- Endgame (the Shattered Crown): four regional bodies and two world bosses.
	elseif kind == "riftmaw" then
		hip, hitbox = 2.2, V(3.6, 4.2, 7.2)
		local rift = hexColor("C77DFF")
		add("Body", "Block", V(2.6, 2.2, 4.6), CF(0, 0.2, 0.2), base)
		add("Chest", "Ball", V(2.8, 2.8, 2.8), CF(0, 0.45, -1.9), base)
		add("Head", "Block", V(1.8, 1.5, 2.0), CF(0, 1.0, -3.4), dark)
		add("Jaw", "Wedge", V(1.6, 0.6, 1.6), CF(0, 0.05, -3.7) * A(pi, 0, 0), dark)
		eyes(0.5, 1.3, -4.42, 0.3, if boss then eye else rift)
		for i, z in ipairs({-1.6, 1.6}) do
			add("LegL" .. i, "Block", V(0.7, 1.9, 0.8), CF(-1.0, -1.25, z), dark, nil, if i == 1 then "legA" else "legB")
			add("LegR" .. i, "Block", V(0.7, 1.9, 0.8), CF(1.0, -1.25, z), dark, nil, if i == 1 then "legB" else "legA")
		end
		for i = 1, 4 do
			add("Spine" .. i, "Wedge", V(0.35, 1.5 - i * 0.2, 0.9), CF(0, 1.9 - i * 0.12, -1.6 + i * 0.9), light, "Glass")
		end
		add("Rift", "Block", V(0.22, 0.3, 3.4), CF(0, 1.35, 0.2), rift, "Neon")
		add("Tail", "Cylinder", V(2.0, 0.4, 0.4), CF(0, 0.6, 3.1) * A(0, pi / 2, math.rad(-25)), dark, nil, "tail")
		light3 = rift
	elseif kind == "seer" then
		hip, hitbox, flying = 3.2, V(3.4, 6.2, 3.4), true
		add("Robe", "Cylinder", V(2.6, 2.6, 2.6), CF(0, -0.5, 0) * upright, base, "Glass", nil, {transparency = 0.1})
		add("Veil", "Ball", V(2.4, 2.4, 2.4), CF(0, -1.9, 0), light, "Glass", "sway", {transparency = 0.35})
		add("Head", "Ball", V(1.5, 1.5, 1.5), CF(0, 1.55, 0), light, "Glass")
		add("Hood", "Wedge", V(1.8, 1.2, 1.8), CF(0, 2.35, 0.1), dark, "Fabric")
		eyes(0.3, 1.6, -0.68, 0.22, if boss then eye else hexColor("FFFFFF"))
		add("SleeveL", "Cylinder", V(1.6, 0.5, 0.5), CF(-1.4, 0.3, -0.3) * A(0, 0, math.rad(-35)), base, "Glass", "wingL", {pivot = V(0.8, 0, 0), axis = "Z"})
		add("SleeveR", "Cylinder", V(1.6, 0.5, 0.5), CF(1.4, 0.3, -0.3) * A(0, 0, math.rad(-145)), base, "Glass", "wingR", {pivot = V(-0.8, 0, 0), axis = "Z"})
		for i = 1, 5 do
			add("Lens" .. i, "Cylinder", V(0.15, 1.0, 1.0), A(0, (i - 1) * 2 * pi / 5, 0) * CF(2.2, 0.6 + (i % 2) * 0.5, 0), hexColor("E9FBFF"), "Glass", "orbit", {transparency = 0.2})
		end
		add("Halo", "Cylinder", V(0.12, 2.4, 2.4), CF(0, 2.9, 0.2) * upright, hexColor("BFF4FF"), "Neon", nil, {transparency = 0.3})
		light3 = hexColor("BFF4FF")
	elseif kind == "colossus" then
		hip, hitbox = 4.6, V(6.2, 9.2, 4)
		local core = hexColor("FFB347")
		add("Torso", "Block", V(4.2, 3.6, 2.8), CF(0, 1.0, 0), base, "Metal")
		add("Core", "Ball", V(1.3, 1.3, 1.3), CF(0, 1.2, -1.35), core, "Neon")
		add("Head", "Block", V(1.8, 1.5, 1.7), CF(0, 3.6, -0.2), dark, "Metal")
		add("Visor", "Block", V(1.4, 0.3, 0.12), CF(0, 3.7, -1.08), core, "Neon")
		for i = 1, 3 do
			add("Spike" .. i, "Wedge", V(0.4, 1.2 - math.abs(i - 2) * 0.35, 0.8), CF((i - 2) * 0.6, 4.75, -0.2), light, "Glass")
		end
		add("ShoulderL", "Ball", V(1.9, 1.9, 1.9), CF(-2.6, 2.4, 0), dark, "Metal")
		add("ShoulderR", "Ball", V(1.9, 1.9, 1.9), CF(2.6, 2.4, 0), dark, "Metal")
		add("ArmL", "Block", V(1.3, 3.4, 1.3), CF(-2.8, 0.4, 0), base, "Metal", "legB", {pivot = V(0, 1.7, 0)})
		add("ArmR", "Block", V(1.3, 3.4, 1.3), CF(2.8, 0.4, 0), base, "Metal", "legA", {pivot = V(0, 1.7, 0)})
		add("FistL", "Block", V(1.7, 1.5, 1.7), CF(-2.8, -1.9, 0), dark, "Metal", "legB", {pivot = V(0, 4.0, 0)})
		add("FistR", "Block", V(1.7, 1.5, 1.7), CF(2.8, -1.9, 0), dark, "Metal", "legA", {pivot = V(0, 4.0, 0)})
		add("LegL", "Block", V(1.5, 2.8, 1.6), CF(-1.0, -2.6, 0), base, "Metal", "legA")
		add("LegR", "Block", V(1.5, 2.8, 1.6), CF(1.0, -2.6, 0), base, "Metal", "legB")
		light3 = core
	elseif kind == "drake" or kind == "wyrm" then
		local wyrm = kind == "wyrm"
		hip, hitbox, flying = 3.6, if wyrm then V(5.4, 4.4, 10) else V(5, 4, 9), true
		local glow = hexColor(if wyrm then "B48CFF" else "8E7CF0")
		add("Body", "Cylinder", V(4.2, 2.2, 2.2), CF(0, 0, 0.4) * alongZ, base)
		add("Neck", "Cylinder", V(2.0, 1.1, 1.1), CF(0, 0.9, -2.1) * A(0, pi / 2, math.rad(-30)), base)
		add("Head", "Block", V(1.3, 1.1, 1.9), CF(0, 1.55, -3.4), dark)
		add("Jaw", "Wedge", V(1.1, 0.4, 1.4), CF(0, 0.95, -3.7) * A(pi, 0, 0), dark)
		eyes(0.45, 1.75, -4.3, 0.24, if boss then eye else glow)
		add("HornL", "Wedge", V(0.2, 0.9, 0.6), CF(-0.45, 2.3, -2.9), light)
		add("HornR", "Wedge", V(0.2, 0.9, 0.6), CF(0.45, 2.3, -2.9), light)
		add("WingL", "Block", V(3.2, 0.18, 2.2), CF(-2.4, 0.6, 0.2), dark, nil, "wingL", {pivot = V(1.6, 0, 0), axis = "Z"})
		add("WingR", "Block", V(3.2, 0.18, 2.2), CF(2.4, 0.6, 0.2), dark, nil, "wingR", {pivot = V(-1.6, 0, 0), axis = "Z"})
		add("Tail", "Cylinder", V(3.0, 0.6, 0.6), CF(0, 0.1, 3.6) * alongZ, base, nil, "tail", {pivot = V(-1.5, 0, 0)})
		add("TailBlade", "Wedge", V(0.2, 0.8, 1.0), CF(0, 0.3, 5.2), glow, "Neon", "tail", {pivot = V(0, 0, -3.1), axis = "Y"})
		add("Belly", "Block", V(1.2, 0.2, 2.6), CF(0, -1.05, 0.3), glow, "Neon")
		if wyrm then
			add("WingL2", "Block", V(2.4, 0.16, 1.6), CF(-2.0, 0.3, 1.8), light, nil, "wingL", {pivot = V(1.2, 0, 0), axis = "Z"})
			add("WingR2", "Block", V(2.4, 0.16, 1.6), CF(2.0, 0.3, 1.8), light, nil, "wingR", {pivot = V(-1.2, 0, 0), axis = "Z"})
			for i = 1, 3 do
				add("Mane" .. i, "Wedge", V(0.18, 0.7, 0.7), CF(0, 1.35 - i * 0.2, -1.6 + i * 0.9), glow, "Glass")
			end
		end
		light3 = glow
	elseif kind == "sovereign" then
		hip, hitbox = 4.4, V(6, 9.4, 4)
		local gold = hexColor("FFE08A")
		add("Torso", "Block", V(3.8, 3.8, 2.4), CF(0, 1.0, 0), base, "Marble")
		add("Mantle", "Wedge", V(4.6, 1.6, 2.8), CF(0, 2.9, 0.1), dark, "Fabric")
		add("Heart", "Ball", V(1.2, 1.2, 1.2), CF(0, 1.4, -1.15), gold, "Neon")
		add("Head", "Ball", V(1.7, 1.7, 1.7), CF(0, 4.1, -0.1), light, "Glass")
		eyes(0.35, 4.15, -0.9, 0.26, if boss then eye else gold)
		add("Circlet", "Cylinder", V(0.25, 2.2, 2.2), CF(0, 4.9, -0.1) * upright, gold, "Metal")
		add("ArmL", "Block", V(1.1, 3.4, 1.1), CF(-2.5, 0.6, 0), base, "Marble", "legB", {pivot = V(0, 1.7, 0)})
		add("ArmR", "Block", V(1.1, 3.4, 1.1), CF(2.5, 0.6, 0), base, "Marble", "legA", {pivot = V(0, 1.7, 0)})
		add("Blade", "Block", V(0.35, 5.0, 0.9), CF(2.5, -1.6, -0.9), gold, "Glass", "legA", {pivot = V(0, 3.9, 0.9)})
		for i = 1, 4 do
			add("Shard" .. i, "Wedge", V(0.6, 1.6, 0.7), A(0, (i - 1) * pi / 2 + pi / 4, 0) * CF(3.6, 2.2, 0), light, "Glass", "orbit")
		end
		add("Robe", "Wedge", V(3.6, 3.0, 2.6), CF(0, -1.9, 0) * A(0, pi, 0), dark, "Fabric", "sway")
		add("LegL", "Block", V(1.2, 2.4, 1.2), CF(-0.8, -3.2, 0), base, "Marble", "legA")
		add("LegR", "Block", V(1.2, 2.4, 1.2), CF(0.8, -3.2, 0), base, "Marble", "legB")
		light3 = gold
	elseif SLAYER_BODY[kind] then -- Slayer tasks section: slayer-only monster bodies
		hip, hitbox, flying, light3 = SLAYER_BODY[kind]({add = add, eyes = eyes, base = base, dark = dark, light = light, hex = hexColor, upright = upright, alongZ = alongZ})
	else
		hip, hitbox = 1.5, V(3, 3, 3)
		add("Body", "Ball", V(3, 3, 3), CF(0, 0, 0), base)
		eyes(0.5, 0.4, -1.4, 0.35)
		kind = "blob" -- §48: the client draws unknown bodies as the fallback slime rig
	end
	local scale = 1
	if boss then
		-- boss == "world": Endgame world bosses tower over slayer bosses.
		scale = if boss == "world" then 3.2 else 2.2
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
	-- §48: `kind` names the forged rig (art/CreatureCatalog.lua rigs) the
	-- client draws over these primitives (CreatureRig / CreatureScale attributes).
	return {kind = kind, parts = parts, hip = hip, hitbox = hitbox, flying = flying, scale = scale, light = light3,
		radius = math.min(C.MAX_RADIUS_BONUS, math.max(hitbox.X, hitbox.Z) / 2)}
end

------------------------------------------------------------------------------
-- 3. Pure rules
------------------------------------------------------------------------------
-- env = {Data, Progression, bridge(op, player, payload), now(), rng(),
--        position(player) -> Vector3?, alive(player) -> bool, players() -> {player},
--        heal(player, percentOfMaxHealth)}
-- bridge(op, player, payload, done?) may answer later through done(reply).
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
	local rearm = {}         -- [player] = time to re-read SlayerBossReady
	local seaRetry = {}      -- [player] = {[seq] = {id, seq, at, deadline}} unapplied kill reports
	local seaOwned = {}      -- [player] = {[record] = true}
	local seaSeq = {}        -- [player] = last accepted SeaCreatureSpawn sequence
	local seaLive = 0
	local liveCount = 0
	local mana = {}          -- [player] = {current, max, at, sentMana, sentMax}
	local spellReady = {}    -- [player] = {[spellId] = time}
	local lastHurt = {}      -- [player] = time last struck by a monster
	local worldBossLive = {} -- [bossId] = record (World Boss section, below)
	local CS = Data.CombatStyles or {}
	local maxRange = math.min(C.MAX_RANGE, tonumber(CS.maxRange) or C.MAX_RANGE)
	L.maxRange = maxRange
	-- One snapshot of every player per AI tick, shared by all monsters.
	local tick = nil         -- {list, alive = {[player] = bool}, pos = {[player] = Vector3?}}

	local function flat(v) return Vector3.new(v.X, 0, v.Z) end
	local function flatDist(a, b) return (flat(a) - flat(b)).Magnitude end
	L.flatDist = flatDist

	-- Per-tick player snapshot ----------------------------------------------
	function L.beginTick()
		local list, alive, pos = {}, {}, {}
		for _, player in ipairs(env.players()) do
			table.insert(list, player)
			alive[player] = env.alive(player) == true
			pos[player] = env.position(player)
		end
		tick = {list = list, alive = alive, pos = pos}
	end
	function L.endTick() tick = nil end
	local function playerList() return if tick then tick.list else env.players() end
	local function isAlive(player)
		if tick and tick.alive[player] ~= nil then return tick.alive[player] end
		return env.alive(player)
	end
	local function positionOf(player)
		if tick and tick.alive[player] ~= nil then return tick.pos[player] end
		return env.position(player)
	end
	function L.nearestPlayerDistance(r)
		local best = math.huge
		for _, player in ipairs(playerList()) do
			local pos = positionOf(player)
			if pos then best = math.min(best, (pos - r.position).Magnitude) end
		end
		return best
	end

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
		-- Accrue mana up to now under the old (cached) Hearthsong multiplier before
		-- the fresh snapshot replaces it, so a new multiplier is never retroactive.
		if mana[player] then L.manaOf(player) end
		statsCache[player] = {value = value, at = now}
		-- Every fresh stats fetch also refreshes the player's max mana.
		if value then L.manaOf(player, value.stats) end
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
		if not def or def.seaCreature or def.worldBoss then return nil, "unknown monster" end
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
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
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
		-- World Boss section: the boss itself and its add waves never respawn.
		if r.worldBoss then
			if worldBossLive[r.id] == r then worldBossLive[r.id] = nil end
			return
		end
		if r.add then
			if r.parent then r.parent.adds[r] = nil end
			return
		end
		if r.sea then
			local owned = seaOwned[r.owner]
			if owned and owned[r] then
				owned[r] = nil
				seaLive -= 1
				if not next(owned) then seaOwned[r.owner] = nil end
			end
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
	-- Shared target checks: live record, boss owner, attacker alive, reach.
	function L.validateTarget(player, target, range)
		local r = L.resolve(target)
		if not r or not r.alive then return false, "target" end
		-- A leashing monster is walking home to heal: it cannot be hit (no free XP).
		if r.leashing then return false, "leashing" end
		if r.boss and r.owner ~= player then return false, "owner" end
		if not env.alive(player) then return false, "dead" end
		local pos = env.position(player)
		if not pos then return false, "position" end
		if (pos - r.position).Magnitude - r.radius > range then return false, "range" end
		return true, r, pos
	end
	function L.validateAttack(player, verb, target)
		if type(verb) ~= "string" or verb ~= "attack" then return false, "verb" end
		local ok, r = L.validateTarget(player, target, C.ATTACK_RANGE)
		if not ok then return false, r end
		if env.now() < (nextAttack[player] or 0) - C.COOLDOWN_GRACE then return false, "cooldown" end
		return true, r
	end
	local function onCooldown(player)
		return env.now() < (nextAttack[player] or 0) - C.COOLDOWN_GRACE
	end
	-- Measured from the scheduled time, not the (possibly early) swing, so the
	-- latency grace never compounds into extra sustained DPS.
	local function scheduleNext(player, seconds)
		nextAttack[player] = math.max(env.now(), nextAttack[player] or 0) + seconds
	end
	function L.lineOfSight(from, r)
		if not env.lineOfSight then return true end
		return env.lineOfSight(from, r) ~= false
	end
	-- Triangle modifier, then the monster's defense.
	function L.mitigate(r, raw, style)
		local mult, tag = Progression.styleModifier(style, r)
		local dealt = Progression.damageTaken(math.floor(raw * mult), r.defense)
		-- World Boss ward: while an add wave lives the boss takes reduced damage.
		if r.worldBoss and next(r.adds) then dealt = math.floor(dealt * Data.Endgame.WARD) end
		return dealt, tag
	end
	-- Style XP for damage (and a spell's cast XP) through the bridge.
	function L.reportXp(player, r, style, damage, spellId)
		local payload = {style = style, spell = spellId}
		if r and damage and damage > 0 then payload.monster, payload.tier, payload.damage = r.id, r.tier, damage end
		if r and r.lair then payload.maxHp = r.maxHp end -- Lairs: damage XP caps at the party-scaled health
		if not payload.damage and not spellId then return end
		env.bridge("combatXp", player, payload)
	end
	-- Contribution record: {damage = total removed from hp, xp = {[style] = damage}}.
	-- Damage XP accrues here (capped by the hp actually removed) and is paid only
	-- when the monster dies (L.payXp); a leash heal or a despawn discards it.
	function L.contribution(r, player)
		local c = r.contributors[player]
		return if c then c.damage else 0
	end
	function L.landHit(player, r, dealt, style, spellId)
		local applied = math.max(0, math.min(dealt, r.hp))
		r.hp -= applied
		local c = r.contributors[player]
		if not c then
			c = {damage = 0, xp = {}}
			r.contributors[player] = c
		end
		c.damage += applied
		c.lastHit = env.now() -- World Boss credit: a recent hit is required at the kill
		if applied > 0 then c.xp[style] = (c.xp[style] or 0) + applied end
		if not r.boss and not r.target and not r.leashing then r.target = player end
		r.provoked = true
		-- Spell cast XP is immediate (it is paid for with glyphs and mana).
		if spellId then L.reportXp(player, nil, "magic", 0, spellId) end
		return applied
	end
	-- Pays each credited contributor the damage XP they accrued on r.
	local XP_STYLES = {"melee", "ranged", "magic"}
	function L.payXp(r, credited)
		for _, player in ipairs(credited) do
			local c = r.contributors[player]
			if c then
				for _, style in ipairs(XP_STYLES) do
					local damage = c.xp[style]
					if damage and damage > 0 then L.reportXp(player, r, style, damage) end
				end
			end
		end
	end
	local function finish(result, r)
		if r and r.hp <= 0 then
			result.killed = true
			result.credited = L.kill(r)
		end
		return result
	end
	local function loadoutOf(info)
		return if type(info.loadout) == "table" then info.loadout else {style = "melee", levels = {}, supplies = {}}
	end

	-- Skill Mastery perks ----------------------------------------------------
	local STYLE_TREE = {melee = "Melee", ranged = "Ranged", magic = "Magic"}
	local function wallClock() return if env.time then env.time() else os.time() end
	local function capstoneAbility(treeId)
		local MA = Data.Mastery
		local tree = MA and MA.TreeById and MA.TreeById[treeId]
		local node = tree and tree.capstone and tree.NodeById[tree.capstone]
		return node and node.ability
	end
	-- {firstStrike, execute, manaThrift, multishot} for a style from a stats snapshot.
	-- A capstone the snapshot counted but that has since expired is taken back out.
	function L.perks(info, style)
		local out = {firstStrike = 0, execute = 0, manaThrift = 0, multishot = 1}
		local m = type(info) == "table" and type(info.mastery) == "table" and info.mastery or nil
		local src = m and type(m[style]) == "table" and m[style] or nil
		if not src then return out end
		for k in pairs(out) do
			local v = tonumber(src[k])
			if v and v == v then out[k] = v end
		end
		local treeId = STYLE_TREE[style]
		local expires = treeId and type(m.active) == "table" and tonumber(m.active[treeId])
		if expires and wallClock() >= expires then
			local ability = capstoneAbility(treeId)
			if ability then
				for k in pairs(out) do
					local v = tonumber(ability[k])
					-- multishot comes only from the capstone (taken as a max), so it falls back to 1.
					if v then out[k] = if k == "multishot" then 1 else out[k] - v end
				end
			end
		end
		local cap = (Data.Mastery and tonumber(Data.Mastery.PERK_CAP)) or 100
		out.firstStrike = math.clamp(out.firstStrike, 0, cap)
		out.execute = math.clamp(out.execute, 0, cap)
		out.manaThrift = math.clamp(out.manaThrift, 0, 100)
		out.multishot = math.clamp(math.floor(out.multishot), 1, C.MULTISHOT_MAX)
		return out
	end
	-- Mana a spell costs after manaThrift: rounded to the nearest point, never below 0.
	function L.spellManaCost(spell, thrift)
		local base = math.max(0, tonumber(spell and spell.mana) or 0)
		thrift = math.clamp(tonumber(thrift) or 0, 0, 100)
		if thrift <= 0 then return base end
		return math.max(0, math.floor(base * (100 - thrift) / 100 + 0.5))
	end
	-- First landed hit on a full-health monster: one roll per monster per player.
	function L.firstStrike(player, r, perks)
		if (perks.firstStrike or 0) <= 0 or r.hp < r.maxHp then return false end
		r.opened = r.opened or {}
		if r.opened[player] then return false end
		r.opened[player] = true
		return env.rng() * 100 < perks.firstStrike
	end
	-- Raw damage after execute (target health before this hit).
	-- Hollow Sunder: is r a boss (never an add or an ordinary monster), and is it shielded?
	function L.sunderMult(weaponId, r)
		local LRD = Data.Lairs
		if not LRD or not LRD.sunderMult or type(r) ~= "table" or r.add or r.lairAdd then return 1 end
		if not (r.boss == true or r.worldBoss == true or r.lair == true) then return 1 end
		local warded = (r.worldBoss == true or r.lair == true) and type(r.adds) == "table" and next(r.adds) ~= nil
		return LRD.sunderMult(weaponId, {boss = true, warded = warded})
	end
	function L.executeBonus(r, raw, perks)
		if (perks.execute or 0) <= 0 or r.hp * 100 >= C.EXECUTE_THRESHOLD * r.maxHp then return raw, false end
		return raw * (1 + perks.execute / 100), true
	end
	local function critStats(stats)
		local s = table.clone(stats)
		s.critChance = 100
		return s
	end
	function L.attack(player, verb, target)
		local ok, r = L.validateAttack(player, verb, target)
		if not ok then return nil, r end
		local info = L.statsFor(player)
		if not info then return nil, "stats" end
		if loadoutOf(info).style ~= "melee" then return nil, "style" end
		local stats = info.stats
		scheduleNext(player, L.attackCooldown(stats.attackSpeed))
		local perks = L.perks(info, "melee")
		local opening = L.firstStrike(player, r, perks)
		local raw, crit = Progression.meleeDamage(if opening then critStats(stats) else stats, env.rng)
		local executed
		raw, executed = L.executeBonus(r, raw, perks)
		-- Polish: Hollow Sunder (Data.Lairs.sunderMult) on boss records only.
		local sunder = L.sunderMult(loadoutOf(info).weapon, r)
		if sunder > 1 then raw = math.floor(raw * sunder) end
		local tide = if L.tideMult then L.tideMult(loadoutOf(info).weapon, r) else 1 -- Raids: Riptide (Data.Raids.tideMult)
		if tide > 1 then raw = math.floor(raw * tide) end
		local dealt, tag = L.mitigate(r, raw, "melee", player)
		L.landHit(player, r, dealt, "melee")
		local lifesteal = tonumber(stats.lifesteal) or 0
		if lifesteal > 0 then env.heal(player, lifesteal) end
		local result = {record = r, damage = dealt, crit = crit == true, healed = lifesteal > 0, style = "melee", tag = tag}
		if sunder > 1 then result.sunder = true end
		if tide > 1 then result.tide = true end
		if opening then result.firstStrike = true end
		if executed then result.execute = true end
		return finish(result, r)
	end
	-- One arrow striking r: accuracy roll, opening blow, damage, execute, accrual.
	function L.rangedHit(player, r, hit, stats, bow, arrow, level, perks)
		hit.chance = L.prayerAccuracy(player, Progression.hitChance(stats.rangedAccuracy, level, r.level, r.defense))
		if env.rng() < hit.chance then
			local opening = L.firstStrike(player, r, perks)
			local raw, crit = Progression.rangedDamage(if opening then critStats(stats) else stats, bow, arrow, level, env.rng)
			local executed
			raw, executed = L.executeBonus(r, raw, perks)
			local tide = if L.tideMult then L.tideMult(bow and bow.id, r) else 1 -- Raids: Undertow (Data.Raids.tideMult)
			if tide > 1 then raw = math.floor(raw * tide); hit.tide = true end
			hit.damage, hit.tag = L.mitigate(r, raw, "ranged", player)
			hit.crit = crit == true
			if opening then hit.firstStrike = true end
			if executed then hit.execute = true end
		else
			hit.damage, hit.miss, hit.crit = 0, true, false
		end
		L.landHit(player, r, hit.damage, "ranged")
		return hit
	end
	-- Bow shot. Validation order: target/reach, cooldown, weapon, bow reach,
	-- ammo and its tier, line of sight; only then is an arrow consumed.
	function L.ranged(player, verb, target)
		if verb ~= "ranged" then return nil, "verb" end
		local ok, r, pos = L.validateTarget(player, target, maxRange)
		if not ok then return nil, r end
		if onCooldown(player) then return nil, "cooldown" end
		local info = L.statsFor(player)
		if not info then return nil, "stats" end
		local loadout = loadoutOf(info)
		local bow = loadout.style == "ranged" and Data.Items[loadout.weapon]
		if not bow or type(bow.ranged) ~= "table" then return nil, "weapon" end
		if (pos - r.position).Magnitude - r.radius > math.min(maxRange, bow.ranged.range or maxRange) then return nil, "range" end
		local arrow = loadout.ammo and Data.Items[loadout.ammo]
		if not arrow or type(arrow.ammo) ~= "table" or (tonumber(loadout.ammoCount) or 0) < 1 then return nil, "ammo" end
		if arrow.ammo.tier > (bow.ranged.maxAmmoTier or 0) then return nil, "ammoTier" end
		if not L.lineOfSight(pos, r) then return nil, "sight" end
		local paid = env.bridge("consume", player, {items = {[loadout.ammo] = 1}})
		if type(paid) ~= "table" or paid.ok ~= true then
			loadout.ammoCount = 0
			return nil, "ammo"
		end
		local left = type(paid.remaining) == "table" and tonumber(paid.remaining[loadout.ammo])
		loadout.ammoCount = left or math.max(0, loadout.ammoCount - 1)
		local stats = info.stats
		scheduleNext(player, Progression.weaponCooldown(bow.ranged.speed, stats.attackSpeed))
		local level = loadout.levels and loadout.levels.Ranged or 1
		local perks = L.perks(info, "ranged")
		local result = {record = r, style = "ranged", ammo = loadout.ammo, ammoLeft = loadout.ammoCount, from = pos, color = arrow.color}
		-- Multishot: extra targets are chosen before the first one may die.
		local extras = if perks.multishot > 1
			then L.multishotTargets(player, r, pos, math.min(maxRange, bow.ranged.range or maxRange), perks.multishot - 1)
			else {}
		L.rangedHit(player, r, result, stats, bow, arrow, level, perks)
		local lifesteal = tonumber(stats.lifesteal) or 0
		if lifesteal > 0 and result.damage > 0 then env.heal(player, lifesteal); result.healed = true end
		finish(result, r)
		if #extras > 0 then
			result.extra = {}
			for _, other in ipairs(extras) do
				local hit = {record = other, style = "ranged", from = pos, color = arrow.color}
				L.rangedHit(player, other, hit, stats, bow, arrow, level, perks)
				table.insert(result.extra, finish(hit, other))
			end
		end
		return result
	end
	-- Monsters a multishot may also strike: nearest to the first target first,
	-- each passing the same checks as an aimed shot (see the header).
	local function splashAllowed(player, r)
		local mine = L.peekStats(player)
		local ironman = mine ~= nil and mine.ironman == true
		for other, c in pairs(r.contributors) do
			if other ~= player and c.damage > 0 then
				if ironman then return false end
				local info = L.peekStats(other)
				if info and info.ironman == true then return false end
			end
		end
		return true
	end
	function L.multishotTargets(player, primary, pos, reach, count)
		local out = {}
		count = math.clamp(math.floor(tonumber(count) or 0), 0, C.MULTISHOT_MAX - 1)
		if count <= 0 then return out end
		local candidates = {}
		for r in pairs(records) do
			if r ~= primary and r.alive and not r.leashing and not (r.boss and r.owner ~= player)
				and (r.position - primary.position).Magnitude - r.radius <= C.MULTISHOT_RADIUS
				and (pos - r.position).Magnitude - r.radius <= reach and splashAllowed(player, r) then
				table.insert(candidates, {r = r, d = (r.position - primary.position).Magnitude})
			end
		end
		table.sort(candidates, function(a, b) return a.d < b.d end)
		for _, entry in ipairs(candidates) do
			if #out >= count then break end
			if L.lineOfSight(pos, entry.r) then table.insert(out, entry.r) end
		end
		return out
	end

	-- Mana (per session, never persisted; SkyBlock mana) ------------------------
	function L.manaOf(player, stats)
		local now = env.now()
		local m = mana[player]
		local max = if stats then Progression.maxMana(stats) elseif m then m.max else 0
		if not m then
			m = {current = max, max = max, at = now}
			mana[player] = m
		end
		m.current = math.min(m.max, m.current + Progression.manaRegen(m.max) * L.prayerMana(player) * math.max(0, now - m.at))
		m.at = now
		if max ~= m.max then m.max = max; m.current = math.min(m.current, max) end
		return m
	end
	-- Mana to replicate: {player, mana, max} for every player whose rounded value changed.
	-- Bounded: only players below max regenerate (no stats needed), and at most
	-- C.MANA_REFRESH_BUDGET players per tick fetch stats (first sight, or max
	-- older than C.MANA_REFRESH); attacks and casts refresh max mana on the way.
	function L.manaTick()
		local updates = {}
		local now, budget = env.now(), C.MANA_REFRESH_BUDGET
		for _, player in ipairs(env.players()) do
			local m = mana[player]
			local cached = statsCache[player]
			if budget > 0 and (not m or not cached or now - cached.at >= C.MANA_REFRESH) then
				budget -= 1
				L.statsFor(player)
				m = mana[player]
			elseif m and m.current < m.max then
				m = L.manaOf(player)
			end
			if m then
				local current = math.floor(m.current)
				if current ~= m.sentMana or m.max ~= m.sentMax then
					m.sentMana, m.sentMax = current, m.max
					table.insert(updates, {player = player, mana = current, max = m.max})
				end
			end
		end
		return updates
	end
	-- Spell cast. target may be nil for self spells (heal, teleport).
	function L.cast(player, verb, target, spellId)
		if verb ~= "cast" then return nil, "verb" end
		if not env.alive(player) then return nil, "dead" end
		local pos = env.position(player)
		if not pos then return nil, "position" end
		local info = L.statsFor(player)
		if not info then return nil, "stats" end
		local loadout = loadoutOf(info)
		if spellId == nil or spellId == "" then spellId = loadout.autocast end
		local spell = type(spellId) == "string" and Data.Spells[spellId]
		if not spell then return nil, "spell" end
		local allowed, why = Progression.spellAllowed(loadout, spell)
		if not allowed then return nil, why end
		local weapon = if loadout.style == "magic" then Data.Items[loadout.weapon] else nil
		local now = env.now()
		local r
		if spell.kind == "damage" or spell.kind == "snare" then
			local okTarget, record = L.validateTarget(player, target, math.min(maxRange, spell.range or maxRange))
			if not okTarget then return nil, record end
			r = record
			if spell.kind == "snare" and (r.boss or r.worldBoss) then return nil, "immune" end
		end
		if spell.kind == "damage" and onCooldown(player) then return nil, "cooldown" end
		local ready = spellReady[player] and spellReady[player][spell.id]
		if ready and now < ready then return nil, "cooldown" end
		if spell.kind == "teleport" and lastHurt[player] and now < lastHurt[player] + (tonumber(CS.combatLock) or 5) then return nil, "combat" end
		-- An agility move would carry the player on after the teleport: refuse mid-move.
		if spell.kind == "teleport" and env.moving and env.moving(player) then return nil, "teleport" end
		local m = L.manaOf(player, info.stats)
		local manaCost = L.spellManaCost(spell, L.perks(info, "magic").manaThrift) -- Skill Mastery: manaThrift / Glyphstorm
		if m.current < manaCost then return nil, "mana" end
		local costs = Progression.glyphCost(spell, weapon)
		local supplies = type(loadout.supplies) == "table" and loadout.supplies or {}
		-- §49 Runebinding: runes pay for glyphs 1:1 (own rune, then the glyph, then a
		-- combination rune, then the Astral / Crown wildcard). No plan: refused below.
		local RB = Data.Runebinding
		if RB and RB.payPlan and next(costs) then costs = RB.payPlan(costs, supplies) or costs end
		for id, n in pairs(costs) do
			if (tonumber(supplies[id]) or 0) < n then return nil, "glyphs" end
		end
		if r and not L.lineOfSight(pos, r) then return nil, "sight" end
		-- Pay first (stale supplies must never buy a free teleport), then act.
		local paid
		if next(costs) then
			paid = env.bridge("consume", player, {items = costs})
			if type(paid) ~= "table" or paid.ok ~= true then
				for id in pairs(costs) do supplies[id] = 0 end
				return nil, "glyphs"
			end
			for id, n in pairs(costs) do
				local left = type(paid.remaining) == "table" and tonumber(paid.remaining[id])
				supplies[id] = left or math.max(0, (tonumber(supplies[id]) or 0) - n)
			end
		end
		if spell.kind == "teleport" and not (env.teleport and env.teleport(player) == true) then
			-- Refund only what was spent: supplies kept by Ink/Quiver Thrift (paid.saved) never left the satchel.
			local spent = {}
			for id, n in pairs(costs) do
				local kept = paid and type(paid.saved) == "table" and tonumber(paid.saved[id]) or 0
				if n - kept > 0 then spent[id] = n - kept end
			end
			if next(spent) then
				local back = env.bridge("refund", player, {items = spent})
				if type(back) == "table" and back.ok == true then
					for id, n in pairs(spent) do supplies[id] = (tonumber(supplies[id]) or 0) + n end
				end
			end
			return nil, "teleport"
		end
		m.current -= manaCost
		if spell.kind == "damage" then
			scheduleNext(player, Progression.weaponCooldown(weapon and weapon.magic and weapon.magic.speed or 1.2, info.stats.attackSpeed))
		end
		if spell.cooldown then
			spellReady[player] = spellReady[player] or {}
			spellReady[player][spell.id] = now + spell.cooldown
		end
		local result = {spell = spell.id, kind = spell.kind, style = "magic", mana = math.floor(m.current), maxMana = m.max,
			manaCost = manaCost, record = r, from = pos, color = spell.color}
		if spell.kind == "damage" then
			local raw = Progression.spellDamage(info.stats, spell, weapon, loadout.levels and loadout.levels.Magic or 1)
			local tide = if L.tideMult then L.tideMult(weapon and weapon.id, r) else 1 -- Raids: Drownlight (Data.Raids.tideMult)
			if tide > 1 then raw = math.floor(raw * tide); result.tide = true end
			result.damage, result.tag = L.mitigate(r, raw, "magic", player)
			result.crit = false
			L.landHit(player, r, result.damage, "magic", spell.id)
			return finish(result, r)
		elseif spell.kind == "snare" then
			r.snaredUntil = now + (spell.duration or 0)
			result.duration = spell.duration
			L.landHit(player, r, 0, "magic", spell.id)
		else
			if spell.kind == "heal" then env.heal(player, spell.heal or 0) end
			L.reportXp(player, nil, "magic", 0, spell.id)
		end
		return result
	end
	function L.creditEligible(r)
		local contributors = 0
		for _, c in pairs(r.contributors) do if c.damage > 0 then contributors += 1 end end
		local out = {}
		for player, c in pairs(r.contributors) do
			if c.damage > 0 and env.alive(player) then
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
			L.payXp(r, credited)
			-- Combat Feats (§45): server-timed fight length and the owner's hits taken.
			L.reportBoss(r.owner, "win", {seconds = math.max(1, math.floor(C.BOSS_DURATION - (r.expires - env.now()) + 0.5)), hits = r.featHits or 0,
				styles = r.featStyles and table.clone(r.featStyles) or {}})
		elseif r.worldBoss then
			credited = L.wbKill(r)
		elseif r.sea then
			credited = L.seaCredit(r)
			L.unregister(r)
			L.payXp(r, credited)
			L.reportSea(r.owner, r.id, r.seq, if #credited > 0 then "kill" else "despawn", r.expires + C.SEA_REPORT_GRACE)
		else
			credited = L.creditEligible(r)
			L.unregister(r)
			L.payXp(r, credited)
			-- Slayer tasks section: the reply may raise a superior (L.onKillReply).
			-- task = Slayer task credit (L.taskCredit: a real damage share), separate from kill credit.
			for _, player in ipairs(credited) do env.bridge("kill", player, {monster = r.id, task = L.taskCredit(r, player)}, function(reply) L.onKillReply(player, r, reply) end) end
		end
		return credited
	end

	-- AI ---------------------------------------------------------------------
	-- May r pick this player as a fresh target? (Slayer tasks section narrows it.)
	function L.aggroAllowed(r, player) return true end
	function L.nearestAggro(r)
		if r.passive and not r.provoked then return nil end
		local best, bestDist
		for _, player in ipairs(playerList()) do
			if isAlive(player) and L.aggroAllowed(r, player) then
				local pos = positionOf(player)
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
		return L.nearestPlayerDistance(r) <= range
	end
	function L.strike(r, player)
		r.nextHit = env.now() + r.attackCooldown
		lastHurt[player] = env.now()
		r.lungeUntil = env.now() + 0.25
		env.bridge("damage", player, {amount = r.damage, style = r.attackStyle}) -- Prayer: protection reads the style
	end
	-- Returns an action: {kind = sleep|idle|wander|chase|hold|strike|leash, goal?, speed?, face?, stop?, healed?}
	function L.think(r)
		if not r.alive then return {kind = "dead"} end
		if r.worldBoss then return L.wbThink(r) end
		local now = env.now()
		local snared = r.snaredUntil ~= nil and now < r.snaredUntil
		if r.boss then
			local owner = r.owner
			local pos = isAlive(owner) and positionOf(owner)
			if not pos then return {kind = "idle"} end
			r.target = owner
		else
			local fromHome = flatDist(r.position, r.home)
			if r.leashing then
				if fromHome <= C.RETURN_RADIUS then
					r.leashing, r.provoked = false, false
					r.hp, r.contributors = r.maxHp, {} -- accrued damage XP is discarded
					return {kind = "idle", healed = true}
				end
				if snared then return {kind = "idle"} end
				return {kind = "leash", goal = r.home, speed = r.speed * 1.25, stop = 0}
			end
			if fromHome > C.LEASH_RANGE and not snared then
				r.leashing, r.target = true, nil
				return {kind = "leash", goal = r.home, speed = r.speed * 1.25, stop = 0}
			end
			if r.target then
				local pos = isAlive(r.target) and positionOf(r.target)
				if not pos or flatDist(pos, r.home) > C.LEASH_RANGE + 8 then r.target = nil end
			end
			-- Sea creatures and Slayer superiors only ever fight their owner.
			if r.superior and r.target ~= nil and r.target ~= r.owner then r.target = nil end
			if not r.target and (r.sea or r.superior) and isAlive(r.owner) then
				local pos = positionOf(r.owner)
				if pos and flatDist(pos, r.home) <= C.LEASH_RANGE then r.target = r.owner end
			end
			if not r.target then r.target = L.nearestAggro(r) end
			if not r.target and not anyPlayerNear(r, C.ACTIVE_RANGE) then return {kind = "sleep"} end
		end
		if r.target then
			local pos = positionOf(r.target)
			local reach = C.MONSTER_REACH + r.radius
			local d = flatDist(pos, r.position)
			if d <= reach then
				if now >= r.nextHit then
					L.strike(r, r.target)
					return {kind = "strike", face = pos, target = r.target}
				end
				return {kind = "hold", face = pos}
			end
			if snared then return {kind = "hold", face = pos, snared = true} end
			return {kind = "chase", goal = pos, speed = r.speed, face = pos, stop = reach * 0.7}
		end
		if snared then return {kind = "idle"} end
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
			defense = (tier - 1) * C.BOSS_DEFENSE_PER_TIER, kind = body.kind, speed = body.speed, color = def.color,
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle}
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
			weakness = spec.weakness, defenceStyle = spec.defenceStyle, attackStyle = spec.attackStyle,
		})
		bosses[player] = r
		return r
	end
	function L.bossOf(player) return bosses[player] end
	function L.failBoss(player)
		local r = bosses[player]
		if not r then return nil end
		L.unregister(r)
		L.reportBoss(player, "fail")
		return r
	end
	-- The bridge answers {ok = true} once the quest is resolved. Anything else
	-- (lease lapsed, bridge missing or erroring) leaves the quest bossReady, so
	-- re-read SlayerBossReady shortly and summon the boss again.
	function L.reportBoss(player, result, feat)
		local payload = {result = result}
		if type(feat) == "table" then payload.seconds, payload.hits, payload.styles = feat.seconds, feat.hits, feat.styles end -- Combat Feats (§45)
		env.bridge("slayerBoss", player, payload, function(reply)
			if type(reply) ~= "table" or reply.ok ~= true then L.rearmBoss(player) end
		end)
	end
	function L.rearmBoss(player)
		rearm[player] = env.now() + C.BOSS_REARM_DELAY
	end
	function L.dueRearms()
		local now, due = env.now(), {}
		for player, at in pairs(rearm) do
			if now >= at and not bosses[player] then table.insert(due, player) end
		end
		for _, player in ipairs(due) do rearm[player] = nil end
		return due
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

	-- Sea creatures ---------------------------------------------------------
	local function seaCap() return tonumber(Data.SeaCreatureCap) or C.SEA_CAP end
	function L.seaDuration() return tonumber(Data.SeaCreatureLifetime) or C.SEA_DURATION end
	function L.parseSeaSpawn(value)
		if type(value) ~= "string" or #value > 80 then return nil end
		local id, seq = value:match("^(%a+):(%d+)$")
		seq = tonumber(seq)
		local def = id and type(Data.SeaCreatures) == "table" and rawget(Data.SeaCreatures, id)
		if not def or not seq or seq < 1 then return nil end
		return id, seq, def
	end
	function L.seaCount(player)
		local n = 0
		for _ in pairs(seaOwned[player] or {}) do n += 1 end
		return n
	end
	function L.seaLive() return seaLive end
	-- A kill whose report was not applied (journal not live: nil or reason
	-- "sync") is resent every C.SEA_RETRY_DELAY until `deadline`, like slayer
	-- boss re-arms. The server settles each ticket once, so resends are safe;
	-- any definitive answer (ok, "ticket", "expired") ends the retries.
	function L.reportSea(player, id, seq, result, deadline)
		env.bridge("seaCreature", player, {monster = id, seq = seq, result = result}, function(reply)
			if result ~= "kill" or not deadline then return end
			if reply == nil or (type(reply) == "table" and reply.reason == "sync") then
				if env.now() + C.SEA_RETRY_DELAY > deadline then return end
				seaRetry[player] = seaRetry[player] or {}
				seaRetry[player][seq] = {id = id, seq = seq, at = env.now() + C.SEA_RETRY_DELAY, deadline = deadline}
			end
		end)
	end
	-- Kill reports due for a resend: {player, id, seq, deadline}; each fires once.
	function L.dueSeaRetries()
		local now, due = env.now(), {}
		for player, list in pairs(seaRetry) do
			for seq, job in pairs(list) do
				if now >= job.at then
					list[seq] = nil
					if now <= job.deadline then table.insert(due, {player = player, id = job.id, seq = seq, deadline = job.deadline}) end
				end
			end
			if not next(list) then seaRetry[player] = nil end
		end
		return due
	end
	-- SeaCreatureSpawn changed. Returns ("spawn", spec) | (nil, reason).
	-- A refused fresh ticket is reported as a despawn so the server frees the slot.
	function L.seaAttribute(player, value, at)
		if value == nil or value == "" then return nil, "empty" end
		local id, seq, def = L.parseSeaSpawn(value)
		if not id then return nil, "invalid" end
		if seq <= (seaSeq[player] or 0) then return nil, "stale" end
		seaSeq[player] = seq
		local reason
		if L.seaCount(player) >= seaCap() then reason = "cap"
		elseif seaLive >= C.SEA_MAX then reason = "full"
		elseif not env.alive(player) then reason = "dead" end
		local home = if typeof(at) == "Vector3" then at else env.position(player)
		if not reason and not home then reason = "position" end
		if not reason and env.position(player) and (env.position(player) - home).Magnitude > C.CREDIT_RANGE then reason = "far" end
		if reason then
			L.reportSea(player, id, seq, "despawn")
			return nil, reason
		end
		return "spawn", {id = id, seq = seq, def = def, owner = player, at = home}
	end
	function L.registerSea(player, spec, model, position, opts)
		if spec.owner ~= player or spec.registered or L.seaCount(player) >= seaCap() or seaLive >= C.SEA_MAX then return nil end
		spec.registered = true
		opts = opts or {}
		local def = spec.def
		local r = newRecord({
			id = spec.id, def = def, sea = true, owner = player, seq = spec.seq, name = def.name, level = def.level,
			maxHp = def.hp, hp = def.hp, damage = def.damage, defense = def.defense or 0, speed = def.speed or 12,
			attackCooldown = L.monsterCooldown(def.speed), passive = false, provoked = true,
			home = position, position = position, model = model, expires = env.now() + L.seaDuration(),
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS), target = player,
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
		})
		seaOwned[player] = seaOwned[player] or {}
		seaOwned[player][r] = true
		seaLive += 1
		return r
	end
	-- Runtime could not build the model: free the server ticket.
	function L.seaFailed(spec) L.reportSea(spec.owner, spec.id, spec.seq, "despawn") end
	function L.seaCredit(r)
		local owner = r.owner
		-- §51 Skysailing: a sky corsair counts its captain's crew hits (deck cannons
		-- fired by gunners), so the captain at the helm is credited when anyone landed one.
		local hit = L.contribution(r, owner) > 0
		if not hit and r.def and r.def.pirate then
			for _, c in pairs(r.contributors) do if c.damage > 0 then hit = true break end end
		end
		if not hit or not env.alive(owner) then return {} end
		local pos = env.position(owner)
		if not pos or (pos - r.position).Magnitude > C.CREDIT_RANGE then return {} end
		local info = L.peekStats(owner)
		if info and info.ironman == true then
			for player, c in pairs(r.contributors) do
				if player ~= owner and c.damage > 0 then return {} end
			end
		end
		return {owner}
	end
	-- §51 Skysailing deck cannons: the live sky corsair nearest the aim within
	-- range and the cone. QC L5: only corsairs owned by this ship's sailors
	-- (`owners` = {[UserId] = true}) and in line of sight.
	function L.cannonTarget(origin, dir, range, cone, owners)
		if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return nil end
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 1e-3 then return nil end
		flat = flat.Unit
		local best, bestD = nil, math.huge
		for _, owned in pairs(seaOwned) do
			for r in pairs(owned) do
				local mine = type(owners) == "table" and r.owner and owners[r.owner.UserId] == true
				if r.alive and r.def and r.def.pirate and mine then
					local to = r.position - origin
					local d = to.Magnitude
					local toFlat = Vector3.new(to.X, 0, to.Z)
					if d <= range + (r.radius or 0) and toFlat.Magnitude > 1e-3 then
						local angle = math.acos(math.clamp(toFlat.Unit:Dot(flat), -1, 1))
						if angle <= cone and d < bestD and L.lineOfSight(origin, r) then best, bestD = r, d end
					end
				end
			end
		end
		return best
	end
	-- One broadside: ranged damage from the gunner (credited like any hit).
	function L.cannon(player, payload)
		if type(payload) ~= "table" then return nil, "payload" end
		local range = math.clamp(tonumber(payload.range) or 0, 0, 120)
		local cone = math.clamp(tonumber(payload.cone) or 0, 0, 1)
		local damage = math.clamp(math.floor(tonumber(payload.damage) or 0), 0, 5000)
		local r = L.cannonTarget(payload.origin, payload.dir, range, cone, payload.owners)
		if not r or damage <= 0 then return {hit = false} end
		local dealt = L.mitigate(r, damage, "ranged", player)
		L.landHit(player, r, dealt, "ranged")
		local result = {hit = true, record = r, damage = dealt, name = r.name, style = "ranged"}
		return finish(result, r)
	end
	-- Submerges sea creatures past their lifetime; returns the records removed.
	function L.seaTick()
		local now, gone = env.now(), {}
		for _, owned in pairs(seaOwned) do
			for r in pairs(owned) do if now >= r.expires then table.insert(gone, r) end end
		end
		for _, r in ipairs(gone) do
			L.unregister(r)
			L.reportSea(r.owner, r.id, r.seq, "despawn")
		end
		return gone
	end

	-- Players ----------------------------------------------------------------
	function L.playerRemoving(player)
		statsCache[player], nextAttack[player], pendingBoss[player], rearm[player], seaSeq[player] = nil, nil, nil, nil, nil
		seaRetry[player], mana[player], spellReady[player], lastHurt[player] = nil, nil, nil, nil
		local removed = {}
		local boss = bosses[player]
		if boss then L.unregister(boss); table.insert(removed, boss) end
		local owned = {}
		for r in pairs(seaOwned[player] or {}) do table.insert(owned, r) end
		for _, r in ipairs(owned) do L.unregister(r); table.insert(removed, r) end
		for r in pairs(records) do
			r.contributors[player] = nil
			if r.target == player then r.target = nil end
		end
		L.wbPlayerRemoving(player)
		return removed
	end
	function L.hasPlayerState(player)
		return statsCache[player] ~= nil or nextAttack[player] ~= nil or pendingBoss[player] ~= nil or bosses[player] ~= nil or rearm[player] ~= nil
			or seaOwned[player] ~= nil or seaSeq[player] ~= nil or seaRetry[player] ~= nil
			or mana[player] ~= nil or spellReady[player] ~= nil or lastHurt[player] ~= nil
	end

	--------------------------------------------------------------------------
	-- World Boss section (Endgame team). Data.Endgame / Data.WorldBosses.
	-- One live record per boss id (r.worldBoss): anyone may fight it, it never
	-- leaves its arena (def.leash from the arena centre), and every phase cycles
	-- telegraphed attacks resolved by L.wbTick:
	--   telegraph {kind disc|ring|safe, center, radius, resolveAt}: players in
	--   the arena that E.struck() at resolve time take damage * mult (bridge
	--   "damage"), so leaving the warning disc / ring (or entering the safe
	--   ring) dodges it.
	--   adds: a wave of region monsters (r.add records, parent = boss) spawned
	--   by the runtime; while any lives the boss is warded (E.WARD damage).
	-- Enrage after def.enrage s; the boss departs after def.duration s or 90 s
	-- with nobody in its arena (no loot, accrued XP discarded).
	-- Summoning: altar sigils (L.placeSigil; full altar -> L.wbDueSummons) or
	-- the calendar schedule (L.wbScheduleTick, one spawn per window key).
	-- Kill: E.rank orders contributors; E.eligible (share, alive, range, recent
	-- hit, Ironman share) decides credit; credited players get damage XP
	-- (L.payXp) and a bridge "worldBoss" {boss, tier, rank, share, damage,
	-- sigils, fight} whose reply reaches env.wbLoot(player, record, entry, reply).
	-- A reply of nil / reason "sync" (journal not live) is resent every
	-- WB_REWARD_RETRY s until WB_REWARD_WINDOW s after the kill (the server
	-- pays each boss:fight:userId once, so resends are safe).
	-- Altar placements are keyed by UserId (a rejoin keeps the per-player cap).
	-- Unspent sigils are refunded through bridge "worldBossRefund" {boss,
	-- userId, sigils, reason} (target: the online Player, else the UserId):
	-- when a full altar's boss cannot be built WB_SUMMON_ATTEMPTS times, when a
	-- summoned boss departs before anyone damaged it, and at shutdown
	-- (L.wbDrain, through IsleWorldBoss "drain").
	--------------------------------------------------------------------------
	local E = Data.Endgame
	local wb = worldBossLive -- [bossId] = live record
	local altar = {}         -- [bossId] = {total = n, by = {[userId] = n}, failures = n}
	local scheduleSeen = {}  -- [window key] = true once spawned (or skipped while active)
	local warnSeen = {}      -- [window key] = true once announced
	local wbRetry = {}       -- unapplied reward reports {player, record, entry, payload, at, deadline}
	local fightSeq = 0
	L.WB_EMPTY_DEPART = 90
	L.WB_REWARD_RETRY = 5
	L.WB_REWARD_WINDOW = 120
	L.WB_SUMMON_ATTEMPTS = 5
	local function uidOf(player)
		if type(player) == "number" then return player end
		local uid = player and player.UserId
		return if type(uid) == "number" then uid else nil
	end
	local function onlineByUserId(uid)
		for _, player in ipairs(env.players()) do if player.UserId == uid then return player end end
		return nil
	end
	-- Refunds a {[userId] = sigils} map through the bridge (unless silent);
	-- returns {{userId, player?, boss, sigils, reason}} in UserId order.
	local function refundSigils(id, by, reason, silent)
		local out, uids = {}, {}
		for uid, n in pairs(by or {}) do if n > 0 then table.insert(uids, uid) end end
		table.sort(uids)
		for _, uid in ipairs(uids) do
			local player = onlineByUserId(uid)
			local entry = {userId = uid, player = player, boss = id, sigils = by[uid], reason = reason}
			table.insert(out, entry)
			if not silent then
				env.bridge("worldBossRefund", player or uid, {boss = id, userId = uid, sigils = by[uid], reason = reason})
			end
		end
		return out
	end
	function L.wbSpec(id)
		local def = E and E.boss(id)
		if not def then return nil end
		return {id = id, def = def, name = def.name, level = def.level, hp = def.hp, damage = def.damage,
			defense = def.defense, speed = def.speed, color = def.color, kind = def.body}
	end
	function L.wbActive(id) return wb[id] end
	function L.wbList()
		local list = {}
		for _, id in ipairs(E and E.BossOrder or {}) do if wb[id] then table.insert(list, wb[id]) end end
		return list
	end
	function L.altarCount(id)
		local a = altar[id]
		return if a then a.total else 0
	end
	-- player: a Player (its UserId) or a UserId.
	function L.altarMine(id, player)
		local a, uid = altar[id], uidOf(player)
		return if a and uid then (a.by[uid] or 0) else 0
	end
	-- Places one sigil. Returns ok, reason ("ready" when the altar is full), count, needed.
	function L.placeSigil(player, id)
		local def = E and E.boss(id)
		if not def then return false, "boss", 0, 0 end
		local uid = uidOf(player)
		if not uid then return false, "player", 0, def.sigils or 0 end
		local a = altar[id] or {total = 0, by = {}, failures = 0}
		local ok, reason = E.canPlaceSigil(id, a.total, a.by[uid] or 0, wb[id] ~= nil)
		if not ok then return false, reason, a.total, def.sigils end
		altar[id] = a
		a.total += 1
		a.by[uid] = (a.by[uid] or 0) + 1
		return true, if a.total >= def.sigils then "ready" else nil, a.total, def.sigils
	end
	-- Empties an altar and refunds every placement (reason "failed" | "shutdown").
	function L.altarReset(id, reason, silent)
		local a = altar[id]
		if not a then return {} end
		altar[id] = nil
		return refundSigils(id, a.by, reason, silent)
	end
	-- The runtime could not build a due altar boss. After WB_SUMMON_ATTEMPTS
	-- failures the altar resets and refunds; returns the refunds (or nil).
	function L.wbSummonFailed(id)
		local a = altar[id]
		if not a then return nil end
		a.failures = (a.failures or 0) + 1
		if a.failures < L.WB_SUMMON_ATTEMPTS then return nil end
		return L.altarReset(id, "failed")
	end
	-- Shutdown: every unspent sigil (placed on an altar, or summoned into a boss
	-- nobody has damaged yet) as refunds, without bridge calls (the caller pays).
	function L.wbDrain()
		local out, ids = {}, {}
		for id in pairs(altar) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			for _, entry in ipairs(L.altarReset(id, "shutdown", true)) do table.insert(out, entry) end
		end
		for _, r in ipairs(L.wbList()) do
			if r.hp >= r.maxHp and next(r.summoners) then
				for _, entry in ipairs(refundSigils(r.id, r.summoners, "shutdown", true)) do table.insert(out, entry) end
				r.summoners = {}
			end
		end
		return out
	end
	-- Full altars whose boss is not up: {id, summoners = {[userId] = sigils}}.
	function L.wbDueSummons()
		local due = {}
		for id, a in pairs(altar) do
			local def = E.boss(id)
			if def and a.total >= def.sigils and not wb[id] then table.insert(due, {id = id, summoners = a.by}) end
		end
		return due
	end
	-- Calendar schedule at wall time t: events {kind = "warn"|"spawn", id, starts, key}.
	function L.wbScheduleTick(t)
		local out = {}
		if not E then return out end
		local w = E.scheduleAt(t)
		if t >= w.warnAt and t < w.starts and not warnSeen[w.key] then
			warnSeen[w.key] = true
			table.insert(out, {kind = "warn", id = w.boss, starts = w.starts, key = w.key})
		end
		if w.open and not scheduleSeen[w.key] then
			scheduleSeen[w.key] = true
			if not wb[w.boss] then table.insert(out, {kind = "spawn", id = w.boss, starts = w.starts, key = w.key}) end
		end
		return out, w
	end
	-- A runtime spawn that could not build: let the same window try again.
	function L.wbScheduleRetry(key) scheduleSeen[key] = nil end
	function L.wbRegister(spec, model, position, opts)
		if not spec or wb[spec.id] then return nil end
		opts = opts or {}
		local def = spec.def
		local now = env.now()
		fightSeq += 1
		local r = newRecord({
			id = spec.id, def = def, worldBoss = true, name = def.name, level = def.level, maxHp = def.hp, hp = def.hp,
			damage = def.damage, defense = def.defense or 0, speed = def.speed or 10, attackCooldown = 2.2, passive = false, provoked = true,
			home = position, position = position, model = model, radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
			phase = 1, step = 0, spawnedAt = now, enrageAt = now + def.enrage, expires = now + def.duration,
			nextTelegraph = now + 4, telegraphs = {}, adds = {}, summoners = opts.summoners or {}, fight = fightSeq, lastSeen = now,
			-- Telegraphs sit on the ground (opts.ground: arena floor Y), not at the boss's hip.
			ground = if type(opts.ground) == "number" then opts.ground else position.Y,
		})
		wb[spec.id] = r
		if def.summon == "altar" then altar[spec.id] = nil end
		return r
	end
	-- One add of a wave: a regional monster bound to its boss (no marker, no respawn).
	function L.wbRegisterAdd(boss, monsterId, model, position, opts)
		local def = Data.Monsters[monsterId]
		if not boss or not boss.alive or not def or def.worldBoss or def.seaCreature then return nil end
		opts = opts or {}
		local r = newRecord({
			id = monsterId, def = def, add = true, parent = boss, name = def.name, level = def.level, maxHp = def.hp, hp = def.hp,
			damage = def.damage, defense = def.defense or 0, speed = def.speed or 12, attackCooldown = L.monsterCooldown(def.speed),
			passive = false, provoked = true, home = boss.home, position = position, model = model,
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
		})
		boss.adds[r] = true
		return r
	end
	function L.wbWarded(r) return r.worldBoss == true and next(r.adds) ~= nil end
	-- Removes the boss and its adds without loot; returns the add records removed.
	function L.wbDepart(r)
		local removed = {}
		for add in pairs(r.adds) do table.insert(removed, add) end
		for _, add in ipairs(removed) do L.unregister(add) end
		L.unregister(r)
		return removed
	end
	-- Players inside the arena (alive, flat distance to the arena centre).
	local function arenaPlayers(r)
		local list = {}
		for _, player in ipairs(playerList()) do
			if isAlive(player) then
				local pos = positionOf(player)
				if pos and flatDist(pos, r.home) <= r.def.arenaRange then table.insert(list, player) end
			end
		end
		return list
	end
	L.arenaPlayers = arenaPlayers
	function L.wbThink(r)
		local now = env.now()
		local best, bestD
		for _, player in ipairs(arenaPlayers(r)) do
			local d = flatDist(positionOf(player), r.position)
			if not bestD or d < bestD then best, bestD = player, d end
		end
		r.target = best
		if not best then
			if flatDist(r.position, r.home) > C.RETURN_RADIUS then return {kind = "leash", goal = r.home, speed = r.speed, stop = 0} end
			return {kind = "idle"}
		end
		r.lastSeen = now
		local pos = positionOf(best)
		local reach = C.MONSTER_REACH + r.radius
		if bestD <= reach then
			if now >= r.nextHit then
				L.strike(r, best)
				return {kind = "strike", face = pos, target = best}
			end
			return {kind = "hold", face = pos}
		end
		local goal = pos
		local offset = flat(pos) - flat(r.home)
		if offset.Magnitude > r.def.leash then goal = r.home + offset.Unit * r.def.leash end
		return {kind = "chase", goal = goal, speed = r.speed, face = pos, stop = reach * 0.7}
	end
	-- Advances every live world boss. Returns events for the runtime:
	-- {kind = "telegraph"|"strike"|"phase"|"enrage"|"adds"|"depart", record, ...}.
	function L.wbTick()
		local now, events = env.now(), {}
		local ids = {}
		for id in pairs(wb) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local r = wb[id]
			local def = r.def
			if #arenaPlayers(r) > 0 then r.lastSeen = now end
			if now >= r.expires or now - r.lastSeen > L.WB_EMPTY_DEPART then
				local adds = L.wbDepart(r)
				-- Nobody ever damaged it: the summoners' sigils were never spent.
				local refunds = if r.hp >= r.maxHp then refundSigils(r.id, r.summoners, "depart") else {}
				r.summoners = {}
				table.insert(events, {kind = "depart", record = r, reason = if now >= r.expires then "timeout" else "empty", adds = adds, refunds = refunds})
				continue
			end
			local phase = E.phaseFor(def, r.hp / r.maxHp)
			if phase > r.phase then
				r.phase, r.step = phase, 0
				r.nextTelegraph = math.min(r.nextTelegraph, now + 1.5)
				table.insert(events, {kind = "phase", record = r, phase = phase})
			end
			if not r.enraged and now >= r.enrageAt then
				r.enraged = true
				r.damage = math.floor(def.damage * E.ENRAGE_DAMAGE)
				table.insert(events, {kind = "enrage", record = r})
			end
			-- Resolve warnings whose windup has elapsed.
			local i = 1
			while i <= #r.telegraphs do
				local tg = r.telegraphs[i]
				if now >= tg.resolveAt then
					table.remove(r.telegraphs, i)
					local hits = {}
					for _, player in ipairs(arenaPlayers(r)) do
						local pos = positionOf(player)
						if E.struck(tg.attack, tg.center, pos) then
							local amount = math.floor(r.damage * tg.attack.mult)
							lastHurt[player] = now
							env.bridge("damage", player, {amount = amount, style = r.attackStyle, worldBoss = true}) -- Prayer: world-boss protection
							table.insert(hits, {player = player, amount = amount})
						end
					end
					table.insert(events, {kind = "strike", record = r, telegraph = tg, hits = hits})
				else
					i += 1
				end
			end
			-- Next attack of the rotation.
			if now >= r.nextTelegraph then
				r.step += 1
				local attackId = E.attackAt(def, r.phase, r.step)
				local attack = def.attacks[attackId]
				r.nextTelegraph = now + E.attackInterval(def, r.phase, r.enraged)
				if attack.kind == "adds" then
					-- A wave never stacks on a living one.
					if not next(r.adds) then
						table.insert(events, {kind = "adds", record = r, id = attackId, attack = attack, monster = attack.monster, count = attack.count})
					end
				else
					local center = r.position
					local victim
					if attack.kind == "disc" then
						local list = arenaPlayers(r)
						if #list > 0 then
							victim = list[1 + math.floor(env.rng() * #list) % #list]
							center = positionOf(victim)
						end
					end
					if attack.kind ~= "disc" or victim then
						local tg = {id = attackId, attack = attack, kind = attack.kind, name = attack.name, center = Vector3.new(center.X, r.ground or r.home.Y, center.Z),
							radius = attack.radius, windup = attack.windup, resolveAt = now + attack.windup, victim = victim}
						table.insert(r.telegraphs, tg)
						table.insert(events, {kind = "telegraph", record = r, telegraph = tg})
					end
				end
			end
		end
		return events
	end
	-- Damage board: E.rank over contributors with damage.
	function L.wbBoard(r)
		local list = {}
		for player, c in pairs(r.contributors) do
			if c.damage > 0 then table.insert(list, {player = player, damage = c.damage, lastHit = c.lastHit}) end
		end
		return E.rank(list, r.maxHp)
	end
	-- HUD payload for one viewer (names resolved by the runtime's nameOf).
	function L.wbHud(r, viewer, nameOf)
		local now = env.now()
		local board = L.wbBoard(r)
		local top, you = {}, nil
		for i, e in ipairs(board) do
			if i <= E.TOP then table.insert(top, {name = nameOf and nameOf(e.player) or tostring(e.player), damage = math.floor(e.damage), share = e.share, you = e.player == viewer}) end
			if e.player == viewer then
				local tier = E.contributionTier(e.share)
				you = {rank = e.rank, damage = math.floor(e.damage), share = e.share, tier = tier and tier.id}
			end
		end
		local phase = r.def.phases[r.phase]
		return {id = r.id, name = r.name, level = r.level, hp = math.max(0, math.floor(r.hp)), maxHp = r.maxHp, phase = r.phase, phases = #r.def.phases,
			phaseName = phase and phase.name, enraged = r.enraged == true, enrageIn = math.max(0, math.ceil(r.enrageAt - now)),
			departIn = math.max(0, math.ceil(r.expires - now)), warded = L.wbWarded(r), top = top, you = you, fighters = #board}
	end
	-- The one boss whose HUD a player at `position` sees: the nearest live boss
	-- whose arena centre is within E.HUD_RANGE (flat), or nil.
	function L.wbHudFor(position)
		if not position then return nil end
		local best, bestD
		for _, r in ipairs(L.wbList()) do
			local d = flatDist(position, r.home)
			if d <= E.HUD_RANGE and (not bestD or d < bestD) then best, bestD = r, d end
		end
		return best
	end
	-- Sends one credited player's reward; an unapplied report (journal not
	-- live) is queued for a resend until `deadline`, then reported as is.
	local function sendReward(player, r, e, payload, deadline)
		env.bridge("worldBoss", player, payload, function(reply)
			if reply == nil or (type(reply) == "table" and reply.reason == "sync") then
				if env.now() + L.WB_REWARD_RETRY <= deadline then
					table.insert(wbRetry, {player = player, record = r, entry = e, payload = payload, at = env.now() + L.WB_REWARD_RETRY, deadline = deadline})
					return
				end
			end
			if env.wbLoot then env.wbLoot(player, r, e, reply) end
		end)
	end
	-- Resends due reward reports; returns how many were sent.
	function L.wbRetryTick()
		local now, due = env.now(), {}
		local i = 1
		while i <= #wbRetry do
			local job = wbRetry[i]
			if now >= job.at then table.remove(wbRetry, i); table.insert(due, job) else i += 1 end
		end
		for _, job in ipairs(due) do sendReward(job.player, job.record, job.entry, job.payload, job.deadline) end
		return #due
	end
	function L.wbPendingRewards() return #wbRetry end
	function L.wbKill(r)
		local now = env.now()
		local ranked = L.wbBoard(r)
		local credited = {}
		for _, e in ipairs(ranked) do
			local alive = env.alive(e.player) == true
			local pos = alive and env.position(e.player) or nil
			local info = L.peekStats(e.player)
			local ok, reason = E.eligible(r.def, {share = e.share, alive = alive, distance = pos and flatDist(pos, r.home) or nil,
				ironman = info ~= nil and info.ironman == true, lastHit = e.lastHit, now = now})
			local tier = ok and E.contributionTier(e.share) or nil
			e.eligible, e.reason, e.tier = ok == true, reason, tier and tier.id
			if ok then table.insert(credited, e.player) end
		end
		r.results = ranked
		r.removedAdds = L.wbDepart(r)
		L.payXp(r, credited)
		local deadline = now + L.WB_REWARD_WINDOW
		for _, e in ipairs(ranked) do
			if e.eligible then
				local payload = {boss = r.id, tier = e.tier, rank = e.rank, share = e.share, damage = math.floor(e.damage),
					sigils = r.summoners[uidOf(e.player)] or 0, fight = r.fight, seconds = math.max(1, math.floor(now - r.spawnedAt + 0.5))} -- §45: server-timed
				sendReward(e.player, r, e, payload, deadline)
			end
		end
		return credited
	end
	function L.wbPlayerRemoving(player)
		-- Placed sigils and summoner credit stay keyed by UserId (a rejoin does
		-- not reset the per-player cap); only queued reward resends are dropped.
		local i = 1
		while i <= #wbRetry do
			if wbRetry[i].player == player then table.remove(wbRetry, i) else i += 1 end
		end
	end
	-- End World Boss section.

	------------------------------------------------------------------------
	-- Prayer section (Prayer & Thieving team). Bridge "stats" carries
	-- info.prayer = {protect, offence = {melee, ranged, magic} (fractions),
	-- sap (fraction of base defence per landed hit), mana (regen multiplier),
	-- defence %} or nil. Protection and wards are applied by the Adventure
	-- script on bridge "damage" (payload.style = r.attackStyle, worldBoss).
	--   offence: raw damage x (1 + offence[style]) before the triangle/defence;
	--            ranged accuracy: hit chance x (1 + offence.ranged), within
	--            the style's hit ceiling.
	--   sap:     every landed hit (> 0) lowers r.defense by ceil(base x sap),
	--            never below base x (1 - Data.Prayer.SAP_MAX) (base = r.baseDefense,
	--            the defence before the first sap); a hit on a monster at full
	--            health (fresh or leash-healed) starts from base again.
	--   mana:    mana regeneration multiplier (Hearthsong).
	-- Uses only the cached stats snapshot (C.STATS_TTL); no extra bridge calls.
	------------------------------------------------------------------------
	local function prayerOf(player)
		local info = player ~= nil and L.peekStats(player)
		local pr = type(info) == "table" and type(info.prayer) == "table" and info.prayer or nil
		return pr
	end
	local function fraction(v, cap)
		v = tonumber(v)
		if not v or v ~= v or v <= 0 then return 0 end
		return math.min(v, cap)
	end
	function L.prayerOffence(player, style)
		local pr = prayerOf(player)
		return 1 + fraction(pr and type(pr.offence) == "table" and pr.offence[style], 1)
	end
	function L.prayerAccuracy(player, chance)
		local bonus = L.prayerOffence(player, "ranged")
		if bonus <= 1 then return chance end
		return math.min(math.max(chance, tonumber(CS.hitCeiling) or 0.98), chance * bonus)
	end
	function L.prayerMana(player)
		local pr = prayerOf(player)
		return 1 + fraction(pr and (tonumber(pr.mana) or 1) - 1, 2)
	end
	local baseMitigate = L.mitigate
	function L.mitigate(r, raw, style, player)
		if player ~= nil then raw = raw * L.prayerOffence(player, style) end
		return baseMitigate(r, raw, style)
	end
	local baseLandHit = L.landHit
	function L.landHit(player, r, dealt, style, spellId)
		local fresh = r.hp >= r.maxHp
		local applied = baseLandHit(player, r, dealt, style, spellId)
		local pr = applied > 0 and prayerOf(player)
		local sap = pr and fraction(pr.sap, 1) or 0
		local PR = Data.Prayer
		if sap > 0 and PR and r.alive and r.hp > 0 then
			r.baseDefense = r.baseDefense or r.defense or 0
			-- A monster back at full health (fresh or leash-healed) has shaken off old saps.
			if fresh then r.defense = r.baseDefense end
			r.defense = PR.sapped(r.defense, r.baseDefense, sap)
		end
		return applied
	end
	-- End Prayer section.

	------------------------------------------------------------------------
	-- Slayer tasks section (Slayer team). Data.SlayerTasks. Bridge "stats"
	-- carries info.slayer = {level, family, visor = {damage, accuracy} | nil}.
	--   * Slayer-only monsters (def.slayerLevel, superiors inherit it): a player
	--     below that Slayer level cannot target them (reason "slayer"; the
	--     Adventure script explains it through bridge "slayerDenied", rate-limited
	--     here to one call per C.DENIED_NOTICE_GAP), a multishot never splashes
	--     them, mitigate() deals them 0 and they never aggro such a player.
	--   * Task credit: bridge "kill" carries task = L.taskCredit (ST.taskEligible:
	--     >= ST.TASK_SHARE of max health or the top damager); kill credit is unchanged.
	--   * Hunter's Visor: against monsters of the player's task family
	--     (a superior counts as its base): raw damage x (1 + damage%) and ranged
	--     accuracy x (1 + accuracy%) within the style's hit ceiling.
	--   * Superiors: the bridge "kill" reply may carry superior = {id, seq}
	--     (Data.SlayerTasks.Superiors[id].base must be the monster just killed).
	--     It is queued (L.pendingSuperiors) and spawned at that monster's position,
	--     owned by the killer: only the owner may hit it, it only ever targets
	--     its owner (idle otherwise); credit like a sea
	--     creature (dealt damage, alive, within C.CREDIT_RANGE); it never respawns
	--     and withdraws after Data.SlayerTasks.SUPERIOR_LIFETIME. Kill or withdrawal
	--     reports bridge "slayerSuperior" {seq, monster, result = "kill"|"despawn"}
	--     (an unapplied kill report is resent like a sea creature's);
	--     the owner leaving removes it silently (the server forgets the ticket).
	------------------------------------------------------------------------
	local ST = Data.SlayerTasks
	local superiorOwned = {} -- [player] = {[record] = true}
	local superiorQueue = {} -- {{player, id, seq, def, at}}
	local function pct(v, cap)
		v = tonumber(v)
		if not v or v ~= v or v <= 0 then return 0 end
		return math.min(v, cap)
	end
	local function slayerInfo(player, fetch)
		local info = if fetch then L.statsFor(player) else L.peekStats(player)
		return type(info) == "table" and type(info.slayer) == "table" and info.slayer or nil
	end
	function L.slayerLevelOf(player, fetch)
		local s = slayerInfo(player, fetch)
		return math.max(1, math.floor(tonumber(s and s.level) or 1))
	end
	-- May this player harm r (Slayer level gate)?
	function L.slayerGate(player, r, fetch)
		local need = tonumber(r and r.def and r.def.slayerLevel) or 0
		if need <= 0 then return true end
		return L.slayerLevelOf(player, fetch) >= need
	end
	-- The visor bonus that applies to this hit, or nil.
	function L.visorFor(player, r)
		local s = slayerInfo(player)
		if not s or type(s.visor) ~= "table" or not ST or not r then return nil end
		local id = if r.superior and r.def then r.def.base else r.id
		if not ST.inFamily(s.family, id) then return nil end
		return s.visor
	end
	-- Drops a player's cached "stats" (runtime: SlayerTask / SlayerVisor attribute
	-- changes) so the task family and visor bonus are re-read on the next use.
	function L.invalidateStats(player) statsCache[player] = nil end
	-- Aggro: superiors only ever pick their owner; slayer-only monsters never
	-- pick a player below their Slayer level (cached stats; unknown = Slayer 1).
	-- Normal kill credit rules are unchanged.
	function L.aggroAllowed(r, player)
		if r.superior then return player == r.owner end
		return L.slayerGate(player, r)
	end
	-- Slayer task credit for one credited killer (ST.taskEligible): at least
	-- ST.TASK_SHARE of max health, or the top damager. A 1-damage tag-along
	-- keeps its kill credit but earns no task progress, Slayer XP or superior roll.
	function L.taskCredit(r, player)
		local top = 0
		for _, c in pairs(r.contributors) do top = math.max(top, c.damage) end
		if not ST then return top > 0 and L.contribution(r, player) >= top end
		return ST.taskEligible(L.contribution(r, player), r.maxHp, top)
	end
	local deniedAt = {} -- [player] = time the next "slayerDenied" notice may be bridged
	local slayerValidate = L.validateTarget
	function L.validateTarget(player, target, range)
		local ok, r, pos = slayerValidate(player, target, range)
		if not ok then return ok, r end
		if r.superior and r.owner ~= player then return false, "owner" end
		if not L.slayerGate(player, r, true) then
			-- Rate-limited here, before the bridge: spammed refused swings cost one call per window.
			local now = env.now()
			if now >= (deniedAt[player] or -math.huge) then
				deniedAt[player] = now + C.DENIED_NOTICE_GAP
				env.bridge("slayerDenied", player, {monster = r.id})
			end
			return false, "slayer"
		end
		return ok, r, pos
	end
	local slayerSplash = L.multishotTargets
	function L.multishotTargets(player, primary, pos, reach, count)
		local out = {}
		for _, r in ipairs(slayerSplash(player, primary, pos, reach, count)) do
			if L.slayerGate(player, r) and not (r.superior and r.owner ~= player) then table.insert(out, r) end
		end
		return out
	end
	local slayerMitigate = L.mitigate
	function L.mitigate(r, raw, style, player)
		if player ~= nil then
			if not L.slayerGate(player, r) then return 0, nil end
			local v = L.visorFor(player, r)
			if v then raw = raw * (1 + pct(v.damage, 100) / 100) end
		end
		return slayerMitigate(r, raw, style, player)
	end
	local aimedAt = nil -- the record a ranged hit is being rolled against
	local slayerRangedHit = L.rangedHit
	function L.rangedHit(player, r, ...)
		aimedAt = r
		local hit = slayerRangedHit(player, r, ...)
		aimedAt = nil
		return hit
	end
	local slayerAccuracy = L.prayerAccuracy
	function L.prayerAccuracy(player, chance)
		chance = slayerAccuracy(player, chance)
		local v = aimedAt and L.visorFor(player, aimedAt)
		local bonus = v and pct(v.accuracy, 100) or 0
		if bonus <= 0 then return chance end
		return math.min(math.max(chance, tonumber(CS.hitCeiling) or 0.98), chance * (1 + bonus / 100))
	end
	-- Superiors ------------------------------------------------------------------
	function L.superiorLifetime() return (ST and tonumber(ST.SUPERIOR_LIFETIME)) or 240 end
	function L.onKillReply(player, r, reply)
		local sup = type(reply) == "table" and type(reply.superior) == "table" and reply.superior or nil
		if not sup or not ST then return nil end
		local id, seq = sup.id, tonumber(sup.seq)
		local def = type(id) == "string" and ST.Superiors[id]
		if not def or not seq or seq < 1 or seq % 1 ~= 0 or def.base ~= r.id then return nil end
		local spec = {player = player, id = id, seq = seq, def = def, at = r.position}
		table.insert(superiorQueue, spec)
		return spec
	end
	function L.pendingSuperiors()
		local due = superiorQueue
		superiorQueue = {}
		return due
	end
	-- A kill report that was not applied (journal not live: nil or reason "sync")
	-- is resent every C.SEA_RETRY_DELAY until `deadline` (the server ticket's
	-- grace), exactly like sea creatures; tickets settle once, so resends are safe.
	local superiorRetry = {} -- [player] = {[seq] = {id, seq, at, deadline}}
	function L.reportSuperior(player, id, seq, result, deadline)
		env.bridge("slayerSuperior", player, {monster = id, seq = seq, result = result}, function(reply)
			if result ~= "kill" or not deadline then return end
			if reply == nil or (type(reply) == "table" and reply.reason == "sync") then
				if env.now() + C.SEA_RETRY_DELAY > deadline then return end
				superiorRetry[player] = superiorRetry[player] or {}
				superiorRetry[player][seq] = {id = id, seq = seq, at = env.now() + C.SEA_RETRY_DELAY, deadline = deadline}
			end
		end)
	end
	-- Superior kill reports due for a resend: {player, id, seq, deadline}; each fires once.
	function L.dueSuperiorRetries()
		local now, due = env.now(), {}
		for player, list in pairs(superiorRetry) do
			for seq, job in pairs(list) do
				if now >= job.at then
					list[seq] = nil
					if now <= job.deadline then table.insert(due, {player = player, id = job.id, seq = seq, deadline = job.deadline}) end
				end
			end
			if not next(list) then superiorRetry[player] = nil end
		end
		return due
	end
	-- Runtime could not build (or the owner left before the spawn): free the ticket.
	function L.superiorFailed(spec) L.reportSuperior(spec.player, spec.id, spec.seq, "despawn") end
	function L.registerSuperior(spec, model, position, opts)
		if spec.registered then return nil end
		spec.registered = true
		opts = opts or {}
		local def, player = spec.def, spec.player
		local r = newRecord({
			id = spec.id, def = def, superior = true, add = true, owner = player, seq = spec.seq, name = def.name, level = def.level,
			maxHp = def.hp, hp = def.hp, damage = def.damage, defense = def.defense or 0, speed = def.speed or 12,
			attackCooldown = L.monsterCooldown(def.speed), passive = false, provoked = true,
			home = position, position = position, model = model, expires = env.now() + L.superiorLifetime(),
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS), target = player,
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
		})
		superiorOwned[player] = superiorOwned[player] or {}
		superiorOwned[player][r] = true
		return r
	end
	function L.superiorCount(player)
		local n = 0
		for _ in pairs(superiorOwned[player] or {}) do n += 1 end
		return n
	end
	function L.superiorCredit(r)
		local owner = r.owner
		if L.contribution(r, owner) <= 0 or not env.alive(owner) then return {} end
		local pos = env.position(owner)
		if not pos or (pos - r.position).Magnitude > C.CREDIT_RANGE then return {} end
		return {owner}
	end
	local slayerUnregister = L.unregister
	function L.unregister(r, noRespawn)
		if r.superior then
			local owned = superiorOwned[r.owner]
			if owned then
				owned[r] = nil
				if not next(owned) then superiorOwned[r.owner] = nil end
			end
		end
		return slayerUnregister(r, noRespawn)
	end
	local slayerKill = L.kill
	function L.kill(r)
		if not r.superior then return slayerKill(r) end
		r.hp = 0
		local credited = L.superiorCredit(r)
		L.unregister(r)
		L.payXp(r, credited)
		L.reportSuperior(r.owner, r.id, r.seq, if #credited > 0 then "kill" else "despawn", r.expires + C.SEA_REPORT_GRACE)
		return credited
	end
	-- Withdraws superiors past their lifetime; returns the records removed.
	function L.superiorTick()
		local now, gone = env.now(), {}
		for _, owned in pairs(superiorOwned) do
			for r in pairs(owned) do if now >= r.expires then table.insert(gone, r) end end
		end
		for _, r in ipairs(gone) do
			L.unregister(r)
			L.reportSuperior(r.owner, r.id, r.seq, "despawn")
		end
		return gone
	end
	local slayerRemoving = L.playerRemoving
	function L.playerRemoving(player)
		local owned = {}
		for r in pairs(superiorOwned[player] or {}) do table.insert(owned, r) end
		for _, r in ipairs(owned) do L.unregister(r) end
		local i = 1
		while i <= #superiorQueue do
			if superiorQueue[i].player == player then table.remove(superiorQueue, i) else i += 1 end
		end
		superiorRetry[player], deniedAt[player] = nil, nil
		local removed = slayerRemoving(player)
		for _, r in ipairs(owned) do table.insert(removed, r) end
		return removed
	end
	local slayerHasState = L.hasPlayerState
	function L.hasPlayerState(player)
		return slayerHasState(player) or superiorOwned[player] ~= nil or superiorRetry[player] ~= nil or deniedAt[player] ~= nil
	end
	-- End Slayer tasks section.

	------------------------------------------------------------------------
	-- Lairs section (Bossing team). Data.Lairs (LR), docs/DEPTH-CONTRACT.md §25.
	-- One boss record per lair fight (r.lair, r.fight): only the fight's
	-- members (UserIds, fixed when the boss rises) may strike it or its adds;
	-- it never leaves its arena (LR.ARENA_RANGE from r.center).
	--   Stances: the basic attack's style cycles def.stances every
	--   def.stanceEvery swings; a swing into the matching Ward prayer (bridge
	--   "stats" prayer.protect) is multiplied by LR.PRAYED before the bridge
	--   applies the prayer's own reduction. Ranged/magic stances strike from
	--   anywhere in the arena; melee chases.
	--   Specials (L.lrTick): disc / ring / safe telegraphs, tile lattices
	--   (LR.tilePattern cells under LR.cellAt) - all styleless (dodge them) -
	--   brood adds (boss takes LR.WARD damage while any lives) and ordered
	--   sigils (boss immune; only the lowest-numbered sigil can be struck,
	--   refusal "order"). Waves never stack. Phases only advance and may turn
	--   the weakness (LR.weaknessAt); enrage at def.enrage; def.duration ends
	--   the fight ("timeout").
	--   Damage and damage XP are kept per UserId (r.dmg), so a member who
	--   drops and rejoins keeps their share. At the kill, LR.credit decides
	--   each member's credit; credited members are paid their damage XP and the
	--   outcome waits in L.lrResult(fight) for lairs.server.lua (which relays
	--   the reward through bridge "lair").
	------------------------------------------------------------------------
	local LR = Data.Lairs
	local lairFights = {}   -- [fight] = boss record
	local lairResults = {}  -- [fight] = {result, credit = {[uid] = {share, damage, ok, reason}}, seconds, party}
	local lairAlert = 0     -- telegraph sequence (HUD notices)
	local function lairBossOf(r)
		if r.lair then return r end
		if r.lairAdd then return r.parent end
		return nil
	end
	function L.lrRecord(fight) return lairFights[fight] end
	function L.lrResult(fight) return lairResults[fight] end
	function L.lrForget(fight) lairResults[fight] = nil end
	function L.lrCount()
		local n = 0
		for _, r in pairs(lairFights) do n += 1; for _ in pairs(r.adds) do n += 1 end end
		return n
	end
	function L.lrRegister(fight, bossId, model, position, opts)
		local def = LR and LR.boss(bossId)
		if type(fight) ~= "string" or not def or lairFights[fight] then return nil end
		local count = 0
		for _, other in pairs(lairFights) do if not other.raid and not other.story then count += 1 end end -- Raids section: raid encounters have their own cap (§53: story encounters too)
		if count >= LR.MAX_INSTANCES then return nil end
		opts = opts or {}
		local now = env.now()
		local members, party = {}, 0
		for _, uid in ipairs(type(opts.members) == "table" and opts.members or {}) do
			if type(uid) == "number" and not members[uid] and party < LR.MAX_PARTY then members[uid] = true; party += 1 end
		end
		if party == 0 then return nil end
		-- opts.party: members inside at the rise (held offline members do not scale health).
		local hp = LR.partyHp(def, math.clamp(math.floor(tonumber(opts.party) or party), 1, party))
		local weakness, defenceStyle = LR.weaknessAt(def, 1)
		local center = typeof(opts.center) == "Vector3" and opts.center or position
		local r = newRecord({
			id = bossId, def = def, lair = true, fight = fight, name = def.name, level = def.level, maxHp = hp, hp = hp,
			damage = def.damage, defense = def.defense, speed = def.speed, attackCooldown = LR.ATTACK_SECONDS, passive = false, provoked = true,
			home = position, position = position, model = model, radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
			weakness = weakness, defenceStyle = defenceStyle, attackStyle = LR.stanceAt(def, 1, 1), swings = 0,
			phase = 1, step = 0, nextSpecial = now + 5, nextHit = now + 2.5, telegraphs = {}, adds = {}, members = members, party = party,
			dmg = {}, started = now, enrageAt = now + def.enrage, expires = now + def.duration, lastSeen = now,
			seed = math.floor(tonumber(opts.seed) or 1), center = center, ground = if type(opts.ground) == "number" then opts.ground else center.Y,
		})
		lairFights[fight] = r
		lairResults[fight] = nil
		return r
	end
	function L.lrNextOrder(boss)
		local best
		for a in pairs(boss.adds) do if a.order and (not best or a.order < best) then best = a.order end end
		return best
	end
	function L.lrSealed(boss) return L.lrNextOrder(boss) ~= nil end
	function L.lrWarded(boss)
		for a in pairs(boss.adds) do if not a.order then return true end end
		return false
	end
	function L.lrRegisterAdd(boss, addId, model, position, opts)
		local def = LR and LR.Adds[addId]
		if not boss or not boss.alive or not boss.lair or not def then return nil end
		local n = 0
		for _ in pairs(boss.adds) do n += 1 end
		if n >= LR.MAX_ADDS then return nil end
		opts = opts or {}
		local r = newRecord({
			id = addId, def = def, add = true, lairAdd = true, parent = boss, fight = boss.fight, name = def.name, level = def.level,
			maxHp = def.hp, hp = def.hp, damage = def.damage, defense = def.defense, speed = def.speed, attackCooldown = L.monsterCooldown(def.speed),
			passive = false, provoked = true, home = position, position = position, model = model,
			radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS), stationary = def.stationary == true,
			order = if type(opts.order) == "number" then opts.order else nil,
			weakness = def.weakness, defenceStyle = def.defenceStyle, attackStyle = def.attackStyle,
		})
		boss.adds[r] = true
		return r
	end
	-- Members alive inside the arena, in player-list order.
	local function lairPlayers(boss)
		local list = {}
		for _, player in ipairs(playerList()) do
			local uid = uidOf(player)
			if uid and boss.members[uid] and isAlive(player) then
				local pos = positionOf(player)
				if pos and flatDist(pos, boss.center) <= LR.ARENA_RANGE then table.insert(list, player) end
			end
		end
		return list
	end
	L.lrPlayers = lairPlayers
	-- Lair rule for one player striking r: nil = allowed, else the refusal.
	function L.lrRefusal(player, r)
		local boss = lairBossOf(r)
		if not boss then return nil end
		local uid = uidOf(player)
		if not (uid and boss.members[uid]) then return "lair" end
		if r.lair and L.lrSealed(r) then return "sealed" end
		if r.lairAdd and r.order and r.order ~= L.lrNextOrder(boss) then return "order" end
		return nil
	end
	local lairValidate = L.validateTarget
	function L.validateTarget(player, target, range)
		local ok, r, pos = lairValidate(player, target, range)
		if not ok then return ok, r, pos end
		local refusal = L.lrRefusal(player, r)
		if refusal then return false, refusal end
		return true, r, pos
	end
	local lairSplash = L.multishotTargets
	function L.multishotTargets(player, primary, pos, reach, count)
		local out = {}
		for _, r in ipairs(lairSplash(player, primary, pos, reach, count)) do
			if not L.lrRefusal(player, r) then table.insert(out, r) end
		end
		return out
	end
	local lairMitigate = L.mitigate
	function L.mitigate(r, raw, style, player)
		local dealt, tag = lairMitigate(r, raw, style, player)
		if r.lair and L.lrWarded(r) then dealt = math.floor(dealt * LR.WARD) end
		return dealt, tag
	end
	-- Damage, the last action and damage XP per UserId (kept across a rejoin).
	local lairLand = L.landHit
	function L.landHit(player, r, dealt, style, spellId)
		local applied = lairLand(player, r, dealt, style, spellId)
		local boss = lairBossOf(r)
		local uid = boss and uidOf(player)
		if uid and boss.members[uid] then
			local d = boss.dmg[uid]
			if not d then d = {damage = 0, xp = {}}; boss.dmg[uid] = d end
			d.lastHit = env.now()
			if r.lair then
				d.damage += applied
				if applied > 0 then d.xp[style] = (d.xp[style] or 0) + applied end
			end
		end
		return applied
	end
	-- A stance attack: the prayer check, then bridge "damage" with the style.
	function L.lrStrike(r, player, style, amount)
		lastHurt[player] = env.now()
		local info = L.statsFor(player)
		local pr = type(info) == "table" and type(info.prayer) == "table" and info.prayer or nil
		local mult = LR.prayerMult(style, pr and pr.protect)
		local dealt = math.max(1, math.floor(amount * mult))
		env.bridge("damage", player, {amount = dealt, style = style})
		return dealt, mult < 1
	end
	function L.lrSwing(r, player)
		local now = env.now()
		r.nextHit = now + r.attackCooldown
		r.lungeUntil = now + 0.25
		r.swings += 1
		local dealt, prayed = L.lrStrike(r, player, r.attackStyle, r.damage)
		r.lastSwing = {player = player, style = r.attackStyle, amount = dealt, prayed = prayed}
		local nextStyle = LR.stanceAt(r.def, r.phase, r.swings + 1)
		if nextStyle ~= r.attackStyle then
			r.attackStyle = nextStyle
			r.stanceChanged = true
		end
		return dealt
	end
	function L.lrThink(r)
		local now = env.now()
		local best, bestD
		for _, player in ipairs(lairPlayers(r)) do
			local d = flatDist(positionOf(player), r.position)
			if not bestD or d < bestD then best, bestD = player, d end
		end
		r.target = best
		if not best then
			if flatDist(r.position, r.home) > C.RETURN_RADIUS then return {kind = "leash", goal = r.home, speed = r.speed, stop = 0} end
			return {kind = "idle"}
		end
		local pos = positionOf(best)
		local reach = C.MONSTER_REACH + r.radius
		local melee = r.attackStyle == "melee"
		if not melee or bestD <= reach then
			if now >= r.nextHit then
				L.lrSwing(r, best)
				return {kind = "strike", face = pos, target = best}
			end
			return {kind = "hold", face = pos}
		end
		local goal = pos
		local offset = flat(pos) - flat(r.center)
		local limit = LR.ARENA_RANGE - 4
		if offset.Magnitude > limit then goal = r.center + offset.Unit * limit end
		return {kind = "chase", goal = goal, speed = r.speed, face = pos, stop = reach * 0.7}
	end
	function L.lrAddThink(r)
		local boss = r.parent
		if r.stationary or not boss or not boss.alive then return {kind = "idle"} end
		local now = env.now()
		local best, bestD
		for _, player in ipairs(lairPlayers(boss)) do
			local d = flatDist(positionOf(player), r.position)
			if not bestD or d < bestD then best, bestD = player, d end
		end
		r.target = best
		if not best then return {kind = "idle"} end
		local pos = positionOf(best)
		local reach = C.MONSTER_REACH + r.radius
		if bestD <= reach then
			if now >= r.nextHit then
				L.strike(r, best)
				return {kind = "strike", face = pos, target = best}
			end
			return {kind = "hold", face = pos}
		end
		return {kind = "chase", goal = pos, speed = r.speed, face = pos, stop = reach * 0.7}
	end
	local lairThink = L.think
	function L.think(r)
		if r.alive and r.lair then return L.lrThink(r) end
		if r.alive and r.lairAdd then return L.lrAddThink(r) end
		return lairThink(r)
	end
	-- Removes a fight's adds and boss without a result; returns the records removed.
	local function lairRemove(r)
		local removed = {}
		for add in pairs(r.adds) do table.insert(removed, add) end
		for _, add in ipairs(removed) do L.unregister(add) end
		if lairFights[r.fight] == r then lairFights[r.fight] = nil end
		if records[r] then L.unregister(r) end
		table.insert(removed, r)
		return removed
	end
	function L.lrDespawn(fight)
		local r = lairFights[fight]
		lairResults[fight] = nil
		if not r then return {} end
		return lairRemove(r)
	end
	function L.lrKill(r)
		local now = env.now()
		r.hp = 0
		local credit, credited = {}, {}
		local uids = {}
		for uid in pairs(r.members) do table.insert(uids, uid) end
		table.sort(uids)
		for _, uid in ipairs(uids) do
			local d = r.dmg[uid]
			local player = onlineByUserId(uid)
			local alive = player ~= nil and env.alive(player) == true
			local pos = alive and env.position(player) or nil
			local info = player and L.peekStats(player)
			local share = if d then d.damage / r.maxHp else 0
			local ok, reason = LR.credit({party = r.party, share = share, member = true, alive = alive,
				inside = pos ~= nil and flatDist(pos, r.center) <= LR.ARENA_RANGE, lastHit = d and d.lastHit, now = now,
				ironman = info ~= nil and info.ironman == true})
			credit[uid] = {share = share, damage = if d then math.floor(d.damage) else 0, ok = ok == true, reason = reason}
			if ok then
				table.insert(credited, player)
				for _, style in ipairs(XP_STYLES) do
					local dmg = d.xp[style]
					if dmg and dmg > 0 then L.reportXp(player, r, style, dmg) end
				end
			end
		end
		r.removedAdds = lairRemove(r)
		table.remove(r.removedAdds) -- the boss itself (its view goes with the kill)
		lairResults[r.fight] = {result = "win", credit = credit, seconds = now - r.started, party = r.party}
		return credited
	end
	local lairKill = L.kill
	function L.kill(r)
		if r.lair then return L.lrKill(r) end
		if r.lairAdd then
			r.hp = 0
			local credited = {}
			local boss = r.parent
			for player, c in pairs(r.contributors) do
				local uid = uidOf(player)
				if c.damage > 0 and env.alive(player) and boss and uid and boss.members[uid] then table.insert(credited, player) end
			end
			L.unregister(r)
			L.payXp(r, credited)
			return credited
		end
		return lairKill(r)
	end
	-- Advances every live fight. Returns events for the runtime:
	-- {kind = "telegraph"|"strike"|"phase"|"stance"|"enrage"|"adds"|"timeout", record, ...}.
	function L.lrTick()
		local now, events = env.now(), {}
		local ids = {}
		for fight in pairs(lairFights) do table.insert(ids, fight) end
		table.sort(ids)
		for _, fight in ipairs(ids) do
			local r = lairFights[fight]
			local def = r.def
			if now >= r.expires then
				local removed = lairRemove(r)
				lairResults[fight] = {result = "timeout", credit = {}, seconds = now - r.started, party = r.party}
				table.insert(events, {kind = "timeout", record = r, removed = removed})
				continue
			end
			local phase = math.max(r.phase, LR.phaseAt(def, r.hp / r.maxHp))
			if phase > r.phase then
				r.phase, r.step = phase, 0
				r.weakness, r.defenceStyle = LR.weaknessAt(def, phase)
				local style = LR.stanceAt(def, phase, r.swings + 1)
				if style ~= r.attackStyle then r.attackStyle, r.stanceChanged = style, true end
				r.nextSpecial = math.min(r.nextSpecial, now + 2)
				table.insert(events, {kind = "phase", record = r, phase = phase})
			end
			if r.stanceChanged then
				r.stanceChanged = nil
				table.insert(events, {kind = "stance", record = r, style = r.attackStyle})
			end
			if not r.enraged and now >= r.enrageAt then
				r.enraged = true
				r.damage = math.floor(def.damage * LR.ENRAGE_DAMAGE)
				r.attackCooldown = LR.ATTACK_SECONDS * LR.ENRAGE_TEMPO
				table.insert(events, {kind = "enrage", record = r})
			end
			local inside = lairPlayers(r)
			-- Resolve telegraphs whose windup has elapsed.
			local i = 1
			while i <= #r.telegraphs do
				local tg = r.telegraphs[i]
				if now >= tg.resolveAt then
					table.remove(r.telegraphs, i)
					local hits = {}
					for _, player in ipairs(inside) do
						local pos = positionOf(player)
						local struck
						if tg.kind == "tiles" then
							local cell = LR.cellAt(pos.X - r.center.X, pos.Z - r.center.Z)
							struck = cell ~= nil and tg.charged[cell] == true
						else
							struck = LR.struck(tg.attack, tg.center.X, tg.center.Z, pos.X, pos.Z)
						end
						if struck then
							local amount = math.floor(r.damage * tg.attack.mult)
							lastHurt[player] = now
							env.bridge("damage", player, {amount = amount}) -- styleless: prayers do not help
							table.insert(hits, {player = player, amount = amount})
						end
					end
					table.insert(events, {kind = "strike", record = r, telegraph = tg, hits = hits})
				else
					i += 1
				end
			end
			-- A fight with nobody inside holds its rotation (paused while members rejoin).
			if #inside == 0 then
				r.nextSpecial = math.max(r.nextSpecial, now + 2)
				r.nextHit = math.max(r.nextHit, now + 1)
				continue
			end
			r.lastSeen = now
			if now >= r.nextSpecial then
				r.step += 1
				local attackId = LR.attackAt(def, r.phase, r.step)
				local a = def.attacks[attackId]
				r.nextSpecial = now + LR.interval(def, r.phase, r.enraged)
				if a.kind == "adds" or a.kind == "sigils" then
					if not next(r.adds) then
						table.insert(events, {kind = "adds", record = r, attack = a, add = a.add, count = math.min(a.count, LR.MAX_ADDS), ordered = a.kind == "sigils"})
					end
				else
					lairAlert += 1
					local tg = {id = attackId, attack = a, kind = a.kind, name = a.name, resolveAt = now + a.windup, windup = a.windup, seq = lairAlert}
					if a.kind == "tiles" then
						tg.cells = LR.tilePattern(r.seed, r.step + 100 * r.phase, a.count)
						tg.charged = {}
						for _, cell in ipairs(tg.cells) do tg.charged[cell] = true end
						tg.center = r.center
					else
						local center = r.position
						if a.kind == "disc" then
							local victim = inside[1 + math.floor(env.rng() * #inside) % #inside]
							center = positionOf(victim)
							tg.victim = victim
						end
						tg.center = Vector3.new(center.X, r.ground, center.Z)
						tg.radius = a.radius
					end
					r.alert = {seq = tg.seq, name = a.name, kind = a.kind}
					table.insert(r.telegraphs, tg)
					table.insert(events, {kind = "telegraph", record = r, telegraph = tg})
				end
			end
		end
		return events
	end
	-- Fight status for lairs.server.lua (HUD, result, notices).
	function L.lrStatus(fight)
		local r = lairFights[fight]
		local result = lairResults[fight]
		if not r then return {alive = false, result = result and result.result, outcome = result} end
		local now = env.now()
		local every = math.max(1, r.def.stanceEvery or 99)
		local stances = LR.stances(r.def, r.phase)
		local switchIn = if #stances > 1 then every - (r.swings % every) else nil
		local adds, order = 0, L.lrNextOrder(r)
		for _ in pairs(r.adds) do adds += 1 end
		local phase = r.def.phases[r.phase]
		return {alive = true, boss = r.id, hp = math.max(0, math.floor(r.hp)), maxHp = r.maxHp, phase = r.phase, phases = #r.def.phases,
			phaseName = phase and phase.name, style = r.attackStyle, nextStyle = LR.stanceAt(r.def, r.phase, r.swings + every - (r.swings % every) + 1),
			switchIn = switchIn, weakness = r.weakness, enraged = r.enraged == true, enrageIn = math.max(0, math.ceil(r.enrageAt - now)),
			endsIn = math.max(0, math.ceil(r.expires - now)), elapsed = math.floor(now - r.started), warded = L.lrWarded(r), sealed = order ~= nil,
			order = order, adds = adds, party = r.party, alert = r.alert, inside = #lairPlayers(r)}
	end
	local lairUnregister = L.unregister
	function L.unregister(r, noRespawn)
		if r.lair then
			if not records[r] then return end
			records[r] = nil
			r.alive = false
			if r.model ~= nil and byModel[r.model] == r then byModel[r.model] = nil end
			if lairFights[r.fight] == r then lairFights[r.fight] = nil end
			return
		end
		return lairUnregister(r, noRespawn)
	end
	local lairRemoving = L.playerRemoving
	function L.playerRemoving(player)
		-- r.dmg is keyed by UserId and survives; only the Player-keyed state goes.
		return lairRemoving(player)
	end
	-- End Lairs section.

	------------------------------------------------------------------------
	-- Raids section (Raid team). Data.Raids (RD), docs/DEPTH-CONTRACT.md §38.
	-- A raid encounter is a lair-shaped record (r.lair, r.raid, r.fight) in
	-- the Lairs fight table, so the Lairs machinery runs it unchanged:
	-- membership, stances and the prayer check, telegraphs, tiles, adds /
	-- sigils (LR.Adds resolves raid adds), phases, enrage, timeout and per-
	-- UserId damage. Only registration (party up to RD.MAX_PARTY, health and
	-- damage scaled by party size and Challenge Mode, its own cap of
	-- RD.MAX_RAIDS live encounters) and the kill differ: every member who
	-- dealt damage is paid damage XP, and raids.server.lua turns the per-UserId
	-- damage into points (no LR.credit fair-share gate: the raid's own credit
	-- rules apply at the end of the run).
	------------------------------------------------------------------------
	do
		local RD = Data.Raids
		function L.rdRegister(fight, encId, model, position, opts)
			local base = RD and RD.encounter(encId)
			if type(fight) ~= "string" or not base or lairFights[fight] then return nil end
			local live = 0
			for _, r in pairs(lairFights) do if r.raid then live += 1 end end
			if live >= RD.MAX_RAIDS then return nil end
			opts = opts or {}
			local now = env.now()
			local members, party = {}, 0
			for _, uid in ipairs(type(opts.members) == "table" and opts.members or {}) do
				if type(uid) == "number" and not members[uid] and party < RD.MAX_PARTY then members[uid] = true; party += 1 end
			end
			if party == 0 then return nil end
			local inside = math.clamp(math.floor(tonumber(opts.party) or party), 1, party)
			local challenge = opts.challenge == true
			local def = RD.scaledDef(encId, inside, challenge)
			local hp = RD.partyHp(base, inside, challenge)
			local weakness, defenceStyle = LR.weaknessAt(def, 1)
			local center = typeof(opts.center) == "Vector3" and opts.center or position
			local r = newRecord({
				id = encId, def = def, lair = true, raid = true, challenge = challenge, fight = fight, name = def.name, level = def.level, maxHp = hp, hp = hp,
				damage = def.damage, defense = def.defense, speed = def.speed, attackCooldown = LR.ATTACK_SECONDS, passive = false, provoked = true,
				home = position, position = position, model = model, radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
				weakness = weakness, defenceStyle = defenceStyle, attackStyle = LR.stanceAt(def, 1, 1), swings = 0,
				phase = 1, step = 0, nextSpecial = now + 5, nextHit = now + 2.5, telegraphs = {}, adds = {}, members = members, party = inside,
				dmg = {}, started = now, enrageAt = now + def.enrage, expires = now + def.duration, lastSeen = now,
				seed = math.floor(tonumber(opts.seed) or 1), center = center, ground = if type(opts.ground) == "number" then opts.ground else center.Y,
			})
			lairFights[fight] = r
			lairResults[fight] = nil
			return r
		end
		-- Per-UserId damage and last hit (the boss's own and its adds' last hits),
		-- read by raids.server.lua every step for points and recent actions.
		function L.rdDamage(fight)
			local r = lairFights[fight]
			if not r or not r.raid then return nil end
			local out = {}
			for uid, d in pairs(r.dmg) do out[uid] = {damage = math.floor(d.damage), lastHit = d.lastHit} end
			return out
		end
		function L.rdKill(r)
			local now = env.now()
			r.hp = 0
			local credit, credited = {}, {}
			for uid in pairs(r.members) do
				local d = r.dmg[uid]
				local player = onlineByUserId(uid)
				local share = if d then d.damage / r.maxHp else 0
				credit[uid] = {share = share, damage = if d then math.floor(d.damage) else 0, lastHit = d and d.lastHit, ok = share > 0}
				if share > 0 and player and env.alive(player) == true then
					table.insert(credited, player)
					for _, style in ipairs(XP_STYLES) do
						local dmg = d.xp[style]
						if dmg and dmg > 0 then L.reportXp(player, r, style, dmg) end
					end
				end
			end
			r.removedAdds = lairRemove(r)
			table.remove(r.removedAdds) -- the encounter itself (its view goes with the kill)
			lairResults[r.fight] = {result = "win", credit = credit, seconds = now - r.started, party = r.party}
			return credited
		end
		-- Lead decision (QC): the raid weapons' specials (Data.Raids.tideMult).
		-- An add is a boss's add (r.parent: lair / raid adds, world boss waves;
		-- never a slayer superior); a boss is a slayer / world / lair / raid boss
		-- record; warded = a lair, raid or world boss with live adds or seals.
		function L.tideMult(weaponId, r)
			if not RD or not RD.tideMult or type(r) ~= "table" or type(weaponId) ~= "string" then return 1 end
			local add = (r.add == true or r.lairAdd == true) and r.parent ~= nil
			local boss = not add and (r.boss == true or r.worldBoss == true or r.lair == true)
			local warded = boss and (r.worldBoss == true or r.lair == true) and type(r.adds) == "table" and next(r.adds) ~= nil
			return RD.tideMult(weaponId, {add = add, boss = boss, raid = not add and r.raid == true, warded = warded})
		end
		local raidKill = L.kill
		function L.kill(r)
			if r.raid and r.lair and not r.lairAdd then return L.rdKill(r) end
			return raidKill(r)
		end
	end
	-- End Raids section.

	------------------------------------------------------------------------
	-- Combat Feats section (Feats team). Data.Feats, docs/DEPTH-CONTRACT.md §45.
	-- Server-side fight records for feat detection (never client-reported):
	--   lair / raid encounters keep r.feat[uid] = {mech (telegraph hits taken),
	--   cast (telegraphs resolved), hitBy[attackId], seen[attackId], swings
	--   (stance swings taken), prayed (into the matching Ward), ward (any Ward
	--   up), adds (distinct adds / sigils / anchors struck), styles, armor (most
	--   armour pieces worn on a landed hit, from bridge "stats" armor)}; the
	--   kill copies each member's record into its credit entry (credit[uid].feat)
	--   for lairs.server.lua / raids.server.lua to relay. Slayer bosses count
	--   the owner's hits taken (r.featHits) and report {seconds, hits}.
	------------------------------------------------------------------------
	do
		local function featOf(boss, uid)
			boss.feat = boss.feat or {}
			local f = boss.feat[uid]
			if not f then
				f = {mech = 0, cast = 0, swings = 0, prayed = 0, ward = 0, adds = 0, styles = {}, hitBy = {}, seen = {}, addSeen = {}}
				boss.feat[uid] = f
			end
			return f
		end
		L.featOf = featOf
		local function member(boss, player)
			local uid = uidOf(player)
			if uid and boss and type(boss.members) == "table" and boss.members[uid] then return uid end
			return nil
		end
		local featLrStrike = L.lrStrike
		function L.lrStrike(r, player, style, amount)
			local dealt, prayed = featLrStrike(r, player, style, amount)
			local uid = member(r, player)
			if uid then
				local f = featOf(r, uid)
				f.swings += 1
				if prayed then f.prayed += 1 end
				local info = L.peekStats(player)
				local pr = type(info) == "table" and type(info.prayer) == "table" and info.prayer or nil
				if pr and pr.protect ~= nil then f.ward += 1 end
			end
			return dealt, prayed
		end
		local featLrTick = L.lrTick
		function L.lrTick()
			local events = featLrTick()
			for _, e in ipairs(events) do
				if e.kind == "strike" and e.record and e.telegraph then
					local r, id = e.record, tostring(e.telegraph.id)
					-- QC H2: only members alive inside the arena as it resolves saw it; a member
					-- held offline / outside / down is marked absent (no perfection that fight).
					local inside = {}
					for _, player in ipairs(L.lrPlayers(r)) do local uid = uidOf(player); if uid then inside[uid] = true end end
					for _, h in ipairs(e.hits or {}) do local uid = member(r, h.player); if uid then inside[uid] = true end end
					for uid in pairs(r.members or {}) do
						local f = featOf(r, uid)
						if inside[uid] then
							f.cast += 1
							f.seen[id] = (f.seen[id] or 0) + 1
						else
							f.absent = true
						end
					end
					for _, h in ipairs(e.hits or {}) do
						local uid = member(r, h.player)
						if uid then
							local f = featOf(r, uid)
							f.mech += 1
							f.hitBy[id] = (f.hitBy[id] or 0) + 1
						end
					end
				end
			end
			return events
		end
		local featLand = L.landHit
		function L.landHit(player, r, dealt, style, spellId)
			local applied = featLand(player, r, dealt, style, spellId)
			local boss = if r.lair then r elseif r.lairAdd then r.parent else nil
			local uid = boss and member(boss, player)
			if uid then
				local f = featOf(boss, uid)
				if type(style) == "string" then f.styles[style] = true end
				local info = L.peekStats(player)
				local armor = type(info) == "table" and tonumber(info.armor) or nil
				if armor then f.armor = math.max(f.armor or 0, armor) end
				if r.lairAdd and applied > 0 and not f.addSeen[r] then f.addSeen[r] = true; f.adds += 1 end
			elseif r.boss and r.owner == player and type(style) == "string" then
				r.featStyles = r.featStyles or {}
				r.featStyles[style] = true
			end
			return applied
		end
		local featStrike = L.strike
		function L.strike(r, player)
			if r.boss and r.owner == player then r.featHits = (r.featHits or 0) + 1 end
			return featStrike(r, player)
		end
		-- A member's record, as relayed to the journal (no instance keys).
		function L.featSummary(r, uid)
			local f = r.feat and r.feat[uid]
			if not f then return {mech = 0, cast = 0, swings = 0, prayed = 0, ward = 0, adds = 0, styles = {}, hitBy = {}, seen = {}} end
			return {mech = f.mech, cast = f.cast, swings = f.swings, prayed = f.prayed, ward = f.ward, adds = f.adds, armor = f.armor, absent = f.absent == true,
				styles = table.clone(f.styles), hitBy = table.clone(f.hitBy), seen = table.clone(f.seen)}
		end
		local function attach(r)
			local res = L.lrResult(r.fight)
			-- QC H1: the fight's real participants (held-offline members included), not
			-- the party that scaled its health.
			local n = 0
			for _ in pairs(r.members or {}) do n += 1 end
			if res then res.members = n end
			if res and type(res.credit) == "table" then
				for uid, c in pairs(res.credit) do c.feat = L.featSummary(r, uid) end
			end
		end
		local featLrKill = L.lrKill
		function L.lrKill(r)
			local credited = featLrKill(r)
			attach(r)
			return credited
		end
		local featRdKill = L.rdKill
		function L.rdKill(r)
			local credited = featRdKill(r)
			attach(r)
			return credited
		end
	end
	-- End Combat Feats section.

	------------------------------------------------------------------------
	-- Story section (Story team). Data.Story (ST), docs/DEPTH-CONTRACT.md §53.
	-- A story encounter is a solo, lair-shaped record (r.lair, r.story, r.fight)
	-- in the Lairs fight table, so the Lairs machinery runs it: stances and the
	-- prayer check, disc / ring / safe telegraphs, adds / sigils, phases,
	-- enrage, timeout, per-UserId damage. Story-only rules:
	--   * its own cap (ST.MAX_FIGHTS), never counted against the lair cap;
	--   * lanterns: the boss is "shrouded" (refusal) unless the striker stands
	--     in the lit lantern's light; the light moves every def.lanterns.every s
	--     (event "lantern");
	--   * cross / beam / half telegraphs (ST.struck geometry): their direction is
	--     set when raised (tg.ux, tg.uz) and their hits are applied here;
	--   * the kill credits the member alive with damage > 0 (solo) and pays
	--     damage XP; the result waits in L.lrResult for the journal.
	------------------------------------------------------------------------
	do
		local ST = Data.Story
		function L.stRegister(fight, bossId, model, position, opts)
			local def = ST and ST.boss(bossId)
			if type(fight) ~= "string" or not def or lairFights[fight] then return nil end
			local live = 0
			for _, r in pairs(lairFights) do if r.story then live += 1 end end
			if live >= ST.MAX_FIGHTS then return nil end
			opts = opts or {}
			local uid = type(opts.members) == "table" and opts.members[1]
			if type(uid) ~= "number" then return nil end
			local now = env.now()
			local weakness, defenceStyle = LR.weaknessAt(def, 1)
			local center = typeof(opts.center) == "Vector3" and opts.center or position
			local r = newRecord({
				id = bossId, def = def, lair = true, story = true, fight = fight, name = def.name, level = def.level, maxHp = def.hp, hp = def.hp,
				damage = def.damage, defense = def.defense, speed = def.speed, attackCooldown = LR.ATTACK_SECONDS, passive = false, provoked = true,
				home = position, position = position, model = model, radius = math.clamp(opts.radius or 0, 0, C.MAX_RADIUS_BONUS),
				weakness = weakness, defenceStyle = defenceStyle, attackStyle = LR.stanceAt(def, 1, 1), swings = 0,
				phase = 1, step = 0, nextSpecial = now + 5, nextHit = now + 2.5, telegraphs = {}, adds = {}, members = {[uid] = true}, party = 1,
				dmg = {}, started = now, enrageAt = now + def.enrage, expires = now + def.duration, lastSeen = now,
				seed = math.floor(tonumber(opts.seed) or 1), center = center, ground = if type(opts.ground) == "number" then opts.ground else center.Y,
				lit = nil, relightAt = now, lightStep = 0,
			})
			lairFights[fight] = r
			lairResults[fight] = nil
			return r
		end
		-- The shroud: nil = in the light (or no lanterns), else "shrouded".
		function L.stShrouded(player, r)
			if not (r and r.story and r.lair and r.def.lanterns) then return nil end
			local pos = positionOf(player)
			if not pos then return "shrouded" end
			if ST.inLight(r.def, r.lit, pos.X - r.center.X, pos.Z - r.center.Z) then return nil end
			return "shrouded"
		end
		local storyRefusal = L.lrRefusal
		function L.lrRefusal(player, r)
			local refusal = storyRefusal(player, r)
			if refusal then return refusal end
			-- QC M2: a story member strikes only from inside the arena (lrPlayers' range).
			local boss = if r and r.lair then r elseif r and r.lairAdd then r.parent else nil
			if boss and boss.story then
				local pos = positionOf(player)
				if not pos or flatDist(pos, boss.center) > LR.ARENA_RANGE then return "outside" end
			end
			return L.stShrouded(player, r)
		end
		local storyTick = L.lrTick
		function L.lrTick()
			local now = env.now()
			local pre = {}
			for _, r in pairs(lairFights) do
				if r.story and r.def.lanterns and now >= r.relightAt then
					r.lightStep += 1
					r.lit = ST.litLantern(r.seed, r.lightStep, r.def.lanterns.count, r.lit)
					r.relightAt = now + r.def.lanterns.every
					table.insert(pre, {kind = "lantern", record = r, lit = r.lit})
				end
			end
			local events = storyTick()
			for _, e in ipairs(events) do
				local r, tg = e.record, e.telegraph
				if r and r.story and tg and ST.CUSTOM_TELEGRAPH[tg.kind] then
					if e.kind == "telegraph" then
						local angle = ST.telegraphAngle(r.seed, r.step + 100 * r.phase)
						local ux, uz = math.cos(angle), math.sin(angle)
						local origin = r.center
						if tg.kind == "beam" then
							local inside = L.lrPlayers(r)
							local victim = inside[1 + math.floor(env.rng() * #inside) % math.max(1, #inside)]
							local vpos = victim and positionOf(victim)
							origin = r.position
							if vpos then
								local d = Vector3.new(vpos.X - origin.X, 0, vpos.Z - origin.Z)
								if d.Magnitude > 0.5 then ux, uz = d.Unit.X, d.Unit.Z end
								tg.victim = victim
							end
						elseif tg.kind == "cross" then
							origin = r.position
						end
						tg.center = Vector3.new(origin.X, r.ground, origin.Z)
						tg.cx, tg.cz, tg.ux, tg.uz = origin.X, origin.Z, ux, uz
						tg.width, tg.length = tg.attack.width, tg.attack.length
					elseif e.kind == "strike" and tg.cx then
						for _, player in ipairs(L.lrPlayers(r)) do
							local pos = positionOf(player)
							if pos and ST.struck(tg.attack, tg, pos.X, pos.Z) then
								local amount = math.floor(r.damage * tg.attack.mult)
								lastHurt[player] = now
								env.bridge("damage", player, {amount = amount}) -- styleless: prayers do not help
								table.insert(e.hits, {player = player, amount = amount})
							end
						end
					end
				end
			end
			for _, e in ipairs(pre) do table.insert(events, e) end
			return events
		end
		function L.stKill(r)
			local now = env.now()
			r.hp = 0
			local credit, credited = {}, {}
			for uid in pairs(r.members) do
				local d = r.dmg[uid]
				local player = onlineByUserId(uid)
				local aliveNow = player ~= nil and env.alive(player) == true
				local ok = d ~= nil and d.damage > 0 and aliveNow
				credit[uid] = {share = if d then d.damage / r.maxHp else 0, damage = if d then math.floor(d.damage) else 0, ok = ok, reason = if ok then nil else (if aliveNow then "damage" else "alive")}
				if ok then
					table.insert(credited, player)
					for _, style in ipairs(XP_STYLES) do
						local dmg = d.xp[style]
						if dmg and dmg > 0 then L.reportXp(player, r, style, dmg) end
					end
				end
			end
			r.removedAdds = lairRemove(r)
			table.remove(r.removedAdds) -- the boss itself (its view goes with the kill)
			lairResults[r.fight] = {result = "win", credit = credit, seconds = now - r.started, party = 1}
			return credited
		end
		local storyKill = L.kill
		function L.kill(r)
			if r.story and r.lair and not r.lairAdd then return L.stKill(r) end
			return storyKill(r)
		end
		function L.stLit(fight)
			local r = lairFights[fight]
			return r and r.lit or nil
		end
	end
	-- End Story section.
	return L
end

-- §48 (QC M1): a boss's pending telegraphs {at = resolve server time, windup}.
-- The model shows the EARLIEST unresolved one, so a quick telegraph raised
-- while a long slam winds up never hides the slam; once a telegraph resolves
-- the next one is published. Returns the entry to show (nil when none).
local function earliestTelegraph(list, now)
	local best
	for i = #list, 1, -1 do
		local t = list[i]
		if t.at <= now then table.remove(list, i)
		elseif not best or t.at < best.at then best = t end
	end
	return best
end
local exports = {C = C, blueprint = blueprint, createLogic = createLogic, BODY_KIND = BODY_KIND, BOSS_BODY = BOSS_BODY, SEA_BODIES = SEA_BODIES,
	earliestTelegraph = earliestTelegraph}
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

local lineOfSight, teleportToHub -- defined with ground probing below
local onWorldBossLoot -- World Boss section: bridge "worldBoss" replies (defined below)
local Logic = createLogic({
	Data = Data, Progression = Progression,
	lineOfSight = function(from, r) return lineOfSight(from, r) end,
	teleport = function(player) return teleportToHub(player) end,
	-- server.server.lua sets AgilityMove "<anim>:<seq>" while a shortcut move runs.
	moving = function(player)
		local move = player:GetAttribute("AgilityMove")
		return type(move) == "string" and move ~= ""
	end,
	now = os.clock,
	wbLoot = function(...) if onWorldBossLoot then onWorldBossLoot(...) end end,
	time = os.time, -- wall clock of mastery capstone expiries (bridge "stats" mastery.active)
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
	bridge = function(op, player, payload, done)
		-- "stats", "consume" (ammo/glyph payment) and "refund" answer synchronously and never yield.
		if op == "stats" or op == "consume" or op == "refund" then return invokeBridge(op, player, payload) end
		-- Mutating ops may yield inside the Adventure script; never block the AI loop.
		task.spawn(function()
			local result = invokeBridge(op, player, payload)
			if op == "damage" and type(result) == "number" and player.Parent then
				fxRemote:FireClient(player, "hurt", {amount = result})
			end
			if done then done(result) end
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
-- Ranged/magic line of sight: from eye height to the monster's root. Monsters,
-- spawn markers and characters never block; any other geometry does.
lineOfSight = function(from, r)
	local origin = from + Vector3.new(0, C.EYE_HEIGHT, 0)
	local delta = r.position - origin
	if delta.Magnitude < 1 then return true end
	return Workspace:Raycast(origin, delta, rayParams) == nil
end
-- Hubward tablet destination: the Hub island's landing anchor, else its centre.
local LANDING_ANCHORS = {"Anchor_Landing", "Anchor_Spawn", "Anchor_Waypoint_Landing", "Anchor_Recall"}
local function hubDestination()
	local islands = Workspace:FindFirstChild("Islands")
	if not islands then return nil end
	for _, island in ipairs(islands:GetChildren()) do
		if island:GetAttribute("Region") == "Hub" then
			for _, name in ipairs(LANDING_ANCHORS) do
				local anchor = island:FindFirstChild(name, true)
				if anchor and anchor:IsA("BasePart") then return anchor.Position + Vector3.new(0, anchor.Size.Y / 2, 0) end
			end
			local center = island:GetAttribute("IslandCenter")
			if typeof(center) == "Vector3" then return Vector3.new(center.X, groundY(center, center.Y), center.Z) end
		end
	end
	return nil
end
teleportToHub = function(player)
	local character, humanoid, root = characterOf(player)
	if not character or not root or not humanoid or humanoid.Health <= 0 then return false end
	local destination = hubDestination()
	if not destination then return false end
	player:SetAttribute("FastTravelAt", os.clock()) -- known fast travel (Aether Mote pickup checks)
	character:PivotTo(CFrame.new(destination + Vector3.new(0, 3.5, 0)) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
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
	local big = opts.boss or opts.worldBoss
	gui.Size = UDim2.fromOffset(if opts.worldBoss then 300 elseif big then 220 else 150, if big then 44 else 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, plan.hitbox.Y / 2 + 1.4, 0)
	gui.MaxDistance = if opts.worldBoss then 260 elseif big then 160 else 90
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.58, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = if opts.worldBoss then Color3.fromRGB(255, 216, 107) elseif opts.boss then Color3.fromRGB(255, 120, 110) else Color3.fromRGB(255, 244, 217)
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
	-- §48 creature visuals: the rig and its uniform scale (creatures.client.lua).
	model:SetAttribute("CreatureRig", plan.kind)
	model:SetAttribute("CreatureScale", plan.scale)
	if opts.boss then
		model:SetAttribute("Boss", true)
		model:SetAttribute("OwnerUserId", opts.owner.UserId)
		model:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + C.BOSS_DURATION)
	elseif opts.sea then
		model:SetAttribute("SeaCreature", true)
		model:SetAttribute("OwnerUserId", opts.owner.UserId)
		model:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + Logic.seaDuration())
		label.TextColor3 = Color3.fromRGB(158, 231, 210)
	end
	CollectionService:AddTag(model, "IsleMonster")
	return model, root, {label = label, fill = fill, welds = welds}
end

-- Writes the root CFrame only when it changed. The idle bob runs only with a
-- player close enough to see it, so idle monsters further away replicate nothing.
local function place(r, near)
	local v = view[r]
	if not v then return end
	local t = os.clock() + v.phase
	local plan = v.plan
	local bob = 0
	if near ~= false then
		bob = if plan.flying then math.sin(t * 2) * 0.5 * plan.scale else math.sin(t * 3) * 0.08 * plan.scale
	end
	local lunge = 0
	if r.lungeUntil and os.clock() < r.lungeUntil then
		lunge = math.sin((r.lungeUntil - os.clock()) / 0.25 * math.pi) * 1.2 * plan.scale
	end
	local cf = CFrame.new(r.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, r.yaw, 0) * CFrame.new(0, 0, -lunge)
	if v.placed ~= cf then
		v.placed = cf
		v.root.CFrame = cf
	end
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
	-- §48 (QC L2): a despawn (leash, timeout, depart) fades out without the death slump.
	if not burst then v.model:SetAttribute("Despawn", true) end
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

local function spawnSea(player, spec)
	local def = spec.def
	local plan = blueprint(SEA_BODIES[def.body] and def.body or "blob", def.color, false)
	local angle = random:NextNumber(0, math.pi * 2)
	local spot = spec.at + Vector3.new(math.cos(angle) * C.SEA_OFFSET, 0, math.sin(angle) * C.SEA_OFFSET)
	local position = Vector3.new(spot.X, groundY(spot, spec.at.Y) + plan.hip, spot.Z)
	local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = spec.id, level = def.level, hp = def.hp, color = def.color, sea = true, owner = player})
	if not ok then
		warn("[Combat] could not build sea creature " .. spec.id .. ": " .. tostring(model))
		Logic.seaFailed(spec)
		return
	end
	local r = Logic.registerSea(player, spec, model, position, {radius = plan.radius})
	if not r then model:Destroy(); Logic.seaFailed(spec) return end
	local _, _, hrp = characterOf(player)
	if hrp then r.yaw = math.atan2(-(hrp.Position.X - position.X), -(hrp.Position.Z - position.Z)) end
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = random:NextNumber(0, 10)}
	place(r)
	model.Parent = folder
	broadcast(position, "death", {position = position, color = "9EE7D2", boss = false, scale = 1})
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

-- World Boss section (Endgame team) ------------------------------------------
-- Arena: World places Anchor_WorldBoss_<id> parts under Workspace.Islands (the
-- arena centre) and the Sovereign Altar prompt (IsleAction "bossSigil",
-- IsleItem "Aurelith"). The Adventure script validates and pays for a sigil,
-- then asks ServerStorage.IsleWorldBoss:Invoke("sigil", player, bossId) ->
-- {ok, reason, count, needed}; "status" -> {[id] = {active, sigils, needed, next}};
-- "drain" (shutdown) -> {{userId, boss, sigils, reason}} unspent sigils to refund.
-- Workspace attributes (read by world props and the client HUD):
--   WorldBossSigils_<id> "n/needed" · WorldBossActive_<id> bool · WorldBossNext_<id> os.time
-- IsleCombatFx kinds: worldBoss (HUD, 2 Hz, the nearest boss within Endgame.HUD_RANGE),
-- telegraph / bossStrike (warning discs and their impact), worldBossAnnounce
-- (server-wide: warn | spawn | phase | enrage | win | depart), worldBossLoot
-- (per contributor at the kill: rank, share, tier, drops or the reason for none).
-- §48: a boss's telegraph window on its model, so creatures.client.lua winds
-- the boss up over [TelegraphAt - TelegraphWindup, TelegraphAt) and slams when
-- the server resolves the strike (both stamped on server ticks: +-1 tick).
-- QC M1: overlapping telegraphs queue; the earliest unresolved one is shown.
local function publishTelegraph(r)
	local v = view[r]
	if not v then return end
	v.telegraphs = v.telegraphs or {}
	local show = earliestTelegraph(v.telegraphs, Workspace:GetServerTimeNow() + 0.05) -- (a resolving tick may read a hair early)
	if show and v.shownTelegraph ~= show then
		v.shownTelegraph = show
		v.model:SetAttribute("TelegraphWindup", show.windup)
		v.model:SetAttribute("TelegraphAt", show.at)
	end
end
local function markTelegraph(r, tg)
	local v = view[r]
	if not v or type(tg.windup) ~= "number" then return end
	v.telegraphs = v.telegraphs or {}
	table.insert(v.telegraphs, {at = Workspace:GetServerTimeNow() + tg.windup, windup = tg.windup})
	publishTelegraph(r)
end
local Endgame = Data.Endgame
local WB = {anchors = {}, hudClock = 0, scheduleClock = 0}
function WB.nameOf(player)
	return if typeof(player) == "Instance" then player.DisplayName else tostring(player)
end
function WB.anchor(id)
	local cached = WB.anchors[id]
	if cached and cached.Parent then return cached end
	local islands = Workspace:FindFirstChild("Islands")
	local found = islands and islands:FindFirstChild("Anchor_WorldBoss_" .. id, true)
	WB.anchors[id] = found
	return found
end
function WB.publish()
	for _, id in ipairs(Endgame.BossOrder) do
		local def = Data.WorldBosses[id]
		Workspace:SetAttribute("WorldBossActive_" .. id, Logic.wbActive(id) ~= nil)
		if def.summon == "altar" then Workspace:SetAttribute("WorldBossSigils_" .. id, Logic.altarCount(id) .. "/" .. def.sigils) end
	end
	local w = Endgame.scheduleAt(os.time())
	Workspace:SetAttribute("WorldBossNext_" .. w.boss, w.starts)
end
function WB.announce(kind, payload)
	payload.kind = kind
	for _, player in ipairs(Players:GetPlayers()) do fxRemote:FireClient(player, "worldBossAnnounce", payload) end
end
function WB.spawn(id, summoners)
	if Logic.wbActive(id) then return true end
	local spec = Logic.wbSpec(id)
	local anchor = WB.anchor(id)
	if not spec or not anchor then return false end
	local plan = blueprint(spec.kind, spec.color, "world")
	local spot = anchor.Position
	local position = Vector3.new(spot.X, groundY(spot, spot.Y) + plan.hip, spot.Z)
	local ok, model, root, parts = pcall(buildModel, spec.name, plan, {id = id, level = spec.level, hp = spec.hp, color = spec.color, worldBoss = true})
	if not ok then
		warn("[Combat] could not build world boss " .. id .. ": " .. tostring(model))
		return false
	end
	local r = Logic.wbRegister(spec, model, position, {radius = plan.radius, summoners = summoners, ground = position.Y - plan.hip})
	if not r then model:Destroy() return false end
	model:SetAttribute("WorldBoss", true)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("EnrageAt", Workspace:GetServerTimeNow() + spec.def.enrage)
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = 0}
	place(r)
	model.Parent = folder
	WB.announce("spawn", {id = id, name = spec.name})
	WB.publish()
	return true
end
function WB.spawnAdds(event)
	local boss = event.record
	local def = Data.Monsters[event.monster]
	if not def then return end
	for i = 1, event.count do
		local plan = blueprint(BODY_KIND[event.monster] or "blob", def.color, false)
		local a = (i - 1) * 2 * math.pi / event.count + random:NextNumber(0, 0.6)
		local spot = boss.home + Vector3.new(math.cos(a) * event.attack.radius, 0, math.sin(a) * event.attack.radius)
		local position = Vector3.new(spot.X, groundY(spot, boss.home.Y) + plan.hip, spot.Z)
		local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = event.monster, level = def.level, hp = def.hp, color = def.color})
		if ok then
			local r = Logic.wbRegisterAdd(boss, event.monster, model, position, {radius = plan.radius})
			if r then
				view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = random:NextNumber(0, 10)}
				place(r)
				model.Parent = folder
				broadcast(position, "death", {position = position, color = def.color, boss = false, scale = 1})
			else
				model:Destroy()
			end
		end
	end
end
-- Kill or departure: adds go, contributors without credit learn why.
function WB.finish(r, result)
	for _, add in ipairs(r.removedAdds or {}) do destroyView(add, true) end
	r.removedAdds = nil
	if result == "win" then
		WB.announce("win", {id = r.id, name = r.name})
		for _, e in ipairs(r.results or {}) do
			if not e.eligible and e.player.Parent then
				fxRemote:FireClient(e.player, "worldBossLoot", {id = r.id, name = r.name, eligible = false, reason = e.reason, rank = e.rank, share = e.share})
			end
		end
	end
	WB.publish()
end
onWorldBossLoot = function(player, r, entry, reply)
	if not player.Parent then return end
	local paid = type(reply) == "table" and reply.ok == true
	-- Refusals: "region" (journal may not enter the Shattered Crown), "paid"
	-- (an earlier report was applied), otherwise the journal stayed unsynced.
	local reason = if paid then nil elseif type(reply) == "table" and (reply.reason == "region" or reply.reason == "paid") then reply.reason else "sync"
	fxRemote:FireClient(player, "worldBossLoot", {id = r.id, name = r.name, eligible = paid, reason = reason,
		rank = entry.rank, share = entry.share, tier = entry.tier, drops = paid and reply.drops or nil, coins = paid and reply.coins or nil})
end
-- Each player sees only the nearest live boss in HUD range (no flicker when
-- both bosses are up).
function WB.hud()
	if #Logic.wbList() == 0 then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, hrp = characterOf(player)
		local r = hrp and Logic.wbHudFor(hrp.Position)
		if r then fxRemote:FireClient(player, "worldBoss", Logic.wbHud(r, player, WB.nameOf)) end
	end
end
-- Summons a full altar's boss; a build that keeps failing resets and refunds the altar.
function WB.summon(due)
	if WB.spawn(due.id, due.summoners) then return true end
	if Logic.wbSummonFailed(due.id) then WB.publish() end
	return false
end
function WB.step(dt)
	for _, event in ipairs(Logic.wbTick()) do
		local r = event.record
		if event.kind == "telegraph" then
			local tg = event.telegraph
			-- The disc lies on the floor under its centre (the record's arena floor as fallback).
			local c = tg.center
			local center = Vector3.new(c.X, groundY(c, c.Y), c.Z)
			broadcast(r.home, "telegraph", {center = center, radius = tg.radius, kind = tg.kind, windup = tg.windup, name = tg.name, boss = r.id})
			markTelegraph(r, tg)
		elseif event.kind == "strike" then
			local tg = event.telegraph
			publishTelegraph(r)
			broadcast(r.home, "bossStrike", {center = tg.center, radius = tg.radius, kind = tg.kind, hits = #event.hits})
		elseif event.kind == "phase" then
			if view[r] then view[r].model:SetAttribute("Phase", event.phase) end
			WB.announce("phase", {id = r.id, name = r.name, phase = event.phase, phaseName = r.def.phases[event.phase].name})
		elseif event.kind == "enrage" then
			WB.announce("enrage", {id = r.id, name = r.name})
		elseif event.kind == "adds" then
			WB.spawnAdds(event)
		elseif event.kind == "depart" then
			for _, add in ipairs(event.adds or {}) do destroyView(add, false) end
			destroyView(r, false)
			WB.announce("depart", {id = r.id, name = r.name, reason = event.reason})
			WB.publish()
		end
	end
	WB.hudClock += dt
	if WB.hudClock >= 0.5 then
		WB.hudClock = 0
		WB.hud()
	end
	WB.scheduleClock += dt
	if WB.scheduleClock >= 1 then
		WB.scheduleClock = 0
		for _, event in ipairs(Logic.wbScheduleTick(os.time())) do
			local def = Data.WorldBosses[event.id]
			if event.kind == "warn" then
				WB.announce("warn", {id = event.id, name = def.name, starts = event.starts})
			elseif not WB.spawn(event.id, {}) then
				Logic.wbScheduleRetry(event.key)
			end
		end
		for _, due in ipairs(Logic.wbDueSummons()) do WB.summon(due) end
		Logic.wbRetryTick() -- unapplied world boss rewards (journal syncing at the kill)
		WB.publish()
	end
end
do
	local existing = ServerStorage:FindFirstChild("IsleWorldBoss")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleWorldBoss"
	-- Synchronous and non-yielding: the Adventure script spends the sigil only after ok.
	fn.OnInvoke = function(op, player, bossId)
		if op == "sigil" then
			if typeof(player) ~= "Instance" or not player:IsA("Player") then return {ok = false, reason = "player"} end
			local ok, reason, count, needed = Logic.placeSigil(player, bossId)
			if ok then
				Workspace:SetAttribute("WorldBossSigils_" .. bossId, count .. "/" .. needed)
				if reason == "ready" then task.defer(function()
					for _, due in ipairs(Logic.wbDueSummons()) do if due.id == bossId then WB.summon(due) end end
				end) end
			end
			return {ok = ok, reason = reason, count = count, needed = needed}
		elseif op == "status" then
			local out = {}
			for _, id in ipairs(Endgame.BossOrder) do
				local def = Data.WorldBosses[id]
				out[id] = {active = Logic.wbActive(id) ~= nil, sigils = Logic.altarCount(id), needed = def.sigils,
					next = if def.summon == "schedule" then Endgame.scheduleAt(os.time()).starts else nil}
			end
			return out
		elseif op == "drain" then
			-- Shutdown (the Adventure script's BindToClose): every unspent sigil as
			-- {userId, boss, sigils, reason}; the altars are emptied.
			local out = {}
			for _, entry in ipairs(Logic.wbDrain()) do
				table.insert(out, {userId = entry.userId, boss = entry.boss, sigils = entry.sigils, reason = entry.reason})
			end
			return out
		end
		return nil
	end
	fn.Parent = ServerStorage
	WB.publish()
end
-- End World Boss section.

-- Lairs section (Bossing team, runtime) -----------------------------------------
-- lairs.server.lua builds each arena and asks ServerStorage.IsleLairCombat
-- (BindableFunction, synchronous, never yields):
--   "spawn"   {fight, boss, center (arena floor centre), members = {userId...},
--              seed, tiles = {[cell] = BasePart}?}  -> {ok, reason}
--   "status"  {fight} -> Logic.lrStatus (alive, hp, phase, stance, alert, result...)
--   "despawn" {fight} -> removes the boss and its adds (no reward), restores tiles.
-- Telegraphs reuse the world-boss FX (telegraph / bossStrike); a tile lattice
-- lights its charged tile parts (Neon) for the windup instead.
DENY_REASONS.order, DENY_REASONS.lair, DENY_REASONS.sealed = true, true, true
DENY_REASONS.shrouded, DENY_REASONS.outside = true, true -- §53 Story: Gloamwick outside the lantern light; members outside the arena (QC M2)
local LairRT = {tiles = {}, lit = {}}
local STANCE_COLOR = {melee = Color3.fromRGB(255, 120, 110), ranged = Color3.fromRGB(150, 225, 120), magic = Color3.fromRGB(140, 170, 255)}
local ROMAN_ORDER = {"I", "II", "III", "IV"}
function LairRT.paintStance(r)
	local v = view[r]
	if not v then return end
	v.label.TextColor3 = STANCE_COLOR[r.attackStyle] or v.label.TextColor3
	v.model:SetAttribute("LairStance", r.attackStyle)
	v.model:SetAttribute("Phase", r.phase)
end
function LairRT.spawn(payload)
	local Lairs = Data.Lairs
	local def = Lairs and Lairs.boss(payload.boss)
	local center = payload.center
	if not def or type(payload.fight) ~= "string" or typeof(center) ~= "Vector3" then return {ok = false, reason = "invalid"} end
	if Logic.lrRecord(payload.fight) then return {ok = false, reason = "active"} end
	local plan = blueprint(def.body, def.color, true)
	local position = Vector3.new(center.X, center.Y + plan.hip, center.Z + Lairs.CELL)
	local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = def.id, level = def.level, hp = Lairs.partyHp(def, tonumber(payload.party) or #(payload.members or {})), color = def.color})
	if not ok then
		warn("[Combat] could not build lair boss " .. def.id .. ": " .. tostring(model))
		return {ok = false, reason = "build"}
	end
	local r = Logic.lrRegister(payload.fight, def.id, model, position, {radius = plan.radius, members = payload.members, party = payload.party, seed = payload.seed, center = center, ground = center.Y})
	if not r then model:Destroy() return {ok = false, reason = "register"} end
	model:SetAttribute("Lair", payload.fight)
	model:SetAttribute("MaxHealth", r.maxHp)
	model:SetAttribute("Health", r.hp)
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = 0}
	LairRT.tiles[payload.fight] = type(payload.tiles) == "table" and payload.tiles or nil
	LairRT.paintStance(r)
	place(r)
	model.Parent = folder
	broadcast(position, "death", {position = position, color = def.color, boss = true, scale = plan.scale})
	return {ok = true, hp = r.maxHp}
end
function LairRT.restoreTiles(fight)
	local lit = LairRT.lit[fight]
	LairRT.lit[fight] = nil
	for part, look in pairs(lit or {}) do
		if part.Parent then part.Color, part.Material = look.color, look.material end
	end
end
function LairRT.lightTiles(r, tg)
	local tiles = LairRT.tiles[r.fight]
	if not tiles then return end
	LairRT.restoreTiles(r.fight)
	local lit = {}
	for _, cell in ipairs(tg.cells) do
		local part = tiles[cell]
		if typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent then
			lit[part] = {color = part.Color, material = part.Material}
			part.Color, part.Material = Color3.fromRGB(120, 200, 255), Enum.Material.Neon
		end
	end
	LairRT.lit[r.fight] = lit
end
function LairRT.spawnAdds(event)
	local boss = event.record
	local Lairs = Data.Lairs
	local def = Lairs.Adds[event.add]
	if not def then return end
	for i = 1, event.count do
		local plan = blueprint(def.body, def.color, false)
		local a = (i - 1) * 2 * math.pi / event.count + (if event.ordered then 0 else random:NextNumber(0, 0.6))
		local spot = boss.center + Vector3.new(math.cos(a) * event.attack.radius, 0, math.sin(a) * event.attack.radius)
		local position = Vector3.new(spot.X, boss.center.Y + plan.hip, spot.Z)
		local name = if event.ordered then def.name .. " " .. (ROMAN_ORDER[i] or tostring(i)) else def.name
		local ok, model, root, parts = pcall(buildModel, name, plan, {id = event.add, level = def.level, hp = def.hp, color = def.color})
		if ok then
			local r = Logic.lrRegisterAdd(boss, event.add, model, position, {radius = plan.radius, order = if event.ordered then i else nil})
			if r then
				if r.order then model:SetAttribute("LairOrder", r.order) end
				view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = random:NextNumber(0, 10)}
				place(r)
				model.Parent = folder
				broadcast(position, "death", {position = position, color = def.color, boss = false, scale = 1})
			else
				model:Destroy()
			end
		end
	end
end
-- The boss died (player attack path): its adds go, tiles return to rest.
function LairRT.finish(r)
	for _, add in ipairs(r.removedAdds or {}) do destroyView(add, true) end
	r.removedAdds = nil
	LairRT.restoreTiles(r.fight)
	if r.fight then LairRT.tiles[r.fight] = nil end -- Raids QC M1: the fight is over; its tile map goes too
end
-- §53 Story: lantern parts per fight ({[i] = BasePart}); the lit one glows (Neon).
local StoryRT = {lanterns = {}}
function StoryRT.lantern(event)
	local r = event.record
	local parts = r and StoryRT.lanterns[r.fight]
	local v = view[r]
	if v then v.model:SetAttribute("StoryLit", event.lit) end
	if not parts then return end
	for i, part in pairs(parts) do
		if typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent then
			local lit = i == event.lit
			part.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
			part.Color = if lit then Color3.fromRGB(255, 214, 120) else Color3.fromRGB(70, 60, 95)
			part:SetAttribute("Lit", lit)
		end
	end
end
function LairRT.step()
	for _, event in ipairs(Logic.lrTick()) do
		local r = event.record
		if event.kind == "telegraph" then
			local tg = event.telegraph
			markTelegraph(r, tg)
			if tg.kind == "tiles" then
				LairRT.lightTiles(r, tg)
			else
				broadcast(r.center, "telegraph", {center = tg.center, radius = tg.radius, kind = tg.kind, windup = tg.windup, name = tg.name, boss = r.id,
					ux = tg.ux, uz = tg.uz, width = tg.width, length = tg.length}) -- §53: cross / beam / half carry a direction
			end
		elseif event.kind == "strike" then
			local tg = event.telegraph
			publishTelegraph(r)
			if tg.kind == "tiles" then
				LairRT.restoreTiles(r.fight)
				broadcast(r.center, "bossStrike", {center = r.center, radius = Data.Lairs.CELL, kind = "ring", hits = #event.hits})
			else
				broadcast(r.center, "bossStrike", {center = tg.center, radius = tg.radius, kind = tg.kind, hits = #event.hits})
			end
		elseif event.kind == "phase" or event.kind == "stance" or event.kind == "enrage" then
			LairRT.paintStance(r)
		elseif event.kind == "lantern" then
			StoryRT.lantern(event) -- §53 Story: the lit lantern moved
		elseif event.kind == "adds" then
			LairRT.spawnAdds(event)
		elseif event.kind == "timeout" then
			for _, removed in ipairs(event.removed or {}) do destroyView(removed, false) end
			LairRT.restoreTiles(r.fight)
			LairRT.tiles[r.fight] = nil
		end
	end
end
do
	local existing = ServerStorage:FindFirstChild("IsleLairCombat")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleLairCombat"
	fn.OnInvoke = function(op, payload)
		if type(payload) ~= "table" then return nil end
		if op == "spawn" then
			return LairRT.spawn(payload)
		elseif op == "status" then
			return Logic.lrStatus(payload.fight)
		elseif op == "despawn" then
			for _, r in ipairs(Logic.lrDespawn(payload.fight)) do destroyView(r, false) end
			LairRT.restoreTiles(payload.fight)
			LairRT.tiles[payload.fight] = nil
			return {ok = true}
		end
		return nil
	end
	fn.Parent = ServerStorage
end
-- End Lairs section (runtime).

-- Raids section (Raid team, runtime) ----------------------------------------
-- raids.server.lua builds each vault room and asks ServerStorage.IsleRaidCombat
-- (BindableFunction, synchronous, never yields):
--   "spawn"   {fight, encounter, center, members = {userId...}, party, seed,
--              challenge, tiles = {[cell] = BasePart}?} -> {ok, hp, reason}
--   "status"  {fight} -> Logic.lrStatus + dmg = Logic.rdDamage (per-UserId damage, last hit)
--   "despawn" {fight} -> removes the encounter and its adds (no reward), restores tiles.
-- Stances, telegraphs, tiles and adds run through LairRT.step (raid records
-- live in the Lairs fight table); LR.Adds resolves the raid adds.
do
	local existing = ServerStorage:FindFirstChild("IsleRaidCombat")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleRaidCombat"
	local function spawnRaid(payload)
		local RD = Data.Raids
		local def = RD and RD.encounter(payload.encounter)
		local center = payload.center
		if not def or type(payload.fight) ~= "string" or typeof(center) ~= "Vector3" then return {ok = false, reason = "invalid"} end
		if Logic.lrRecord(payload.fight) then return {ok = false, reason = "active"} end
		local plan = blueprint(def.body, def.color, true)
		local position = Vector3.new(center.X, center.Y + plan.hip, center.Z + RD.CELL)
		local party = tonumber(payload.party) or #(payload.members or {})
		local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = def.id, level = def.level, hp = RD.partyHp(def, party, payload.challenge == true), color = def.color})
		if not ok then
			warn("[Combat] could not build raid encounter " .. def.id .. ": " .. tostring(model))
			return {ok = false, reason = "build"}
		end
		local r = Logic.rdRegister(payload.fight, def.id, model, position, {radius = plan.radius, members = payload.members, party = payload.party,
			seed = payload.seed, center = center, ground = center.Y, challenge = payload.challenge == true})
		if not r then model:Destroy() return {ok = false, reason = "register"} end
		model:SetAttribute("Lair", payload.fight)
		model:SetAttribute("Raid", payload.fight)
		model:SetAttribute("MaxHealth", r.maxHp)
		model:SetAttribute("Health", r.hp)
		view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = 0}
		LairRT.tiles[payload.fight] = type(payload.tiles) == "table" and payload.tiles or nil
		LairRT.paintStance(r)
		place(r)
		model.Parent = folder
		broadcast(position, "death", {position = position, color = def.color, boss = true, scale = plan.scale})
		return {ok = true, hp = r.maxHp}
	end
	fn.OnInvoke = function(op, payload)
		if type(payload) ~= "table" then return nil end
		if op == "spawn" then
			return spawnRaid(payload)
		elseif op == "status" then
			local status = Logic.lrStatus(payload.fight)
			if type(status) == "table" then status.dmg = Logic.rdDamage(payload.fight) end
			return status
		elseif op == "despawn" then
			for _, r in ipairs(Logic.lrDespawn(payload.fight)) do destroyView(r, false) end
			LairRT.restoreTiles(payload.fight)
			LairRT.tiles[payload.fight] = nil
			return {ok = true}
		end
		return nil
	end
	fn.Parent = ServerStorage
end
-- End Raids section (runtime).

-- Story section (Story team, runtime; §53) -----------------------------------
-- server.server.lua's Story block asks ServerStorage.IsleStoryCombat
-- (BindableFunction, synchronous, never yields):
--   "spawn"   {fight, boss, center, members = {userId}, seed, lanterns = {[i] = BasePart}?} -> {ok, hp, reason}
--   "status"  {fight} -> Logic.lrStatus (+ lit = the lit lantern)
--   "despawn" {fight} -> removes the boss and its adds (no reward).
-- Telegraphs, adds and lanterns run through LairRT.step.
do
	local existing = ServerStorage:FindFirstChild("IsleStoryCombat")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleStoryCombat"
	local function spawnStory(payload)
		local ST = Data.Story
		local def = ST and ST.boss(payload.boss)
		local center = payload.center
		if not def or type(payload.fight) ~= "string" or typeof(center) ~= "Vector3" then return {ok = false, reason = "invalid"} end
		if Logic.lrRecord(payload.fight) then return {ok = false, reason = "active"} end
		local plan = blueprint(def.body, def.color, true)
		local position = Vector3.new(center.X, center.Y + plan.hip, center.Z + 11)
		local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = def.id, level = def.level, hp = def.hp, color = def.color})
		if not ok then
			warn("[Combat] could not build story encounter " .. def.id .. ": " .. tostring(model))
			return {ok = false, reason = "build"}
		end
		local r = Logic.stRegister(payload.fight, def.id, model, position, {radius = plan.radius, members = payload.members, seed = payload.seed, center = center, ground = center.Y})
		if not r then model:Destroy() return {ok = false, reason = "register"} end
		model:SetAttribute("Lair", payload.fight)
		model:SetAttribute("Story", payload.fight)
		model:SetAttribute("MaxHealth", r.maxHp)
		model:SetAttribute("Health", r.hp)
		view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = 0}
		StoryRT.lanterns[payload.fight] = type(payload.lanterns) == "table" and payload.lanterns or nil
		LairRT.paintStance(r)
		place(r)
		model.Parent = folder
		broadcast(position, "death", {position = position, color = def.color, boss = true, scale = plan.scale})
		return {ok = true, hp = r.maxHp}
	end
	fn.OnInvoke = function(op, payload)
		if type(payload) ~= "table" then return nil end
		if op == "spawn" then
			return spawnStory(payload)
		elseif op == "status" then
			local status = Logic.lrStatus(payload.fight)
			if type(status) == "table" then status.lit = Logic.stLit(payload.fight) end
			return status
		elseif op == "despawn" then
			for _, r in ipairs(Logic.lrDespawn(payload.fight)) do destroyView(r, false) end
			StoryRT.lanterns[payload.fight] = nil
			return {ok = true}
		end
		return nil
	end
	fn.Parent = ServerStorage
end
-- End Story section (runtime).

-- Skysailing (§51) deck cannons: server.server.lua's sailFire calls
-- ServerStorage.IsleCannon:Invoke("fire", gunner, {origin, dir, range, cone,
-- damage}) -> {hit, name, damage, killed}. Synchronous, never yields; the hit
-- is the gunner's (L.landHit), so corsair credit and XP flow as usual.
do
	local existing = ServerStorage:FindFirstChild("IsleCannon")
	local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
	fn.Name = "IsleCannon"
	fn.OnInvoke = function(op, player, payload)
		if op ~= "fire" or typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
		local result = Logic.cannon(player, payload)
		if not result or not result.hit then return {hit = false} end
		local r = result.record
		local top = r.position + Vector3.new(0, (view[r] and view[r].plan.hitbox.Y or 3) / 2, 0)
		broadcast(r.position, "projectile", {from = payload.origin, to = top, style = "ranged", color = "FFB347", attacker = player.UserId})
		updateBar(r)
		broadcast(r.position, "hit", {model = r.model, position = top, amount = result.damage, attacker = player.UserId, style = "ranged"})
		if result.killed then destroyView(r, true) end
		return {hit = true, name = r.name, damage = result.damage, killed = result.killed == true}
	end
	fn.Parent = ServerStorage
end

-- Player attacks -------------------------------------------------------------
local denyAt = {} -- [player] = os.clock() before which no further "denied" notice is sent
local function deny(player, verb, reason)
	if not DENY_REASONS[reason] or not player.Parent then return end
	local now = os.clock()
	if (denyAt[player] or 0) > now then return end
	denyAt[player] = now + C.DENY_INTERVAL
	fxRemote:FireClient(player, "denied", {action = verb, reason = reason})
end
combatRemote.OnServerEvent:Connect(function(player, verb, target, spellId)
	local result, reason
	if verb == "attack" or verb == "ranged" then
		if typeof(target) ~= "Instance" then return end
		if verb == "attack" then
			result, reason = Logic.attack(player, verb, target)
		else
			result, reason = Logic.ranged(player, verb, target)
		end
	elseif verb == "cast" then
		if target ~= nil and typeof(target) ~= "Instance" then return end
		if spellId ~= nil and (type(spellId) ~= "string" or #spellId > 40) then return end
		result, reason = Logic.cast(player, verb, target, spellId)
	else
		return
	end
	if not result then deny(player, verb, reason) return end
	local r = result.record
	if result.ammoLeft ~= nil then player:SetAttribute("QuiverCount", result.ammoLeft) end
	if result.mana ~= nil then player:SetAttribute("Mana", result.mana) end
	local top = r and r.position + Vector3.new(0, (view[r] and view[r].plan.hitbox.Y or 3) / 2, 0)
	if result.from and top then
		broadcast(r.position, "projectile", {from = result.from + Vector3.new(0, C.EYE_HEIGHT, 0), to = top, style = result.style,
			spell = result.spell, color = result.color, attacker = player.UserId})
	end
	if r and result.damage ~= nil then
		updateBar(r)
		broadcast(r.position, "hit", {model = r.model, position = top, amount = result.damage, crit = result.crit,
			attacker = player.UserId, style = result.style, miss = result.miss == true, tag = result.tag, spell = result.spell})
		if result.killed then destroyView(r, true) end
		if result.killed and r.worldBoss then WB.finish(r, "win") end
		if result.killed and r.lair then LairRT.finish(r) end -- Lairs section: adds and tiles go with the boss
	elseif result.kind == "snare" and r then
		broadcast(r.position, "snare", {model = r.model, position = top, duration = result.duration, attacker = player.UserId})
	elseif result.kind == "heal" or result.kind == "teleport" then
		fxRemote:FireClient(player, result.kind, {spell = result.spell})
	end
	-- Skill Mastery multishot: one arrow FX and hit per extra target.
	for _, hit in ipairs(result.extra or {}) do
		local other = hit.record
		local otherTop = other.position + Vector3.new(0, (view[other] and view[other].plan.hitbox.Y or 3) / 2, 0)
		broadcast(other.position, "projectile", {from = hit.from + Vector3.new(0, C.EYE_HEIGHT, 0), to = otherTop, style = hit.style,
			color = hit.color, attacker = player.UserId})
		updateBar(other)
		broadcast(other.position, "hit", {model = other.model, position = otherTop, amount = hit.damage, crit = hit.crit,
			attacker = player.UserId, style = hit.style, miss = hit.miss == true, tag = hit.tag})
		if hit.killed then destroyView(other, true) end
		if hit.killed and other.worldBoss then WB.finish(other, "win") end
		if hit.killed and other.lair then LairRT.finish(other) end
	end
end)

-- Slayer bosses --------------------------------------------------------------
local playerConnections = {} -- [player] = {connection...}
local function onBossAttribute(player)
	local action, payload = Logic.bossAttribute(player, player:GetAttribute("SlayerBossReady"))
	if action == "cancel" and payload then destroyView(payload, false) end
end
local function onSeaAttribute(player)
	local action, spec = Logic.seaAttribute(player, player:GetAttribute("SeaCreatureSpawn"), player:GetAttribute("SeaCreatureAt"))
	if action == "spawn" then spawnSea(player, spec) end
end
local function onPlayerAdded(player)
	playerConnections[player] = {
		player:GetAttributeChangedSignal("SlayerBossReady"):Connect(function() onBossAttribute(player) end),
		player:GetAttributeChangedSignal("SeaCreatureSpawn"):Connect(function() onSeaAttribute(player) end),
		-- Slayer tasks section: a new task family or a (un)equipped visor drops the cached stats.
		player:GetAttributeChangedSignal("SlayerTask"):Connect(function() Logic.invalidateStats(player) end),
		player:GetAttributeChangedSignal("SlayerVisor"):Connect(function() Logic.invalidateStats(player) end),
		player.CharacterAdded:Connect(function() task.defer(refreshRayFilter) end),
	}
	onBossAttribute(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, player) end
Players.PlayerRemoving:Connect(function(player)
	for _, connection in ipairs(playerConnections[player] or {}) do connection:Disconnect() end
	playerConnections[player] = nil
	denyAt[player] = nil
	for _, r in ipairs(Logic.playerRemoving(player)) do destroyView(r, false) end
	task.defer(refreshRayFilter)
end)

-- Slayer tasks section (Slayer team): superior spawns. A queued superior
-- (Logic.pendingSuperiors) is built with its base monster's body at boss scale
-- (crown and aura), owned by the task holder (OwnerUserId, Superior = true).
local function spawnSuperior(spec)
	local player = spec.player
	if not player or not player.Parent or not playerConnections[player] then return end
	local def = spec.def
	local plan = blueprint(BODY_KIND[def.base] or "blob", def.color, true)
	local position = Vector3.new(spec.at.X, groundY(spec.at, spec.at.Y - plan.hip) + plan.hip, spec.at.Z)
	local ok, model, root, parts = pcall(buildModel, def.name, plan, {id = spec.id, level = def.level, hp = def.hp, color = def.color, boss = true, owner = player})
	if not ok then
		warn("[Combat] could not build superior " .. spec.id .. ": " .. tostring(model))
		Logic.superiorFailed(spec)
		return
	end
	local r = Logic.registerSuperior(spec, model, position, {radius = plan.radius})
	if not r then model:Destroy() return end
	model:SetAttribute("Superior", true)
	model:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + Logic.superiorLifetime())
	view[r] = {model = model, root = root, plan = plan, fill = parts.fill, label = parts.label, welds = parts.welds, phase = random:NextNumber(0, 10)}
	place(r)
	model.Parent = folder
	broadcast(position, "bossSpawn", {position = position, name = def.name, owner = player.UserId, color = def.color})
end
local function slayerStep()
	for _, spec in ipairs(Logic.pendingSuperiors()) do spawnSuperior(spec) end
	for _, r in ipairs(Logic.superiorTick()) do destroyView(r, false) end
	for _, job in ipairs(Logic.dueSuperiorRetries()) do
		if job.player.Parent then Logic.reportSuperior(job.player, job.id, job.seq, "kill", job.deadline) end
	end
end
-- End Slayer tasks section (runtime).

-- One loop for all AI --------------------------------------------------------
local AI_STEP = 1 / 15
local accumulator, housekeeping, animClock = 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < AI_STEP then return end
	local step = math.min(accumulator, 0.25)
	accumulator = 0
	housekeeping += step
	if housekeeping >= 0.5 then
		housekeeping = 0
		for _, marker in ipairs(Logic.dueSpawns()) do spawnMarkerMonster(marker) end
		for _, player in ipairs(Logic.dueRearms()) do
			if player.Parent and playerConnections[player] then onBossAttribute(player) end
		end
		for _, pending in ipairs(Logic.pendingBosses()) do spawnBoss(pending.player, pending.spec) end
		slayerStep() -- Slayer tasks section: superior spawns and withdrawals
		for _, job in ipairs(Logic.dueSeaRetries()) do
			if job.player.Parent then Logic.reportSea(job.player, job.id, job.seq, "kill", job.deadline) end
		end
		-- Mana regeneration, replicated as player attributes.
		for _, update in ipairs(Logic.manaTick()) do
			if update.player.Parent then
				update.player:SetAttribute("MaxMana", update.max)
				update.player:SetAttribute("Mana", update.mana)
			end
		end
	end
	for _, r in ipairs(Logic.seaTick()) do destroyView(r, false) end
	for _, failed in ipairs(Logic.bossTick()) do
		if failed.player.Parent then fxRemote:FireClient(failed.player, "bossFail", {reason = failed.reason}) end
		destroyView(failed.record, false)
	end
	animClock += step
	local animTick = animClock >= C.ANIMATE_STEP
	if animTick then animClock = 0 end
	Logic.beginTick()
	WB.step(step) -- World Boss section: telegraphs, phases, schedule, HUD (inside the tick snapshot)
	LairRT.step() -- Lairs section: stances, telegraphs, tiles, adds, enrage (inside the tick snapshot)
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
				-- §48: a landed monster hit (the lunge) tells clients when to play the bite.
				if r.lungeUntil ~= v.lunge then
					v.lunge = r.lungeUntil
					v.model:SetAttribute("AttackAt", Workspace:GetServerTimeNow())
				end
				local near = Logic.nearestPlayerDistance(r) <= C.ANIMATE_RANGE
				place(r, near)
				if near and animTick then animate(r, moved) end
			end
		end
	end
	Logic.endTick()
end)

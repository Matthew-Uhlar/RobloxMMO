-- §47 Animation depth (animate.client.lua + gesture.server.lua): every
-- interaction verb the servers build maps to its own animation; keyframes stay
-- inside human joint ranges with anticipation / follow-through / recovery;
-- gathering swings match the server's strike cadence (Data.Strike SWING /
-- IMPACT) frame for frame; weapon combos chain; stances follow node size; the
-- rod bends; the body layer (landing, sprint lean, flinch), idle fidgets and
-- death; the reduced-motion path; and the replication budget (relay names,
-- rate, caps, observed / derived gestures never relayed, no per-frame tables).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local Core
load("animate.client.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3,
	__GestureTestHarness = function(exports) Core = exports end})
assert(Core, "client harness hook")
local Relay
load("gesture.server.lua", {Vector3 = Vector3, __GestureRelayHarness = function(exports) Relay = exports end})
assert(Relay, "server harness hook")

local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(a, b, case) assert(a == b, case .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local function near(a, b, case, eps) assert(math.abs(a - b) < (eps or 1e-6), case .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local G = Core.GESTURES
local client = fs.readFile("animate.client.lua")
local server = fs.readFile("gesture.server.lua")

------------------------------------------------------------------------------
-- 1. Every interaction verb maps to an animation
------------------------------------------------------------------------------
-- IsleAction verbs: scanned from every script that builds prompts (attribute
-- sets, prompt() calls, hall / stall definitions and the contract comments).
local verbs = {}
local SOURCES = {"world.server.lua", "server.server.lua", "raids.server.lua", "lairs.server.lua", "festival.server.lua", "beaconry.server.lua",
	"combat.server.lua", "minigames.server.lua", "expedition.server.lua", "coop.server.lua", "motes.client.lua"}
for _, path in ipairs(SOURCES) do
	local text = fs.readFile(path)
	for line in text:gmatch("[^\n]+") do
		if line:find('SetAttribute%("IsleAction"') or line:find("IsleAction \"") or line:find('prompt IsleAction') then
			local _, at = line:find("IsleAction")
			for word in line:sub(at + 1):gmatch('"([a-z][A-Za-z]+)"') do verbs[word] = true end
		end
	end
	-- world.server.lua prompt(part, verb, label, action, ...) with a literal action
	if path == "world.server.lua" then
		for action in text:gmatch('prompt%([^,\n]+,[^,\n]+,[^\n]-,%s*"([a-z][A-Za-z]+)"') do verbs[action] = true end
	end
	if path == "world.server.lua" then for action in text:gmatch('action="([a-z][A-Za-z]+)"') do verbs[action] = true end end
end
-- Ternaries the patterns above cannot see.
for _, v in ipairs({"worker", "workerBuild", "workerClaim", "trap", "net", "station", "craftStation", "craft", "raidAct", "raidLeave"}) do verbs[v] = true end
-- Not prompt verbs: strike is §42's remote verb (struck nodes, no prompt).
verbs.strike = nil
verbs.leave = nil -- raids.server.lua compares its target to "leave" on the IsleAction line
local count = 0
for _ in pairs(verbs) do count += 1 end
ok(count >= 35, "the scan found the prompt verbs (" .. count .. ")")
for _, known in ipairs({"bank", "sell", "claim", "altarPray", "altarOffer", "gardenPlot", "gardenOpen", "moteCollect", "beaconLight", "lairEnter",
	"raidPortal", "landmark", "thieve", "lecternVisit", "councilView", "factionBoard", "moteShrine", "bossSigil", "eventVendor", "logsBoard"}) do
	ok(verbs[known], "scan sees " .. known)
end
local itemFor = {station = "Forge", craftStation = "Jeweller", craft = "Blade", gardenOpen = "ledger"}
for verb in pairs(verbs) do
	local name, source = Core.selectGesture({action = verb, item = itemFor[verb]}, Data, 0)
	if Core.SILENT_ACTION[verb] then
		eq(name, nil, verb .. " waits for its attribute-driven move")
	else
		ok(name ~= nil and G[name] ~= nil, verb .. " maps to a gesture (" .. tostring(name) .. ")")
		eq(source, "action", verb .. " has its own mapping, not the generic fallback")
	end
end
-- The generic reach is a deliberate choice only where it fits (a lever, a pyre's hold).
for verb, name in pairs(Core.ACTION_GESTURE) do
	if name == "interact" then ok(verb == "beaconLight" or verb == "raidAct", verb .. " reach-and-press is deliberate") end
end
-- Stations: every station kind (world + crafting) animates with its own work.
for kind, list in pairs(Core.STATION_GESTURE) do
	for i, name in ipairs(list) do ok(G[name] ~= nil, kind .. " station gesture " .. i .. " " .. name) end
end
eq(Core.STATION_GESTURE.Forge[1], "hammer", "anvil hammering")
ok(table.find(Core.STATION_GESTURE.Cauldron, "pour") and table.find(Core.STATION_GESTURE.Cauldron, "stir"), "alchemy pours and stirs")
ok(table.find(Core.STATION_GESTURE.Hearth, "stir") and table.find(Core.STATION_GESTURE.Hearth, "flip"), "cooking stirs and flips")
ok(table.find(Data.Crafting.Stations.Tannery.gesture, "weave"), "the loom weaves")
ok(table.find(Data.Crafting.Stations.Glassworks.gesture, "blow"), "the furnace blows glass")
for id, b in pairs(Data.Crafting.Branches) do ok(G[b.gesture] ~= nil and Relay.NAMES[b.gesture], id .. " batch gesture " .. b.gesture .. " exists and relays") end
-- Prompts without an IsleAction pick by their text (travel posts, NPC talk,
-- expedition and minigame prompts).
local texts = {}
for _, path in ipairs({"world.server.lua", "expedition.server.lua", "minigames.server.lua", "festival.server.lua", "coop.server.lua"}) do
	local text = fs.readFile(path)
	-- world: prompt(part, "Verb", label) with no action
	for line in text:gmatch("[^\n]+") do
		local verb = line:match('prompt%([%w_]+,%s*"([^"]+)",%s*[^,]+%)%s*$') or line:match('prompt%([%w_]+,%s*"([^"]+)",%s*[^,]+%)%.Triggered')
		if verb then texts[verb] = true end
	end
	-- expedition / minigames: prompt(part, object, "Action", callback)
	for verb in text:gmatch('prompt%([%w_]+,%s*"[^"]*",%s*"([^"]+)",%s*function') do texts[verb] = true end
	for verb in text:gmatch('ActionText%s*=%s*"([^"]+)"') do texts[verb] = true end
end
for _, t in ipairs({"Talk", "Travel to hub", "Return to quarry", "Ride the Gale", "Step through", "Board the Skybreach ferry"}) do texts[t] = true end
local textCount = 0
for verb in pairs(texts) do
	textCount += 1
	local name, source = Core.selectGesture({text = verb}, Data, 0)
	ok(G[name] ~= nil, "'" .. verb .. "' maps to a gesture")
	ok(source == "text", "'" .. verb .. "' has a text rule, not the generic fallback (" .. tostring(source) .. ")")
end
ok(textCount >= 15, "text prompts scanned (" .. textCount .. ")")
eq((Core.selectGesture({role = "Guide", text = "Talk"}, Data)), "talk", "townsfolk talk")
eq((Core.selectGesture({text = "Travel to Gale Reach"}, Data)), "attune", "travel beacons attune")
eq((Core.selectGesture({action = "gardenOpen", item = "composter"}, Data)), "open", "composter lid opens")
eq((Core.selectGesture({action = "gardenOpen", item = "visitor"}, Data)), "talk", "garden visitors talk")
eq((Core.selectGesture({}, Data)), "interact", "an unknown prompt still reaches")
-- Deferred garden plots: the reply decides plant / water / harvest / tend.
ok(Core.DEFERRED_ACTION.gardenPlot, "garden plots wait for the reply")
eq(Core.replyGesture("Planted Sunwheat in plot 2   ·   ripe in about 4m"), "plant", "planting")
eq(Core.replyGesture("Watered plot 3   ·   +25% growth for 10m"), "water", "watering")
eq(Core.replyGesture("4 Sunwheat   ·   +120 Farming XP   ·   +1 seed"), "harvest", "harvesting")
eq(Core.replyGesture("Cleared the withered crop from plot 1."), "tend", "clearing")
eq(Core.replyGesture(nil), "tend", "no reply: tend")
-- The owner's list: every named interaction has a gesture of its own.
for _, name in ipairs({"talk", "open", "hammer", "stir", "pour", "weave", "deposit", "plant", "water", "kindle", "pray", "pickup", "attune",
	"eat", "drink", "offer", "read", "survey", "pilfer", "blow", "sift", "reel", "bite"}) do
	ok(G[name] ~= nil, name .. " exists")
end
-- Consumables still eat / drink.
eq((Core.consumeGesture("Tonic restored up to 40 health.", Data)), "drink", "tonics drink")

------------------------------------------------------------------------------
-- 2. Keyframe sanity: human joint ranges, anticipation, follow-through, recovery
------------------------------------------------------------------------------
local L = Core.JOINT_LIMITS
local function inRange(name, pose, slack)
	slack = slack or 0
	for joint, v in pairs(pose) do
		local lim = L[joint]
		ok(lim ~= nil, name .. ": joint " .. joint .. " has limits")
		for axis = 1, 3 do
			local x = v[axis] or 0
			assert(x >= lim[axis][1] - slack and x <= lim[axis][2] + slack,
				name .. ": " .. joint .. " axis " .. axis .. " = " .. x .. " outside " .. lim[axis][1] .. ".." .. lim[axis][2])
		end
		for axis = 4, 6 do
			local x = v[axis] or 0
			if joint == "root" then
				assert(x >= lim.offset[1] - 1e-9 and x <= lim.offset[2] + 1e-9, name .. ": root offset " .. x)
			else
				assert(math.abs(x) < 1e-9, name .. ": only the root moves (" .. joint .. " offset " .. x .. ")")
			end
		end
		checks += 1
	end
end
local function eachKeys(def, f)
	for _, phase in ipairs({"intro", "loop", "outro", "outroFlourish"}) do
		if def[phase] then f(phase, def[phase]) end
	end
	for i, v in ipairs(def.variants or {}) do f("variant" .. i, v) end
end
local gestures = 0
for name, def in pairs(G) do
	gestures += 1
	eachKeys(def, function(phase, keys)
		for i, k in ipairs(keys) do
			inRange(name .. "." .. phase .. "[" .. i .. "]", k.pose)
			if i > 1 then ok(k.t > keys[i - 1].t, name .. "." .. phase .. " keys sorted") end
		end
		-- Interpolated frames stay human too (backOut overshoots a little).
		local buf = Core.poseBuffer()
		for step = 0, 40 do inRange(name .. "." .. phase .. " sample", Core.samplePose(keys, Core.duration(keys) * step / 40, buf), 12) end
	end)
end
ok(gestures >= 60, "gesture library size (" .. gestures .. ")")
-- Anticipation → strike → follow-through → recovery: the impact is never the
-- first or last key, the key before it is a wind-up (not rest) and a
-- follow-through key sits between the impact and the recovery.
local function impactIndex(keys)
	for i, k in ipairs(keys) do if k.mark == "impact" or k.mark == "release" then return i end end
	return nil
end
local function phrasing(name, keys)
	local i = impactIndex(keys)
	ok(i ~= nil, name .. " has an impact")
	ok(i > 2, name .. " winds up (anticipation) before the impact")
	ok(next(keys[i - 1].pose) ~= nil, name .. " anticipation is a pose")
	ok(i <= #keys - 2, name .. " has a follow-through and a recovery after the impact")
	ok(keys[#keys].t - keys[i].t >= 0.15, name .. " recovery takes time (" .. (keys[#keys].t - keys[i].t) .. " s)")
	return i
end
for _, name in ipairs({"attack", "thrust", "cleave", "lunge"}) do
	for v, keys in ipairs(G[name].variants) do phrasing(name .. " variant " .. v, keys) end
end
for _, name in ipairs({"shoot", "cast", "flick"}) do phrasing(name, G[name].loop) end
for name, def in pairs(G) do
	if def.strike then phrasing(name .. " strike", def.loop) end
end
-- Weapon classes have distinct combos.
eq(#G.attack.variants, 3, "sword: 3-hit combo")
eq(#G.thrust.variants, 3, "dagger: jab, jab, slit")
eq(#G.cleave.variants, 2, "heavy (greatblade / maul / axe): slam, sweep")
eq(#G.lunge.variants, 2, "glaive: lunge, sweep")
for _, name in ipairs({"attack", "thrust", "cleave", "lunge"}) do
	ok(G[name].combo and G[name].combo.window > 0, name .. " chains as a combo")
	ok(#G[name].combo.hitstops == #G[name].variants, name .. " hit-stop per combo step")
end
ok(G.attack.combo.hitstops[3] > G.attack.combo.hitstops[1], "the sword finisher hits harder")
local function impactAt(keys) return keys[impactIndex(keys)].t end
ok(impactAt(G.thrust.variants[1]) < impactAt(G.attack.variants[1]), "dagger stabs land quicker than sword cuts")
ok(impactAt(G.cleave.variants[1]) > impactAt(G.attack.variants[1]), "heavy weapons wind up longer")
-- Each class's swing lands before the next melee swing can replace it.
local meleeCooldown = tonumber(fs.readFile("combat.client.lua"):match("local BASE_COOLDOWN = ([%d%.]+)"))
ok(meleeCooldown ~= nil, "melee cadence read from combat.client.lua")
for _, name in ipairs({"attack", "thrust", "cleave", "lunge"}) do
	for v, keys in ipairs(G[name].variants) do
		ok(impactAt(keys) < meleeCooldown, name .. " " .. v .. " lands inside the " .. meleeCooldown .. " s cadence")
	end
	ok(G[name].combo.window > meleeCooldown, name .. " combo window outlasts the cadence")
end
-- Bow: draw → anchor → release → follow.
do
	local loop = G.shoot.loop
	local release = impactIndex(loop)
	eq(loop[release].mark, "release", "the bow looses on its release mark")
	ok(loop[release - 1].pose.rightElbow[1] > 120, "anchored at full draw before the release")
	ok(loop[release + 1].pose.rightArm[3] > loop[release].pose.rightArm[3], "the string hand flies back after the release")
end

------------------------------------------------------------------------------
-- 3. Gathering: per tool, per node size, server cadence, tier flourish, rod
------------------------------------------------------------------------------
local ST = Data.Strike
for base, T in pairs(Core.STRIKE) do
	eq(T.swing, ST.SWING[T.skill], base .. " loop = Data.Strike.SWING." .. T.skill)
	eq(T.impact, ST.IMPACT[T.skill], base .. " impact = Data.Strike.IMPACT." .. T.skill)
	eq(ST.GESTURE[T.skill], base, T.skill .. " swings " .. base)
end
for name, def in pairs(G) do
	if def.strike then
		local T = Core.STRIKE[def.strike]
		near(Core.duration(def.loop), T.swing, name .. " swing cycle = server cadence " .. T.swing .. " s")
		near(Core.duration(def.intro) + impactAt(def.loop), T.impact, name .. " first impact at the strike send " .. T.impact .. " s")
		ok(def.outroFlourish ~= nil, name .. " has a tier flourish")
		eq(def.tool, ({mine = "Pickaxe", chop = "Hatchet", harvest = "Hoe"})[def.strike], name .. " swings its tool")
	end
end
eq(Core.STRIKE.mine.swing, 0.7, "mining 0.7 s")
eq(Core.STRIKE.harvest.swing, 0.6, "farming 0.6 s")
-- Stances by node size / height (root at 0; a 2-stud rock on the floor, a vein, a high seam).
eq(Core.stanceFor("mine", 0, -2, 2), "mine_low", "a rock at the feet: crouch swing")
eq(Core.stanceFor("mine", 0, 0, 5), "mine", "a waist-high vein: the standard swing")
eq(Core.stanceFor("mine", 0, 3.2, 3), "mine_high", "a vein above the shoulders: overhead")
eq(Core.stanceFor("chop", 0, -2.2, 1.2), "chop_low", "a stump: low chop")
eq(Core.stanceFor("chop", 0, 2, 10), "chop", "a trunk: side chop")
eq(Core.stanceFor("harvest", 0, -2.6, 0.6), "harvest", "crops: crouch sickle sweep")
eq(Core.stanceFor("harvest", 0, 0.2, 3), "harvest_high", "a tall bush: standing sweep")
eq(Core.stanceFor("fish", 0, 0, 1), "fish", "fishing has no stance")
eq(Core.stanceFor("mine", nil, 0, 1), "mine", "no root: the standard swing")
for base, set in pairs(Core.STANCES) do
	for _, key in ipairs({"low", "high"}) do
		local name = set[key]
		if name then
			ok(G[name].derived and G[name].base == base, name .. " is a derived stance of " .. base)
			eq(Core.fitName(name), base, name .. " answers to " .. base .. " for the held item")
		end
	end
end
ok(Core.drivenJoints(G.mine_low).rightKnee and Core.drivenJoints(G.mine_low).root, "the low swing crouches")
ok(not Core.drivenJoints(G.mine_high).rightKnee, "the overhead swing leaves the legs to the Animator")
ok(Core.samplePose(G.mine_high.loop, impactAt(G.mine_high.loop)).rightArm[1] > Core.samplePose(G.mine.loop, impactAt(G.mine.loop)).rightArm[1] + 40,
	"the high vein is struck at head height")
ok(Core.drivenJoints(G.harvest).rightKnee, "crops are cut from a crouch")
do -- the sickle sweeps across (yaw), it does not chop down
	local loop = G.harvest.loop
	local wind = loop[impactIndex(loop) - 1].pose.rightArm[2]
	local hit = loop[impactIndex(loop)].pose.rightArm[2]
	ok(wind < -40 and hit > 20, "sickle sweep crosses the body (" .. wind .. " → " .. hit .. ")")
end
-- Tier flourish by tool tier.
do
	local seen = {}
	for id, def in pairs(Data.Items) do
		if def.kind == "tool" then seen[Core.flourishLevel(Data, id)] = true end
	end
	ok(seen[0] and seen[1] and seen[2], "tools span every flourish level")
	eq(Core.flourishLevel(Data, nil), 0, "bare hands: no flourish")
	eq(Core.flourishLevel(Data, "Ore"), 0, "non-tools: no flourish")
	ok(Core.FLOURISH_FX[3] > Core.FLOURISH_FX[1], "higher tiers throw more chips")
	local f = G.mine.outroFlourish
	local twirl = false
	for _, k in ipairs(f) do if k.pose.rightWrist and math.abs(k.pose.rightWrist[3]) > 60 then twirl = true end end
	ok(twirl, "the flourish twirls the tool")
	eq(next(f[#f].pose), nil, "the flourish ends at rest")
end
-- Fishing: the cast fits the cast gap, the reel fits the bite window, the rod bends.
do
	local F = ST.FISH
	ok(Core.duration(G.fish.intro) <= F.gap, "the cast finishes inside the " .. F.gap .. " s cast gap")
	ok(Core.duration(G.fish.outro) <= F.window, "the reel finishes inside the bite window")
	local castMark
	for _, k in ipairs(G.fish.intro) do if k.mark == "cast" then castMark = k end end
	ok(castMark and castMark.t > 0.3, "the cast loads back before the whip")
	local s = {name = "fish", phase = "intro", phaseStart = 0}
	ok(Core.rodBend(s, 0.3) < 0, "the blank loads backward on the back-swing")
	ok(Core.rodBend(s, 0.46) > 15, "and whips through on the cast")
	s.phase = "loop"
	local lo, hi = math.huge, -math.huge
	for i = 0, 18 do local b = Core.rodBend(s, i * 0.05); lo = math.min(lo, b); hi = math.max(hi, b) end
	ok(lo > 0 and hi - lo > 4, "the waiting rod bobs")
	s.biteAt = 0.5
	ok(Core.rodBend(s, 0.55) > hi + 10, "a bite snaps the tip down")
	ok(Core.rodBend(s, 0.5 + Core.BITE_TIME + 0.01) <= hi + 1e-9, "and lets go")
	s = {name = "fish", phase = "outro", phaseStart = 0}
	ok(Core.rodBend(s, 0.05) > 25 and Core.rodBend(s, 0.6) == 0, "the reel holds the fish's pull, then straightens")
	ok(Core.rodBend({name = "reel", phase = "loop", phaseStart = 0}, 0.1) > 20, "the one-shot reel bends")
	-- Bending tips the far end down about the grip's top.
	local pivot = CFrame.new(0, 0, Core.ROD_PIVOT)
	local tip = CFrame.new(0, 0, -6)
	local bent = Core.bendC0(tip, pivot, 20)
	ok(bent.Position.Y < -1, "the tip drops toward the water (" .. bent.Position.Y .. ")")
	near((bent.Position - pivot.Position).Magnitude, (tip.Position - pivot.Position).Magnitude, "the blank keeps its length", 1e-4)
	near(Core.bendC0(tip, pivot, 0).Position.Z, -6, "no bend: unchanged", 1e-6)
	ok(G.fish.rod and G.reel.rod and G.bite.rod, "every fishing gesture bends the rod")
	ok(Core.ROD_PARTS.Rod and Core.ROD_PARTS.Tip and not Core.ROD_PARTS.Grip, "the blank bends, the grip stays")
	local rodShape = {}
	for _, p in ipairs(Data.Held.SHAPES.rod) do rodShape[p.n] = p end
	for part in pairs(Core.ROD_PARTS) do ok(rodShape[part] ~= nil, "held rod has " .. part) end
	near(rodShape.Grip.o[3] - rodShape.Grip.s[3] / 2, Core.ROD_PIVOT, "the pivot is the grip's top")
	ok(client:find('gesture("bite", node)', 1, true) == nil and fs.readFile("combat.client.lua"):find('gesture("bite", node)', 1, true) ~= nil,
		"the server's bite push snaps the rod (combat.client.lua)")
end

------------------------------------------------------------------------------
-- 4. Engine: cadence, combos, crossfades, rejoin, death, cancel
------------------------------------------------------------------------------
local function motor(name)
	return {Name = name, C0 = CFrame.new(), Transform = CFrame.new(), Parent = true, IsA = function(_, c) return c == "Motor6D" end}
end
local function fakeCharacter()
	local children = {UpperTorso = {}}
	local c = {Parent = true, children = children}
	function c:FindFirstChild(name) return children[name] end
	for _, spec in ipairs(Core.RIGS.R15) do children[spec[1]] = motor(spec[1]) end
	return c
end
local function rig(dead)
	local clock = {t = 0}
	local log = {marks = {}, posts = 0, ended = 0}
	local engine = Core.createEngine({
		now = function() return clock.t end,
		alive = function(c) return c.Parent ~= nil and not (dead and dead[c]) end,
		bindRig = Core.bindRig,
		attachTool = function() return {Destroy = function() end} end,
		watch = function() return {} end,
		mark = function(state, m) table.insert(log.marks, {name = state.name, mark = m, t = clock.t}) end,
		post = function() log.posts += 1 end,
		ended = function() log.ended += 1 end,
	})
	local function run(seconds, dt)
		dt = dt or 1 / 240
		local stop = clock.t + seconds
		while clock.t < stop - 1e-9 do clock.t += dt; engine.step() end
	end
	return engine, clock, log, run
end
local function impactsOf(log, name)
	local out = {}
	for _, m in ipairs(log.marks) do if m.name == name and m.mark == "impact" then table.insert(out, m.t) end end
	return out
end
-- Strikes every 0.7 s (the server cadence) land 0.42 s after each click.
for base, T in pairs(Core.STRIKE) do
	local engine, clock, log, run = rig()
	local c = fakeCharacter()
	for n = 0, 3 do
		engine.play(c, base, {extend = true})
		run(T.swing)
	end
	run(1)
	local hits = impactsOf(log, base)
	eq(#hits, 4, base .. ": four clicks, four strikes")
	for n, t in ipairs(hits) do near(t, (n - 1) * T.swing + T.impact, base .. " strike " .. n .. " lands on the send frame", 1 / 200) end
	eq(engine.count, 0, base .. " recovers to rest after the last strike")
	ok(clock.t > 0, "clock ran")
end
-- A late click (after the grace hold, in the recovery) rejoins at the intro: still 0.42 s to impact.
do
	local engine, clock, log, run = rig()
	local c = fakeCharacter()
	engine.play(c, "mine", {extend = true, isLocal = true})
	run(1.0) -- loop done at 0.76, grace hold to 0.91: recovering
	eq(engine.get(c).phase, "outro", "recovering after the strike")
	local s = engine.play(c, "mine", {extend = true, isLocal = true})
	ok(s == engine.get(c) and s.phase == "intro" and s.from ~= nil, "the late strike rejoins with a crossfade")
	run(0.6)
	local hits = impactsOf(log, "mine")
	eq(#hits, 2, "both strikes land")
	near(hits[2], 1.0 + Core.STRIKE.mine.impact, "the rejoined strike lands on its send frame", 1 / 200)
end
-- Combos: steps chain inside the window and restart after a pause.
do
	local rec = Core.newCombo()
	eq(Core.comboNext(rec, "attack", 0), 1, "first cut")
	eq(Core.comboNext(rec, "attack", 0.45), 2, "backhand")
	eq(Core.comboNext(rec, "attack", 0.9), 3, "finisher")
	eq(Core.comboNext(rec, "attack", 1.35), 1, "the chain wraps")
	eq(Core.comboNext(rec, "attack", 1.35 + G.attack.combo.window + 0.1), 1, "a pause restarts it")
	eq(Core.comboNext(rec, "thrust", 3), 1, "another weapon class starts its own chain")
	eq(Core.comboNext(rec, "mine", 3.1), 1, "non-combo gestures: step 1")
	-- Hit-stop per combo step (local only).
	local engine = rig()
	local c = fakeCharacter()
	local s3 = engine.play(c, "attack", {variant = 3, isLocal = true})
	eq(s3.hitstop, G.attack.combo.hitstops[3], "the finisher's hit-stop")
	local s1 = engine.play(c, "attack", {variant = 1, isLocal = true})
	eq(s1.hitstop, G.attack.combo.hitstops[1], "the first cut's hit-stop")
	eq(engine.play(c, "attack", {variant = 2}).hitstop, nil, "remote swings never hit-stop")
end
-- Crossfade: chaining a combo does not snap the arm back to the Animator pose.
do
	local engine, _, _, run = rig()
	local c = fakeCharacter()
	engine.play(c, "attack", {variant = 1})
	run(0.2)
	local before = c.children.RightShoulder.Transform
	engine.play(c, "attack", {variant = 2})
	run(1 / 240)
	local after = c.children.RightShoulder.Transform
	local jump = math.deg(math.acos(math.clamp((before.LookVector:Dot(after.LookVector)), -1, 1)))
		+ math.deg(math.acos(math.clamp((before.UpVector:Dot(after.UpVector)), -1, 1)))
	ok(jump < 20, "the next combo step starts from the last arm pose (" .. jump .. "° in one frame)")
	local rest = CFrame.new()
	local snap = math.deg(math.acos(math.clamp((before.LookVector:Dot(rest.LookVector)), -1, 1)))
		+ math.deg(math.acos(math.clamp((before.UpVector:Dot(rest.UpVector)), -1, 1)))
	ok(snap > jump * 4, "a snap to rest would have been far larger (" .. snap .. "°)")
	run(2)
end
-- Tier flourish replaces the plain recovery.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter()
	engine.play(c, "chop", {extend = true, flourish = 2})
	run(1.6)
	local flourished = false
	for _, m in ipairs(log.marks) do if m.mark == "flourish" then flourished = true end end
	ok(flourished, "a tier-7 tool flourishes after its last strike")
	local engine2, _, log2, run2 = rig()
	engine2.play(c, "chop", {extend = true, flourish = 0})
	run2(1.6)
	for _, m in ipairs(log2.marks) do ok(m.mark ~= "flourish", "low tiers recover plainly") end
end
-- Death plays on a dead character and holds until the body goes.
do
	local dead = {}
	local engine, _, _, run = rig(dead)
	local c = fakeCharacter()
	dead[c] = true
	eq(engine.play(c, "mine", {}), nil, "the dead cannot swing")
	local s = engine.play(c, "death", {hold = true, noWatch = true})
	ok(s ~= nil, "death plays on the corpse")
	run(5)
	eq(engine.get(c), s, "the collapse holds")
	ok(c.children.RightKnee.Transform ~= CFrame.new(), "the knees buckle")
	c.Parent = nil
	run(0.05)
	eq(engine.count, 0, "removed with the body")
	ok(G.death.observed and G.death.dead and not Relay.NAMES.death, "death is observed from Humanoid.Died, never relayed")
end
-- Walking away from a kneel fades it out; post / ended hooks run.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter()
	engine.play(c, "pray", {})
	run(0.5)
	ok(G.pray.stopOnMove, "praying stops when you walk")
	engine.cancel(c)
	ok(engine.get(c).fadeStart ~= nil, "cancel fades")
	run(Core.FADE_OUT + 0.05)
	eq(engine.count, 0, "and ends")
	ok(log.posts > 0 and log.ended == 1, "post runs per frame, ended once")
	for _, name in ipairs({"plant", "tend", "open", "offer", "pickup"}) do ok(G[name].stopOnMove, name .. " stops on move") end
end
-- Remote fishing holds the cast until the reel arrives (bounded).
ok(G.fish.remoteHold and G.fish.remoteHold <= 30, "remote casts hold at most 30 s")
do
	local engine, _, log, run = rig()
	local c = fakeCharacter()
	engine.play(c, "fish", {hold = true, maxHold = 3, extend = true})
	run(2.5)
	local reels = 0
	for _, m in ipairs(log.marks) do if m.mark == "reel" then reels += 1 end end
	eq(reels, 0, "still waiting")
	run(2)
	for _, m in ipairs(log.marks) do if m.mark == "reel" then reels += 1 end end
	eq(reels, 1, "a lost reel relay still ends the cast")
end

------------------------------------------------------------------------------
-- 5. Body layer: landing squash, sprint lean, flinch, fidgets, NPC nod
------------------------------------------------------------------------------
do
	local b = Core.newBody()
	local now = 0
	local function frame(vy, h, reduced)
		now += 1 / 60
		return Core.bodyFeed(b, vy, h, now, 1 / 60, reduced)
	end
	for _ = 1, 10 do ok(not frame(-20, 0), "small hops do not squash") end
	ok(frame(0, 0) == false, "a hop lands without a squash")
	for _ = 1, 10 do frame(-70, 0) end
	ok(frame(-1, 0), "a real fall lands")
	ok(b.landAmp > 0.6, "harder falls squash more (" .. b.landAmp .. ")")
	local pose, active = Core.bodyPose(b, now + 0.07)
	ok(active and pose.rightKnee[1] < -25 and pose.root[5] < -0.2, "the knees take the landing")
	inRange("landing", pose)
	local _, still = Core.bodyPose(b, now + Core.LAND_TIME + 0.01)
	eq(still, false, "the squash springs back")
	for _ = 1, 120 do frame(0, 30) end
	ok(b.lean > 0.9, "sprinting leans forward")
	pose = Core.bodyPose(b, now)
	ok(pose.waist[1] < -8 and pose.neck[1] > 4, "lean at the waist, eyes level")
	for _ = 1, 120 do frame(0, 12) end
	ok(b.lean < 0.05, "walking straightens up")
	Core.bodyHit(b, 0.2, now, false)
	pose = Core.bodyPose(b, now + 0.05)
	ok(pose.waist[1] > 5 and pose.neck[1] > 6, "hits rock the head and torso back")
	inRange("flinch", pose)
	-- Everything at once stays human.
	b.land, b.landAmp, b.flinch, b.flinchAmp, b.lean = now, 1, now, 1, 1
	inRange("land + lean + flinch", (Core.bodyPose(b, now + 0.06)), 0)
	-- Reduced motion calms all three.
	local r = Core.newBody()
	for _ = 1, 10 do Core.bodyFeed(r, -80, 0, 0, 1 / 60, true) end
	Core.bodyFeed(r, 0, 0, 0, 1 / 60, true)
	ok(r.landAmp <= Core.REDUCED.land + 1e-9, "reduced motion: a gentle squash")
	for _ = 1, 200 do Core.bodyFeed(r, 0, 40, 0, 1 / 60, true) end
	ok(r.lean <= Core.REDUCED.lean + 1e-6, "reduced motion: half the lean")
	Core.bodyHit(r, 1, 0, true)
	ok(r.flinchAmp <= Core.REDUCED.flinch + 1e-9, "reduced motion: a small flinch")
	-- No per-frame tables.
	local before = gcinfo()
	for i = 1, 3000 do
		Core.bodyFeed(b, -40 + (i % 50), 20, i / 60, 1 / 60, false)
		if i % 40 == 0 then Core.bodyHit(b, 0.1, i / 60, false) end
		Core.bodyPose(b, i / 60)
	end
	ok(gcinfo() - before < 64, "3000 body frames allocate (almost) nothing (" .. (gcinfo() - before) .. " KB)")
	local from = Core.samplePose(G.attack.variants[1], 0.2)
	local buf = Core.poseBuffer()
	Core.blendFrom(from, Core.samplePose(G.attack.variants[2], 0.1, buf), 0.5, buf)
	before = gcinfo()
	for i = 1, 2000 do Core.blendFrom(from, Core.samplePose(G.attack.variants[2], (i % 40) / 100, buf), 0.5, buf) end
	ok(gcinfo() - before < 64, "crossfades reuse the pose buffer")
end
-- Idle fidgets: after IDLE_AFTER s still, then every FIDGET_GAP; moving resets.
do
	local b = Core.newBody()
	ok(not Core.fidgetDue(b, 0, true, 0.5), "not straight away")
	ok(not Core.fidgetDue(b, Core.IDLE_AFTER - 0.1, true, 0.5), "not before IDLE_AFTER")
	ok(Core.fidgetDue(b, Core.IDLE_AFTER + 0.1, true, 0.5), "a fidget once idle")
	ok(not Core.fidgetDue(b, Core.IDLE_AFTER + 1, true, 0.5), "then a pause")
	ok(Core.fidgetDue(b, Core.IDLE_AFTER + 0.1 + Core.FIDGET_GAP[2], true, 0.5), "and another")
	ok(not Core.fidgetDue(b, 100, false, 0.5) and b.stillSince == nil, "moving resets the idle clock")
	for class in pairs(Data.Held.CLASSES) do
		local name = Core.FIDGET[class]
		ok(name and G[name] and G[name].observed and not Relay.NAMES[name], class .. " has an observed idle fidget")
	end
	ok(Core.FIDGET.striker ~= nil, "Beaconry strikers fidget too")
	eq(Core.REDUCED.fidgets, false, "reduced motion: no fidgets")
	ok(client:find("still and not reduced", 1, true) ~= nil, "the runtime skips fidgets under reduced motion")
end
-- NPC nod.
near(Core.nodCurve(0), 0, "the nod starts level")
near(Core.nodCurve(Core.NOD_TIME), 0, "and ends level")
ok(Core.nodCurve(Core.NOD_TIME * 0.25) < -5, "the head dips")
ok(client:find("nodNpc(prompt:FindFirstAncestorOfClass(\"Model\"))", 1, true) ~= nil, "talking to townsfolk makes them nod")

------------------------------------------------------------------------------
-- 6. Reduced motion
------------------------------------------------------------------------------
eq(Core.shouldShake(true, G.mine, true), false, "no camera shake")
do
	local engine = rig()
	local c = fakeCharacter()
	eq(engine.play(c, "attack", {variant = 3, isLocal = true, reduced = true}).hitstop, nil, "no hit-stop")
end
ok(Core.fxBudget(true) < Core.fxBudget(false), "fewer FX parts")
eq(Core.REDUCED.flourish, false, "no tier flourish")
ok(Core.REDUCED.land < 1 and Core.REDUCED.lean < 1 and Core.REDUCED.flinch < 1, "calmer body layer")
ok(client:find("if (def.strike or def.rod) and not reduced then Core.flourishLevel", 1, true) ~= nil, "the flourish is skipped when reduced")
ok(client:find("if neck and neck:IsA(\"Motor6D\") and not reducedMotion() then", 1, true) ~= nil, "no NPC nod when reduced")
ok(client:find('(state.flourish or 0) >= 2 and not reduced', 1, true) ~= nil, "no glint when reduced")

------------------------------------------------------------------------------
-- 7. Replication budget
------------------------------------------------------------------------------
eq(Relay.RATE, 4, "4 relayed gestures a second per player")
eq(Relay.BURST, 4, "burst of 4")
ok(client:find("sendTokens = math.min(4, sendTokens + (now - sendStamp) * 4)", 1, true) ~= nil, "the client throttles to the server's rate")
eq(Core.REMOTE_CAP, 12, "12 nearest remote gesture players")
ok(Core.BODY_CAP <= Core.REMOTE_CAP, "body layer capped as tightly")
ok(Relay.BROADCAST_RANGE >= Core.REMOTE_RANGE, "the server broadcasts at least as far as clients animate")
for name in pairs(Relay.NAMES) do
	ok(#name <= 16 and G[name] ~= nil and not G[name].derived and not G[name].observed, name .. " relays a real, base gesture")
end
for name, def in pairs(G) do
	if def.derived or def.observed or def.agility then eq(Relay.NAMES[name], nil, name .. " never crosses the network") end
end
-- Fishing beats carry only a rod; interactions carry no item.
ok(Relay.itemOk(Data, "reel", "Rod") or true, "reel item check runs")
for id, def in pairs(Data.Items) do
	if def.kind == "tool" and def.toolKind == "Rod" then
		ok(Relay.itemOk(Data, "reel", id) and Relay.itemOk(Data, "bite", id), id .. " tints a relayed reel / bite")
		break
	end
end
ok(not Relay.itemOk(Data, "talk", "Pickaxe") and Relay.itemOk(Data, "talk", nil), "talk carries no item")
-- The relay: whitelisted, ranged, rate-limited.
do
	local t = 0
	local sent = 0
	local me, other = {}, {}
	local R = Relay.create({now = function() return t end, Data = Data, players = function() return {me, other} end,
		rootPosition = function(p) return if p == me then Vector3.new(0, 0, 0) else Vector3.new(30, 0, 0) end,
		targetPosition = function() return nil end, send = function() sent += 1 end})
	for _ = 1, 4 do ok((R.handle(me, "talk")), "talk relays") end
	eq((R.handle(me, "talk")), false, "the fifth in a burst is dropped")
	t = 1
	ok((R.handle(me, "pray")), "tokens refill")
	eq((R.handle(me, "mine_low")), false, "stance names are refused (derived on every client)")
	eq((R.handle(me, "fidget_blade")), false, "fidgets are refused (observed)")
	eq((R.handle(me, "death")), false, "death is refused (observed)")
	eq(sent, 5, "relayed to the nearby player")
end
-- Server-set attributes replicate to every client (no relay).
ok(client:find('own(who, who:GetAttributeChangedSignal("BeaconryGesture")', 1, true) ~= nil, "every player's kindling plays from BeaconryGesture")
ok(client:find('own(who, who:GetAttributeChangedSignal("CraftingGesture")', 1, true) ~= nil, "every player's crafting plays from CraftingGesture")
ok(client:find("playLocal(name, nil, {itemId = item, noRelay = true})", 1, true) ~= nil, "attribute gestures are not relayed again")
ok(server:find("BreakJointsOnDeath = false", 1, true) ~= nil, "joints survive death so the collapse can play")
ok(client:find("Core.admitHolders(bodyList, Core.BODY_CAP", 1, true) ~= nil, "bodies are ranked under the cap")

------------------------------------------------------------------------------
-- 7b. QC regressions (§47 review: M1-M4, L1-L11), one block each
------------------------------------------------------------------------------
local combatSource = fs.readFile("combat.client.lua")
local function rigCycles()
	local clock = {t = 0}
	local log = {marks = {}, cycles = 0}
	local engine = Core.createEngine({
		now = function() return clock.t end, alive = function(c) return c.Parent ~= nil end, bindRig = Core.bindRig,
		attachTool = function() return {Destroy = function() end} end, watch = function() return {} end,
		mark = function(state, m) table.insert(log.marks, {name = state.name, mark = m, t = clock.t}) end,
		cycle = function() log.cycles += 1 end,
	})
	local function run(seconds, dt)
		dt = dt or 1 / 240
		local stop = clock.t + seconds
		while clock.t < stop - 1e-9 do clock.t += dt; engine.step() end
	end
	return engine, clock, log, run
end
-- M1: repeated fish relays on a held remote cast refresh its bound, never queue loops; rods never cycle-relay.
do
	local engine, clock, log, run = rigCycles()
	local c = fakeCharacter()
	local s = engine.play(c, "fish", {hold = true, extend = true, maxHold = 30})
	for _ = 1, 6 do
		run(0.5)
		engine.play(c, "fish", {hold = true, extend = true, maxHold = 30})
	end
	eq(s.extra, 0, "M1: no backlog of extra loops from repeated relays")
	near(s.holdUntil, clock.t + 30, "M1: the hold bound is refreshed", 1e-6)
	eq(log.cycles, 0, "M1: a held rod never re-relays per bob")
	engine.release(c)
	run(2)
	local reels = 0
	for _, m in ipairs(log.marks) do if m.mark == "reel" then reels += 1 end end
	eq(reels, 1, "M1: one reel right after the release")
	eq(engine.count, 0, "M1: the cast ends promptly")
	-- non-rod held gestures still cycle-relay
	local engine2, _, log2, run2 = rigCycles()
	engine2.play(c, "hammer", {hold = true})
	run2(1.2)
	ok(log2.cycles >= 1, "M1: other held gestures still relay each cycle")
end
-- M2: the additive layer restores every written motor before the next frame (no CFrame equality),
-- so a joint the Animator never rewrites does not accumulate and nothing bleeds into fades.
do
	local function m(name) return {Name = name, Parent = true, Transform = CFrame.new()} end
	local entries = {{motor = m("Waist"), parts = {{"waist", 1}}, basis = CFrame.new(), basisInv = CFrame.new(), identity = true}}
	local b = {entries = entries}
	local pose = {waist = {-10, 0, 0, 0, 0, 0}}
	for _ = 1, 100 do -- no Animator: nothing rewrites Transform between frames
		Core.bodyRestore(b)
		Core.bodyApply(b, pose)
	end
	local want = Core.jointCFrame({-10, 0, 0})
	ok(entries[1].motor.Transform:FuzzyEq(want, 1e-5), "M2: 100 frames on an un-animated joint = one offset (no accumulation)")
	Core.bodyRestore(b)
	ok(entries[1].motor.Transform:FuzzyEq(CFrame.new(), 1e-6), "M2: restore puts the base back")
	local walk = CFrame.Angles(math.rad(20), 0, 0)
	for _ = 1, 10 do -- an Animator that rewrites the joint each frame
		Core.bodyRestore(b)
		entries[1].motor.Transform = walk
		Core.bodyApply(b, pose)
	end
	ok(entries[1].motor.Transform:FuzzyEq(walk * want, 1e-5), "M2: the offset rides on the Animator's pose")
	ok(client:find("RunService.PreAnimation", 1, true) and client:find("preAnimation:Connect(restoreBodies)", 1, true), "M2: restored in PreAnimation")
	ok(not client:find("== e.written", 1, true) and not client:find("Transform == e.", 1, true), "M2: no CFrame equality rewrite detection")
end
-- M3: the swing grid, the grace hold and re-phasing.
do
	local text = combatSource:match("(function GN%.nextSwing%(now, due, swing%).-\n\tend)")
	ok(text ~= nil, "M3: GN.nextSwing in combat.client.lua")
	local GN = {CONTINUOUS = tonumber(combatSource:match("GN%.CONTINUOUS = ([%d%.]+)"))}
	luau.load("local GN = ...\n" .. text:gsub("^\t", "") .. "\nreturn GN", {debugName = "nextSwing"})(GN)
	near(GN.nextSwing(0.716, 0.7, 0.7), 1.4, "M3: a continuous hold keeps the 0.7 s grid")
	near(GN.nextSwing(5, 0.7, 0.7), 5.7, "M3: after a pause the grid restarts at the click")
	near(GN.nextSwing(0.3, 0, 0.7), 1.0, "M3: the first swing starts the grid")
	ok(combatSource:find("GN.next = GN.nextSwing(now, GN.next, ST.SWING[r.skill] or 0.7)", 1, true) ~= nil, "M3: strikes use the grid")
	-- grace: a slightly late local strike re-phases (impact = click + IMPACT), no recovery dip
	local engine, clock, log, run = rigCycles()
	local c = fakeCharacter()
	engine.play(c, "mine", {extend = true, isLocal = true})
	run(0.7 + Core.STRIKE_INTRO + 0.1) -- 0.1 s into the grace hold
	eq(engine.get(c).phase, "grace", "M3: the ready pose holds after the last strike")
	local at = clock.t
	engine.play(c, "mine", {extend = true, isLocal = true})
	eq(engine.get(c).phase, "loop", "M3: a strike in the grace hold re-phases the loop")
	run(1)
	local hits = impactsOf(log, "mine")
	near(hits[2], at + Core.STRIKE.mine.impact, "M3: the re-phased strike lands IMPACT after its click", 1 / 200)
	ok(Core.STRIKE_GRACE_REMOTE > Core.STRIKE_GRACE and Core.STRIKE_GRACE >= 0.15, "M3: observers hold the ready pose longer")
	-- drifting clicks: each impact lands IMPACT after its own click
	local engine2, clock2, log2, run2 = rigCycles()
	local c2 = fakeCharacter()
	local clicks = {0, 0.72, 1.45, 2.17}
	for i, t in ipairs(clicks) do
		run2(t - clock2.t)
		engine2.play(c2, "chop", {extend = true, isLocal = true})
		if i == #clicks then run2(1.5) end
	end
	local h2 = impactsOf(log2, "chop")
	eq(#h2, #clicks, "M3: one strike per click")
	for i, t in ipairs(clicks) do near(h2[i], t + Core.STRIKE.chop.impact, "M3: drifted click " .. i .. " lands on its own send frame", 1 / 200) end
end
-- M4: corpses in range always collapse; farther ones break joints; the pose never moves the root.
do
	eq(Core.deathPlan(true, math.huge), "play", "M4: our own death always plays")
	eq(Core.deathPlan(false, Core.REMOTE_RANGE - 1), "play", "M4: a corpse in range plays (whatever the body cap)")
	eq(Core.deathPlan(false, Core.REMOTE_RANGE + 1), "break", "M4: a far corpse breaks its joints")
	eq(Core.drivenJoints(G.death).root, nil, "M4: the collapse never moves the root joint")
	ok(not client:find("if who ~= player and not (b and b.admitted) then return end", 1, true), "M4: no body-cap gate on death")
	ok(client:find("character:BreakJoints()", 1, true) ~= nil, "M4: far corpses ragdoll locally")
end
-- L1: per-loop relays only for gestures playLocal relayed.
ok(client:find("if state.isLocal and state.relayName then send(state.relayName", 1, true) ~= nil, "L1: cycle relays need a relay name")
ok(client:find("if not opts.noRelay then state.relayName = name end", 1, true) ~= nil, "L1: attribute gestures carry no relay name")
-- L2: a removed character drops its combo record.
ok(client:find("own(who, who.CharacterRemoving:Connect(forgetCharacter))", 1, true) and client:find("remoteCombos[character] = nil", 1, true),
	"L2: combos forgotten on CharacterRemoving")
-- L3: no body layer while seated / platform-standing / dead.
do
	ok(Core.bodySkip(nil), "L3: no humanoid")
	ok(Core.bodySkip({Health = 0}), "L3: dead")
	ok(Core.bodySkip({Health = 50, Sit = true}), "L3: seated")
	ok(Core.bodySkip({Health = 50, PlatformStand = true}), "L3: platform-standing")
	ok(not Core.bodySkip({Health = 50, Sit = false, PlatformStand = false}), "L3: standing")
end
-- L4: MaxHealth clamps are not hits.
do
	ok(Core.isHit(100, 80, 100, 100), "L4: damage flinches")
	ok(not Core.isHit(150, 120, 150, 120), "L4: MaxHealth 150 → 120 clamping Health is not a hit")
	ok(Core.isHit(150, 90, 150, 120), "L4: a real hit while MaxHealth drops still flinches")
	ok(not Core.isHit(80, 90, 100, 100), "L4: healing does not flinch")
	ok(not Core.isHit(10, 0, 100, 100), "L4: the killing blow is the death, not a flinch")
end
-- L5: remote fidgets go through the remote cap.
ok(client:find("playRemote(character, fidget, {})", 1, true) ~= nil, "L5: remote fidgets admitted under the cap")
-- L6: bind caches the basis inverse; identity / zero poses skip work.
do
	local r15 = fakeCharacter()
	local entries = Core.bindRig(r15)
	for _, e in ipairs(entries) do ok(e.basisInv ~= nil and e.identity == true, "L6: R15 " .. e.motor.Name .. " cached, axis-aligned") end
	eq(Core.motorTarget(entries[1], {}), Core.IDENTITY, "L6: an empty pose returns the shared identity")
	eq(Core.motorTarget(entries[1], {rightArm = {0, 0, 0}}), Core.IDENTITY, "L6: a zero pose returns the shared identity")
	local rotated = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local basis = Core.basisOf(rotated)
	local entry = {parts = {{"rightArm", 1}, {"rightElbow", 0.5}}, basis = basis, basisInv = basis:Inverse(), identity = false}
	local pose = {rightArm = {60, 10, -5}, rightElbow = {40}}
	local old = basis:Inverse() * Core.jointCFrame(pose.rightArm) * Core.jointCFrame(pose.rightElbow, 0.5) * basis
	ok(Core.motorTarget(entry, pose):FuzzyEq(old, 1e-6), "L6: the cached conversion matches the old one (R6 basis)")
end
-- L7: impact FX parts are pooled.
ok(client:find("local fx = table.remove(fxFree)", 1, true) and client:find("table.insert(fxFree, fx)", 1, true), "L7: FX parts reused from a pool")
-- L8: crafting station lists come from Data.Crafting; every one is reachable.
do
	for id, st in pairs(Data.Crafting.Stations) do
		for i, g in ipairs(st.gesture) do
			eq((Core.selectGesture({action = "craftStation", item = id}, Data, i - 1)), g, "L8: " .. id .. " gesture " .. i .. " from Data.Crafting")
		end
	end
	eq((Core.selectGesture({action = "craftStation", item = "Glassworks"}, Data, 2)), "sift", "L8: the Glass Furnace reaches sift")
	ok(client:find('if info.action == "station" or info.action == "craftStation" then stationCounter += 1 end', 1, true), "L8: craftStation counts too")
end
-- L9: a lost fish plays and relays "lost", the reel click plays the reel.
do
	ok(G.lost and G.lost.rod and Relay.NAMES.lost and Relay.itemOk(Data, "lost", nil), "L9: lost is a relayed rod gesture")
	ok(Core.rodBend({name = "lost", phase = "loop", phaseStart = 0}, 0.1) < 0, "L9: a slack line")
	eq(Core.fitName("lost"), "fish", "L9: the held rod swings it")
	local hasSplash = false
	for _, k in ipairs(G.lost.loop) do if k.mark == "reel" then hasSplash = true end end
	ok(not hasSplash and G.lost.fx == nil, "L9: no hook-set, no splash")
	ok(combatSource:find('gesture("release", node, "reel")', 1, true) ~= nil, "L9: combat marks the reel click")
	ok(client:find('playLocal("lost", state.target', 1, true) ~= nil, "L9: a plain release plays lost")
end
-- L10: leg motors are left to the walk cycle while moving.
do
	local engine, _, _, run = rigCycles()
	local c = fakeCharacter()
	local walk = CFrame.Angles(math.rad(25), 0, 0)
	engine.play(c, "mine_low", {extend = true})
	engine.setMoving(c, true)
	for _ = 1, 20 do
		c.children.RightHip.Transform = walk
		run(1 / 60)
		ok(c.children.RightHip.Transform:FuzzyEq(walk, 1e-6), "L10: the crouch leaves the hips to the walk while moving")
	end
	ok(not c.children.RightShoulder.Transform:FuzzyEq(CFrame.new(), 1e-3), "L10: the arms still swing")
	engine.setMoving(c, false)
	c.children.RightHip.Transform = walk
	run(1 / 60)
	ok(not c.children.RightHip.Transform:FuzzyEq(walk, 1e-3), "L10: standing still, the crouch returns")
	local entries = Core.bindRig(c)
	for _, e in ipairs(entries) do
		local leg = if e.motor.Name:find("Hip") or e.motor.Name:find("Knee") or e.motor.Name == "Root" then true else false
		eq(e.legs, leg, "L10: " .. e.motor.Name .. " leg flag")
	end
end
-- L11: rebinding and rod retries.
do
	local entries = Core.bindRig(fakeCharacter())
	ok(not Core.needsRebind(entries), "L11: a fresh binding is good")
	entries[5].motor.Parent = nil
	ok(Core.needsRebind(entries), "L11: any lost motor rebinds (not just the first)")
	ok(Core.needsRebind({}) and Core.needsRebind(nil), "L11: empty bindings rebind")
	ok(client:find("if Core.needsRebind(b.entries) then", 1, true) ~= nil, "L11: the ranking pass rebinds")
	local rod = client:match("local function rodWelds%(s%)(.-)\nend")
	ok(rod and not rod:find("return false", 1, true), "L11: a missing rod returns nil, so the bend retries")
	ok(client:find("s.bendRetryAt = real + ROD_RETRY", 1, true) ~= nil, "L11: retries are throttled")
end

------------------------------------------------------------------------------
-- 8. Packaging
------------------------------------------------------------------------------
ok(fs.readFile("scripts/build.sh"):find("verify-animations.luau", 1, true), "build.sh runs this suite")
ok(fs.readFile("build.ps1"):find("verify-animations.luau", 1, true), "build.ps1 runs this suite")
ok(fs.readFile("docs/DEPTH-CONTRACT.md"):find("## 47. Animation depth", 1, true), "contract §47")

print("verify-animations: " .. checks .. " checks passed")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-animations.luau")

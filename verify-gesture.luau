-- Headless checks for the gesture system (animate.client.lua + gesture.server.lua):
-- pose math and keyframe interpolation, rig conversion, prompt → gesture
-- selection, tool colours, the engine state machine (hold loops, one-shots,
-- fishing phases, cleanup on death / leave / replace), remote admission caps,
-- and the server relay's whitelist, distance, rate limit and broadcast radius.
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
local function cfNear(a, b, case)
	local ca, cb = {a:GetComponents()}, {b:GetComponents()}
	for i = 1, 12 do assert(math.abs(ca[i] - cb[i]) < 1e-4, case .. " component " .. i .. ": " .. ca[i] .. " vs " .. cb[i]) end
	checks += 1
end

------------------------------------------------------------------------------
-- 1. Easing + keyframe interpolation
------------------------------------------------------------------------------
for name, f in pairs(Core.ease) do
	near(f(0), 0, name .. "(0)")
	near(f(1), 1, name .. "(1)")
end
near(Core.ease.quadInOut(0.5), 0.5, "quadInOut midpoint")
near(Core.ease.quadIn(0.5), 0.25, "quadIn accelerates")
near(Core.ease.quadOut(0.5), 0.75, "quadOut decelerates")
ok(Core.ease.backOut(0.7) > 1, "backOut overshoots")

local keys = {
	{t = 0, pose = {rightArm = {0, 0, 0}}},
	{t = 1, ease = "linear", pose = {rightArm = {100, -20, 10}, waist = {0, 0, 0, 0, -1, 0}}},
	{t = 2, ease = "quadIn", pose = {}},
}
local p = Core.samplePose(keys, 0.5)
near(p.rightArm[1], 50, "linear lerp rx")
near(p.rightArm[2], -10, "linear lerp ry")
near(p.waist[5], -0.5, "absent joint lerps from rest")
p = Core.samplePose(keys, 1.5)
near(p.rightArm[1], 100 - 100 * 0.25, "eased segment uses the destination key's ease")
p = Core.samplePose(keys, -1)
near(p.rightArm[1], 0, "before first key clamps")
p = Core.samplePose(keys, 9)
eq(next(p), nil, "after last key = last pose (rest)")
keys[1].pose.rightArm[1] = 0
p = Core.samplePose(keys, 0)
p.rightArm[1] = 999
eq(keys[1].pose.rightArm[1], 0, "samples are copies, never aliases of the table")

-- Every gesture is well formed: sorted keys, known eases, known joints, rest-ended one-shots.
local jointSet = {}
for _, j in ipairs(Core.JOINTS) do jointSet[j] = true end
local function checkKeys(name, list)
	ok(#list >= 2 and list[1].t == 0, name .. " starts at 0")
	for i, k in ipairs(list) do
		if i > 1 then ok(k.t > list[i - 1].t, name .. " sorted") end
		ok(k.ease == nil or Core.ease[k.ease] ~= nil, name .. " ease known")
		for j in pairs(k.pose) do ok(jointSet[j], name .. " joint " .. j) end
	end
end
for name, def in pairs(Core.GESTURES) do
	for _, phase in ipairs({"intro", "loop", "outro"}) do
		if def[phase] then checkKeys(name .. "." .. phase, def[phase]) end
	end
	for i, v in ipairs(def.variants or {}) do checkKeys(name .. ".variant" .. i, v) end
	local loop = Core.keysFor(def, "loop", 1)
	ok(loop ~= nil, name .. " has a loop")
	if def.intro then
		eq(next(def.intro[1].pose), nil, name .. " intro starts from rest")
		eq(next(def.outro[#def.outro].pose), nil, name .. " outro returns to rest")
	else
		eq(next(loop[#loop].pose), nil, name .. " one-shot returns to rest")
	end
	if def.tool then ok(Core.toolSpec(def.tool) ~= nil, name .. " tool spec " .. def.tool) end
	eq(Relay.NAMES[name], true, name .. " is whitelisted on the server")
end
for name in pairs(Relay.NAMES) do ok(Core.GESTURES[name] ~= nil, "server whitelist " .. name .. " has a client gesture") end
eq(#Core.GESTURES.attack.variants, 3, "three slash variants")
ok(Core.keysFor(Core.GESTURES.attack, "loop", 4) == Core.GESTURES.attack.variants[1], "variants cycle")

------------------------------------------------------------------------------
-- 2. Joint-space conversion (R15 axis-aligned, R6 rotated C0)
------------------------------------------------------------------------------
local raise = Core.jointCFrame({90, 0, 0})
local down = CFrame.new(0, -1, 0)
near((raise * down).Position.Z, -1, "+rx raises an arm forward (-Z)")
near((Core.jointCFrame({0, 0, 90}) * down).Position.X, 1, "+rz swings a right arm outward (+X)")
near(Core.jointCFrame({0, 0, 0, 0, -0.9, 0}).Position.Y, -0.9, "offset applies")
near(Core.jointCFrame({90, 0, 0}, 0.5):ToEulerAnglesXYZ(), math.rad(45), "scale halves angles")

local r15C0 = CFrame.new(1, 0.56, 0)
cfNear(Core.toJointSpace(raise, Core.basisOf(r15C0)), raise, "R15 basis is identity")
local r6Shoulder = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0)
local r6Root = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi)
for _, c0 in ipairs({r6Shoulder, r6Root, r15C0}) do
	for _, r in ipairs({raise, Core.jointCFrame({20, -40, 15, 0, -0.5, 0.2})}) do
		local T = Core.toJointSpace(r, Core.basisOf(c0))
		-- Part0 * C0 * T must equal Part0 * pivot * R * C0rotation
		cfNear(c0 * T, CFrame.new(c0.Position) * r * Core.basisOf(c0), "pose lands in parent space for every rig")
	end
end

-- Rig binding with fake characters.
local function motor(name, c0)
	return {Name = name, C0 = c0 or CFrame.new(), Transform = CFrame.new(), IsA = function(_, c) return c == "Motor6D" end}
end
local function fakeCharacter(kind)
	local children = {}
	local c = {Parent = true, health = 100, children = children}
	function c:FindFirstChild(name) return children[name] end
	if kind == "R15" then
		children.UpperTorso = {}
		for _, spec in ipairs(Core.RIGS.R15) do children[spec[1]] = motor(spec[1]) end
	else
		children.Torso = {}
		children["Right Shoulder"] = motor("Right Shoulder", r6Shoulder)
		children["Left Shoulder"] = motor("Left Shoulder", CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0))
		children.Neck = motor("Neck", CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi))
		children.RootJoint = motor("RootJoint", r6Root)
		children["Right Hip"] = motor("Right Hip", CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0))
		children["Left Hip"] = motor("Left Hip", CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	end
	return c
end
local r15 = fakeCharacter("R15")
local entries, kind = Core.bindRig(r15)
eq(kind, "R15", "R15 detected by UpperTorso")
eq(#entries, 12, "R15 binds 12 motors")
local r6 = fakeCharacter("R6")
entries, kind = Core.bindRig(r6)
eq(kind, "R6", "R6 detected by Torso")
eq(#entries, 6, "R6 binds 6 motors")
eq(Core.bindRig({FindFirstChild = function() return nil end}), nil, "no rig, no binding")
-- R6 folds half the elbow into the shoulder.
local shoulderEntry = entries[1]
local folded = Core.motorTarget(shoulderEntry, {rightArm = {60, 0, 0}, rightElbow = {40, 0, 0}})
cfNear(r6Shoulder * folded, CFrame.new(r6Shoulder.Position) * Core.jointCFrame({80, 0, 0}) * Core.basisOf(r6Shoulder), "R6 shoulder = arm + half elbow")

------------------------------------------------------------------------------
-- 3. Prompt → gesture selection, tool colours, consume parsing
------------------------------------------------------------------------------
local function sel(action, item, coop, counter)
	return Core.selectGesture({action = action, item = item, coopResource = coop}, Data, counter)
end
eq(sel("gather", "Ore"), "mine", "Ore mines")
eq(sel("gather", "Aetherite"), "mine", "Aetherite mines")
eq(sel("gather", "Timber"), "chop", "Timber chops")
eq(sel("gather", "WindpineLog"), "chop", "logs chop")
eq(sel("gather", "Fish"), "fish", "Fish fishes")
eq(sel("gather", "Herb"), "harvest", "Herb harvests")
eq(sel("gather", "Sunwheat"), "harvest", "crops harvest")
eq(sel("gather", "Nope"), "interact", "unknown resource falls back to interact")
eq(sel(nil, nil, "Timber"), "chop", "coop timber chops")
eq(sel(nil, nil, "Ore"), "mine", "coop ore mines")
eq(sel(nil, nil, "Herb"), "harvest", "coop herb harvests")
eq(sel("station", "Forge", nil, 1), "hammer", "Forge hammers")
eq(sel("station", "Cauldron", nil, 1), "stir", "Cauldron stirs")
eq(sel("station", "Hearth", nil, 0), "flip", "Hearth flips")
eq(sel("station", "Hearth", nil, 1), "stir", "Hearth alternates to stir")
eq(sel("station", "Workbench", nil, 0), "hammer", "Workbench hammers")
eq(sel("station", "Workbench", nil, 1), "saw", "Workbench alternates to saw")
eq(sel("station", "Slayer"), "interact", "Slayer master is a conversation")
eq(sel("craft", "Blade"), "hammer", "Starforge blade hammers")
eq(sel("craft", "Pickaxe"), "hammer", "Starforge pickaxe hammers")
eq(sel("craft", "Tonic"), "stir", "Apothecary tonic stirs")
eq(sel("fight", "Warden"), "attack", "Warden strike slashes")
eq(sel("workerBuild", "2"), "hammer", "building a worker hammers")
eq(sel("decorate", "Garden"), "hammer", "decorating hammers")
for _, action in ipairs({"bank", "sell", "claim", "explore", "workerClaim"}) do eq(sel(action), "interact", action .. " reaches/presses") end
eq(sel(nil, nil), "interact", "warps/signs without attributes interact")

local function rgbOf(c) return math.floor(c.R * 255 + 0.5) .. "," .. math.floor(c.G * 255 + 0.5) .. "," .. math.floor(c.B * 255 + 0.5) end
eq(rgbOf(Core.toolColor(Data, "mine", "Pickaxe")), rgbOf(Core.hex(Data.Items.Pickaxe.color)), "copper pickaxe tints the head")
eq(rgbOf(Core.toolColor(Data, "mine", "ReinforcedPickaxe")), rgbOf(Core.hex("7FD6E8")), "reinforced pickaxe tint")
-- Every crafted tool tier colours its own gesture, and only its own.
local tiers = 0
for id, def in pairs(Data.Items) do
	if def.kind == "tool" then
		local gesture = ({Pickaxe = "mine", Hatchet = "chop", Rod = "fish", Hoe = "harvest"})[def.toolKind]
		eq(rgbOf(Core.toolColor(Data, gesture, id)), rgbOf(Core.hex(def.color)), id .. " colours " .. gesture)
		local other = if gesture == "mine" then "chop" else "mine"
		eq(rgbOf(Core.toolColor(Data, other, id)), rgbOf(Core.hex(Core.BARE_METAL)), id .. " cannot tint " .. other)
		ok(Relay.itemOk(Data, gesture, id) and not Relay.itemOk(Data, other, id), id .. " server item check agrees")
		tiers += 1
	end
end
ok(tiers >= 20, "every tool tier covered (" .. tiers .. ")")
eq(rgbOf(Core.toolColor(Data, "mine", nil)), rgbOf(Core.hex(Core.BARE_METAL)), "no tool: bare head")
eq(rgbOf(Core.toolColor(Data, "mine", "Ore")), rgbOf(Core.hex(Core.BARE_METAL)), "non-tool id ignored")
eq(rgbOf(Core.toolColor(Data, "eat", "ExpeditionRation")), rgbOf(Core.hex(Data.Items.ExpeditionRation.color)), "food tints the morsel")

local g, item = Core.consumeGesture("Tonic restored up to 40 health.", Data)
eq(g, "drink", "tonic provision drinks"); eq(item, "Tonic", "tonic id")
g, item = Core.consumeGesture("ExpeditionRation restored up to 65 health.", Data)
eq(g, "eat", "ration eats"); eq(item, "ExpeditionRation", "ration id")
g = Core.consumeGesture(Data.Items.HuntersFeast.name .. " active for 10 minutes.", Data)
eq(g, "eat", "feast eats")
for id, def in pairs(Data.Items) do
	if def.kind == "consumable" and def.category == "potion" then
		eq((Core.consumeGesture(def.name .. " active for 5 minutes.", Data)), "drink", def.name .. " drinks")
	end
end
eq(Core.consumeGesture("Already at full health.", Data), nil, "refusals do not animate")
eq(Core.consumeGesture("You have no Meadow Tonic.", Data), nil, "missing item does not animate")
eq(Core.consumeGesture(nil, Data), nil, "no message")

local hit = Core.impactPoint(Vector3.new(0, 2, 0), Vector3.new(2, 4, 2), Vector3.new(5, 3, 0))
ok(hit.X == 1 and hit.Y == 3 and hit.Z == 0, "impact on the face nearest the hand")
eq(Core.fxBudget(true) < Core.fxBudget(false), true, "reduced motion trims FX")
eq(Core.shouldShake(true, Core.GESTURES.mine, true), false, "reduced motion: no shake")
eq(Core.shouldShake(false, Core.GESTURES.mine, false), false, "remote gestures never shake our camera")
eq(Core.shouldShake(false, Core.GESTURES.mine, true), true, "local mining shakes slightly")

------------------------------------------------------------------------------
-- 4. Engine: hold loops, one-shots, phases, cleanup
------------------------------------------------------------------------------
local function rig()
	local clock = {t = 0}
	local log = {marks = {}, cycles = 0, tools = 0, destroyed = 0, disconnected = 0, conns = 0}
	local dead = {}
	local engine = Core.createEngine({
		now = function() return clock.t end,
		alive = function(c) return c.Parent ~= nil and not dead[c] end,
		bindRig = Core.bindRig,
		attachTool = function(_, kind, colour)
			log.tools += 1
			log.lastTool, log.lastColour = kind, colour
			return {Destroy = function() log.destroyed += 1 end}
		end,
		watch = function(c, onEnd)
			log.conns += 2
			log.onEnd = onEnd
			return {{Disconnect = function() log.disconnected += 1 end}, {Disconnect = function() log.disconnected += 1 end}}
		end,
		mark = function(state, m) table.insert(log.marks, state.name .. ":" .. m) end,
		cycle = function() log.cycles += 1 end,
	})
	local function run(seconds, dt)
		dt = dt or 1 / 60
		local stop = clock.t + seconds
		while clock.t < stop - 1e-9 do clock.t += dt; engine.step() end
	end
	return engine, clock, log, run, dead
end
local function count(list, value)
	local n = 0
	for _, v in ipairs(list) do if v == value then n += 1 end end
	return n
end

-- Held mining: strikes loop while held, the last strike lands, then a clean finish.
do
	local engine, clock, log, run = rig()
	local c = fakeCharacter("R15")
	local s = engine.play(c, "mine", {hold = true, color = Core.hex("B87333")})
	ok(s ~= nil and engine.count == 1, "mine starts")
	eq(log.lastTool, "Pickaxe", "pickaxe attached")
	run(0.05)
	local shoulder = c.children.RightShoulder
	ok(shoulder.Transform ~= CFrame.new(), "shoulder driven during gesture")
	run(1.4) -- intro 0.12 + ~2.3 strikes
	eq(count(log.marks, "mine:impact"), 2, "two strikes while held for 1.45s")
	eq(log.cycles, 2, "each looped strike is replicated")
	engine.release(c)
	run(1.2)
	eq(count(log.marks, "mine:impact"), 3, "current strike finishes after release")
	eq(engine.count, 0, "gesture ends after outro + fade")
	eq(log.destroyed, 1, "tool removed")
	eq(log.disconnected, 2, "watch connections released")
	cfNear(shoulder.Transform, CFrame.new(), "faded back to the animator pose (rest here)")
end

-- Unlisted joints are never written: a swing must not freeze the walk cycle
-- (hips, knees, root keep the Animator's Transform under an arm-only gesture).
do
	local engine, _, _, run = rig()
	local c = fakeCharacter("R15")
	local walk = CFrame.Angles(math.rad(25), 0, 0)
	for _, name in ipairs({"RightHip", "LeftHip", "RightKnee", "LeftKnee", "Root"}) do c.children[name].Transform = walk end
	engine.play(c, "mine", {hold = true})
	for _ = 1, 10 do
		run(0.1)
		for _, name in ipairs({"RightHip", "LeftHip", "RightKnee", "LeftKnee", "Root"}) do
			cfNear(c.children[name].Transform, walk, name .. " left to the walk cycle during a swing")
		end
	end
	ok(c.children.RightShoulder.Transform ~= CFrame.new(), "listed joints still driven")
	engine.stop(c)
	cfNear(c.children.RightHip.Transform, walk, "an abrupt stop resets only the gesture's own joints")
	local mineJoints = Core.drivenJoints(Core.GESTURES.mine)
	ok(mineJoints.rightArm and mineJoints.waist and not mineJoints.rightHip and not mineJoints.root, "mine drives arms/waist/neck only")
	local harvest = Core.drivenJoints(Core.GESTURES.harvest)
	ok(harvest.rightHip and harvest.rightKnee and harvest.root, "the harvest crouch owns the legs it lists")
	local engine2, _, _, run2 = rig()
	local c2 = fakeCharacter("R15")
	c2.children.RightHip.Transform = walk
	engine2.play(c2, "harvest", {})
	run2(0.3)
	ok(not c2.children.RightHip.Transform:FuzzyEq(walk, 1e-3), "harvest drives the hips it lists")
end

-- Instant prompt: exactly one strike.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter("R6")
	engine.play(c, "chop", {})
	run(2)
	eq(count(log.marks, "chop:impact"), 1, "instant prompt plays one strike")
	eq(log.cycles, 0, "no extra replication for one-shots")
	eq(engine.count, 0, "one-shot cleans up")
end

-- Fishing: cast → bob while held → reel. Instant: cast → reel.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter("R15")
	engine.play(c, "fish", {hold = true})
	run(2.0)
	ok(count(log.marks, "fish:cast") == 1 and count(log.marks, "fish:bob") >= 1, "cast then bob while held")
	eq(count(log.marks, "fish:reel"), 0, "no reel while held")
	engine.release(c)
	run(2)
	eq(count(log.marks, "fish:reel"), 1, "reel after release")
	eq(engine.count, 0, "fishing cleans up")
	local engine2, _, log2, run2 = rig()
	engine2.play(c, "fish", {})
	run2(2)
	ok(count(log2.marks, "fish:cast") == 1 and count(log2.marks, "fish:bob") == 0 and count(log2.marks, "fish:reel") == 1, "instant cast skips the bob")
end

-- Remote extend: a second event while playing queues one more strike.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter("R15")
	engine.play(c, "hammer", {extend = true})
	run(0.1)
	local again = engine.play(c, "hammer", {extend = true})
	eq(again, engine.get(c), "extend reuses the running gesture")
	run(2)
	eq(count(log.marks, "hammer:impact"), 2, "two strikes for two events")
	eq(log.tools, 1, "one hammer for both strikes")
end

-- Attack variants, eat and drink one-shots.
do
	local engine, _, log, run = rig()
	local c = fakeCharacter("R15")
	for v = 1, 3 do
		engine.play(c, "attack", {variant = v})
		run(0.7)
	end
	eq(count(log.marks, "attack:impact"), 3, "each slash variant lands")
	engine.play(c, "eat", {})
	run(1.4)
	eq(count(log.marks, "eat:impact"), 2, "two bites")
	engine.play(c, "drink", {})
	run(1.4)
	eq(count(log.marks, "drink:impact"), 1, "one gulp")
	eq(log.destroyed, log.tools, "every held item removed")
	eq(engine.count, 0, "idle afterwards")
end

-- Death mid-gesture, character removal, watch callback, replacement and clear.
do
	local engine, _, log, run, dead = rig()
	local c = fakeCharacter("R15")
	engine.play(c, "mine", {hold = true})
	run(0.3)
	dead[c] = true
	run(0.02)
	eq(engine.count, 0, "death stops the gesture")
	eq(log.destroyed, 1, "death removes the tool")
	cfNear(c.children.RightShoulder.Transform, CFrame.new(), "death restores joints")
	eq(engine.play(c, "mine", {}), nil, "dead characters cannot start gestures")
	dead[c] = nil

	engine.play(c, "harvest", {hold = true})
	run(0.3)
	log.onEnd() -- Died / tool equipped / seated / removed
	eq(engine.count, 0, "watch callback stops the gesture")
	eq(log.disconnected, log.conns, "all watch connections disconnected")

	local leaving = fakeCharacter("R6")
	engine.play(leaving, "chop", {hold = true})
	run(0.2)
	leaving.Parent = nil -- player left / character removing
	run(0.02)
	eq(engine.count, 0, "removed characters are dropped")

	engine.play(c, "stir", {hold = true})
	engine.play(c, "saw", {hold = true})
	eq(engine.count, 1, "replacing a gesture keeps one entry")
	eq(engine.get(c).name, "saw", "new gesture wins")
	local other = fakeCharacter("R15")
	engine.play(other, "flip", {hold = true})
	engine.clear()
	eq(engine.count, 0, "clear stops everything")
	eq(log.destroyed, log.tools, "no leaked tool models")
	eq(log.disconnected, log.conns, "no leaked connections")
	eq(engine.play(c, "dance", {}), nil, "unknown gestures ignored")
end

------------------------------------------------------------------------------
-- 5. Remote admission caps
------------------------------------------------------------------------------
do
	local active = {}
	for i = 1, Core.REMOTE_CAP do active["p" .. i] = i * 5 end
	local admit, evict = Core.admitRemote(active, "near", 3)
	ok(admit and evict == "p" .. Core.REMOTE_CAP, "nearer player evicts the farthest when full")
	admit = Core.admitRemote(active, "far", 90)
	eq(admit, false, "farther than all active when full: skipped")
	eq((Core.admitRemote({}, "x", Core.REMOTE_RANGE + 1)), false, "beyond range skipped")
	admit, evict = Core.admitRemote({}, "x", 10)
	ok(admit and evict == nil, "room available")
	ok((Core.admitRemote(active, "p3", 15)), "already animating stays admitted")
	eq(Core.REMOTE_CAP, 12, "cap is the nearest 12")
end

------------------------------------------------------------------------------
-- 6. Server relay
------------------------------------------------------------------------------
do
	local clock = 0
	local positions, sent = {}, {}
	local targets = {}
	local list = {}
	local function player(name, pos)
		local p = {Name = name}
		positions[p] = pos
		table.insert(list, p)
		return p
	end
	local relay = Relay.create({
		now = function() return clock end, Data = Data, players = function() return list end,
		rootPosition = function(p) return positions[p] end,
		targetPosition = function(t) return targets[t] end,
		send = function(to, source, name) table.insert(sent, {to = to, source = source, name = name}) end,
	})
	local a = player("A", Vector3.new(0, 0, 0))
	local near1 = player("Near", Vector3.new(50, 0, 0))
	local edge = player("Edge", Vector3.new(0, 0, 119))
	local far = player("Far", Vector3.new(200, 0, 0))
	player("Dead", nil)
	local node, distant = {}, {}
	targets[node] = Vector3.new(6, 0, 0)
	targets[distant] = Vector3.new(30, 0, 0)

	local okay, out = relay.handle(a, "mine", node, "Pickaxe")
	ok(okay, "valid gesture relays")
	eq(#out, 2, "broadcast to the two players within 120 studs")
	ok(table.find(out, near1) and table.find(out, edge) and not table.find(out, far) and not table.find(out, a), "radius excludes far players and the sender")
	eq(sent[1].source, a, "recipients learn the source player")

	local function reason(...)
		local r = {relay.handle(...)}
		return r[2]
	end
	clock += 10
	eq(reason(a, "teleport", node), "name", "unknown names dropped")
	eq(reason(a, 42, node), "name", "non-string names dropped")
	eq(reason(a, string.rep("m", 40), node), "name", "long names dropped")
	eq(reason(a, "mine", distant), "distance", "targets beyond 20 studs dropped")
	eq(reason(a, "mine", {}), "target", "non-workspace targets dropped")
	local weapon
	for id, def in pairs(Data.Items) do if def.kind == "weapon" then weapon = id; break end end
	ok(weapon ~= nil and Relay.itemOk(Data, "attack", weapon), "weapons tint slashes")
	eq(reason(a, "mine", node, weapon), "item", "a sword cannot tint a pickaxe")
	eq(reason(a, "mine", node, {}), "item", "non-string items dropped")
	eq(reason(a, "interact", node, "Pickaxe"), "item", "interact carries no item")
	eq(reason(list[5], "mine", node), "character", "no character, no relay")
	ok((relay.handle(a, "eat", nil, "ExpeditionRation")), "eat needs no target")

	-- Rate limit: burst of 4, then 4 per second.
	clock += 10
	local passed = 0
	for _ = 1, 10 do if relay.handle(a, "attack", nil) then passed += 1 end end
	eq(passed, 4, "burst capped at 4")
	clock += 0.25
	eq((relay.handle(a, "attack", nil)), true, "one token refills per 0.25s")
	eq(reason(a, "attack", nil), "rate", "then limited again")
	clock += 0.25
	eq((relay.handle(near1, "attack", nil)), true, "limits are per player")
	relay.forget(a)
	eq(relay.buckets[a], nil, "leaving players are forgotten")
	eq((relay.handle(a, "attack", nil)), true, "fresh bucket after rejoin")
	eq(Relay.TARGET_RANGE, 20, "target range")
	eq(Relay.BROADCAST_RANGE, 120, "broadcast range")
end

------------------------------------------------------------------------------
-- 7. Packaging
------------------------------------------------------------------------------
local project = fs.readFile("default.project.json")
ok(project:find('"Gestures": { "$path": "animate.client.lua" }', 1, true), "Gestures registered in StarterPlayerScripts")
ok(project:find('"GestureRelay": { "$path": "gesture.server.lua" }', 1, true), "GestureRelay registered in ServerScriptService")
ok(fs.readFile("scripts/build.sh"):find("verify-gesture.luau", 1, true), "build.sh runs this suite")
ok(fs.readFile("build.ps1"):find("verify-gesture.luau", 1, true), "build.ps1 runs this suite")
local verify = fs.readFile("verify.luau")
ok(verify:find('Gestures = "animate.client.lua"', 1, true) and verify:find('GestureRelay = "gesture.server.lua"', 1, true), "verify.luau binds both scripts")
local combat = fs.readFile("combat.client.lua")
ok(combat:find('FindFirstChild("IsleGestureLocal")', 1, true), "combat swing routes through the gesture player")
local client = fs.readFile("animate.client.lua")
ok(client:find("PromptButtonHoldBegan", 1, true) and client:find("PromptButtonHoldEnded", 1, true) and client:find("PromptTriggered", 1, true), "prompt hold + trigger hooks")
ok(client:find('GetAttribute("ReducedMotion")', 1, true), "ReducedMotion honoured")

print("verify-gesture: " .. checks .. " checks passed")

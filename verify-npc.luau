-- Guide team QA: Townsfolk data (roster, dialogue graphs, options), tutorial
-- evaluation from sample snapshots, contextual tips, waypoint target specs and
-- lifecycle, NPC placement against Workspace.Islands anchors (late islands,
-- late anchors, late attributes, fallbacks) by running the production
-- npc.server.lua against instance doubles, the recall charm's validation, and
-- the Adventure server's single "recall" hook.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local checks = 0
local function ok(cond, case)
	assert(cond, case)
	checks += 1
end
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function loadModule(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = loadModule("shared/GameData.lua")
local Progression = loadModule("shared/Progression.lua", {script = nil})
Progression.useData(Data)
local T = Data.Townsfolk
ok(T ~= nil, "Townsfolk section present")

------------------------------------------------------------------------------
-- 1. Roster and dialogue graph integrity.
------------------------------------------------------------------------------
local ACTIONS = {"to", "atlas", "waypoint", "tip", "verb", "close"}
ok(#T.Order >= 8 and #T.Order <= 12, "8-12 townsfolk")
local names, roles = {}, {}
for _, role in ipairs(T.Order) do
	ok(not roles[role], "unique role " .. role)
	roles[role] = true
	local def = T.NPCs[role]
	ok(def ~= nil, "definition for " .. role)
	ok(type(def.name) == "string" and #def.name > 2 and not names[def.name], "unique name " .. role)
	names[def.name] = true
	ok(type(def.title) == "string" and #def.title > 2, "title " .. role)
	ok(Data.RegionById[def.region] ~= nil, "region " .. role)
	for _, key in ipairs({"skin", "shirt", "pants", "shoes", "accent", "hair"}) do
		ok(type(def.look[key]) == "string" and string.match(def.look[key], "^%x%x%x%x%x%x$") ~= nil, "colour " .. role .. "." .. key)
	end
	for _, key in ipairs({"cape", "apron"}) do
		if def.look[key] then ok(string.match(def.look[key], "^%x%x%x%x%x%x$") ~= nil, "colour " .. role .. "." .. key) end
	end
	ok(type(def.look.hat) == "string" and type(def.look.held) == "string", "outfit " .. role)
	ok(def.nodes[def.start] ~= nil, "start node " .. role)
	-- Every option names exactly one valid action.
	for nodeId, node in pairs(def.nodes) do
		ok(type(node.text) == "string" and #node.text > 0, "node text " .. role .. "." .. nodeId)
		ok(#node.options > 0, "node options " .. role .. "." .. nodeId)
		local unconditional = false
		for i, option in ipairs(node.options) do
			local where = role .. "." .. nodeId .. "[" .. i .. "]"
			ok(type(option.label) == "string" and #option.label > 0 and #option.label <= 44, "label " .. where)
			local actions = 0
			for _, key in ipairs(ACTIONS) do if option[key] ~= nil then actions += 1 end end
			eq(actions, 1, "one action " .. where)
			if option.to then ok(def.nodes[option.to] ~= nil, "goto target " .. where) end
			if option.atlas then ok(T.AtlasStations[option.atlas] ~= nil, "atlas page " .. where) end
			if option.tip then ok(T.Tips[option.tip] ~= nil, "tip kind " .. where) end
			if option.close then eq(option.close, true, "close flag " .. where) end
			if option.verb then
				local rule = T.Verbs[option.verb]
				ok(rule ~= nil, "whitelisted verb " .. where)
				if rule.item == false then eq(option.item, nil, "verb takes no item " .. where)
				else ok(rule.item[option.item] == true, "verb item " .. where) end
			end
			if option.waypoint then
				if option.waypoint == "tutorial" then ok(node.tutorial == true, "tutorial waypoint only on the tutorial node " .. where)
				else
					ok(type(option.waypoint) == "table" and #option.waypoint > 0, "waypoint list " .. where)
					for _, spec in ipairs(option.waypoint) do ok(T.parseTarget(spec) ~= nil, "waypoint spec " .. spec .. " " .. where) end
				end
			end
			if option.when then ok(T.Conditions[option.when] ~= nil, "condition " .. where)
			else unconditional = true end
		end
		ok(unconditional, "node always offers a way on " .. role .. "." .. nodeId)
	end
	-- Every node is reachable from the start node.
	local seen, queue = {[def.start] = true}, {def.start}
	while #queue > 0 do
		local node = def.nodes[table.remove(queue, 1)]
		for _, option in ipairs(node.options) do
			if option.to and not seen[option.to] then seen[option.to] = true; table.insert(queue, option.to) end
		end
	end
	for nodeId in pairs(def.nodes) do ok(seen[nodeId], "reachable " .. role .. "." .. nodeId) end
	-- Every node can reach a farewell (no conversational dead ends).
	for nodeId in pairs(def.nodes) do
		local visited, stack, exit = {}, {nodeId}, false
		while #stack > 0 and not exit do
			local id = table.remove(stack)
			if not visited[id] then
				visited[id] = true
				for _, option in ipairs(def.nodes[id].options) do
					if option.close or option.atlas or option.waypoint or option.tip or option.verb then exit = true
					elseif option.to then table.insert(stack, option.to) end
				end
			end
		end
		ok(exit, "exit reachable from " .. role .. "." .. nodeId)
	end
end
for role in pairs(T.NPCs) do ok(roles[role], "ordered role " .. role) end
for _, role in ipairs({"Guide", "Banker", "Merchant", "Forgemaster", "Slayer", "Fisher", "Auctioneer", "Herald", "Registrar"}) do
	ok(T.NPCs[role] ~= nil, "required townsfolk " .. role)
end
-- Atlas pages match the field guide's stationTabs (ui.client.lua).
local ui = fs.readFile("ui.client.lua")
local tabs = string.match(ui, "local stationTabs=(%b{})")
ok(tabs ~= nil, "field guide stationTabs found")
for station in pairs(T.AtlasStations) do ok(string.find(tabs, station .. "=", 1, true) ~= nil, "atlas page known to the field guide " .. station) end
-- Verbs exist in the Adventure server.
local server = fs.readFile("server.server.lua")
for verb in pairs(T.Verbs) do ok(string.find(server, 'verb=="' .. verb .. '"', 1, true) ~= nil, "server verb " .. verb) end

------------------------------------------------------------------------------
-- 2. Tutorial evaluation from sample snapshots.
------------------------------------------------------------------------------
eq(#T.Tutorial, 6, "six tutorial steps")
local order = {"gather", "craft", "equip", "fight", "bank", "contract"}
for i, id in ipairs(order) do
	eq(T.Tutorial[i].id, id, "tutorial order " .. i)
	local step = T.Tutorial[i]
	if step.waypoint then for _, spec in ipairs(step.waypoint) do ok(T.parseTarget(spec) ~= nil, "tutorial spec " .. spec) end end
	if step.atlas then ok(T.AtlasStations[step.atlas] ~= nil, "tutorial atlas " .. id) end
end
local function fresh()
	return {items = {}, collection = {}, coins = 0, bank = 0, kills = 0, started = false, levels = {},
		quest = {title = "First sparks", detail = "Gather 3 Ore.", ready = false, stage = 1, total = 8},
		slayer = {active = false, ready = false, progress = 0, target = 2},
		journal = {contracts = 0, quests = {}},
		depth = {equipment = {}, bestiary = {}, skills = {Mining = {level = 1}, Woodcutting = {level = 1}, Fishing = {level = 1}, Farming = {level = 1}, Combat = {level = 1}},
			regions = {{id = "Windpine", name = "Windpine Grove", unlocked = false, requirement = "Woodcutting 10"}}, accessoryBag = {}, slayer = {lines = {}}}}
end
local s = fresh()
local state = T.tutorialState(s)
eq(state.current, 1, "new player starts at gather")
eq(state.done, 0, "nothing done")
eq(state.complete, false, "tutorial active")
eq(state.steps[1].need, 9, "gather needs 6 ore + 3 timber")
ok(T.Conditions.tutorialActive(s), "tutorialActive condition")
s.collection.Ore = 4
eq(T.tutorialState(s).steps[1].have, 4, "partial gather progress")
s.collection.Ore, s.collection.Timber = 12, 3
eq(T.tutorialState(s).current, 2, "gather done -> craft")
s.items.Blade = 1
eq(T.tutorialState(s).current, 3, "blade crafted -> equip")
s.depth.equipment.weapon = "Blade"
eq(T.tutorialState(s).current, 4, "equipped -> fight")
s.depth.bestiary.BramblebackBoar = 1
eq(T.tutorialState(s).current, 5, "bestiary kill -> bank")
s.bank = 25
eq(T.tutorialState(s).current, 6, "banked -> contract")
s.quest.ready = true
ok(T.Conditions.contractReady(s), "contract ready condition")
s.journal.contracts = 1
state = T.tutorialState(s)
eq(state.current, nil, "all steps done")
eq(state.complete, true, "tutorial complete")
eq(state.done, 6, "six steps done")
ok(not T.Conditions.tutorialActive(s), "tutorial no longer offered")
-- Legacy kills count and out-of-order progress is honoured.
local legacy = fresh()
legacy.kills = 3
ok(T.tutorialState(legacy).steps[4].done, "legacy Warden kills count as a fight")
eq(T.tutorialState(legacy).current, 1, "earliest unfinished step is current")
-- Contract count from the legacy quest stage when journal is absent.
local noJournal = fresh()
noJournal.journal = nil
noJournal.quest.stage = 3
eq(T.contracts(noJournal), 2, "contracts from quest stage")
-- Veterans graduate even with an untouched step.
local veteran = fresh()
veteran.journal.contracts = T.GRADUATE_CONTRACTS
ok(T.tutorialState(veteran).complete and T.tutorialState(veteran).graduated, "veterans graduate")
-- Loading / malformed snapshots never error and never show the tutorial.
for _, sample in ipairs({nil, {loading = true, message = "Opening"}, {}, "bad"}) do
	local st = T.tutorialState(sample)
	ok(st.complete == false and st.loading == true or st.complete ~= nil, "tolerant tutorial state")
	ok(not T.Conditions.tutorialActive(sample), "no tutorial while loading")
end
eq(T.tutorialState({}).current, 1, "empty snapshot evaluates as a new player")

------------------------------------------------------------------------------
-- 3. Contextual tips and conditions on sample snapshots.
------------------------------------------------------------------------------
local samples = {nil, {}, {loading = true}, fresh(), s, veteran, legacy}
for i, sample in ipairs(samples) do
	for kind, tip in pairs(T.Tips) do
		local okTip, text = pcall(tip, sample, {event = "BloomtideFair"})
		ok(okTip and type(text) == "string" and #text > 0, "tip " .. kind .. " on sample " .. i)
	end
	for id, cond in pairs(T.Conditions) do
		local okCond, value = pcall(cond, sample, {})
		ok(okCond and type(value) == "boolean", "condition " .. id .. " on sample " .. i)
	end
end
ok(has(T.Tips.next(fresh()), "Step 1/6"), "next tip follows the tutorial")
ok(has(T.Tips.next(s), "First sparks"), "graduate next tip shows the contract")
ok(has(T.Tips.contract(s), "ready"), "contract tip flags a ready claim")
local unlock = T.Tips.unlock(fresh())
ok(has(unlock, "→") and has(unlock, "Windpine Grove"), "unlock tip lists tiers and the next region")
local rich = fresh()
rich.items = {Ore = 40, Blade = 1, Tonic = 2, EmberfoxPet = 1}
local itemsTip = T.Tips.items(rich)
ok(has(itemsTip, "Equip your Copper Blade") and has(itemsTip, "Adopt your Emberfox Pet") and has(itemsTip, "Surplus"), "items tip: equip, adopt, sell")
ok(has(T.Tips.bank({coins = 500, bank = 0}), "Consider depositing"), "bank tip nudges deposits")
ok(has(T.Tips.event(nil, {event = "DeepveinSurge"}), "Deepvein Surge"), "event tip names the live event")
ok(has(T.Tips.event(nil, {nextEvent = "HollowNight"}), "Hollow Night"), "event tip names the next event")
local slayerSample = fresh()
slayerSample.depth.slayer.quest = {line = "Bramble", tier = 1, progress = 40, needed = 150}
ok(has(T.Tips.slayer(slayerSample), "40/150"), "slayer tip reports quest progress")
local questSample = fresh()
questSample.journal = {contracts = 8, quests = {{available = true, done = false, ready = false, objectives = {{3, 10}, {100, 100}}}}}
local questText = T.Tips.quest(questSample)
ok(has(questText, "Surveyor's Oath") and has(questText, "Brambleback Boar 3/10") and not has(questText, "100/100"), "quest tip shows unmet objectives")
-- Option visibility follows conditions.
local guideHello = T.NPCs.Guide.nodes.hello
local function labels(list) local out = {} for _, o in ipairs(list) do out[o.label] = true end return out end
local newOpts = labels(T.visibleOptions(guideHello, fresh(), {}))
ok(newOpts["Walk me through the basics"] and not newOpts["Claim my guild contract"], "new player sees the tutorial, no claim")
local readyOpts = labels(T.visibleOptions(guideHello, s, {}))
ok(readyOpts["Claim my guild contract"] and not readyOpts["Walk me through the basics"], "graduate with a ready contract sees the claim")
local slayerHello = T.NPCs.Slayer.nodes.hello
ok(labels(T.visibleOptions(slayerHello, fresh(), {}))["Begin a Warden hunt"], "idle hunter can begin")
ok(not labels(T.visibleOptions(slayerHello, {slayer = {active = true}}, {}))["Begin a Warden hunt"], "active hunt hides begin")
ok(not labels(T.visibleOptions(T.NPCs.Merchant.nodes.hello, fresh(), {}))["Sell my basic supplies"], "nothing to sell hides the sale")
ok(labels(T.visibleOptions(T.NPCs.Merchant.nodes.hello, {items = {Fish = 2}}, {}))["Sell my basic supplies"], "basics unlock the sale")

------------------------------------------------------------------------------
-- 4. Waypoint specs, resolution and lifecycle.
------------------------------------------------------------------------------
for _, bad in ipairs({"", "station", "teleport:Hub", "npc:", 7, "anchor:Bad Name"}) do eq(T.parseTarget(bad), nil, "rejects spec " .. tostring(bad)) end
local kind, arg = T.parseTarget("anchor:Waypoint_Forge")
ok(kind == "anchor" and arg == "Waypoint_Forge", "parses anchor spec")
eq(T.parseTarget("warpReturn"), "warpReturn", "argument-free warpReturn")
eq(T.targetLabel("npc:Banker"), "Odile Marrowcoin", "npc label")
eq(T.targetLabel("region:Windpine"), "Windpine Grove", "region label")
eq(T.targetLabel("gather:Ore"), "Copperstone Ore", "gather label")
eq(T.targetLabel("monster:BramblebackBoar"), "Brambleback Boar", "monster label")
eq(T.targetLabel("anchor:Waypoint_Forge"), "Forge", "anchor label")
local V = Vector3.new
local index = {anchors = {Anchor_Waypoint_Forge = {V(100, 0, 0), V(10, 0, 0)}}, npcs = {Banker = V(5, 0, 5)}, islands = {Hub = V(0, 0, 0)},
	station = {Forge = {V(50, 0, 0)}}, gather = {}, monster = {BramblebackBoar = {V(300, 0, 0), V(-40, 0, 0)}}, warp = {}, warpReturn = {V(0, 0, 30)}}
eq(T.resolveTarget("anchor:Waypoint_Forge", index, V(0, 0, 0)), V(10, 0, 0), "nearest anchor wins")
eq(T.resolveTarget("monster:BramblebackBoar", index, V(0, 0, 0)), V(-40, 0, 0), "nearest monster spawn")
eq(T.resolveTarget("npc:Banker", index), V(5, 0, 5), "npc target")
eq(T.resolveTarget("warpReturn", index, V(0, 0, 0)), V(0, 0, 30), "homeward beacon")
eq(T.resolveTarget("home", index), nil, "no home yet")
local pos, used = T.resolveFirst({"station:Hearth", "npc:Guide", "station:Forge", "region:Hub"}, index, V(0, 0, 0))
ok(pos == V(50, 0, 0) and used == "station:Forge", "first resolvable spec wins")
eq(T.resolveFirst({"npc:Guide"}, index), nil, "unresolvable list")
-- Lifecycle: active → arrived; lost after grace; expired after timeout.
local wp = T.newWaypoint({"station:Forge"}, "Forge", 0)
eq(T.stepWaypoint(wp, V(0, 0, 0), V(50, 0, 0), 1), "active", "far away stays active")
eq(math.floor(wp.distance), 50, "flat distance tracked")
eq(T.stepWaypoint(wp, V(48, 30, 0), V(50, 0, 0), 2), "active", "above the target (another layer) is not arrival")
eq(T.stepWaypoint(wp, V(45, 3, 2), V(50, 0, 0), 3), "arrived", "arrives within radius")
eq(T.stepWaypoint(wp, V(0, 0, 0), V(50, 0, 0), 4), "arrived", "arrival is terminal")
local lost = T.newWaypoint({"npc:Guide"}, "Pell", 10)
eq(T.stepWaypoint(lost, V(0, 0, 0), nil, 10 + T.LOST_GRACE - 1), "active", "brief resolution gaps tolerated")
eq(T.stepWaypoint(lost, V(0, 0, 0), nil, 10 + T.LOST_GRACE + 1), "lost", "unresolvable target is dropped")
local old = T.newWaypoint({"region:Hub"}, "Hub", 0)
eq(T.stepWaypoint(old, V(500, 0, 0), V(0, 0, 0), T.WAYPOINT_TIMEOUT + 1), "expired", "stale waypoint expires")
local respawn = T.newWaypoint({"region:Hub"}, "Hub", 0)
eq(T.stepWaypoint(respawn, nil, V(0, 0, 0), 5), "active", "no character (respawning) keeps the waypoint")
ok(T.MINIMAP_INTERVAL >= 0.1, "minimap at most 10 Hz")

------------------------------------------------------------------------------
-- 5. Recall rules.
------------------------------------------------------------------------------
local good, msg = T.recallCheck("Home", 100, nil, nil)
ok(good and has(msg, "Recalled"), "first recall allowed")
ok(not T.recallCheck("Skyreach", 100, nil, nil), "only Hub/Home")
ok(not T.recallCheck(nil, 100), "target required")
good, msg = T.recallCheck("Hub", 100, 100 - T.RECALL_COOLDOWN + 5, nil)
ok(not good and has(msg, "5s"), "cooldown with remaining seconds")
ok(T.recallCheck("Hub", 100, 100 - T.RECALL_COOLDOWN, nil), "cooldown elapses")
ok(not T.recallCheck("Hub", 100, nil, 100 - T.RECALL_HURT_GRACE + 1), "no recall right after damage")

------------------------------------------------------------------------------
-- 6. Production npc.server.lua against instance doubles.
------------------------------------------------------------------------------
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) table.insert(listeners, f); return {Disconnect = function() table.remove(listeners, table.find(listeners, f)) end} end,
		Fire = function(_, ...) for _, f in table.clone(listeners) do f(...) end end,
		count = function() return #listeners end,
	}
end
local SIGNALS = {ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, AttributeChanged = true,
	HealthChanged = true, CharacterAdded = true, PlayerAdded = true, PlayerRemoving = true}
local BASEPART = {Part = true, SpawnLocation = true}
local Methods, Meta = {}, {}
local rayGround = nil
local function new(class, props)
	local self = setmetatable({__class = class, __props = {Name = class}, __children = {}, __attrs = {}, __signals = {}, __changed = {}}, Meta)
	for k, v in pairs(props or {}) do self[k] = v end
	return self
end
local function descendants(inst, out)
	out = out or {}
	for _, c in ipairs(rawget(inst, "__children")) do table.insert(out, c); descendants(c, out) end
	return out
end
Meta.__index = function(self, key)
	local m = Methods[key]
	if m then return m end
	local v = rawget(self, "__props")[key]
	if v ~= nil then return v end
	if key == "ClassName" then return rawget(self, "__class") end
	if SIGNALS[key] then
		local s = rawget(self, "__signals")
		s[key] = s[key] or signal()
		return s[key]
	end
	for _, c in ipairs(rawget(self, "__children")) do if c.Name == key then return c end end
	return nil
end
Meta.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key ~= "Parent" then
		props[key] = value
		local s = rawget(self, "__changed")[key]
		if s then s:Fire() end
		return
	end
	local oldParent = props.Parent
	if oldParent == value then return end
	if oldParent then
		local subtree = {self}
		for _, d in ipairs(descendants(self)) do table.insert(subtree, d) end
		local a = oldParent
		while a do for _, d in ipairs(subtree) do a.DescendantRemoving:Fire(d) end; a = a.Parent end
		local list = rawget(oldParent, "__children")
		table.remove(list, table.find(list, self))
		props.Parent = nil
		oldParent.ChildRemoved:Fire(self)
	end
	props.Parent = value
	if value then
		table.insert(rawget(value, "__children"), self)
		value.ChildAdded:Fire(self)
		local subtree = {self}
		for _, d in ipairs(descendants(self)) do table.insert(subtree, d) end
		local a = value
		while a do for _, d in ipairs(subtree) do a.DescendantAdded:Fire(d) end; a = a.Parent end
	end
end
function Methods.GetChildren(self) return table.clone(rawget(self, "__children")) end
function Methods.GetDescendants(self) return descendants(self) end
function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(if recursive then descendants(self) else rawget(self, "__children")) do if c.Name == name then return c end end
	return nil
end
Methods.WaitForChild = Methods.FindFirstChild
function Methods.FindFirstChildOfClass(self, class)
	for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__class") == class then return c end end
	return nil
end
function Methods.IsA(self, class)
	local c = rawget(self, "__class")
	return c == class or class == "Instance" or (class == "BasePart" and BASEPART[c] == true)
end
function Methods.IsDescendantOf(self, other)
	local a = self.Parent
	while a do if a == other then return true end; a = a.Parent end
	return false
end
function Methods.SetAttribute(self, key, value)
	rawget(self, "__attrs")[key] = value
	self.AttributeChanged:Fire(key)
end
function Methods.GetAttribute(self, key) return rawget(self, "__attrs")[key] end
function Methods.GetPropertyChangedSignal(self, prop)
	local c = rawget(self, "__changed")
	c[prop] = c[prop] or signal()
	return c[prop]
end
function Methods.PivotTo(self, cf) rawget(self, "__props").__pivot = cf end
function Methods.GetPivot(self) return rawget(self, "__props").__pivot or CFrame.new() end
function Methods.Destroy(self) self.Parent = nil end
function Methods.Raycast(_, origin, direction)
	if rayGround then return {Position = Vector3.new(origin.X, rayGround, origin.Z)} end
	return nil
end

local clock = 1000
local delays = {}
local function flush() while #delays > 0 do table.remove(delays, 1)() end end
local workspaceDouble = new("Workspace", {Name = "Workspace"})
local serverStorage = new("ServerStorage", {Name = "ServerStorage"})
local playerList = {}
local players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return playerList end}
local dataMarker = {Name = "AetherData"}
local npcEnv = {
	game = {GetService = function(_, name)
		return ({Players = players, ReplicatedStorage = {WaitForChild = function() return dataMarker end}, ServerStorage = serverStorage})[name]
	end},
	workspace = workspaceDouble,
	require = function(target) assert(target == dataMarker, "unexpected require"); return Data end,
	Instance = {new = function(class) return new(class) end},
	RaycastParams = {new = function() return {} end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2,
	task = {delay = function(_, f) table.insert(delays, f) end, spawn = function(f, ...) local co = coroutine.create(f); assert(coroutine.resume(co, ...)) end,
		wait = function() end},
	os = {clock = function() return clock end, time = os.time},
}
loadModule("npc.server.lua", npcEnv)
local folder = workspaceDouble:FindFirstChild("Townsfolk")
ok(folder ~= nil, "Townsfolk folder in workspace")
eq(#folder:GetChildren(), 0, "nobody stands anywhere before islands exist")
local stash = serverStorage:FindFirstChild("TownsfolkUnplaced")
eq(#stash:GetChildren(), #T.Order, "every NPC built and waiting")
local function npc(role)
	for _, parent in ipairs({folder, stash}) do
		for _, m in ipairs(parent:GetChildren()) do if m:GetAttribute("TownsfolkRole") == role then return m end end
	end
	return nil
end
-- Rig anatomy: R15-style parts, joints, nameplate, talk prompt.
for _, role in ipairs(T.Order) do
	local m = npc(role)
	ok(m ~= nil, "rig " .. role)
	for _, part in ipairs({"HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
		"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
		ok(m:FindFirstChild(part) ~= nil, "R15 part " .. part .. " on " .. role)
	end
	for _, joint in ipairs({"Neck", "Waist", "LeftShoulder", "RightShoulder", "Root"}) do
		local j = m:FindFirstChild(joint, true)
		ok(j ~= nil and j.ClassName == "Motor6D", "joint " .. joint .. " on " .. role)
	end
	eq(m.HumanoidRootPart.Anchored, true, "anchored root " .. role)
	ok(#m:GetChildren() >= 30, "dressed rig (" .. #m:GetChildren() .. " parts) " .. role)
	local prompt = m.HumanoidRootPart:FindFirstChild("TalkPrompt")
	ok(prompt and prompt.ActionText == "Talk" and prompt:GetAttribute("TownsfolkRole") == role, "talk prompt " .. role)
	eq(prompt:GetAttribute("IsleAction"), nil, "talk prompt is ignored by the Adventure server")
	local plate = m.Head:FindFirstChild("Nameplate")
	ok(plate ~= nil and has(plate.Frame.NpcName.Text, T.NPCs[role].name) and plate.Frame.NpcTitle.Text == T.NPCs[role].title, "nameplate " .. role)
end
-- Distinct silhouettes: no two NPCs share the same hat + held + shirt.
local looks = {}
for _, role in ipairs(T.Order) do
	local l = T.NPCs[role].look
	local key = l.hat .. "/" .. l.held .. "/" .. l.shirt
	ok(not looks[key], "distinct outfit " .. role)
	looks[key] = true
end

-- Islands arrive late: an island without attributes is ignored until they are set.
local islands = new("Folder", {Name = "Islands"})
islands.Parent = workspaceDouble
local hub = new("Model", {Name = "AetherHub"})
hub.Parent = islands
flush()
eq(#folder:GetChildren(), 0, "an island without IslandCenter places nobody")
rayGround = 6
hub:SetAttribute("Region", "Hub")
hub:SetAttribute("IslandRadius", 80)
hub:SetAttribute("IslandCenter", V(1000, 5, -2000))
flush()
eq(#folder:GetChildren(), #T.Order, "late attributes place everyone (missing regions fall back to the Hub)")
local spots = {}
for _, role in ipairs(T.Order) do
	local m = npc(role)
	eq(m:GetAttribute("Placement"), "fallback", "fallback placement " .. role)
	local p = m:GetPivot().Position
	local flat = Vector3.new(p.X - 1000, 0, p.Z + 2000).Magnitude
	ok(flat >= 7 and flat <= 42, "fallback ring around the island centre " .. role)
	eq(p.Y, 6, "feet on the raycast ground " .. role)
	for other, q in pairs(spots) do ok((q - p).Magnitude > 3, "no two NPCs share a spot " .. role .. "/" .. other) end
	spots[role] = p
	-- Fallback NPCs face the island centre.
	local look = m:GetPivot().LookVector
	local toward = (Vector3.new(1000, p.Y, -2000) - p).Unit
	ok(look:Dot(toward) > 0.99, "faces the centre " .. role)
end
local grove = npc("Grovekeeper")
local groveFallback = grove:GetPivot().Position
-- A late Windpine island moves its warden home.
local windpine = new("Model", {Name = "WindpineGrove"})
windpine:SetAttribute("Region", "Windpine")
windpine:SetAttribute("IslandRadius", 120)
windpine:SetAttribute("IslandCenter", V(-3000, 40, 500))
windpine.Parent = islands
flush()
local gp = grove:GetPivot().Position
ok(Vector3.new(gp.X + 3000, 0, gp.Z - 500).Magnitude <= 42, "late region island claims its warden")
ok((gp - groveFallback).Magnitude > 100, "warden left the Hub fallback")
-- A late anchor (nested in a sub-model) overrides the fallback.
local plaza = new("Model", {Name = "Plaza"})
plaza.Parent = hub
local anchor = new("Part", {Name = "Anchor_NPC_Guide", Size = V(1, 1, 1), Position = V(1012, 9.5, -1990)})
anchor.CFrame = CFrame.lookAt(V(1012, 9.5, -1990), V(1012, 9.5, -1980))
anchor.Parent = plaza
flush()
local guide = npc("Guide")
eq(guide:GetAttribute("Placement"), "anchor", "late anchor takes over")
ok((guide:GetPivot().Position - V(1012, 9, -1990)).Magnitude < 0.01, "feet at the anchor's base")
ok(guide:GetPivot().LookVector:Dot(V(0, 0, 1)) > 0.99, "faces the anchor's look direction")
-- Moving the anchor moves the NPC.
anchor.Position = V(1020, 9.5, -1990)
anchor.CFrame = CFrame.lookAt(V(1020, 9.5, -1990), V(1020, 9.5, -2000))
flush()
ok((guide:GetPivot().Position - V(1020, 9, -1990)).Magnitude < 0.01, "anchor moves are followed")
-- Removing the anchor drops back to the ring.
anchor.Parent = nil
flush()
eq(guide:GetAttribute("Placement"), "fallback", "anchor removal falls back")
-- An anchor for a regional NPC on another island wins over its region fallback.
local deepAnchor = new("Part", {Name = "Anchor_NPC_Deepwarden", Size = V(2, 2, 2), Position = V(1030, 10, -2030)})
deepAnchor.CFrame = CFrame.new(deepAnchor.Position)
deepAnchor.Parent = hub
flush()
eq(npc("Deepwarden"):GetAttribute("Placement"), "anchor", "anchor wins wherever it is")
-- Islands removed entirely: NPCs leave the world, return when rebuilt.
islands.Parent = nil
flush()
eq(#folder:GetChildren(), 0, "no islands, nobody placed")
local rebuilt = new("Folder", {Name = "Islands"})
local hub2 = new("Model", {Name = "Hub2"})
hub2:SetAttribute("Region", "Hub")
hub2:SetAttribute("IslandRadius", 60)
hub2:SetAttribute("IslandCenter", V(0, 0, 0))
hub2.Parent = rebuilt
rebuilt.Parent = workspaceDouble
flush()
eq(#folder:GetChildren(), #T.Order, "a rebuilt Islands folder is watched")
-- Placement is pure on the scan too.
local emptyScan = T.scanIslands(nil)
eq(T.placement("Guide", emptyScan), nil, "no islands → no placement")
eq(T.placement("Nobody", T.scanIslands(rebuilt)), nil, "unknown role")
eq(T.placement("Grovekeeper", T.scanIslands(rebuilt)).island.region, "Hub", "missing region → Hub")

-- Recall charm: validation, cooldown, damage gate, destinations.
local recallFn = serverStorage:FindFirstChild("IsleRecall")
ok(recallFn ~= nil and recallFn.ClassName == "BindableFunction", "IsleRecall published")
local humanoid = new("Humanoid", {Name = "Humanoid", Health = 100})
local root = new("Part", {Name = "HumanoidRootPart", Position = V(0, 0, 0), CFrame = CFrame.new(5, 5, 5)})
local character = new("Model", {Name = "Wayfarer"})
humanoid.Parent, root.Parent = character, character
local spawnPad = new("SpawnLocation", {Name = "Home Landing", Position = V(300, 2, 400), Size = V(4, 0.5, 4)})
spawnPad.Parent = workspaceDouble
local traveller = new("Player", {Name = "Traveller", Character = character, RespawnLocation = spawnPad, UserId = 7})
table.insert(playerList, traveller)
players.PlayerAdded:Fire(traveller)
eq(recallFn.OnInvoke(traveller, "Skyreach"), "Choose Hub or Home to recall to.", "invalid target")
eq(character:GetPivot().Position, V(0, 0, 0), "no travel on an invalid target")
local reply = recallFn.OnInvoke(traveller, "Home")
ok(has(reply, "Recalled"), "home recall")
ok((character:GetPivot().Position - V(300, 5.75, 400)).Magnitude < 0.01, "lands on the home spawn")
clock += 10
ok(has(recallFn.OnInvoke(traveller, "Hub"), "recharging"), "cooldown enforced")
clock += T.RECALL_COOLDOWN
humanoid.Health = 60
humanoid.HealthChanged:Fire(60)
ok(has(recallFn.OnInvoke(traveller, "Hub"), "mid-fight"), "damage blocks recall")
clock += T.RECALL_HURT_GRACE + 1
humanoid.HealthChanged:Fire(80) -- healing never blocks
local landing = new("Part", {Name = "Anchor_Landing", Position = V(10, 2, 10), Size = V(4, 1, 4)})
landing.Parent = hub2
reply = recallFn.OnInvoke(traveller, "Hub")
ok(has(reply, "Recalled"), "hub recall")
ok((character:GetPivot().Position - V(10, 6, 10)).Magnitude < 0.01, "lands on the hub landing anchor")
clock += T.RECALL_COOLDOWN + 1
humanoid.Health = 0
eq(recallFn.OnInvoke(traveller, "Home"), "Return to your island first.", "the fallen cannot recall")
humanoid.Health = 100
traveller.RespawnLocation = nil
traveller:SetAttribute("IslandCenter", nil)
ok(has(recallFn.OnInvoke(traveller, "Home"), "isn't charted"), "no home, no travel")
traveller:SetAttribute("IslandCenter", V(-500, 3, 900))
ok(has(recallFn.OnInvoke(traveller, "Home"), "Recalled"), "home from the IslandCenter attribute (failed attempts cost no cooldown)")
-- Expedition runs: no recall out of the Observatory (no leeching the clear from home).
do
	local arena = new("Model", {Name = "The Hollow Observatory"})
	arena.Parent = workspaceDouble
	local gatePad = new("Part", {Name = "Matchmaking pad", Position = V(0, 2, 40)}) -- arena-parented, but at the hub gate
	gatePad.Parent = arena
	local heart = new("Part", {Name = "Eclipse Heart", Position = V(0, 48, 1800)})
	heart:SetAttribute("BossName", "Umbral Warden")
	heart.Parent = arena
	clock += T.RECALL_COOLDOWN + 1
	local before = character:GetPivot().Position
	root.Position = V(4, 47, 1790)
	ok(has(recallFn.OnInvoke(traveller, "Hub"), "expedition"), "recall refused inside the Observatory core")
	root.Position = V(10, 47, 1690)
	ok(has(recallFn.OnInvoke(traveller, "Home"), "expedition"), "recall refused in the sentinel hall")
	eq(character:GetPivot().Position, before, "a refused delver stays put")
	root.Position = V(0, 5, 40)
	ok(has(recallFn.OnInvoke(traveller, "Hub"), "Recalled"), "recall works at the gate (outside the run)")
	arena.Parent = nil
	root.Position = V(0, 0, 0)
end
-- Respawned characters are tracked again.
local character2 = new("Model", {Name = "Wayfarer"})
local humanoid2 = new("Humanoid", {Name = "Humanoid", Health = 100})
local root2 = new("Part", {Name = "HumanoidRootPart", CFrame = CFrame.new()})
humanoid2.Parent, root2.Parent = character2, character2
traveller.Character = character2
traveller.CharacterAdded:Fire(character2)
clock += T.RECALL_COOLDOWN + 1
humanoid2.Health = 50
humanoid2.HealthChanged:Fire(50)
ok(has(recallFn.OnInvoke(traveller, "Hub"), "mid-fight"), "damage tracked after respawn")
players.PlayerRemoving:Fire(traveller)
ok(has(recallFn.OnInvoke(traveller, "Hub"), "Recalled"), "state forgotten on leave")

------------------------------------------------------------------------------
-- 7. Adventure server hook: verb "recall" defers to ServerStorage.IsleRecall.
------------------------------------------------------------------------------
local function plainSignal()
	local listeners = {}
	return {Connect = function(_, f) table.insert(listeners, f) end, Fire = function(_, ...) for _, f in listeners do f(...) end end}
end
local data = {}
local db = {}
function db:GetAsync(key) return data[key] end
function db:UpdateAsync(key, op)
	local value = op(data[key])
	if value then data[key] = value end
	return data[key]
end
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = Progression}
local hookCalls = {}
local hookMode = "ok"
local hook = {Invoke = function(_, player, item)
	table.insert(hookCalls, {player = player, item = item})
	if hookMode == "error" then error("boom") end
	if hookMode == "nonstring" then return 5 end
	return "Recalled to " .. tostring(item) .. "."
end}
local present = true
local services = {
	Players = {PlayerAdded = plainSignal(), PlayerRemoving = plainSignal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = plainSignal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) return if name == "IsleRecall" and present then hook else nil end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "npc-test" end},
	RunService = {IsStudio = function() return false end},
}
local objects = {}
local sclock, utc = 10, 1500000000
local serverEnv = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function() return nil end},
	Instance = {new = function(class)
		local instance = {Event = plainSignal(), FireClient = function(_, player, st) player.last = st end}
		objects[class] = instance
		return instance
	end},
	os = {clock = function() return sclock end, time = function() return utc end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return 0.999 end} end},
	task = {spawn = function(f, ...) assert(coroutine.resume(coroutine.create(f), ...)) end, defer = function(f, ...) f(...) end,
		wait = function() coroutine.yield() end, delay = function() end},
}
luau.load(server:gsub("^\239\187\191", ""), {debugName = "server.server.lua", environment = serverEnv, injectGlobals = true})()
local hum = {Health = 100, MaxHealth = 100, Died = plainSignal(), TakeDamage = function(self, n) self.Health -= n end}
local pl = {GetAttribute = function(self, key) return rawget(self, "attr_" .. key) end, SetAttribute = function(self, key, value) rawset(self, "attr_" .. key, value) end,
	UserId = 42, Parent = true, CharacterAdded = plainSignal(), Kick = function() end}
pl.Character = {FindFirstChild = function() return {Position = Vector3.zero} end, FindFirstChildOfClass = function() return hum end, WaitForChild = function() return hum end}
services.Players.PlayerAdded:Fire(pl)
local function cmd(verb, item)
	sclock += 1
	return objects.RemoteFunction.OnServerInvoke(pl, verb, item)
end
local first = cmd("recall", "Home")
eq(first.message, "Recalled to Home.", "hook relays IsleRecall's answer")
eq(#hookCalls, 1, "hook invoked once")
ok(hookCalls[1].player == pl and hookCalls[1].item == "Home", "hook receives the caller and target")
hookMode = "error"
eq(cmd("recall", "Hub").message, "The recall charm flickers. Try again shortly.", "hook errors are contained")
hookMode = "nonstring"
eq(cmd("recall", "Hub").message, "The recall charm flickers. Try again shortly.", "non-string answers are refused")
hookMode = "ok"
present = false
ok(has(cmd("recall", "Hub").message, "still being charted"), "missing IsleRecall is explained")
present = true
local calls = #hookCalls
sclock += 1
eq(objects.RemoteFunction.OnServerInvoke(pl, "recall", string.rep("x", 65)).message, "That request is too long.", "oversized item rejected before the hook")
eq(#hookCalls, calls, "oversized item never reaches the hook")
hum.Health = 0
ok(not has(cmd("recall", "Home").message, "Recalled"), "dead players never reach the hook")
eq(#hookCalls, calls, "dead caller never reaches the hook")
hum.Health = 100
eq(cmd("recall", "Home").message, "Recalled to Home.", "hook works again")
ok(cmd("state").items ~= nil, "snapshot still served")

print("verify-npc: " .. checks .. " checks passed (" .. #T.Order .. " townsfolk).")

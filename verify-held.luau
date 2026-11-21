-- Headless checks for held items & swings (docs/DEPTH-CONTRACT.md §26):
-- 1. Data.Held: every weapon / tool resolves to a class and a model within the
--    part budget, tier looks, gesture fits.
-- 2. held.server.lua: welds at the right / left grip on R15 and R6, rebuild on
--    change / respawn / hand loss, cleanup on CharacterRemoving and leave.
-- 3. server.server.lua: `hold` / `hotbarSet` validation, rate limit, compact
--    reply, auto tool switch on gather with idle return, leave never saves an
--    auto switch.
-- 4. animate.client.lua: swing coverage for every gather skill, weapon class and
--    station; held item swings instead of a prop; hit-stop; carry poses.
-- 5. hotbar.client.lua: slots, keys, hold requests, auto switch, HotbarApi.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local function source(path) return (fs.readFile(path):gsub("^\239\187\191", "")) end
local function load(path, env)
	return luau.load(source(path), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local Progression = load("shared/Progression.lua", {script = nil})
Progression.useData(Data)
local HD = Data.Held

local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(a, b, case) assert(a == b, case .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end

------------------------------------------------------------------------------
-- 1. Data.Held
------------------------------------------------------------------------------
local all = HD.all()
local byClass, weapons, tools = {}, 0, 0
for id, def in pairs(Data.Items) do
	if def.kind == "weapon" or def.kind == "tool" then
		ok(HD.holdable(id), id .. " is holdable")
		if def.kind == "weapon" then weapons += 1 else tools += 1 end
	end
end
ok(weapons >= 40 and tools >= 30, "every weapon (" .. weapons .. ") and tool (" .. tools .. ") counted")
for _, id in ipairs(all) do
	local spec = HD.spec(id)
	ok(spec ~= nil, id .. " has a model")
	ok(#spec.parts >= 3 and #spec.parts <= HD.MAX_PARTS, id .. " part budget (" .. #spec.parts .. ")")
	byClass[spec.class] = (byClass[spec.class] or 0) + 1
	for _, part in ipairs(spec.parts) do
		ok(#part.colour == 6 and tonumber(part.colour, 16) ~= nil, id .. "." .. part.name .. " colour")
		ok(part.size[1] > 0 and part.size[2] > 0 and part.size[3] > 0, id .. "." .. part.name .. " size")
		ok(part.material ~= "metal", id .. " metal resolved")
	end
	eq(spec.hand, if spec.class == "shortbow" or spec.class == "longbow" or spec.class == "shield" then "left" else "right", id .. " hand")
	ok(HD.ATTACK[spec.class] ~= nil or HD.CLASSES[spec.class].kind == "tool", id .. " has a swing")
end
for _, class in ipairs({"sword", "greatblade", "dagger", "maul", "glaive", "shortbow", "longbow", "staff", "wand", "pickaxe", "hatchet", "rod", "hoe"}) do
	ok((byClass[class] or 0) > 0, "class " .. class .. " is used by items")
end
for class in pairs(HD.CLASSES) do ok(HD.SHAPES[class] ~= nil, class .. " has a shape") end
eq(HD.classOf(Data.Items.Pickaxe), "pickaxe", "copper pickaxe")
eq(HD.classOf(Data.Items.CopperHatchet), "hatchet", "hatchet")
eq(HD.classOf(Data.Items.WovenRod), "rod", "rod")
eq(HD.classOf(Data.Items.CopperHoe), "hoe", "hoe")
eq(HD.classOf(Data.Items.BrassSword), "sword", "sword")
eq(HD.classOf(Data.Items.SovereignGreatblade), "greatblade", "greatblade")
eq(HD.classOf(Data.Items.AstrarchFang), "dagger", "dagger")
eq(HD.classOf(Data.Items.BastionMaul), "maul", "maul")
eq(HD.classOf(Data.Items.EclipseGlaive), "glaive", "glaive")
eq(HD.classOf(Data.Items.MeadowShortbow), "shortbow", "shortbow")
eq(HD.classOf(Data.Items.MeadowLongbow), "longbow", "longbow")
eq(HD.classOf(Data.Items.WindpineStaff), "staff", "staff")
eq(HD.classOf(Data.Items.MeadowWand), "wand", "wand")
eq(HD.classOf(Data.Items.Ore), nil, "resources are not holdable")
eq(HD.classOf({kind = "weapon", name = "Test Buckler"}), "shield", "shield class ready for offhand items")
-- Tier look: higher tiers and rarities get richer metal, trim and an inlay.
local copper, celestial = HD.spec("Pickaxe"), HD.spec("CelestialPickaxe")
ok(copper.look.metal ~= celestial.look.metal, "tier changes the metal")
ok(copper.look.glow == nil and celestial.look.glow ~= nil, "inlay only from Epic up")
ok(#celestial.parts > #copper.parts, "the inlay is an extra part")
eq(HD.spec("Pickaxe").parts[4].colour, Data.Items.Pickaxe.color, "head takes the item colour")
-- Attack gestures by class.
eq(HD.attackGesture("BrassSword"), "attack", "sword slashes")
eq(HD.attackGesture("AstrarchFang"), "thrust", "dagger thrusts")
eq(HD.attackGesture("SovereignGreatblade"), "cleave", "greatblade cleaves")
eq(HD.attackGesture("BastionMaul"), "cleave", "maul cleaves")
eq(HD.attackGesture("EclipseGlaive"), "lunge", "glaive lunges")
eq(HD.attackGesture(nil), "attack", "bare hands slash")
-- Validation.
local function meets(p, req) return Progression.meetsRequirements(p, req) end
local prof = {items = {Pickaxe = 1, Ore = 5, CelestialPickaxe = 1}, xp = {}, equipment = {weapon = "Pickaxe"}}
eq(select(2, HD.validate(prof, "Pickaxe", meets)), "Pickaxe", "owned tool")
local okT, idT, temp = HD.validate(prof, "~Pickaxe", meets)
ok(okT and idT == "Pickaxe" and temp == true, "~ marks a temporary hold")
ok(not HD.validate(prof, "Ore", meets), "resources refused")
ok(not HD.validate(prof, "BrassSword", meets), "unowned refused")
local okR, why = HD.validate(prof, "CelestialPickaxe", meets)
ok(not okR and why:find("requires", 1, true), "requirements enforced: " .. tostring(why))
ok(not HD.validate(prof, "Nope", meets) and not HD.validate(prof, string.rep("a", 80), meets) and not HD.validate(prof, 5, meets), "junk refused")
eq(select(2, HD.validate(prof, "", meets)), "none", "empty hands")
eq(HD.resolve({items = {BrassSword = 1}, xp = {}, equipment = {weapon = "BrassSword"}}, meets), nil, "weapon held only when its requirement is met")
eq(HD.resolve({items = {Blade = 1}, xp = {}, equipment = {weapon = "Blade"}}, meets), "Blade", "default hold is the equipped weapon")
eq(HD.resolve({items = {Blade = 1}, xp = {}, equipment = {weapon = "Blade"}, held = "none"}, meets), nil, "explicit empty hands")
eq(HD.resolve({items = {Blade = 1, Pickaxe = 1}, xp = {}, equipment = {weapon = "Blade"}, held = "Pickaxe"}, meets), "Pickaxe", "explicit hold")
eq(HD.resolve({items = {Blade = 1}, xp = {}, equipment = {weapon = "Blade"}, held = "Pickaxe"}, meets), "Blade", "sold hold falls back to the weapon")
eq(HD.parseSlot("3:Pickaxe"), 3, "slot parse")
eq(HD.parseSlot("1:Pickaxe"), nil, "slots 1-2 are fixed")
eq(HD.parseSlot("x"), nil, "junk slot")
eq(HD.hotbarString({items = {Ore = 2, Pickaxe = 1}, hotbar = {s3 = "Ore", s5 = "Pickaxe", s9 = "Gone"}}), "Ore,,Pickaxe,,,,", "hotbar attribute")
local bucket = {}
local taken = 0
for _ = 1, 20 do if HD.take(bucket, 0) then taken += 1 end end
eq(taken, HD.BURST, "bucket burst")
ok(HD.take(bucket, 1 / HD.RATE), "bucket refills")

------------------------------------------------------------------------------
-- 2. held.server.lua builder + lifecycle (real lune Instances)
------------------------------------------------------------------------------
local Builder
load("held.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum, Instance = roblox.Instance,
	__HeldServerHarness = function(b) Builder = b end})
assert(Builder, "server harness hook")
local function character(rig)
	local model = roblox.Instance.new("Model")
	local names = if rig == "R15" then {"UpperTorso", "RightHand", "LeftHand"} else {"Torso", "Right Arm", "Left Arm"}
	for i, name in ipairs(names) do
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Size = if rig == "R15" then Vector3.new(0.5, 0.3, 0.5) else Vector3.new(1, 2, 1)
		part.CFrame = CFrame.new(i * 2, 3, 0)
		part.Parent = model
		if i > 1 then
			local grip = roblox.Instance.new("Attachment")
			grip.Name = if i == 2 then "RightGripAttachment" else "LeftGripAttachment"
			grip.Position = Vector3.new(0, -0.15, 0)
			grip.Parent = part
		end
	end
	return model
end
for _, rig in ipairs({"R15", "R6"}) do
	local c = character(rig)
	for _, id in ipairs(all) do
		local model, hand = Builder.build(Data, c, id)
		ok(model ~= nil, rig .. " " .. id .. " builds")
		local spec = HD.spec(id)
		eq(hand.Name, Builder.HAND[rig][spec.hand], rig .. " " .. id .. " welds to the " .. spec.hand .. " hand")
		eq(model.Name, "HeldItem", "model name")
		eq(model:GetAttribute("HeldClass"), spec.class, "class attribute")
		local parts = 0
		for _, part in ipairs(model:GetChildren()) do
			parts += 1
			ok(part.CanCollide == false and part.Massless == true and part.Anchored == false, id .. " parts are massless, non-colliding")
			local weld = part:FindFirstChild("HeldWeld")
			ok(weld and weld.Part0 == hand and weld.Part1 == part, id .. " welded to the hand")
			ok(math.abs(weld.C0.Position.Y - (-0.15 + 0)) < 3, "weld from the grip")
		end
		eq(parts, #spec.parts, id .. " part count")
		model:Destroy()
	end
end
-- Grip: the attachment position (no attachment -> bottom of the hand).
do
	local c = character("R15")
	local _, grip = Builder.gripFor(c, "right")
	ok((grip.Position - Vector3.new(0, -0.15, 0)).Magnitude < 1e-4, "grip at RightGripAttachment")
	c.RightHand.RightGripAttachment:Destroy()
	_, grip = Builder.gripFor(c, "right")
	ok((grip.Position - Vector3.new(0, -0.15, 0)).Magnitude < 1e-4, "fallback grip at the hand bottom")
	eq(Builder.build(Data, roblox.Instance.new("Model"), "Pickaxe"), nil, "no rig, no model")
	eq(Builder.build(Data, c, "Ore"), nil, "non-holdable, no model")
end
-- Lifecycle with a fake player.
local function signal()
	local s = {handlers = {}}
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		local conn = {}
		function conn.Disconnect() local i = table.find(s.handlers, fn); if i then table.remove(s.handlers, i) end end
		return conn
	end
	function s:Fire(...) for _, f in ipairs(table.clone(self.handlers)) do f(...) end end
	return s
end
do
	local deferred = {}
	local env = {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum, Instance = roblox.Instance,
		task = {defer = function(f, ...) table.insert(deferred, table.pack(f, ...)) end},
		__HeldServerHarness = function(b) Builder = b end}
	load("held.server.lua", env)
	local handGone, deaths, timers = {}, {}, {}
	local t = 100
	local S = Builder.create(Data, function(hand, onGone)
		handGone[hand] = onGone
		return {Disconnect = function() handGone[hand] = nil end}
	end, {
		now = function() return t end,
		delay = function(seconds, f) table.insert(timers, {at = t + seconds, f = f}) end,
		watchDeath = function(character, onDied)
			deaths[character] = onDied
			return {Disconnect = function() deaths[character] = nil end}
		end,
	})
	local function runTimers()
		local i = 1
		while i <= #timers do
			if timers[i].at <= t then table.remove(timers, i).f() else i += 1 end
		end
	end
	local function advance(seconds) t += seconds; runTimers() end
	local attrSignals = {}
	local who = {attrs = {}, CharacterAdded = signal(), CharacterRemoving = signal(), CharacterAppearanceLoaded = signal()}
	function who:GetAttribute(k) return self.attrs[k] end
	function who:GetAttributeChangedSignal(k) attrSignals[k] = attrSignals[k] or signal(); return attrSignals[k] end
	local function setAttr(k, v) who.attrs[k] = v; if attrSignals[k] then attrSignals[k]:Fire() end end
	local c = character("R15")
	who.Character = c
	S.track(who)
	local function flush() while #deferred > 0 do local d = table.remove(deferred, 1); d[1](table.unpack(d, 2, d.n)) end end
	flush()
	eq(c:FindFirstChild("HeldItem"), nil, "nothing held yet")
	advance(1)
	setAttr("HeldItem", "Pickaxe")
	local m1 = c:FindFirstChild("HeldItem")
	ok(m1 and m1:GetAttribute("ItemId") == "Pickaxe", "HeldItem change builds the model")
	advance(1)
	setAttr("HeldItem", "MeadowLongbow")
	local m2 = c:FindFirstChild("HeldItem")
	ok(m2 ~= m1 and m1.Parent == nil and m2:GetAttribute("HeldClass") == "longbow", "change replaces the old model")
	eq(#c:GetChildren(), 4, "exactly one held model on the character")
	-- M2 regression: equip / unequip churn (~6 HeldItem changes a second) is
	-- coalesced into at most one rebuild per REBUILD_GAP, with the latest value.
	do
		advance(1)
		local before = S.builds
		local churn = {"BrassSword", "", "Pickaxe", "", "MeadowLongbow", "Pickaxe"}
		for _, id in ipairs(churn) do
			setAttr("HeldItem", id)
			advance(1 / 6 - 0.001)
		end
		eq(S.builds - before, 2, "six changes in a second rebuild twice (now + once deferred)")
		advance(HD.REBUILD_GAP)
		ok(S.builds - before <= 3, "never more than one rebuild per gap (" .. (S.builds - before) .. ")")
		local last = c:FindFirstChild("HeldItem")
		ok(last and last:GetAttribute("ItemId") == "Pickaxe", "the deferred rebuild shows the latest value")
		eq(#c:GetChildren(), 4, "still exactly one held model after churn")
		advance(1)
		m2 = c:FindFirstChild("HeldItem")
	end
	-- Hand replaced (appearance / package): rebuilt on the new hand.
	local onGone = handGone[c.RightHand]
	ok(onGone ~= nil, "hand watched")
	onGone()
	flush()
	ok(c:FindFirstChild("HeldItem") ~= m2, "hand loss rebuilds")
	-- L1 regression: death removes the model at once (nothing drops through the
	-- floor) and nothing is rebuilt on the corpse.
	do
		ok(deaths[c] ~= nil, "death watched")
		deaths[c]()
		eq(c:FindFirstChild("HeldItem"), nil, "death destroys the held model")
		advance(1)
		setAttr("HeldItem", "BrassSword")
		advance(1)
		eq(c:FindFirstChild("HeldItem"), nil, "no rebuild on a dead character")
	end
	-- Respawn: removing clears, the new character gets its own model.
	who.CharacterRemoving:Fire(c)
	eq(c:FindFirstChild("HeldItem"), nil, "CharacterRemoving destroys the model")
	eq(next(handGone), nil, "hand watch released")
	eq(next(deaths), nil, "death watch released")
	local c2 = character("R6")
	c2.Name = "Respawned"
	who.Character = c2
	advance(1)
	setAttr("HeldItem", "MeadowLongbow")
	ok(c2:FindFirstChild("HeldItem") ~= nil, "respawned character holds the item")
	advance(1)
	setAttr("HeldItem", "")
	eq(c2:FindFirstChild("HeldItem"), nil, "empty hands remove the model")
	setAttr("HeldItem", "BrassSword")
	S.forget(who)
	runTimers()
	advance(1)
	eq(c2:FindFirstChild("HeldItem"), nil, "leave destroys the model (and cancels a pending rebuild)")
	eq(#attrSignals.HeldItem.handlers + #who.CharacterAdded.handlers + #who.CharacterRemoving.handlers, 0, "leave disconnects everything")
	eq(next(S.models), nil, "no model references kept")
end

------------------------------------------------------------------------------
-- 3. server.server.lua: hold / hotbarSet verbs and auto switch
------------------------------------------------------------------------------
do
	local function copy(value)
		if type(value) ~= "table" then return value end
		local out = {}
		for k, v in value do out[k] = copy(v) end
		return out
	end
	local clock, utc = 10, 1500000000
	local function advance(seconds) clock += seconds; utc += seconds end
	local store = {}
	local db = {}
	function db:GetAsync(key) return copy(store[key]) end
	function db:UpdateAsync(key, op)
		local value = op(copy(store[key]))
		if value then store[key] = copy(value) end
		return copy(store[key])
	end
	local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
	local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = Progression}
	local services = {
		Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
		ProximityPromptService = {PromptTriggered = signal()},
		ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
		DataStoreService = {GetDataStore = function() return db end},
		HttpService = {GenerateGUID = function() return "held-guid" end},
		RunService = {IsStudio = function() return false end},
	}
	local objects = {}
	local env = {
		game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
		workspace = {GetAttribute = function(self, key) return rawget(self, key) end},
		Instance = {new = function(class)
			local instance = {Event = signal(), FireClient = function(_, player, state) player.last = state end}
			objects[class] = instance
			return instance
		end},
		os = {clock = function() return clock end, time = function() return math.floor(utc) end},
		require = function(target) return assert(modules[target], "unexpected require") end,
		Random = {new = function() return {NextNumber = function() return 0.999 end} end},
		task = {spawn = function(f, ...) coroutine.resume(coroutine.create(f), ...) end, defer = function(f, ...) f(...) end,
			wait = function() coroutine.yield() end, delay = function() end},
	}
	luau.load(source("server.server.lua"), {environment = env, injectGlobals = true})()
	local function newPlayer(id)
		local humanoid = {Health = 100, MaxHealth = 100, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
		local root = {Position = Vector3.zero}
		local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function() end}
		function p:GetAttribute(k) return rawget(self, k) end
		function p:SetAttribute(k, v) rawset(self, k, v) end
		p.Character = {FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
			WaitForChild = function() return humanoid end}
		services.Players.PlayerAdded:Fire(p)
		return p
	end
	local function cmd(p, verb, item)
		advance(1)
		return objects.RemoteFunction.OnServerInvoke(p, verb, item)
	end
	local function node(item)
		return {Enabled = true, MaxActivationDistance = 10, GetAttribute = function(_, key)
			return ({IsleAction = "gather", IsleItem = item})[key]
		end, FindFirstAncestorWhichIsA = function() return {Position = Vector3.zero} end}
	end
	local ore, wood = node("Ore"), node("Timber")
	local function gather(p, n)
		advance(3.5)
		services.ProximityPromptService.PromptTriggered:Fire(n, p)
		return p.last
	end
	local a = newPlayer(41)
	eq(a.HeldItem, "", "fresh journal: empty hands")
	eq(a.Hotbar, ",,,,,,", "fresh hotbar")
	local r = cmd(a, "hold", "Pickaxe")
	ok(r.held == true and r.items == nil, "hold gets a compact reply, not a snapshot")
	ok(r.message:find("do not own", 1, true), "unowned: " .. r.message)
	for _ = 1, 8 do gather(a, ore) end
	for _ = 1, 5 do gather(a, wood) end
	eq(cmd(a, "craft", "Pickaxe").items.Pickaxe, 1, "pickaxe crafted")
	r = cmd(a, "hold", "Pickaxe")
	eq(r.heldItem, "Pickaxe", "owned pickaxe held")
	eq(a.HeldItem, "Pickaxe", "HeldItem attribute published")
	r = cmd(a, "hold", "Ore")
	ok(r.message:find("can't be held", 1, true) and a.HeldItem == "Pickaxe", "resources refused, hold unchanged")
	r = cmd(a, "hold", "none")
	eq(a.HeldItem, "", "hands emptied")
	-- Hold bypasses the action cooldown: a gather right after a hotbar key still works.
	advance(1)
	objects.RemoteFunction.OnServerInvoke(a, "hold", "Pickaxe")
	services.ProximityPromptService.PromptTriggered:Fire(ore, a)
	ok(a.last and a.last.message:sub(1, 1) == "+" or a.last.message:find("regrowing", 1, true), "gather after hold not blocked by the cooldown: " .. tostring(a.last.message))
	-- Rate limit: the bucket empties under spam.
	local refused = 0
	for _ = 1, 12 do
		clock += 0.1
		local reply = objects.RemoteFunction.OnServerInvoke(a, "hold", "none")
		if reply and reply.message == "One moment…" then refused += 1 end
	end
	ok(refused > 0, "hold spam is rate-limited (" .. refused .. ")")
	advance(5)
	cmd(a, "hold", "none")
	-- Auto switch: a gather with empty hands puts the pickaxe in hand, then returns.
	gather(a, ore)
	eq(a.HeldItem, "Pickaxe", "gathering ore auto-holds the pickaxe")
	advance(HD.AUTO_RETURN - 2)
	cmd(a, "state")
	eq(a.HeldItem, "Pickaxe", "still held while working")
	advance(3)
	cmd(a, "state")
	eq(a.HeldItem, "", "returned to empty hands after the idle window")
	-- Temporary "~" hold from the client: same return path.
	cmd(a, "hold", "~Pickaxe")
	eq(a.HeldItem, "Pickaxe", "~ hold applies at once")
	advance(HD.AUTO_RETURN + 1)
	cmd(a, "state")
	eq(a.HeldItem, "", "~ hold returns")
	-- An explicit hold cancels a pending return.
	cmd(a, "hold", "~Pickaxe")
	cmd(a, "hold", "Pickaxe")
	advance(HD.AUTO_RETURN + 1)
	cmd(a, "state")
	eq(a.HeldItem, "Pickaxe", "explicit hold is kept")
	-- Hotbar slots.
	r = cmd(a, "hotbarSet", "3:Ore")
	ok(r.message:find("slot 3", 1, true), "any owned item can sit in a free slot: " .. r.message)
	eq(a.Hotbar, "Ore,,,,,,", "Hotbar attribute")
	r = cmd(a, "hotbarSet", "1:Ore")
	ok(r.message:find("3-9", 1, true), "slots 1-2 are fixed")
	r = cmd(a, "hotbarSet", "4:BrassSword")
	ok(r.message:find("do not own", 1, true), "unowned refused")
	r = cmd(a, "hotbarSet", "3:")
	eq(a.Hotbar, ",,,,,,", "slot cleared")
	-- L7 regression: the compact reply carries a status field (no message parsing).
	do
		local good = cmd(a, "hotbarSet", "6:Pickaxe")
		ok(good.ok == true, "successful hotbarSet reply has ok=true")
		local bad = cmd(a, "hotbarSet", "6:BrassSword")
		ok(bad.ok == false and bad.message:find("do not own", 1, true), "refused hotbarSet reply has ok=false")
		ok(cmd(a, "hotbarSet", "6:").ok == true, "clearing reports ok")
		ok(cmd(a, "hold", "Ore").ok == false, "refused hold reports ok=false")
	end
	-- M1 regression: a temporary switch is published as HeldAuto (and an explicit
	-- hold of the very same item clears it, so the choice sticks).
	do
		cmd(a, "hold", "none")
		eq(a.HeldAuto, false, "explicit choice: HeldAuto false")
		gather(a, ore)
		ok(a.HeldItem == "Pickaxe" and a.HeldAuto == true, "auto switch publishes HeldAuto")
		cmd(a, "hold", "Pickaxe")
		ok(a.HeldItem == "Pickaxe" and a.HeldAuto == false, "explicit hold of the auto item clears HeldAuto")
		advance(HD.AUTO_RETURN + 1)
		cmd(a, "state")
		eq(a.HeldItem, "Pickaxe", "the explicit choice of the auto-held item does not revert")
		cmd(a, "hold", "~Pickaxe")
		cmd(a, "hold", "none")
		cmd(a, "hold", "~Pickaxe")
		advance(HD.AUTO_RETURN + 1)
		cmd(a, "state")
		ok(a.HeldItem == "" and a.HeldAuto == false, "auto return clears HeldAuto")
	end
	-- M4 regression: equipping a new weapon during an auto switch makes the
	-- return land on the new weapon, not the old one.
	do
		local seed = copy(store.p41)
		ok(seed and seed.profile ~= nil, "a stored profile to seed from")
		seed.owner, seed.expires = "", 0
		local prof = seed.profile
		prof.items.Blade, prof.items.BrassSword, prof.items.Pickaxe = 1, 1, 1
		prof.equipment = prof.equipment or {}
		prof.equipment.weapon, prof.held = "Blade", "Blade"
		prof.xp = prof.xp or {}
		for skill in pairs(Data.Items.BrassSword.requires or {}) do prof.xp[skill] = 1e8 end
		store.p42 = seed
		local b = newPlayer(42)
		eq(b.HeldItem, "Blade", "seeded: holding the equipped Blade")
		cmd(b, "hold", "~Pickaxe")
		ok(b.HeldItem == "Pickaxe" and b.HeldAuto == true, "auto switch to the pickaxe")
		cmd(b, "equip", "BrassSword")
		eq(b.HeldItem, "Pickaxe", "the auto switch stays until it returns")
		advance(HD.AUTO_RETURN + 1)
		cmd(b, "state")
		eq(b.HeldItem, "BrassSword", "the return lands on the newly equipped weapon")
		services.Players.PlayerRemoving:Fire(b)
	end
	-- Leaving mid auto switch never saves the temporary tool.
	cmd(a, "hold", "none")
	gather(a, ore)
	eq(a.HeldItem, "Pickaxe", "auto switch before leaving")
	-- M3 regression: the return comes due while the player is already leaving
	-- (player.Parent nil: Held.tick skips the publish). The temporary id never
	-- lived in p.held, so the save still holds the explicit choice.
	a.Parent = nil
	advance(HD.AUTO_RETURN + 1)
	cmd(a, "state")
	services.Players.PlayerRemoving:Fire(a)
	local saved
	for key, value in pairs(store) do if key == "p41" then saved = value end end
	ok(saved and saved.profile and saved.profile.held == "none", "saved hold is the explicit choice, got " .. tostring(saved and saved.profile and saved.profile.held))
end

------------------------------------------------------------------------------
-- 4. animate.client.lua swings
------------------------------------------------------------------------------
local Core
load("animate.client.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, __GestureTestHarness = function(c) Core = c end})
local Relay
load("gesture.server.lua", {Vector3 = Vector3, __GestureRelayHarness = function(r) Relay = r end})
for skill, class in pairs(HD.SKILL_CLASS) do
	local gesture = Core.SKILL_GESTURE[skill]
	ok(gesture and Core.GESTURES[gesture], skill .. " has a swing")
	ok(HD.fits(gesture, class), skill .. " swing is played by the held " .. class)
end
for class, gesture in pairs(HD.ATTACK) do
	ok(Core.GESTURES[gesture] ~= nil and Relay.NAMES[gesture], class .. " attack " .. gesture .. " exists and replicates")
	if class ~= "shield" then ok(HD.fits(gesture, class), class .. " swings itself in " .. gesture) end
end
for station, list in pairs(Core.STATION_GESTURE) do
	for _, g in ipairs(list) do ok(Core.GESTURES[g] ~= nil, station .. " station animates " .. g) end
end
for class in pairs(HD.CLASSES) do ok(Core.HOLD_POSE[class] ~= nil, class .. " has a carry pose") end
for _, name in ipairs({"thrust", "cleave", "lunge", "attack"}) do
	ok(Core.GESTURES[name].hitstop and Core.GESTURES[name].shake, name .. " has hit-stop and shake")
	ok(Relay.itemOk(Data, name, "BrassSword") and not Relay.itemOk(Data, name, "Pickaxe"), name .. " relay item check")
end
-- Engine with a fake R15 / R6 rig: held item replaces the prop, else prop + hidden held item.
local function motor(name, c0)
	return {Name = name, C0 = c0 or CFrame.new(), Transform = CFrame.new(), IsA = function(_, c) return c == "Motor6D" end}
end
local function fakeCharacter(kind)
	local children = {}
	local c = {Parent = true, children = children}
	function c:FindFirstChild(name) return children[name] end
	if kind == "R15" then
		children.UpperTorso = {}
		for _, spec in ipairs(Core.RIGS.R15) do children[spec[1]] = motor(spec[1]) end
	else
		children.Torso = {}
		children["Right Shoulder"] = motor("Right Shoulder", CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0))
		children["Left Shoulder"] = motor("Left Shoulder", CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0))
		children.Neck = motor("Neck", CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi))
		children.RootJoint = motor("RootJoint", CFrame.Angles(-math.pi / 2, 0, math.pi))
		children["Right Hip"] = motor("Right Hip", CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0))
		children["Left Hip"] = motor("Left Hip", CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	end
	return c
end
for _, kind in ipairs({"R15", "R6"}) do
	local clock = {t = 0}
	local log = {tools = 0, hidden = 0, shown = 0, marks = 0}
	local heldClass = {}
	local engine = Core.createEngine({
		now = function() return clock.t end, alive = function(c) return c.Parent ~= nil end, bindRig = Core.bindRig,
		attachTool = function() log.tools += 1; return {Destroy = function() end} end,
		watch = function() return {} end, mark = function() log.marks += 1 end,
		heldFits = function(c, name) return HD.fits(name, heldClass[c]) end,
		hideHeld = function(_, hidden) if hidden then log.hidden += 1 else log.shown += 1 end; return true end,
	})
	local function run(seconds) local stop = clock.t + seconds; while clock.t < stop do clock.t += 1 / 60; engine.step() end end
	local c = fakeCharacter(kind)
	for skill, class in pairs(HD.SKILL_CLASS) do
		heldClass[c] = class
		engine.play(c, Core.SKILL_GESTURE[skill], {})
		run(2)
	end
	for class, gesture in pairs(HD.ATTACK) do
		heldClass[c] = class
		engine.play(c, gesture, {variant = 2})
		run(1)
	end
	eq(log.tools, 1, kind .. ": held items swing themselves; only the shield (no attack fit) used a prop")
	-- Station hammer with a sword in hand: a prop appears and the sword hides, then shows again.
	heldClass[c] = "sword"
	engine.play(c, "stir", {})
	run(2)
	eq(log.tools, 2, kind .. ": station prop")
	eq(log.hidden, log.shown, kind .. ": held item hidden during the prop and shown after")
	ok(log.hidden >= 2, kind .. ": hidden twice")
	eq(engine.count, 0, kind .. ": idle afterwards")
	-- Every weapon class swing drives the rig.
	for _, gesture in ipairs({"thrust", "cleave", "lunge"}) do
		engine.play(c, gesture, {variant = 1})
		run(0.2)
		local shoulder = c.children.RightShoulder or c.children["Right Shoulder"]
		ok(shoulder.Transform ~= CFrame.new(), kind .. " " .. gesture .. " moves the shoulder")
		run(1)
	end
	-- Hold poses produce targets on both rigs.
	for class, pose in pairs(Core.HOLD_POSE) do
		local targets = Core.holdTargets(Core.bindRig(c), pose)
		ok(#targets >= 1, kind .. " " .. class .. " carry pose drives a motor")
	end
end
-- Hit-stop: a local cleave lands later than a remote one by the freeze time.
do
	local function impactTime(isLocal)
		local clock, hit = {t = 0}, nil
		local engine = Core.createEngine({now = function() return clock.t end, alive = function() return true end, bindRig = Core.bindRig,
			attachTool = function() return nil end, watch = function() return {} end, mark = function() end})
		local c = fakeCharacter("R15")
		engine.play(c, "cleave", {variant = 1, isLocal = isLocal})
		local done
		while clock.t < 2 do
			clock.t += 1 / 120
			engine.step()
			if not engine.get(c) and not done then done = clock.t end
		end
		return done
	end
	local localEnd, remoteEnd = impactTime(true), impactTime(false)
	ok(localEnd - remoteEnd > 0.05, "local hit-stop holds the swing (" .. localEnd .. " vs " .. remoteEnd .. ")")
end
-- L2 regression: an observer starts a remote mine with the prop (HeldItem not
-- replicated yet); when the pickaxe model arrives the prop goes and the swing
-- uses it (never two pickaxes). A model that does not fit is hidden instead.
do
	local clock = {t = 0}
	local arrive, props, hidden = {}, {}, {}
	local engine = Core.createEngine({
		now = function() return clock.t end, alive = function() return true end, bindRig = Core.bindRig,
		attachTool = function(c)
			local prop = {alive = true}
			function prop.Destroy() prop.alive = false end
			props[c] = prop
			return prop
		end,
		watch = function() return {} end, mark = function() end,
		heldFits = function() return false end,
		hideHeld = function(c, h) hidden[c] = h; return true end,
		watchHeld = function(c, onArrive) arrive[c] = onArrive; return {Disconnect = function() arrive[c] = nil end} end,
		modelFits = function(model, name) return HD.fits(name, model.class) end,
	})
	local c = fakeCharacter("R15")
	local s = engine.play(c, "mine", {})
	ok(props[c] and props[c].alive and arrive[c] ~= nil, "prop shown and HeldItem watched while it is out")
	arrive[c]({class = "pickaxe"})
	ok(not props[c].alive and s.tool == nil and s.usesHeld, "the arriving pickaxe replaces the prop")
	eq(hidden[c], false, "and is shown")
	local c2 = fakeCharacter("R15")
	engine.play(c2, "mine", {})
	arrive[c2]({class = "sword"})
	ok(props[c2].alive and hidden[c2] == true, "a non-fitting arrival is hidden while the prop stays")
	engine.stop(c2)
	eq(arrive[c2], nil, "HeldItem watch released when the gesture ends")
	eq(hidden[c2], false, "hidden model shown again after the gesture")
end
-- L3 regression: our pending auto switch is dropped as soon as the reply shows
-- another item in hand (refused / rate-limited), not only after the timeout.
do
	local P = Core.newPending()
	P.set("Pickaxe", 10)
	eq(P.get(10.1), "Pickaxe", "pending while in flight")
	P.reply("Pickaxe", "")
	eq(P.get(10.2), nil, "refused reply clears the pending fit")
	P.set("Pickaxe", 20)
	P.reply("CopperHatchet", "")
	eq(P.get(20.1), "Pickaxe", "a reply to another request leaves it")
	P.reply("Pickaxe", "Pickaxe")
	eq(P.get(20.2), "Pickaxe", "a granted reply keeps it until HeldItem replicates")
	eq(P.get(20 + Core.PENDING_HOLD + 0.01), nil, "timeout still applies")
end
-- L10 regression: carry poses only for the REMOTE_CAP nearest holders in range,
-- and samplePose reuses its buffer (no per-frame tables).
do
	local list = {}
	for i = 1, 20 do table.insert(list, {distance = 21 - i}) end
	table.insert(list, {distance = Core.REMOTE_RANGE + 5})
	table.insert(list, {distance = -1, isLocal = true})
	Core.admitHolders(list, Core.REMOTE_CAP + 1)
	local admitted, farthest = 0, -math.huge
	for _, h in ipairs(list) do
		if h.admitted then admitted += 1; farthest = math.max(farthest, h.distance) end
		if h.isLocal then ok(h.admitted, "the local holder is always posed") end
	end
	eq(admitted, Core.REMOTE_CAP + 1, "local + REMOTE_CAP nearest remote holders posed")
	eq(farthest, Core.REMOTE_CAP, "the nearest ones win")
	local keys = Core.GESTURES.mine.loop
	local buf = Core.poseBuffer()
	local a = Core.samplePose(keys, 0.1, buf)
	local arm = a.rightArm
	local b = Core.samplePose(keys, 0.2, buf)
	ok(a == b and b == buf.out and (arm == nil or b.rightArm == arm), "samplePose reuses the buffer and joint arrays")
	local fresh = Core.samplePose(keys, 0.2)
	for joint, v in pairs(fresh) do
		for k = 1, 6 do ok(math.abs((v[k] or 0) - (b[joint][k] or 0)) < 1e-9, "buffered sample matches " .. joint) end
	end
	for joint in pairs(b) do ok(fresh[joint] ~= nil, "no stale joint " .. joint .. " in the buffer") end
	local before = gcinfo()
	for i = 1, 2000 do Core.samplePose(keys, (i % 50) / 100, buf) end
	ok(gcinfo() - before < 64, "2000 buffered samples allocate (almost) nothing (" .. (gcinfo() - before) .. " KB)")
end
-- L12 regression (animate.client.lua runtime, fake services): every per-player
-- connection (AgilityMove, CharacterAdded / Removing, the character's HeldItem
-- watch) is released on PlayerRemoving.
do
	local function fakePlayer(name)
		local who = {Name = name, attrs = {}, attrSignals = {}, CharacterAdded = signal(), CharacterRemoving = signal()}
		function who:GetAttribute(k) return self.attrs[k] end
		function who:SetAttribute(k, v) self.attrs[k] = v; if self.attrSignals[k] then self.attrSignals[k]:Fire() end end
		function who:GetAttributeChangedSignal(k) self.attrSignals[k] = self.attrSignals[k] or signal(); return self.attrSignals[k] end
		local c = fakeCharacter("R15")
		c.ChildAdded, c.ChildRemoved = signal(), signal()
		function c:FindFirstChildOfClass() return nil end
		who.Character = c
		return who
	end
	local me, other = fakePlayer("Me"), fakePlayer("Other")
	local function bindableEvent()
		local e = {Event = signal()}
		function e:Fire(...) self.Event:Fire(...) end
		return e
	end
	local stored = {AetherData = {Name = "AetherData"}, IsleGesture = {OnClientEvent = signal(), FireServer = function() end},
		IsleUpdate = {OnClientEvent = signal()}, IsleHeldAuto = bindableEvent(), IsleImpactLocal = bindableEvent(),
		IsleHeldAutoReply = bindableEvent(), IsleGestureLocal = bindableEvent()}
	local replicatedFake = {FindFirstChild = function(_, n) return stored[n] end, WaitForChild = function(_, n) return assert(stored[n], n) end}
	local playersFake = {LocalPlayer = me, PlayerAdded = signal(), PlayerRemoving = signal(),
		GetPlayers = function() return {me, other} end,
		GetPlayerFromCharacter = function(_, c) return if c == me.Character then me elseif c == other.Character then other else nil end}
	local stepped = signal()
	local services = {Players = playersFake, ReplicatedStorage = replicatedFake, RunService = {Stepped = stepped},
		ProximityPromptService = {PromptButtonHoldBegan = signal(), PromptButtonHoldEnded = signal(), PromptTriggered = signal()},
		Workspace = {CurrentCamera = {}, Gravity = 196.2}}
	local RCore
	luau.load(source("animate.client.lua"), {debugName = "animate.client.lua", injectGlobals = true, environment = {
		game = {GetService = function(_, n) return assert(services[n], n) end}, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3,
		Enum = roblox.Enum, Instance = {new = function() return bindableEvent() end},
		require = function() return Data end,
		task = {defer = function(f, ...) f(...) end, spawn = function(f, ...) f(...) end, delay = function() end, wait = function() end},
		__GestureRuntimeHarness = function(core) RCore = core end,
	}})()
	ok(RCore ~= nil, "runtime loaded headless")
	local function handlerCount(who)
		local n = #who.CharacterAdded.handlers + #who.CharacterRemoving.handlers + #who.Character.ChildAdded.handlers + #who.Character.ChildRemoved.handlers
		for _, s in pairs(who.attrSignals) do n += #s.handlers end
		return n
	end
	ok(handlerCount(other) >= 5, "other player watched (" .. handlerCount(other) .. " connections)")
	ok(RCore.playerConns[other] ~= nil and #RCore.playerConns[other] >= 3, "per-player connections stored")
	stepped:Fire(0, 1 / 60)
	playersFake.PlayerRemoving:Fire(other)
	eq(handlerCount(other), 0, "PlayerRemoving releases every per-player connection")
	eq(RCore.playerConns[other], nil, "no per-player connection list kept")
	ok(handlerCount(me) > 0, "the local player is still watched")
end
-- L11 regression: the camera shake adds to the existing CameraOffset and puts it back.
do
	local base = Vector3.new(0, -1.5, 0)
	local hum = {CameraOffset = base}
	local K = Core.newShake()
	K.start(hum, 0)
	K.step(0.02, function() return 0.9 end)
	ok(hum.CameraOffset ~= base and math.abs(hum.CameraOffset.Y - base.Y) < 0.2, "shakes around the existing offset")
	K.step(1, function() return 0.9 end)
	eq(hum.CameraOffset, base, "restores the previous offset")
	local other = Vector3.new(0, 2, 0)
	K.start(hum, 2)
	K.step(2.02, function() return 0.1 end)
	hum.CameraOffset = other -- another script takes the offset mid-shake
	K.step(2.04, function() return 0.1 end)
	K.step(3, function() return 0.1 end)
	eq(hum.CameraOffset, other, "another script's new offset is kept")
end

------------------------------------------------------------------------------
-- 5. hotbar.client.lua (atlas mock instances)
------------------------------------------------------------------------------
do
	local H = require("./tools/ui-harness")
	local new = H.new
	local player = new("Player", {Name = "Tester", UserId = 7})
	local playerGui = new("PlayerGui", {ChildAdded = new("BindableEvent").Event})
	playerGui.Parent = player
	local replicated = new("ReplicatedStorage")
	new("ModuleScript", {Name = "AetherData"}).Parent = replicated
	local update = new("RemoteEvent", {Name = "IsleUpdate"})
	update.Parent = replicated
	local calls = {}
	local holdGate, holdRefuse = nil, false
	local action = new("RemoteFunction", {Name = "IsleAction"})
	action.OnInvoke = function(verb, item)
		table.insert(calls, {verb, item})
		if verb == "hold" then
			if holdGate then holdGate = coroutine.running(); coroutine.yield() end
			if holdRefuse then return {held = true, ok = false, message = "One moment…", heldItem = player:GetAttribute("HeldItem") or ""} end
			local id = if item == "none" then "" else (item:gsub("^~", ""))
			player:SetAttribute("HeldAuto", item:sub(1, 1) == "~" and id ~= "")
			player:SetAttribute("HeldItem", id)
			return {held = true, ok = true, message = "ok", heldItem = id}
		end
		local slot, id = item:match("^(%d):(.*)$")
		local list = string.split(player:GetAttribute("Hotbar") or ",,,,,,", ",")
		list[tonumber(slot) - 2] = id
		player:SetAttribute("Hotbar", table.concat(list, ","))
		-- L7: success comes from the status field; the message text is deliberately unhelpful.
		return {held = true, ok = true, message = "done"}
	end
	action.Parent = replicated
	local shown = new("BindableEvent")
	local input = new("UserInputService", {TouchEnabled = false})
	local camera = new("Camera")
	local workspace = new("Workspace", {CurrentCamera = camera})
	local cas = {bound = {}}
	function cas:BindActionAtPriority(name, fn, _, priority, ...) self.bound[name] = {fn = fn, priority = priority, inputs = {...}} end
	function cas:UnbindAction(name) self.bound[name] = nil end
	local services = {Players = new("Players", {LocalPlayer = player}), ReplicatedStorage = replicated, UserInputService = input, ContextActionService = cas,
		TweenService = new("TweenService"), ProximityPromptService = new("ProximityPromptService", {PromptShown = shown.Event}), Workspace = workspace}
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local delays = {}
	local env = {game = game, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, Vector3 = Vector3,
		Color3 = Color3, ColorSequence = roblox.ColorSequence, TweenInfo = {new = function() return {} end},
		Instance = {new = function(class) return new(class) end},
		require = function(target) assert(target.Name == "AetherData"); return Data end,
		task = {spawn = function(f, ...) local co = coroutine.create(f); assert(coroutine.resume(co, ...)) end,
			delay = function(_, f, ...) table.insert(delays, table.pack(f, ...)) end, defer = function(f, ...) f(...) end,
			wait = function() return coroutine.yield() end}}
	luau.load(source("hotbar.client.lua"), {debugName = "hotbar.client.lua", environment = env, injectGlobals = true})()
	local function flush() while #delays > 0 do local d = table.remove(delays, 1); d[1](table.unpack(d, 2, d.n)) end end
	local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("IsleHotbar")
	local bar = gui:FindFirstChild("Hotbar")
	eq(bar.Visible, false, "hidden until the first snapshot")
	player:SetAttribute("Hotbar", "Ore,,,,,,")
	update.OnClientEvent:Fire({items = {Blade = 1, Pickaxe = 1, CopperHatchet = 1, Ore = 42}, depth = {equipment = {weapon = "Blade"},
		tools = {Mining = "Pickaxe", Woodcutting = "CopperHatchet"}}})
	eq(bar.Visible, true, "shown after the snapshot")
	local slots = #bar:GetChildren()
	eq(slots, 9, "nine slots")
	ok(bar:FindFirstChild("Slot1").Size.X.Offset >= 44, "touch targets >= 44 px")
	ok(player:GetAttribute("IsleHotbarHeight") >= 44 + 70, "publishes its height with the action-bar band")
	eq(bar.Position.Y.Offset, -6, "bottom-centre")
	eq(bar:FindFirstChild("Slot3"):FindFirstChild("Count").Text, "42", "stack count on a stacked item")
	local api = replicated:FindFirstChild("HotbarApi")
	local view = api.OnInvoke("getSlots")
	eq(view.slots[1], "Blade", "slot 1 = weapon")
	eq(view.slots[2], "Pickaxe", "slot 2 = context tool (default mining)")
	eq(view.slots[3], "Ore", "slot 3 from the Hotbar attribute")
	-- Keys: 2 holds the pickaxe, 3 (ore) empties the hands.
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.Two, UserInputType = roblox.Enum.UserInputType.Keyboard}, false)
	flush()
	eq(calls[#calls][1], "hold", "key sends hold"); eq(calls[#calls][2], "Pickaxe", "slot 2 holds the pickaxe")
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.Three, UserInputType = roblox.Enum.UserInputType.Keyboard}, false)
	flush()
	eq(calls[#calls][2], "none", "a non-holdable slot empties the hands")
	-- Fast scroll / key mash sends only where it settles.
	local before = #calls
	for _, key in ipairs({roblox.Enum.KeyCode.One, roblox.Enum.KeyCode.Two, roblox.Enum.KeyCode.One}) do
		input.InputBegan:Fire({KeyCode = key, UserInputType = roblox.Enum.UserInputType.Keyboard}, false)
	end
	flush()
	eq(#calls, before + 1, "debounced to one request"); eq(calls[#calls][2], "Blade", "settled on slot 1")
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.Four, UserInputType = roblox.Enum.UserInputType.Keyboard}, true)
	flush()
	eq(#calls, before + 1, "processed input (chat) ignored")
	-- Context tool follows the gather prompt in view.
	shown:Fire({GetAttribute = function(_, k) return ({IsleAction = "gather", IsleItem = "Timber"})[k] end})
	eq(api.OnInvoke("getSlots").slots[2], "CopperHatchet", "trees put the hatchet in slot 2")
	-- Auto switch from the animation layer.
	replicated:FindFirstChild("IsleHeldAuto"):Fire("Pickaxe")
	eq(calls[#calls][2], "~Pickaxe", "auto switch is a temporary hold")
	local n = #calls
	replicated:FindFirstChild("IsleHeldAuto"):Fire("Ore")
	eq(#calls, n, "auto switch ignores non-holdable ids")
	-- HotbarApi: assign / clear / select.
	local okAssign = api.OnInvoke("assign", 5, "CopperHatchet")
	ok(okAssign and api.OnInvoke("getSlots").slots[5] == "CopperHatchet", "assign through the API")
	ok(not api.OnInvoke("assign", 1, "Ore"), "API refuses fixed slots")
	ok(not api.OnInvoke("assign", 6, "NotAnItem"), "API refuses unknown items")
	ok(api.OnInvoke("assign", 5, nil) and api.OnInvoke("getSlots").slots[5] == false, "API clears a slot")
	ok(api.OnInvoke("select", 2) and api.OnInvoke("getSlots").selected == 2, "API selects")
	ok(not api.OnInvoke("select", 12), "API refuses bad slots")
	-- Picker: right-click a free slot lists owned items.
	bar:FindFirstChild("Slot4").InputBegan:Fire({UserInputType = roblox.Enum.UserInputType.MouseButton2})
	local picker = gui:FindFirstChild("HotbarPicker")
	ok(picker.Visible and #picker:FindFirstChild("List"):GetChildren() >= 5, "picker lists owned items")
	for _, row in ipairs(picker:FindFirstChild("List"):GetChildren()) do
		if row.ClassName == "TextButton" then ok(row.Size.Y.Offset >= 44, "picker rows >= 44 px") end
	end
	picker.Visible = false
	local function rim(i) return bar:FindFirstChild("Slot" .. i):FindFirstChild("Rim") end
	-- L7 regression: assign trusts the reply's status field, not its wording.
	do
		local okA, msg = api.OnInvoke("assign", 7, "Ore")
		ok(okA == true and msg == "done", "assign succeeds from ok=true whatever the message says")
		api.OnInvoke("assign", 7, nil)
	end
	-- M1 regression: re-selecting the item that is only auto-held sends the hold
	-- (else the server returns it after AUTO_RETURN and the choice reverts).
	do
		api.OnInvoke("select", 1)
		flush()
		player:SetAttribute("HeldItem", "CopperHatchet")
		player:SetAttribute("HeldAuto", true)
		local before = #calls
		api.OnInvoke("select", 2)
		flush()
		eq(#calls, before + 1, "choosing the auto-held item is sent")
		eq(calls[#calls][2], "CopperHatchet", "as an explicit hold")
		eq(player:GetAttribute("HeldAuto"), false, "now explicit")
		api.OnInvoke("select", 2)
		flush()
		eq(#calls, before + 1, "re-selecting an explicit hold sends nothing")
	end
	-- L8 regression: the mint ring marks a real auto hold only.
	do
		api.OnInvoke("select", 1)
		flush()
		player:SetAttribute("HeldItem", "CopperHatchet")
		player:SetAttribute("HeldAuto", false)
		ok(rim(2).Color ~= Color3.fromRGB(0x7F, 0xE3, 0xCC), "explicitly held, not selected: no mint ring")
		player:SetAttribute("HeldAuto", true)
		eq(rim(2).Color, Color3.fromRGB(0x7F, 0xE3, 0xCC), "auto-held: mint ring")
		player:SetAttribute("HeldAuto", false)
	end
	-- L3 regression: auto requests that arrive while one is in flight are queued
	-- (latest wins), and every settled request is answered on IsleHeldAutoReply.
	do
		local replies = {}
		replicated:FindFirstChild("IsleHeldAutoReply").Event:Connect(function(id, heldItem) table.insert(replies, {id, heldItem}) end)
		player:SetAttribute("HeldItem", "")
		local before = #calls
		holdGate = true
		replicated:FindFirstChild("IsleHeldAuto"):Fire("Pickaxe")
		local waiting = holdGate
		ok(type(waiting) == "thread", "first auto request in flight")
		replicated:FindFirstChild("IsleHeldAuto"):Fire("CopperHatchet")
		replicated:FindFirstChild("IsleHeldAuto"):Fire("Blade")
		holdGate = nil
		coroutine.resume(waiting)
		eq(#calls, before + 2, "in-flight request + only the latest queued one")
		eq(calls[before + 1][2], "~Pickaxe", "first request")
		eq(calls[before + 2][2], "~Blade", "latest queued request sent, the stale one dropped")
		eq(player:GetAttribute("HeldItem"), "Blade", "queued switch applied")
		holdRefuse = true
		replicated:FindFirstChild("IsleHeldAuto"):Fire("Pickaxe")
		holdRefuse = false
		local last = replies[#replies]
		ok(last[1] == "Pickaxe" and last[2] == "Blade", "a refused request reports what is really held")
	end
	-- L5 regression: hovering the bar binds a high-priority wheel action that sinks
	-- the wheel (no camera zoom); leaving releases it.
	do
		eq(bar.Active, true, "bar is Active")
		bar.MouseEnter:Fire()
		local binding = cas.bound.IsleHotbarWheel
		ok(binding ~= nil and binding.inputs[1] == roblox.Enum.UserInputType.MouseWheel, "wheel bound while hovering")
		local from = api.OnInvoke("getSlots").selected
		local result = binding.fn("IsleHotbarWheel", roblox.Enum.UserInputState.Change,
			{UserInputType = roblox.Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, -1)})
		flush()
		eq(result, roblox.Enum.ContextActionResult.Sink, "the wheel is sunk")
		eq(api.OnInvoke("getSlots").selected, from % 9 + 1, "the wheel moves the selection")
		bar.MouseLeave:Fire()
		eq(cas.bound.IsleHotbarWheel, nil, "unbound after leaving the bar")
	end
	-- L6 regression: the release ending a long-press does not also select the slot.
	do
		api.OnInvoke("select", 1)
		flush()
		local before = #calls
		local slot4 = bar:FindFirstChild("Slot4")
		slot4.InputBegan:Fire({UserInputType = roblox.Enum.UserInputType.Touch})
		flush()
		ok(picker.Visible, "long-press opens the picker")
		slot4.Activated:Fire()
		flush()
		eq(api.OnInvoke("getSlots").selected, 1, "long-press release does not select")
		eq(#calls, before, "and sends nothing")
		slot4.Activated:Fire()
		flush()
		eq(api.OnInvoke("getSlots").selected, 4, "a later tap selects as usual")
		picker.Visible = false
	end
	-- L9 regression: the bar follows the dialogue box's Visible property (no poll).
	do
		ok(not source("hotbar.client.lua"):find("task.wait(0.5)", 1, true), "no dialogue poll")
		local folk = new("ScreenGui", {Name = "TownsfolkDialogue", ChildAdded = new("BindableEvent").Event})
		local box = new("Frame", {Name = "Dialogue", Visible = false})
		box.Parent = folk
		folk.Parent = playerGui
		playerGui.ChildAdded:Fire(folk)
		eq(bar.Visible, true, "dialogue closed: bar shown")
		box.Visible = true
		eq(bar.Visible, false, "dialogue opened: bar hidden at once")
		box.Visible = false
		eq(bar.Visible, true, "dialogue closed again: bar back")
	end
	-- L4 regression: narrow phones keep the bar clear of the touch Attack button
	-- (x >= W - 196) with slots >= 44 px: one row at 667 x 375, two rows at 568.
	do
		local function edges()
			local w = bar.Size.X.Offset
			local cx = bar.Position.X.Scale * camera.ViewportSize.X + bar.Position.X.Offset
			return cx - w / 2, cx + w / 2
		end
		for _, case in ipairs({{667, 375, 1}, {568, 320, 2}}) do
			camera.ViewportSize = roblox.Vector2.new(case[1], case[2])
			local left, right = edges()
			local size = bar:FindFirstChild("Slot1").Size.X.Offset
			ok(right <= case[1] - 196 + 0.01, case[1] .. " px: bar ends left of the Attack button (" .. right .. ")")
			ok(left >= 8 - 0.01, case[1] .. " px: bar stays on screen (" .. left .. ")")
			ok(size >= 44, case[1] .. " px: touch targets >= 44 px (" .. size .. ")")
			local rows = if bar:FindFirstChild("Slot9").Position.Y.Offset > 0 then 2 else 1
			eq(rows, case[3], case[1] .. " px rows")
			for i = 1, 9 do
				local b = bar:FindFirstChild("Slot" .. i)
				ok(b.Position.X.Offset + size <= bar.Size.X.Offset + 0.01 and b.Position.Y.Offset + size <= bar.Size.Y.Offset + 0.01, case[1] .. " px slot " .. i .. " inside the bar")
			end
			eq(player:GetAttribute("IsleHotbarHeight"), 6 + bar.Size.Y.Offset + 70, case[1] .. " px published height covers every row")
		end
		camera.ViewportSize = roblox.Vector2.new(1366, 768)
		eq(bar.Position.X.Scale, 0.5, "wide screens: centred again")
	end
	-- Building hides the bar and releases its height.
	player:SetAttribute("IslandBuilding", true)
	eq(bar.Visible, false, "hidden while building")
	eq(player:GetAttribute("IsleHotbarHeight"), 0, "height released")
end

------------------------------------------------------------------------------
-- 6. Packaging
------------------------------------------------------------------------------
local project = fs.readFile("default.project.json")
ok(project:find('"Hotbar": { "$path": "hotbar.client.lua" }', 1, true), "Hotbar registered")
ok(project:find('"HeldItems": { "$path": "held.server.lua" }', 1, true), "HeldItems registered")
ok(fs.readFile("scripts/build.sh"):find("verify-held.luau", 1, true) and fs.readFile("build.ps1"):find("verify-held.luau", 1, true), "build scripts run this suite")
local verify = fs.readFile("verify.luau")
ok(verify:find('Hotbar = "hotbar.client.lua"', 1, true) and verify:find('HeldItems = "held.server.lua"', 1, true), "verify.luau binds both scripts")
ok(fs.readFile("docs/DEPTH-CONTRACT.md"):find("## 26. Held items", 1, true), "contract §26")
-- L13 regression: combat.client.lua no longer documents the old 1-6 spell keys.
ok(not fs.readFile("combat.client.lua"):find("keys 1-6", 1, true), "combat spell-bar comment names Z X C V B N, not 1-6")

print("verify-held: " .. checks .. " checks passed")
print("SUITE-END verify-held.luau")
